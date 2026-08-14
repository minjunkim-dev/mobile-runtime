import Foundation

/// The React Native version the Tier 2 matrix is looked up with, and the evidence it
/// stands on. ADR-0003's chain, strongest first:
///
/// `node_modules` measurement → lockfile → exact pin → nothing.
///
/// The chain exists because the North Star is `git clone → mobile up`, and a clone has
/// no `node_modules`. A lockfile is committed and holds a resolved version, and a
/// dependency written as a single version is not a range — neither of them breaks the
/// rule that a declared *range* is not a measurement.
public struct ReactNativeVersion: Sendable, Equatable {
    public let value: String
    /// How a verdict names the evidence — `node_modules/react-native`, a lockfile
    /// name, or the manifest field. The source string is the only record of what a
    /// judgement believed, so every link in the chain has to be able to say its name.
    public let origin: String
    /// A weaker piece of evidence that answers differently. The stronger one still
    /// wins; the conflict rides into `-v` rather than being swallowed, the same
    /// discipline `mobile.yml` overrides follow.
    public let disagreement: String?

    public init(value: String, origin: String, disagreement: String? = nil) {
        self.value = value
        self.origin = origin
        self.disagreement = disagreement
    }

    /// How a verdict spells the whole chain: the version, what said so, and whatever
    /// disagreed with it.
    public var described: String {
        "\(value) from \(origin)" + (disagreement.map { ", but \($0)" } ?? "")
    }

    /// The npm package, which is a different thing from the matrix's framework key
    /// even where the two happen to be spelled alike.
    static let packageName = "react-native"
    static let measuredOrigin = "node_modules/\(packageName)"
    static let declarationOrigin = DeclarationOrigin.anchor("dependencies.react-native")

    /// Walks the chain. Returns nil when no link answers — a range in `package.json`
    /// and nothing installed or locked is genuinely unmeasurable, and `unknown` is the
    /// honest verdict there.
    static func resolve(
        anchorDirectory: String,
        declared: String,
        installed: String?,
        workspaceRoot: WorkspaceRoot?,
        fileManager: FileManager
    ) -> ReactNativeVersion? {
        let locked = workspaceRoot.flatMap {
            lockedVersion(
                root: $0, anchorDirectory: anchorDirectory, declared: declared, fileManager: fileManager
            )
        }

        if let installed {
            let disagreement = locked.flatMap { locked in
                locked.version == installed ? nil : "\(locked.lockfile) resolves \(locked.version)"
            }
            return ReactNativeVersion(
                value: installed, origin: measuredOrigin, disagreement: disagreement
            )
        }
        if let locked {
            return ReactNativeVersion(value: locked.version, origin: locked.lockfile)
        }
        guard isExactPin(declared) else { return nil }
        return ReactNativeVersion(value: declared, origin: declarationOrigin)
    }

    /// A single version, not a range: `0.81.6` pins, `^0.81.0` and `0.81` do not.
    /// Anything short of all three components leaves a minor or patch free, and the
    /// matrix rows differ by minor.
    private static func isExactPin(_ declared: String) -> Bool {
        VersionComponents(declared)?.values.count == 3
    }

    /// Only the two lockfiles ADR-0003 reads. pnpm and bun locks fall through to the
    /// next link rather than becoming a miss.
    private static func lockedVersion(
        root: WorkspaceRoot, anchorDirectory: String, declared: String, fileManager: FileManager
    ) -> (version: String, lockfile: String)? {
        guard
            let data = fileManager.contents(
                atPath: root.directory.path.appending("/\(root.lockfile)")
            )
        else { return nil }

        let version: String? =
            switch root.lockfile {
            case "package-lock.json":
                npmLockVersion(data, anchorPath: relativePath(of: anchorDirectory, under: root.directory.path))
            case "yarn.lock":
                yarnBerryVersion(String(decoding: data, as: UTF8.self), declared: declared)
            default:
                nil
            }
        return version.map { ($0, root.lockfile) }
    }

    private static func relativePath(of anchorDirectory: String, under root: String) -> String {
        guard anchorDirectory.hasPrefix(root.appending("/")) else { return "" }
        return String(anchorDirectory.dropFirst(root.count + 1))
    }

    /// lockfileVersion 2 and 3 both carry the flat `packages` map keyed by install
    /// path. Version 1 has none and answers nothing, which is the point of a chain.
    ///
    /// npm hoists to the workspace root, but a version conflict leaves a copy beside
    /// the package that asked for it — and that copy, not the hoisted one, is what
    /// this anchor builds against.
    private static func npmLockVersion(_ data: Data, anchorPath: String) -> String? {
        guard let lock = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let packages = lock["packages"] as? [String: Any]
        else { return nil }

        let hoisted = "node_modules/\(packageName)"
        let nested = anchorPath.isEmpty ? nil : "\(anchorPath)/\(hoisted)"
        return [nested, hoisted].compactMap { $0 }
            .lazy
            .compactMap { (packages[$0] as? [String: Any])?["version"] as? String }
            .first
    }

    /// yarn berry keys an entry by the descriptors that resolve to it
    /// (`"react-native@npm:0.81.6":`), several to a line when they share a resolution.
    /// A `yarn.lock` can hold more than one react-native — joplin holds 0.81.6 and
    /// 0.70.6 — so the anchor's own declared range is what picks the entry. Taking the
    /// first match instead would answer confidently and wrongly.
    ///
    /// Yarn classic writes neither the `npm:` protocol nor `version:`, so it fails to
    /// match and the chain moves on.
    private static func yarnBerryVersion(_ text: String, declared: String) -> String? {
        let descriptor = "\(packageName)@npm:\(declared)"
        var inEntry = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.hasPrefix(" ") else {
                inEntry = line.hasSuffix(":") && descriptors(in: line.dropLast()).contains(descriptor)
                continue
            }
            let field = line.trimmingCharacters(in: .whitespaces)
            guard inEntry, field.hasPrefix("version:") else { continue }
            return field.dropFirst("version:".count)
                .trimmingCharacters(in: CharacterSet(charactersIn: " \""))
        }
        return nil
    }

    private static func descriptors(in key: Substring) -> [String] {
        key.split(separator: ",").map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: " \""))
        }
    }
}

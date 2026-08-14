import Foundation

/// A Node version pinned by team convention (`.nvmrc`, `.node-version`). Breaking
/// a pin is a warning; `engines` is the contract that errors.
public struct NodePin: Sendable, Equatable {
    public let value: String
    public let file: String

    public init(value: String, file: String) {
        self.value = value
        self.file = file
    }
}

/// The `packageManager` field, split into the two halves that get compared. The
/// corepack hash suffix is dropped — it is integrity data, not a version.
public struct PackageManagerRequirement: Sendable, Equatable {
    public let name: String
    public let version: String

    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }
}

/// A `Gemfile.lock` next to the anchor. Its existence is what makes the CocoaPods
/// Check exist at all; `cocoapodsVersion` is nil when the lock pins no CocoaPods —
/// a different thing from having no lock, and the two lead to different verdicts.
public struct GemfileLock: Sendable, Equatable {
    public let cocoapodsVersion: String?

    public init(cocoapodsVersion: String?) {
        self.cocoapodsVersion = cocoapodsVersion
    }
}

/// The project's anchor: the nearest `package.json` that depends on react-native,
/// plus the Tier 1 declarations sitting next to it. Detection happens once and
/// everything project-scoped — the checks here, `mobile.yml` later — reads the
/// same anchor. There is exactly one detection rule in this project.
public struct ProjectAnchor: Sendable, Equatable {
    /// The directory holding the anchoring `package.json`.
    public let directory: URL
    /// From `dependencies.react-native` — a declared range, not a measurement.
    public let declaredReactNativeVersion: String
    /// From `node_modules/react-native/package.json` — what is really installed.
    /// nil when dependencies are not installed, which is what makes the Tier 2
    /// checks `unknown` rather than wrong.
    public let installedReactNativeVersion: String?
    public let hasIOSDirectory: Bool
    public let hasNodeModules: Bool
    public let nodePin: NodePin?
    public let nodeEngines: String?
    public let packageManager: PackageManagerRequirement?
    /// nil when the project manages no gems — then there is no CocoaPods Check.
    public let gemfileLock: GemfileLock?
    /// From `.ruby-version`. nil means no Ruby Check — absence, not `unknown`.
    public let rubyPin: String?
    /// From `.xcode-version`, the file xcodes and fastlane already read. Tier 1
    /// evidence for a requirement the matrix only knows a framework floor for;
    /// nil is silence, not a missing answer.
    public let declaredXcodeVersion: String?

    /// What a human would run to install the project's dependencies. doctor prints
    /// it and never runs it.
    public var installCommand: String {
        "\(packageManager?.name ?? "npm") install"
    }

    /// The Project checks this anchor can answer. A Check that needs a declaration
    /// to compare against is absent when the declaration is — a project that never
    /// pinned Ruby gets no Ruby line at all, rather than a permanent `unknown`.
    public func checks(runner: any ProcessRunner) -> [any Check] {
        var checks: [any Check] = [
            ProjectDetectedCheck(anchor: self),
            NodeVersionCheck(anchor: self, runner: runner),
        ]
        if let packageManager {
            checks.append(PackageManagerVersionCheck(requirement: packageManager, runner: runner))
        }
        if let gemfileLock {
            checks.append(CocoaPodsVersionCheck(lockedVersion: gemfileLock.cocoapodsVersion, runner: runner))
        }
        if let rubyPin {
            checks.append(RubyVersionCheck(pin: rubyPin, runner: runner))
        }
        return checks
    }

    /// Walks up from `directory` looking for the anchor, stopping at the git root
    /// (or the filesystem root). The nearest react-native `package.json` wins, so a
    /// monorepo naturally judges the app you are standing in.
    ///
    /// - Returns: nil when there is no React Native project above the starting
    ///   point. That is not an error — it means host checks only.
    public static func detect(from directory: URL, fileManager: FileManager = .default) -> ProjectAnchor? {
        var current = directory.resolvingSymlinksInPath().path
        while true {
            if let anchor = read(at: current, fileManager: fileManager) { return anchor }
            // Above the git root is somebody else's project.
            if fileManager.fileExists(atPath: current.appending("/.git")) { return nil }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current || parent.isEmpty { return nil }
            current = parent
        }
    }

    private static let pinFiles = [".nvmrc", ".node-version"]

    private static func read(at directory: String, fileManager: FileManager) -> ProjectAnchor? {
        guard let data = fileManager.contents(atPath: directory.appending("/package.json")),
            let manifest = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let declared = (manifest["dependencies"] as? [String: Any])?["react-native"] as? String
        else { return nil }

        return ProjectAnchor(
            directory: URL(fileURLWithPath: directory),
            declaredReactNativeVersion: declared,
            installedReactNativeVersion: installedReactNative(in: directory, fileManager: fileManager),
            hasIOSDirectory: isDirectory(directory.appending("/ios"), fileManager),
            hasNodeModules: isDirectory(directory.appending("/node_modules"), fileManager),
            nodePin: pin(in: directory, fileManager: fileManager),
            nodeEngines: (manifest["engines"] as? [String: Any])?["node"] as? String,
            packageManager: (manifest["packageManager"] as? String).flatMap(packageManager),
            gemfileLock: gemfileLock(in: directory, fileManager: fileManager),
            rubyPin: rubyPin(in: directory, fileManager: fileManager),
            declaredXcodeVersion: declaration(
                at: directory.appending("/\(xcodeVersionFile)"), fileManager: fileManager
            )
        )
    }

    /// Named here because the origin string in a verdict has to quote it back.
    public static let xcodeVersionFile = ".xcode-version"

    /// A one-line declaration file — `.nvmrc`, `.ruby-version`, `.xcode-version`.
    /// A blank file declares nothing, the same as no file at all.
    private static func declaration(at path: String, fileManager: FileManager) -> String? {
        guard let data = fileManager.contents(atPath: path) else { return nil }
        let value = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static let lockedCocoaPodsPrefix = "    cocoapods ("

    /// Reads the CocoaPods version out of the `specs:` section, not the
    /// `DEPENDENCIES` one: both name cocoapods, and the four-space indent is what
    /// tells the locked version apart from the range the Gemfile asked for.
    /// `cocoapods-core` fails the prefix, as it should.
    private static func gemfileLock(in directory: String, fileManager: FileManager) -> GemfileLock? {
        guard let data = fileManager.contents(atPath: directory.appending("/Gemfile.lock")) else { return nil }
        let line = String(decoding: data, as: UTF8.self).split(separator: "\n").first {
            $0.hasPrefix(lockedCocoaPodsPrefix) && $0.hasSuffix(")")
        }
        return GemfileLock(
            cocoapodsVersion: line.map { String($0.dropFirst(lockedCocoaPodsPrefix.count).dropLast()) }
        )
    }

    /// RVM writes `ruby-3.2.2` where rbenv writes `3.2.2` — the prefix is the version
    /// manager's, not part of the version.
    private static func rubyPin(in directory: String, fileManager: FileManager) -> String? {
        guard let value = declaration(at: directory.appending("/.ruby-version"), fileManager: fileManager)
        else { return nil }
        return value.hasPrefix("ruby-") ? String(value.dropFirst(5)) : value
    }

    private static func installedReactNative(in directory: String, fileManager: FileManager) -> String? {
        guard
            let data = fileManager.contents(
                atPath: directory.appending("/node_modules/react-native/package.json")
            ),
            let manifest = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        return manifest["version"] as? String
    }

    private static func pin(in directory: String, fileManager: FileManager) -> NodePin? {
        for file in pinFiles {
            guard let value = declaration(at: directory.appending("/\(file)"), fileManager: fileManager)
            else { continue }
            return NodePin(value: value, file: file)
        }
        return nil
    }

    /// `yarn@3.6.4+sha224.…` → yarn 3.6.4.
    private static func packageManager(_ field: String) -> PackageManagerRequirement? {
        let parts = field.split(separator: "@", maxSplits: 1)
        guard parts.count == 2, !parts[0].isEmpty else { return nil }
        let version = parts[1].split(separator: "+", maxSplits: 1)[0]
        guard !version.isEmpty else { return nil }
        return PackageManagerRequirement(name: String(parts[0]), version: String(version))
    }

    private static func isDirectory(_ path: String, _ fileManager: FileManager) -> Bool {
        var directory: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
    }
}

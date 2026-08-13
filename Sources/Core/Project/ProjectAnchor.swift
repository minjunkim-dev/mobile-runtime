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

    /// What a human would run to install the project's dependencies. doctor prints
    /// it and never runs it.
    public var installCommand: String {
        "\(packageManager?.name ?? "npm") install"
    }

    /// The Project checks this anchor can answer. `package-manager.version` needs a
    /// declaration to compare against, so an undeclared package manager produces no
    /// Check rather than a permanent `unknown`; the other two always apply.
    public func checks(runner: any ProcessRunner) -> [any Check] {
        var checks: [any Check] = [
            ProjectDetectedCheck(anchor: self),
            NodeVersionCheck(anchor: self, runner: runner),
        ]
        if let packageManager {
            checks.append(PackageManagerVersionCheck(requirement: packageManager, runner: runner))
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
            packageManager: (manifest["packageManager"] as? String).flatMap(packageManager)
        )
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
            guard let data = fileManager.contents(atPath: directory.appending("/\(file)")) else { continue }
            let value = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
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

import Foundation
import Yams

public enum ProjectPlatform: String, Codable, Sendable {
    case ios, android
}

public struct FolderIdentity: Codable, Sendable, Equatable, Hashable {
    public let path: String
    public let volume: UInt64
    public let file: UInt64

    public init(directory: URL) throws {
        let resolved = directory.standardizedFileURL.resolvingSymlinksInPath()
        let attributes = try FileManager.default.attributesOfItem(atPath: resolved.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
            let volume = attributes[.systemNumber] as? NSNumber,
            let file = attributes[.systemFileNumber] as? NSNumber
        else { throw CocoaError(.fileReadInvalidFileName) }
        self.path = resolved.path
        self.volume = volume.uint64Value
        self.file = file.uint64Value
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.volume == rhs.volume && lhs.file == rhs.file
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(volume)
        hasher.combine(file)
    }
}

public struct ProjectCandidate: Codable, Sendable, Equatable {
    public let id: String
    public let app: FolderIdentity
    public let workspace: FolderIdentity?
    public let platforms: [ProjectPlatform]
}

public struct ProjectSelection: Codable, Sendable {
    public let directory: FolderIdentity
    public let candidates: [ProjectCandidate]
    public let selected: ProjectCandidate?
    public let platform: ProjectPlatform?
    public let requiredInput: [String]
    public let error: String?

    public init(directory: FolderIdentity, candidates: [ProjectCandidate], selected: ProjectCandidate?,
                platform: ProjectPlatform?, requiredInput: [String], error: String?) {
        self.directory = directory
        self.candidates = candidates
        self.selected = selected
        self.platform = platform
        self.requiredInput = requiredInput
        self.error = error
    }

    public var state: String {
        error != nil ? "failed" : requiredInput.isEmpty ? "succeeded" : "needs-selection"
    }
}

/// An inspection never changes cwd or exports the supplied environment in its result.
public struct ProjectInspectionInput: Sendable {
    public let directory: URL
    public let environment: [String: String]
    public let app: String?
    public let platform: ProjectPlatform?

    public init(directory: URL, environment: [String: String], app: String? = nil, platform: ProjectPlatform? = nil) {
        self.directory = directory
        self.environment = environment
        self.app = app
        self.platform = platform
    }

    public func selection() throws -> ProjectSelection {
        let identity = try FolderIdentity(directory: directory)
        let root = URL(fileURLWithPath: identity.path)
        var anchors: [ProjectAnchor] = []
        if let nearest = ProjectAnchor.detect(from: root) { anchors.append(nearest) }
        let manifestURL = root.appendingPathComponent("package.json")
        let manifest = (try? Data(contentsOf: manifestURL)).flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        var patterns = manifest?["workspaces"] as? [String]
            ?? (manifest?["workspaces"] as? [String: Any])?["packages"] as? [String] ?? []
        let pnpm = root.appendingPathComponent("pnpm-workspace.yaml")
        if let text = try? String(contentsOf: pnpm, encoding: .utf8),
            let yaml = try Yams.load(yaml: text) as? [String: Any],
            let packages = yaml["packages"] as? [String] {
            patterns += packages
        }
        if !patterns.isEmpty {
            // Only declared workspace members are candidates; dependency and native host trees are excluded.
            let ignored: Set<String> = ["node_modules", "Pods", "build", ".git", "ios", "android"]
            var readFailure: (any Error)?
            guard let files = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles],
                errorHandler: { _, error in readFailure = error; return false }
            ) else { throw CocoaError(.fileReadNoPermission) }
            for case let url as URL in files {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values.isSymbolicLink == true || ignored.contains(url.lastPathComponent) {
                    files.skipDescendants()
                    continue
                }
                guard url.lastPathComponent == "package.json" else { continue }
                let folder = url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
                let relative = String(folder.path.dropFirst(root.path.count + 1))
                let included = patterns.filter { !$0.hasPrefix("!") }.contains { matches(relative, $0) }
                let excluded = patterns.filter { $0.hasPrefix("!") }.contains { matches(relative, String($0.dropFirst())) }
                guard included, !excluded, let anchor = ProjectAnchor.detect(from: folder),
                    anchor.directory.standardizedFileURL.resolvingSymlinksInPath().path == folder.path else { continue }
                anchors.append(anchor)
            }
            if let readFailure { throw readFailure }
        }
        var seen = Set<FolderIdentity>()
        var candidates: [ProjectCandidate] = []
        for anchor in anchors {
            let appIdentity = try FolderIdentity(directory: anchor.directory)
            guard seen.insert(appIdentity).inserted else { continue }
            let path = appIdentity.path
            let id = path == root.path ? "." : path.hasPrefix(root.path + "/")
                ? String(path.dropFirst(root.path.count + 1)) : path
            candidates.append(ProjectCandidate(
                id: id, app: appIdentity,
                workspace: try anchor.workspaceRoot.map { try FolderIdentity(directory: $0.directory) }
                    ?? (!patterns.isEmpty && path.hasPrefix(root.path + "/") ? identity : nil),
                platforms: (anchor.hasIOSDirectory ? [.ios] : []) + (anchor.hasAndroidDirectory ? [.android] : [])
            ))
        }
        candidates.sort { $0.id < $1.id }
        let chosen = app.flatMap { id in candidates.first { $0.id == id } }
            ?? (app == nil && candidates.count == 1 ? candidates.first : nil)
        var error: String?
        var required: [String] = []
        if app != nil && chosen == nil { error = "Invalid --app. Choose a reported candidate id." }
        if chosen == nil && candidates.count > 1 && error == nil { required.append("--app") }
        var effectivePlatform = platform
        if let chosen {
            if let platform, !chosen.platforms.isEmpty, !chosen.platforms.contains(platform) {
                error = "The selected app has no \(platform.rawValue) host directory."
            } else if platform == nil {
                if chosen.platforms.count == 1 { effectivePlatform = chosen.platforms[0] }
                else if chosen.platforms.count > 1 { required.append("--platform") }
                else { required.append("--platform") }
            }
        }
        return ProjectSelection(directory: identity, candidates: candidates, selected: chosen,
                                platform: effectivePlatform, requiredInput: required, error: error)
    }

    private func matches(_ path: String, _ pattern: String) -> Bool {
        let expression = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*\\*", with: ".*")
            .replacingOccurrences(of: "\\*", with: "[^/]*")
        return path.range(of: "^" + expression + "$", options: .regularExpression) != nil
    }
}

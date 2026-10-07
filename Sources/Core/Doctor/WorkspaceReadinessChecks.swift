import Foundation

/// File-system access is observed without creating files or changing permissions.
public struct WorkspaceAccessCheck: Check {
    public let id = "host.workspace-access"
    public let category = "Workspace"
    public let title = "Working and cache directories are accessible"
    let paths: [URL]
    let unresolvedCache: String?

    public init(paths: [URL], unresolvedCache: String? = nil) {
        self.paths = paths
        self.unresolvedCache = unresolvedCache
    }

    public func run() async throws -> CheckOutcome {
        let manager = FileManager.default
        for path in paths {
            let directory = Self.existingDirectory(for: path)
            do {
                _ = try manager.contentsOfDirectory(atPath: directory.path)
            } catch {
                return Self.denied(path, observed: error.localizedDescription)
            }
            guard manager.isReadableFile(atPath: directory.path),
                manager.isWritableFile(atPath: directory.path),
                manager.isExecutableFile(atPath: directory.path)
            else { return Self.denied(path, observed: "cannot read, write, or search \(directory.path)") }
        }
        if let unresolvedCache { return .unknown(reason: unresolvedCache) }
        return .pass(observed: "\(paths.count) working/cache locations accessible (no write probe)")
    }

    static func existingDirectory(for path: URL) -> URL {
        var current = path.standardizedFileURL
        while !FileManager.default.fileExists(atPath: current.path), current.path != "/" {
            current.deleteLastPathComponent()
        }
        return current
    }

    private static func denied(_ path: URL, observed: String) -> CheckOutcome {
        .error(
            observed: "\(path.path): \(observed)", required: "accessible working and cache directories",
            remediation: Remediation(
                summary: "Use a directory your user can read and write. If macOS denied folder access, allow this terminal in System Settings > Privacy & Security > Files & Folders. Then run mobile doctor again.",
                url: "https://support.apple.com/guide/mac-help/mchld5a35146/mac"
            )
        )
    }
}

public struct WorkspaceStorageCheck: Check {
    public let id = "host.storage"
    public let category = "Workspace"
    public let title = "Working and cache volumes have free storage"
    public let dependsOn = ["host.workspace-access"]
    let paths: [URL]
    // ponytail: a preparation warning, not a project size model; revisit after measured build requirements exist.
    static let recommendedBytes: Int64 = 10 * 1024 * 1024 * 1024

    public init(paths: [URL]) { self.paths = paths }

    public func run() async throws -> CheckOutcome {
        var available: [(path: URL, bytes: Int64)] = []
        for path in paths {
            do {
                let values = try FileManager.default.attributesOfFileSystem(
                    forPath: WorkspaceAccessCheck.existingDirectory(for: path).path
                )
                guard let bytes = values[.systemFreeSize] as? NSNumber else {
                    return .unknown(reason: "free storage could not be measured for \(path.path)")
                }
                available.append((path, bytes.int64Value))
            } catch {
                return .unknown(reason: "free storage could not be measured for \(path.path): \(error.localizedDescription)")
            }
        }
        guard let minimum = available.min(by: { $0.bytes < $1.bytes }) else { return .unknown(reason: "no working/cache paths to measure") }
        return Self.outcome(availableBytes: minimum.bytes, path: minimum.path)
    }

    static func outcome(availableBytes: Int64, path: URL? = nil) -> CheckOutcome {
        let observed = "least free storage\(path.map { " at \($0.path)" } ?? ""): \(ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .file))"
        if availableBytes < recommendedBytes {
            return .warning(
                observed: observed, required: "10 GiB free recommended; actual project requirements vary",
                remediation: Remediation(summary: "Free storage on the working/cache volume before a large install or build. mobile does not delete files for you.")
            )
        }
        return .pass(observed: observed, required: "10 GiB preparation recommendation; not a build guarantee")
    }
}

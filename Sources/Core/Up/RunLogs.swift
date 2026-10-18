import Foundation

/// Where a Stage's full output goes when a tail is not enough. Under the system
/// temporary directory rather than the repo: a tool that writes into someone's
/// project earns itself a `.gitignore` entry, and mobile keeps no state of its own.
///
/// The path is always printed with the failure that produced it — a log nobody can
/// find is not a log.
public struct RunLogs: Sendable {
    /// `<temp>/mobile/<project name>-<digest of its path>`. The name is there so a
    /// human scanning the directory recognises their project. The legacy digest
    /// reduces log name collisions; it is not the real input folder's identity.
    public let directory: URL
    private let project: URL

    public init(project: URL, temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        // Resolved for both halves: a project reached through a symlink and through
        // its real path is one project, and must not get two log directories.
        let resolved = project.resolvingSymlinksInPath()
        self.project = resolved
        directory = temporaryDirectory
            .appendingPathComponent("mobile")
            .appendingPathComponent("\(resolved.lastPathComponent)-\(Self.digest(resolved.path))")
    }

    /// Where a log by this name goes, without creating anything. For output something
    /// else writes — a `ProcessCommand` streamed straight to its file.
    public func url(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    /// One Xcode output tree per real input folder, shared by build and its queries.
    /// Inspect existing components without creating them or following a redirect.
    public var derivedDataDirectory: URL {
        get throws {
            let identity = try FolderIdentity(directory: project)
            let root = directory.deletingLastPathComponent().deletingLastPathComponent()
                .resolvingSymlinksInPath().standardizedFileURL
            let parent = root.appendingPathComponent("mobile")
            let input = parent.appendingPathComponent(directory.lastPathComponent)
            // The readable legacy log digest can collide. Reuse the folder lease's
            // volume/inode identity for Xcode output without moving logs or records.
            let folder = input.appendingPathComponent("folder-\(identity.volume)-\(identity.file)")
            let output = folder.appendingPathComponent("DerivedData")
            let manager = FileManager.default
            for component in [root, parent, input, folder, output] {
                do {
                    let attributes = try manager.attributesOfItem(atPath: component.path)
                    guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                        throw DomainError(summary: "The input's Xcode output path is redirected or is not a directory.",
                            remediation: Remediation(summary: "Inspect \(component.path). Existing content was preserved."))
                    }
                } catch let error as CocoaError where error.code == .fileReadNoSuchFile && component != root {
                    // Xcode creates absent children. A dangling symlink has its own
                    // attributes and is rejected by the directory check above.
                    continue
                }
            }
            return output
        }
    }

    /// - Returns: the file written, or nil when it could not be. A log that failed to
    ///   save must not become the failure the caller reports — it had one already.
    public func write(_ contents: String, to name: String) -> URL? {
        let file = url(name)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: file)
            return file
        } catch {
            return nil
        }
    }

    /// FNV-1a. Swift's `Hasher` is seeded per process, and a path that hashes
    /// differently on every run would put each `up` in a directory of its own.
    private static func digest(_ path: String) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in path.utf8 {
            hash ^= UInt32(byte)
            hash &*= 16_777_619
        }
        return String(format: "%08x", hash)
    }
}

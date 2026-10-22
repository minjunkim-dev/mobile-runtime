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
    let project: URL

    public init(project: URL, temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        // Resolved for both halves: a project reached through a symlink and through
        // its real path is one project, and must not get two log directories.
        let resolved = project.resolvingSymlinksInPath()
        self.project = resolved
        directory = temporaryDirectory
            .appendingPathComponent("mobile")
            .appendingPathComponent("\(resolved.lastPathComponent)-\(Self.digest(resolved.path))")
    }

    /// The legacy path remains available for ownership-checked reads. New writes
    /// use the same real folder identity as leases, even if the log digest collides.
    public func url(_ name: String) throws -> URL {
        try guardedURL(name, type: .typeRegular)
    }

    public var derivedDataDirectory: URL {
        get throws { try guardedURL("DerivedData", type: .typeDirectory) }
    }

    private var folderDirectory: URL {
        get throws {
            let identity = try FolderIdentity(directory: project)
            let root = directory.deletingLastPathComponent().deletingLastPathComponent()
                .resolvingSymlinksInPath().standardizedFileURL
            let parent = root.appendingPathComponent("mobile")
            let input = parent.appendingPathComponent(directory.lastPathComponent)
            let folder = input.appendingPathComponent("folder-\(identity.volume)-\(identity.file)")
            for component in [root, parent, input, folder] {
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: component.path)
                    guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw redirected(component) }
                } catch let error as CocoaError where error.code == .fileReadNoSuchFile && component != root {
                    continue
                }
            }
            return folder
        }
    }

    private func guardedURL(_ name: String, type: FileAttributeType) throws -> URL {
        guard !name.isEmpty, name != ".", name != "..", URL(fileURLWithPath: name).lastPathComponent == name else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        let file = try folderDirectory.appendingPathComponent(name)
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            guard attributes[.type] as? FileAttributeType == type else { throw redirected(file) }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile { return file }
        return file
    }

    private func redirected(_ path: URL) -> DomainError {
        DomainError(summary: "The input's runtime output path is redirected or has an unexpected type.",
            remediation: Remediation(summary: "Inspect \(path.path). Existing content was preserved."))
    }

    /// A failed diagnostic write does not replace the failure being reported.
    public func write(_ contents: String, to name: String) -> URL? {
        do {
            let file = try url(name)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: file)
            return file
        } catch { return nil }
    }

    /// Only exact absence in both namespaces permits the base-main 8081 endpoint.
    /// Earlier unmerged development port files carry no confirmed folder identity.
    public func metroPort(platform: ProjectPlatform = .ios) throws -> Int? {
        let name = "metro-port-\(platform.rawValue)"
        let file = try url(name)
        do {
            _ = try FileManager.default.attributesOfItem(atPath: file.path)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            let legacy = directory.appendingPathComponent(name)
            do {
                _ = try FileManager.default.attributesOfItem(atPath: legacy.path)
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
            throw DomainError(summary: "The earlier Metro port record has no confirmed folder owner.",
                remediation: Remediation(summary: "Inspect \(legacy.path) and the earlier run's evidence before choosing a recovery action. Existing records and servers were preserved."))
        }
        let data = try Data(contentsOf: file)
        guard let text = String(data: data, encoding: .utf8),
              let port = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)), (1...65535).contains(port)
        else { throw DomainError(summary: "The recorded Metro port is unreadable or invalid.",
            remediation: Remediation(summary: "Inspect \(file.path). Existing servers were preserved.")) }
        return port
    }

    public func recordMetroPort(_ port: Int, platform: ProjectPlatform = .ios) throws {
        guard (1...65535).contains(port) else {
            throw DomainError(summary: "The Metro port must be from 1 through 65535.",
                remediation: Remediation(summary: "Select a valid development server port."))
        }
        _ = try metroPort(platform: platform)
        let file = try url("metro-port-\(platform.rawValue)")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("\(port)\n".utf8).write(to: file, options: .atomic)
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

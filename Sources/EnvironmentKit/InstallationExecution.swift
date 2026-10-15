import Core
import CryptoKit
import Darwin
import Foundation

/// Providers pin one immutable payload. Credentials and inherited environments are never plan data.
public struct InstallationArtifact: Codable, Sendable, Equatable {
    public let url: URL
    public let checksumAlgorithm: String
    public let checksum: String
    public let size: Int64
    public init(url: URL, checksumAlgorithm: String, checksum: String, size: Int64) {
        self.url = url; self.checksumAlgorithm = checksumAlgorithm; self.checksum = checksum; self.size = size
    }
}

/// The shared approval and lease contract for preparation providers (#203–#206).
public struct InstallationMetadata: Codable, Sendable, Equatable {
    public let package: String
    public let revision: String
    public let destination: URL
    public let resourceRoot: URL
    public let artifact: InstallationArtifact
    public let repositoryURL: URL
    public let repositorySHA256: String
    public let licenseID: String?
    public let licenseSHA1: String?
    public let requiredFile: String
    public let executable: Bool
    public var resourceKey: ResourceKey { .destination(resourceRoot) }

    public init(package: String, revision: String, destination: URL, resourceRoot: URL,
                artifact: InstallationArtifact, repositoryURL: URL, repositorySHA256: String,
                licenseID: String? = nil, licenseSHA1: String? = nil, requiredFile: String, executable: Bool = false) {
        self.package = package; self.revision = revision; self.destination = destination; self.resourceRoot = resourceRoot
        self.artifact = artifact; self.repositoryURL = repositoryURL; self.repositorySHA256 = repositorySHA256
        self.licenseID = licenseID; self.licenseSHA1 = licenseSHA1; self.requiredFile = requiredFile; self.executable = executable
    }
}

/// Executable provider behavior stays outside Codable approval data.
/// Providers reuse the same lease, approval checks, runner, cancellation and completion loop.
public struct InstallationAction: Sendable {
    public let metadata: InstallationMetadata
    private let operation: @Sendable (any ProcessRunner, @Sendable ([URL]) async throws -> Void) async throws -> Void

    public init(metadata: InstallationMetadata,
                operation: @escaping @Sendable (any ProcessRunner, @Sendable ([URL]) async throws -> Void) async throws -> Void) {
        self.metadata = metadata; self.operation = operation
    }

    /// A trusted provider reports only its exact owned temporary paths for source observation.
    public func run(runner: any ProcessRunner, beforeCommit: @escaping @Sendable ([URL]) async throws -> Void) async throws {
        try Task.checkCancellation()
        try await beforeCommit([])
        try await operation(runner, beforeCommit)
    }
}

/// Downloads only into an owned directory. Providers reuse this boundary for their own install format.
public enum InstallationExecution {
    public static func download(_ artifact: InstallationArtifact, to directory: URL, runner: any ProcessRunner) async throws -> URL {
        guard artifact.url.scheme == "https", artifact.url.user == nil, artifact.url.password == nil,
              artifact.size > 0, ["sha1", "sha256"].contains(artifact.checksumAlgorithm),
              artifact.checksum.range(of: artifact.checksumAlgorithm == "sha1" ? #"^[0-9a-f]{40}$"# : #"^[0-9a-f]{64}$"#,
                                      options: .regularExpression) != nil else { throw failure("Invalid pinned installation artifact") }
        try Task.checkCancellation()
        let payload = directory.appendingPathComponent("payload.zip")
        let result = try await runner.run(ProcessCommand("curl", ["--fail", "--silent", "--show-error", "--location",
            "--proto", "=https", "--proto-redir", "=https", "--max-redirs", "3", "--connect-timeout", "30",
            "--max-time", "1800", "--max-filesize", String(artifact.size), "--output", payload.path, artifact.url.absoluteString], timeout: .seconds(1810)))
        guard result.terminationStatus.isSuccess else { throw failure("Pinned artifact download failed (\(result.terminationStatus))") }
        try Task.checkCancellation()
        let values = try payload.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, Int64(values.fileSize ?? -1) == artifact.size else {
            throw failure("Downloaded artifact size differs from the approved plan")
        }
        let data = try Data(contentsOf: payload, options: .mappedIfSafe)
        let actual = artifact.checksumAlgorithm == "sha1"
            ? Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
            : SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == artifact.checksum else { throw failure("Downloaded artifact checksum differs from the approved plan") }
        return payload
    }

    /// Must run while the caller owns metadata.resourceKey and has re-observed the approved plan.
    /// Existing destinations are never replaced, even when they look incomplete.
    public static func installSDKZip(_ metadata: InstallationMetadata, localMetadata: Data,
                                     runner: any ProcessRunner,
                                     beforeCommit: @Sendable ([URL]) async throws -> Void = { _ in }) async throws {
        try validateSDKLicense(metadata)
        try validateDestination(metadata)
        let manager = FileManager.default
        let scratch = metadata.resourceRoot.appendingPathComponent(".runstir-install-\(UUID().uuidString)")
        try manager.createDirectory(at: scratch, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: scratch) }
        let payload = try await download(metadata.artifact, to: scratch, runner: runner)
        let archive = try SafeZIP(data: Data(contentsOf: payload, options: .mappedIfSafe))
        try await archive.validateLinks(payload: payload, runner: runner)
        let extracted = scratch.appendingPathComponent("contents")
        try manager.createDirectory(at: extracted, withIntermediateDirectories: false)
        let unpack = try await runner.run(ProcessCommand("unzip", ["-q", payload.path, "-d", extracted.path], timeout: .seconds(600)))
        guard unpack.terminationStatus.isSuccess else { throw failure("Pinned archive extraction failed") }
        try Task.checkCancellation()
        try validateExtractedLinks(extracted)
        let children = try manager.contentsOfDirectory(at: extracted, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        let source: URL
        if manager.fileExists(atPath: extracted.appendingPathComponent("source.properties").path) { source = extracted }
        else if children.count == 1,
                try children[0].resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]).isDirectory == true,
                try children[0].resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true {
            source = children[0]
        } else { throw failure("Archive does not contain one SDK package") }
        let properties = try String(contentsOf: source.appendingPathComponent("source.properties"), encoding: .utf8)
        let revisions = properties.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            return parts.count == 2 && parts[0] == "Pkg.Revision" ? parts[1] : nil
        }
        guard revisions.count == 1, normalizedRevision(revisions[0]) == normalizedRevision(metadata.revision),
              normalizedRevision(metadata.revision) != nil else { throw failure("Archive package revision differs from the approved plan") }
        let marker = source.appendingPathComponent(metadata.requiredFile)
        guard manager.fileExists(atPath: marker.path),
              let sourcePath = canonicalPath(source), let markerPath = canonicalPath(marker),
              markerPath.hasPrefix(sourcePath + "/"),
              !metadata.executable || manager.isExecutableFile(atPath: marker.path) else { throw failure("Archive is missing the required SDK package content") }
        let packageXML = source.appendingPathComponent("package.xml")
        // This private stage becomes public only through the final exclusive rename.
        // Replacing a staged metadata link must never overwrite another archive member.
        if manager.fileExists(atPath: packageXML.path)
            || (try? manager.destinationOfSymbolicLink(atPath: packageXML.path)) != nil {
            try manager.removeItem(at: packageXML)
        }
        try localMetadata.write(to: packageXML)
        try Task.checkCancellation()
        try await beforeCommit([scratch])
        try validateSDKLicense(metadata)
        try validateDestination(metadata)
        let parent = metadata.destination.deletingLastPathComponent()
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        let staged = parent.appendingPathComponent(".runstir-stage-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: staged) }
        try manager.copyItem(at: source, to: staged)
        try Task.checkCancellation()
        try await beforeCommit([scratch, staged])
        try validateSDKLicense(metadata)
        try validateDestination(metadata)
        guard renamex_np(staged.path, metadata.destination.path, UInt32(RENAME_EXCL)) == 0 else {
            throw failure("Installation destination appeared or could not be committed; existing content was preserved")
        }
        // Once the atomic rename completed, the caller records completion before observing cancellation.
    }

    static func validateDestination(_ metadata: InstallationMetadata) throws {
        let manager = FileManager.default
        let root = metadata.resourceRoot.standardizedFileURL
        let destination = metadata.destination.standardizedFileURL
        guard destination.path.hasPrefix(root.path + "/"), destination.path != root.path,
              !manager.fileExists(atPath: destination.path),
              (try? manager.destinationOfSymbolicLink(atPath: destination.path)) == nil else {
            throw failure("Existing or out-of-scope installation destination must be preserved")
        }
        var ancestor = destination.deletingLastPathComponent()
        while ancestor.path.hasPrefix(root.path + "/") {
            if (try? manager.destinationOfSymbolicLink(atPath: ancestor.path)) != nil {
                throw failure("Installation destination has a symbolic-link ancestor")
            }
            ancestor.deleteLastPathComponent()
        }
        while !manager.fileExists(atPath: ancestor.path), ancestor.path != "/" { ancestor.deleteLastPathComponent() }
        guard manager.isWritableFile(atPath: ancestor.path) else { throw failure("Installation destination needs separate manual permission") }
    }

    private static func validateSDKLicense(_ metadata: InstallationMetadata) throws {
        guard let id = metadata.licenseID, let hash = metadata.licenseSHA1,
              id.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil,
              hash.range(of: #"^[0-9a-f]{40}$"#, options: .regularExpression) != nil,
              let text = try? String(contentsOf: metadata.resourceRoot.appendingPathComponent("licenses").appendingPathComponent(id), encoding: .utf8),
              text.split(whereSeparator: \.isNewline).contains(Substring(hash)) else {
            throw failure("The exact SDK license acceptance is missing or changed; manual consent is separate from plan approval")
        }
    }

    private static func validateExtractedLinks(_ root: URL) throws {
        var failure: (any Error)?
        guard let contents = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey],
            errorHandler: { _, error in failure = error; return false }) else { throw CocoaError(.fileReadNoPermission) }
        for case let file as URL in contents {
            if try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                contents.skipDescendants()
                guard let source = canonicalPath(root), let target = canonicalPath(file), target.hasPrefix(source + "/") else {
                    throw Self.failure("Extracted ZIP link escapes the owned package stage")
                }
            }
        }
        if let failure { throw failure }
    }

    private static func canonicalPath(_ url: URL) -> String? {
        guard let path = realpath(url.path, nil) else { return nil }
        defer { free(path) }
        return String(cString: path)
    }

    private static func normalizedRevision(_ value: String) -> [Int]? {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !components.isEmpty, components.count <= 3 else { return nil }
        let numbers = components.compactMap { Int($0) }
        guard numbers.count == components.count, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
        return numbers + Array(repeating: 0, count: 3 - numbers.count)
    }

    static func failure(_ message: String) -> DomainError {
        DomainError(summary: message, remediation: Remediation(summary: "Preserve completed installations. Inspect the current state and approve a new plan before retrying."))
    }
}

/// Inspects central and local ZIP headers before any untrusted member is extracted.
private struct SafeZIP {
    struct Entry { let path: String; let link: Bool }
    let entries: [Entry]
    init(data: Data) throws {
        func u16(_ offset: Int) throws -> Int {
            guard offset >= 0, offset + 2 <= data.count else { throw InstallationExecution.failure("Truncated ZIP header") }
            return Int(data[offset]) | Int(data[offset + 1]) << 8
        }
        func u32(_ offset: Int) throws -> Int { try u16(offset) | u16(offset + 2) << 16 }
        let minimum = max(0, data.count - 65557)
        var end: Int?
        if data.count >= 22 {
            for offset in stride(from: data.count - 22, through: minimum, by: -1) {
                if try u32(offset) == 0x06054b50, offset + 22 + (try u16(offset + 20)) == data.count { end = offset; break }
            }
        }
        guard let end, try u16(end + 4) == 0, try u16(end + 6) == 0,
              try u16(end + 8) == u16(end + 10) else { throw InstallationExecution.failure("Unsupported multi-disk or invalid ZIP") }
        let count = try u16(end + 10), size = try u32(end + 12)
        var offset = try u32(end + 16)
        let limit = offset + size
        guard count > 0, count < 65535, limit == end else { throw InstallationExecution.failure("Unsupported ZIP64 or ambiguous archive") }
        var values: [Entry] = [], seen = Set<String>()
        for _ in 0..<count {
            guard try u32(offset) == 0x02014b50 else { throw InstallationExecution.failure("Invalid ZIP central directory") }
            let flags = try u16(offset + 8), method = try u16(offset + 10)
            let length = try u16(offset + 28), extra = try u16(offset + 30), comment = try u16(offset + 32)
            let nameStart = offset + 46, next = nameStart + length + extra + comment
            guard flags & 1 == 0, [0, 8].contains(method), next <= limit, length > 0,
                  let name = String(data: data[nameStart..<(nameStart + length)], encoding: .utf8),
                  !name.hasPrefix("/"), !name.contains("\\"), !name.contains(":"),
                  !name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else {
                throw InstallationExecution.failure("Unsafe ZIP member name or encoding")
            }
            let path = name.hasSuffix("/") ? String(name.dropLast()) : name
            guard path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  seen.insert(path.precomposedStringWithCanonicalMapping.lowercased()).inserted else { throw InstallationExecution.failure("Unsafe or duplicate ZIP member path") }
            let type = (try u32(offset + 38) >> 16) & 0xf000
            guard [0, 0x4000, 0x8000, 0xa000].contains(type) else { throw InstallationExecution.failure("Unsupported ZIP member type") }
            let local = try u32(offset + 42)
            let localLength = try u16(local + 26), localExtra = try u16(local + 28)
            guard try u32(local) == 0x04034b50, try u16(local + 6) == flags, try u16(local + 8) == method,
                  localLength == length, local + 30 + localLength + localExtra <= offset,
                  data[(local + 30)..<(local + 30 + localLength)] == data[nameStart..<(nameStart + length)] else {
                throw InstallationExecution.failure("ZIP local and central identities disagree")
            }
            values.append(Entry(path: path, link: type == 0xa000))
            offset = next
        }
        guard offset == limit else { throw InstallationExecution.failure("Unexpected ZIP directory bytes") }
        let links = Set(values.filter(\.link).map { $0.path.precomposedStringWithCanonicalMapping.lowercased() })
        for value in values {
            let parts = value.path.split(separator: "/")
            for depth in 1..<parts.count where links.contains(parts.prefix(depth).joined(separator: "/").precomposedStringWithCanonicalMapping.lowercased()) {
                throw InstallationExecution.failure("ZIP writes through a symbolic-link ancestor")
            }
        }
        entries = values
    }

    func validateLinks(payload: URL, runner: any ProcessRunner) async throws {
        for entry in entries where entry.link {
            let result = try await runner.run(ProcessCommand("unzip", ["-p", payload.path, entry.path], timeout: .seconds(15)))
            let target = result.standardOutput
            guard result.terminationStatus.isSuccess, !target.isEmpty, target.utf8.count <= 4096,
                  !target.hasPrefix("/"), !target.contains("\\"), !target.contains(":"),
                  !target.unicodeScalars.contains(where: { $0.value < 32 }) else { throw InstallationExecution.failure("Unsafe ZIP symbolic-link target") }
            var parts = entry.path.split(separator: "/").dropLast().map(String.init)
            for component in target.split(separator: "/") {
                if component == ".." { guard !parts.isEmpty else { throw InstallationExecution.failure("ZIP link escapes staging") }; parts.removeLast() }
                else if component != "." { parts.append(String(component)) }
            }
            guard !parts.isEmpty else { throw InstallationExecution.failure("ZIP link escapes its package") }
        }
    }
}

import Core
import Darwin
import Foundation

/// A pinned tool archive uses the same approval, destination lease and download
/// contract as SDK preparation. It never invokes a manager's implicit installer.
public enum ToolArchive {
    public static func installExecutable(
        _ metadata: InstallationMetadata, runner: any ProcessRunner,
        beforeCommit: @Sendable ([URL]) async throws -> Void = { _ in },
        validate: @Sendable (URL, any ProcessRunner) async throws -> Void = { _, _ in }
    ) async throws {
        try Task.checkCancellation()
        try metadata.validate()
        guard let artifact = metadata.artifact else { throw InstallationExecution.failure("Tool preparation requires an archive artifact") }
        try InstallationExecution.validateDestination(metadata)
        let manager = FileManager.default
        try manager.createDirectory(at: metadata.resourceRoot, withIntermediateDirectories: true)
        let scratch = metadata.resourceRoot.appendingPathComponent(".runstir-tool-\(UUID().uuidString)")
        try manager.createDirectory(at: scratch, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: scratch) }
        try await beforeCommit([scratch])
        let payload = try await InstallationExecution.download(artifact, to: scratch, runner: runner)
        let source = scratch.appendingPathComponent("contents")
        let executable = source.appendingPathComponent(try ToolTAR.path(metadata.requiredFile))
        try manager.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manager.moveItem(at: payload, to: executable)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        try await validate(source, runner)
        try Task.checkCancellation()
        try await beforeCommit([scratch])
        try InstallationExecution.validateDestination(metadata)
        try manager.createDirectory(at: metadata.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try InstallationExecution.validateDestination(metadata)
        guard renamex_np(source.path, metadata.destination.path, UInt32(RENAME_EXCL)) == 0 else {
            throw InstallationExecution.failure("Tool destination appeared or exclusive commit failed; existing content was preserved")
        }
    }

    public static func installTarGzip(
        _ metadata: InstallationMetadata, payloadRoot: String,
        runner: any ProcessRunner,
        beforeCommit: @Sendable ([URL]) async throws -> Void = { _ in },
        validate: @Sendable (URL, any ProcessRunner) async throws -> Void = { _, _ in }
    ) async throws {
        try Task.checkCancellation()
        try metadata.validate()
        guard let artifact = metadata.artifact else { throw InstallationExecution.failure("Tool preparation requires an archive artifact") }
        try InstallationExecution.validateDestination(metadata)
        let manager = FileManager.default
        try manager.createDirectory(at: metadata.resourceRoot, withIntermediateDirectories: true)
        let scratch = metadata.resourceRoot.appendingPathComponent(".runstir-tool-\(UUID().uuidString)")
        try manager.createDirectory(at: scratch, withIntermediateDirectories: false,
                                    attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: scratch) }
        try await beforeCommit([scratch])
        let payload = try await InstallationExecution.download(artifact, to: scratch, runner: runner)
        let tar = scratch.appendingPathComponent("payload.tar")
        // POSIX file-size limits bound decompression before TAR parsing. Paths are
        // positional arguments to a constant script, never interpolated shell code.
        let unpack = try await runner.run(ProcessCommand("/bin/sh", ["-c",
            "ulimit -f 2097152 && exec /usr/bin/gzip -dc -- \"$1\" > \"$2\"",
            "runstir-tool-gzip", payload.path, tar.path], timeout: .seconds(600)))
        guard unpack.terminationStatus.isSuccess else { throw InstallationExecution.failure("Pinned tool gzip extraction failed or exceeded its size limit") }
        try Task.checkCancellation()
        let archive = try ToolTAR(data: Data(contentsOf: tar, options: .mappedIfSafe))
        let contents = scratch.appendingPathComponent("contents")
        try archive.extract(to: contents)
        let relative = try ToolTAR.path(payloadRoot)
        let source = contents.appendingPathComponent(relative)
        let root = contents.resolvingSymlinksInPath().path
        let resolved = source.resolvingSymlinksInPath().path
        guard resolved.hasPrefix(root + "/"),
              (try? source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])).map({ $0.isDirectory == true && $0.isSymbolicLink != true }) == true else {
            throw InstallationExecution.failure("Tool archive payload root differs from the approved layout")
        }
        try ToolTAR.validatePayloadLinks(source)
        let marker = source.appendingPathComponent(try ToolTAR.path(metadata.requiredFile))
        guard marker.resolvingSymlinksInPath().path.hasPrefix(resolved + "/"),
              metadata.executable ? manager.isExecutableFile(atPath: marker.path) : manager.fileExists(atPath: marker.path) else {
            throw InstallationExecution.failure("Tool archive is missing its approved executable")
        }
        try await validate(source, runner)
        try Task.checkCancellation()
        try await beforeCommit([scratch])
        try InstallationExecution.validateDestination(metadata)
        let parent = metadata.destination.deletingLastPathComponent()
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        // Creating nested parents must not make an intervening alias acceptable.
        try InstallationExecution.validateDestination(metadata)
        guard renamex_np(source.path, metadata.destination.path, UInt32(RENAME_EXCL)) == 0 else {
            throw InstallationExecution.failure("Tool destination appeared or exclusive commit failed; existing content was preserved")
        }
        // A completed rename is reported before observing a later cancellation.
    }
}

/// Only regular files, directories and contained links are accepted. GNU long
/// names and per-entry POSIX path headers are parsed before any member is written.
private struct ToolTAR {
    struct Entry {
        let name: String
        let type: UInt8
        let mode: Int
        let bytes: Range<Int>
        let link: String
    }
    let data: Data
    let entries: [Entry]

    init(data: Data) throws {
        guard data.count >= 1024, data.count <= 1_073_741_824, data.count % 512 == 0 else { throw Self.failure() }
        var result: [Entry] = []
        var names: Set<String> = []
        var position = 0
        var longName: String?
        var longLink: String?
        var pax: [String: String] = [:]
        var terminated = false
        while position + 512 <= data.count {
            try Task.checkCancellation()
            let header = Array(data[position..<(position + 512)])
            if header.allSatisfy({ $0 == 0 }) {
                guard position + 1024 <= data.count, data[position...].allSatisfy({ $0 == 0 }),
                      longName == nil, longLink == nil, pax.isEmpty else { throw Self.failure() }
                terminated = true
                break
            }
            func field(_ start: Int, _ count: Int) throws -> String {
                let bytes = header[start..<(start + count)].prefix { $0 != 0 }
                guard let value = String(bytes: bytes, encoding: .utf8) else { throw Self.failure() }
                return value
            }
            func octal(_ start: Int, _ count: Int) throws -> Int {
                let value = try field(start, count).trimmingCharacters(in: .whitespaces)
                guard !value.isEmpty, value.allSatisfy({ ("0"..."7").contains(String($0)) }),
                      let number = Int(value, radix: 8) else { throw Self.failure() }
                return number
            }
            let checksum = try octal(148, 8)
            let actual = header.enumerated().reduce(0) { $0 + ((148..<156).contains($1.offset) ? 32 : Int($1.element)) }
            let size = try octal(124, 12)
            guard checksum == actual, size <= 1_073_741_824,
                  position + 512 <= data.count - size else { throw Self.failure() }
            let start = position + 512
            let end = start + size
            let type = header[156]
            position = end + ((512 - size % 512) % 512)
            guard position <= data.count else { throw Self.failure() }
            if type == 76 || type == 75 {
                guard size < 16_384, let value = String(data: data[start..<end], encoding: .utf8) else { throw Self.failure() }
                var text = value
                while text.hasSuffix("\0") { text.removeLast() }
                if type == 76 { guard longName == nil else { throw Self.failure() }; longName = text }
                else { guard longLink == nil else { throw Self.failure() }; longLink = text }
                continue
            }
            if type == 120 {
                guard pax.isEmpty, size < 65_536 else { throw Self.failure() }
                pax = try Self.pax(Data(data[start..<end]))
                continue
            }
            guard [UInt8(0), 48, 49, 50, 53].contains(type), result.count < 100_000 else { throw Self.failure() }
            let prefix = try field(345, 155)
            let short = try field(0, 100)
            let combined = prefix.isEmpty ? short : prefix + "/" + short
            let name = try Self.path(pax["path"] ?? longName ?? combined)
            let mode = try octal(100, 8)
            guard mode & 0o7000 == 0, names.insert(name).inserted,
                  type == 0 || type == 48 || size == 0 else { throw Self.failure() }
            let link = try pax["linkpath"] ?? longLink ?? field(157, 100)
            result.append(Entry(name: name, type: type, mode: mode, bytes: start..<end, link: link))
            longName = nil; longLink = nil; pax = [:]
        }
        guard terminated, !result.isEmpty else { throw Self.failure() }
        let links = Set(result.filter { $0.type == 49 || $0.type == 50 }.map(\.name))
        for entry in result {
            let components = entry.name.split(separator: "/")
            for count in 1..<components.count {
                guard !links.contains(components.prefix(count).joined(separator: "/")) else { throw Self.failure() }
            }
            if entry.type == 49 || entry.type == 50 {
                let target = try Self.linkTarget(entry)
                guard names.contains(target) || result.contains(where: { $0.name.hasPrefix(target + "/") }) else { throw Self.failure() }
            }
        }
        self.data = data
        self.entries = result
    }

    static func path(_ raw: String) throws -> String {
        guard !raw.hasPrefix("/"), !raw.contains("\\"), !raw.contains(":"),
              !raw.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw failure() }
        let components = raw.split(separator: "/")
        guard !components.contains("..") else { throw failure() }
        let value = components.filter { $0 != "." }.joined(separator: "/")
        guard !value.isEmpty, value.utf8.count < 4096 else { throw failure() }
        return value
    }

    private static func linkTarget(_ entry: Entry) throws -> String {
        guard !entry.link.hasPrefix("/"), !entry.link.contains("\\"), !entry.link.contains(":"),
              !entry.link.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw failure() }
        var parts = entry.type == 50 ? entry.name.split(separator: "/").dropLast().map(String.init) : []
        for part in entry.link.split(separator: "/") {
            if part == "." { continue }
            if part == ".." { guard !parts.isEmpty else { throw failure() }; parts.removeLast() }
            else { parts.append(String(part)) }
        }
        guard !parts.isEmpty else { throw failure() }
        return parts.joined(separator: "/")
    }

    private static func pax(_ bytes: Data) throws -> [String: String] {
        var position = 0
        var fields: [String: String] = [:]
        while position < bytes.count {
            guard let space = bytes[position...].firstIndex(of: 32),
                  let length = Int(String(decoding: bytes[position..<space], as: UTF8.self)),
                  length > space - position + 2, length <= bytes.count - position,
                  bytes[position + length - 1] == 10,
                  let value = String(data: bytes[(space + 1)..<(position + length - 1)], encoding: .utf8),
                  let equal = value.firstIndex(of: "=") else { throw failure() }
            let key = String(value[..<equal])
            let content = String(value[value.index(after: equal)...])
            guard ["path", "linkpath", "mtime", "atime", "ctime", "uid", "gid", "uname", "gname"].contains(key), fields[key] == nil else { throw failure() }
            fields[key] = content
            position += length
        }
        return fields
    }

    func extract(to root: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        for entry in entries where entry.type != 49 && entry.type != 50 {
            try Task.checkCancellation()
            let target = root.appendingPathComponent(entry.name)
            try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if entry.type == 53 { try manager.createDirectory(at: target, withIntermediateDirectories: true) }
            else {
                try data[entry.bytes].write(to: target, options: .withoutOverwriting)
                try manager.setAttributes([.posixPermissions: entry.mode & 0o777], ofItemAtPath: target.path)
            }
        }
        for entry in entries where entry.type == 49 || entry.type == 50 {
            try Task.checkCancellation()
            let target = root.appendingPathComponent(entry.name)
            try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let source = root.appendingPathComponent(try Self.linkTarget(entry))
            if entry.type == 50 { try manager.createSymbolicLink(atPath: target.path, withDestinationPath: entry.link) }
            else {
                guard (try? source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])).map({ $0.isRegularFile == true && $0.isSymbolicLink != true }) == true else { throw Self.failure() }
                try manager.linkItem(at: source, to: target)
            }
        }
        for entry in entries where entry.type == 50 {
            let resolved = root.appendingPathComponent(entry.name).resolvingSymlinksInPath().path
            guard resolved.hasPrefix(root.path + "/"), manager.fileExists(atPath: resolved) else { throw Self.failure() }
        }
    }

    private static func failure() -> DomainError { InstallationExecution.failure("Tool TAR contains malformed, unsupported or escaping entries") }

    static func validatePayloadLinks(_ root: URL) throws {
        let manager = FileManager.default
        let prefix = root.resolvingSymlinksInPath().path + "/"
        guard let members = manager.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { throw failure() }
        for case let member as URL in members {
            if try member.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                members.skipDescendants()
                let resolved = member.resolvingSymlinksInPath().path
                guard resolved.hasPrefix(prefix), manager.fileExists(atPath: resolved) else { throw failure() }
            }
        }
    }
}

import Compression
import Core
import Darwin
import Foundation

/// Extracts the single `Payload/*.app` of an `.ipa` without trusting the archive.
/// Every central-directory entry is validated before a byte is written. Files keep
/// their bytes and permission bits; nothing is re-signed and no contained code runs.
enum IPAArchive {
    static let entryLimit = 100_000
    static let expandedLimit: UInt64 = 8 << 30
    static let directoryLimit = 64 << 20
    static let linkLimit: UInt64 = 1_024
    static let depthLimit = 64

    private enum Kind { case file, directory, link }

    private struct Entry {
        let name: Data
        let components: [String]
        let kind: Kind
        let mode: mode_t
        let method: UInt16
        let crc: UInt32
        let compressedSize: UInt64
        let size: UInt64
        let localOffset: UInt64
        var dataOffset: UInt64 = 0
        // APFS and HFS+ are usually case- and normalization-insensitive. This key gives early,
        // readable errors; extraction itself refuses any on-disk collision with lstat.
        let folded: [String]

        func key(_ depth: Int? = nil) -> String { folded.prefix(depth ?? folded.count).joined(separator: "/") }
    }

    /// Creates `root` (mode 0700, must not exist) and returns the extracted `.app` inside it.
    static func extract(_ ipa: URL, into root: URL) throws -> URL {
        let input = try FileHandle(forReadingFrom: ipa)
        defer { try? input.close() }
        let size = try input.seekToEnd()
        var (entries, directoryOffset) = try centralDirectory(input, size: size)
        let app = try payloadApp(entries)
        let extracted = entries.indices.filter {
            entries[$0].components.count > 2 && entries[$0].components[0] == "Payload" && entries[$0].components[1] == app
        }
        let expanded = extracted.reduce(UInt64(0)) { $0 + entries[$1].size }
        guard expanded <= expandedLimit else {
            throw failure("The IPA expands to \(expanded) bytes, above the \(expandedLimit)-byte extraction limit.")
        }
        try localHeaders(input, entries: &entries, end: directoryOffset)

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        if let available = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage, available < Int64(clamping: expanded) {
            throw DomainError(summary: "The IPA needs \(expanded) bytes but the temporary volume has \(available) available.",
                remediation: Remediation(summary: "Free space on the temporary volume, then inspect the same IPA again. Runstir did not change the original file."))
        }
        let appMode = entries.first { $0.components == ["Payload", app] }?.mode ?? 0o755
        let appRoot = URL(fileURLWithPath: try directory(root, ["Payload", app], mode: appMode), isDirectory: true)
        // Directories and files first, links last: no write can pass through an archive link.
        let ordered = extracted.sorted { entries[$0].components.count < entries[$1].components.count }
        for index in ordered where entries[index].kind != .link {
            try Task.checkCancellation()
            let entry = entries[index]
            if entry.kind == .directory {
                _ = try directory(root, entry.components, mode: entry.mode)
                continue
            }
            let path = try directory(root, entry.components.dropLast()) + "/" + entry.components.last!
            let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard descriptor >= 0 else { throw failure("The IPA entry cannot be created: \(entry.components.joined(separator: "/"))") }
            let output = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            try inflate(input, entry) { try output.write(contentsOf: $0) }
            guard fchmod(descriptor, entry.mode | 0o600) == 0 else { throw failure("The IPA entry mode cannot be applied.") }
            try output.close()
        }
        for index in extracted where entries[index].kind == .link {
            let entry = entries[index]
            var target = Data()
            try inflate(input, entry) { target.append($0) }
            guard let destination = String(data: target, encoding: .utf8), !destination.contains("\0"),
                  linkStaysInside(entry.components, destination) else {
                throw failure("The IPA contains an absolute or escaping symbolic link: \(entry.components.joined(separator: "/"))")
            }
            let path = try directory(root, entry.components.dropLast()) + "/" + entry.components.last!
            guard symlink(destination, path) == 0 else {
                throw failure("The IPA symbolic link collides with an extracted entry: \(entry.components.joined(separator: "/"))")
            }
        }
        // The extracted bundle must pass the same link and special-file checks as a chosen .app.
        _ = try AppFileSnapshot.read(appRoot)
        return appRoot
    }

    /// Creates missing directories one component at a time below `root`. An existing link or file
    /// anywhere on the path is refused, so no later write can follow a colliding name.
    private static func directory(_ root: URL, _ components: some Collection<String>, mode: mode_t = 0o755) throws -> String {
        var path = root.path
        for (offset, component) in components.enumerated() {
            path += "/" + component
            var status = stat()
            if lstat(path, &status) == 0 {
                guard status.st_mode & S_IFMT == S_IFDIR else {
                    throw failure("The IPA entry collides with an extracted file or link: \(components.joined(separator: "/"))")
                }
            } else if errno != ENOENT || mkdir(path, 0o700) != 0 {
                throw failure("The IPA directory cannot be created: \(components.joined(separator: "/"))")
            }
            if offset == components.count - 1 || status.st_mode == 0 {
                guard chmod(path, (offset == components.count - 1 ? mode : 0o755) | 0o700) == 0 else {
                    throw failure("The IPA directory mode cannot be applied: \(components.joined(separator: "/"))")
                }
            }
        }
        return path
    }

    private static func centralDirectory(_ input: FileHandle, size: UInt64) throws -> ([Entry], UInt64) {
        guard size >= 22 else { throw failure("The IPA is not a complete zip archive.") }
        let tailOffset = size - min(size, 65_557)
        let tail = try read(input, at: tailOffset, count: Int(size - tailOffset))
        // The end record must be the last thing in the file; a comment cannot hide another one.
        guard let end = stride(from: tail.count - 22, through: 0, by: -1).first(where: {
            tail.u32($0) == 0x0605_4b50 && $0 + 22 + Int(tail.u16($0 + 20)) == tail.count
        }) else { throw failure("The IPA is not a complete zip archive.") }
        let endOffset = tailOffset + UInt64(end)
        let count = Int(tail.u16(end + 10))
        let directorySize = UInt64(tail.u32(end + 12))
        let directoryOffset = UInt64(tail.u32(end + 16))
        guard tail.u16(end + 4) == 0, tail.u16(end + 6) == 0, tail.u16(end + 8) == count,
              count != 0xFFFF, directorySize != 0xFFFF_FFFF, directoryOffset != 0xFFFF_FFFF,
              end < 20 || tail.u32(end - 20) != 0x0706_4b50 else {
            throw failure("The IPA uses a multi-part or ZIP64 layout, which this extraction does not accept.")
        }
        guard count <= entryLimit, directorySize <= directoryLimit else {
            throw failure("The IPA has more entries or directory data than the extraction limit (\(entryLimit) entries).")
        }
        guard directoryOffset + directorySize == endOffset else {
            throw failure("The IPA central directory does not end at its end record.")
        }
        let directory = try read(input, at: directoryOffset, count: Int(directorySize))
        var entries: [Entry] = []
        var cursor = 0
        for _ in 0..<count {
            try Task.checkCancellation()
            guard cursor + 46 <= directory.count, directory.u32(cursor) == 0x0201_4b50 else {
                throw failure("The IPA central directory is malformed.")
            }
            let flags = directory.u16(cursor + 8)
            let method = directory.u16(cursor + 10)
            let nameLength = Int(directory.u16(cursor + 28))
            let next = cursor + 46 + nameLength + Int(directory.u16(cursor + 30)) + Int(directory.u16(cursor + 32))
            guard next <= directory.count else { throw failure("The IPA central directory is malformed.") }
            let name = directory.subdata(in: cursor + 46..<cursor + 46 + nameLength)
            let shown = String(decoding: name, as: UTF8.self)
            guard flags & 0x2041 == 0 else { throw failure("The IPA entry is encrypted: \(shown)") }
            guard method == 0 || method == 8 else { throw failure("The IPA entry uses unsupported compression \(method): \(shown)") }
            let compressedSize = UInt64(directory.u32(cursor + 20))
            let size = UInt64(directory.u32(cursor + 24))
            guard method == 8 || compressedSize == size else { throw failure("The IPA stored entry sizes disagree: \(shown)") }
            // macOS ditto writes UTF-8 names without the UTF-8 flag; only strict UTF-8 is accepted.
            guard let text = String(data: name, encoding: .utf8) else {
                throw failure("The IPA entry name is not valid UTF-8: \(shown)")
            }
            let directoryName = text.hasSuffix("/")
            let components = (directoryName ? String(text.dropLast()) : text).split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard !text.isEmpty, !text.hasPrefix("/"), !text.contains("\\"), !text.contains(":"), text.utf8.count <= 1_024, components.count <= depthLimit,
                  !text.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
                  components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.count <= 255 }) else {
                throw failure("The IPA entry path is absolute, escaping or malformed: \(shown)")
            }
            // Unix (3) and macOS (19) hosts store the mode in the high attribute bits.
            let unixMode = [3, 19].contains(directory.u8(cursor + 5)) ? mode_t(directory.u32(cursor + 38) >> 16) : 0
            let kind: Kind
            switch unixMode & S_IFMT {
            case 0: kind = directoryName ? .directory : .file
            case S_IFREG where !directoryName: kind = .file
            case S_IFDIR: kind = .directory
            case S_IFLNK where !directoryName: kind = .link
            default: throw failure("The IPA contains a special or contradictory entry type: \(shown)")
            }
            guard kind != .link || size <= linkLimit else { throw failure("The IPA symbolic link target is too long: \(shown)") }
            let mode = unixMode == 0 ? (kind == .file ? 0o644 : 0o755) : unixMode & 0o777
            entries.append(Entry(name: name, components: components, kind: kind, mode: mode, method: method,
                crc: directory.u32(cursor + 16), compressedSize: compressedSize, size: size,
                localOffset: UInt64(directory.u32(cursor + 42)),
                folded: components.map { $0.precomposedStringWithCanonicalMapping.folding(options: .caseInsensitive, locale: nil) }))
            cursor = next
        }
        guard cursor == directory.count else { throw failure("The IPA central directory has trailing data.") }

        var kinds: [String: Kind] = [:]
        for entry in entries {
            guard kinds.updateValue(entry.kind, forKey: entry.key()) == nil else {
                throw failure("The IPA has duplicate or case/normalization-colliding entries: \(entry.components.joined(separator: "/"))")
            }
        }
        for entry in entries {
            try Task.checkCancellation()
            for length in 1..<max(entry.components.count, 1) where kinds[entry.key(length), default: .directory] != .directory {
                throw failure("The IPA places an entry below a file or link: \(entry.components.joined(separator: "/"))")
            }
        }
        return (entries, directoryOffset)
    }

    /// Exactly one `Payload/<name>.app` directory and nothing else directly in `Payload`.
    private static func payloadApp(_ entries: [Entry]) throws -> String {
        let payload = entries.filter { $0.components[0] == "Payload" }
        // A differently cased top folder would be a second, silently skipped payload.
        if let other = entries.first(where: { $0.components[0] != "Payload" && $0.components[0].lowercased() == "payload" }) {
            throw failure("The IPA has an ambiguous payload folder: \(other.components.joined(separator: "/"))")
        }
        let children = Set(payload.compactMap { $0.components.count > 1 ? $0.components[1] : nil })
        guard let app = children.first, children.count == 1, app.hasSuffix(".app"), app.count > 4 else {
            throw failure(children.isEmpty
                ? "The IPA has no Payload/*.app application."
                : "The IPA Payload must hold exactly one .app and nothing else; found: \(children.sorted().joined(separator: ", ")).")
        }
        guard payload.allSatisfy({ $0.components.count > 2 || $0.kind == .directory }),
              payload.contains(where: { $0.components.count > 2 }) else {
            throw failure("The IPA Payload app \(app) is not a directory with contents.")
        }
        return app
    }

    private static func localHeaders(_ input: FileHandle, entries: inout [Entry], end: UInt64) throws {
        for index in entries.indices {
            let entry = entries[index]
            let header = try read(input, at: entry.localOffset, count: 30)
            let nameLength = Int(header.u16(26))
            // Without a data descriptor the local CRC and sizes must agree, so no other reader sees other contents.
            let described = header.u16(6) & 0x8 != 0
            guard header.u32(0) == 0x0403_4b50, header.u16(8) == entry.method, header.u16(6) & 0x2041 == 0,
                  described || (header.u32(14) == entry.crc && UInt64(header.u32(18)) == entry.compressedSize
                      && UInt64(header.u32(22)) == entry.size),
                  try read(input, at: entry.localOffset + 30, count: nameLength) == entry.name else {
                throw failure("The IPA local header disagrees with its central directory: \(entry.components.joined(separator: "/"))")
            }
            entries[index].dataOffset = entry.localOffset + 30 + UInt64(nameLength) + UInt64(header.u16(28))
        }
        // Overlapping entries reuse compressed bytes to multiply output (a zip bomb).
        let ordered = entries.sorted { $0.localOffset < $1.localOffset }
        let starts = ordered.dropFirst().map(\.localOffset) + [end]
        for (entry, limit) in zip(ordered, starts) where entry.dataOffset + entry.compressedSize > limit {
            throw failure("The IPA entries overlap or run past the archive: \(entry.components.joined(separator: "/"))")
        }
    }

    /// Streams exactly the declared size and CRC. A lying header cannot expand past its declaration.
    private static func inflate(_ input: FileHandle, _ entry: Entry, write: @escaping (Data) throws -> Void) throws {
        let shown = entry.components.joined(separator: "/")
        var written: UInt64 = 0
        var crc = CRC32()
        let sink: (Data) throws -> Void = { block in
            written += UInt64(block.count)
            guard written <= entry.size else { throw failure("The IPA entry expands past its declared size: \(shown)") }
            crc.update(block)
            try write(block)
        }
        let filter = entry.method == 8 ? try OutputFilter(.decompress, using: .zlib) { if let block = $0 { try sink(block) } } : nil
        try input.seek(toOffset: entry.dataOffset)
        var remaining = entry.compressedSize
        while remaining > 0 {
            try Task.checkCancellation()
            guard let block = try input.read(upToCount: Int(min(remaining, 1 << 20))), !block.isEmpty else {
                throw failure("The IPA entry data is truncated: \(shown)")
            }
            remaining -= UInt64(block.count)
            if let filter { try filter.write(block) } else { try sink(block) }
        }
        try filter?.finalize()
        guard written == entry.size, crc.value == entry.crc else {
            throw failure("The IPA entry size or CRC does not match its declaration: \(shown)")
        }
    }

    /// Lexically resolves a relative target from the link's directory; it must stay inside the app.
    private static func linkStaysInside(_ components: [String], _ destination: String) -> Bool {
        guard !destination.isEmpty, !destination.hasPrefix("/") else { return false }
        var resolved = Array(components.dropLast())
        for part in destination.split(separator: "/", omittingEmptySubsequences: true) {
            switch part {
            case ".": continue
            case "..": resolved.removeLast(); if resolved.count < 2 { return false }
            default: resolved.append(String(part))
            }
        }
        return resolved.count > 2
    }

    private static func read(_ input: FileHandle, at offset: UInt64, count: Int) throws -> Data {
        try input.seek(toOffset: offset)
        guard let data = try input.read(upToCount: count), data.count == count else {
            throw failure("The IPA is truncated.")
        }
        return data
    }

    static func failure(_ summary: String) -> DomainError {
        DomainError(summary: summary, remediation: Remediation(summary: "Choose a Development or Ad Hoc .ipa with one Payload app and a plain zip layout, or export the .app itself, then inspect again. Runstir did not change the original file."))
    }
}

struct CRC32 {
    private static let table: [UInt32] = (0..<256).map { byte in
        (0..<8).reduce(UInt32(byte)) { value, _ in value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
    }
    private var state: UInt32 = 0xFFFF_FFFF
    var value: UInt32 { state ^ 0xFFFF_FFFF }

    mutating func update(_ data: Data) {
        for byte in data { state = Self.table[Int((state ^ UInt32(byte)) & 0xFF)] ^ (state >> 8) }
    }
}

private extension Data {
    func u8(_ offset: Int) -> UInt8 { self[startIndex + offset] }
    func u16(_ offset: Int) -> UInt16 { UInt16(u8(offset)) | UInt16(u8(offset + 1)) << 8 }
    func u32(_ offset: Int) -> UInt32 { UInt32(u16(offset)) | UInt32(u16(offset + 2)) << 16 }
}

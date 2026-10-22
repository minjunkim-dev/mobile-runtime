import Core
@testable import EnvironmentKit
import Foundation
import TestSupport
import Testing

@Suite("IPA extraction validates every archive entry before writing")
struct IPAArchiveTests {
    @Test("one Payload app keeps its bytes, modes and inner links; entries outside Payload stay unextracted")
    func extractsPayloadApp() throws {
        let repo = try FixtureRepo()
        let ipa = try repo.ipa([
            .directory("Payload/"), .directory("Payload/X.app/", mode: 0o755),
            .file("Payload/X.app/Info.plist", "plist bytes", deflate: true),
            .file("Payload/X.app/X", "executable", mode: 0o755),
            .file("Payload/X.app/Frameworks/F.framework/F", "framework", deflate: true),
            .link("Payload/X.app/Current", "Frameworks/F.framework/F"),
            .file("Symbols/X.symbols", "outside payload"),
        ])
        let before = try Data(contentsOf: ipa)
        let app = try IPAArchive.extract(ipa, into: repo.url("out"))

        #expect(app.path == repo.url("out/Payload/X.app").path)
        #expect(try String(contentsOf: app.appendingPathComponent("Info.plist"), encoding: .utf8) == "plist bytes")
        #expect(try String(contentsOf: app.appendingPathComponent("Current"), encoding: .utf8) == "framework")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: app.appendingPathComponent("Current").path) == "Frameworks/F.framework/F")
        let mode = try FileManager.default.attributesOfItem(atPath: app.appendingPathComponent("X").path)[.posixPermissions] as? Int
        #expect(mode == 0o755)
        let root = try FileManager.default.attributesOfItem(atPath: repo.url("out").path)[.posixPermissions] as? Int
        #expect(root == 0o700)
        #expect(!FileManager.default.fileExists(atPath: repo.url("out/Symbols").path))
        #expect(try Data(contentsOf: ipa) == before)
    }

    @Test("unsafe or ambiguous archives are rejected without writing outside the extraction root", arguments: [
        "traversal", "absolute", "backslash", "escaping-link", "absolute-link", "chained-escape", "duplicate", "case-collision",
        "below-link", "below-file", "two-apps", "no-app", "payload-extra", "app-is-link", "special-file", "encrypted",
        "lying-size", "oversized", "overlap", "crc", "not-zip", "zip64", "name-mismatch", "unsupported-method",
    ])
    func rejected(_ defect: String) throws {
        let repo = try FixtureRepo()
        let app = "Payload/X.app/"
        var entries: [TestZip.Entry] = [.file(app + "Info.plist", "plist")]
        var layout = TestZip.Layout()
        switch defect {
        case "traversal": entries.append(.file(app + "../../../escaped", "x"))
        case "absolute": entries.append(.file("/tmp/escaped", "x"))
        case "backslash": entries.append(.file(app + "..\\..\\escaped", "x"))
        case "escaping-link": entries.append(.link(app + "link", "../../../escaped"))
        case "absolute-link": entries.append(.link(app + "link", repo.url("escaped").path))
        case "chained-escape":
            // Each link stays inside lexically; resolving the chain leaves the app.
            entries += [.directory(app + "t/"), .link(app + "d1/d2/d3/d4/L1", "../../../../t"),
                        .link(app + "L2", "d1/d2/d3/d4/L1/../../../escaped")]
        case "duplicate": entries.append(.file(app + "Info.plist", "second"))
        case "case-collision": entries.append(.file(app + "info.PLIST", "second"))
        case "below-link": entries += [.link(app + "dir", "Frameworks"), .file(app + "dir/x", "x")]
        case "below-file": entries.append(.file(app + "Info.plist/x", "x"))
        case "two-apps": entries.append(.file("Payload/Y.app/Info.plist", "plist"))
        case "no-app": entries = [.directory("Payload/"), .file("Other/X.app/Info.plist", "plist")]
        case "payload-extra": entries.append(.file("Payload/.DS_Store", "x"))
        case "app-is-link": entries = [.link("Payload/X.app", "../Other.app")]
        case "special-file": entries.append(.file(app + "fifo", "", mode: 0o010_644))
        case "encrypted": entries[0].flags |= 0x1
        case "lying-size": entries[0] = .file(app + "Info.plist", String(repeating: "A", count: 100_000), deflate: true); entries[0].declaredSize = 10
        case "oversized":
            for index in 0..<3 { var entry = TestZip.Entry.file(app + "big\(index)", "x"); entry.declaredSize = 0xFFFF_FFF0; entry.declaredCompressed = 0xFFFF_FFF0; entries.append(entry) }
        case "overlap": entries[0].declaredCompressed = 200; entries[0].declaredSize = 200; entries.append(.file(app + "next", String(repeating: "B", count: 300)))
        case "crc": entries[0].crc = 0xDEAD_BEEF
        case "not-zip": layout.raw = Data("not a zip archive".utf8)
        case "zip64": layout.entryCount = 0xFFFF
        case "name-mismatch": entries[0].localName = app + "Other.plist"
        case "unsupported-method": entries[0].method = 12
        default: Issue.record("unknown defect \(defect)")
        }
        let ipa = try repo.ipa(entries, layout: layout)
        let before = try Data(contentsOf: ipa)
        #expect(throws: DomainError.self) { try IPAArchive.extract(ipa, into: repo.url("out")) }
        #expect(!FileManager.default.fileExists(atPath: repo.url("escaped").path))
        #expect(!FileManager.default.fileExists(atPath: "/tmp/escaped"))
        #expect(try Data(contentsOf: ipa) == before)
    }
}

/// Writes zip bytes directly so tests can express headers that real tools refuse to produce.
enum TestZip {
    struct Entry {
        var name: String
        var data: Data
        var mode: UInt32
        var deflate = false
        var flags: UInt16 = 0x800
        var method: UInt16?
        var declaredSize: UInt32?
        var declaredCompressed: UInt32?
        var crc: UInt32?
        var localName: String?

        static func file(_ name: String, _ text: String, mode: UInt32 = 0o100_644, deflate: Bool = false) -> Entry {
            Entry(name: name, data: Data(text.utf8), mode: mode & 0o170_000 == 0 ? mode | 0o100_000 : mode, deflate: deflate)
        }
        static func directory(_ name: String, mode: UInt32 = 0o755) -> Entry { Entry(name: name, data: Data(), mode: 0o040_000 | mode) }
        static func link(_ name: String, _ target: String) -> Entry { Entry(name: name, data: Data(target.utf8), mode: 0o120_777) }
    }

    struct Layout {
        var raw: Data?
        var entryCount: UInt16?
    }

    static func archive(_ entries: [Entry], layout: Layout = Layout()) throws -> Data {
        if let raw = layout.raw { return raw }
        var body = Data()
        var directory = Data()
        for entry in entries {
            var crc = CRC32()
            crc.update(entry.data)
            let payload = entry.deflate ? try (entry.data as NSData).compressed(using: .zlib) as Data : entry.data
            let method = entry.method ?? (entry.deflate ? 8 : 0)
            let compressed = entry.declaredCompressed ?? UInt32(payload.count)
            let size = entry.declaredSize ?? UInt32(entry.data.count)
            let checksum = entry.crc ?? crc.value
            let name = Data(entry.name.utf8)
            let localName = Data((entry.localName ?? entry.name).utf8)
            let offset = UInt32(body.count)
            body.le(UInt32(0x0403_4b50)); body.le(UInt16(20)); body.le(entry.flags); body.le(method)
            body.le(UInt32(0)); body.le(checksum); body.le(compressed); body.le(size)
            body.le(UInt16(localName.count)); body.le(UInt16(0)); body.append(localName); body.append(payload)
            directory.le(UInt32(0x0201_4b50)); directory.le(UInt16(0x0314)); directory.le(UInt16(20)); directory.le(entry.flags)
            directory.le(method); directory.le(UInt32(0)); directory.le(checksum); directory.le(compressed); directory.le(size)
            directory.le(UInt16(name.count)); directory.le(UInt16(0)); directory.le(UInt16(0)); directory.le(UInt16(0)); directory.le(UInt16(0))
            directory.le(entry.mode << 16); directory.le(offset); directory.append(name)
        }
        let count = layout.entryCount ?? UInt16(entries.count)
        var end = Data()
        end.le(UInt32(0x0605_4b50)); end.le(UInt16(0)); end.le(UInt16(0)); end.le(count); end.le(count)
        end.le(UInt32(directory.count)); end.le(UInt32(body.count)); end.le(UInt16(0))
        return body + directory + end
    }
}

extension FixtureRepo {
    func ipa(_ entries: [TestZip.Entry], layout: TestZip.Layout = TestZip.Layout(), name: String = "Input.ipa") throws -> URL {
        let file = url(name)
        try TestZip.archive(entries, layout: layout).write(to: file)
        return file
    }
}

private extension Data {
    mutating func le<T: FixedWidthInteger>(_ value: T) { Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) } }
}

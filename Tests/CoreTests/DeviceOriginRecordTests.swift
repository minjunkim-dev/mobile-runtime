import Core
import Foundation
import TestSupport
import Testing

@Suite("Device origin record (ADR-0045)")
struct DeviceOriginRecordTests {
    @Test("no record means external; a recorded UDID is Runstir-created")
    func simulator() throws {
        let home = try FixtureRepo()
        let record = DeviceOriginRecord(environment: ["HOME": home.root.path])
        #expect(record.file.path.hasSuffix("Library/Application Support/dev.runstir/device-origins.json"))
        #expect(record.devices() == [])
        #expect(record.origin(platform: .ios, id: "A", folder: nil) == .external)
        try record.record(.simulator("A"))
        try record.record(.simulator("A"))
        #expect(record.devices() == [.simulator("A")])
        #expect(record.origin(platform: .ios, id: "A", folder: nil) == .runstirCreated)
        #expect(record.origin(platform: .ios, id: "B", folder: nil) == .external)
    }

    @Test("an AVD keeps its origin across setting changes; a same-name recreation is unknown")
    func avd() throws {
        let home = try FixtureRepo()
        let record = DeviceOriginRecord(environment: ["HOME": home.root.path])
        try home.write("avd/Pixel.avd/config.ini", "hw.ramSize=2048\n")
        let folder = home.url("avd/Pixel.avd")
        try record.record(try #require(DeviceOriginRecord.Device.avd(name: "Pixel", folder: folder)))
        #expect(record.origin(platform: .android, id: "Pixel", folder: folder.path) == .runstirCreated)
        try home.write("avd/Pixel.avd/config.ini", "hw.ramSize=4096\n")
        #expect(record.origin(platform: .android, id: "Pixel", folder: folder.path) == .runstirCreated)
        #expect(record.origin(platform: .android, id: "Other", folder: home.url("avd/Other.avd").path) == .external)
        #expect(record.origin(platform: .android, id: "Pixel", folder: home.url("elsewhere/Pixel.avd").path) == .unknown)
        #expect(record.origin(platform: .android, id: "Pixel", folder: nil) == .unknown)
        try FileManager.default.removeItem(at: folder)
        try home.write("avd/Pixel.avd/config.ini", "hw.ramSize=2048\n")
        #expect(record.origin(platform: .android, id: "Pixel", folder: folder.path) == .unknown)
    }

    @Test("an unreadable record makes every virtual device unknown and is never overwritten",
          arguments: ["not json", #"{"schemaVersion":2,"devices":[]}"#])
    func unreadable(contents: String) throws {
        let home = try FixtureRepo()
        let record = DeviceOriginRecord(environment: ["HOME": home.root.path])
        try FileManager.default.createDirectory(at: record.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: record.file)
        #expect(record.devices() == nil)
        #expect(record.origin(platform: .ios, id: "A", folder: nil) == .unknown)
        #expect(throws: (any Error).self) { try record.record(.simulator("A")) }
        #expect(try String(contentsOf: record.file, encoding: .utf8) == contents)
    }

    @Test("doctor warns only when the record exists and cannot be read")
    func doctor() async throws {
        let home = try FixtureRepo()
        let record = DeviceOriginRecord(environment: ["HOME": home.root.path])
        #expect(try await DeviceOriginRecordCheck(record: record).run().status == .pass)
        try record.record(.simulator("A"))
        #expect(try await DeviceOriginRecordCheck(record: record).run().status == .pass)
        try Data("damaged".utf8).write(to: record.file)
        #expect(try await DeviceOriginRecordCheck(record: record).run().status == .warning)
        #expect(try String(contentsOf: record.file, encoding: .utf8) == "damaged")
    }
}

import Core
import Foundation
import TestSupport
import Testing

@Suite("virtual-device origin records")
struct DeviceOriginTests {
    @Test("only an explicit creation record marks a Simulator as Runstir-created")
    func simulator() throws {
        let repo = try FixtureRepo()
        let store = DeviceOriginStore(leases: ResourceLeases(directory: repo.url("leases")))
        let id = UUID().uuidString
        #expect(store.origin(platform: .ios, id: id) == .external)
        try store.record(platform: .ios, id: id)
        #expect(DeviceOriginStore(leases: store.leases).origin(platform: .ios, id: id) == .runstir)
        #expect(store.origin(platform: .ios, id: UUID().uuidString) == .external)
    }

    @Test("AVD settings may change, but the directory birth identity may not")
    func android() throws {
        let repo = try FixtureRepo()
        let store = DeviceOriginStore(leases: ResourceLeases(directory: repo.url("leases")))
        let avd = try repo.directory("avds/test.avd")
        try repo.write("avds/test.avd/config.ini", "hw.ramSize=2048")
        try store.record(platform: .android, id: "test", directory: avd)
        try repo.write("avds/test.avd/config.ini", "hw.ramSize=4096")
        #expect(store.origin(platform: .android, id: "test", directory: avd) == .runstir)
        let other = try repo.directory("other/test.avd")
        #expect(store.origin(platform: .android, id: "test", directory: other) == .unknown)
        try FileManager.default.setAttributes([.creationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: avd.path)
        #expect(store.origin(platform: .android, id: "test", directory: avd) == .unknown)
        #expect(store.origin(platform: .android, id: "test", directory: nil) == .unknown)
        #expect(store.origin(platform: .android, id: "external", directory: other) == .external)
    }

    @Test("unreadable or unsupported records warn without being overwritten", arguments: ["not json", "{\"version\":2,\"records\":[]}"])
    func corrupt(_ text: String) throws {
        let repo = try FixtureRepo()
        let store = DeviceOriginStore(leases: ResourceLeases(directory: try repo.directory("leases")))
        try Data(text.utf8).write(to: store.file)
        #expect(store.origin(platform: .ios, id: UUID().uuidString) == .unknown)
        #expect(store.warning != nil)
        #expect(throws: (any Error).self) { try store.record(platform: .ios, id: UUID().uuidString) }
        #expect(try String(contentsOf: store.file, encoding: .utf8) == text)
    }

    @Test("origin writes respect the shared lease and preserve existing records")
    func contention() throws {
        let repo = try FixtureRepo()
        let store = DeviceOriginStore(leases: ResourceLeases(directory: repo.url("leases")))
        let id = UUID().uuidString
        try store.record(platform: .ios, id: id)
        let before = try Data(contentsOf: store.file)
        let held = try store.leases.acquire([.destination(store.file)], owner: LeaseOwner(operationId: "other", command: "setup", project: "other"))
        defer { held.release() }
        #expect(throws: ResourceConflict.self) { try store.record(platform: .ios, id: UUID().uuidString) }
        #expect(try Data(contentsOf: store.file) == before)
    }
}

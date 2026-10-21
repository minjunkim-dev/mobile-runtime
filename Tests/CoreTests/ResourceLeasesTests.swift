@testable import Core
import Foundation
import TestSupport
import Testing

@Suite("shared resource leases")
struct ResourceLeasesTests {
    private func store() -> ResourceLeases {
        ResourceLeases(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("runstir-leases-\(UUID().uuidString)"))
    }

    private func owner(_ id: String, project: String = "/work/a") -> LeaseOwner {
        LeaseOwner(operationId: id, command: "up", project: project)
    }

    @Test("a held key reports its owning operation and releases only the keys this operation took")
    func conflictReleasesOnlyOwnKeys() throws {
        let leases = store()
        let held = try leases.acquire([.port(8081)], owner: owner("first", project: "/work/first"))
        let error = try #require(throws: ResourceConflict.self) {
            try leases.acquire([.device(.ios, "A"), .port(8081)], owner: owner("second"))
        }
        #expect(error.key == .port(8081))
        #expect(error.owner == owner("first", project: "/work/first"))
        #expect(error.domainError.message.contains("operation first"))
        #expect(error.domainError.message.contains("/work/first"))
        // The device the failed operation took first is free again; the other owner's port is not.
        _ = try leases.acquire([.device(.ios, "A")], owner: owner("third"))
        #expect(throws: ResourceConflict.self) { try leases.acquire([.port(8081)], owner: owner("third")) }
        withExtendedLifetime(held) {}
    }

    @Test("another process's lock blocks with its owner or as unknown; its exit frees the key despite a live pid in the stale record")
    func crossProcess() throws {
        let leases = store()
        let key = ResourceKey.device(.android, "avd:Pixel")
        try FileManager.default.createDirectory(at: leases.directory, withIntermediateDirectories: true)
        let file = leases.file(key, "lock")
        // This test process is alive, so the record names a live pid after its writer exits.
        let other = owner("other-process", project: "/work/other")
        let holder = try LockHolder(file: file, record: String(decoding: try JSONEncoder().encode(other), as: UTF8.self))
        let held = try #require(throws: ResourceConflict.self) { try leases.acquire([key], owner: owner("mine")) }
        #expect(held.owner == other)
        holder.finish()
        #expect(try String(contentsOf: file, encoding: .utf8).contains("other-process"))
        let lease = try leases.acquire([key], owner: owner("mine"))
        lease.release()

        let anonymous = try LockHolder(file: file, record: "")
        let unknown = try #require(throws: ResourceConflict.self) { try leases.acquire([key], owner: owner("mine")) }
        #expect(unknown.owner == nil)
        #expect(unknown.reason.contains("owner record is missing or unreadable"))
        anonymous.finish()
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test("an app left running by another project's finished run blocks the device until observed stopped")
    func liveAppClaim() async throws {
        let leases = store()
        let device = ResourceKey.device(.ios, "A")
        let first = owner("first", project: "/work/first")
        try leases.record(ResourceClaim(device: device, platform: .ios, handle: "A", appID: "com.first", owner: first))
        let calls = Counter()

        try await leases.check(device: device, project: "/work/first") { _ in calls.add(); return .running("pid 7") }
        #expect(calls.value == 0)
        let running = try await #require(throws: ResourceConflict.self) {
            try await leases.check(device: device, project: "/work/second") { _ in .running("pid 7") }
        }
        #expect(running.owner == first)
        #expect(running.key == .app(.ios, device: "A", appID: "com.first"))
        #expect(running.reason.contains("still running"))
        let unknown = try await #require(throws: ResourceConflict.self) {
            try await leases.check(device: device, project: "/work/second") { _ in .unknown("simctl failed") }
        }
        #expect(unknown.reason.contains("could not be observed: simctl failed"))
        try await leases.check(device: device, project: "/work/second") { claim in
            #expect(claim.appID == "com.first")
            return .stopped
        }
        try await leases.check(device: device, project: "/work/second") { _ in calls.add(); return .running("") }
        #expect(calls.value == 0)
    }

    @Test("an unconfirmed reservation blocks other projects without observing an unknown app")
    func unconfirmedReservation() async throws {
        let leases = store()
        let device = ResourceKey.device(.ios, "A")
        let first = owner("first", project: "/work/first")
        try leases.reserve(device: device, owner: first)
        let calls = Counter()
        try await leases.check(device: device, project: first.project) { _ in calls.add(); return .stopped }
        let conflict = try await #require(throws: ResourceConflict.self) {
            try await leases.check(device: device, project: "/work/second") { _ in calls.add(); return .stopped }
        }
        #expect(conflict.key == device)
        #expect(conflict.owner == first)
        #expect(conflict.reason.contains("unconfirmed"))
        #expect(calls.value == 0)
        #expect(FileManager.default.fileExists(atPath: leases.file(device, "claim").path))
    }

    @Test("a final app record replaces the reservation and supports fresh observation")
    func reservationBecomesAppClaim() async throws {
        let leases = store()
        let device = ResourceKey.device(.android, "avd:Pixel")
        let first = owner("first", project: "/work/first")
        try leases.reserve(device: device, owner: first)
        let claim = ResourceClaim(device: device, platform: .android, handle: "emulator-5554", appID: "com.first", owner: first)
        try leases.record(claim)
        let conflict = try await #require(throws: ResourceConflict.self) {
            try await leases.check(device: device, project: "/work/second") { saved in
                #expect(saved == claim)
                return .running("pid 7")
            }
        }
        #expect(conflict.key == claim.app)
        #expect(conflict.owner == first)
    }

    @Test("legacy app claims remain observable")
    func legacyAppClaim() async throws {
        let leases = store()
        let device = ResourceKey.device(.ios, "A")
        let claim = ResourceClaim(device: device, platform: .ios, handle: "A", appID: "com.first", owner: owner("first"))
        try FileManager.default.createDirectory(at: leases.directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(claim).write(to: leases.file(device, "claim"), options: .atomic)
        let conflict = try await #require(throws: ResourceConflict.self) {
            try await leases.check(device: device, project: "/work/second") { saved in
                #expect(saved == claim)
                return .running("pid 7")
            }
        }
        #expect(conflict.key == claim.app)
        try leases.releaseAfterTeardown(device: device, project: claim.owner.project)
        #expect(!FileManager.default.fileExists(atPath: leases.file(device, "claim").path))
    }

    @Test("verified owned runtime teardown releases only its own claim file", arguments: [false, true])
    func releaseOwnedRuntime(confirmed: Bool) throws {
        let leases = store()
        let device = ResourceKey.device(.android, "avd:Pixel")
        let first = owner("first")
        if confirmed {
            try leases.record(ResourceClaim(device: device, platform: .android, handle: "emulator-5554",
                appID: "com.first", owner: first))
        } else {
            try leases.reserve(device: device, owner: first)
        }
        let held = try leases.acquire([device], owner: first)
        defer { held.release() }
        let lock = leases.file(device, "lock")
        let lockBytes = try Data(contentsOf: lock)
        try leases.releaseAfterTeardown(device: device, project: first.project)
        #expect(!FileManager.default.fileExists(atPath: leases.file(device, "claim").path))
        #expect(try Data(contentsOf: lock) == lockBytes)
        try leases.releaseAfterTeardown(device: device, project: first.project)
    }

    @Test("runtime teardown preserves another project's reservation", arguments: [false, true])
    func releaseOtherRuntime(confirmed: Bool) throws {
        let leases = store()
        let device = ResourceKey.device(.android, "avd:Pixel")
        let first = owner("first", project: "/work/first")
        if confirmed {
            try leases.record(ResourceClaim(device: device, platform: .android, handle: "emulator-5554",
                appID: "com.first", owner: first))
        } else {
            try leases.reserve(device: device, owner: first)
        }
        let file = leases.file(device, "claim")
        let data = try Data(contentsOf: file)
        #expect(throws: ResourceConflict.self) {
            try leases.releaseAfterTeardown(device: device, project: "/work/other")
        }
        #expect(try Data(contentsOf: file) == data)
    }

    @Test("runtime teardown preserves an unreadable claim")
    func releaseUnreadableRuntime() throws {
        let leases = store()
        let device = ResourceKey.device(.android, "avd:Pixel")
        try FileManager.default.createDirectory(at: leases.directory, withIntermediateDirectories: true)
        let file = leases.file(device, "claim")
        let data = Data("unreadable fixture".utf8)
        try data.write(to: file)
        #expect(throws: ResourceConflict.self) {
            try leases.releaseAfterTeardown(device: device, project: "/work/a")
        }
        #expect(try Data(contentsOf: file) == data)
    }

    @Test("a claim for a different device stays unknown without observing or deleting it")
    func mismatchedDeviceClaim() async throws {
        let leases = store()
        let device = ResourceKey.device(.ios, "A")
        let claim = ResourceClaim(device: .device(.ios, "B"), platform: .ios, handle: "B", appID: "com.first", owner: owner("first"))
        try FileManager.default.createDirectory(at: leases.directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(claim)
        let file = leases.file(device, "claim")
        try data.write(to: file, options: .atomic)
        let conflict = try await #require(throws: ResourceConflict.self) {
            try await leases.check(device: device, project: "/work/second") { _ in
                Issue.record("An inconsistent claim must not observe an app")
                return .stopped
            }
        }
        #expect(conflict.key == device)
        #expect(conflict.owner == nil)
        #expect(try Data(contentsOf: file) == data)
        #expect(throws: ResourceConflict.self) {
            try leases.releaseAfterTeardown(device: device, project: claim.owner.project)
        }
        #expect(try Data(contentsOf: file) == data)
    }

    @Test("a failed final write preserves the unconfirmed reservation")
    func failedFinalWriteKeepsReservation() async throws {
        let leases = store()
        let device = ResourceKey.device(.ios, "A")
        let first = owner("first", project: "/work/first")
        try leases.reserve(device: device, owner: first)
        let claim = ResourceClaim(device: device, platform: .ios, handle: "A", appID: "com.first", owner: first)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: leases.directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: leases.directory.path) }
        #expect(throws: (any Error).self) { try leases.record(claim) }
        let conflict = try await #require(throws: ResourceConflict.self) {
            try await leases.check(device: device, project: "/work/second") { _ in
                Issue.record("An unconfirmed reservation must not observe an app")
                return .stopped
            }
        }
        #expect(conflict.owner == first)
        #expect(conflict.reason.contains("unconfirmed"))
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func add() { lock.withLock { count += 1 } }
}

/// A separate OS process that holds a real flock until its stdin closes.
private final class LockHolder {
    private let process = Process()
    private let input = Pipe()

    init(file: URL, record: String) throws {
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-e", """
            use Fcntl qw(:flock); open(my $f, "+>>", $ARGV[0]) or die; flock($f, LOCK_EX|LOCK_NB) or die "busy";
            if (length $ARGV[1]) { truncate($f, 0); syswrite($f, $ARGV[1]); }
            $| = 1; print "locked\n"; <STDIN>;
            """, file.path, record]
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        let line = String(decoding: output.fileHandleForReading.availableData, as: UTF8.self)
        guard line == "locked\n" else { throw CocoaError(.fileLocking) }
    }

    func finish() {
        try? input.fileHandleForWriting.close()
        process.waitUntilExit()
    }
}

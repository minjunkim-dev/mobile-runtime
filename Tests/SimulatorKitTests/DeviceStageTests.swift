import Core
import Foundation
import TestSupport
import Testing

@testable import SimulatorKit

private let developerDirectory = "/Applications/Xcode.app/Contents/Developer"

/// The fixtures are captured output, so their udids belong to the machine that
/// captured them: tests read the list rather than hard-coding one.
private func listed(in deviceList: String) throws -> [[String: Any]] {
    let json = try JSONSerialization.jsonObject(with: Data(deviceList.utf8)) as? [String: Any]
    return (json?["devices"] as? [String: [[String: Any]]] ?? [:]).values.flatMap { $0 }
}

private func udids(in deviceList: String) throws -> [String] {
    try listed(in: deviceList).compactMap { $0["udid"] as? String }
}

private func udid(of name: String, in deviceList: String) throws -> String {
    let match = try listed(in: deviceList).first { $0["name"] as? String == name }
    return try #require(match?["udid"] as? String)
}

/// The captured list as simctl prints it once that device has booted. Booting changes
/// one field, so the fixture stays the machine's real output rather than a second
/// capture of a state this machine was not asked to enter.
private func booted(_ udid: String, in deviceList: String) throws -> String {
    var json = try #require(
        try JSONSerialization.jsonObject(with: Data(deviceList.utf8)) as? [String: Any]
    )
    var devices = try #require(json["devices"] as? [String: [[String: Any]]])
    for (runtime, listed) in devices {
        devices[runtime] = listed.map { device in
            var device = device
            if device["udid"] as? String == udid { device["state"] = "Booted" }
            return device
        }
    }
    json["devices"] = devices
    return String(decoding: try JSONSerialization.data(withJSONObject: json), as: UTF8.self)
}

private func runner(
    devices: String,
    deviceTypes: String? = nil,
    boot: FakeProcessRunner.Response = .ok("")
) throws -> FakeProcessRunner {
    var responses: [String: FakeProcessRunner.Response] = [
        "xcode-select -p": .ok(developerDirectory + "\n"),
        "xcodebuild -version": .ok("Xcode 26.6\nBuild version 17F113\n"),
        "xcrun simctl list devices -j": .ok(devices),
    ]
    for udid in try udids(in: devices) {
        responses["xcrun simctl bootstatus \(udid) -b"] = boot
    }
    if let deviceTypes {
        responses["xcrun simctl list devicetypes -j"] = .ok(deviceTypes)
    }
    return FakeProcessRunner(responses: responses)
}

@discardableResult
private func run(
    _ runner: FakeProcessRunner,
    declared: String? = nil,
    lookup: MatrixLookup? = nil,
    context: inout UpContext
) async throws -> StageOutcome {
    let stage = DeviceStage(
        declared: declared,
        lookup: lookup,
        runner: runner,
        locator: XcodeLocator(runner: runner, developerDirOverride: nil)
    )
    return try await stage.run(&context)
}

private func bootCommands(_ runner: FakeProcessRunner) -> [String] {
    runner.log.all.map(\.description).filter { $0.contains("bootstatus") }
}

@Suite("device stage")
struct DeviceStageTests {
    /// A declaration outranks a booted simulator: the project said which device it
    /// wants, and a device someone left running is not an answer to that.
    @Test("mobile.yml's device wins, and gets booted")
    func declared() async throws {
        let devices = try Fixture.text("simctl-list-devices.stdout.json")
        let runner = try runner(devices: devices)
        var context = UpContext()

        let outcome = try await run(runner, declared: "iPhone 16 Pro", context: &context)

        #expect(outcome.status == .pass)
        #expect(outcome.detail == "iPhone 16 Pro on iOS 26.5")
        #expect(context.device?.name == "iPhone 16 Pro")
        #expect(context.device?.udid == (try udid(of: "iPhone 16 Pro", in: devices)))
        #expect(context.device?.runtime == "26.5")
        #expect(bootCommands(runner) == ["xcrun simctl bootstatus \(try udid(of: "iPhone 16 Pro", in: devices)) -b"])
    }

    /// Nothing declared and something already running: use it. Booting a second
    /// simulator to do what the running one can do is the slowest possible answer.
    @Test("a booted simulator is reused, and not booted again")
    func bootedReused() async throws {
        let devices = try Fixture.text("simctl-list-devices.stdout.json")
        let runner = try runner(devices: devices)
        var context = UpContext()

        let outcome = try await run(runner, context: &context)

        #expect(outcome.status == .skipped)
        // The device's own name carries the runtime, so the line does not repeat it.
        #expect(outcome.detail == "iPhone 17 Pro - iOS 26.5 is already booted")
        #expect(context.device?.name == "iPhone 17 Pro - iOS 26.5")
        #expect(bootCommands(runner).isEmpty)
    }

    /// Newest runtime, then the plainest model of the newest generation — `iPhone 16`
    /// over `iPhone 16 Pro`. Any rule would do; a stable one is what matters.
    @Test("with nothing declared and nothing booted, the newest iPhone is chosen")
    func automatic() async throws {
        let devices = try Fixture.text("simctl-list-devices-shutdown.stdout.json")
        let runner = try runner(devices: devices)
        var context = UpContext()

        let outcome = try await run(runner, context: &context)

        #expect(outcome.status == .pass)
        #expect(context.device?.name == "iPhone 16")
        #expect(bootCommands(runner) == ["xcrun simctl bootstatus \(try udid(of: "iPhone 16", in: devices)) -b"])
    }

    /// mobile creates nothing. The command is measured — the runtime comes from the
    /// list simctl just printed, the device type from the ones this Xcode ships.
    @Test("no simulators at all is an error carrying a create command")
    func noCandidates() async throws {
        let runner = try runner(
            devices: Fixture.text("simctl-list-devices-none.stdout.json"),
            deviceTypes: Fixture.text("simctl-list-devicetypes.stdout.json")
        )
        var context = UpContext()

        let error = await #expect(throws: DomainError.self) {
            try await run(runner, context: &context)
        }

        #expect(error?.summary == "no iPhone simulator on this machine to boot")
        #expect(
            error?.remediation.command == "xcrun simctl create \"iPhone 17\" "
                + "com.apple.CoreSimulator.SimDeviceType.iPhone-17 "
                + "com.apple.CoreSimulator.SimRuntime.iOS-26-5"
        )
        #expect(context.device == nil)
    }

    /// The rule the repo keeps re-learning: no command beats a wrong one. Without the
    /// device type list there is nothing to name, so the line says what to do instead.
    @Test("a create command is offered only when the device type could be read")
    func noCandidatesWithoutDeviceTypes() async throws {
        let runner = try runner(devices: Fixture.text("simctl-list-devices-none.stdout.json"))
        var context = UpContext()

        let error = await #expect(throws: DomainError.self) {
            try await run(runner, context: &context)
        }

        #expect(error?.remediation.command == nil)
        #expect(error?.remediation.summary.contains("xcrun simctl create") == true)
    }

    @Test("a simulator that will not boot stops the run with what simctl said")
    func bootFails() async throws {
        let runner = try runner(
            devices: Fixture.text("simctl-list-devices-shutdown.stdout.json"),
            boot: .failed(164, "Unable to boot device in current state: Creating\n")
        )
        var context = UpContext()

        let error = await #expect(throws: DomainError.self) {
            try await run(runner, context: &context)
        }

        #expect(error?.observed == "Unable to boot device in current state: Creating")
        #expect(error?.remediation.command?.hasPrefix("xcrun simctl boot ") == true)
    }

    /// Re-running `up` on a machine it already set up must not restart the simulator.
    /// The second run reads what simctl says after the first one's boot, which is the
    /// same capture with one field moved on — the state is the only thing booting
    /// changes about a device.
    @Test("the boot a first run did is skipped by the second")
    func idempotent() async throws {
        let shutdown = try Fixture.text("simctl-list-devices-shutdown.stdout.json")
        let chosen = try udid(of: "iPhone 16", in: shutdown)
        let first = try runner(devices: shutdown)
        let second = try runner(devices: try booted(chosen, in: shutdown))

        var before = UpContext()
        var after = UpContext()
        let one = try await run(first, context: &before)
        let two = try await run(second, context: &after)

        #expect(one.status == .pass)
        #expect(two.status == .skipped)
        #expect(before.device == after.device)
        #expect(bootCommands(first) == ["xcrun simctl bootstatus \(chosen) -b"])
        #expect(bootCommands(second).isEmpty)
    }

    /// simctl not answering is the machine's problem, not the project's, so it must
    /// not be a `DomainError` — that would put it on exit 1 beside things a developer
    /// can fix in their repo.
    @Test("simctl refusing to list is a tool failure, not a project one")
    func simctlUnavailable() async throws {
        var runner = try runner(devices: Fixture.text("simctl-list-devices-none.stdout.json"))
        runner.responses["xcrun simctl list devices -j"] = .failed(
            72, try Fixture.text("simctl-commandlinetools.stderr.txt")
        )
        var context = UpContext()

        let error = await #expect(throws: SimctlUnavailable.self) {
            try await run(runner, context: &context)
        }

        #expect(error?.description.contains("xcrun simctl list devices -j") == true)
        #expect(context.device == nil)
    }

    /// `config.values` grades this first, so up only reaches it when the file changed
    /// under a running command — but a stage that picks a device has to say what it
    /// could not find rather than boot something else.
    @Test("a declared device that is not installed stops the run")
    func declaredMissing() async throws {
        let runner = try runner(devices: Fixture.text("simctl-list-devices.stdout.json"))
        var context = UpContext()

        let error = await #expect(throws: DomainError.self) {
            try await run(runner, declared: "iPhone 15 Ultra", context: &context)
        }

        #expect(error?.summary.contains("iPhone 15 Ultra") == true)
        #expect(error?.remediation.command == "xcrun simctl list devices available")
    }
}

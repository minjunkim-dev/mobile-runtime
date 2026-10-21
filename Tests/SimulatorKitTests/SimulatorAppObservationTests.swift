import Core
import Foundation
import SimulatorKit
import TestSupport
import Testing

@Suite("Simulator live app observation")
struct SimulatorAppObservationTests {
    private let list = "xcrun simctl spawn A launchctl list"

    private func observe(_ response: FakeProcessRunner.Response) async -> ClaimObservation {
        let runner = FakeProcessRunner(responses: ["xcode-select -p": .ok("/test/Xcode"), list: response])
        return try! await simulatorAppObservation(udid: "A", bundleID: "com.other.App", runner: runner,
            locator: XcodeLocator(runner: runner))
    }

    @Test("only a live pid on the app's job is running; a shut-down Simulator is stopped; other failures stay unknown")
    func observation() async {
        #expect(await observe(.ok("PID\tStatus\tLabel\n4242\t0\tUIKitApplication:com.other.App[a1][rb-legacy]\n"))
            == .running("com.other.App pid 4242 on A"))
        #expect(await observe(.ok("PID\tStatus\tLabel\n-\t0\tUIKitApplication:com.other.App[a1][rb-legacy]\n")) == .stopped)
        #expect(await observe(.ok("PID\tStatus\tLabel\n-\t0\tUIKitApplication:com.other.App[a1][rb-legacy]\n55\t0\tUIKitApplication:com.other.App[b2][rb-legacy]\n"))
            == .running("com.other.App pid 55 on A"))
        #expect(await observe(.ok("PID\tStatus\tLabel\n77\t0\tUIKitApplication:com.other.AppExtra[a1][rb-legacy]\n")) == .stopped)
        // Recorded from simctl spawn on a shut-down iOS 27 Simulator.
        #expect(await observe(.failed(149, """
            An error was encountered processing the command (domain=com.apple.CoreSimulator.SimError, code=405):
            Process spawn via launchd failed because device is not booted.
            Underlying error (domain=com.apple.SimLaunchHostService.RequestError, code=3):
            	Bad or unknown session: com.apple.CoreSimulator.SimDevice.A
            """)) == .stopped)
        #expect(await observe(.failed(148, "Invalid device: A")) == .stopped)
        #expect(await observe(.failed(1, "CoreSimulatorService connection became invalid")) == .unknown("CoreSimulatorService connection became invalid"))
    }

    @Test("cancellation during observation stays a cancellation, not an unknown owner")
    func cancellation() async {
        let runner = FakeProcessRunner(responses: ["xcode-select -p": .ok("/test/Xcode")], failures: [list: CancellationError()])
        await #expect(throws: CancellationError.self) {
            try await simulatorAppObservation(udid: "A", bundleID: "com.other.App", runner: runner, locator: XcodeLocator(runner: runner))
        }
    }
}

import Core
import Foundation
import Testing

@testable import SimulatorKit

/// The one test that talks to the real simctl. Every other SimulatorKit test feeds
/// captured output to a fake, so a new Xcode or runner image that changes simctl
/// passes them all. The manual `Simulator smoke` workflow sets this variable to the
/// app `scripts/build-simulator-smoke-app.sh` built; every other run skips the suite.
private let smokeApp = ProcessInfo.processInfo.environment["RUNSTIR_SIMULATOR_SMOKE_APP"]

@Suite(.enabled(if: smokeApp != nil, "RUNSTIR_SIMULATOR_SMOKE_APP is not set"))
struct RealSimulatorSmokeTests {
    @Test func upStagesDriveTheRealSimulator() async throws {
        let appPath = try #require(smokeApp)
        let bundleID = try #require(Bundle(path: appPath)?.bundleIdentifier)
        let runner = SystemProcessRunner()
        let locator = XcodeLocator(runner: runner)
        let environment = await locator.pinnedEnvironment()

        // The parsers the fakes feed with captured JSON, fed with this Xcode's.
        #expect(try await timed("simulator.daemon") {
            try await SimulatorDaemonCheck(runner: runner, locator: locator).run().status
        } == .pass)
        let runtimes = try #require(SimctlRuntimeList.decode(try await timed("list runtimes") {
            try await runner.run(SimctlRuntimeList.command(environment: environment)).standardOutput
        }))
        let runtime = try #require(
            runtimes.runtimes.filter { $0.isIOS && $0.isAvailable }
                .compactMap { SemanticVersion($0.version) }.max()
        )
        let types = try #require(SimctlDeviceTypeList.decode(try await timed("list devicetypes") {
            try await runner.run(SimctlDeviceTypeList.command(environment: environment)).standardOutput
        }))
        #expect(types.newestPhone(runningOn: runtime) != nil)

        var context = UpContext()
        let device = try await timed("device") {
            try await DeviceStage(declared: nil, lookup: nil, runner: runner, locator: locator).run(&context)
        }
        let selected = try #require(context.device)
        print("smoke: device \(device.status.rawValue) — \(selected.name) iOS \(selected.runtime) \(selected.udid)")
        let project = FileManager.default.temporaryDirectory
            .appendingPathComponent("runstir-simulator-smoke-\(UUID().uuidString)")
        let logs = RunLogs(project: project)

        do {
            let list = try #require(SimctlDeviceList.decode(
                try await runner.run(SimctlDeviceList.command(environment: environment)).standardOutput
            ))
            #expect(list.simulators.contains { $0.udid == selected.udid && $0.isBooted })

            context.product = BuiltProduct(path: appPath, bundleIdentifier: bundleID)
            let install = try await timed("install") {
                try await InstallStage(runner: runner, locator: locator, logs: logs).run(&context)
            }
            #expect(install.status == .pass)
            let launch = try await timed("launch") {
                try await LaunchStage(project: project, runner: runner, locator: locator).run(&context)
            }
            #expect(launch.status == .pass)
            #expect((context.appPid ?? 0) > 0)

            let stopped = await timed("app teardown") {
                await AppTeardown(logs: logs, runner: runner, locator: locator).run()
            }
            #expect(stopped.status == .stopped)
        } catch {
            _ = await timed("clean up") { await cleanUp(selected, bundleID, bootedHere: device.status == .pass, runner, environment, logs) }
            throw error
        }
        #expect(
            await timed("clean up") {
                await cleanUp(selected, bundleID, bootedHere: device.status == .pass, runner, environment, logs)
            },
            "simctl shutdown failed on the simulator this test booted"
        )
    }

    /// Each step's time on stdout, failed ones included: a cold runner's first boot and
    /// launch are slow, and a timeout alone does not say which step spent the minutes.
    private func timed<T>(_ step: String, _ body: () async throws -> T) async rethrows -> T {
        let start = ContinuousClock.now
        defer { print("smoke: \(step) took \(start.duration(to: .now).formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 1))))") }
        return try await body()
    }

    /// The fixture app is this test's own, so it goes. The simulator goes only when this
    /// test booted it: one that was already running belongs to whoever started it.
    /// - Returns: false only when the simulator this test booted did not shut down.
    private func cleanUp(
        _ device: SelectedDevice, _ bundleID: String, bootedHere: Bool,
        _ runner: SystemProcessRunner, _ environment: [String: String], _ logs: RunLogs
    ) async -> Bool {
        _ = try? await runner.run(ProcessCommand(
            "xcrun", ["simctl", "uninstall", device.udid, bundleID], environment: environment, timeout: .seconds(60)
        ))
        defer { try? FileManager.default.removeItem(at: logs.directory) }
        guard bootedHere else { return true }
        let shutdown = try? await runner.run(ProcessCommand(
            "xcrun", ["simctl", "shutdown", device.udid], environment: environment, timeout: .seconds(60)
        ))
        return shutdown?.terminationStatus.isSuccess == true
    }
}

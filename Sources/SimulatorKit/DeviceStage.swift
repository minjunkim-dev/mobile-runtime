import Core
import Foundation

/// simctl could not be asked. Not a `DomainError`: nothing about the project is
/// wrong, so it must not land on the project's exit code.
struct SimctlUnavailable: Error, CustomStringConvertible {
    let description: String
}

/// `device` — pick a simulator and make sure it is running. What mobile.yml declared,
/// else whatever is already booted, else the newest iPhone this machine has.
///
/// It never creates one. A machine with no simulators gets the `simctl create` line
/// and stops there: creating devices behind someone's back is how a tool ends up
/// owning a machine's simulator set.
public struct DeviceStage: Stage {
    public let id = "device"

    /// `ios.device` from mobile.yml. Already graded by `config.values`, which is why
    /// reaching a failure here means the file changed under a running command.
    private let declared: String?
    private let lookup: MatrixLookup?
    private let runner: any ProcessRunner
    private let locator: XcodeLocator

    public init(
        declared: String?,
        lookup: MatrixLookup?,
        runner: any ProcessRunner,
        locator: XcodeLocator
    ) {
        self.declared = declared
        self.lookup = lookup
        self.runner = runner
        self.locator = locator
    }

    public func run(_ context: inout UpContext) async throws -> StageOutcome {
        let environment = await locator.pinnedEnvironment()
        let list = try await devices(environment)
        let selector = SimulatorSelector(simulators: list.simulators, lookup: lookup)

        let simulator: SimctlDeviceList.Simulator
        switch selector.resolve(declared: declared) {
        case .success(let resolved):
            simulator = resolved
        case .failure(let miss):
            throw DomainError(
                summary: miss.observed,
                remediation: miss.remediation(
                    availableNames: selector.availableNames,
                    create: miss == .noPhoneInstalled ? await createCommand(list, environment) : nil
                )
            )
        }

        // Written before the boot: a simulator that fails to come up is still the one
        // this run chose, and the failure names it.
        context.device = SelectedDevice(
            name: simulator.name, udid: simulator.udid, runtime: simulator.runtimeText
        )

        // Xcode names a duplicated device `iPhone 17 Pro - iOS 26.5`, which already
        // carries the runtime — saying it twice reads like a bug on the progress line.
        let name = simulator.name.contains(simulator.runtimeText)
            ? simulator.name
            : "\(simulator.name) on iOS \(simulator.runtimeText)"
        // Not `bootstatus`-is-idempotent-so-run-it-anyway: a second `up` should show
        // that it had nothing to do, and `skipped` is the word for that.
        guard !simulator.isBooted else { return .skipped("\(name) is already booted") }

        try await boot(simulator, environment)
        return .pass(name)
    }

    private func devices(_ environment: [String: String]) async throws -> SimctlDeviceList {
        let command = SimctlDeviceList.command(environment: environment)
        let result = try await runner.run(command)
        guard result.terminationStatus.isSuccess, let list = SimctlDeviceList.decode(result.standardOutput) else {
            throw SimctlUnavailable(
                description: "`\(command.description)` did not list the simulators — "
                    + (result.standardError.firstLine ?? "its output was not a device list")
            )
        }
        return list
    }

    /// `bootstatus -b` boots and then waits for the device to finish booting, which is
    /// the state the next stage needs — `boot` alone returns while it is still coming
    /// up. Already-booted devices never reach here, so its idempotency is a safety net
    /// rather than the design.
    private func boot(_ simulator: SimctlDeviceList.Simulator, _ environment: [String: String]) async throws {
        let command = ProcessCommand(
            "xcrun", ["simctl", "bootstatus", simulator.udid, "-b"],
            environment: environment,
            timeout: .seconds(120)
        )
        let result = try await runner.run(command)
        guard result.terminationStatus.isSuccess else {
            throw DomainError(
                summary: "\(simulator.name) did not boot",
                observed: result.standardError.firstLine ?? result.standardOutput.firstLine
                    ?? "`\(command.description)` failed",
                remediation: Remediation(
                    summary: "Boot it by hand to see what the Simulator says. A device wedged in "
                        + "`Creating` or `Booting` is erased with `xcrun simctl erase \(simulator.udid)`.",
                    command: "xcrun simctl boot \(simulator.udid)"
                )
            )
        }
    }

    /// Measured, never assumed: the runtime is one simctl just printed — the key is
    /// there even when it holds no devices — and the device type is one this Xcode
    /// ships. If either cannot be read the caller gets no command at all.
    private func createCommand(_ list: SimctlDeviceList, _ environment: [String: String]) async -> String? {
        guard let runtime = list.newestRuntime(clearing: lookup),
            let result = try? await runner.run(SimctlDeviceTypeList.command(environment: environment)),
            result.terminationStatus.isSuccess,
            let type = SimctlDeviceTypeList.decode(result.standardOutput)?
                .newestPhone(runningOn: runtime.version)
        else { return nil }
        return "xcrun simctl create \"\(type.name)\" \(type.identifier) \(runtime.identifier)"
    }
}

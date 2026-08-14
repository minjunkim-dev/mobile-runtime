import Core
import Foundation

/// `simulator.daemon` — is CoreSimulator answering? When the daemon is wedged
/// every simctl call below it fails without saying why.
public struct SimulatorDaemonCheck: Check {
    public let id = "simulator.daemon"
    public let category = "iOS Simulator"
    public let title = "CoreSimulator daemon responds to simctl"
    public let dependsOn = ["xcode.installed"]

    private static let restart = Remediation(
        summary: "Restart the CoreSimulator service, then re-run mobile doctor.",
        command: "killall -9 com.apple.CoreSimulator.CoreSimulatorService"
    )

    private let runner: any ProcessRunner
    private let locator: XcodeLocator

    public init(runner: any ProcessRunner, locator: XcodeLocator) {
        self.runner = runner
        self.locator = locator
    }

    public func run() async throws -> CheckOutcome {
        let result = try await runner.run(
            SimctlRuntimeList.command(environment: await locator.pinnedEnvironment())
        )

        guard result.terminationStatus.isSuccess else {
            return .error(
                observed: result.standardError.firstLine ?? "simctl exited with \(result.terminationStatus)",
                required: "simctl responds to `simctl list runtimes -j`",
                remediation: Self.restart
            )
        }
        guard let list = SimctlRuntimeList.decode(result.standardOutput) else {
            return .error(
                observed: "simctl returned output that is not a runtime list",
                required: "simctl responds to `simctl list runtimes -j`",
                remediation: Self.restart
            )
        }

        let available = list.runtimes.filter(\.isAvailable).count
        return .pass(
            observed: "CoreSimulator responded — \(available) of \(list.runtimes.count) runtimes available",
            required: "simctl responds to `simctl list runtimes -j`"
        )
    }
}

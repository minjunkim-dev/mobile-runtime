import Core
import Foundation

/// `install` — `xcrun simctl install`, straight over whatever is already on the
/// device.
///
/// No uninstall first: simctl replaces the bundle in place, and removing the app
/// would take its container with it. A developer's logged-in session and seeded
/// database are not this stage's to throw away, and "delete it and try again" is
/// the manual step `up` exists to retire.
public struct InstallStage: Stage {
    public let id = "install"

    private let runner: any ProcessRunner
    private let locator: XcodeLocator
    /// Where the install record goes — next to this run's logs.
    private let logs: RunLogs

    public init(runner: any ProcessRunner, locator: XcodeLocator, logs: RunLogs) {
        self.runner = runner
        self.locator = locator
        self.logs = logs
    }

    public func run(_ context: inout UpContext) async throws -> StageOutcome {
        let (device, product) = try context.built(for: id)

        let command = ProcessCommand(
            "xcrun", ["simctl", "install", device.udid, product.path],
            environment: await locator.pinnedEnvironment(),
            timeout: .seconds(120)
        )
        let result = try await runner.run(command)
        guard result.terminationStatus.isSuccess else {
            throw DomainError(
                summary: "the app could not be installed on \(device.name)",
                observed: result.combinedOutput.lastLines(5),
                remediation: Remediation(
                    summary: "Run the install by hand to see the whole message — simctl says "
                        + "which of the two it could not find, the device or the bundle, and "
                        + "an installer that refuses says why in more lines than fit here.",
                    command: command.description
                )
            )
        }
        // The first moment both halves of "which app, on which device" are settled,
        // and the only path `down` has to them later. Best effort: a record that
        // could not be written costs a `down` that skips the app, and losing that is
        // not worth failing an install that worked.
        InstallRecord(udid: device.udid, bundleId: product.bundleIdentifier).write(to: logs)

        return .pass(product.bundleIdentifier)
    }
}

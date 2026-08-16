import Core
import Foundation

/// `down`'s app half: terminate the app this project installed, on the simulator it
/// was installed on, as the install record says.
///
/// Nothing is uninstalled and the record is not deleted — `down` stops the app, and
/// the app is still installed afterwards, which is what the record still describes.
public struct AppTeardown: Sendable {
    public static let id = "app"

    private let logs: RunLogs
    private let runner: any ProcessRunner
    private let locator: XcodeLocator

    public init(logs: RunLogs, runner: any ProcessRunner, locator: XcodeLocator) {
        self.logs = logs
        self.runner = runner
        self.locator = locator
    }

    public func run() async -> TeardownItem {
        guard let record = InstallRecord.read(from: logs) else {
            return .skipped(Self.id, "no install record — nothing to stop")
        }

        let result = try? await runner.run(
            ProcessCommand(
                "xcrun", ["simctl", "terminate", record.udid, record.bundleId],
                environment: await locator.pinnedEnvironment(),
                timeout: .seconds(30)
            )
        )
        // Every failure ignored, the runner's own included — `launch` already made
        // this judgement for the same command: an app that was not running is not a
        // failure to stop it, and simctl says so with a paragraph and exit 3.
        //
        // What simctl said, rather than why we think it said it: "not running" is the
        // usual reason and not the only one, and a guess printed as a fact is the
        // habit the `unidentifiable` verdict exists to break.
        guard let result, result.terminationStatus.isSuccess else {
            let said = result?.combinedOutput.lastLines(1) ?? "simctl could not be run"
            return .skipped(Self.id, "\(record.bundleId) was not stopped — \(said)")
        }
        return .stopped(Self.id, "\(record.bundleId) on \(record.udid)")
    }
}

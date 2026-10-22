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
    private let leases: ResourceLeases
    private let ownerProject: String?

    public init(logs: RunLogs, runner: any ProcessRunner, locator: XcodeLocator,
                leases: ResourceLeases = .user, ownerProject: String? = nil) {
        self.logs = logs
        self.runner = runner
        self.locator = locator
        self.leases = leases
        self.ownerProject = ownerProject
    }

    public func run() async -> TeardownItem {
        let record: InstallRecord
        do {
            guard let saved = try InstallRecord.read(from: logs, leases: leases, ownerProject: ownerProject) else {
                return .skipped(Self.id, "no install record — nothing to stop")
            }
            record = saved
        } catch {
            return .blocked(Self.id, error as? DomainError ?? DomainError(
                summary: "The install record could not be confirmed.",
                remediation: Remediation(summary: "Inspect the existing record. Existing apps were preserved.")))
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

/// Whether an app a finished `up` left on a Simulator is still running there. A
/// shut-down Simulator runs nothing; any other failure stays unknown.
public func simulatorAppObservation(udid: String, bundleID: String, runner: any ProcessRunner,
                                    locator: XcodeLocator) async throws -> ClaimObservation {
    let result: ProcessResult
    do {
        result = try await runner.run(ProcessCommand("xcrun", ["simctl", "spawn", udid, "launchctl", "list"],
            environment: await locator.pinnedEnvironment(), timeout: .seconds(30)))
    } catch let error where !(error is CancellationError) {
        return .unknown("simctl could not be run: \(error)")
    }
    guard result.terminationStatus.isSuccess else {
        // simctl 27: a shut-down Simulator exits 149, a deleted one exits 148.
        let said = result.combinedOutput
        return said.contains("device is not booted") || said.contains("Invalid device: \(udid)") ? .stopped : .unknown(said.lastLines(1))
    }
    // launchctl keeps a job for an exited app; only a numeric pid column is a live process.
    let pid = result.standardOutput.split(whereSeparator: \.isNewline)
        .map { $0.split(separator: "\t") }
        .first { $0.count == 3 && $0[2].hasPrefix("UIKitApplication:\(bundleID)[") && Int32($0[0]) != nil }
        .map { $0[0] }
    guard let pid else { return .stopped }
    return .running("\(bundleID) pid \(pid) on \(udid)")
}

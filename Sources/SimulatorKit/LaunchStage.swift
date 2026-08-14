import Core
import Foundation

/// `launch` — terminate, then launch, on every run.
///
/// The relaunch is the guarantee `up` sells: when the command returns, what is on
/// the screen is the code it just built. `simctl launch` on an app that is already
/// running hands back the old instance's pid without restarting it, so without the
/// terminate the promise would hold for the bundle on disk and quietly break on the
/// screen — the worst shape a bug can take, because nothing looks wrong.
public struct LaunchStage: Stage {
    public let id = "launch"

    private let runner: any ProcessRunner
    private let locator: XcodeLocator
    /// The fixed wait after launch returns. `simctl launch` answers when the app has
    /// been asked to start, not when it has drawn anything, and a command that hands
    /// the terminal back with a blank simulator reads as a failure.
    ///
    /// A wall-clock guess is what one writes in the absence of a signal. Replace it
    /// the day there is one to poll — a first frame, a bundle request Metro logs —
    /// rather than by tuning the number. Injected, not a constant, so tests spend
    /// nothing on it and a slow machine can be given more.
    ///
    /// It is served inside the stage, so `launch`'s elapsed time includes it. That is
    /// the honest reading: the wait is work this stage does, and hiding it would make
    /// the one number that says how long `up` took disagree with the clock.
    private let settle: Duration

    /// One source of truth for the wait, shared with `iOSUpStages`.
    public static let defaultSettle: Duration = .seconds(3)

    public init(
        runner: any ProcessRunner,
        locator: XcodeLocator,
        settle: Duration = LaunchStage.defaultSettle
    ) {
        self.runner = runner
        self.locator = locator
        self.settle = settle
    }

    public func run(_ context: inout UpContext) async throws -> StageOutcome {
        let (device, product) = try context.built(for: id)
        let environment = await locator.pinnedEnvironment()

        // Every failure ignored, the runner's own included: on a first run there is
        // nothing to terminate, and simctl says so with a paragraph and exit 3.
        _ = try? await runner.run(
            ProcessCommand(
                "xcrun", ["simctl", "terminate", device.udid, product.bundleIdentifier],
                environment: environment,
                timeout: .seconds(30)
            )
        )

        let command = ProcessCommand(
            "xcrun", ["simctl", "launch", device.udid, product.bundleIdentifier],
            environment: environment,
            timeout: .seconds(60)
        )
        let result = try await runner.run(command)
        guard result.terminationStatus.isSuccess else {
            throw DomainError(
                summary: "\(product.bundleIdentifier) did not start on \(device.name)",
                observed: result.combinedOutput.lastLines(5),
                remediation: Remediation(
                    summary: "Run it by hand to see the whole message. An app that installs and "
                        + "then refuses to start is usually one built for another platform, or "
                        + "one whose deployment target is above this runtime.",
                    command: command.description
                )
            )
        }

        // simctl answers `com.example.MyApp: 3538`. Reporting the pid is half of what
        // this stage is for, so an answer without one is a broken tool, not a broken
        // project — it must not land on the project's exit code.
        guard let pid = Self.pid(in: result.standardOutput) else {
            throw ToolUnavailable(
                description: "`\(command.description)` started the app without printing a pid — "
                    + (result.standardOutput.firstLine ?? "it printed nothing")
            )
        }
        context.appPid = pid

        try await Task.sleep(for: settle)
        return .pass("\(product.bundleIdentifier) — pid \(pid)")
    }

    /// The pid is what a line ends with. Read from the end rather than by splitting on
    /// the colon: a bundle id is dots and dashes, but the tail is the number whatever
    /// simctl decides to print in front of it. Every line is offered, so a future
    /// simctl that prints a notice first still gets its pid read.
    private static func pid(in output: String) -> Int32? {
        output.split(separator: "\n").lazy
            .compactMap { $0.split(separator: " ").last.flatMap { Int32($0) } }
            .first
    }
}

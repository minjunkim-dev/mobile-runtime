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
    private let metroRunner: any ProcessRunner
    private let locator: XcodeLocator
    private let project: URL
    /// The upper bound for observing the bundle after the app asks Metro for it.
    /// Injected so tests do not wait, while a first bundle gets enough time on a cold
    /// machine to finish honestly.
    private let readinessWait: Duration

    public static let defaultReadinessWait: Duration = .seconds(120)

    public init(
        project: URL,
        runner: any ProcessRunner,
        metroRunner: (any ProcessRunner)? = nil,
        locator: XcodeLocator,
        readinessWait: Duration = LaunchStage.defaultReadinessWait
    ) {
        self.project = project
        self.runner = runner
        self.metroRunner = metroRunner ?? runner
        self.locator = locator
        self.readinessWait = readinessWait
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

        let detail = "\(product.bundleIdentifier) — pid \(pid)"
        guard let metro = context.metro else { return .pass(detail) }
        let ready = await MetroReadiness(
            project: project, runner: metroRunner, timeout: readinessWait
        ).wait(for: metro)
        if ready { return .pass(detail) }

        let hint = metro.logPath.map { " — Metro still bundling; log at \($0)" }
            ?? " — Metro still bundling; check the Metro process on port 8081"
        return .pass(detail + hint)
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

/// The signal differs by ownership: a Metro this run started has a log to read,
/// while a reused one can answer the same `/status` question `up` already trusts.
private struct MetroReadiness: Sendable {
    private let project: URL
    private let runner: any ProcessRunner
    private let timeout: Duration

    init(project: URL, runner: any ProcessRunner, timeout: Duration) {
        self.project = project
        self.runner = runner
        self.timeout = timeout
    }

    func wait(for metro: MetroProcess) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while true {
            if await isReady(metro) { return true }
            let remaining = ContinuousClock.now.duration(to: deadline)
            guard remaining > .zero else { return false }
            try? await Task.sleep(for: min(.milliseconds(250), remaining))
        }
    }

    private func isReady(_ metro: MetroProcess) async -> Bool {
        switch metro.state {
        case .spawned:
            guard let logPath = metro.logPath,
                  let log = try? String(contentsOfFile: logPath, encoding: .utf8)
            else { return false }
            return log.split(whereSeparator: \.isNewline).contains { rawLine in
                let line = rawLine.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                let completedBundle = line.uppercased().hasPrefix("BUNDLE ")
                    && (line.contains("100.0%") || line.contains("100%") || !line.contains("%"))
                let connectedApp = line.contains("Running \"") && line.contains(" with {")
                return completedBundle || connectedApp
            }
        case .reused:
            guard let verdict = try? await MetroVerdict.ask(anchor: project, runner: runner)
            else { return false }
            if case .mine = verdict { return true }
            return false
        }
    }
}

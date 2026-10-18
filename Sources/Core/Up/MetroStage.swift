import Foundation

/// `metro` — the React Native bundler on 8081. Before `build`, so it warms up while
/// xcodebuild spends its minutes.
///
/// What the stage does with 8081 is `MetroVerdict`'s answer plus two actions: this
/// project's own Metro is reused, an empty port gets one started detached — `up`
/// exits when the app is on screen, and a bundler that died with it would take Fast
/// Refresh along — and the three remaining answers stop the run with a sentence.
public struct MetroStage: Stage {
    public let id = "metro"

    private let anchor: ProjectAnchor
    private let runner: any ProcessRunner
    private let logs: RunLogs
    /// How long the port is given to answer with the bundler's pid after the start
    /// script is launched. Injected for tests, which have no real process to wait for.
    private let bindWait: Duration
    private let port: Int

    public static let defaultBindWait = MetroLaunch.defaultBindWait

    public init(
        anchor: ProjectAnchor,
        runner: any ProcessRunner,
        logs: RunLogs? = nil,
        bindWait: Duration = MetroStage.defaultBindWait,
        port: Int = MetroVerdict.port
    ) {
        self.anchor = anchor
        self.runner = runner
        self.logs = logs ?? RunLogs(project: anchor.directory)
        self.bindWait = bindWait
        self.port = port
    }

    public func run(_ context: inout UpContext) async throws -> StageOutcome {
        if let previous = try logs.metroPort(), previous != port {
            let previousState = try await MetroVerdict.ask(anchor: anchor.directory, runner: runner, port: previous)
            guard previousState == .empty else {
                throw DomainError(summary: "The previously selected Metro port \(previous) is still occupied or unconfirmed.",
                    remediation: Remediation(summary: "Run mobile down for this project before selecting a different port. Existing servers were preserved."))
            }
        }
        let verdict = try await MetroVerdict.ask(anchor: anchor.directory, runner: runner, port: port)
        if let blocker = verdict.blocker(port: port) { throw blocker }
        try logs.recordMetroPort(port)

        if case .mine = verdict {
            // No pid and no log path: the verdict says this Metro is this project's,
            // not that this run started it, and a CI job that cleans up what it did
            // not start is worse than one that leaks.
            context.metro = MetroProcess(state: .reused, port: port)
            return .skipped("already running on \(port)")
        }

        let logFile = logs.directory.appendingPathComponent("metro.log")
        let (command, pid) = try await MetroLaunch.start(
            anchor: anchor, runner: runner, logFile: logFile, afterReinstall: context.nodeModulesReinstalled, port: port
        )
        // Waiting is affordable here because it is bounded and because the stage it
        // delays — `build` — takes minutes.
        let listener: Int32
        switch try await MetroLaunch.readiness(startPID: pid, runner: runner, bindWait: bindWait, port: port) {
        case .listening(let pid):
            listener = pid
        case .exited:
            throw bindFailure(
                "`\(command.description)` exited before anything listened on \(port)",
                command: command,
                logFile: logFile
            )
        case .timedOut:
            throw bindFailure(
                "nothing listened on \(port) within \(bindWait)",
                command: command,
                logFile: logFile
            )
        }
        context.metro = MetroProcess(
            state: .spawned, pid: pid, listenerPid: listener, logPath: logFile.path, port: port
        )
        return .pass(
            "started on \(port) — pid \(listener), log at \(logFile.path)"
        )
    }

    private func bindFailure(
        _ observed: String,
        command: ProcessCommand,
        logFile: URL
    ) -> DomainError {
        DomainError(
            summary: "Metro did not start on \(port)",
            observed: observed,
            remediation: Remediation(
                summary: "Run the project start command and inspect the log at \(logFile.path).",
                command: command.description
            )
        )
    }
}

import Foundation

/// `metro` — the React Native bundler on 8081. Before `build`, so it warms up while
/// xcodebuild spends its minutes.
///
/// What the stage does with 8081 is `MetroVerdict`'s answer plus two actions: this
/// project's own Metro is reused, an empty port gets one started detached — `up`
/// exits when the app is on screen, and a bundler that died with it would take Fast
/// Refresh along — and the three remaining answers stop the run with a sentence.
public struct MetroStage: Stage {
    private enum Readiness {
        case listening(Int32)
        case exited
        case timedOut
    }

    public let id = "metro"

    private let anchor: ProjectAnchor
    private let runner: any ProcessRunner
    private let logs: RunLogs
    /// How long the port is given to answer with the bundler's pid after the start
    /// script is launched. Measured at ~2s on this project's dogfooding repos, so ten
    /// is room for a cold machine rather than a guess. Injected for tests, which have
    /// no real process to wait for.
    private let bindWait: Duration

    public static let defaultBindWait: Duration = .seconds(10)

    public init(
        anchor: ProjectAnchor,
        runner: any ProcessRunner,
        logs: RunLogs? = nil,
        bindWait: Duration = MetroStage.defaultBindWait
    ) {
        self.anchor = anchor
        self.runner = runner
        self.logs = logs ?? RunLogs(project: anchor.directory)
        self.bindWait = bindWait
    }

    public func run(_ context: inout UpContext) async throws -> StageOutcome {
        let verdict = try await MetroVerdict.ask(anchor: anchor.directory, runner: runner)
        if let blocker = verdict.blocker { throw blocker }

        if case .mine = verdict {
            // No pid and no log path: the verdict says this Metro is this project's,
            // not that this run started it, and a CI job that cleans up what it did
            // not start is worse than one that leaks.
            context.metro = MetroProcess(state: .reused)
            return .skipped("already running on \(MetroVerdict.port)")
        }

        let logFile = logs.directory.appendingPathComponent("metro.log")
        // The project's own start script, through the manager its lockfile named —
        // the same answer `dependencies` installs with.
        let command = anchor.startProcess(resettingCache: context.nodeModulesReinstalled)
        let pid = try await runner.spawnDetached(command, logFile: logFile)

        // The pid that comes back is the start script's, and the bundler is two links
        // below it — a `kill` there does not reach the port (#61). So the port is
        // asked who holds it, the same way `down` asks.
        let readiness = try await readiness(startPID: pid)
        let listener: Int32
        switch readiness {
        case .listening(let pid):
            listener = pid
        case .exited:
            throw bindFailure(
                "`\(command.description)` exited before anything listened on \(MetroVerdict.port)",
                command: command,
                logFile: logFile
            )
        case .timedOut:
            throw bindFailure(
                "nothing listened on \(MetroVerdict.port) within \(bindWait)",
                command: command,
                logFile: logFile
            )
        }
        context.metro = MetroProcess(
            state: .spawned, pid: pid, listenerPid: listener, logPath: logFile.path
        )
        return .pass(
            "started on \(MetroVerdict.port) — pid \(listener), log at \(logFile.path)"
        )
    }

    /// Polled rather than asked once: the start script has to boot Node before
    /// anything binds, and asking in the same breath as the spawn always answers
    /// "nobody". Waiting is affordable here because it is bounded and because the
    /// stage it delays — `build` — takes minutes.
    ///
    private func readiness(startPID: Int32) async throws -> Readiness {
        let deadline = ContinuousClock.now + bindWait
        while true {
            if let pid = try await currentListener() { return .listening(pid) }
            guard try await startProcessIsRunning(startPID) else { return .exited }
            guard ContinuousClock.now < deadline else { return .timedOut }
            try await Task.sleep(for: .milliseconds(250))
        }
    }

    private func startProcessIsRunning(_ pid: Int32) async throws -> Bool {
        try await runner.run(
            ProcessCommand("kill", ["-0", "\(pid)"], timeout: .seconds(10))
        ).terminationStatus.isSuccess
    }

    private func bindFailure(
        _ observed: String,
        command: ProcessCommand,
        logFile: URL
    ) -> DomainError {
        DomainError(
            summary: "Metro did not start on \(MetroVerdict.port)",
            observed: observed,
            remediation: Remediation(
                summary: "Run the project start command and inspect the log at \(logFile.path).",
                command: command.description
            )
        )
    }

    private func currentListener() async throws -> Int32? {
        let result = try await runner.run(
            ProcessCommand(
                "lsof", MetroVerdict.listenerArguments + ["-t"], timeout: .seconds(10)
            )
        )
        return result.standardOutput
            .split(separator: "\n")
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
            .first
    }
}

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

    public init(anchor: ProjectAnchor, runner: any ProcessRunner, logs: RunLogs? = nil) {
        self.anchor = anchor
        self.runner = runner
        self.logs = logs ?? RunLogs(project: anchor.directory)
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
        let command = ProcessCommand(
            anchor.packageManagerName, ["start"],
            workingDirectory: anchor.directory, timeout: nil
        )
        let pid = try await runner.spawnDetached(command, logFile: logFile)

        context.metro = MetroProcess(state: .spawned, pid: pid, logPath: logFile.path)
        return .pass("started on \(MetroVerdict.port) — pid \(pid), log at \(logFile.path)")
    }
}

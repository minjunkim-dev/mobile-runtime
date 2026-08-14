import Foundation

/// `metro` — the React Native bundler on 8081. Before `build`, so it warms up while
/// xcodebuild spends its minutes.
///
/// The port has three answers and each gets its own: Metro is already there and is
/// reused, something else is there and the run stops with a sentence, or nothing is
/// there and one is started detached — `up` exits when the app is on screen, and a
/// bundler that died with it would take Fast Refresh along.
public struct MetroStage: Stage {
    public let id = "metro"

    /// Fixed. Configuring it was ruled out with the rest of mobile.yml v0 (#11), and
    /// a React Native app's default bundler URL is compiled into the Debug build.
    public static let port = 8081

    private let anchor: ProjectAnchor
    private let runner: any ProcessRunner
    private let logs: RunLogs

    public init(anchor: ProjectAnchor, runner: any ProcessRunner, logs: RunLogs? = nil) {
        self.anchor = anchor
        self.runner = runner
        self.logs = logs ?? RunLogs(project: anchor.directory)
    }

    public func run(_ context: inout UpContext) async throws -> StageOutcome {
        if let answer = try await portAnswer() {
            guard answer.contains(Self.runningMarker) else { throw Self.notMetro(answer) }

            // No pid and no log path: that process is somebody else's, and a CI job
            // that cleans up what it did not start is worse than one that leaks.
            context.metro = MetroProcess(state: .reused)
            return .skipped("already running on \(Self.port)")
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
        return .pass("started on \(Self.port) — pid \(pid), log at \(logFile.path)")
    }

    /// Asked with curl through the same runner rather than by opening a socket: a new
    /// way to reach the network would be a second seam to fake, and `/status` is the
    /// answer Metro itself publishes for exactly this question.
    ///
    /// - Returns: what the port replied, or nil when the port is empty.
    ///
    /// Only exit 7 — "failed to connect" — is an empty port. Every other failure
    /// means something answered the connection and then did not finish the sentence:
    /// a timeout (28), an empty reply (52), a reset. Reading those as empty is how
    /// `up` starts a second Metro that cannot bind and reports it as started, which
    /// is exactly the blank screen this stage exists to replace with a sentence.
    private func portAnswer() async throws -> String? {
        let result = try await runner.run(
            ProcessCommand(
                "curl", ["-s", "-m", "2", "http://localhost:\(Self.port)/status"],
                timeout: .seconds(10)
            )
        )
        switch result.terminationStatus {
        case .exited(0): return result.standardOutput
        case .exited(Self.couldNotConnect): return nil
        case .exited(let code): return "curl exited \(code) — the port answered but Metro did not"
        case .signaled(let signal): return "curl was killed by signal \(signal)"
        }
    }

    /// curl's `CURLE_COULDNT_CONNECT`.
    private static let couldNotConnect: Int32 = 7

    /// What Metro answers `/status` with.
    private static let runningMarker = "packager-status:running"

    /// The alternative is a blank screen in the simulator and nothing to read. Naming
    /// the occupant is not ours to do — `lsof` does it, and the line is right here.
    private static func notMetro(_ answer: String) -> DomainError {
        DomainError(
            summary: "port \(port) is held by something that is not Metro",
            observed: String(answer.prefix(200)).trimmingCharacters(in: .whitespacesAndNewlines),
            remediation: Remediation(
                summary: "React Native's bundler only listens on \(port), so whatever holds it has "
                    + "to go first. This says which process that is.",
                command: "lsof -nP -iTCP:\(port) -sTCP:LISTEN"
            )
        )
    }
}

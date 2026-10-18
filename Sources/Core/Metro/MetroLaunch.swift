import Foundation

/// How a Metro is started, waited for and found on 8081, spelled once for iOS and
/// Android. Who owns the bundler — `MetroVerdict` plus the install record, or the
/// Android active run — stays each platform's call (ADR-0013); the process facts
/// underneath it do not differ.
public enum MetroLaunch {
    public enum Readiness: Sendable, Equatable {
        case listening(Int32)
        case exited
        case timedOut
    }

    /// A fresh macOS VM exceeded ten seconds during first startup (#167), so allow
    /// one minute while still checking for an early process exit.
    public static let defaultBindWait: Duration = .seconds(60)

    /// The project's own start script, detached, through the manager its lockfile
    /// named — the same answer `dependencies` installs with.
    public static func start(
        anchor: ProjectAnchor,
        runner: any ProcessRunner,
        logFile: URL,
        afterReinstall: Bool,
        port: Int? = nil
    ) async throws -> (command: ProcessCommand, pid: Int32) {
        if afterReinstall { await dropWatchmanWatch(of: anchor.directory, runner: runner) }
        var command = anchor.startProcess
        if let port {
            command.arguments += (anchor.packageManagerName == "npm" ? ["--"] : []) + ["--port", String(port)]
            command.environment["RCT_METRO_PORT"] = String(port)
        }
        // Metro colors its completed BUNDLE label green and its failed label red.
        // Preserve that distinction when its output goes to our non-TTY log file.
        command.environment["FORCE_COLOR"] = "1"
        return (command, try await runner.spawnDetached(command, logFile: logFile))
    }

    /// Polled rather than asked once: the start script has to boot Node before
    /// anything binds, and asking in the same breath as the spawn always answers
    /// "nobody". The pid that comes back from the spawn is the start script's, and
    /// the bundler is two links below it — a `kill` there does not reach the port
    /// (#61) — so the port is asked who holds it.
    ///
    /// - Parameter accept: whether this listener is the Metro that was started. A
    ///   throw stops the wait with that error; `false` keeps waiting.
    public static func readiness(
        startPID: Int32,
        runner: any ProcessRunner,
        bindWait: Duration,
        poll: Duration = .milliseconds(250),
        port: Int = MetroVerdict.port,
        accept: @Sendable (Int32) async throws -> Bool = { _ in true }
    ) async throws -> Readiness {
        let deadline = ContinuousClock.now + bindWait
        while true {
            if let pid = try await listeners(runner: runner, port: port).first, try await accept(pid) {
                return .listening(pid)
            }
            guard try await isRunning(startPID, runner: runner) else { return .exited }
            guard ContinuousClock.now < deadline else { return .timedOut }
            if poll > .zero { try await Task.sleep(for: poll) }
        }
    }

    /// Asked at the moment it is needed rather than remembered from a run: a pid in a
    /// file goes stale silently, and a reused one points at a stranger. Non-zero from
    /// lsof is "found nothing", so the exit code carries nothing to interpret.
    public static func listeners(runner: any ProcessRunner, port: Int = MetroVerdict.port) async throws -> [Int32] {
        let result = try await runner.run(
            ProcessCommand("lsof", MetroVerdict.listenerArguments(port: port) + ["-t"], timeout: .seconds(10))
        )
        return result.standardOutput.split(separator: "\n")
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
    }

    public static func isRunning(_ pid: Int32, runner: any ProcessRunner) async throws -> Bool {
        try await runner.run(
            ProcessCommand("kill", ["-0", "\(pid)"], timeout: .seconds(10))
        ).terminationStatus.isSuccess
    }

    /// A reinstall swaps thousands of files under watchman, which then recrawls, and a
    /// Metro that queries mid-recrawl gets a partial file list: it fails to resolve
    /// modules that are on disk (#149). Dropping the project's watch makes Metro's own
    /// `watch-project` start a fresh one, which watchman answers only after its full
    /// crawl. Without watchman there is nothing to drop, so every failure is ignored.
    public static func dropWatchmanWatch(of directory: URL, runner: any ProcessRunner) async {
        let probe = ProcessCommand(
            "watchman", ["watch-project", directory.path], workingDirectory: directory, timeout: .seconds(15)
        )
        guard let result = try? await runner.run(probe), result.terminationStatus.isSuccess,
            let reply = try? JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [String: Any],
            let root = reply["watch"] as? String
        else { return }
        _ = try? await runner.run(
            ProcessCommand("watchman", ["watch-del", root], workingDirectory: directory, timeout: .seconds(15))
        )
    }
}

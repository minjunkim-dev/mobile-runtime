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
        try Task.checkCancellation()
        return (command, try await runner.spawnDetached(command, logFile: logFile))
    }

    /// Polled rather than asked once: the start script has to boot Node before
    /// anything binds, and asking in the same breath as the spawn always answers
    /// "nobody". The pid that comes back from the spawn is the start script's, and
    /// the bundler is two links below it (#61). Only that current process tree is
    /// asked about the port; an unrelated listener is never a startup candidate.
    ///
    /// - Parameter accept: whether this listener is the Metro that was started. A
    ///   throw stops the wait with that error; `false` keeps waiting.
    public static func readiness(
        startPID: Int32,
        anchor: URL,
        runner: any ProcessRunner,
        bindWait: Duration,
        poll: Duration = .milliseconds(250),
        port: Int = MetroVerdict.port,
        accept: @Sendable (Int32) async throws -> Bool = { _ in true }
    ) async throws -> Readiness {
        let deadline = ContinuousClock.now + bindWait
        var started: ProcessIdentity?
        while true {
            try Task.checkCancellation()
            guard let tree = try await processTree(startPID: startPID, runner: runner, deadline: deadline) else { return .exited }
            if let started, started != tree[startPID] { throw uncertainStartup() }
            if started == nil {
                try await confirm(startPID: startPID, listener: startPID, tree: tree,
                    anchor: anchor, runner: runner, deadline: deadline)
            }
            started = tree[startPID]
            let candidates = try await startupListeners(pids: tree.keys.sorted(), runner: runner, port: port, deadline: deadline)
            for pid in candidates {
                try await confirm(startPID: startPID, listener: pid, tree: tree, anchor: anchor, runner: runner, deadline: deadline)
                if try await accept(pid) {
                    try Task.checkCancellation()
                    if bindWait > .zero, ContinuousClock.now >= deadline { return .timedOut }
                    try await confirm(startPID: startPID, listener: pid, tree: tree, anchor: anchor, runner: runner, deadline: deadline)
                    guard try await startupListeners(pids: [pid], runner: runner, port: port, deadline: deadline) == [pid] else {
                        throw uncertainStartup()
                    }
                    try Task.checkCancellation()
                    return .listening(pid)
                }
            }
            guard try await isRunning(startPID, runner: runner) else { return .exited }
            guard ContinuousClock.now < deadline else { return .timedOut }
            if poll > .zero { try await Task.sleep(for: poll) }
        }
    }

    private struct ProcessIdentity: Equatable {
        let parent: Int32
        let birth: String
    }

    /// `lstart` binds later observations to the same process, rather than a reused
    /// numeric PID. Descendants must still have their original chain to the root.
    private static func processTree(
        startPID: Int32, runner: any ProcessRunner, deadline: ContinuousClock.Instant
    ) async throws -> [Int32: ProcessIdentity]? {
        guard startPID > 0 else { throw uncertainStartup() }
        let result = try await runner.run(ProcessCommand(
            "ps", ["-axo", "pid=,ppid=,lstart="], environment: ["LC_ALL": "C"], timeout: probeTimeout(deadline)
        ))
        guard result.terminationStatus.isSuccess, result.standardError.isEmpty else { throw uncertainStartup() }
        var processes: [Int32: ProcessIdentity] = [:]
        for line in result.standardOutput.split(separator: "\n") {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count == 7, let pid = decimalPID(parts[0]),
                  let parent = decimalPID(parts[1], allowingZero: true), pid != parent,
                  processes[pid] == nil else { throw uncertainStartup() }
            processes[pid] = ProcessIdentity(parent: parent, birth: parts.dropFirst(2).joined(separator: " "))
        }
        guard let root = processes[startPID] else { return nil }
        var tree = [startPID: root]
        var pending = [startPID]
        while let parent = pending.popLast() {
            for (pid, identity) in processes where identity.parent == parent {
                guard tree[pid] == nil else { throw uncertainStartup() }
                tree[pid] = identity
                pending.append(pid)
            }
        }
        return tree
    }

    private static func startupListeners(
        pids: [Int32], runner: any ProcessRunner, port: Int, deadline: ContinuousClock.Instant
    ) async throws -> [Int32] {
        guard !pids.isEmpty else { throw uncertainStartup() }
        let result = try await runner.run(ProcessCommand(
            "lsof", ["-a", "-p", pids.map(String.init).joined(separator: ",")]
                + MetroVerdict.listenerArguments(port: port) + ["-t"], timeout: probeTimeout(deadline)
        ))
        guard result.standardError.isEmpty,
              result.terminationStatus == .exited(0)
                || result.terminationStatus == .exited(1)
        else { throw uncertainStartup() }
        var listeners: [Int32] = []
        for line in result.standardOutput.split(separator: "\n") {
            guard let pid = decimalPID(Substring(line.trimmingCharacters(in: .whitespaces))),
                  pids.contains(pid), !listeners.contains(pid) else { throw uncertainStartup() }
            listeners.append(pid)
        }
        // A disappearing descendant can leave partial output with exit 1.
        // Validate it, but only a fresh complete observation may confirm readiness.
        return result.terminationStatus == .exited(0) ? listeners.sorted() : []
    }

    private static func confirm(
        startPID: Int32, listener: Int32, tree: [Int32: ProcessIdentity],
        anchor: URL, runner: any ProcessRunner, deadline: ContinuousClock.Instant
    ) async throws {
        try Task.checkCancellation()
        guard let current = try await processTree(startPID: startPID, runner: runner, deadline: deadline) else { throw uncertainStartup() }
        var pid = listener
        while true {
            guard let previous = tree[pid], current[pid] == previous else { throw uncertainStartup() }
            if pid == startPID { break }
            pid = previous.parent
        }
        let pids = Array(Set([startPID, listener])).sorted()
        let result = try await runner.run(ProcessCommand(
            "lsof", ["-a", "-p", pids.map(String.init).joined(separator: ","), "-d", "cwd", "-Fpn"],
            timeout: probeTimeout(deadline)
        ))
        guard result.terminationStatus.isSuccess, result.standardError.isEmpty else { throw uncertainStartup() }
        var directories: [Int32: String] = [:]
        var seen: Set<Int32> = []
        var selected: Int32?
        var sawCWD = false
        for line in result.standardOutput.split(separator: "\n") {
            if line.first == "p" {
                if let selected, directories[selected] == nil { throw uncertainStartup() }
                guard let pid = decimalPID(line.dropFirst()), pids.contains(pid), seen.insert(pid).inserted else {
                    throw uncertainStartup()
                }
                selected = pid
                sawCWD = false
            } else if line == "fcwd" {
                guard let pid = selected, !sawCWD, directories[pid] == nil else { throw uncertainStartup() }
                sawCWD = true
            } else if line.first == "n" {
                guard let pid = selected, sawCWD, directories[pid] == nil, line.dropFirst().first == "/" else {
                    throw uncertainStartup()
                }
                directories[pid] = URL(fileURLWithPath: String(line.dropFirst())).standardizedFileURL.resolvingSymlinksInPath().path
            } else { throw uncertainStartup() }
        }
        let expected = anchor.standardizedFileURL.resolvingSymlinksInPath().path
        guard directories.count == pids.count, directories.values.allSatisfy({ $0 == expected }) else {
            throw uncertainStartup()
        }
    }

    private static func probeTimeout(_ deadline: ContinuousClock.Instant) -> Duration {
        min(.seconds(10), max(.milliseconds(1), ContinuousClock.now.duration(to: deadline)))
    }

    private static func decimalPID(_ value: Substring, allowingZero: Bool = false) -> Int32? {
        guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
              let pid = Int32(value), pid > 0 || (allowingZero && pid == 0) else { return nil }
        return pid
    }

    private static func uncertainStartup() -> DomainError {
        DomainError(summary: "The started Metro process identity could not be confirmed.",
            remediation: Remediation(summary: "Inspect this run's Metro log and current processes. Existing servers were preserved."))
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
    public static func dropWatchmanWatch(
        of directory: URL,
        runner: any ProcessRunner
    ) async {
        // Read through Metro's runner so project activation can override the parent environment.
        guard let environment = try? await runner.run(ProcessCommand(
            "/usr/bin/printenv", ["WATCHMAN_SOCK"], workingDirectory: directory, timeout: .seconds(15)
        )), environment.standardError.isEmpty else { return }
        let socketPath: String
        switch environment.terminationStatus {
        case .exited(0) where environment.standardOutput.utf8.last == 10:
            socketPath = String(decoding: environment.standardOutput.utf8.dropLast(), as: UTF8.self)
        case .exited(1) where environment.standardOutput.isEmpty:
            socketPath = ""
        default:
            return
        }
        // fb-watchman uses WATCHMAN_SOCK directly; the Watchman CLI ignores it.
        let options = if !socketPath.isEmpty {
            ["--sockname=\(socketPath)", "--no-spawn", "--no-local"]
        } else {
            [String]()
        }
        let probe = ProcessCommand(
            "watchman", options + ["watch-project", directory.path], workingDirectory: directory, timeout: .seconds(15)
        )
        guard let result = try? await runner.run(probe), result.terminationStatus.isSuccess,
            let reply = try? JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [String: Any],
            let root = reply["watch"] as? String
        else { return }
        _ = try? await runner.run(
            ProcessCommand("watchman", options + ["watch-del", root], workingDirectory: directory, timeout: .seconds(15))
        )
    }
}

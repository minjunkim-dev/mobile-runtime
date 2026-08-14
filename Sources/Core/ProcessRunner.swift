import Foundation
import Logging
import Subprocess

/// How a subprocess ended. Non-zero is ordinary data here — simctl returns it
/// routinely — so it never surfaces as a thrown error.
public enum TerminationStatus: Sendable, Hashable {
    case exited(Int32)
    case signaled(Int32)

    public var isSuccess: Bool { self == .exited(0) }
}

/// A subprocess invocation. `environment` is applied on top of the inherited
/// environment; the runner has no policy of its own (no `DEVELOPER_DIR` opinion).
public struct ProcessCommand: Sendable, CustomStringConvertible {
    /// Resolved through `PATH`. Absolute paths are not supported — no caller needs one.
    public var executable: String
    public var arguments: [String]
    public var environment: [String: String]
    /// Where the child runs. nil inherits ours — most tools do not care, and the two
    /// installs and Metro are the ones that do. Deliberately absent from
    /// `description`: the description is what a human would type, and a fixture keyed
    /// by it should not change spelling because a caller named a directory.
    public var workingDirectory: URL?
    public var timeout: Duration?

    public init(
        _ executable: String,
        _ arguments: [String] = [],
        environment: [String: String] = [:],
        workingDirectory: URL? = nil,
        timeout: Duration? = .seconds(30)
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.timeout = timeout
    }

    public var description: String {
        ([executable] + arguments).joined(separator: " ")
    }
}

public struct ProcessResult: Sendable {
    public let terminationStatus: TerminationStatus
    public let standardOutput: String
    public let standardError: String

    public init(terminationStatus: TerminationStatus, standardOutput: String, standardError: String) {
        self.terminationStatus = terminationStatus
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    /// Both streams as one text. Which stream a tool puts its diagnostics on is its
    /// own business — xcodebuild prints `error:` on stdout and keeps stderr for its
    /// noise, npm does the opposite — so anything reading a failure reads both.
    public var combinedOutput: String {
        [standardOutput, standardError].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

extension String {
    /// The last lines that say something, because a failed tool's news is at the
    /// bottom. Blank lines are dropped so the limit is spent on content.
    public func lastLines(_ limit: Int) -> String {
        split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .suffix(limit)
            .joined(separator: "\n")
    }
}

/// Infrastructure failure — the process could not be run to completion. Distinct
/// from a domain failure, which is carried by the exit status of a `ProcessResult`.
public enum ProcessError: Error, CustomStringConvertible {
    case spawnFailed(command: String, underlying: any Error)
    case timedOut(command: String, timeout: Duration)

    public var description: String {
        switch self {
        case .spawnFailed(let command, let underlying):
            return "failed to run `\(command)`: \(underlying)"
        case .timedOut(let command, let timeout):
            return "`\(command)` timed out after \(timeout)"
        }
    }
}

/// Collected-output process execution. Streaming is deliberately absent — that
/// decision is about watching a child's output as it runs, and it still stands
/// (ADR-0002). `spawnDetached` is a different question: not how output is read, but
/// whether the child outlives us.
public protocol ProcessRunner: Sendable {
    func run(_ command: ProcessCommand) async throws -> ProcessResult

    /// Starts `command` and returns as soon as it is running: both its streams go to
    /// `logFile`, and its pid comes back so a caller can report or kill it. Metro has
    /// to survive the `up` that started it, which is the one thing `run` cannot do.
    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32
}

public struct SystemProcessRunner: ProcessRunner {
    private static let outputLimit = 4 * 1024 * 1024
    private static let errorLimit = 1024 * 1024

    private let logger: Logger

    public init(logger: Logger = Logger(label: "mobile.process")) {
        self.logger = logger
    }

    public func run(_ command: ProcessCommand) async throws -> ProcessResult {
        let start = ContinuousClock.now
        var overrides: [Subprocess.Environment.Key: String?] = [:]
        for (name, value) in command.environment {
            guard let key = Subprocess.Environment.Key(rawValue: name) else { continue }
            overrides[key] = value
        }
        let environment = Subprocess.Environment.inherit.updating(overrides)

        let invocation = Self.invocation(command)
        let work = Task {
            try await Subprocess.run(
                .name(invocation.executable),
                arguments: Arguments(invocation.arguments),
                environment: environment,
                output: .string(limit: Self.outputLimit),
                error: .string(limit: Self.errorLimit)
            )
        }

        // swift-subprocess has no timeout of its own; cancelling the task kills the
        // child, which comes back as an ordinary signaled result — hence the flag.
        let expired = Flag()
        let deadline: Task<Void, any Error>? = command.timeout.map { timeout in
            Task {
                try await Task.sleep(for: timeout)
                expired.raise()
                work.cancel()
            }
        }
        defer { deadline?.cancel() }

        func log(_ message: Logger.Message, _ detail: (key: String, value: String)) {
            logger.debug(
                message,
                metadata: [
                    "command": .string(command.description),
                    "elapsed": .string("\(start.duration(to: .now))"),
                    detail.key: .string(detail.value),
                ]
            )
        }

        func timedOut() -> ProcessError {
            let timeout = command.timeout ?? .zero
            log("subprocess timed out", ("timeout", "\(timeout)"))
            return .timedOut(command: command.description, timeout: timeout)
        }

        do {
            let result = try await work.value
            let status = Self.translate(result.terminationStatus)
            // The deadline kills the child, so a killed process that also raced to
            // the finish line still counts as a real result.
            if expired.isRaised, !status.isSuccess {
                throw timedOut()
            }
            log("ran subprocess", ("status", "\(status)"))
            return ProcessResult(
                terminationStatus: status,
                standardOutput: Self.collected(result.standardOutput),
                standardError: Self.collected(result.standardError)
            )
        } catch let error as ProcessError {
            throw error
        } catch is CancellationError where expired.isRaised {
            throw timedOut()
        } catch {
            log("subprocess failed", ("error", "\(error)"))
            if error is CancellationError { throw error }  // our caller was cancelled, not the child
            throw ProcessError.spawnFailed(command: command.description, underlying: error)
        }
    }

    /// Foundation's `Process` rather than swift-subprocess: that library's whole API
    /// runs a child to completion, and this child has to outlive us. The choice stays
    /// in this file for the same reason swift-subprocess does (ADR-0002) — one place
    /// knows how a process is started.
    ///
    /// Detached as far as a process can be taken without `setsid`, which macOS ships
    /// no binary for and Foundation does not expose: the child survives us exiting,
    /// which is the case the spec names, but it stays in our process group, so a
    /// Ctrl-C in the terminal still reaches it.
    public func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
        let process = Process()
        process.executableURL = Self.env
        process.arguments = [command.executable] + command.arguments
        process.currentDirectoryURL = command.workingDirectory
        process.environment = ProcessInfo.processInfo.environment
            .merging(command.environment) { _, override in override }
        // Not the terminal we were started from: a background child that reads stdin
        // is stopped with SIGTTIN the moment `up` hands the terminal back, and Metro's
        // interactive prompt reads stdin.
        process.standardInput = FileHandle.nullDevice

        do {
            try FileManager.default.createDirectory(
                at: logFile.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data().write(to: logFile)
            let sink = try FileHandle(forWritingTo: logFile)
            process.standardOutput = sink
            process.standardError = sink
            try process.run()
        } catch {
            throw ProcessError.spawnFailed(command: command.description, underlying: error)
        }

        logger.debug(
            "spawned detached subprocess",
            metadata: [
                "command": .string(command.description),
                "pid": .string("\(process.processIdentifier)"),
                "log": .string(logFile.path),
            ]
        )
        return process.processIdentifier
    }

    /// A working directory is the one thing `ProcessCommand` asks for that
    /// swift-subprocess will not take without a `SystemPackage.FilePath`, and
    /// importing that module is what ADR-0001's Linux gate exists to catch. So the
    /// shell does the `cd`.
    ///
    /// Not `env -C`, which reads better and is too new: it arrived in FreeBSD 14.2,
    /// well after the macOS 14 this package declares as its floor. Every argument is
    /// passed as an argument here — nothing is interpolated into the script — so a
    /// directory or a scheme with a space in it cannot become two words.
    private static func invocation(_ command: ProcessCommand) -> (executable: String, arguments: [String]) {
        guard let directory = command.workingDirectory else {
            return (command.executable, command.arguments)
        }
        return (
            "sh",
            ["-c", #"cd -- "$1" && shift 1 && exec "$@""#, "sh", directory.path, command.executable]
                + command.arguments
        )
    }

    /// How `spawnDetached` resolves a PATH name: Foundation's `Process` wants an
    /// absolute executable, and `ProcessCommand.executable` promises a PATH lookup.
    /// The absolute path is `env`'s own, never the caller's (ADR-0001).
    private static let env = URL(fileURLWithPath: "/usr/bin/env")

    /// swift-subprocess hands back `String?` on Darwin and `String` on Linux;
    /// the implicit promotion makes one signature serve both.
    private static func collected(_ output: String?) -> String { output ?? "" }

    /// One-way latch shared between the work task and its deadline.
    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var raised = false

        func raise() { lock.withLock { raised = true } }
        var isRaised: Bool { lock.withLock { raised } }
    }

    private static func translate(_ status: Subprocess.TerminationStatus) -> TerminationStatus {
        switch status {
        case .exited(let code): .exited(Int32(code))
        case .signaled(let signal): .signaled(Int32(signal))
        }
    }
}

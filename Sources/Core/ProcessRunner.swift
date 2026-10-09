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

/// Where a command's output goes. The axis is the destination, not what flows — which
/// is why streaming costs the protocol no second method (ADR-0002, note on #44/#56).
public enum ProcessOutput: Sendable, Hashable {
    /// Held in memory under a limit and handed back on `ProcessResult`. The limit is a
    /// backstop, and every remaining caller of it measures in tens of kilobytes.
    case collected
    /// Written to `file` as it arrives, with no limit, and absent from `ProcessResult`.
    /// Both streams land in the one file in arrival order — the exact interleaving is
    /// not promised, for the same reason `combinedOutput` does not promise one.
    case streamed(to: URL)
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
    /// Deliberately absent from `description` for the same reason `workingDirectory`
    /// is: the description is what a human would type, and it keys the test fixtures.
    public var output: ProcessOutput

    public init(
        _ executable: String,
        _ arguments: [String] = [],
        environment: [String: String] = [:],
        workingDirectory: URL? = nil,
        timeout: Duration? = .seconds(30),
        output: ProcessOutput = .collected
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.timeout = timeout
        self.output = output
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

/// The first notable lines of an output nobody is holding, or its last lines when
/// none match. Blank lines are dropped so the limit is spent on content.
///
/// A locked class rather than a struct because it is fed from `run(_:onLine:)`, whose
/// callback is `@Sendable` and outlives no scope a value could live in. Every stage
/// that streams and selects an excerpt needs exactly this, so the lock lives here
/// once instead of in a wrapper per stage.
public final class LineExcerpt: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private let isNotable: @Sendable (String) -> Bool
    private var notable: [String] = []
    private var totalNotable = 0
    private var tail: [String] = []

    public init(limit: Int, notable isNotable: @escaping @Sendable (String) -> Bool) {
        self.limit = limit
        self.isNotable = isNotable
    }

    @discardableResult
    public func append(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return lock.withLock {
            tail.append(trimmed)
            if tail.count > limit { tail.removeFirst() }
            guard isNotable(trimmed) else { return nil }
            totalNotable += 1
            if notable.count < limit { notable.append(trimmed) }
            return trimmed
        }
    }

    public var text: String {
        lock.withLock {
            (notable.isEmpty ? tail : notable).joined(separator: "\n")
        }
    }

    public var notableCount: Int { lock.withLock { totalNotable } }
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

/// Process execution, with the output destination on the command and the line
/// callback on the call. One requirement, so a fake implements one method
/// (ADR-0002 and its note on #44/#56).
///
/// `spawnDetached` is a different question again: not where the output goes, but
/// whether the child outlives us.
public protocol ProcessRunner: Sendable {
    /// - Parameter onLine: called with complete lines as they arrive, for a command
    ///   whose output is `.streamed`. Splitting is the runner's job — a pipe delivers
    ///   chunks that end mid-line, and every caller and every fake would otherwise
    ///   reproduce the same bug. A `.collected` command never calls it: its output was
    ///   held rather than watched, and it is all there on the result to read.
    func run(
        _ command: ProcessCommand,
        onLine: (@Sendable (String) -> Void)?
    ) async throws -> ProcessResult

    /// Starts `command` and returns as soon as it is running: both its streams go to
    /// `logFile`, and its pid comes back so a caller can report or kill it. Metro has
    /// to survive the `up` that started it, which is the one thing `run` cannot do.
    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32
}

extension ProcessRunner {
    /// What almost every caller wants: run it, read the result. Nothing to watch.
    public func run(_ command: ProcessCommand) async throws -> ProcessResult {
        try await run(command, onLine: nil)
    }
}

public struct SystemProcessRunner: ProcessRunner {
    private static let outputLimit = 4 * 1024 * 1024
    private static let errorLimit = 1024 * 1024

    private let logger: Logger
    private let environment: [String: String]
    private let workingDirectory: URL?

    public init(logger: Logger = Logger(label: "mobile.process"), environment: [String: String] = ProcessInfo.processInfo.environment, workingDirectory: URL? = nil) {
        self.logger = logger
        self.environment = environment
        self.workingDirectory = workingDirectory
    }

    public func run(
        _ command: ProcessCommand,
        onLine: (@Sendable (String) -> Void)?
    ) async throws -> ProcessResult {
        var resolvedCommand = command
        if resolvedCommand.workingDirectory == nil { resolvedCommand.workingDirectory = workingDirectory }
        let command = resolvedCommand
        let start = ContinuousClock.now
        var values: [Subprocess.Environment.Key: String] = [:]
        for (name, value) in environment.merging(command.environment, uniquingKeysWith: { _, override in override }) {
            guard let key = Subprocess.Environment.Key(rawValue: name) else { continue }
            values[key] = value
        }
        let environment = Subprocess.Environment.custom(values)

        let invocation = Self.invocation(command)
        let work = Task { () async throws -> ProcessResult in
            switch command.output {
            case .collected:
                let result = try await Subprocess.run(
                    .name(invocation.executable),
                    arguments: Arguments(invocation.arguments),
                    environment: environment,
                    output: .string(limit: Self.outputLimit),
                    error: .string(limit: Self.errorLimit)
                )
                return ProcessResult(
                    terminationStatus: Self.translate(result.terminationStatus),
                    standardOutput: Self.collected(result.standardOutput),
                    standardError: Self.collected(result.standardError)
                )

            case .streamed(let file):
                let sink = try LogWriter(file: file, onLine: onLine)
                defer { sink.close() }
                let result = try await Subprocess.run(
                    .name(invocation.executable),
                    arguments: Arguments(invocation.arguments),
                    environment: environment,
                    input: .none,
                    output: .sequence,
                    error: .sequence
                ) { execution in
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask { try await Self.pump(execution.standardOutput, into: sink) }
                        group.addTask { try await Self.pump(execution.standardError, into: sink) }
                        try await group.waitForAll()
                    }
                }
                return ProcessResult(
                    terminationStatus: Self.translate(result.terminationStatus),
                    standardOutput: "",
                    standardError: ""
                )
            }
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
            // The deadline kills the child, so a killed process that also raced to
            // the finish line still counts as a real result.
            if expired.isRaised, !result.terminationStatus.isSuccess {
                throw timedOut()
            }
            log("ran subprocess", ("status", "\(result.terminationStatus)"))
            return result
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
        process.currentDirectoryURL = command.workingDirectory ?? workingDirectory
        process.environment = environment
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

    /// Drains one of the child's streams: the bytes as they came to the file, the
    /// complete lines to the callback.
    private static func pump(_ stream: SubprocessOutputSequence, into sink: LogWriter) async throws {
        var splitter = LineSplitter()
        for try await buffer in stream {
            let bytes = buffer.withUnsafeBytes { Array($0) }
            sink.write(bytes, lines: splitter.take(bytes))
        }
        sink.write([], lines: splitter.flush())
    }

    /// Both of a child's streams into one file, and complete lines out to the caller.
    /// The lock is what makes "arrival order" mean anything with two streams running:
    /// a chunk lands whole, and `onLine` is never re-entered.
    ///
    /// Not `LogSink`: "sink" is the domain's word for the destination a command names
    /// (CONTEXT.md), and spending it on the thing that does the writing would leave the
    /// concept without one.
    private final class LogWriter: @unchecked Sendable {
        private let lock = NSLock()
        private let handle: FileHandle
        private let onLine: (@Sendable (String) -> Void)?

        init(file: URL, onLine: (@Sendable (String) -> Void)?) throws {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data().write(to: file)
            self.handle = try FileHandle(forWritingTo: file)
            self.onLine = onLine
        }

        func write(_ bytes: [UInt8], lines: [String]) {
            lock.withLock {
                // A log that could not be written must not become the failure the
                // caller reports — the exit status is the news, as it always was.
                if !bytes.isEmpty { try? handle.write(contentsOf: bytes) }
                for line in lines { onLine?(line) }
            }
        }

        func close() { try? handle.close() }
    }

    /// Chunks in, whole lines out. A pipe ends a chunk wherever the kernel decided,
    /// so the tail of one chunk is the head of the next line.
    private struct LineSplitter {
        private var carry: [UInt8] = []

        /// - Returns: every line the chunk completed. A line still in progress stays.
        mutating func take(_ chunk: [UInt8]) -> [String] {
            var lines: [String] = []
            for byte in chunk {
                if byte == UInt8(ascii: "\n") {
                    lines.append(Self.decode(carry))
                    carry.removeAll(keepingCapacity: true)
                } else {
                    carry.append(byte)
                }
            }
            return lines
        }

        /// The last line of output whose author forgot the newline. Nothing when the
        /// stream ended on one.
        mutating func flush() -> [String] {
            guard !carry.isEmpty else { return [] }
            defer { carry.removeAll() }
            return [Self.decode(carry)]
        }

        /// Trailing CR dropped so a tool that writes CRLF does not hand every caller a
        /// line ending it has to strip again.
        private static func decode(_ bytes: [UInt8]) -> String {
            let line = bytes.last == UInt8(ascii: "\r") ? bytes.dropLast() : bytes[...]
            return String(decoding: line, as: UTF8.self)
        }
    }

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

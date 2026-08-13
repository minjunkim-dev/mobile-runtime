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
    public var timeout: Duration?

    public init(
        _ executable: String,
        _ arguments: [String] = [],
        environment: [String: String] = [:],
        timeout: Duration? = .seconds(30)
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
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

/// Collected-output process execution. Streaming is deliberately absent until
/// `up`'s xcodebuild needs it.
public protocol ProcessRunner: Sendable {
    func run(_ command: ProcessCommand) async throws -> ProcessResult
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

        let work = Task {
            try await Subprocess.run(
                .name(command.executable),
                arguments: Arguments(command.arguments),
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

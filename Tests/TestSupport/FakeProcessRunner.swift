import Core
import Foundation

/// The one injection seam the doctor tests use. Keyed by the full command line so
/// a test that changes the arguments fails loudly instead of silently matching.
public struct FakeProcessRunner: ProcessRunner {
    public struct Response: Sendable {
        public var status: TerminationStatus = .exited(0)
        public var standardOutput: String = ""
        public var standardError: String = ""

        public init(
            status: TerminationStatus = .exited(0),
            standardOutput: String = "",
            standardError: String = ""
        ) {
            self.status = status
            self.standardOutput = standardOutput
            self.standardError = standardError
        }

        public static func ok(_ standardOutput: String) -> Response {
            Response(status: .exited(0), standardOutput: standardOutput)
        }

        public static func failed(_ code: Int32, _ standardError: String) -> Response {
            Response(status: .exited(code), standardError: standardError)
        }
    }

    public final class CallLog: @unchecked Sendable {
        private let lock = NSLock()
        private var commands: [ProcessCommand] = []

        func record(_ command: ProcessCommand) {
            lock.withLock { commands.append(command) }
        }

        public var all: [ProcessCommand] { lock.withLock { commands } }

        public func first(matching description: String) -> ProcessCommand? {
            all.first { $0.description == description }
        }
    }

    public var responses: [String: Response]
    /// Thrown instead of answering, to exercise the infrastructure-failure path.
    public var failures: [String: any Error] = [:]
    public let log = CallLog()

    public init(responses: [String: Response] = [:], failures: [String: any Error] = [:]) {
        self.responses = responses
        self.failures = failures
    }

    public func run(_ command: ProcessCommand) async throws -> ProcessResult {
        log.record(command)
        if let failure = failures[command.description] { throw failure }
        guard let response = responses[command.description] else {
            throw ProcessError.spawnFailed(
                command: command.description,
                underlying: FixtureMiss(command: command.description)
            )
        }
        return ProcessResult(
            terminationStatus: response.status,
            standardOutput: response.standardOutput,
            standardError: response.standardError
        )
    }
}

public struct FixtureMiss: Error, CustomStringConvertible {
    public let command: String
    public var description: String { "no canned response for `\(command)`" }

    public init(command: String) {
        self.command = command
    }
}

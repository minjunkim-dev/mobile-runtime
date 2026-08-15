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

    /// A detached child, with the file its output was pointed at. The command is in
    /// `all` as well — one log, so a test that asks what ran gets the whole answer.
    public struct Spawn: Sendable {
        public let command: ProcessCommand
        public let logFile: URL
    }

    public final class CallLog: @unchecked Sendable {
        private let lock = NSLock()
        private var commands: [ProcessCommand] = []
        private var spawns: [Spawn] = []

        func record(_ command: ProcessCommand) {
            lock.withLock { commands.append(command) }
        }

        func record(_ spawn: Spawn) {
            lock.withLock {
                commands.append(spawn.command)
                spawns.append(spawn)
            }
        }

        public var all: [ProcessCommand] { lock.withLock { commands } }

        /// Only the detached ones. Spawning is what a test verifies about `metro`, and
        /// a command that was awaited instead would be a different bug.
        public var spawned: [Spawn] { lock.withLock { spawns } }

        public func first(matching description: String) -> ProcessCommand? {
            all.first { $0.description == description }
        }
    }

    public var responses: [String: Response]
    /// Thrown instead of answering, to exercise the infrastructure-failure path.
    public var failures: [String: any Error] = [:]
    /// What a spawn reports back. One value — no scenario has two live children.
    public var spawnedPID: Int32 = 4242
    public let log = CallLog()

    public init(responses: [String: Response] = [:], failures: [String: any Error] = [:]) {
        self.responses = responses
        self.failures = failures
    }

    /// The canned output goes out line by line, the way a real stream would — but no
    /// file is ever written. A test that cares about the log asserts on the path the
    /// command carries, which is the only part of it a fake can honestly own.
    public func run(
        _ command: ProcessCommand,
        onLine: (@Sendable (String) -> Void)?
    ) async throws -> ProcessResult {
        log.record(command)
        if let failure = failures[command.description] { throw failure }
        guard let response = responses[command.description] else {
            throw ProcessError.spawnFailed(
                command: command.description,
                underlying: FixtureMiss(command: command.description)
            )
        }
        let result = ProcessResult(
            terminationStatus: response.status,
            standardOutput: response.standardOutput,
            standardError: response.standardError
        )
        guard case .streamed = command.output else { return result }
        for line in result.combinedOutput.split(separator: "\n") {
            onLine?(String(line))
        }
        // Streamed output is in the file, so the result holds none of it.
        return ProcessResult(terminationStatus: response.status, standardOutput: "", standardError: "")
    }

    /// No canned response to look up: a spawn has no output to answer with, and the
    /// record of it *is* the assertion.
    public func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
        log.record(Spawn(command: command, logFile: logFile))
        if let failure = failures[command.description] { throw failure }
        return spawnedPID
    }
}

public struct FixtureMiss: Error, CustomStringConvertible {
    public let command: String
    public var description: String { "no canned response for `\(command)`" }

    public init(command: String) {
        self.command = command
    }
}

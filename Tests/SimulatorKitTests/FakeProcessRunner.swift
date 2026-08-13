import Core
import Foundation

/// The one injection seam the doctor tests use. Keyed by the full command line so
/// a test that changes the arguments fails loudly instead of silently matching.
struct FakeProcessRunner: ProcessRunner {
    struct Response {
        var status: TerminationStatus = .exited(0)
        var standardOutput: String = ""
        var standardError: String = ""

        static func ok(_ standardOutput: String) -> Response {
            Response(status: .exited(0), standardOutput: standardOutput)
        }

        static func failed(_ code: Int32, _ standardError: String) -> Response {
            Response(status: .exited(code), standardError: standardError)
        }
    }

    final class CallLog: @unchecked Sendable {
        private let lock = NSLock()
        private var commands: [ProcessCommand] = []

        func record(_ command: ProcessCommand) {
            lock.withLock { commands.append(command) }
        }

        var all: [ProcessCommand] { lock.withLock { commands } }

        func first(matching description: String) -> ProcessCommand? {
            all.first { $0.description == description }
        }
    }

    var responses: [String: Response]
    /// Thrown instead of answering, to exercise the infrastructure-failure path.
    var failures: [String: any Error] = [:]
    let log = CallLog()

    func run(_ command: ProcessCommand) async throws -> ProcessResult {
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

struct FixtureMiss: Error, CustomStringConvertible {
    let command: String
    var description: String { "no canned response for `\(command)`" }
}

enum Fixture {
    /// Real captured tool output — see Fixtures/README.md for provenance.
    static func text(_ name: String) throws -> String {
        let url = Bundle.module.resourceURL!.appendingPathComponent("Fixtures/\(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }
}

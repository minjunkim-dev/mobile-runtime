import Testing

@testable import Core

// Only the two things a fake cannot verify: real timeout behaviour and the
// non-zero-exit-is-data contract. Everything else is tested through the fake seam.
@Suite("SystemProcessRunner against real subprocesses")
struct SystemProcessRunnerTests {
    let runner = SystemProcessRunner()

    @Test("non-zero exit is data, not a thrown error")
    func nonZeroExitIsData() async throws {
        let result = try await runner.run(
            ProcessCommand("sh", ["-c", "echo out; echo err >&2; exit 3"])
        )

        #expect(result.terminationStatus == .exited(3))
        #expect(result.terminationStatus.isSuccess == false)
        #expect(result.standardOutput == "out\n")
        #expect(result.standardError == "err\n")
    }

    @Test("successful exit reports status zero")
    func successfulExit() async throws {
        let result = try await runner.run(ProcessCommand("echo", ["hello"]))

        #expect(result.terminationStatus.isSuccess)
        #expect(result.standardOutput == "hello\n")
    }

    @Test("timeout throws an infrastructure error")
    func timeoutThrows() async throws {
        let command = ProcessCommand("sleep", ["30"], timeout: .milliseconds(300))

        await #expect(throws: ProcessError.self) {
            try await runner.run(command)
        }

        do {
            _ = try await runner.run(command)
        } catch let error as ProcessError {
            guard case .timedOut(let timedOutCommand, let timeout) = error else {
                Issue.record("expected .timedOut, got \(error)")
                return
            }
            #expect(timedOutCommand == "sleep 30")
            #expect(timeout == .milliseconds(300))
        }
    }

    @Test("spawn failure throws an infrastructure error")
    func spawnFailureThrows() async throws {
        await #expect(throws: ProcessError.self) {
            try await runner.run(ProcessCommand("/nonexistent/definitely-not-a-tool"))
        }
    }

    @Test("environment overrides reach the child process")
    func environmentInjection() async throws {
        let result = try await runner.run(
            ProcessCommand(
                "sh",
                ["-c", "printf %s \"$MOBILE_TEST_VAR\""],
                environment: ["MOBILE_TEST_VAR": "injected"]
            )
        )

        #expect(result.standardOutput == "injected")
    }
}

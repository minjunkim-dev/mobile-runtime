import Foundation
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

    /// The `env -C` translation is invisible from the outside, which is the point:
    /// the child has to land in the directory the caller named.
    @Test("a working directory is where the child actually runs")
    func workingDirectory() async throws {
        let directory = try temporaryDirectory()

        let result = try await runner.run(ProcessCommand("pwd", workingDirectory: directory))

        #expect(sameDirectory(result.standardOutput, directory))
    }

    /// The whole contract of a detached spawn, checked against a real child: it comes
    /// back before the child is done, its output lands in the log file, and the pid is
    /// the one that wrote it.
    @Test("a detached child keeps running, writes to its log, and reports its pid")
    func spawnDetached() async throws {
        let directory = try temporaryDirectory()
        let logFile = directory.appendingPathComponent("child/out.log")

        let pid = try await runner.spawnDetached(
            ProcessCommand("sh", ["-c", "sleep 0.2; printf %s \"$PWD\""], workingDirectory: directory),
            logFile: logFile
        )

        #expect(pid > 0)
        // Nothing yet: `spawnDetached` returned while the child was still sleeping.
        #expect(try String(contentsOf: logFile, encoding: .utf8).isEmpty)

        // Polled rather than slept on: the assertion is that the child finishes and
        // writes, and a fixed wait would race a loaded machine instead of saying so.
        let deadline = ContinuousClock.now + .seconds(10)
        var written = ""
        while written.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
            written = try String(contentsOf: logFile, encoding: .utf8)
        }
        #expect(sameDirectory(written, directory))
    }

    /// macOS hands out `/var/folders/…` and the child reports the `/private/var/…` it
    /// really stands in. Both spellings name one directory.
    private func sameDirectory(_ reported: String, _ expected: URL) -> Bool {
        let path = reported.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(fileURLWithPath: path).resolvingSymlinksInPath()
            == expected.resolvingSymlinksInPath()
    }

    /// A log file that cannot be opened is the machine's problem, and it must be said
    /// rather than swallowed into a child nobody can read.
    @Test("a log file that cannot be written is an infrastructure error")
    func spawnLogFailure() async throws {
        await #expect(throws: ProcessError.self) {
            try await runner.spawnDetached(
                ProcessCommand("echo", ["hi"]),
                logFile: URL(fileURLWithPath: "/dev/null/not-a-directory/out.log")
            )
        }
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mobile-processrunner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

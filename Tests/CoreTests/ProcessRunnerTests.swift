import Foundation
import Logging
import Testing
import TestSupport

@testable import Core

// Exercise output delivery, process termination and privacy against real children.
@Suite("SystemProcessRunner against real subprocesses")
struct SystemProcessRunnerTests {
    let runner = SystemProcessRunner()

    @Test("argument redaction preserves actual argv, environment and cwd while hiding debug arguments", arguments: [false, true], [false, true])
    func privateArguments(_ redacted: Bool, _ bytes: Bool) async throws {
        let messages = Mutable<[String]>([])
        let logger = Logger(label: "process-privacy") { _ in ProcessLogCapture(messages: messages) }
        let directory = try temporaryDirectory()
        let command = ProcessCommand("/bin/sh", ["-c", "printf '%s\\n' \"$1\" \"$MOBILE_TEST_VAR\" \"$PWD\"", "_", "synthetic-auth"],
            environment: ["MOBILE_TEST_VAR": "kept"], workingDirectory: directory,
            timeout: .seconds(10), redactArguments: redacted)
        let runner = SystemProcessRunner(logger: logger, environment: ["PATH": "/usr/bin:/bin"])
        let result: ProcessResult
        if bytes { result = try await runner.run(command, onBytes: { _, _ in }) }
        else { result = try await runner.run(command) }
        let lines = result.standardOutput.split(whereSeparator: \.isNewline)
        #expect(result.terminationStatus.isSuccess)
        #expect(lines.count == 3)
        #expect(lines.first == "synthetic-auth")
        #expect(lines.dropFirst().first == "kept")
        #expect(sameDirectory(String(try #require(lines.last)), directory))
        #expect(command.timeout == .seconds(10))
        #expect(command.arguments.last == "synthetic-auth")
        #expect(command.description.contains("synthetic-auth") == !redacted)
        #expect(messages.value.contains { $0.contains("ran subprocess") })
        #expect(messages.value.joined().contains("synthetic-auth") == !redacted)
    }

    @Test("a sensitive timeout keeps its classification and omits arguments from debug logs")
    func privateTimeout() async throws {
        let messages = Mutable<[String]>([])
        let logger = Logger(label: "process-privacy") { _ in ProcessLogCapture(messages: messages) }
        let command = ProcessCommand("/bin/sh", ["-c", "exec /bin/sleep 30", "_", "synthetic-auth"],
            timeout: .milliseconds(100), redactArguments: true)
        do {
            _ = try await SystemProcessRunner(logger: logger, environment: ["PATH": "/usr/bin:/bin"]).run(command)
            Issue.record("the sensitive command must time out")
        } catch let error as ProcessError {
            guard case .timedOut(let description, let timeout) = error else {
                Issue.record("expected timeout")
                return
            }
            #expect(!description.contains("synthetic-auth"))
            #expect(timeout == .milliseconds(100))
        }
        #expect(messages.value.contains { $0.contains("subprocess timed out") })
        #expect(!messages.value.joined().contains("synthetic-auth"))
    }

    @Test("a sensitive spawn failure hides private underlying diagnostics from debug logs", arguments: [false, true])
    func privateSpawnFailure(_ redacted: Bool) async throws {
        let messages = Mutable<[String]>([])
        let logger = Logger(label: "process-privacy") { _ in ProcessLogCapture(messages: messages) }
        let obstruction = try temporaryDirectory().appendingPathComponent("synthetic-auth")
        try Data("owned fixture obstruction\n".utf8).write(to: obstruction, options: .withoutOverwriting)
        let command = ProcessCommand("/bin/echo", ["private-argument"],
            output: .streamed(to: obstruction.appendingPathComponent("out.log")), redactArguments: redacted)
        do {
            _ = try await SystemProcessRunner(logger: logger, environment: [:]).run(command)
            Issue.record("the invalid output path must fail")
        } catch let error as ProcessError {
            guard case .spawnFailed(let description, let underlying) = error else {
                Issue.record("expected spawn failure")
                return
            }
            #expect(description.contains("private-argument") == !redacted)
            #expect(String(describing: underlying).contains("synthetic-auth"))
        }
        #expect(messages.value.contains { $0.contains("subprocess failed") })
        #expect(messages.value.joined().contains("private-argument") == !redacted)
        #expect(messages.value.joined().contains("synthetic-auth") == !redacted)
        #expect(try Data(contentsOf: obstruction) == Data("owned fixture obstruction\n".utf8))
    }

    @Test("prepared tool and mise wrappers preserve sensitive arguments and logging policy")
    func privateWrappedArguments() async throws {
        let repo = try FixtureRepo()
        let config = try repo.directory("config")
        let project = try repo.directory("app")
        let mise = try repo.write("bin/mise", "#!/bin/sh\nshift\nshift\nexec \"$@\"\n")
        let node = try repo.write("bin/node", "#!/bin/sh\nprintf '%s\\n' \"$1\" \"$MOBILE_TEST_VAR\" \"$PWD\"\n")
        for file in [mise, node] { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path) }
        let messages = Mutable<[String]>([])
        let logger = Logger(label: "process-privacy") { _ in ProcessLogCapture(messages: messages) }
        let host = SystemProcessRunner(logger: logger, environment: ["PATH": "/usr/bin:/bin"])
        let selected = ProjectExecutionEnvironment(directRunner: MiseProcessRunner(base: host,
            configDirectory: config, executable: mise.path)).activatingTools(["node": node], environment: ["PATH": "/usr/bin:/bin"])
        let result = try await selected.runner.run(ProcessCommand("node", ["synthetic-auth"],
            environment: ["MOBILE_TEST_VAR": "kept"], workingDirectory: project, timeout: .seconds(10), redactArguments: true))
        #expect(result.terminationStatus.isSuccess)
        let lines = result.standardOutput.split(whereSeparator: \.isNewline)
        #expect(lines.count == 3)
        #expect(lines.first == "synthetic-auth")
        #expect(lines.dropFirst().first == "kept")
        #expect(sameDirectory(String(try #require(lines.last)), project))
        #expect(messages.value.contains { $0.contains("ran subprocess") })
        #expect(!messages.value.joined().contains("synthetic-auth"))
    }

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

    @Test("raw callbacks deliver both binary streams before the child exits and keep collected results")
    func bytesBeforeExit() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let release = directory.appendingPathComponent("release")
        defer { try? Data().write(to: release) }
        let observed = Mutable<[Data]>([Data(), Data()])
        let output = Data([1, 255]) + Data("out".utf8)
        let error = Data([0, 254]) + Data("err".utf8)
        let command = ProcessCommand("/bin/sh", ["-c",
            "printf '\\001\\377out'; printf '\\000\\376err' >&2; while [ ! -f \"$1\" ]; do /bin/sleep 0.01; done; printf tail; exit 7",
            "_", release.path], timeout: .seconds(5))
        let result = try await runner.run(command, onBytes: { channel, bytes in
            let index = switch channel { case .standardOutput: 0; case .standardError: 1 }
            observed.mutate { streams in
                streams[index].append(bytes)
                // The child cannot exit until both live callbacks release it; no consumer task must win the timeout race.
                if streams == [output, error] {
                    do { try Data().write(to: release, options: .withoutOverwriting) }
                    catch { Issue.record(error) }
                }
            }
        })
        #expect(FileManager.default.fileExists(atPath: release.path))
        #expect(result.terminationStatus == .exited(7))
        #expect(result.standardOutput == String(decoding: output + Data("tail".utf8), as: UTF8.self))
        #expect(result.standardError == String(decoding: error, as: UTF8.self))
        #expect(observed.value == [output + Data("tail".utf8), error])
    }

    @Test("existing conformers deliver collected output through the default byte callback")
    func defaultBytes() async throws {
        let command = ProcessCommand("fixture")
        let fake: any ProcessRunner = FakeProcessRunner(responses: ["fixture": .init(
            status: .exited(3), standardOutput: "out", standardError: "err")])
        let observed = Mutable<[Data]>([Data(), Data()])
        let result = try await fake.run(command, onBytes: { channel, bytes in
            let index = switch channel { case .standardOutput: 0; case .standardError: 1 }
            observed.mutate { $0[index].append(bytes) }
        })
        #expect(result.terminationStatus == .exited(3))
        #expect(observed.value == [Data("out".utf8), Data("err".utf8)])
    }

    @Test("byte callbacks preserve cancellation and timeout after delivering both streams", arguments: [false, true])
    func byteInterruption(_ timeout: Bool) async throws {
        let observed = Mutable<[Data]>([Data(), Data()])
        let command = ProcessCommand("/bin/sh", ["-c", "printf out; printf err >&2; exec /bin/sleep 30"],
            timeout: timeout ? .milliseconds(300) : .seconds(5), redactArguments: true)
        let task = Task {
            try await runner.run(command, onBytes: { channel, bytes in
                let index = switch channel { case .standardOutput: 0; case .standardError: 1 }
                observed.mutate { $0[index].append(bytes) }
            })
        }
        defer { task.cancel() }
        if !timeout {
            let deadline = ContinuousClock.now + .seconds(3)
            while observed.value.contains(where: \.isEmpty), ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            task.cancel()
        }
        do {
            _ = try await task.value
            Issue.record("the interrupted byte command must not succeed")
        } catch is CancellationError {
            #expect(!timeout)
        } catch let error as ProcessError {
            guard case .timedOut(let description, let duration) = error else { throw error }
            #expect(timeout)
            #expect(duration == .milliseconds(300))
            #expect(description == "/bin/sh [arguments redacted]")
        }
        #expect(observed.value == [Data("out".utf8), Data("err".utf8)])
    }

    @Test("cancellation and timeout stop owned descendants while preserving an unrelated detached child", .serialized,
          arguments: ["collected", "bytes", "streamed"], [false, true])
    func descendantInterruption(_ mode: String, _ timeout: Bool) async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let marker = directory.appendingPathComponent("child.pid")
        let childToken = "30.\(UInt64.random(in: 1...UInt64.max))"
        let siblingToken = "30.\(UInt64.random(in: 1...UInt64.max))"
        let sibling = try await runner.spawnDetached(ProcessCommand("/bin/sleep", [siblingToken]),
                                                     logFile: directory.appendingPathComponent("sibling.log"))
        // A cooperative parent must not leave its TERM-ignoring child behind.
        let script = #"trap 'exit 0' TERM; /bin/sh -c 'trap "" TERM; printf %s "$$" > "$2"; exec /bin/sleep "$1"' runstir-descendant-child "$1" "$2" >/dev/null 2>&1 & child=$!; wait "$child""#
        let command = ProcessCommand("/bin/sh", ["-c", script, "runstir-descendant-test", childToken, marker.path],
            timeout: timeout ? .seconds(10) : nil,
            output: mode == "streamed" ? .streamed(to: directory.appendingPathComponent("command.log")) : .collected)
        let task = Task {
            if mode == "bytes" { return try await runner.run(command, onBytes: { _, _ in }) }
            return try await runner.run(command)
        }
        var child: Int32?
        func cleanup() async {
            task.cancel()
            _ = try? await task.value
            let observed = child ?? (try? String(contentsOf: marker, encoding: .utf8)).flatMap(Int32.init)
            for (pid, token, signal) in [(observed, childToken, "-KILL"), (Optional(sibling), siblingToken, "-TERM")] {
                if let pid, (try? await processMatches(pid, token: token)) == true {
                    _ = try? await runner.run(ProcessCommand("/bin/kill", [signal, "\(pid)"]))
                    let stopped = ContinuousClock.now + .seconds(3)
                    while (try? await processMatches(pid, token: token)) == true, ContinuousClock.now < stopped {
                        try? await Task.sleep(for: .milliseconds(20))
                    }
                    #expect((try? await processMatches(pid, token: token)) == false)
                }
            }
        }
        do {
            let ready = ContinuousClock.now + .seconds(5)
            while child == nil, ContinuousClock.now < ready {
                child = (try? String(contentsOf: marker, encoding: .utf8)).flatMap(Int32.init)
                if child == nil { try await Task.sleep(for: .milliseconds(10)) }
            }
            let pid = try #require(child)
            #expect(try await processMatches(pid, token: childToken))
            if !timeout { task.cancel() }
            do {
                _ = try await task.value
                Issue.record("the interrupted command must not succeed")
            } catch is CancellationError {
                #expect(!timeout)
            } catch let error as ProcessError {
                guard case .timedOut = error else { throw error }
                #expect(timeout)
            }
            let stopped = ContinuousClock.now + .seconds(3)
            while try await processMatches(pid, token: childToken), ContinuousClock.now < stopped {
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(try await !processMatches(pid, token: childToken))
            #expect(try await processMatches(sibling, token: siblingToken))
        } catch {
            await cleanup()
            throw error
        }
        await cleanup()
    }

    private func processMatches(_ pid: Int32, token: String) async throws -> Bool {
        let result = try await runner.run(ProcessCommand("/bin/ps", ["-p", "\(pid)", "-o", "command="]))
        return result.terminationStatus.isSuccess && result.standardOutput.contains(token)
    }

    @Test("byte callbacks keep the separate collected output limits", arguments: [false, true])
    func byteLimits(_ standardError: Bool) async throws {
        let limit = (standardError ? 1 : 4) * 1024 * 1024
        let script = "/usr/bin/head -c \(limit + 1) /dev/zero" + (standardError ? " >&2" : "")
        await #expect(throws: ProcessError.self) {
            try await runner.run(ProcessCommand("/bin/sh", ["-c", script]), onBytes: { _, _ in })
        }
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

    /// The point of the streamed destination: the output is in the file and nowhere in
    /// memory. A caller that wants to remember something says so in `onLine`.
    @Test("a streamed command keeps nothing in its result and everything in its file")
    func streamedResultIsEmpty() async throws {
        let logFile = try temporaryDirectory().appendingPathComponent("nested/run.log")
        let lines = Mutable<[String]>([])

        let result = try await runner.run(
            ProcessCommand(
                "sh", ["-c", "echo out; echo err >&2; exit 3"], output: .streamed(to: logFile)
            ),
            onLine: { line in lines.mutate { $0.append(line) } }
        )

        #expect(result.terminationStatus == .exited(3))
        #expect(result.standardOutput.isEmpty)
        #expect(result.standardError.isEmpty)
        // Both streams, in one file, and the same lines through the callback.
        let written = try String(contentsOf: logFile, encoding: .utf8)
        #expect(written.contains("out\n"))
        #expect(written.contains("err\n"))
        #expect(lines.value.sorted() == ["err", "out"])
    }

    /// A pipe hands over chunks and a chunk ends where the kernel decided, which for a
    /// line this long is somewhere in the middle of it. The callback must not see that.
    @Test("a line split across chunks reaches the callback whole")
    func linesSurviveChunkBoundaries() async throws {
        let logFile = try temporaryDirectory().appendingPathComponent("long.log")
        let lines = Mutable<[String]>([])
        let width = 400_000

        _ = try await runner.run(
            ProcessCommand(
                "sh",
                ["-c", "head -c \(width) /dev/zero | tr '\\0' 'a'; echo; echo tail"],
                output: .streamed(to: logFile)
            ),
            onLine: { line in lines.mutate { $0.append(line) } }
        )

        #expect(lines.value.count == 2)
        #expect(lines.value.first?.count == width)
        #expect(lines.value.last == "tail")
    }

    /// The accident this destination exists for: a healthy first build of a real app
    /// printed about 39 MiB and the 4 MiB collected limit killed it (#55). Five is
    /// enough to prove the limit is not on this path — forty would only prove it
    /// slower.
    @Test("a streamed command has no output limit")
    func streamedOutputIsUnbounded() async throws {
        let logFile = try temporaryDirectory().appendingPathComponent("big.log")
        let bytes = 5 * 1024 * 1024

        let result = try await runner.run(
            ProcessCommand(
                "sh",
                ["-c", "head -c \(bytes) /dev/zero | tr '\\0' 'a' | fold -w 100"],
                timeout: nil,
                output: .streamed(to: logFile)
            )
        )

        #expect(result.terminationStatus.isSuccess)
        let written = try FileManager.default.attributesOfItem(atPath: logFile.path)[.size] as? Int
        #expect(written ?? 0 >= bytes)
    }

    /// A log file that cannot be opened loses the whole output, so it stops the run
    /// rather than leaving a build to fail with nothing to read.
    @Test("a stream destination that cannot be written is an infrastructure error")
    func streamLogFailure() async throws {
        await #expect(throws: ProcessError.self) {
            try await runner.run(
                ProcessCommand(
                    "echo", ["hi"],
                    output: .streamed(to: URL(fileURLWithPath: "/dev/null/not-a-directory/out.log"))
                )
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

private struct ProcessLogCapture: LogHandler {
    let messages: Mutable<[String]>
    var metadata: Logger.Metadata = [:]
    var logLevel: Logger.Level = .debug

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(event: LogEvent) {
        messages.mutate { $0.append("\(event.message) \(event.metadata ?? [:])") }
    }
}

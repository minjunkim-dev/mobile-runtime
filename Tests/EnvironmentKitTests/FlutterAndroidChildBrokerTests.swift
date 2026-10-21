import Core
import Darwin
import Foundation
import Testing
@testable import EnvironmentKit

@Suite("Flutter Android owner-side child transport", .serialized)
struct FlutterAndroidChildBrokerTests {
    @Test("authenticated argv preserves live binary channels and exited or signaled status", arguments: [false, true])
    func outputAndStatus(_ signaled: Bool) async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = SystemProcessRunner(environment: ["PATH": "/usr/bin:/bin"], workingDirectory: root)
        let bytes = Output()
        let broker = try FlutterAndroidChildBroker(root: root, runner: runner) { arguments in
            #expect(arguments == ["a b", "--value=한글"])
            return ProcessCommand("/bin/sh", ["-c", "printf '\\000\\377out'; printf '\\376err' >&2; "
                + (signaled ? "kill -TERM $$" : "exit 7")],
                                  workingDirectory: root, timeout: .seconds(5))
        }
        defer { broker.close() }
        let status = await Task.detached {
            FlutterAndroidChildClient.run(arguments: ["mobile", "--runstir-flutter-child", "a b", "--value=한글"],
                environment: broker.environment, output: { bytes.append($0, $1) })
        }.value
        #expect(status == (signaled ? 143 : 7))
        #expect(bytes.value(.standardOutput) == Data([0, 255] + Array("out".utf8)))
        #expect(bytes.value(.standardError) == Data([254] + Array("err".utf8)))
    }

    @Test("invalid authentication and oversized argv never run an SDK command")
    func invalidRequests() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let broker = try FlutterAndroidChildBroker(root: root,
            runner: SystemProcessRunner(environment: ["PATH": "/usr/bin:/bin"], workingDirectory: root)) { _ in
            Issue.record("An invalid request reached the command factory")
            return ProcessCommand("/usr/bin/true")
        }
        defer { broker.close() }
        var invalid = broker.environment
        invalid["RUNSTIR_FLUTTER_CHILD_TOKEN"] = String(repeating: "0", count: 64)
        let invalidEnvironment = invalid
        let denied = await Task.detached {
            FlutterAndroidChildClient.run(arguments: ["mobile", "--runstir-flutter-child", "assemble"],
                environment: invalidEnvironment, output: { _, _ in })
        }.value
        #expect(denied != 0)
        let oversized = await Task.detached {
            FlutterAndroidChildClient.run(arguments: ["mobile", "--runstir-flutter-child", String(repeating: "x", count: 1_048_577)],
                environment: broker.environment, output: { _, _ in })
        }.value
        #expect(oversized != 0)
        // Ordinary entrypoints return before looking for private transport credentials.
        FlutterAndroidChildClient.runIfRequested(arguments: ["mobile", "--help"])
    }

    @Test("owner close or client disconnect cancels the running child and rejects later requests", arguments: [false, true])
    func ownerCancellation(_ disconnect: Bool) async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let started = AsyncStream<Data>.makeStream()
        let broker = try FlutterAndroidChildBroker(root: root,
            runner: SystemProcessRunner(environment: ["PATH": "/usr/bin:/bin"], workingDirectory: root)) { _ in
            ProcessCommand("/bin/sh", ["-c", "printf '%s\\n' $$; exec /bin/sleep 30"],
                           workingDirectory: root, timeout: .seconds(10))
        }
        defer { broker.close() }
        let client = Task.detached {
            defer { started.continuation.finish() }
            return FlutterAndroidChildClient.run(arguments: ["mobile", "--runstir-flutter-child", "assemble"],
                environment: broker.environment, output: { channel, data in
                    if channel == .standardOutput { started.continuation.yield(data) }
                    if disconnect { throw CancellationError() }
                })
        }
        var processBytes = Data()
        for await chunk in started.stream {
            processBytes.append(chunk)
            if processBytes.contains(10) { break }
        }
        let process = try #require(Int32(String(decoding: processBytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
        if !disconnect { broker.close() }
        #expect(await client.value != 0)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(8))
        while kill(process, 0) == 0, clock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(kill(process, 0) == -1 && errno == ESRCH)
        let late = await Task.detached {
            FlutterAndroidChildClient.run(arguments: ["mobile", "--runstir-flutter-child", "assemble"],
                environment: broker.environment, output: { _, _ in })
        }.value
        #expect(late != 0)
    }

    @Test("owner starts a child policy once while preserving generated and protected write boundaries")
    func siblingSandbox() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let sdk = root.appendingPathComponent("sdk")
        let output = root.appendingPathComponent("output")
        try FileManager.default.createDirectory(at: sdk, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        let source = root.appendingPathComponent("source")
        try FlutterAndroidExecution.write(Data("source".utf8), to: source)
        let profile = try FlutterAndroidExecution.childPolicy(protected: [source], sdk: sdk, writable: [output])
        let policy = root.appendingPathComponent("child.sb")
        try FlutterAndroidExecution.write(Data(profile.utf8), to: policy)
        let runner = SystemProcessRunner(environment: ["PATH": "/usr/bin:/bin"], workingDirectory: root)
        let broker = try FlutterAndroidChildBroker(root: root, runner: runner) { arguments in
            #expect(arguments == ["assemble"])
            return ProcessCommand("/usr/bin/sandbox-exec", ["-f", policy.path, "/bin/sh", "-c",
                "printf generated > \"$1/output/artifact\" && if printf bad > \"$1/source\"; then exit 9; fi; if printf bad > \"$1/unowned\"; then exit 10; fi",
                "flutter-test", root.path], workingDirectory: root, timeout: .seconds(5))
        }
        defer { broker.close() }
        let status = await Task.detached {
            FlutterAndroidChildClient.run(arguments: ["mobile", "--runstir-flutter-child", "assemble"],
                environment: broker.environment, output: { _, _ in })
        }.value
        #expect(status == 0)
        #expect(try Data(contentsOf: source) == Data("source".utf8))
        #expect(try String(contentsOf: output.appendingPathComponent("artifact"), encoding: .utf8) == "generated")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("unowned").path))
    }

    private func makeRoot() throws -> URL {
        try FlutterAndroidExecution.makeRoot(in: URL(fileURLWithPath: "/private/tmp"))
    }

    private final class Output: @unchecked Sendable {
        let lock = NSLock()
        var stdout = Data()
        var stderr = Data()
        func append(_ channel: ProcessOutputChannel, _ bytes: Data) {
            lock.withLock {
                switch channel {
                case .standardOutput: stdout.append(bytes)
                case .standardError: stderr.append(bytes)
                }
            }
        }
        func value(_ channel: ProcessOutputChannel) -> Data {
            lock.withLock {
                switch channel {
                case .standardOutput: return stdout
                case .standardError: return stderr
                }
            }
        }
    }
}

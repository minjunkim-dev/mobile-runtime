import Foundation
import TestSupport
import Testing

@testable import Core

private let anchor = URL(fileURLWithPath: "/Users/me/joplin/packages/app-mobile")
private let listCommand = "lsof -nP -iTCP:8081 -sTCP:LISTEN -t"
private let killCommand = "kill -TERM 65260"

private func teardown(_ runner: FakeProcessRunner) async throws -> TeardownItem {
    // No grace: the wait is for a real SIGTERM to be delivered, and a fake answers
    // the second question with whatever the test already decided.
    try await MetroTeardown(anchor: anchor, runner: runner, grace: .zero).run()
}

/// Two answers for one command, in order: the port before the kill and after it.
private final class PortSequence: ProcessRunner, @unchecked Sendable {
    /// nil is a refused connection — curl's exit 7, which is the only proof the
    /// bundler that was there is gone.
    private let answers: [String?]
    private let lock = NSLock()
    private var asked = 0
    private(set) var killed: [String] = []

    init(before: String, after: String?) {
        answers = [before, after]
    }

    func run(
        _ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?
    ) async throws -> ProcessResult {
        lock.withLock {
            switch command.description {
            case MetroStatus.command:
                let answer = answers[min(asked, answers.count - 1)]
                asked += 1
                guard let answer else {
                    return ProcessResult(terminationStatus: .exited(7), standardOutput: "", standardError: "")
                }
                return ProcessResult(terminationStatus: .exited(0), standardOutput: answer, standardError: "")
            case listCommand:
                return ProcessResult(terminationStatus: .exited(0), standardOutput: "65260\n", standardError: "")
            default:
                killed.append(command.description)
                return ProcessResult(terminationStatus: .exited(0), standardOutput: "", standardError: "")
            }
        }
    }

    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 { 0 }
}

@Suite("metro teardown")
struct MetroTeardownTests {
    /// The kill is SIGTERM and the pid comes from the port at that moment — no state
    /// file, because a pid in a file goes stale without saying so (ADR-0007).
    @Test("this project's Metro is stopped with SIGTERM and named by pid")
    func stopsMine() async throws {
        let runner = PortSequence(
            before: MetroStatus.running(projectRoot: anchor),
            after: nil
        )

        let item = try await MetroTeardown(anchor: anchor, runner: runner, grace: .zero).run()

        #expect(item.status == .stopped)
        #expect(item.detail?.contains("65260") == true)
        #expect(runner.killed == [killCommand])
    }

    /// The judge `up` reuses on is the judge `down` kills on. Another project's
    /// Metro is not ours to stop, and saying which of the three it was is the point.
    @Test("another project's Metro is left alone, and the reason is said")
    func leavesAnother() async throws {
        let runner = FakeProcessRunner(responses: [
            MetroStatus.command: .ok(
                MetroStatus.running(projectRoot: URL(fileURLWithPath: "/Users/me/mattermost-mobile"))
            )
        ])

        let item = try await teardown(runner)

        #expect(item.status == .blocked)
        #expect(item.detail?.contains("another project's Metro") == true)
        #expect(runner.log.all.map(\.description).contains(listCommand) == false)
    }

    @Test("a port that cannot say whose Metro it is keeps its process")
    func leavesUnidentifiable() async throws {
        let runner = FakeProcessRunner(responses: [
            MetroStatus.command: .ok(MetroStatus.reply("HTTP/1.1 404 Not Found", body: "Not found"))
        ])

        let item = try await teardown(runner)

        #expect(item.status == .blocked)
        #expect(item.detail?.contains("could not be confirmed") == true)
    }

    @Test("an empty port is nothing to stop, not a failure")
    func emptyPort() async throws {
        let runner = FakeProcessRunner(responses: [MetroStatus.command: .failed(7, "")])

        let item = try await teardown(runner)

        #expect(item.status == .skipped)
        #expect(item.detail == "nothing on 8081")
    }

    /// SIGTERM is the whole escalation this tool performs. `kill -9` is the human's
    /// to type, so a Metro that ignored the signal is a failure with a line to paste.
    @Test("a Metro that survives SIGTERM fails, and does not get escalated")
    func survivesSignal() async throws {
        let running = MetroStatus.running(projectRoot: anchor)
        let runner = PortSequence(before: running, after: running)

        let item = try await MetroTeardown(anchor: anchor, runner: runner, grace: .zero).run()

        #expect(item.status == .failed)
        #expect(item.remediation?.command == "lsof -nP -iTCP:8081 -sTCP:LISTEN")
        #expect(runner.killed == [killCommand])
        #expect(runner.killed.contains { $0.contains("-9") } == false)
    }

    /// Only an empty port proves the kill landed. A port that answers as something
    /// else is a bundler this run can no longer account for — reporting that as
    /// stopped is the false negative #45 was made of.
    @Test("a port still answering as something else is not a stopped Metro")
    func unconfirmedAfterSignal() async throws {
        let runner = PortSequence(
            before: MetroStatus.running(projectRoot: anchor),
            after: MetroStatus.reply("HTTP/1.1 404 Not Found", body: "Not found")
        )

        let item = try await MetroTeardown(anchor: anchor, runner: runner, grace: .zero).run()

        #expect(item.status == .failed)
        #expect(item.detail?.contains("no longer be confirmed stopped") == true)
    }

    /// The port says one thing and lsof says another. Acting on that disagreement
    /// means killing something nobody identified.
    @Test("a Metro nobody is listening for is reported, not guessed at")
    func noListener() async throws {
        let runner = FakeProcessRunner(responses: [
            MetroStatus.command: .ok(MetroStatus.running(projectRoot: anchor)),
            listCommand: .ok(""),
        ])

        let item = try await teardown(runner)

        #expect(item.status == .failed)
        #expect(item.detail?.contains("no process was found listening") == true)
    }
}

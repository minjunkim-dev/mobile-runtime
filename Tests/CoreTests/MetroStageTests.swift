import Foundation
import TestSupport
import Testing

@testable import Core

private let packageJSON = #"{"dependencies": {"react-native": "0.81.0"}}"#
private let statusCommand = "curl -s -m 2 http://localhost:8081/status"

private func app() throws -> FixtureRepo {
    let repo = try FixtureRepo()
    try repo.write("package.json", packageJSON)
    try repo.write("yarn.lock", "")
    return repo
}

private func temporaryLogs() throws -> RunLogs {
    let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent("mobile-metrostage-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    return RunLogs(project: URL(fileURLWithPath: "/a/MyApp"), temporaryDirectory: temporary)
}

@discardableResult
private func run(
    _ repo: FixtureRepo,
    _ runner: FakeProcessRunner,
    context: inout UpContext,
    logs: RunLogs? = nil
) async throws -> StageOutcome {
    let anchor = try #require(ProjectAnchor.detect(from: repo.root))
    return try await MetroStage(anchor: anchor, runner: runner, logs: try logs ?? temporaryLogs())
        .run(&context)
}

@Suite("metro stage")
struct MetroStageTests {
    /// Metro publishes this on `/status`, and two bundlers on one port is the thing
    /// this branch exists to prevent.
    @Test("a Metro already on 8081 is reused, not restarted")
    func reuses() async throws {
        let repo = try app()
        let runner = FakeProcessRunner(responses: [statusCommand: .ok("packager-status:running")])
        var context = UpContext()

        let outcome = try await run(repo, runner, context: &context)

        #expect(outcome.status == .skipped)
        #expect(context.metro?.state == .reused)
        // The pid belongs to whoever started it — CI must only clean up its own.
        #expect(context.metro?.pid == nil)
        #expect(runner.log.spawned.isEmpty)
    }

    /// The alternative is a blank screen with nothing to read.
    @Test("something else on 8081 stops the run with a way to find it")
    func occupied() async throws {
        let repo = try app()
        let runner = FakeProcessRunner(responses: [statusCommand: .ok("<!DOCTYPE html><title>Grafana</title>")])
        var context = UpContext()

        let error = await #expect(throws: DomainError.self) {
            try await run(repo, runner, context: &context)
        }

        #expect(error?.summary.contains("8081") == true)
        #expect(error?.remediation.command?.contains("8081") == true)
        #expect(runner.log.spawned.isEmpty)
        #expect(context.metro == nil)
    }

    /// curl's non-zero is "could not connect", which is exactly an empty port.
    @Test("an empty 8081 gets a detached Metro, reported by pid and log path")
    func spawns() async throws {
        let repo = try app()
        let runner = FakeProcessRunner(responses: [statusCommand: .failed(7, "")])
        let logs = try temporaryLogs()
        var context = UpContext()

        let outcome = try await run(repo, runner, context: &context, logs: logs)

        #expect(outcome.status == .pass)
        let spawn = try #require(runner.log.spawned.first)
        // The project's own start script, through the manager the lockfile named.
        #expect(spawn.command.description == "yarn start")
        #expect(spawn.command.workingDirectory?.path == repo.root.path)
        #expect(spawn.logFile == logs.directory.appendingPathComponent("metro.log"))
        #expect(context.metro?.state == .spawned)
        #expect(context.metro?.pid == runner.spawnedPID)
        #expect(context.metro?.logPath == spawn.logFile.path)
    }

    /// A port that accepts the connection and then says nothing is not an empty port.
    /// Spawning here produces a Metro that cannot bind and a run that claims it did.
    @Test("a port that answers slowly is held, not empty")
    func slowOccupant() async throws {
        let repo = try app()
        // curl 28: the `-m 2` deadline passed with the connection open.
        let runner = FakeProcessRunner(responses: [statusCommand: .failed(28, "")])
        var context = UpContext()

        let error = await #expect(throws: DomainError.self) {
            try await run(repo, runner, context: &context)
        }

        #expect(error?.observed?.contains("28") == true)
        #expect(runner.log.spawned.isEmpty)
    }

    /// A run that could not even ask has no answer about the port, and guessing
    /// "empty" would start a second Metro next to a live one.
    @Test("a curl that cannot run stays an infrastructure failure")
    func probeFailure() async throws {
        let repo = try app()
        let runner = FakeProcessRunner(failures: [
            statusCommand: ProcessError.spawnFailed(command: statusCommand, underlying: FixtureMiss(command: "curl"))
        ])
        var context = UpContext()

        await #expect(throws: ProcessError.self) {
            try await run(repo, runner, context: &context)
        }
        #expect(runner.log.spawned.isEmpty)
    }
}

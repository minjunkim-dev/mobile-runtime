import Foundation
import TestSupport
import Testing

@testable import Core

private let packageJSON = #"{"dependencies": {"react-native": "0.81.0"}}"#

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
    _ runner: any ProcessRunner,
    context: inout UpContext,
    logs: RunLogs? = nil,
    bindWait: Duration = .zero
) async throws -> StageOutcome {
    let anchor = try #require(ProjectAnchor.detect(from: repo.root))
    return try await MetroStage(
        anchor: anchor, runner: runner, logs: try logs ?? temporaryLogs(), bindWait: bindWait
    ).run(&context)
}

private actor DelayedListenerRunner: ProcessRunner {
    private let inner: FakeProcessRunner
    private var probes = 0

    init(_ inner: FakeProcessRunner) {
        self.inner = inner
    }

    func run(
        _ command: ProcessCommand,
        onLine: (@Sendable (String) -> Void)?
    ) async throws -> ProcessResult {
        guard command.description == "lsof -nP -iTCP:8081 -sTCP:LISTEN -t" else {
            return try await inner.run(command, onLine: onLine)
        }
        probes += 1
        return ProcessResult(
            terminationStatus: .exited(probes == 1 ? 1 : 0),
            standardOutput: probes == 1 ? "" : "70947\n",
            standardError: ""
        )
    }

    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
        try await inner.spawnDetached(command, logFile: logFile)
    }
}

@Suite("metro stage")
struct MetroStageTests {
    @Test("after a reinstall the project's watchman watch is dropped so Metro crawls fresh")
    func dropsWatchmanWatch() async throws {
        let repo = try app()
        let probe = "watchman watch-project \(repo.root.path)"
        let runner = FakeProcessRunner(responses: [probe: .ok(#"{"watch": "/watched/root"}"#)])

        await MetroStage.dropWatchmanWatch(of: repo.root, runner: runner)

        #expect(runner.log.first(matching: "watchman watch-del /watched/root") != nil)
    }

    @Test("without an answer from watchman there is no watch to drop")
    func noWatchmanNoDrop() async throws {
        let repo = try app()
        let runner = FakeProcessRunner()

        await MetroStage.dropWatchmanWatch(of: repo.root, runner: runner)

        #expect(!runner.log.all.contains { $0.arguments.first == "watch-del" })
    }

    /// Metro publishes this on `/status`, and two bundlers on one port is the thing
    /// this branch exists to prevent.
    @Test("a Metro already on 8081 for this project is reused, not restarted")
    func reuses() async throws {
        let repo = try app()
        let runner = FakeProcessRunner(responses: [
            MetroStatus.command: .ok(MetroStatus.running(projectRoot: repo.root))
        ])
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
        let runner = FakeProcessRunner(responses: [
            MetroStatus.command: .ok(MetroStatus.reply(body: "<!DOCTYPE html><title>Grafana</title>"))
        ])
        var context = UpContext()

        let error = await #expect(throws: DomainError.self) {
            try await run(repo, runner, context: &context)
        }

        #expect(error?.summary.contains("8081") == true)
        #expect(error?.remediation.command?.contains("8081") == true)
        #expect(runner.log.spawned.isEmpty)
        #expect(context.metro == nil)
    }

    /// #45: the run that gave this project's app to another project's bundler and
    /// reported success. Reuse is not "a Metro is up", it is "this project's Metro".
    @Test("a Metro serving another project stops the run instead of being reused")
    func anotherProjectsMetro() async throws {
        let repo = try app()
        let other = URL(fileURLWithPath: "/Users/me/mattermost-mobile")
        let runner = FakeProcessRunner(responses: [
            MetroStatus.command: .ok(MetroStatus.running(projectRoot: other))
        ])
        var context = UpContext()

        let error = await #expect(throws: DomainError.self) {
            try await run(repo, runner, context: &context)
        }

        #expect(error?.observed?.contains(other.path) == true)
        #expect(runner.log.spawned.isEmpty)
        #expect(context.metro == nil)
    }

    /// The stopping sentence a user reads has to be the one about not knowing, not
    /// the one about somebody else — the port answering without a `/status` is what
    /// a 0.76+ project's own Metro looks like from here.
    @Test("a port that cannot say whose Metro it is stops the run saying that")
    func unidentifiable() async throws {
        let repo = try app()
        let runner = FakeProcessRunner(responses: [
            MetroStatus.command: .ok(MetroStatus.reply("HTTP/1.1 404 Not Found", body: "Not found"))
        ])
        var context = UpContext()

        let error = await #expect(throws: DomainError.self) {
            try await run(repo, runner, context: &context)
        }

        #expect(error?.summary.contains("could not be confirmed") == true)
        #expect(runner.log.spawned.isEmpty)
        #expect(context.metro == nil)
    }

    /// curl's non-zero is "could not connect", which is exactly an empty port.
    @Test("an empty 8081 gets a detached Metro, reported by pid and log path")
    func spawns() async throws {
        let repo = try app()
        let logs = try temporaryLogs()
        var context = UpContext()

        let runner = FakeProcessRunner(responses: [
            MetroStatus.command: .failed(7, ""),
            "lsof -nP -iTCP:8081 -sTCP:LISTEN -t": .ok("70947\n"),
        ])
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

    @Test("a declared Corepack manager starts Metro offline")
    func corepackSpawns() async throws {
        let repo = try FixtureRepo()
        try repo.write(
            "package.json",
            #"{"dependencies":{"react-native":"0.81.0"},"packageManager":"yarn@4.16.0"}"#
        )
        try repo.write("yarn.lock", "")
        let runner = FakeProcessRunner(responses: [
            MetroStatus.command: .failed(7, ""),
            "lsof -nP -iTCP:8081 -sTCP:LISTEN -t": .ok("70947\n"),
        ])
        var context = UpContext()

        _ = try await run(repo, runner, context: &context)

        let spawn = try #require(runner.log.spawned.first)
        #expect(spawn.command.description == "corepack yarn start")
        #expect(spawn.command.environment["COREPACK_ENABLE_NETWORK"] == "0")
        #expect(spawn.command.workingDirectory?.path == repo.root.path)
    }

    /// #61: the pid the spawn hands back is the start script's, and the bundler is
    /// two links below it — killing the reported one left 8081 held. So the port is
    /// asked who holds it, and that is the pid a reader is given.
    @Test("the pid holding 8081 is reported next to the process up started")
    func reportsTheListener() async throws {
        let repo = try app()
        let runner = FakeProcessRunner(responses: [
            MetroStatus.command: .failed(7, ""),
            "lsof -nP -iTCP:8081 -sTCP:LISTEN -t": .ok("70947\n"),
        ])
        var context = UpContext()

        let outcome = try await run(repo, runner, context: &context)

        #expect(context.metro?.pid == runner.spawnedPID)
        #expect(context.metro?.listenerPid == 70947)
        #expect(outcome.detail?.contains("pid 70947") == true)
    }

    @Test("a start process that exits before binding stops before build")
    func startExits() async throws {
        let repo = try app()
        let logs = try temporaryLogs()
        let runner = FakeProcessRunner(responses: [
            MetroStatus.command: .failed(7, ""),
            "lsof -nP -iTCP:8081 -sTCP:LISTEN -t": .ok(""),
            "kill -0 4242": .failed(1, "No such process"),
        ])
        var context = UpContext()

        let error = await #expect(throws: DomainError.self) {
            try await run(repo, runner, context: &context, logs: logs)
        }

        #expect(error?.observed?.contains("exited") == true)
        #expect(error?.remediation.command == "yarn start")
        #expect(error?.remediation.summary.contains(logs.directory.path) == true)
        #expect(context.metro == nil)
    }

    @Test("a live start process that never binds times out before build")
    func bindTimeout() async throws {
        let repo = try app()
        let runner = FakeProcessRunner(responses: [
            MetroStatus.command: .failed(7, ""),
            "lsof -nP -iTCP:8081 -sTCP:LISTEN -t": .ok(""),
            "kill -0 4242": .ok(""),
        ])
        var context = UpContext()

        let error = await #expect(throws: DomainError.self) {
            try await run(repo, runner, context: &context)
        }

        #expect(error?.observed?.contains("within") == true)
        #expect(context.metro == nil)
    }

    @Test("a delayed listener passes once it binds within the deadline")
    func delayedBind() async throws {
        let repo = try app()
        let runner = DelayedListenerRunner(FakeProcessRunner(responses: [
            MetroStatus.command: .failed(7, ""),
            "kill -0 4242": .ok(""),
        ]))
        var context = UpContext()

        let outcome = try await run(
            repo, runner, context: &context, bindWait: .seconds(1)
        )

        #expect(outcome.status == .pass)
        #expect(context.metro?.listenerPid == 70947)
    }

    /// A port that accepts the connection and then says nothing is not an empty port.
    /// Spawning here produces a Metro that cannot bind and a run that claims it did.
    @Test("a port that answers slowly is held, not empty")
    func slowOccupant() async throws {
        let repo = try app()
        // curl 28: the `-m 2` deadline passed with the connection open.
        let runner = FakeProcessRunner(responses: [MetroStatus.command: .failed(28, "")])
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
            MetroStatus.command: ProcessError.spawnFailed(
                command: MetroStatus.command, underlying: FixtureMiss(command: "curl")
            )
        ])
        var context = UpContext()

        await #expect(throws: ProcessError.self) {
            try await run(repo, runner, context: &context)
        }
        #expect(runner.log.spawned.isEmpty)
    }
}

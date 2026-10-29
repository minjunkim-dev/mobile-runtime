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

private func temporaryLogs() throws -> RunLogs { try RunLogs.temporary() }

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

private typealias DelayedListenerRunner = MetroStatus.StartingRunner

private actor NextProbeListenerRunner: ProcessRunner {
    private let inner: FakeProcessRunner
    private(set) var listenerReadiness: [Bool] = []

    init(projectRoot: URL) {
        var responses = MetroStatus.startupResponses(projectRoot: projectRoot)
        responses[MetroStatus.command] = .ok(MetroStatus.running(projectRoot: projectRoot))
        responses["kill -0 4242"] = .ok("")
        inner = FakeProcessRunner(responses: responses)
    }

    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        var response = inner
        if command.executable == "lsof", command.arguments.contains("-p"), command.arguments.contains("-t"),
            inner.responses[command.description] != nil {
            let ready = !listenerReadiness.isEmpty
            listenerReadiness.append(ready)
            if !ready { response.responses[command.description] = .failed(1, "") }
        }
        return try await response.run(command, onLine: onLine)
    }

    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
        try await inner.spawnDetached(command, logFile: logFile)
    }
}

private struct SocketProbeCancellingRunner: ProcessRunner {
    let base = FakeProcessRunner(responses: ["/usr/bin/printenv WATCHMAN_SOCK": .ok("")])

    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        let result = try await base.run(command, onLine: onLine)
        if command.executable == "/usr/bin/printenv", command.arguments == ["WATCHMAN_SOCK"] {
            withUnsafeCurrentTask { $0?.cancel() }
            try Task.checkCancellation()
        }
        return result
    }

    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
        try await base.spawnDetached(command, logFile: logFile)
    }
}

@Suite("metro stage")
struct MetroStageTests {
    @Test("omitting the start port preserves the legacy script arguments and inherited native input")
    func omittedPortStart() async throws {
        let repo = try app()
        let anchor = try #require(ProjectAnchor.detect(from: repo.root))
        let runner = FakeProcessRunner()
        _ = try await MetroLaunch.start(anchor: anchor, runner: runner, logFile: repo.url("metro.log"), afterReinstall: false)
        #expect(runner.log.spawned.first?.command.arguments == ["start"])
        #expect(runner.log.spawned.first?.command.environment["RCT_METRO_PORT"] == nil)
    }
    @Test("every explicit endpoint reaches start, listener probing, failure hints and the retry record", arguments: [8081, 8097])
    func selectedPortSurvivesFailure(port: Int) async throws {
        let repo = try app()
        let anchor = try #require(ProjectAnchor.detect(from: repo.root))
        let logs = try temporaryLogs()
        let runner = FakeProcessRunner(responses: [
            "curl -s -i -m 2 http://localhost:\(port)/status": .failed(7, ""),
            MetroStatus.processTableCommand: .ok(""),
            "kill -0 4242": .failed(1, ""),
        ])
        var context = UpContext()
        await #expect(throws: DomainError.self) {
            try await MetroStage(anchor: anchor, runner: runner, logs: logs, bindWait: .zero, port: port).run(&context)
        }
        #expect(try logs.metroPort() == port)
        #expect(runner.log.spawned.first?.command.arguments == ["start", "--port", "\(port)"])
        #expect(runner.log.spawned.first?.command.environment["RCT_METRO_PORT"] == "\(port)")
    }

    @Test("a previous occupied endpoint blocks a port change without overwriting its record")
    func changedPortPreservesServer() async throws {
        let repo = try app()
        let anchor = try #require(ProjectAnchor.detect(from: repo.root))
        let logs = try temporaryLogs()
        try logs.recordMetroPort(8097)
        let runner = FakeProcessRunner(responses: [
            "curl -s -i -m 2 http://localhost:8097/status": .ok(MetroStatus.running(projectRoot: repo.root)),
        ])
        var context = UpContext()
        await #expect(throws: DomainError.self) {
            try await MetroStage(anchor: anchor, runner: runner, logs: logs, port: 8098).run(&context)
        }
        #expect(try logs.metroPort() == 8097)
        #expect(runner.log.spawned.isEmpty)
        #expect(runner.log.all.count == 1)
    }

    @Test("an unwritable endpoint record blocks Metro before spawn")
    func portRecordWriteFailure() async throws {
        let repo = try app()
        let anchor = try #require(ProjectAnchor.detect(from: repo.root))
        let blocked = try repo.write("not-a-directory", "preserve")
        let logs = RunLogs(project: repo.root, temporaryDirectory: blocked)
        let runner = FakeProcessRunner(responses: [MetroStatus.command: .failed(7, "")])
        var context = UpContext()
        await #expect(throws: (any Error).self) {
            try await MetroStage(anchor: anchor, runner: runner, logs: logs).run(&context)
        }
        #expect(runner.log.spawned.isEmpty)
        #expect(try String(contentsOf: blocked, encoding: .utf8) == "preserve")
    }
    @Test("without an explicit socket the project's default Watchman watch is dropped", arguments: [nil, ""] as [String?])
    func dropsWatchmanWatch(socketPath: String?) async throws {
        let repo = try app()
        let probe = "watchman watch-project \(repo.root.path)"
        let runner = FakeProcessRunner(responses: [
            "/usr/bin/printenv WATCHMAN_SOCK": socketPath.map { .ok($0 + "\n") } ?? .failed(1, ""),
            probe: .ok(#"{"watch": "/watched/root"}"#),
        ])

        await MetroLaunch.dropWatchmanWatch(of: repo.root, runner: runner)

        #expect(runner.log.first(matching: "watchman watch-del /watched/root") != nil)
    }

    @Test("without an answer from watchman there is no watch to drop")
    func noWatchmanNoDrop() async throws {
        let repo = try app()
        let runner = FakeProcessRunner(responses: ["/usr/bin/printenv WATCHMAN_SOCK": .failed(1, "")])

        await MetroLaunch.dropWatchmanWatch(of: repo.root, runner: runner)

        #expect(!runner.log.all.contains { $0.arguments.first == "watch-del" })
        #expect(runner.log.all.map(\.executable) == ["/usr/bin/printenv", "watchman"])
    }

    @Test("an explicit Metro Watchman socket is used for both fresh-crawl commands")
    func dropsConfiguredWatchmanWatch() async throws {
        let repo = try app()
        let socket = "/tmp/runstir watchman.sock"
        let options = ["--sockname=\(socket)", "--no-spawn", "--no-local"]
        let probe = ProcessCommand("watchman", options + ["watch-project", repo.root.path])
        let runner = FakeProcessRunner(responses: [
            "/usr/bin/printenv WATCHMAN_SOCK": .ok(socket + "\n"),
            probe.description: .ok(#"{"watch": "/watched/root"}"#),
        ])

        await MetroLaunch.dropWatchmanWatch(of: repo.root, runner: runner)

        #expect(runner.log.all.map(\.arguments) == [
            ["WATCHMAN_SOCK"],
            options + ["watch-project", repo.root.path],
            options + ["watch-del", "/watched/root"],
        ])
    }

    @Test("an unavailable explicit Watchman socket never falls back to the default server")
    func missingConfiguredWatchmanPreservesDefault() async throws {
        let repo = try app()
        let socket = "/tmp/missing-runstir-watchman.sock"
        let runner = FakeProcessRunner(responses: ["/usr/bin/printenv WATCHMAN_SOCK": .ok(socket + "\n")])

        await MetroLaunch.dropWatchmanWatch(of: repo.root, runner: runner)

        #expect(runner.log.all.map(\.arguments) == [
            ["WATCHMAN_SOCK"],
            ["--sockname=\(socket)", "--no-spawn", "--no-local", "watch-project", repo.root.path],
        ])
    }

    @Test("an uncertain project socket observation never reaches any Watchman server", arguments: [
        "exit2", "exit127", "signal", "stderr", "unterminated", "empty", "unset-output", "timeout", "cancel",
    ])
    func uncertainProjectSocketPreservesServers(_ fault: String) async throws {
        let repo = try app()
        let probe = "/usr/bin/printenv WATCHMAN_SOCK"
        let response: FakeProcessRunner.Response
        switch fault {
        case "exit2": response = .failed(2, "")
        case "exit127": response = .failed(127, "")
        case "signal": response = .init(status: .signaled(15))
        case "stderr": response = .init(standardOutput: "/tmp/private.sock\n", standardError: "unconfirmed environment\n")
        case "unterminated": response = .ok("/tmp/private.sock")
        case "unset-output": response = .init(status: .exited(1), standardOutput: "/tmp/private.sock\n")
        default: response = .ok("")
        }
        var failures: [String: any Error] = [:]
        if fault == "timeout" { failures[probe] = ProcessError.timedOut(command: probe, timeout: .seconds(15)) }
        if fault == "cancel" { failures[probe] = CancellationError() }
        let runner = FakeProcessRunner(responses: [probe: response], failures: failures)

        await MetroLaunch.dropWatchmanWatch(of: repo.root, runner: runner)

        #expect(runner.log.all.map(\.description) == [probe])
    }

    @Test("cancelling the actual task during its socket probe prevents detached Metro startup")
    func cancelledSocketProbePreventsStartup() async throws {
        let repo = try app()
        let anchor = try #require(ProjectAnchor.detect(from: repo.root))
        let runner = SocketProbeCancellingRunner()
        let task = Task {
            try await MetroLaunch.start(anchor: anchor, runner: runner,
                logFile: repo.url("metro.log"), afterReinstall: true)
        }

        do {
            _ = try await task.value
            Issue.record("cancelled socket probe still started Metro")
        } catch is CancellationError {}

        #expect(task.isCancelled)
        #expect(runner.base.log.all.map(\.description) == ["/usr/bin/printenv WATCHMAN_SOCK"])
        #expect(runner.base.log.spawned.isEmpty)
    }

    @Test("reinstalled Metro resets only the socket inherited by its actual project child", arguments: [false, true])
    func reinstalledMetroUsesProjectSocket(_ useMise: Bool) async throws {
        let repo = try app()
        let socket = repo.url("project watchman.sock").path
        let calls = repo.url("watchman-calls")
        let deleted = repo.url("deleted-socket")
        let metroSocket = repo.url("metro-socket")
        let watchman = try repo.write("bin/watchman", #"""
            #!/bin/sh
            printf '%s\n' "$@" >> "$RUNSTIR_WATCHMAN_CALLS"
            selected=default
            case "$1" in
                --sockname=*) selected=${1#--sockname=}; shift 3 ;;
            esac
            case "$1" in
                watch-project) printf '{"watch":"/watched/root"}\n' ;;
                watch-del) printf '%s\n' "$selected" >> "$RUNSTIR_DELETED_SOCKET" ;;
            esac
            """#)
        let yarn = try repo.write("bin/yarn", #"""
            #!/bin/sh
            printf '%s\n' "$WATCHMAN_SOCK" > "$RUNSTIR_METRO_SOCKET"
            """#)
        let mise = try repo.write("bin/mise", #"""
            #!/bin/sh
            export WATCHMAN_SOCK="$RUNSTIR_MISE_SOCKET"
            shift 2
            exec "$@"
            """#)
        for file in [watchman, yarn, mise] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        let host = SystemProcessRunner(environment: [
            "PATH": repo.url("bin").path + ":/usr/bin:/bin",
            "WATCHMAN_SOCK": useMise ? repo.url("host watchman.sock").path : socket,
            "RUNSTIR_MISE_SOCKET": socket,
            "RUNSTIR_WATCHMAN_CALLS": calls.path,
            "RUNSTIR_DELETED_SOCKET": deleted.path,
            "RUNSTIR_METRO_SOCKET": metroSocket.path,
        ])
        let runner: any ProcessRunner = useMise
            ? MiseProcessRunner(base: host, configDirectory: repo.root, executable: mise.path) : host
        _ = try await MetroLaunch.start(anchor: try #require(ProjectAnchor.detect(from: repo.root)),
            runner: runner, logFile: repo.url("metro.log"), afterReinstall: true)

        let deadline = ContinuousClock.now + .seconds(5)
        while !FileManager.default.fileExists(atPath: metroSocket.path), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let actualMetroSocket = try String(contentsOf: metroSocket, encoding: .utf8)
        let actualCalls = try String(contentsOf: calls, encoding: .utf8)
        let actualDeletedSocket = try String(contentsOf: deleted, encoding: .utf8)
        #expect(actualMetroSocket == socket + "\n")
        let options = ["--sockname=\(socket)", "--no-spawn", "--no-local"]
        let expected = options + ["watch-project", repo.root.path] + options + ["watch-del", "/watched/root"]
        #expect(actualCalls == expected.joined(separator: "\n") + "\n")
        #expect(actualDeletedSocket == socket + "\n")
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

        let runner = DelayedListenerRunner(FakeProcessRunner(responses: [
            MetroStatus.command: .failed(7, ""),
        ]), projectRoot: repo.root)
        let outcome = try await run(repo, runner, context: &context, logs: logs)

        #expect(outcome.status == .pass)
        let spawn = try #require(runner.log.spawned.first)
        // The project's own start script, through the manager the lockfile named.
        #expect(spawn.command.description == "yarn start")
        #expect(spawn.command.environment["FORCE_COLOR"] == "1")
        #expect(spawn.command.workingDirectory?.path == repo.root.path)
        #expect(spawn.logFile == (try logs.url("metro.log")))
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
        let runner = DelayedListenerRunner(FakeProcessRunner(responses: [
            MetroStatus.command: .failed(7, ""),
        ]), projectRoot: repo.root)
        var context = UpContext()

        _ = try await run(repo, runner, context: &context)

        let spawn = try #require(runner.log.spawned.first)
        #expect(spawn.command.description == "corepack yarn start")
        #expect(spawn.command.environment["COREPACK_ENABLE_NETWORK"] == "0")
        #expect(spawn.command.environment["FORCE_COLOR"] == "1")
        #expect(spawn.command.workingDirectory?.path == repo.root.path)
    }

    /// #61: the pid the spawn hands back is the start script's, and the bundler is
    /// two links below it — killing the reported one left 8081 held. So the port is
    /// asked who holds it, and that is the pid a reader is given.
    @Test("the pid holding 8081 is reported next to the process up started")
    func reportsTheListener() async throws {
        let repo = try app()
        let runner = DelayedListenerRunner(FakeProcessRunner(responses: [
            MetroStatus.command: .failed(7, ""),
        ]), projectRoot: repo.root)
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
            MetroStatus.processTableCommand: .ok(""),
            "kill -0 4242": .failed(1, "No such process"),
        ])
        var context = UpContext()

        let error = await #expect(throws: DomainError.self) {
            try await run(repo, runner, context: &context, logs: logs)
        }

        #expect(error?.observed?.contains("exited") == true)
        #expect(error?.remediation.command == "yarn start")
        #expect(error?.remediation.summary.contains(logs.directory.path) == true)
        #expect(context.metro?.pid == 4242)
        #expect(context.metro?.listenerPid == nil)
    }

    @Test("a live start process that never binds times out before build")
    func bindTimeout() async throws {
        let repo = try app()
        var responses = MetroStatus.startupResponses(projectRoot: repo.root)
        responses[MetroStatus.processTableCommand] = .ok("4242 1 Mon Oct 19 17:00:00 2026\n")
        responses["lsof -a -p 4242 -nP -iTCP:8081 -sTCP:LISTEN -t"] = .ok("")
        responses.merge([
            MetroStatus.command: .failed(7, ""),
            "kill -0 4242": .ok(""),
        ]) { _, new in new }
        let runner = FakeProcessRunner(responses: responses)
        var context = UpContext()

        let error = await #expect(throws: DomainError.self) {
            try await run(repo, runner, context: &context)
        }

        #expect(error?.observed?.contains("within") == true)
        #expect(context.metro?.state == .spawned)
        #expect(context.metro?.listenerPid == nil)
    }

    /// Android accepts a listener only when the Metro verdict says it is this
    /// project's; any other answer must keep waiting, never report it as started.
    @Test("a listener the caller does not accept is not reported as the started Metro")
    func unacceptedListener() async throws {
        let repo = try app()
        var responses = MetroStatus.startupResponses(projectRoot: repo.root)
        responses["kill -0 4242"] = .failed(1, "No such process")
        let runner = FakeProcessRunner(responses: responses)

        let readiness = try await MetroLaunch.readiness(
            startPID: 4242, anchor: repo.root, runner: runner, bindWait: .zero, poll: .zero
        ) { _ in false }

        #expect(readiness == .exited)
    }

    @Test("an initially empty listener probe passes when the next probe finds its owned listener")
    func delayedBind() async throws {
        let repo = try app()
        let projectRoot = repo.root
        let runner = NextProbeListenerRunner(projectRoot: projectRoot)

        let readiness = try await MetroLaunch.readiness(
            startPID: 4242, anchor: projectRoot, runner: runner, bindWait: .seconds(1), poll: .zero
        ) { _ in
            try await MetroVerdict.ask(anchor: projectRoot, runner: runner) == .mine
        }

        #expect(readiness == .listening(70947))
        let probes = await runner.listenerReadiness
        #expect(probes.count >= 2)
        #expect(probes.starts(with: [false, true]))
    }

    @Test("a cold Metro that binds after ten seconds passes with the production wait")
    func coldStartup() async throws {
        let repo = try app()
        let anchor = try #require(ProjectAnchor.detect(from: repo.root))
        let inner = FakeProcessRunner(responses: [
            MetroStatus.command: .failed(7, ""),
            "kill -0 4242": .ok(""),
        ])
        let runner = DelayedListenerRunner(inner, projectRoot: repo.root, bindDelay: .seconds(11))
        var context = UpContext()

        let outcome = try await MetroStage(
            anchor: anchor, runner: runner, logs: try temporaryLogs()
        ).run(&context)

        #expect(outcome.status == .pass)
        #expect(context.metro?.state == .spawned)
        #expect(context.metro?.listenerPid == 70947)
        #expect(inner.log.spawned.count == 1)
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

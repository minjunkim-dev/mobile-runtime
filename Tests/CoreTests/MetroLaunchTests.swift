import Foundation
import TestSupport
import Testing

@testable import Core

private actor StartupReplies: ProcessRunner {
    private let base: FakeProcessRunner
    private var sequences: [String: [FakeProcessRunner.Response]]
    private let cancelCommand: String?
    private let cancelOccurrence: Int
    private var occurrences: [String: Int] = [:]
    nonisolated let log: FakeProcessRunner.CallLog

    init(
        root: URL, port: Int = 8097, sequences: [String: [FakeProcessRunner.Response]] = [:],
        failures: [String: any Error] = [:], cancelCommand: String? = nil, cancelOccurrence: Int = 1
    ) {
        var responses = MetroStatus.startupResponses(projectRoot: root, port: port)
        responses["kill -0 4242"] = .ok("")
        let base = FakeProcessRunner(responses: responses, failures: failures)
        self.base = base
        self.log = base.log
        self.sequences = sequences
        self.sequences["curl -s -i -m 2 http://localhost:\(port)/status"] =
            sequences["curl -s -i -m 2 http://localhost:\(port)/status"]
            ?? [.failed(7, ""), .ok(MetroStatus.running(projectRoot: root))]
        self.cancelCommand = cancelCommand
        self.cancelOccurrence = cancelOccurrence
    }

    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        occurrences[command.description, default: 0] += 1
        if command.description == cancelCommand, occurrences[command.description] == cancelOccurrence {
            throw CancellationError()
        }
        var selected = base
        if var queue = sequences[command.description], let answer = queue.first {
            if queue.count > 1 { queue.removeFirst(); sequences[command.description] = queue }
            selected.responses[command.description] = answer
        }
        return try await selected.run(command, onLine: onLine)
    }

    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
        try await base.spawnDetached(command, logFile: logFile)
    }
}

private struct AfterMetro: Stage {
    let id = "after-metro"
    func run(_ context: inout UpContext) async throws -> StageOutcome { .pass("must not run after a failed startup") }
}

private func startupReport(
    _ repo: FixtureRepo, _ runner: any ProcessRunner, port: Int = 8097
) async throws -> UpReport {
    let anchor = try #require(ProjectAnchor.detect(from: repo.root))
    return await UpPipeline(stages: [
        MetroStage(anchor: anchor, runner: runner, logs: try .temporary(project: repo.root), bindWait: .zero, port: port),
        AfterMetro(),
    ]).run()
}

private func startupProject() throws -> FixtureRepo {
    let repo = try FixtureRepo()
    try repo.write("package.json", #"{"dependencies":{"react-native":"0.87.1"}}"#)
    try repo.write("package-lock.json", "{}")
    return repo
}

@Suite("Metro startup process identity")
struct MetroLaunchTests {
    @Test("startup ignores a slow global port scan and reports the actual child listener", arguments: [8081, 8097])
    func ownTreeOnly(port: Int) async throws {
        let repo = try startupProject()
        let global = "lsof -nP -iTCP:\(port) -sTCP:LISTEN -t"
        let runner = StartupReplies(root: repo.root, port: port, failures: [
            global: ProcessError.timedOut(command: global, timeout: .seconds(10)),
        ])
        let report = try await startupReport(repo, runner, port: port)
        #expect(report.exitCode == 0)
        #expect(report.context.metro?.pid == 4242)
        #expect(report.context.metro?.listenerPid == 70947)
        #expect(report.context.metro?.port == port)
        #expect(!runner.log.all.contains { $0.description == global })
        #expect(runner.log.all.contains {
            $0.description == "lsof -a -p 4242,4243,70947 -nP -iTCP:\(port) -sTCP:LISTEN -t"
        })
        #expect(runner.log.all.filter { $0.executable == "ps" || $0.executable == "lsof" }.allSatisfy {
            ($0.timeout ?? .seconds(99)) <= .seconds(10)
        })
    }

    @Test("a foreign or unidentified Metro that wins the startup race is preserved", arguments: [true, false])
    func foreignAfterSpawn(identifiable: Bool) async throws {
        let repo = try startupProject()
        let foreign = identifiable
            ? MetroStatus.running(projectRoot: URL(fileURLWithPath: "/another-project"))
            : MetroStatus.reply(body: "packager-status:running")
        let runner = StartupReplies(root: repo.root, sequences: [
            "curl -s -i -m 2 http://localhost:8097/status": [.failed(7, ""), .ok(foreign)],
        ])
        let report = try await startupReport(repo, runner)
        #expect(report.exitCode == 1)
        #expect(report.stages.map(\.id) == ["metro"])
        #expect(report.context.metro?.pid == 4242)
        #expect(report.context.metro?.listenerPid == nil)
        #expect(!runner.log.all.contains { $0.executable == "kill" && $0.arguments != ["-0", "4242"] })
    }

    @Test("malformed or cyclic process ancestry never becomes a listener", arguments: [
        "4242 1 Mon Oct 19 17:00:00 2026\n4242 1 Mon Oct 19 17:00:00 2026\n",
        "4242 4242 Mon Oct 19 17:00:00 2026\n",
        "4242 70947 Mon Oct 19 17:00:00 2026\n70947 4242 Mon Oct 19 17:00:00 2026\n",
        "bad 1 Mon Oct 19 17:00:00 2026\n",
        "2147483648 1 Mon Oct 19 17:00:00 2026\n",
        "-1 1 Mon Oct 19 17:00:00 2026\n",
        "4242 unknown Mon Oct 19 17:00:00 2026\n",
        "4242 1\n",
    ])
    func malformedTree(table: String) async throws {
        let repo = try startupProject()
        let runner = StartupReplies(root: repo.root, sequences: [MetroStatus.processTableCommand: [.ok(table)]])
        let report = try await startupReport(repo, runner)
        #expect(report.exitCode == 1)
        #expect(report.context.metro?.pid == 4242)
        #expect(report.context.metro?.listenerPid == nil)
        #expect(report.stages.map(\.id) == ["metro"])
        #expect(!runner.log.all.contains { $0.executable == "lsof" })
    }

    @Test("malformed duplicate or out-of-tree listener output is rejected", arguments: [
        "not-a-pid\n", "70947\n70947\n", "99999\n", "0\n", "-1\n",
    ])
    func malformedListener(output: String) async throws {
        let repo = try startupProject()
        let runner = StartupReplies(root: repo.root, sequences: [
            "lsof -a -p 4242,4243,70947 -nP -iTCP:8097 -sTCP:LISTEN -t": [.ok(output)],
        ])
        let report = try await startupReport(repo, runner)
        #expect(report.exitCode == 1)
        #expect(report.context.metro?.listenerPid == nil)
        #expect(report.stages.map(\.id) == ["metro"])
    }

    @Test("a root or listener whose cwd belongs elsewhere is rejected", arguments: [true, false])
    func wrongCWD(rootMoved: Bool) async throws {
        let repo = try startupProject()
        let key = rootMoved ? "lsof -a -p 4242 -d cwd -Fpn" : "lsof -a -p 4242,70947 -d cwd -Fpn"
        let answer = rootMoved ? "p4242\nn/another-project\n"
            : "p4242\nn\(repo.root.path)\np70947\nn/another-project\n"
        let runner = StartupReplies(root: repo.root, sequences: [key: [.ok(answer)]])
        let report = try await startupReport(repo, runner)
        #expect(report.exitCode == 1)
        #expect(report.context.metro?.listenerPid == nil)
    }

    @Test("changed ancestry or process birth between probes is not accepted", arguments: ["parent", "root-birth", "listener-birth"])
    func identityRace(change: String) async throws {
        let repo = try startupProject()
        let original = try #require(MetroStatus.startupResponses(projectRoot: repo.root)[MetroStatus.processTableCommand]).standardOutput
        let changed: String
        switch change {
        case "parent": changed = original.replacingOccurrences(of: "70947 4243", with: "70947 1")
        case "root-birth": changed = original.replacingOccurrences(of: "4242 1 Mon Oct 19 17:00:00", with: "4242 1 Mon Oct 19 17:01:00")
        default: changed = original.replacingOccurrences(of: "70947 4243 Mon Oct 19 17:00:02", with: "70947 4243 Mon Oct 19 17:01:02")
        }
        let runner = StartupReplies(root: repo.root, sequences: [
            MetroStatus.processTableCommand: [.ok(original), .ok(original), .ok(changed)],
        ])
        let report = try await startupReport(repo, runner)
        #expect(report.exitCode == 1)
        #expect(report.context.metro?.listenerPid == nil)
        #expect(report.stages.map(\.id) == ["metro"])
    }

    @Test("a PID-bound lsof timeout preserves partial context and stops later stages")
    func boundProbeTimeout() async throws {
        let repo = try startupProject()
        let command = "lsof -a -p 4242,4243,70947 -nP -iTCP:8097 -sTCP:LISTEN -t"
        let runner = StartupReplies(root: repo.root, failures: [
            command: ProcessError.timedOut(command: command, timeout: .seconds(10)),
        ])
        let report = try await startupReport(repo, runner)
        #expect(report.exitCode == 2)
        #expect(report.context.metro?.state == .spawned)
        #expect(report.context.metro?.pid == 4242)
        #expect(report.context.metro?.port == 8097)
        #expect(report.context.metro?.logPath?.hasSuffix("/metro.log") == true)
        #expect(report.context.metro?.listenerPid == nil)
        #expect(report.teardownHint?.contains("did not confirm a listener") == true)
        #expect(report.stages.map(\.id) == ["metro"])
    }

    @Test("cancellation in tree listener and accept probes stays exit130 with partial spawn", arguments: ["tree", "listener", "accept"])
    func cancellation(boundary: String) async throws {
        let repo = try startupProject()
        let command: String
        switch boundary {
        case "tree": command = MetroStatus.processTableCommand
        case "listener": command = "lsof -a -p 4242,4243,70947 -nP -iTCP:8097 -sTCP:LISTEN -t"
        default: command = "curl -s -i -m 2 http://localhost:8097/status"
        }
        let runner = StartupReplies(root: repo.root, cancelCommand: command, cancelOccurrence: boundary == "accept" ? 2 : 1)
        let report = try await startupReport(repo, runner)
        #expect(report.exitCode == 130)
        #expect(report.context.metro?.pid == 4242)
        #expect(report.context.metro?.listenerPid == nil)
        #expect(report.stages.map(\.id) == ["metro"])
        #expect(!runner.log.all.contains { $0.executable == "kill" && $0.arguments != ["-0", "4242"] })
    }

    @Test("public listener discovery keeps its global teardown contract")
    func globalDiscoveryUnchanged() async throws {
        let command = "lsof -nP -iTCP:8097 -sTCP:LISTEN -t"
        let runner = FakeProcessRunner(responses: [command: .ok("99999\n")])
        #expect(try await MetroLaunch.listeners(runner: runner, port: 8097) == [99999])
        #expect(runner.log.all.first?.timeout == .seconds(10))
    }
}


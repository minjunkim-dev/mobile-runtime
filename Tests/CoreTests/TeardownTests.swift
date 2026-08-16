import Foundation
import TestSupport
import Testing

@testable import Core

private struct JobFailed: Error {}

private func report(_ jobs: [Teardown.Job]) async -> TeardownReport {
    await Teardown(jobs: jobs).run()
}

@Suite("teardown")
struct TeardownTests {
    /// Not a pipeline: a Metro that would not die is no reason to leave the app
    /// running (ADR-0007), so both jobs run and both report.
    @Test("every job runs even after one fails")
    func noFailFast() async throws {
        let result = await report([
            (id: "metro", run: { .failed("metro", DomainError(summary: "still there", remediation: Remediation(summary: "…"))) }),
            (id: "app", run: { .stopped("app", "net.cozic.joplin") }),
        ])

        #expect(result.items.map(\.id) == ["metro", "app"])
        #expect(result.items.map(\.status) == [.failed, .stopped])
        #expect(result.exitCode == 1)
        #expect(result.status == .error)
    }

    /// Nothing of this project's was there. That is an answer — the run did its job
    /// and found no work — so it exits 0.
    @Test("nothing to stop is exit 0, not a warning")
    func nothingToStop() async throws {
        let result = await report([
            (id: "metro", run: { .skipped("metro", "nothing on 8081") }),
            (id: "app", run: { .skipped("app", "no install record — nothing to stop") }),
        ])

        #expect(result.stoppedNothing)
        #expect(result.exitCode == 0)
        #expect(result.status == .pass)
    }

    @Test("one thing stopped is not nothing to stop")
    func somethingStopped() async throws {
        let result = await report([
            (id: "metro", run: { .stopped("metro", "pid 65260") }),
            (id: "app", run: { .skipped("app", "no install record — nothing to stop") }),
        ])

        #expect(result.stoppedNothing == false)
        #expect(result.exitCode == 0)
    }

    /// A job that could not run says nothing about the thing it aimed at — it is the
    /// tool's problem (exit 2), and `failed` stays the word for "it is still there".
    @Test("a job that cannot run is the tool's problem, not the project's")
    func toolFailure() async throws {
        let result = await report([
            (id: "metro", run: { throw JobFailed() }),
            (id: "app", run: { .stopped("app", "net.cozic.joplin") }),
        ])

        #expect(result.items.first?.status == .unknown)
        #expect(result.toolFailures.count == 1)
        #expect(result.toolFailures.first?.hasPrefix("metro:") == true)
        #expect(result.exitCode == 2)
    }

    /// `--json` carries what was stopped, what was skipped, and what would not stop,
    /// under the envelope every command shares.
    @Test("the JSON document carries one item per thing down aimed at")
    func json() async throws {
        let result = await report([
            (id: "metro", run: { .stopped("metro", "pid 65260") }),
            (id: "app", run: { .skipped("app", "no install record — nothing to stop") }),
        ])

        let document = try DownJSONDocument(report: result, toolVersion: "0.1.0").encoded()

        #expect(document.contains("\"command\" : \"down\""))
        #expect(document.contains("\"status\" : \"stopped\""))
        #expect(document.contains("\"status\" : \"skipped\""))
        #expect(document.contains("\"schemaVersion\" : \(JSONOutput.schemaVersion)"))
    }

    /// stdout is the JSON document and nothing else, so a piped `down` stays
    /// parseable however much a human would have wanted to read.
    @Test("human lines and tool failures stay on stderr")
    func streams() async throws {
        let out = Mutable<[String]>([])
        let err = Mutable<[String]>([])
        let writer = DownWriter(
            json: true,
            toolVersion: "0.1.0",
            renderer: HumanReportRenderer(useColor: false),
            standardOutput: { line in out.mutate { $0.append(line) } },
            standardError: { line in err.mutate { $0.append(line) } }
        )

        try writer.finish(
            TeardownReport(items: [.stopped("metro", "pid 1")], toolFailures: ["app: no simctl"])
        )

        #expect(out.value.count == 1)
        #expect(out.value.first?.contains("\"command\" : \"down\"") == true)
        #expect(err.value == ["tool failure: app: no simctl"])
    }

    @Test("the human report says nothing to stop once, at the end")
    func humanNothingToStop() async throws {
        let err = Mutable<[String]>([])
        let writer = DownWriter(
            json: false,
            toolVersion: "0.1.0",
            renderer: HumanReportRenderer(useColor: false),
            standardOutput: { _ in },
            standardError: { line in err.mutate { $0.append(line) } }
        )

        try writer.finish(
            TeardownReport(items: [
                .skipped("metro", "nothing on 8081"),
                .skipped("app", "no install record — nothing to stop"),
            ])
        )

        #expect(err.value.first?.hasPrefix("metro") == true)
        #expect(err.value.last == "nothing to stop")
    }

    /// Somebody else's Metro on the port is not an empty machine. Saying "nothing to
    /// stop" there would report the opposite of what the line above it just said.
    @Test("a blocked port is not nothing to stop")
    func blocked() async throws {
        let blocker = DomainError(
            summary: "port 8081 is held by another project's Metro",
            observed: "it is serving /Users/me/mattermost-mobile",
            remediation: Remediation(summary: "…", command: "lsof -nP -iTCP:8081 -sTCP:LISTEN")
        )

        let result = await report([
            (id: "metro", run: { .blocked("metro", blocker) }),
            (id: "app", run: { .skipped("app", "no install record — nothing to stop") }),
        ])

        #expect(result.stoppedNothing == false)
        // Nothing of ours was there to stop, so nothing failed either.
        #expect(result.exitCode == 0)
        #expect(result.status == .pass)
        // The path the header gave and the line that names the process both survive
        // into the item — that identity is what ADR-0007 bought.
        let metro = try #require(result.items.first)
        #expect(metro.detail?.contains("mattermost-mobile") == true)
        #expect(metro.remediation?.command == "lsof -nP -iTCP:8081 -sTCP:LISTEN")
    }

    /// A blocked port never reaches the error renderer — it is not an error — so the
    /// line that names the process holding it has to come out here.
    @Test("a blocked item prints the command that names what is holding the port")
    func humanBlocked() async throws {
        let err = Mutable<[String]>([])
        let writer = DownWriter(
            json: false,
            toolVersion: "0.1.0",
            renderer: HumanReportRenderer(useColor: false),
            standardOutput: { _ in },
            standardError: { line in err.mutate { $0.append(line) } }
        )

        try writer.finish(
            TeardownReport(items: [
                .blocked(
                    "metro",
                    DomainError(
                        summary: "port 8081 is held by another project's Metro",
                        observed: "it is serving /Users/me/mattermost-mobile",
                        remediation: Remediation(summary: "…", command: "lsof -nP -iTCP:8081 -sTCP:LISTEN")
                    )
                )
            ])
        )

        #expect(err.value.contains { $0.contains("mattermost-mobile") })
        #expect(err.value.contains { $0.contains("lsof -nP -iTCP:8081 -sTCP:LISTEN") })
        #expect(err.value.contains("nothing to stop") == false)
    }

    /// A run that could not ask must not answer `pass`, and must not be counted as
    /// having found an empty machine.
    @Test("a job that could not run is unknown, and is not nothing to stop")
    func unknownIsNotEmpty() async throws {
        let result = await report([
            (id: "metro", run: { throw JobFailed() }),
            (id: "app", run: { .skipped("app", "no install record — nothing to stop") }),
        ])

        #expect(result.items.first?.status == .unknown)
        #expect(result.stoppedNothing == false)
        #expect(result.status == .unknown)
        #expect(result.exitCode == 2)
        // Whatever the exit code says, the envelope says it too.
        #expect(try DownJSONDocument(report: result, toolVersion: "0.1.0").encoded()
            .contains("\"error\""))
    }

    /// Standing outside a project is a failure of the run, not of a job — so it does
    /// not invent a third item id next to `metro` and `app`.
    @Test("a run that could not start carries its failure without inventing an item")
    func runFailure() async throws {
        let failure = DomainError(
            summary: "no React Native project here",
            remediation: Remediation(summary: "Run down from the project directory.")
        )

        let result = TeardownReport(items: [], failure: failure)

        #expect(result.items.isEmpty)
        #expect(result.exitCode == 1)
        #expect(try DownJSONDocument(report: result, toolVersion: "0.1.0").encoded()
            .contains("no React Native project here"))
    }

    /// Something that would not stop is the news. "Nothing to stop" next to it would
    /// read as a contradiction of the line above it.
    @Test("a failure is reported instead of nothing to stop")
    func humanFailure() async throws {
        let err = Mutable<[String]>([])
        let writer = DownWriter(
            json: false,
            toolVersion: "0.1.0",
            renderer: HumanReportRenderer(useColor: false),
            standardOutput: { _ in },
            standardError: { line in err.mutate { $0.append(line) } }
        )

        try writer.finish(
            TeardownReport(items: [
                .failed(
                    "metro",
                    DomainError(
                        summary: "this project's Metro is still on 8081 after SIGTERM",
                        remediation: Remediation(summary: "…", command: "lsof -nP -iTCP:8081 -sTCP:LISTEN")
                    )
                ),
                .skipped("app", "no install record — nothing to stop"),
            ])
        )

        #expect(err.value.contains("nothing to stop") == false)
        #expect(err.value.contains { $0.contains("after SIGTERM") })
        #expect(err.value.contains { $0.contains("lsof -nP -iTCP:8081") })
    }
}

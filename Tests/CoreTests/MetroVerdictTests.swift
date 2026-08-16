import Foundation
import TestSupport
import Testing

@testable import Core

private let anchor = URL(fileURLWithPath: "/Users/me/joplin/packages/app-mobile")

private func ask(_ response: FakeProcessRunner.Response, at directory: URL = anchor) async throws
    -> MetroVerdict
{
    try await MetroVerdict.ask(
        anchor: directory,
        runner: FakeProcessRunner(responses: [MetroStatus.command: response])
    )
}

@Suite("metro verdict")
struct MetroVerdictTests {
    /// The header is what `up` reuses on and what `down` kills on — one query,
    /// one answer, both verbs (ADR-0007).
    @Test("a Metro serving the anchor is mine")
    func mine() async throws {
        let verdict = try await ask(.ok(MetroStatus.running(projectRoot: anchor)))

        #expect(verdict == .mine)
        #expect(verdict.blocker == nil)
    }

    /// #45: joplin's app attached to mattermost's bundler and `up` said pass. The
    /// body says `running` for *any* Metro, so the body alone cannot be the answer.
    @Test("a Metro serving another project is not reusable, and is named")
    func another() async throws {
        let other = "/Users/me/mattermost-mobile"

        let verdict = try await ask(.ok(MetroStatus.running(projectRoot: URL(fileURLWithPath: other))))

        #expect(verdict == .another(projectRoot: other))
        let blocker = try #require(verdict.blocker)
        #expect(blocker.observed?.contains(other) == true)
        // The header is that process's cwd, not a React Native anchor, so the
        // command that gets pasted still points at the process (ADR-0006).
        #expect(blocker.remediation.command == "lsof -nP -iTCP:8081 -sTCP:LISTEN")
    }

    /// Two spellings of one directory — here a `.` component, and by the same call a
    /// symlinked `/var` against `/private/var` — are one directory.
    @Test("the header and the anchor are compared as paths, not as strings")
    func normalizesPaths() async throws {
        let verdict = try await ask(.ok(MetroStatus.running(projectRoot: anchor.appendingPathComponent("."))))

        #expect(verdict == .mine)
    }

    /// RN 0.76+ without `cli-server-api` serves no `/status` at all. Calling that
    /// "not Metro" would tell a user their own Metro belongs to somebody else.
    @Test("a port that answers without a /status is unidentifiable, not somebody else's")
    func unidentifiable() async throws {
        let verdict = try await ask(.ok(MetroStatus.reply("HTTP/1.1 404 Not Found", body: "Not found")))

        guard case .unidentifiable = verdict else {
            Issue.record("expected unidentifiable, got \(verdict)")
            return
        }
        let blocker = try #require(verdict.blocker)
        #expect(blocker.summary.contains("8081"))
        #expect(blocker.remediation.command == "lsof -nP -iTCP:8081 -sTCP:LISTEN")
    }

    /// A Metro that reports running but not where it runs cannot be reused either.
    @Test("a running Metro with no project root header is unidentifiable")
    func runningWithoutHeader() async throws {
        let verdict = try await ask(.ok(MetroStatus.reply(body: "packager-status:running")))

        guard case .unidentifiable = verdict else {
            Issue.record("expected unidentifiable, got \(verdict)")
            return
        }
    }

    @Test("a served page that is not Metro's stops the run")
    func notMetro() async throws {
        let verdict = try await ask(.ok(MetroStatus.reply(body: "<!DOCTYPE html><title>Grafana</title>")))

        guard case .notMetro = verdict else {
            Issue.record("expected notMetro, got \(verdict)")
            return
        }
        #expect(verdict.blocker?.summary.contains("not Metro") == true)
    }

    /// curl's `CURLE_COULDNT_CONNECT` — nothing is listening, and only then do we
    /// start one.
    @Test("a refused connection is an empty port")
    func empty() async throws {
        let verdict = try await ask(.failed(7, ""))

        #expect(verdict == .empty)
        #expect(verdict.blocker == nil)
    }

    /// A connection that opened and then said nothing is held, not empty.
    @Test("a port that answers slowly is held, not empty")
    func slowOccupant() async throws {
        let verdict = try await ask(.failed(28, ""))

        #expect(verdict.blocker?.observed?.contains("28") == true)
    }

    /// No answer at all is not a verdict — guessing "empty" starts a second Metro
    /// next to a live one.
    @Test("a curl that cannot run stays an infrastructure failure")
    func probeFailure() async throws {
        let runner = FakeProcessRunner(failures: [
            MetroStatus.command: ProcessError.spawnFailed(
                command: MetroStatus.command, underlying: FixtureMiss(command: "curl")
            )
        ])

        await #expect(throws: ProcessError.self) {
            try await MetroVerdict.ask(anchor: anchor, runner: runner)
        }
    }
}

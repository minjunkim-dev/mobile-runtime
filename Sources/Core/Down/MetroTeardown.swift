import Foundation

/// `down`'s Metro half: stop the bundler on 8081 when it is this project's, and say
/// why when it is not.
///
/// The "may I kill this" is `up`'s "may I reuse this" — one judge, `MetroVerdict`.
/// If the two ever split, `up` reuses a Metro `down` then refuses to clean up, and
/// the crack shows up in a user's terminal (ADR-0007).
///
/// Ownership is not tracked, so a Metro this project's own user started by hand is
/// stopped too. That is the accepted cost of keeping no state file: a stale pid
/// tells no one it is stale, and a hand-started Metro would otherwise be
/// unstoppable — which is one of the two Metros round 1 had to kill by hand.
public struct MetroTeardown: Sendable {
    public static let id = "metro"

    private let anchor: URL
    private let runner: any ProcessRunner
    /// How long `SIGTERM` is given before the port is asked again. Injected so tests
    /// spend nothing on it, the way `launch`'s settle is.
    private let grace: Duration

    public static let defaultGrace: Duration = .seconds(2)

    public init(anchor: URL, runner: any ProcessRunner, grace: Duration = MetroTeardown.defaultGrace) {
        self.anchor = anchor
        self.runner = runner
        self.grace = grace
    }

    public func run() async throws -> TeardownItem {
        let verdict = try await MetroVerdict.ask(anchor: anchor, runner: runner)

        // The three answers that stop `up` are the three that block `down`, and they
        // arrive with the sentence already written — which project the port is
        // serving, and the line that names the process holding it. `blocked` rather
        // than `skipped`: something is there, and "nothing to stop" would report an
        // empty machine.
        if let blocker = verdict.blocker { return .blocked(Self.id, blocker) }

        guard case .mine = verdict else {
            return .skipped(Self.id, "nothing on \(MetroVerdict.port)")
        }
        return try await stop()
    }

    private func stop() async throws -> TeardownItem {
        let pids = try await listeningPIDs()
        guard !pids.isEmpty else {
            // The port answered as this project's Metro a moment ago and lsof finds
            // nobody holding it. Two of our own tools disagreeing is our problem, not
            // the project's — it must not land on the project's exit code.
            throw ToolsDisagree(
                description: "\(MetroVerdict.port) answers as this project's Metro, but "
                    + "`\(Self.listenerCommand)` found no process listening on it"
            )
        }

        // SIGTERM only. A killed Metro skips its own shutdown and leaves watchman
        // subscriptions and children behind, which is the problem this decision
        // solves wearing a different hat — so `kill -9` is the human's to type, and
        // the remediation below types it for them (ADR-0007).
        for pid in pids {
            _ = try? await runner.run(ProcessCommand("kill", ["-TERM", "\(pid)"], timeout: .seconds(10)))
        }
        try await Task.sleep(for: grace)

        // The same judge again, and only an empty port proves the kill landed. Any
        // other answer means something is still on 8081 — reporting that as stopped
        // is the false negative #14 priced above a false positive, and it is the
        // exact shape of bug #45 was.
        let after = (try? await MetroVerdict.ask(anchor: anchor, runner: runner)) ?? .unidentifiable(
            observed: "the port could not be asked again after SIGTERM"
        )
        let listed = pids.map(String.init).joined(separator: ", ")
        switch after {
        case .empty:
            return .stopped(Self.id, pids.map { "pid \($0)" }.joined(separator: ", "))

        // Escalation is the human's call: a killed Metro skips its own shutdown and
        // leaves watchman subscriptions and children behind (ADR-0007).
        case .mine:
            return .failed(
                Self.id,
                DomainError(
                    summary: "this project's Metro is still on \(MetroVerdict.port) after SIGTERM",
                    observed: "pid \(listed)",
                    remediation: Remediation(
                        summary: "It was asked to stop and did not. See what it is doing first, "
                            + "and `kill -9 <pid>` if it has to go.",
                        command: Self.listenerCommand
                    )
                )
            )

        case .another, .unidentifiable, .notMetro:
            return .failed(
                Self.id,
                DomainError(
                    summary: "\(MetroVerdict.port) still answers after SIGTERM, and it can no "
                        + "longer be confirmed stopped",
                    observed: "pid \(listed) was asked to stop",
                    remediation: Remediation(
                        summary: "Something is on the port and it is no longer answering as this "
                            + "project's Metro. This says what is there now.",
                        command: Self.listenerCommand
                    )
                )
            )
        }
    }

    /// Asked at the moment it is needed rather than remembered from a run: a pid in a
    /// file goes stale silently, and a reused one points at a stranger.
    private func listeningPIDs() async throws -> [Int32] {
        let result = try await runner.run(
            ProcessCommand("lsof", MetroVerdict.listenerArguments + ["-t"], timeout: .seconds(10))
        )
        // Non-zero from lsof is "found nothing", which the caller reads as the
        // disagreement it is — there is nothing to interpret in the exit code itself.
        return result.standardOutput.split(separator: "\n").compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// The judge's own spelling of the question, so the line a user is handed and the
    /// line `down` runs cannot drift apart.
    private static let listenerCommand = MetroVerdict.listenerCommand
}

/// Two of mobile's own probes contradicting each other. Infrastructure, like
/// `ProcessError` — the project did nothing wrong and can do nothing about it.
struct ToolsDisagree: Error, CustomStringConvertible {
    let description: String
}

import Testing

@testable import Core

private struct StubCheck: Check {
    let id: String
    var category = "Stub"
    var title = "stub check"
    var dependsOn: [String] = []
    var outcome: @Sendable () async throws -> CheckOutcome

    func run() async throws -> CheckOutcome { try await outcome() }
}

private func stub(
    _ id: String,
    category: String = "Stub",
    dependsOn: [String] = [],
    _ outcome: @escaping @Sendable () async throws -> CheckOutcome
) -> StubCheck {
    StubCheck(id: id, category: category, dependsOn: dependsOn, outcome: outcome)
}

@Suite("DoctorEngine")
struct DoctorEngineTests {
    @Test("runs every check even when one fails — no fail-fast")
    func runsAll() async {
        let report = await DoctorEngine(checks: [
            stub("a") { .error(remediation: Remediation(summary: "fix a")) },
            stub("b") { .pass(observed: "b is fine") },
        ]).run()

        #expect(report.checks.map(\.id) == ["a", "b"])
        #expect(report.status == .error)
    }

    @Test("aggregate status is error > warning > unknown > pass")
    func aggregateSeverity() {
        #expect(CheckStatus.aggregate([.pass, .unknown]) == .unknown)
        #expect(CheckStatus.aggregate([.unknown, .warning]) == .warning)
        #expect(CheckStatus.aggregate([.warning, .error]) == .error)
        #expect(CheckStatus.aggregate([.pass, .pass]) == .pass)
        #expect(CheckStatus.aggregate([]) == .pass)
    }

    @Test("a check whose dependency did not pass becomes unknown and never runs")
    func dependencyBecomesUnknown() async {
        let ran = Mutable(false)
        let report = await DoctorEngine(checks: [
            stub("root") { .error(remediation: Remediation(summary: "fix root")) },
            stub("leaf", dependsOn: ["root"]) {
                ran.value = true
                return .pass()
            },
        ]).run()

        #expect(ran.value == false)
        #expect(report.checks.last?.status == .unknown)
        #expect(report.checks.last?.outcome.reason?.contains("root") == true)
    }

    @Test("a subset pulls in the dependencies it needs")
    func subsetPullsDependencies() async {
        let report = await DoctorEngine(checks: [
            stub("root") { .pass(observed: "root ok") },
            stub("other") { .pass() },
            stub("leaf", dependsOn: ["root"]) { .pass() },
        ]).run(only: ["leaf"])

        #expect(report.checks.map(\.id) == ["root", "leaf"])
    }

    @Test("a thrown DomainError becomes an error result carrying its remediation")
    func domainErrorBecomesResult() async throws {
        let report = await DoctorEngine(checks: [
            stub("a") {
                throw DomainError(
                    summary: "broken",
                    observed: "observed detail",
                    remediation: Remediation(summary: "do the thing", command: "run me")
                )
            }
        ]).run()

        let check = try #require(report.checks.first)
        #expect(check.status == .error)
        // The interpreted sentence leads; the raw tool output follows it.
        #expect(check.outcome.observed == "broken — observed detail")
        #expect(check.outcome.remediation?.command == "run me")
        #expect(report.hasToolFailure == false)
    }

    @Test("an infrastructure error is a tool failure, and the other checks still run")
    func infrastructureErrorIsToolFailure() async throws {
        let report = await DoctorEngine(checks: [
            stub("a") { throw ProcessError.timedOut(command: "sleep 30", timeout: .seconds(1)) },
            stub("b") { .pass(observed: "still ran") },
        ]).run()

        #expect(report.checks.first?.status == .unknown)
        #expect(report.checks.last?.outcome.observed == "still ran")
        #expect(report.hasToolFailure)
        #expect(report.toolFailures.first?.contains("a:") == true)
    }

    @Test("independent checks run concurrently")
    func independentChecksAreConcurrent() async {
        let started = Counter()
        // Each check waits until both have started; a serial engine would deadlock
        // into the timeout instead of finishing.
        let gate: @Sendable () async throws -> CheckOutcome = {
            await started.increment()
            while await started.value < 2 {
                try await Task.sleep(for: .milliseconds(5))
            }
            return .pass()
        }

        let report = await DoctorEngine(checks: [stub("a", gate), stub("b", gate)]).run()

        #expect(report.status == .pass)
    }

    @Test("exit code: 0 for no errors, 1 for a domain failure, 2 for a tool failure")
    func exitCodes() async {
        let clean = await DoctorEngine(checks: [stub("a") { .pass() }]).run()
        #expect(clean.exitCode == 0)

        let warned = await DoctorEngine(checks: [
            stub("a") { .warning(remediation: Remediation(summary: "tidy up")) },
            stub("b") { .unknown(reason: "cannot tell") },
        ]).run()
        #expect(warned.exitCode == 0)

        let failed = await DoctorEngine(checks: [
            stub("a") { .error(remediation: Remediation(summary: "fix it")) }
        ]).run()
        #expect(failed.exitCode == 1)

        let broken = await DoctorEngine(checks: [
            stub("a") { throw ProcessError.timedOut(command: "sleep 30", timeout: .seconds(1)) }
        ]).run()
        #expect(broken.exitCode == 2)
    }
}

private final class Mutable<Value: Sendable>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}

private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}

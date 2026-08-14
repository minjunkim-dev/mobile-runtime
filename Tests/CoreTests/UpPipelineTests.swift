import Testing
import TestSupport

@testable import Core

/// Every stub runs a command through the one seam, so "did this stage run" is
/// answered by the CallLog rather than by a flag only the test can see.
private struct StubStage: Stage {
    let id: String
    let runner: FakeProcessRunner
    var outcome: @Sendable (inout UpContext) async throws -> StageOutcome = { _ in .pass() }

    func run(_ context: inout UpContext) async throws -> StageOutcome {
        _ = try? await runner.run(ProcessCommand("echo", [id]))
        return try await outcome(&context)
    }
}

private func stage(
    _ id: String,
    _ runner: FakeProcessRunner,
    _ outcome: @escaping @Sendable (inout UpContext) async throws -> StageOutcome = { _ in .pass() }
) -> StubStage {
    StubStage(id: id, runner: runner, outcome: outcome)
}

@Suite("UpPipeline")
struct UpPipelineTests {
    @Test("stages run in order and each result carries its status and detail")
    func runsInOrder() async {
        let runner = FakeProcessRunner()
        let report = await UpPipeline(stages: [
            stage("validate", runner),
            stage("dependencies", runner) { _ in .skipped("node_modules present") },
        ]).run()

        #expect(report.stages.map(\.id) == ["validate", "dependencies"])
        #expect(report.stages.map(\.status) == [.pass, .skipped])
        #expect(report.stages.last?.detail == "node_modules present")
        #expect(report.status == .pass)
        #expect(report.exitCode == 0)
    }

    /// fail-fast, stated the only way it can be observed from outside: the commands
    /// of the stages behind the failure never left.
    @Test("a failed stage stops the ones behind it")
    func failFast() async {
        let runner = FakeProcessRunner()
        let report = await UpPipeline(stages: [
            stage("validate", runner),
            stage("dependencies", runner) { _ in
                throw DomainError(summary: "install failed", remediation: Remediation(summary: "run it by hand"))
            },
            stage("device", runner),
        ]).run()

        #expect(runner.log.all.map(\.description) == ["echo validate", "echo dependencies"])
        #expect(report.stages.map(\.id) == ["validate", "dependencies"])
        #expect(report.stages.last?.status == .failed)
        #expect(report.exitCode == 1)
    }

    @Test("exit code: 0 clean, 1 domain failure, 2 tool failure")
    func exitCodes() async {
        let runner = FakeProcessRunner()

        let clean = await UpPipeline(stages: [stage("validate", runner)]).run()
        #expect(clean.exitCode == 0)

        let domain = await UpPipeline(stages: [
            stage("validate", runner) { _ in
                throw DomainError(summary: "no", remediation: Remediation(summary: "fix it"))
            }
        ]).run()
        #expect(domain.exitCode == 1)
        #expect(domain.failure?.message.contains("no") == true)
        #expect(domain.failure?.remediation?.summary == "fix it")

        let tool = await UpPipeline(stages: [
            stage("validate", runner) { _ in
                throw ProcessError.timedOut(command: "sleep 30", timeout: .seconds(1))
            }
        ]).run()
        #expect(tool.exitCode == 2)
        // The stage id belongs in the message: nothing else names where it broke.
        #expect(tool.failure?.message.contains("validate") == true)
        #expect(tool.failure?.remediation == nil)
    }

    @Test("a stage reads what the stage before it put in the context")
    func contextFlowsForward() async {
        let runner = FakeProcessRunner()
        let seen = Mutable<DoctorReport?>(nil)
        let validation = DoctorReport(checks: [
            CheckResult(id: "a", category: "Stub", title: "a", outcome: .pass())
        ])

        let report = await UpPipeline(stages: [
            stage("validate", runner) { context in
                context.validation = validation
                return .pass()
            },
            stage("dependencies", runner) { context in
                seen.value = context.validation
                return .pass()
            },
        ]).run()

        #expect(seen.value?.checks.map(\.id) == ["a"])
        #expect(report.context.validation?.checks.map(\.id) == ["a"])
    }

    /// Progress is printed as it happens, so the callback has to fire per stage —
    /// including for the one that failed.
    @Test("each finished stage is reported as it finishes")
    func reportsProgress() async {
        let runner = FakeProcessRunner()
        let seen = Mutable<[String]>([])

        _ = await UpPipeline(stages: [
            stage("validate", runner),
            stage("dependencies", runner) { _ in
                throw DomainError(summary: "no", remediation: Remediation(summary: "fix it"))
            },
        ]).run { result in
            seen.value.append("\(result.id) \(result.status.rawValue)")
        }

        #expect(seen.value == ["validate pass", "dependencies failed"])
    }
}

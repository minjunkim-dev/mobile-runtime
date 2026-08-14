import Testing

@testable import Core

private struct StubCheck: Check {
    let id: String
    var category = "Stub"
    var title = "stub check"
    var outcome: @Sendable () async throws -> CheckOutcome

    func run() async throws -> CheckOutcome { try await outcome() }
}

private func engine(_ checks: [StubCheck]) -> DoctorEngine {
    DoctorEngine(checks: checks)
}

private func check(
    _ id: String,
    _ outcome: @escaping @Sendable () async throws -> CheckOutcome
) -> StubCheck {
    StubCheck(id: id, outcome: outcome)
}

@Suite("validate stage")
struct ValidateStageTests {
    @Test("only the declared ids run — doctor's other checks stay out")
    func runsDeclaredIDsOnly() async throws {
        let stage = ValidateStage(
            engine: engine([
                check("wanted") { .pass() },
                check("android.sdk") { .error(remediation: Remediation(summary: "never asked for")) },
            ]),
            checkIDs: ["wanted"]
        )

        var context = UpContext()
        let outcome = try await stage.run(&context)

        #expect(outcome.status == .pass)
        #expect(context.validation?.checks.map(\.id) == ["wanted"])
    }

    @Test("an error stops the pipeline and carries the check's own remediation")
    func errorFails() async throws {
        let stage = ValidateStage(
            engine: engine([
                check("xcode.installed") { .pass() },
                check("simulator.runtime") {
                    .error(
                        observed: "no iOS 26 runtime",
                        remediation: Remediation(summary: "Install it.", command: "xcodebuild -downloadPlatform iOS")
                    )
                },
            ]),
            checkIDs: ["xcode.installed", "simulator.runtime"]
        )

        var context = UpContext()
        let error = await #expect(throws: DomainError.self) {
            try await stage.run(&context)
        }

        #expect(error?.remediation.command == "xcodebuild -downloadPlatform iOS")
        // What was observed, not the check's title: the title reads like good news on
        // the line that says the run stopped.
        #expect(error?.summary == "no iOS 26 runtime")
        // The report survives the throw: the failure renders through doctor's renderer.
        #expect(context.validation?.status == .error)
    }

    @Test("several errors are counted, and the first one is still named")
    func severalErrors() async {
        func broken(_ id: String, _ observed: String) -> StubCheck {
            check(id) { .error(observed: observed, remediation: Remediation(summary: "fix \(id)")) }
        }
        let stage = ValidateStage(
            engine: engine([broken("xcode.installed", "no Xcode"), broken("node.version", "no Node")]),
            checkIDs: ["xcode.installed", "node.version"]
        )

        var context = UpContext()
        let error = await #expect(throws: DomainError.self) { try await stage.run(&context) }

        #expect(error?.summary == "2 environment checks failed")
        #expect(error?.observed == "no Xcode")
        #expect(error?.remediation.summary == "fix xcode.installed")
    }

    @Test("warning and unknown are reported and do not stop the pipeline")
    func warningsPass() async throws {
        let stage = ValidateStage(
            engine: engine([
                check("node.version") { .warning(remediation: Remediation(summary: "switch node")) },
                check("ruby.version") { .unknown(reason: "no ruby pinned") },
                check("xcode.installed") { .pass() },
            ]),
            checkIDs: ["node.version", "ruby.version", "xcode.installed"]
        )

        var context = UpContext()
        let outcome = try await stage.run(&context)

        #expect(outcome.status == .pass)
        #expect(outcome.detail == "2 of 3 checks need attention")
        #expect(context.validation?.status == .warning)
    }

    @Test("an all-pass validate says nothing beyond pass")
    func cleanPass() async throws {
        let stage = ValidateStage(
            engine: engine([check("xcode.installed") { .pass() }]),
            checkIDs: ["xcode.installed"]
        )

        var context = UpContext()
        #expect(try await stage.run(&context).detail == nil)
    }

    /// A check that could not run is the tool's problem, not the project's — exit 2,
    /// the same split doctor makes.
    @Test("a check that could not run is a tool failure")
    func toolFailureExitsTwo() async {
        let stage = ValidateStage(
            engine: engine([
                check("simulator.daemon") {
                    throw ProcessError.timedOut(command: "xcrun simctl list", timeout: .seconds(1))
                }
            ]),
            checkIDs: ["simulator.daemon"]
        )

        let report = await UpPipeline(stages: [stage]).run()

        #expect(report.exitCode == 2)
        #expect(report.failure?.message.contains("simctl") == true)
    }
}

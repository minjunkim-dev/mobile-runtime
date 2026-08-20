import Foundation

/// A Check that could not run at all. Not a `DomainError`: nothing about the
/// project is wrong, so it must not land on the project's exit code.
struct ValidationToolFailure: Error, CustomStringConvertible {
    let failures: [String]
    var description: String { failures.joined(separator: "; ") }
}

/// `validate` — the environment gate, run before anything is built. It is doctor's
/// engine over a **named** subset of doctor's Checks, so what doctor calls an error
/// `up` calls an error too, and the id `up` names is the id doctor answers to.
///
/// - Parameter checkIDs: declared by the caller, never "everything registered". A
///   future Android or host Check would otherwise slip into an iOS `up` unasked.
public struct ValidateStage: Stage {
    public let id = "validate"

    private let engine: DoctorEngine
    private let checkIDs: Set<String>
    private let promoteToError: @Sendable (CheckResult) -> Bool

    public init(
        engine: DoctorEngine,
        checkIDs: Set<String>,
        promoteToError: @escaping @Sendable (CheckResult) -> Bool = { _ in false }
    ) {
        self.engine = engine
        self.checkIDs = checkIDs
        self.promoteToError = promoteToError
    }

    public func run(_ context: inout UpContext) async throws -> StageOutcome {
        let doctorReport = await engine.run(only: checkIDs)
        let report = DoctorReport(
            checks: doctorReport.checks.map { result in
                guard result.status == .warning, promoteToError(result),
                    let remediation = result.outcome.remediation
                else { return result }
                return CheckResult(
                    id: result.id,
                    category: result.category,
                    title: result.title,
                    outcome: .error(
                        observed: result.outcome.observed,
                        required: result.outcome.required,
                        source: result.outcome.source,
                        remediation: remediation
                    )
                )
            },
            toolFailures: doctorReport.toolFailures
        )
        // Kept before any throw: the report is what gets rendered, pass or fail.
        context.validation = report

        if report.hasToolFailure {
            throw ValidationToolFailure(failures: report.toolFailures)
        }

        let failed = report.checks.filter { $0.status == .error }
        if let first = failed.first {
            // What the Check observed, not its title: a title says what was required
            // ("mobile.yml names a simulator that exists"), which reads like good news
            // on the line that says the run stopped.
            let cause = first.outcome.observed ?? first.title
            throw DomainError(
                summary: failed.count == 1 ? cause : "\(failed.count) environment checks failed",
                observed: failed.count == 1 ? nil : cause,
                remediation: first.outcome.remediation ?? Self.askDoctor
            )
        }

        // warning and unknown are said out loud and stepped over: "works but drifted"
        // and "cannot tell" are both poor reasons to refuse to build (ADR-0004).
        let noteworthy = report.checks.filter { $0.status != .pass }.count
        return .pass(
            noteworthy == 0 ? nil : "\(noteworthy) of \(report.checks.count) checks need attention"
        )
    }

    /// Only reachable if a Check ever reports an error without remediation, which the
    /// `CheckOutcome.error` signature forbids — but a dead end with no next step is
    /// worse than one redundant line.
    private static let askDoctor = Remediation(
        summary: "Run doctor to see the full report.", command: "mobile doctor"
    )
}

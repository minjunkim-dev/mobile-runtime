import Foundation

/// Why `up` stopped. The two cases are the two exit codes: a project problem the
/// user can act on, and a tool problem they cannot.
public enum UpFailure: Sendable {
    case domain(DomainError)
    /// Already spelled with the stage that hit it — nothing else names where it broke.
    case tool(String)

    public var message: String {
        switch self {
        case .domain(let error): error.message
        case .tool(let description): description
        }
    }

    public var remediation: Remediation? {
        switch self {
        case .domain(let error): error.remediation
        case .tool: nil
        }
    }
}

/// What a run of `up` produced: every Stage that finished, whatever the Stages left
/// in the context, and the failure that stopped it.
public struct UpReport: Sendable {
    public let stages: [StageResult]
    public let context: UpContext
    public let failure: UpFailure?

    public init(stages: [StageResult], context: UpContext = UpContext(), failure: UpFailure? = nil) {
        self.stages = stages
        self.context = context
        self.failure = failure
    }

    /// The envelope's verdict, in the same vocabulary doctor uses: a machine that
    /// makes doctor say `warning` must not make up say `pass`. Only `error` is the
    /// pipeline's own word — the rest is whatever the Stages observed.
    public var status: CheckStatus {
        failure == nil ? (context.validation?.status ?? .pass) : .error
    }

    /// What a failed run leaves behind that a user can clean up in one line. Only
    /// when this run started the Metro: a reused one was there before, and telling
    /// someone to stop what they were already using is not a next step. `up` does
    /// not roll back (#13), so the line is worth carrying — on both streams, which
    /// is why it is written here rather than at one of them.
    public var teardownHint: String? {
        guard failure != nil, context.metro?.state == .spawned else { return nil }
        return "The Metro this run started is still on \(MetroVerdict.port) — "
            + "`mobile down` stops it."
    }

    /// The same split doctor makes: 1 is the project's problem, 2 is ours. 64 (usage)
    /// is the CLI parser's.
    public var exitCode: Int32 {
        switch failure {
        case .none: 0
        case .domain: 1
        case .tool: 2
        }
    }
}

/// Runs Stages in order and stops at the first failure. Serial and fail-fast, the
/// opposite of `DoctorEngine` on both counts — a Stage builds on the one before it,
/// so running past a failure would only produce damage that needs explaining.
public struct UpPipeline: Sendable {
    private let stages: [any Stage]

    public init(stages: [any Stage]) {
        self.stages = stages
    }

    /// - Parameter onStageFinished: called as each Stage lands, so progress is
    ///   printed while the pipeline runs rather than collected for the end.
    public func run(
        onStageFinished: (@Sendable (StageResult) -> Void)? = nil
    ) async -> UpReport {
        var context = UpContext()
        var results: [StageResult] = []

        for stage in stages {
            let start = ContinuousClock.now

            func finish(_ status: StageStatus, _ detail: String?) -> StageResult {
                let result = StageResult(
                    id: stage.id, status: status, duration: start.duration(to: .now), detail: detail
                )
                results.append(result)
                onStageFinished?(result)
                return result
            }

            do {
                let outcome = try await stage.run(&context)
                _ = finish(outcome.status, outcome.detail)
            } catch let error as DomainError {
                _ = finish(.failed, error.summary)
                return UpReport(stages: results, context: context, failure: .domain(error))
            } catch {
                _ = finish(.failed, "could not run")
                return UpReport(
                    stages: results, context: context, failure: .tool("\(stage.id): \(error)")
                )
            }
        }

        return UpReport(stages: results, context: context)
    }
}

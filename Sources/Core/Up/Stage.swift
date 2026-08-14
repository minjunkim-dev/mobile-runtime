import Foundation

/// How a Stage ended. Deliberately not `CheckStatus`: a Check hands down a verdict
/// on the machine, a Stage reports what it did to it. `skipped` is the honest word
/// for work that was already done — nothing to warn about, nothing to install.
public enum StageStatus: String, Sendable, Codable {
    case pass
    case skipped
    case failed
}

/// What a Stage says when it is done. Failure is thrown, never returned — a Stage
/// that failed has no result to hand forward, and the pipeline stops there.
public struct StageOutcome: Sendable, Equatable {
    public let status: StageStatus
    /// The one thing worth reading on the progress line — which device, which
    /// scheme, why it was skipped. nil when the status already says everything.
    public let detail: String?

    public static func pass(_ detail: String? = nil) -> StageOutcome {
        StageOutcome(status: .pass, detail: detail)
    }

    public static func skipped(_ detail: String? = nil) -> StageOutcome {
        StageOutcome(status: .skipped, detail: detail)
    }
}

/// A finished Stage, with the time it took. `id` is a stable contract — scripts and
/// JSON consumers hold on to it, so renaming one is a breaking change.
public struct StageResult: Sendable, Equatable {
    public let id: String
    public let status: StageStatus
    public let duration: Duration
    public let detail: String?

    public init(id: String, status: StageStatus, duration: Duration, detail: String? = nil) {
        self.id = id
        self.status = status
        self.duration = duration
        self.detail = detail
    }

    public var durationMs: Int { Int((duration.seconds * 1000).rounded()) }
}

/// What the Stages hand each other. Explicit and passed through the pipeline, so a
/// Stage can only read what an earlier one actually put here — no global state, and
/// no Stage reaching sideways into another's internals.
public struct UpContext: Sendable {
    /// `validate`'s report, kept past the stage that produced it: a failure renders
    /// through doctor's renderer, and warnings still have to be shown.
    public var validation: DoctorReport?

    public init() {}
}

/// One step of `up`. Unlike a Check, a Stage exists for its side effect, its place
/// in the order is part of the contract, and it consumes what the Stage before it
/// produced. The two never merge into one type.
public protocol Stage: Sendable {
    /// Stable contract. Never rename.
    var id: String { get }

    func run(_ context: inout UpContext) async throws -> StageOutcome
}

extension Duration {
    var seconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) * 1e-18
    }
}

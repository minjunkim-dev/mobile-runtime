import Foundation

/// The result of a Check. `unknown` says "I can't tell" out loud instead of
/// staying silent — a silent pass is the failure mode that breaks trust.
public enum CheckStatus: String, Sendable, Codable, CaseIterable {
    case pass
    case warning
    case error
    case unknown

    /// error > warning > unknown > pass
    var severity: Int {
        switch self {
        case .pass: 0
        case .unknown: 1
        case .warning: 2
        case .error: 3
        }
    }

    public static func aggregate(_ statuses: some Sequence<CheckStatus>) -> CheckStatus {
        statuses.max { $0.severity < $1.severity } ?? .pass
    }
}

/// Recovery guidance. Mandatory on `warning`/`error`. Shared with `up`'s failures —
/// doctor does not get its own message system.
public struct Remediation: Sendable, Codable, Equatable {
    public let summary: String
    public let command: String?
    public let url: String?

    public init(summary: String, command: String? = nil, url: String? = nil) {
        self.summary = summary
        self.command = command
        self.url = url
    }
}

/// Where the requirement came from. `tier` is nil for host checks, which compare
/// against nothing but the machine itself.
public struct CheckSource: Sendable, Codable, Equatable {
    public let tier: Int?
    public let origin: String

    public init(tier: Int? = nil, origin: String) {
        self.tier = tier
        self.origin = origin
    }

    public static let host = CheckSource(origin: "host")
}

/// What a Check produces. The id/category/title come from the Check itself, so
/// the outcome carries only the verdict.
public struct CheckOutcome: Sendable, Equatable {
    public let status: CheckStatus
    public let observed: String?
    public let required: String?
    public let source: CheckSource
    public let remediation: Remediation?
    public let reason: String?

    private init(
        status: CheckStatus,
        observed: String?,
        required: String?,
        source: CheckSource,
        remediation: Remediation?,
        reason: String?
    ) {
        self.status = status
        self.observed = observed
        self.required = required
        self.source = source
        self.remediation = remediation
        self.reason = reason
    }

    /// The one line a category summary can afford. A `warning` or an `error` is
    /// unreadable without its target — "Node 24.19.0" does not say what is wrong with
    /// 24.19.0, and the remediation under it says how to change versions without
    /// saying to which. `pass` has nothing to move towards, and `unknown` carries its
    /// reason instead. Source and tier stay behind `-v`.
    var headline: String? {
        guard let observed else { return nil }
        guard status == .warning || status == .error, let required else { return observed }
        return "\(observed) → \(required)"
    }

    public static func pass(
        observed: String? = nil,
        required: String? = nil,
        source: CheckSource = .host
    ) -> CheckOutcome {
        CheckOutcome(
            status: .pass, observed: observed, required: required,
            source: source, remediation: nil, reason: nil
        )
    }

    public static func warning(
        observed: String? = nil,
        required: String? = nil,
        source: CheckSource = .host,
        remediation: Remediation
    ) -> CheckOutcome {
        CheckOutcome(
            status: .warning, observed: observed, required: required,
            source: source, remediation: remediation, reason: nil
        )
    }

    public static func error(
        observed: String? = nil,
        required: String? = nil,
        source: CheckSource = .host,
        remediation: Remediation
    ) -> CheckOutcome {
        CheckOutcome(
            status: .error, observed: observed, required: required,
            source: source, remediation: remediation, reason: nil
        )
    }

    public static func unknown(
        reason: String,
        observed: String? = nil,
        required: String? = nil,
        source: CheckSource = .host
    ) -> CheckOutcome {
        CheckOutcome(
            status: .unknown, observed: observed, required: required,
            source: source, remediation: nil, reason: reason
        )
    }
}

/// A Check result with its identity attached. `id` is a stable contract —
/// renaming one is a breaking change; `title` is display-only.
public struct CheckResult: Sendable, Equatable {
    public let id: String
    public let category: String
    public let title: String
    public let outcome: CheckOutcome

    public var status: CheckStatus { outcome.status }

    public init(id: String, category: String, title: String, outcome: CheckOutcome) {
        self.id = id
        self.category = category
        self.title = title
        self.outcome = outcome
    }
}

public protocol Check: Sendable {
    /// Stable contract. Never rename.
    var id: String { get }
    /// Display grouping, by subject (Xcode / iOS Simulator / Node / …), not by tier.
    var category: String { get }
    var title: String { get }
    /// Ids that must pass first. A dependency that did not pass turns this Check
    /// into `unknown` rather than a second copy of the same error.
    var dependsOn: [String] { get }

    func run() async throws -> CheckOutcome
}

extension Check {
    public var dependsOn: [String] { [] }
}

/// A failure interpreted from a tool's exit code + stderr, carrying its own
/// recovery guidance. Distinct from `ProcessError`, which is infrastructure.
public struct DomainError: Error, Sendable, Equatable {
    public let summary: String
    public let observed: String?
    public let remediation: Remediation

    public init(summary: String, observed: String? = nil, remediation: Remediation) {
        self.summary = summary
        self.observed = observed
        self.remediation = remediation
    }
}

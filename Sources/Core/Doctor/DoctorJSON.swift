import Foundation

/// The `--json` document: envelope + doctor body. Consumers key off `id`, so the
/// shape is a contract.
public struct DoctorJSONDocument: Encodable, Sendable {
    public static let schemaVersion = JSONOutput.schemaVersion

    public struct Item: Encodable, Sendable {
        public let id: String
        public let category: String
        public let title: String
        public let status: CheckStatus
        public let observed: String?
        public let required: String?
        public let source: CheckSource
        /// Present on warning/error.
        public let remediation: Remediation?
        /// Present on unknown, in place of remediation.
        public let reason: String?
    }

    public let schemaVersion: Int
    public let toolVersion: String
    public let command: String
    public let status: CheckStatus
    public let checks: [Item]

    public init(report: DoctorReport, toolVersion: String, command: String = "doctor") {
        self.schemaVersion = Self.schemaVersion
        self.toolVersion = toolVersion
        self.command = command
        self.status = report.status
        self.checks = report.checks.map { check in
            Item(
                id: check.id,
                category: check.category,
                title: check.title,
                status: check.status,
                observed: check.outcome.observed,
                required: check.outcome.required,
                source: check.outcome.source,
                remediation: check.outcome.remediation,
                reason: check.outcome.reason
            )
        }
    }

    public func encoded() throws -> String { try JSONOutput.encode(self) }
}

import Foundation

/// `down --json`: the envelope every command shares, with one item per thing `down`
/// aimed at — what was stopped, what was not there, what would not stop.
public struct DownJSONDocument: Encodable, Sendable {
    public static let schemaVersion = JSONOutput.schemaVersion

    public struct Item: Encodable, Sendable {
        public let id: String
        public let status: TeardownStatus
        public let detail: String?
        public let remediation: Remediation?
    }

    /// A failure of the run rather than of a job — spelled the way `up` spells one.
    public struct Failure: Encodable, Sendable {
        public let message: String
        public let remediation: Remediation?
    }

    public let schemaVersion: Int
    public let toolVersion: String
    public let command: String
    /// Additive schema-v1 discriminator. nil preserves the legacy iOS document.
    public let platform: String?
    public let status: CheckStatus
    public let items: [Item]
    public let error: Failure?
    public let operation: WorkflowOperation?

    public init(
        report: TeardownReport,
        toolVersion: String,
        command: String = "down",
        platform: String? = nil,
        operation: WorkflowOperation? = nil
    ) {
        self.schemaVersion = Self.schemaVersion
        self.toolVersion = toolVersion
        self.command = command
        self.platform = platform
        self.operation = operation
        self.status = report.status
        self.items = report.items.map {
            Item(id: $0.id, status: $0.status, detail: $0.detail, remediation: $0.remediation)
        }
        // A job that could not run is a failure of the run as much as standing
        // outside a project is: without this, a `down` that exits 2 hands a machine
        // an envelope with nothing in it to explain the exit code.
        self.error = report.failure.map { Failure(message: $0.message, remediation: $0.remediation) }
            ?? (report.toolFailures.isEmpty
                ? nil
                : Failure(message: report.toolFailures.joined(separator: "; "), remediation: nil))
    }

    public func encoded() throws -> String { try JSONOutput.encode(self) }
}

/// `down`'s two streams, split the way `up` splits them: the `--json` document is
/// the only thing on stdout, and everything a human reads goes to stderr, so a
/// piped run and a watched one are the same run.
public struct DownWriter: Sendable {
    private static let nameWidth = 14

    private let json: Bool
    private let toolVersion: String
    private let platform: String?
    private let renderer: HumanReportRenderer
    private let standardOutput: @Sendable (String) -> Void
    private let standardError: @Sendable (String) -> Void

    public init(
        json: Bool,
        toolVersion: String,
        platform: String? = nil,
        renderer: HumanReportRenderer,
        standardOutput: @escaping @Sendable (String) -> Void,
        standardError: @escaping @Sendable (String) -> Void
    ) {
        self.json = json
        self.toolVersion = toolVersion
        self.platform = platform
        self.renderer = renderer
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public func finish(_ report: TeardownReport) throws {
        // A job that could not run at all is the tool's problem, and it is the same
        // sentence in both modes — `--json` describes what `down` did, and this is
        // something it could not do.
        for failure in report.toolFailures { standardError("tool failure: \(failure)") }

        if json {
            return standardOutput(
                try DownJSONDocument(
                    report: report, toolVersion: toolVersion, platform: platform
                ).encoded()
            )
        }

        for item in report.items {
            standardError(line(item))
            // A blocked item uses its own line rather than the failed-item renderer,
            // but it still needs its actionable command when one exists.
            if item.status == .blocked, let command = item.remediation?.command {
                standardError("              → \(command)")
            }
        }

        // Said once, at the end, rather than left for the reader to conclude from two
        // `skipped` lines. Nothing to stop is an answer, not an absence of one.
        if report.stoppedNothing, !report.items.isEmpty { standardError("nothing to stop") }

        let failed = report.items.filter { $0.status == .failed }.map(Self.check)
            + (report.failure.map { [Self.check(for: $0)] } ?? [])
        guard !failed.isEmpty else { return }
        standardError("")
        standardError(renderer.render(DoctorReport(checks: failed)))
    }

    private func line(_ item: TeardownItem) -> String {
        let outcome = item.detail.map { "\(item.status.rawValue) — \($0)" } ?? item.status.rawValue
        return item.id + String(repeating: " ", count: max(2, Self.nameWidth - item.id.count)) + outcome
    }

    /// The run's own failure, drawn the same way. `down` is the name of the run, and
    /// it never appears as an item id — the items are `metro` and `app`.
    private static func check(for failure: DomainError) -> CheckResult {
        CheckResult(
            id: "down",
            category: "down",
            title: "down",
            outcome: .error(observed: failure.observed ?? failure.summary, remediation: failure.remediation)
        )
    }

    /// A failed item, dressed as the one thing the renderer knows how to draw —
    /// cheaper than a second output path, which would drift from doctor's.
    private static func check(_ item: TeardownItem) -> CheckResult {
        CheckResult(
            id: item.id,
            category: item.id,
            title: item.id,
            outcome: .error(
                observed: item.detail,
                remediation: item.remediation
                    ?? Remediation(summary: "This could not be stopped, and said nothing about why.")
            )
        )
    }
}

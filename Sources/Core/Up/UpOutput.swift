import Foundation

/// `up --json`: the same envelope doctor uses, so a consumer does not branch per
/// command. One document, written once, at the end.
public struct UpJSONDocument: Encodable, Sendable {
    public static let schemaVersion = JSONOutput.schemaVersion

    public struct Item: Encodable, Sendable {
        public let id: String
        public let status: StageStatus
        public let durationMs: Int
        public let detail: String?
    }

    /// `DomainError`, serialised as it stands — up does not get a second error type.
    public struct Failure: Encodable, Sendable {
        public let message: String
        /// Absent on a tool failure, which has no project-level next step.
        public let remediation: Remediation?
        /// What this run left running, and the one line that stops it. Absent unless
        /// this run started the Metro — see `UpReport.teardownHint`.
        public let teardown: String?
    }

    /// What the run produced, as opposed to what it did. Absent until a stage puts
    /// something here — an empty object would be one more thing to interpret.
    public struct Outcome: Encodable, Sendable {
        public let device: SelectedDevice?
        /// What install and launch address the app by. The `.app` path build also
        /// settled on stays inside the pipeline — it is derived data, true for one
        /// machine until the next clean, and nothing outside a run can use it.
        public let bundleId: String?
        /// So a CI job can tail the bundler's log, and kill the process it started —
        /// and only that one.
        public let metro: MetroProcess?
        /// The app's pid in the simulator. With the four fields together, whatever
        /// runs after `up` never has to ask the machine what this run did.
        public let appPid: Int32?
        /// xcodebuild's whole output, on disk. Unlike the `.app` path this survives
        /// being read from another machine's terminal — it is what a build's warnings
        /// are in, and a failure puts the same path in its remediation.
        public let buildLog: String?
        public let android: AndroidBuiltProduct?
    }

    public let schemaVersion: Int
    public let toolVersion: String
    public let command: String
    /// Additive schema-v1 discriminator. nil preserves the legacy iOS document.
    public let platform: String?
    public let status: CheckStatus
    public let stages: [Item]
    public let result: Outcome?
    public let error: Failure?
    public let operation: WorkflowOperation?

    public init(
        report: UpReport,
        toolVersion: String,
        command: String = "up",
        platform: String? = nil,
        operation: WorkflowOperation? = nil
    ) {
        self.schemaVersion = Self.schemaVersion
        self.toolVersion = toolVersion
        self.command = command
        self.platform = platform
        self.operation = operation
        self.status = report.status
        self.stages = report.stages.map {
            Item(id: $0.id, status: $0.status, durationMs: $0.durationMs, detail: $0.detail)
        }
        let device = report.context.device
        let bundleId = report.context.product?.bundleIdentifier
        let metro = report.context.metro
        let appPid = report.context.appPid
        let buildLog = report.context.buildLog
        let android = report.context.androidProduct
        self.result = device == nil && bundleId == nil && metro == nil && appPid == nil
            && buildLog == nil && android == nil
            ? nil
            : Outcome(
                device: device,
                bundleId: bundleId,
                metro: metro,
                appPid: appPid,
                buildLog: buildLog,
                android: android
            )
        self.error = report.failure.map {
            Failure(
                message: $0.message, remediation: $0.remediation, teardown: report.teardownHint
            )
        }
    }

    public func encoded() throws -> String { try JSONOutput.encode(self) }
}

/// The row a long Stage prints while it is still working: name, what it is doing,
/// how long it has taken.
public struct StageLineRenderer: Sendable {
    private static let nameWidth = 14
    private static let outcomeWidth = 24

    public init() {}

    /// A Stage that has not landed yet. `build` is the only step long enough to make
    /// a reader wonder whether the tool died, and the answer to that is the same row
    /// it will become, printed early.
    public func waiting(_ id: String, detail: String? = nil, elapsed: Duration) -> String {
        row(id, detail.map { "running… — \($0)" } ?? "running…", elapsed)
    }

    private func row(_ id: String, _ outcome: String, _ elapsed: Duration) -> String {
        column(id, Self.nameWidth)
            + column(outcome, Self.outcomeWidth)
            + String(format: "%.1fs", elapsed.seconds)
    }

    /// Always at least two spaces: a long detail pushes the elapsed time right rather
    /// than colliding with it.
    private func column(_ text: String, _ width: Int) -> String {
        text + String(repeating: " ", count: max(2, width - text.count))
    }
}

/// The build/up report a human reads, on stderr. stdout is left to the `--json`
/// document, which `WorkflowResult` writes.
public struct UpWriter: Sendable {
    private let command: String
    private let renderer: HumanReportRenderer
    private let standardError: @Sendable (String) -> Void

    public init(
        command: String = "up",
        renderer: HumanReportRenderer,
        standardError: @escaping @Sendable (String) -> Void
    ) {
        self.command = command
        self.renderer = renderer
        self.standardError = standardError
    }

    public func finish(_ report: UpReport) {
        // Whatever validate found — the errors that stopped the run, and the warnings
        // that did not — through doctor's renderer. There is one renderer.
        if let validation = report.context.validation, validation.status != .pass {
            standardError("")
            standardError(renderer.render(validation))
        }

        // Anything the block above did not already say. A Check that could not run is
        // one of those: it exits 2 next to check errors that exit 1, and printing only
        // the errors would hide the reason the exit code disagrees with them.
        if let failure = report.failure, !renderedAsValidation(failure, report) {
            standardError("")
            standardError(
                renderer.render(
                    DoctorReport(checks: [Self.check(for: failure, in: report, command: command)])
                )
            )
        }

        // The same sentence `--json` carries in its error, from the same place.
        if let hint = report.teardownHint {
            standardError("")
            standardError(hint)
        }
    }

    private func renderedAsValidation(_ failure: UpFailure, _ report: UpReport) -> Bool {
        guard case .domain = failure else { return false }
        return report.context.validation?.status == .error
    }

    /// A failure, dressed as the one thing the renderer knows how to draw. Cheaper
    /// than a second output path, which would drift from doctor's.
    private static func check(
        for failure: UpFailure, in report: UpReport, command: String
    ) -> CheckResult {
        // The stage names itself first: where it stopped is the first thing to know.
        let stage = report.stages.last { $0.status == .failed }?.id ?? command
        return CheckResult(
            id: stage,
            category: stage,
            title: stage,
            outcome: .error(observed: failure.message, remediation: failure.remediation ?? toolTrouble)
        )
    }

    /// A tool failure has no project-level next step, and a dead end with no next
    /// line is worse than a plain one.
    private static let toolTrouble = Remediation(
        summary: "This step could not run at all — that is the tool or the machine, not the project."
    )
}

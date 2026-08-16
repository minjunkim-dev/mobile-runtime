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
    }

    public let schemaVersion: Int
    public let toolVersion: String
    public let command: String
    public let status: CheckStatus
    public let stages: [Item]
    public let result: Outcome?
    public let error: Failure?

    public init(report: UpReport, toolVersion: String, command: String = "up") {
        self.schemaVersion = Self.schemaVersion
        self.toolVersion = toolVersion
        self.command = command
        self.status = report.status
        self.stages = report.stages.map {
            Item(id: $0.id, status: $0.status, durationMs: $0.durationMs, detail: $0.detail)
        }
        let device = report.context.device
        let bundleId = report.context.product?.bundleIdentifier
        let metro = report.context.metro
        let appPid = report.context.appPid
        let buildLog = report.context.buildLog
        self.result = device == nil && bundleId == nil && metro == nil && appPid == nil
            && buildLog == nil
            ? nil
            : Outcome(
                device: device, bundleId: bundleId, metro: metro, appPid: appPid, buildLog: buildLog
            )
        self.error = report.failure.map {
            Failure(message: $0.message, remediation: $0.remediation)
        }
    }

    public func encoded() throws -> String { try JSONOutput.encode(self) }
}

/// One line per Stage: name, what happened, how long it took. Printed as the Stage
/// lands, which is why it renders a single result and not a report.
public struct StageLineRenderer: Sendable {
    private static let nameWidth = 14
    private static let outcomeWidth = 24

    public init() {}

    public func line(_ result: StageResult) -> String {
        // A detail is what the reader wanted — which device, which scheme — so on a
        // pass it takes the column outright. `skipped` and `failed` keep their word:
        // there, the status is the news and the detail is the reason.
        let outcome = switch result.status {
        case .pass: result.detail ?? result.status.rawValue
        case .skipped, .failed:
            result.detail.map { "\(result.status.rawValue) — \($0)" } ?? result.status.rawValue
        }
        return row(result.id, outcome, result.duration)
    }

    /// A Stage that has not landed yet. `build` is the only step long enough to make
    /// a reader wonder whether the tool died, and the answer to that is the same row
    /// it will become, printed early.
    public func waiting(_ id: String, elapsed: Duration) -> String {
        row(id, "running…", elapsed)
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

/// up's two streams, in one place. stdout carries the `--json` document and nothing
/// else; everything a human reads goes to stderr, so a piped run and a watched
/// terminal are the same run. Progress printed while the pipeline runs is exactly
/// how that rule gets broken, so both streams leave through here rather than
/// through prints scattered across the command.
public struct UpWriter: Sendable {
    private let json: Bool
    private let toolVersion: String
    private let renderer: HumanReportRenderer
    private let lines = StageLineRenderer()
    private let standardOutput: @Sendable (String) -> Void
    private let standardError: @Sendable (String) -> Void

    public init(
        json: Bool,
        toolVersion: String,
        renderer: HumanReportRenderer,
        standardOutput: @escaping @Sendable (String) -> Void,
        standardError: @escaping @Sendable (String) -> Void
    ) {
        self.json = json
        self.toolVersion = toolVersion
        self.renderer = renderer
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    /// Called as each Stage lands — the reader watches the run, rather than waiting
    /// for it. Never stdout, whatever the mode.
    public func progress(_ result: StageResult) {
        standardError(lines.line(result))
    }

    /// A line from a Stage that is still working. Same door as everything else a
    /// human reads — `--json` has not written its document yet, and one stray line
    /// on stdout is all it takes to make it unparseable.
    public func note(_ line: String) {
        standardError(line)
    }

    public func finish(_ report: UpReport) throws {
        if json {
            return standardOutput(try UpJSONDocument(report: report, toolVersion: toolVersion).encoded())
        }

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
            standardError(renderer.render(DoctorReport(checks: [Self.check(for: failure, in: report)])))
        }

        // A failed run leaves its own Metro behind — `up` does not roll back (#13),
        // so the line that cleans it up is worth printing. Only when this run started
        // it: a reused Metro was there before, and telling a user to stop what they
        // were already using is not a next step, it is a mess.
        if report.failure != nil, report.context.metro?.state == .spawned {
            standardError("")
            standardError("The Metro this run started is still on \(MetroVerdict.port) — `mobile down` stops it.")
        }
    }

    private func renderedAsValidation(_ failure: UpFailure, _ report: UpReport) -> Bool {
        guard case .domain = failure else { return false }
        return report.context.validation?.status == .error
    }

    /// A failure, dressed as the one thing the renderer knows how to draw. Cheaper
    /// than a second output path, which would drift from doctor's.
    private static func check(for failure: UpFailure, in report: UpReport) -> CheckResult {
        // The stage names itself first: where it stopped is the first thing to know.
        let stage = report.stages.last { $0.status == .failed }?.id ?? "up"
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

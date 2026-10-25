import Core
import Foundation

public struct EnvironmentInspection: Sendable {
    public let selection: ProjectSelection
    public let report: DoctorReport
    /// Optional read-only build/device choices for a GUI refresh. Not part of doctor JSON.
    public let targets: WorkflowOperation?

    private init(selection: ProjectSelection, report: DoctorReport, targets: WorkflowOperation? = nil) {
        self.selection = selection
        self.report = report
        self.targets = targets
    }

    public var exitCode: Int32 {
        report.hasToolFailure ? 2 : selection.error != nil || !selection.requiredInput.isEmpty ? 1 : report.exitCode
    }

    public func document(toolVersion: String) -> DoctorJSONDocument {
        DoctorJSONDocument(report: report, toolVersion: toolVersion,
                           platform: selection.platform == .android ? "android" : nil, selection: selection)
    }

    /// `note` reports long steps that emit no check result, such as the protected SDK view.
    public static func run(input: ProjectInspectionInput, runner: (any ProcessRunner)? = nil,
                           scheme: String? = nil, configuration: String? = nil,
                           module: String? = nil, variant: String? = nil, includeTargets: Bool = false,
                           note: @Sendable (String) -> Void = { _ in }) async throws -> Self {
        try await run(input: input, runner: runner, scheme: scheme, configuration: configuration,
                      module: module, variant: variant, includeTargets: includeTargets,
                      flutterFactory: FlutterAndroidWorkflow.defaultFactory, note: note)
    }

    static func run(input: ProjectInspectionInput, runner: (any ProcessRunner)? = nil,
                    scheme: String? = nil, configuration: String? = nil,
                    module: String? = nil, variant: String? = nil, includeTargets: Bool = false,
                    flutterFactory: FlutterAndroidWorkflow.Factory,
                    note: @Sendable (String) -> Void = { _ in }) async throws -> Self {
        let runner = runner ?? SystemProcessRunner(environment: input.environment, workingDirectory: input.directory)
        let selection = try input.selection()
        let anchor = selection.error == nil && selection.requiredInput.isEmpty
            ? selection.selected.flatMap { ProjectAnchor.detect(candidate: $0) } : nil
        if let anchor, input.entrypoint != nil, anchor.framework != .flutter {
            let report = DoctorReport(checks: [CheckResult(id: "project.selection", category: "Project",
                title: "Entrypoint selection", outcome: .error(observed: "An explicit entrypoint requires a Flutter app.",
                    remediation: Remediation(summary: "Omit --entrypoint for this framework. No tool was run.")))])
            return Self(selection: selection, report: report)
        }
        if let anchor, anchor.framework != .reactNative && anchor.framework != .nativeIOS && anchor.framework != .nativeAndroid
            && !(anchor.framework == .flutter && (selection.platform == .ios || selection.platform == .android)) {
            let report = DoctorReport(checks: [CheckResult(id: "project.framework", category: "Project",
                title: "Project framework support", outcome: .error(
                    observed: "\(anchor.framework.displayName) inspection is not implemented yet.",
                    source: CheckSource(tier: 1, origin: anchor.framework.rawValue),
                    remediation: Remediation(summary: "Use the project's existing native tool workflow until this framework is supported.")))])
            return Self(selection: selection, report: report)
        }
        if selection.platform == .android && (scheme != nil || configuration != nil) {
            let report = DoctorReport(checks: [CheckResult(id: "project.selection", category: "Project",
                title: "iOS target selection", outcome: .error(observed: "Scheme and configuration apply only to iOS.",
                    remediation: Remediation(summary: "Omit --scheme and --configuration for Android. No tool was run.")))])
            return Self(selection: selection, report: report)
        }
        let config = ConfigContext.detect(anchor: anchor, workingDirectory: input.directory).selecting(scheme: scheme, module: module, variant: variant)
        func finish(selection: ProjectSelection, report: DoctorReport, context: WorkflowContext) async throws -> Self {
            guard includeTargets, let anchor, let platform = selection.platform else {
                return Self(selection: selection, report: report)
            }
            var targets = WorkflowOperation(id: UUID().uuidString, kind: .up, state: "ready")
            targets.selection = selection
            do {
                _ = try await WorkflowExecution.selectTargets(input: WorkflowInput(project: input,
                    scheme: scheme, configuration: configuration, module: module, variant: variant),
                    kind: .up, anchor: anchor, platform: platform, config: config, wiring: context,
                    runner: runner, operation: &targets)
                if !targets.requiredInput.isEmpty { targets.state = "needs-selection" }
            } catch is CancellationError { throw CancellationError() }
            catch let error as DomainError {
                targets.state = "failed"
                targets.nextAction = error.summary
            } catch {
                targets.state = "failed"
                targets.nextAction = String(describing: error)
            }
            try Task.checkCancellation()
            return Self(selection: selection, report: report, targets: targets)
        }
        if let anchor, anchor.framework == .flutter, selection.platform == .android {
            note(FlutterAndroidWorkflow.preparingViewDetail)
            do {
                let flutter = try await FlutterAndroidWorkflow.make(input: input, anchor: anchor, runner: runner,
                    factory: flutterFactory)
                note(FlutterAndroidWorkflow.viewReadyDetail)
                let context = await WorkflowContext.make(input: input, platform: .android, anchor: anchor, runner: runner,
                    projectEnvironmentOverride: flutter.projectEnvironment, projectRunnerOverride: flutter.projectRunner,
                    selectedConfig: config)
                let report = await context.engine.run()
                try Task.checkCancellation()
                return try await finish(selection: try FlutterIOSWorkflow.selection(selection, workspace: flutter.workspace), report: report, context: context)
            } catch is CancellationError { throw CancellationError() }
            catch {
                let outcome = try await FlutterAndroidReadinessCheck().run()
                return Self(selection: selection, report: DoctorReport(checks: [CheckResult(
                    id: "android.flutter.execution", category: "Flutter Android", title: "Protected Flutter Android execution",
                    outcome: outcome)], toolFailures: error is DomainError ? [] : [String(describing: error)]))
            }
        }
        let context = await WorkflowContext.make(input: input, platform: selection.platform ?? .ios,
                                                 anchor: anchor, runner: runner, selectedConfig: config,
                                                 selectedConfiguration: configuration)
        let report = await context.engine.run()
        // The engine records cancelled checks as unknown; a cancelled inspection is not a result.
        try Task.checkCancellation()
        return try await finish(selection: try FlutterIOSWorkflow.selection(selection, workspace: context.flutter?.workspace), report: report, context: context)
    }
}

import Core
import Foundation

public struct EnvironmentInspection: Sendable {
    public let selection: ProjectSelection
    public let report: DoctorReport

    public var exitCode: Int32 {
        report.hasToolFailure ? 2 : selection.error != nil || !selection.requiredInput.isEmpty ? 1 : report.exitCode
    }

    public func document(toolVersion: String) -> DoctorJSONDocument {
        DoctorJSONDocument(report: report, toolVersion: toolVersion,
                           platform: selection.platform == .android ? "android" : nil, selection: selection)
    }

    public static func run(input: ProjectInspectionInput, runner: (any ProcessRunner)? = nil) async throws -> Self {
        try await run(input: input, runner: runner, flutterFactory: FlutterAndroidWorkflow.defaultFactory)
    }

    static func run(input: ProjectInspectionInput, runner: (any ProcessRunner)? = nil,
                    flutterFactory: FlutterAndroidWorkflow.Factory) async throws -> Self {
        let runner = runner ?? SystemProcessRunner(environment: input.environment, workingDirectory: input.directory)
        let selection = try input.selection()
        let anchor = selection.error == nil && selection.requiredInput.isEmpty
            ? selection.selected.flatMap { ProjectAnchor.detect(candidate: $0) } : nil
        if let anchor, anchor.framework == .flutter, selection.platform == .android {
            do {
                let flutter = try await FlutterAndroidWorkflow.make(input: input, anchor: anchor, runner: runner,
                    factory: flutterFactory)
                let context = await WorkflowContext.make(input: input, platform: .android, anchor: anchor, runner: runner,
                    projectEnvironmentOverride: flutter.projectEnvironment, projectRunnerOverride: flutter.projectRunner)
                let report = await context.engine.run()
                try Task.checkCancellation()
                return Self(selection: selection, report: report)
            } catch is CancellationError { throw CancellationError() }
            catch {
                let outcome = try await FlutterAndroidReadinessCheck().run()
                return Self(selection: selection, report: DoctorReport(checks: [CheckResult(
                    id: "android.flutter.execution", category: "Flutter Android", title: "Protected Flutter Android execution",
                    outcome: outcome)], toolFailures: error is DomainError ? [] : [String(describing: error)]))
            }
        }
        if let anchor, anchor.framework != .reactNative && anchor.framework != .nativeIOS && anchor.framework != .nativeAndroid {
            let report = DoctorReport(checks: [CheckResult(id: "project.framework", category: "Project",
                title: "Project framework support", outcome: .error(
                    observed: "\(anchor.framework.displayName) inspection is not implemented yet.",
                    source: CheckSource(tier: 1, origin: anchor.framework.rawValue),
                    remediation: Remediation(summary: "Use the project's existing native tool workflow until this framework is supported.")))])
            return Self(selection: selection, report: report)
        }
        let context = await WorkflowContext.make(input: input, platform: selection.platform ?? .ios,
                                                 anchor: anchor, runner: runner)
        return Self(selection: selection, report: await context.engine.run())
    }
}

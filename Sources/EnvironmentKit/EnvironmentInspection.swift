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
        let runner = runner ?? SystemProcessRunner(environment: input.environment, workingDirectory: input.directory)
        let selection = try input.selection()
        let anchor = selection.error == nil && selection.requiredInput.isEmpty
            ? selection.selected.flatMap { ProjectAnchor.detect(from: URL(fileURLWithPath: $0.app.path)) } : nil
        let context = await WorkflowContext.make(input: input, platform: selection.platform ?? .ios,
                                                 anchor: anchor, runner: runner)
        return Self(selection: selection, report: await context.engine.run())
    }
}

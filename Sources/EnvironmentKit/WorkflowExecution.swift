import AndroidKit
import Core
import Foundation
import SimulatorKit

public struct WorkflowInput: Sendable {
    public let project: ProjectInspectionInput
    public let device: String?
    public let scheme: String?
    public let configuration: String?
    public let module: String?
    public let variant: String?

    public init(project: ProjectInspectionInput, device: String? = nil, scheme: String? = nil,
                configuration: String? = nil, module: String? = nil, variant: String? = nil) {
        self.project = project
        self.device = device
        self.scheme = scheme
        self.configuration = configuration
        self.module = module
        self.variant = variant
    }
}

public struct WorkflowResult: Sendable {
    public let operation: WorkflowOperation
    public let up: UpReport?
    public let down: TeardownReport?

    public var exitCode: Int32 { operation.state == "cancelled" ? 130 : up?.exitCode ?? down?.exitCode ?? 1 }

    public func encoded(toolVersion: String) throws -> String {
        let platform = operation.selection?.platform == .android ? "android" : nil
        if let down {
            return try DownJSONDocument(report: down, toolVersion: toolVersion, platform: platform,
                                        operation: operation).encoded()
        }
        return try UpJSONDocument(report: up ?? UpReport(stages: []), toolVersion: toolVersion,
                                  command: operation.kind.rawValue, platform: platform,
                                  operation: operation).encoded()
    }
}

/// The CLI and GUI use the same selection, factories, cancellation and final document.
public enum WorkflowExecution {
    public static func run(_ kind: WorkflowKind, input: WorkflowInput,
                           runner suppliedRunner: (any ProcessRunner)? = nil,
                           onEvent: @escaping @Sendable (WorkflowEvent) -> Void = { _ in }) async -> WorkflowResult {
        var operation = WorkflowOperation(id: UUID().uuidString, kind: kind, state: "running")
        let events = WorkflowEvents(id: operation.id, callback: onEvent)
        events.send("started", state: "running")
        var up: UpReport?
        var down: TeardownReport?

        do {
            try Task.checkCancellation()
            let selection = try input.project.selection()
            operation.selection = selection
            operation.requiredInput = selection.requiredInput
            if let error = selection.error { throw selectionFailure(error) }
            if !selection.requiredInput.isEmpty {
                operation.state = "needs-selection"
                throw selectionFailure("Select \(selection.requiredInput.joined(separator: ", ")).")
            }
            guard let candidate = selection.selected, let platform = selection.platform,
                let anchor = ProjectAnchor.detect(from: URL(fileURLWithPath: candidate.app.path)) else {
                throw selectionFailure("No React Native app selected. Choose a prepared React Native project.")
            }
            if kind == .down && [input.device, input.scheme, input.configuration, input.module, input.variant].contains(where: { $0 != nil }) {
                throw selectionFailure("down uses the selected project's recorded resources. Omit build and device selectors.")
            }
            if platform == .ios && (input.module != nil || input.variant != nil) {
                throw selectionFailure("--module and --variant apply only to Android.")
            }
            if platform == .android && (input.scheme != nil || input.configuration != nil) {
                throw selectionFailure("--scheme and --configuration apply only to iOS.")
            }
            let runner = suppliedRunner ?? SystemProcessRunner(environment: input.project.environment,
                                                               workingDirectory: anchor.directory)
            var config = ConfigContext.detect(anchor: anchor, workingDirectory: input.project.directory)
                .selecting(scheme: input.scheme, module: input.module, variant: input.variant,
                           clearDevice: platform == .ios && (input.device != nil || kind == .build))
            var wiring = await WorkflowContext.make(input: input.project, platform: platform, anchor: anchor,
                runner: runner, includeProjectEnvironment: kind != .down,
                includeRuntimeSDKTools: kind != .build || platform == .ios, selectedConfig: config)
            try Task.checkCancellation()

            if kind != .down {
                let report = await wiring.engine.run()
                try Task.checkCancellation()
                let ids = platform == .ios ? IOSWorkflowValidation.checkIDs : AndroidWorkflowValidation.checkIDs
                let blocking = report.checks.filter { ids.contains($0.id) && $0.status == .error }
                if report.hasToolFailure {
                    var context = UpContext()
                    context.validation = report
                    up = UpReport(stages: [], context: context, failure: .tool(report.toolFailures.joined(separator: "; ")))
                    throw WorkflowStopped()
                }
                if !blocking.isEmpty {
                    var context = UpContext()
                    context.validation = report
                    up = UpReport(stages: [], context: context, failure: .domain(DomainError(
                        summary: "Environment is not ready: \(blocking.map(\.id).joined(separator: ", "))",
                        remediation: Remediation(summary: "Run mobile doctor for this project and follow its setup instructions. See docs/environment-setup.md."))))
                    throw WorkflowStopped()
                }

                if platform == .ios {
                    let choices = try await IOSWorkflowCandidates.load(anchor: anchor, config: config, lookup: wiring.lookup,
                        runner: wiring.projectRunner, locator: wiring.locator, includeDevices: kind == .up || input.device != nil)
                    operation.schemes = choices.schemes
                    operation.configurations = choices.configurations
                    operation.devices = choices.devices
                    operation.scheme = config.configuration?.scheme ?? (choices.schemes.count == 1 ? choices.schemes.first : nil)
                    if let scheme = operation.scheme, !choices.schemes.contains(scheme) {
                        throw selectionFailure("Unknown scheme: \(scheme). Select a listed scheme.")
                    }
                    if operation.scheme == nil { operation.requiredInput.append("--scheme") }
                    operation.configuration = input.configuration ?? (choices.configurations.contains("Debug") ? "Debug" : nil)
                    if let configuration = input.configuration, !choices.configurations.contains(configuration) {
                        throw selectionFailure("Unknown configuration: \(configuration). Select a listed configuration.")
                    }
                    if operation.configuration == nil { operation.requiredInput.append("--configuration") }
                    operation.device = input.device ?? choices.declaredDeviceID
                    if kind == .up && operation.device == nil && config.configuration?.device == nil && choices.devices.count == 1 {
                        operation.device = choices.devices.first?.id
                    }
                    if kind == .up || input.device != nil {
                        if config.configuration?.device != nil && operation.device == nil && input.device == nil {
                            throw selectionFailure("ios.device does not resolve to a compatible Simulator. Refresh and select a device identity.")
                        }
                        try selectDevice(&operation)
                    }
                    config = config.selecting(scheme: operation.scheme)
                } else {
                    let target = try await AndroidWorkflowTarget.load(anchor: anchor, config: config, hostRunner: runner,
                        projectRunner: wiring.projectRunner, environment: AndroidEnvironment(values: input.project.environment))
                    operation.modules = target.modules
                    operation.variants = target.variants
                    operation.module = target.module
                    operation.variant = target.variant
                    operation.requiredInput += target.requiredInput
                    config = config.selecting(module: target.module, variant: target.variant)
                    if kind == .up {
                        operation.devices = try await androidWorkflowDevices(anchor: anchor, config: config, runner: runner,
                            environment: AndroidEnvironment(values: input.project.environment))
                        operation.device = input.device ?? config.configuration?.androidAVD.map { "avd:\($0)" }
                        if operation.device == nil && operation.devices.count == 1 { operation.device = operation.devices.first?.id }
                        try selectDevice(&operation)
                        let avd = operation.devices.first { $0.id == operation.device }?.name
                        config = config.selecting(avd: avd)
                    } else if input.device != nil {
                        throw selectionFailure("Android build does not use an execution device. Omit --device.")
                    }
                }
                operation.module = config.configuration?.androidModule
                operation.variant = config.configuration?.androidVariant
                if !operation.requiredInput.isEmpty {
                    operation.state = "needs-selection"
                    throw selectionFailure("Select \(operation.requiredInput.joined(separator: ", ")) before starting changes.")
                }
                wiring = await WorkflowContext.make(input: input.project, platform: platform, anchor: anchor,
                    runner: runner, includeRuntimeSDKTools: kind != .build || platform == .ios, selectedConfig: config)
                try Task.checkCancellation()
            }

            let started: @Sendable (String) -> Void = { events.send("stage", stage: $0, state: "running") }
            let finished: @Sendable (StageResult) -> Void = { events.send("stage", stage: $0.id, state: $0.status.rawValue, detail: $0.detail) }
            let note: @Sendable (String) -> Void = { events.send("detail", state: "running", detail: $0) }
            switch (kind, platform) {
            case (.down, .ios):
                started("down")
                down = await iOSTeardown(anchor: anchor, runner: runner, locator: wiring.locator).run()
            case (.down, .android):
                started("down")
                down = await androidTeardown(anchor: anchor, config: config, runner: runner, projectRunner: runner,
                                             environment: AndroidEnvironment(values: input.project.environment))
            case (.up, .android):
                up = await runAndroidUp(anchor: anchor, doctor: wiring.engine, config: config,
                    hostRunner: runner, projectRunner: wiring.projectRunner,
                    environment: AndroidEnvironment(values: input.project.environment), note: note,
                    onStageFinished: finished, onStageStarted: started)
            case (.build, .android):
                up = await UpPipeline(stages: androidBuildStages(anchor: anchor, doctor: wiring.engine, config: config,
                    hostRunner: runner, projectRunner: wiring.projectRunner,
                    environment: AndroidEnvironment(values: input.project.environment), note: note))
                    .run(onStageFinished: finished, onStageStarted: started)
            case (.build, .ios), (.up, .ios):
                up = await UpPipeline(stages: iOSStages(workflow: kind == .build ? .build : .up,
                    anchor: anchor, doctor: wiring.engine, config: config, lookup: wiring.lookup,
                    hostRunner: runner, projectRunner: wiring.projectRunner, locator: wiring.locator,
                    deviceID: operation.device, configuration: operation.configuration ?? "Debug",
                    buildWithoutDevice: kind == .build && operation.device == nil, note: note))
                    .run(onStageFinished: finished, onStageStarted: started)
            }
        } catch is WorkflowStopped {
            // The existing report carries the validation and its public failure classification.
        } catch is CancellationError {
            if kind == .down { down = TeardownReport(items: [], cancelled: true) }
            else { up = UpReport(stages: [], failure: .cancelled) }
        } catch let error as DomainError {
            operation.nextAction = error.remediation.summary
            if kind == .down { down = TeardownReport(items: [], failure: error) }
            else { up = UpReport(stages: [], failure: .domain(error)) }
        } catch {
            if kind == .down { down = TeardownReport(items: [], toolFailures: [String(describing: error)]) }
            else { up = UpReport(stages: [], failure: .tool(String(describing: error))) }
        }

        let code = Task.isCancelled ? 130 : up?.exitCode ?? down?.exitCode ?? 1
        if operation.state != "needs-selection" { operation.state = code == 130 ? "cancelled" : code == 0 ? "succeeded" : "failed" }
        operation.completed = up?.stages.filter { $0.status != .failed }.map(\.id)
            ?? down?.items.filter { $0.status == .stopped }.map(\.id) ?? []
        operation.nextAction = operation.nextAction ?? up?.failure?.remediation?.summary ?? down?.failure?.remediation.summary
        if code == 130 && operation.nextAction == nil {
            operation.nextAction = "Inspect the remaining resources and retry down for this project and platform."
        }
        if code == 2 && operation.nextAction == nil {
            operation.nextAction = "Check the failed tool and its logs. Run mobile doctor for the selected project and platform."
        }
        if let hint = up?.teardownHint { operation.remaining.append(hint) }
        if code == 130 && operation.remaining.isEmpty && !operation.completed.isEmpty {
            operation.remaining = ["Completed changes remain. Inspect this project's resources before retrying or running down."]
        }
        if let down {
            operation.remaining += down.items.filter { $0.status == .failed || $0.status == .blocked || $0.status == .unknown }
                .map { "\($0.id): \($0.detail ?? $0.status.rawValue)" }
        }
        events.send(code == 130 ? "cancelled" : "finished", state: operation.state, detail: operation.nextAction)
        return WorkflowResult(operation: operation, up: up, down: down)
    }

    private static func selectDevice(_ operation: inout WorkflowOperation) throws {
        guard let id = operation.device else { operation.requiredInput.append("--device"); return }
        guard operation.devices.contains(where: { $0.id == id }) else {
            throw selectionFailure("Unknown or unavailable device identity: \(id). Refresh the candidates.")
        }
    }

    private static func selectionFailure(_ summary: String) -> DomainError {
        DomainError(summary: summary, remediation: Remediation(summary: summary))
    }
}

private struct WorkflowStopped: Error {}

private final class WorkflowEvents: @unchecked Sendable {
    private let lock = NSLock()
    private let id: String
    private let callback: @Sendable (WorkflowEvent) -> Void
    private var sequence = 0

    init(id: String, callback: @escaping @Sendable (WorkflowEvent) -> Void) {
        self.id = id
        self.callback = callback
    }

    func send(_ kind: String, stage: String? = nil, state: String, detail: String? = nil) {
        lock.withLock {
            sequence += 1
            callback(WorkflowEvent(operationId: id, sequence: sequence, kind: kind, stageId: stage, state: state, detail: detail))
        }
    }
}

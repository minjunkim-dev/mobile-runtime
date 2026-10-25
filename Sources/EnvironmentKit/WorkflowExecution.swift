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
    public let port: Int?
    public let preparedDependencies: Bool

    public init(project: ProjectInspectionInput, device: String? = nil, scheme: String? = nil,
                configuration: String? = nil, module: String? = nil, variant: String? = nil, port: Int? = nil,
                preparedDependencies: Bool = false) {
        self.project = project
        self.device = device
        self.scheme = scheme
        self.configuration = configuration
        self.module = module
        self.variant = variant
        self.port = port
        self.preparedDependencies = preparedDependencies
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
                           runner suppliedRunner: (any ProcessRunner)? = nil, leases: ResourceLeases = .user,
                           onEvent: @escaping @Sendable (WorkflowEvent) -> Void = { _ in }) async -> WorkflowResult {
        await run(kind, input: input, runner: suppliedRunner, leases: leases,
            flutterFactory: FlutterAndroidWorkflow.defaultFactory, onEvent: onEvent)
    }

    static func run(_ kind: WorkflowKind, input: WorkflowInput,
                    runner suppliedRunner: (any ProcessRunner)? = nil, leases: ResourceLeases = .user,
                    flutterFactory: FlutterAndroidWorkflow.Factory,
                    onEvent: @escaping @Sendable (WorkflowEvent) -> Void = { _ in }) async -> WorkflowResult {
        var operation = WorkflowOperation(id: UUID().uuidString, kind: kind, state: "running")
        operation.preparedDependencies = input.preparedDependencies ? true : nil
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
                let anchor = ProjectAnchor.detect(candidate: candidate) else {
                throw selectionFailure("No app selected. Choose a reported project candidate.")
            }
            guard anchor.framework == .reactNative || (anchor.framework == .nativeIOS && platform == .ios)
                || (anchor.framework == .nativeAndroid && platform == .android)
                || anchor.framework == .flutter else {
                throw selectionFailure("\(anchor.framework.displayName) execution is not implemented yet.")
            }
            if input.project.entrypoint != nil && anchor.framework != .flutter {
                throw selectionFailure("An explicit entrypoint requires a Flutter app.")
            }
            if input.preparedDependencies && (![ProjectFramework.reactNative, .flutter].contains(anchor.framework) || kind == .down) {
                throw selectionFailure("--prepared-dependencies는 React Native·Flutter build/up에서만 사용할 수 있습니다.")
            }
            if let port = input.port {
                let supported = (anchor.framework == .reactNative && kind != .down)
                    || (anchor.framework == .flutter && kind == .up)
                guard supported, (1...65535).contains(port) else {
                    throw selectionFailure("--port requires React Native build/up or Flutter up and a port from 1 through 65535. This workflow cannot forward it; no project file was changed.")
                }
                if anchor.framework == .reactNative { try validatePortForwarding(anchor: anchor, platform: platform) }
            }
            if anchor.framework == .flutter && kind != .down {
                guard let project = try? FlutterProject(directory: anchor.directory, entrypoint: input.project.entrypoint), project.entrypoint != nil else {
                    throw selectionFailure("Choose an existing Dart entrypoint inside a valid Flutter app. No tool was run and no source was changed.")
                }
            }
            operation.entrypoint = input.project.entrypoint
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
            let androidFlutter: FlutterAndroidWorkflow?
            if anchor.framework == .flutter && platform == .android && kind != .down {
                // Copying and checking the SDK view can take minutes before validate reports.
                events.send("detail", state: "running", detail: FlutterAndroidWorkflow.preparingViewDetail)
                androidFlutter = try await FlutterAndroidWorkflow.make(input: input.project, anchor: anchor,
                    runner: runner, preparedDependencies: input.preparedDependencies, factory: flutterFactory)
            } else {
                androidFlutter = nil
            }
            if let androidFlutter { operation.entrypoint = androidFlutter.entrypoint.path }
            var config = ConfigContext.detect(anchor: anchor, workingDirectory: input.project.directory)
                .selecting(scheme: input.scheme, module: input.module, variant: input.variant,
                           clearDevice: platform == .ios && (input.device != nil || (kind == .build && anchor.framework != .flutter)))
            var wiring = await WorkflowContext.make(input: input.project, platform: platform, anchor: anchor,
                runner: runner, includeProjectEnvironment: kind != .down,
                includeRuntimeSDKTools: kind != .build || platform == .ios,
                preparedDependencies: input.preparedDependencies,
                projectEnvironmentOverride: androidFlutter?.projectEnvironment,
                projectRunnerOverride: androidFlutter?.projectRunner, selectedConfig: config,
                selectedConfiguration: input.configuration)
            operation.selection = try FlutterIOSWorkflow.selection(selection, workspace: androidFlutter?.workspace ?? wiring.flutter?.workspace)
            try Task.checkCancellation()

            if kind != .down {
                let report = await wiring.engine.run()
                try Task.checkCancellation()
                let ids = (platform == .ios ? IOSWorkflowValidation.checkIDs : AndroidWorkflowValidation.checkIDs)
                    .union(report.checks.filter { $0.id.hasPrefix("tools.") || $0.id.hasPrefix("flutter.") || $0.id == "dependencies.flutter" || $0.id.hasPrefix("ios.flutter.") }.map(\.id))
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

                config = try await selectTargets(input: input, kind: kind, anchor: anchor, platform: platform,
                    config: config, wiring: wiring, runner: runner, operation: &operation)
                if !operation.requiredInput.isEmpty {
                    operation.state = "needs-selection"
                    throw selectionFailure("Select \(operation.requiredInput.joined(separator: ", ")) before starting changes.")
                }
                wiring = await WorkflowContext.make(input: input.project, platform: platform, anchor: anchor,
                    runner: runner, includeRuntimeSDKTools: kind != .build || platform == .ios,
                    preparedDependencies: input.preparedDependencies,
                    projectEnvironmentOverride: androidFlutter?.projectEnvironment,
                    projectRunnerOverride: androidFlutter?.projectRunner, selectedConfig: config,
                    selectedConfiguration: operation.configuration)
                try Task.checkCancellation()
            }

            // Stabilize this project's recorded targets before acquiring the resources down changes.
            var flutterDownRoot: URL?
            if kind == .down && anchor.framework == .flutter {
                guard let project = try? FlutterProject(directory: anchor.directory, entrypoint: input.project.entrypoint),
                      let root = try? project.workspaceDirectoryForTeardown() else {
                    throw selectionFailure("Confirm the current Flutter workspace declarations before down. Existing resources were preserved; no SDK was run.")
                }
                flutterDownRoot = root
            }
            let folder = try FolderIdentity(directory: flutterDownRoot ?? androidFlutter?.workspace.directory ?? wiring.flutter?.workspace?.directory
                ?? anchor.workspaceRoot?.directory ?? anchor.directory)
            // Flutter shares a workspace lease, but the selected app owns its installed runtime.
            let ownerProject = anchor.framework == .flutter ? candidate.app.path : folder.path
            let owner = LeaseOwner(operationId: operation.id, command: kind.rawValue, project: ownerProject)
            let folderLease = try leases.acquire([.folder(folder)], owner: owner)
            defer { folderLease.release() }
            let logs = RunLogs(project: anchor.directory)
            let recordedPort = try anchor.framework == .reactNative ? logs.metroPort(platform: platform) : nil
            let metroPort = anchor.framework == .reactNative
                ? (kind == .down ? recordedPort ?? MetroVerdict.port : input.port ?? MetroVerdict.port) : nil
            let device: ResourceKey?
            switch kind {
            case .up: device = operation.device.map { .device(platform, $0) }
            case .down:
                switch platform {
                case .ios:
                    device = try InstallRecord.read(from: RunLogs(project: anchor.directory), leases: leases, ownerProject: owner.project).map { .device(.ios, $0.udid) }
                case .android:
                    device = try androidTeardownDeviceKey(anchor: anchor)
                }
            case .build: device = nil
            }
            let flutterReentry = platform == .android && anchor.framework == .flutter && kind == .up
                ? try androidFlutterReentry(anchor: anchor) : nil
            let flutterPort: Int?
            if anchor.framework == .flutter && kind == .up {
                if input.port == nil, let flutterReentry { flutterPort = flutterReentry.hostPort }
                else { flutterPort = try FlutterIOSWorkflow.availablePort(input.port) }
            } else { flutterPort = nil }
            operation.port = flutterPort ?? metroPort
            let recordedAndroid = kind == .down && platform == .android
                ? try androidTeardownResourceKeys(anchor: anchor) : []
            let resources = (device.map { [$0] } ?? []) + recordedAndroid + (flutterReentry?.resourceKeys ?? [])
                + (kind == .build ? [] : [metroPort, recordedPort].compactMap { $0 }.map(ResourceKey.port))
            let resourceLease = try leases.acquire(resources + (flutterPort.map { [.port($0)] } ?? []), owner: owner)
            defer { resourceLease.release() }
            if kind == .up, let recordedPort, let metroPort, recordedPort != metroPort {
                guard try await MetroVerdict.ask(anchor: anchor.directory, runner: wiring.projectRunner, port: recordedPort) == .empty else {
                    throw selectionFailure("The previously selected Metro port \(recordedPort) remains occupied or unconfirmed. Run mobile down for this project before selecting a different port.")
                }
            }
            if let flutterReentry {
                guard flutterPort == flutterReentry.hostPort,
                      try androidFlutterReentry(anchor: anchor) == flutterReentry else {
                    throw selectionFailure("The recorded Flutter run changed while acquiring its resources. Preserve it and run mobile down --platform android.")
                }
            }
            if let device {
                let environment = AndroidEnvironment(values: input.project.environment)
                try await leases.check(device: device, project: owner.project) { [wiring] claim in
                    switch claim.platform {
                    case .ios:
                        try await simulatorAppObservation(udid: claim.handle, bundleID: claim.appID, runner: runner, locator: wiring.locator)
                    case .android:
                        try await androidAppObservation(serial: claim.handle, applicationId: claim.appID, expectedDevice: claim.device, anchor: anchor,
                            config: config, runner: runner, environment: environment)
                    }
                }
            }
            if kind == .up, let device { try leases.reserve(device: device, owner: owner) }

            let started: @Sendable (String) -> Void = { events.send("stage", stage: $0, state: "running") }
            let finished: @Sendable (StageResult) -> Void = { events.send("stage", stage: $0.id, state: $0.status.rawValue, detail: $0.detail) }
            let note: @Sendable (String) -> Void = { events.send("detail", state: "running", detail: $0) }
            switch (kind, platform) {
            case (.down, .ios):
                started("down")
                down = await iOSTeardown(anchor: anchor, runner: runner, locator: wiring.locator,
                    leases: leases, ownerProject: owner.project).run()
            case (.down, .android):
                started("down")
                down = await androidTeardown(anchor: anchor, config: config, runner: runner, projectRunner: runner,
                                             environment: AndroidEnvironment(values: input.project.environment))
                if let device, let report = down, report.status == .pass,
                    report.items.contains(where: { $0.id == "android.emulator"
                        && ($0.status == .stopped || $0.ownedRuntimeStopped == true) }) {
                    do {
                        try leases.releaseAfterTeardown(device: device, project: owner.project)
                    } catch {
                        let detail = "The device claim cleanup could not be confirmed: \(error)"
                        operation.remaining.append(detail)
                        down = TeardownReport(items: report.items, toolFailures: report.toolFailures + [detail],
                            failure: report.failure, blockedIsFailure: report.blockedIsFailure, cancelled: report.cancelled)
                    }
                }
            case (.up, .android):
                up = await runAndroidUp(anchor: anchor, doctor: wiring.engine, config: config,
                    hostRunner: runner, projectRunner: wiring.projectRunner,
                    environment: AndroidEnvironment(values: input.project.environment),
                    preparedDependencies: input.preparedDependencies,
                    metroPort: anchor.framework == .reactNative ? input.port : nil,
                    port: flutterPort, flutterEntrypoint: androidFlutter?.entrypoint,
                    reentry: flutterReentry, note: note,
                    onStageFinished: finished, onStageStarted: started)
            case (.build, .android):
                up = await UpPipeline(stages: androidBuildStages(anchor: anchor, doctor: wiring.engine, config: config,
                    hostRunner: runner, projectRunner: wiring.projectRunner,
                    environment: AndroidEnvironment(values: input.project.environment),
                    preparedDependencies: input.preparedDependencies, metroPort: input.port, note: note))
                    .run(onStageFinished: finished, onStageStarted: started)
            case (.build, .ios), (.up, .ios):
                let flutter: FlutterIOSWorkflow?
                if anchor.framework == .flutter {
                    flutter = try await FlutterIOSWorkflow(anchor: anchor, input: input.project, preparation: wiring.flutter,
                        runner: wiring.projectRunner, trackingRunner: runner)
                } else { flutter = nil }
                let stages = iOSStages(workflow: kind == .build ? .build : .up,
                    anchor: anchor, doctor: wiring.engine, config: config, lookup: wiring.lookup,
                    hostRunner: runner, projectRunner: flutter?.buildRunner ?? wiring.projectRunner, locator: wiring.locator,
                    deviceID: operation.device, configuration: operation.configuration ?? "Debug",
                    buildWithoutDevice: kind == .build && operation.device == nil,
                    preparedDependencies: input.preparedDependencies,
                    metroPort: input.port, flutterPort: flutterPort, note: note)
                up = await UpPipeline(stages: flutter?.guarding(stages) ?? stages)
                    .run(onStageFinished: finished, onStageStarted: started)
                if let flutter, !flutter.changedFiles.isEmpty {
                    operation.remaining += flutter.changedFiles.map { "Unexpected changed source: \($0). No file was restored." }
                }
            }
            if let report = up, anchor.framework == .flutter, platform == .android {
                operation.developmentServiceURI = report.context.developmentServiceURI
            }
            if let report = up, anchor.framework == .flutter, platform == .ios {
                operation.entrypoint = wiring.flutter?.entrypoint?.path
                operation.developmentServiceURI = report.context.developmentServiceURI
                if report.failure != nil && report.context.product != nil && kind == .up {
                    operation.remaining.append("The recorded Flutter app may remain installed or running. Run mobile down --platform ios for this project.")
                }
            }
            // The app outlives this lease, even after a later stage failed. The next run observes it again.
            if let device, let report = up, let claim = claim(report.context, device: device, platform: platform, owner: owner) {
                do {
                    try leases.record(claim)
                } catch {
                    let detail = "Could not record the app claim: \(error). The device reservation remains unconfirmed."
                    operation.remaining.append(detail)
                    operation.nextAction = "Inspect the recorded device and retry this project. Other projects remain blocked until its ownership is confirmed."
                    let failure: UpFailure
                    if case .cancelled? = report.failure { failure = .cancelled }
                    else { failure = .tool([report.failure?.message, detail].compactMap { $0 }.joined(separator: "\n")) }
                    up = UpReport(stages: report.stages, context: report.context, failure: failure)
                }
            }
        } catch is WorkflowStopped {
            // The existing report carries the validation and its public failure classification.
        } catch is CancellationError {
            if kind == .down { down = TeardownReport(items: [], cancelled: true) }
            else { up = UpReport(stages: [], failure: .cancelled) }
        } catch let conflict as ResourceConflict {
            operation.conflict = conflict
            operation.nextAction = conflict.domainError.remediation.summary
            if kind == .down { down = TeardownReport(items: [], failure: conflict.domainError) }
            else { up = UpReport(stages: [], failure: .domain(conflict.domainError)) }
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

    /// Read-only candidates are shared by inspection and execution; execution validates them again.
    static func selectTargets(input: WorkflowInput, kind: WorkflowKind, anchor: ProjectAnchor,
                              platform: ProjectPlatform, config original: ConfigContext, wiring: WorkflowContext,
                              runner: any ProcessRunner, operation: inout WorkflowOperation) async throws -> ConfigContext {
        var config = original
        if platform == .ios {
            let needsDevice = kind == .up || anchor.framework == .flutter || input.device != nil
            let choices = try await IOSWorkflowCandidates.load(anchor: anchor, config: config, lookup: wiring.lookup,
                runner: wiring.projectRunner, locator: wiring.locator, includeDevices: needsDevice,
                configuration: input.configuration, entrypoint: input.project.entrypoint,
                flutterSDKRoot: wiring.flutter?.sdk?.root)
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
            if needsDevice && operation.device == nil && config.configuration?.device == nil && choices.devices.count == 1 {
                operation.device = choices.devices.first?.id
            }
            if needsDevice {
                if config.configuration?.device != nil && operation.device == nil && input.device == nil {
                    throw selectionFailure("ios.device does not resolve to a compatible Simulator. Refresh and select a device identity.")
                }
                try selectDevice(&operation)
            }
            config = config.selecting(scheme: operation.scheme)
        } else {
            let target = try await AndroidWorkflowTarget.candidates(anchor: anchor, config: config, hostRunner: runner,
                projectRunner: wiring.projectRunner, environment: AndroidEnvironment(values: input.project.environment))
            operation.modules = target.modules
            operation.variants = target.variants
            operation.module = target.module
            operation.variant = target.variant
            operation.requiredInput += target.requiredInput
        if let error = target.selectionError { throw error }
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
        return config
    }

    private static func claim(_ context: UpContext, device: ResourceKey, platform: ProjectPlatform, owner: LeaseOwner) -> ResourceClaim? {
        switch platform {
        case .ios:
            guard let udid = context.device?.udid, let app = context.product?.bundleIdentifier else { return nil }
            return ResourceClaim(device: device, platform: .ios, handle: udid, appID: app, owner: owner)
        case .android:
            guard let product = context.androidProduct, let serial = product.device?.serial else { return nil }
            return ResourceClaim(device: device, platform: .android, handle: serial, appID: product.applicationId, owner: owner)
        }
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

    private static func validatePortForwarding(anchor: ProjectAnchor, platform: ProjectPlatform) throws {
        let root = anchor.directory
        let manifest = try? JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("package.json"))) as? [String: Any]
        guard (manifest?["scripts"] as? [String: String])?["start"]?.trimmingCharacters(in: .whitespacesAndNewlines) == "react-native start" else {
            throw selectionFailure("This start script has no confirmed --port forwarding path. Use the standard react-native start script or the default port; no project file was changed.")
        }
        let dependency = (anchor.workspaceRoot?.directory ?? root).appendingPathComponent("node_modules")
        let relative = platform == .ios ? "react-native/React-Core.podspec"
            : "@react-native/gradle-plugin/react-native-gradle-plugin/src/main/kotlin/com/facebook/react/utils/AgpConfiguratorUtils.kt"
        let required = platform == .ios ? "RCT_METRO_PORT=${RCT_METRO_PORT}" : "reactNativeDevServerPort"
        guard let text = try? String(contentsOf: dependency.appendingPathComponent(relative), encoding: .utf8), text.contains(required) else {
            throw selectionFailure("The installed React Native native build has no confirmed selected-port input. Prepare a supported local dependency tree; no tool was installed and no source was changed.")
        }
        if platform == .ios {
            let provider = dependency.appendingPathComponent("react-native/React/Base/RCTBundleURLProvider.mm")
            guard let text = try? String(contentsOf: provider, encoding: .utf8),
                text.contains("RCT_jsLocation"), text.contains("stringForKey:kRCTJsLocationKey") else {
                throw selectionFailure("The installed iOS React Native bundle provider has no confirmed launch port argument. Existing source and app preferences were preserved.")
            }
        }
    }
}

private struct WorkflowStopped: Error {}

final class WorkflowEvents: @unchecked Sendable {
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

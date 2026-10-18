import Core
import AndroidKit
import CryptoKit
import Foundation
import SimulatorKit

public struct PreparationStep: Codable, Sendable {
    public let id: String
    public let platform: ProjectPlatform?
    public let kind: String
    public let target: String
    public let observed: String?
    public let required: String?
    public let source: CheckSource
    public let command: String?
    public let remediation: Remediation?
    /// Only explicit, non-secret execution policy. Never the process environment.
    public var environment: [String: String] = [:]
    public var installation: InstallationMetadata? = nil
}

public struct PreparationPlatform: Codable, Sendable {
    public let platform: ProjectPlatform
    public var state: String
    public let checks: [PreparationStep]
}

public struct PreparationPlan: Codable, Sendable {
    public var id: String
    public let project: FolderIdentity
    public let app: String
    public let projectKind: String
    public var platforms: [PreparationPlatform]
    public let steps: [PreparationStep]
    /// Content digests only. Declaration contents and process environments stay private.
    public let files: [String: String]
    public let installed: [String: Bool]
    public var androidRequirements: AndroidSDKRequirements? = nil
    /// Observed iOS identities are approval inputs, separate from payload checksums.
    public var resources: [IOSPreparationResource]? = nil

    /// The same approval inspection is visible in both clients.
    public var inspectionLines: [String] {
        platforms.flatMap { platform in
            platform.checks.map { check in
                "\(platform.platform.rawValue) \(check.id) [\(check.kind)] observed: \(check.observed ?? "unknown"); required: \(check.required ?? "none"); source: \(check.source.origin); target: \(check.target)"
            }
        } + installed.keys.sorted().map { "destination: \($0) — \(installed[$0] == true ? "present" : "absent")" }
        + steps.compactMap(\.installation).map(\.inspectionLine)
    }
}

public struct PreparationOperation: Encodable, Sendable {
    public let id: String
    public let kind = "setup"
    public var state = "needs-selection"
    public var completed: [String] = []
    public var remaining: [String] = []
    public var manual: [PreparationStep] = []
    public var changedFiles: [String] = []
    public var requiredInput: [String] = []
    public var nextAction: String?
    public var error: String?
    public var log: String?
    public var conflict: ResourceConflict?
    /// Completed or uncertain OS resources survive failures and cancellation.
    public var resources: [IOSPreparationResource] = []
}

public struct PreparationResult: Sendable {
    public var plan: PreparationPlan?
    public var selection: ProjectSelection?
    public var operation: PreparationOperation
    public var exitCode: Int32

    public func encoded(toolVersion: String) throws -> String {
        struct Document: Encodable {
            let schemaVersion = JSONOutput.schemaVersion
            let command = "setup"
            let toolVersion: String
            let status: CheckStatus
            let exitCode: Int32
            let selection: ProjectSelection?
            let plan: PreparationPlan?
            let operation: PreparationOperation
        }
        return try JSONOutput.encode(Document(toolVersion: toolVersion,
            status: exitCode == 0 ? .pass : .error, exitCode: exitCode,
            selection: selection, plan: plan, operation: operation))
    }
}

/// One approval boundary for CLI and GUI. New tool provisioning remains in its providers.
public enum PreparationExecution {
    public static func run(
        input: ProjectInspectionInput, planOnly: Bool = false,
        approvedPlanID: String? = nil, trustRepository: Bool = false,
        runner: (any ProcessRunner)? = nil, leases: ResourceLeases = .user,
        onEvent: (@Sendable (WorkflowEvent) -> Void)? = nil
    ) async -> PreparationResult {
        let events = PreparationEvents(onEvent)
        var result = PreparationResult(operation: PreparationOperation(id: events.id), exitCode: 1)
        let host = runner ?? SystemProcessRunner(environment: input.environment, workingDirectory: input.directory)
        events.emit("started", state: "running", detail: "Inspect preparation platforms")
        do {
            try Task.checkCancellation()
            let prepared = try await inspect(input, runner: host)
            result.plan = prepared.plan
            result.selection = prepared.selection
            result.operation.resources = prepared.resources
            result.operation.requiredInput = prepared.selection?.requiredInput ?? []
            if !result.operation.requiredInput.isEmpty || prepared.plan == nil {
                result.operation.error = prepared.selection?.error ?? "Choose a detected project app."
                result.operation.state = prepared.selection?.error == nil ? "needs-selection" : "failed"
                return finish(result, events)
            }
            guard let plan = prepared.plan else { return finish(result, events) }
            result.operation.manual = plan.steps.filter { $0.kind != "align" && $0.kind != "install" }
            result.operation.remaining = plan.steps.map(\.id)
            if planOnly || approvedPlanID == nil {
                result.operation.state = "needs-approval"
                result.operation.nextAction = "Review this plan. Approve only its exact plan-id; repository trust is separate."
                result.exitCode = planOnly ? 0 : 1
                return finish(result, events)
            }
            guard approvedPlanID == plan.id else {
                result.operation.state = "needs-approval"
                result.operation.error = "Plan conditions changed. No preparation changes started."
                result.operation.nextAction = "Review the new plan and approve its new plan-id."
                return finish(result, events)
            }
            let actions = plan.steps.filter { $0.kind == "align" }
            let installations = plan.steps.filter { $0.kind == "install" }
            guard actions.isEmpty || trustRepository else {
                result.operation.state = "waiting-manual"
                result.operation.requiredInput = ["--trust-repository"]
                result.operation.nextAction = "Inspect repository scripts. Explicitly trust this repository separately from plan approval."
                return finish(result, events)
            }
            // Recheck after approval and immediately before acquiring the dependency target.
            let fresh = try await inspect(input, runner: host)
            guard fresh.plan?.id == plan.id else {
                result.plan = fresh.plan
                result.operation.state = "needs-approval"
                result.operation.error = "Conditions changed immediately before execution."
                result.operation.nextAction = "Review and approve the new plan-id."
                return finish(result, events)
            }
            guard let anchor = prepared.anchor, let dependencyRunner = prepared.dependencyRunner else {
                result.operation.state = "waiting-manual"
                result.operation.nextAction = "Finish the listed provider steps, then inspect again."
                return finish(result, events)
            }
            let folder = try FolderIdentity(directory: prepared.root)
            // Separate projects can reuse one global Bundle destination.
            let destinations = actions.filter { ["dependencies.gems", "dependencies.flutter"].contains($0.id) }.map { ResourceKey.destination(URL(fileURLWithPath: $0.target)) }
            let installationTargets = installations.flatMap { $0.installation?.resourceKeys ?? [] }
            let lease = try leases.acquire([.folder(folder)] + destinations + installationTargets,
                owner: LeaseOwner(operationId: result.operation.id, command: "setup", project: folder.path))
            defer { lease.release() }
            // Another preparation may have finished while the plan was being read.
            guard try await inspect(input, runner: host).plan?.id == plan.id else {
                result.plan = try await inspect(input, runner: host).plan
                result.operation.state = "needs-approval"
                result.operation.error = "Conditions changed while acquiring the preparation target."
                return finish(result, events)
            }
            let installedDestinations = installations.compactMap { $0.installation?.destination }
            let originalFiles = try sourceFiles(prepared.root, excluding: installedDestinations)
            let sourceRoot = prepared.root
            var existingIOSDevices: [IOSResourceInventory.Device]?
            for step in installations {
                try Task.checkCancellation()
                guard let metadata = step.installation,
                      let action = prepared.installationActions[step.id], action.metadata == metadata else {
                    throw DomainError(summary: "Approved installation metadata is missing", remediation: Remediation(summary: "Inspect the package plan again."))
                }
                if case .iosRuntime(let pin) = metadata.managed {
                    existingIOSDevices = try await IOSResourceInventory.load(runner: host,
                        environment: ["DEVELOPER_DIR": pin.developerDirectory], deviceSet: pin.deviceSet).devices
                }
                if case .iosSimulator(let request) = metadata.managed,
                   result.operation.completed.contains("ios.runtime.install"),
                   let existingIOSDevices,
                   case .iosRuntime(let pin)? = installations.first(where: { $0.id == "ios.runtime.install" })?.installation?.managed {
                    let observed = try await IOSResourceInventory.load(runner: host,
                        environment: ["DEVELOPER_DIR": pin.developerDirectory], deviceSet: pin.deviceSet)
                    guard IOSPreparation.preservesDevices(existingIOSDevices, after: observed.devices, installedRuntimeID: pin.identifier) else {
                        throw DomainError(summary: "Existing Simulator conditions changed after runtime installation",
                            remediation: Remediation(summary: "Preserve completed resources. Inspect the changed devices and approve the remaining plan again."))
                    }
                    let fresh = try await inspect(input, runner: host)
                    if let current = fresh.plan, current.project == plan.project, current.app == plan.app,
                       current.files == plan.files, current.androidRequirements == plan.androidRequirements,
                       !current.steps.contains(where: { $0.id == step.id }),
                       current.steps.filter({ $0.kind == "install" || $0.kind == "align" }).allSatisfy({ candidate in
                           plan.steps.contains { $0.id == candidate.id && $0.kind == candidate.kind && $0.installation == candidate.installation }
                       }),
                       let reused = fresh.resources.first(where: {
                           $0.kind == .simulator && $0.origin == .reused && $0.isAvailable == true
                               && $0.identifier.map(pin.existingDeviceIDs.contains) == true
                               && $0.runtimeIdentifier == request.runtimeIdentifier && $0.runtimeBuild == request.runtimeBuild
                               && $0.version == request.runtimeVersion && $0.architecture == request.architecture
                       }) {
                        let now = try sourceFiles(sourceRoot, excluding: installedDestinations)
                        let changed = Set(now.keys).union(originalFiles.keys).filter { now[$0] != originalFiles[$0] }.sorted()
                        guard changed.isEmpty else { throw PreparationSourceChanged(files: changed) }
                        // Installing the approved runtime can make a preserved existing device reusable.
                        result.operation.resources.append(reused)
                        continue
                    }
                }
                result.operation.state = "running"
                events.emit("stage", stage: step.id, state: "running", detail: "\(metadata.package) revision \(metadata.revision)")
                do {
                    let installed = try await action.run(runner: host) { ownedTemporaryPaths in
                        try await verifyInstallation(input: input, host: host, plan: plan, step: step, root: sourceRoot,
                            files: originalFiles, excluding: installedDestinations + ownedTemporaryPaths)
                    }
                    result.operation.resources += installed.resources
                } catch let failure as InstallationActionFailure {
                    result.operation.resources += failure.result.resources
                    events.emit("stage", stage: step.id, state: failure.underlying is CancellationError ? "cancelled" : "failed")
                    throw failure.underlying
                } catch {
                    events.emit("stage", stage: step.id, state: error is CancellationError ? "cancelled" : "failed")
                    throw error
                }
                result.operation.completed.append(step.id)
                events.emit("stage", stage: step.id, state: "succeeded")
                let after = try sourceFiles(prepared.root, excluding: installedDestinations)
                let changedAfter = Set(after.keys).union(originalFiles.keys).filter { after[$0] != originalFiles[$0] }.sorted()
                guard changedAfter.isEmpty else {
                    result.operation.changedFiles = changedAfter
                    throw DomainError(summary: "Source changed during resource installation", remediation: Remediation(summary: "Preserve the completed resource. Inspect changed files manually, then re-plan."))
                }
            }
            if !actions.isEmpty {
                result.operation.state = "running"
                let guarded = PreparationRunner(base: dependencyRunner, plan: plan,
                    root: prepared.root, files: try sourceFiles(prepared.root, excluding: actions.filter { $0.id == "dependencies.flutter" }.map { URL(fileURLWithPath: $0.target) }),
                    excluded: actions.filter { $0.id == "dependencies.flutter" }.map { URL(fileURLWithPath: $0.target) }, actions: actions, events: events) {
                        try await inspect(input, runner: host).plan
                    }
                let includePods = actions.contains { $0.id == "dependencies.pods" }
                var stageContext = UpContext()
                do {
                    if anchor.framework == .flutter {
                        for command in prepared.dependencyCommands {
                            let output = try await guarded.run(command)
                            guard output.terminationStatus.isSuccess else {
                                throw DomainError(summary: "Locked Flutter preparation command failed",
                                    remediation: Remediation(summary: "Preserve completed resources and inspect the locked dependency command before re-planning."))
                            }
                        }
                    } else {
                        _ = try await DependenciesStage(anchor: anchor, runner: guarded,
                            includePods: includePods, forceLockedAlignment: true).run(&stageContext)
                    }
                    result.operation.completed += guarded.completed
                } catch {
                    result.operation.completed += guarded.completed
                    result.operation.changedFiles = guarded.changedFiles
                    result.operation.log = guarded.log
                    throw error
                }
                result.operation.changedFiles = guarded.changedFiles
                result.operation.log = guarded.log
            }
            try Task.checkCancellation()
            let after = try await inspect(input, runner: host)
            result.plan = after.plan
            result.operation.manual = after.plan?.steps.filter { $0.kind != "align" && $0.kind != "install" } ?? []
            result.operation.remaining = after.plan?.steps.filter {
                $0.kind != "align" || !result.operation.completed.contains($0.id)
            }.map(\.id) ?? []
            // Only executed alignment is measured by its successful frozen/locked command.
            if var updated = result.plan {
                for index in updated.platforms.indices {
                    let platform = updated.platforms[index].platform
                    let pending = updated.steps.filter {
                        !result.operation.completed.contains($0.id) && ($0.platform == nil || $0.platform == platform)
                    }
                    updated.platforms[index].state = pending.isEmpty ? "succeeded"
                        : pending.contains { $0.kind == "install" || $0.kind == "align" } ? "needs-approval" : "waiting-manual"
                }
                result.plan = updated
            }
            let completedPlatforms = result.plan?.platforms.filter { $0.state == "succeeded" }.count ?? 0
            result.operation.state = result.operation.remaining.isEmpty ? "succeeded"
                : (!result.operation.completed.isEmpty || completedPlatforms > 0 ? "partial" : "waiting-manual")
            result.exitCode = result.operation.state == "succeeded" ? 0 : 1
            result.operation.nextAction = result.exitCode == 0
                ? "Preparation complete. Build and app launch need separate verification."
                : "Preserve completed resources. Finish manual steps, inspect again, and approve the remaining plan."
        } catch is CancellationError {
            result.exitCode = 130
            result.operation.state = "cancelled"
            result.operation.nextAction = "Completed dependencies and shared caches were preserved. Inspect again before retrying."
        } catch let conflict as ResourceConflict {
            result.exitCode = 1
            result.operation.state = "failed"
            result.operation.conflict = conflict
            result.operation.error = conflict.domainError.message
            result.operation.nextAction = conflict.domainError.remediation.summary
        } catch let changed as PreparationSourceChanged {
            result.exitCode = 1
            result.operation.state = "failed"
            result.operation.changedFiles = changed.files
            result.operation.error = "Source changed during preparation"
            result.operation.nextAction = "Inspect the changed files. No files were restored. Preserve completed packages and re-plan."
        } catch let error as DomainError {
            result.exitCode = 1
            result.operation.state = "failed"
            result.operation.error = error.message
            result.operation.nextAction = error.remediation.summary
        } catch {
            result.exitCode = 2
            result.operation.state = "failed"
            result.operation.error = String(describing: error)
            result.operation.nextAction = "Inspect the failing tool. Preserve completed resources and re-plan."
        }
        result.operation.remaining.removeAll { result.operation.completed.contains($0) }
        return finish(result, events)
    }

    private static func finish(_ result: PreparationResult, _ events: PreparationEvents) -> PreparationResult {
        events.emit(result.operation.state == "cancelled" ? "cancelled" : "finished",
                    state: result.operation.state, detail: result.operation.nextAction)
        return result
    }

    private static func verifyInstallation(input: ProjectInspectionInput, host: any ProcessRunner,
                                           plan: PreparationPlan, step: PreparationStep, root: URL,
                                           files: [String: String], excluding: [URL]) async throws {
        try Task.checkCancellation()
        let now = try sourceFiles(root, excluding: excluding)
        let changed = Set(now.keys).union(files.keys).filter { now[$0] != files[$0] }.sorted()
        guard changed.isEmpty else { throw PreparationSourceChanged(files: changed) }
        guard let current = try await inspect(input, runner: host, excluding: excluding).plan,
              current.project == plan.project, current.app == plan.app, current.files == plan.files,
              current.androidRequirements == plan.androidRequirements,
              current.steps.contains(where: { $0.id == step.id && $0.kind == "install" && $0.installation == step.installation }) else {
            throw DomainError(summary: "Installation conditions changed before the next package commit",
                remediation: Remediation(summary: "Preserve completed packages. Inspect the remaining plan and approve it again."))
        }
    }

    private struct Inspection {
        var plan: PreparationPlan?
        var selection: ProjectSelection?
        var anchor: ProjectAnchor?
        var context: WorkflowContext?
        var dependencyRunner: (any ProcessRunner)?
        var dependencyCommands: [ProcessCommand] = []
        var root: URL
        var installationActions: [String: InstallationAction] = [:]
        var resources: [IOSPreparationResource] = []
    }

    private static func inspect(_ input: ProjectInspectionInput, runner: any ProcessRunner, excluding: [URL] = []) async throws -> Inspection {
        try Task.checkCancellation()
        let detected = try ProjectInspectionInput(directory: input.directory, environment: input.environment, app: input.app, entrypoint: input.entrypoint).selection()
        // Setup selects an app; both platforms remain in its preparation scope.
        let selection = ProjectSelection(directory: detected.directory, candidates: detected.candidates,
            selected: detected.selected, platform: nil,
            requiredInput: detected.requiredInput.filter { $0 != "--platform" }, error: detected.error)
        let root = URL(fileURLWithPath: selection.selected?.workspace?.path ?? selection.selected?.app.path ?? selection.directory.path)
        var value = Inspection(selection: selection, root: root)
        guard selection.error == nil, let selected = selection.selected,
              let anchor = ProjectAnchor.detect(candidate: selected) else {
            // Invalid Flutter declarations remain an explicit migration; no tool is executed.
            if selection.candidates.isEmpty, FileManager.default.fileExists(atPath: root.appendingPathComponent("pubspec.yaml").path) {
                let step = PreparationStep(id: "provider.flutter", platform: nil, kind: "provider", target: root.path,
                    observed: "Flutter declarations do not identify a supported app", required: "Pinned Flutter SDK and locked dependencies",
                    source: CheckSource(tier: 1, origin: "pubspec.yaml"), command: nil,
                    remediation: Remediation(summary: "Supply valid Flutter declarations and an existing entrypoint, then re-plan. No tool installation occurred."))
                value.plan = try makePlan(project: selection.directory, app: ".", kind: "flutter", platforms: [.ios, .android].map {
                    PreparationPlatform(platform: $0, state: "waiting-manual", checks: [])
                }, steps: [step], files: approvalFiles(root, excluding: excluding), installed: [:])
            }
            return value
        }
        if input.entrypoint != nil, anchor.framework != .flutter {
            value.selection = ProjectSelection(directory: selection.directory, candidates: selection.candidates,
                selected: selection.selected, platform: selection.platform, requiredInput: selection.requiredInput,
                error: "An explicit entrypoint requires a Flutter app.")
            return value
        }
        value.anchor = anchor
        var platforms: [PreparationPlatform] = []
        var steps: [PreparationStep] = []
        var contexts: [ProjectPlatform: WorkflowContext] = [:]
        var androidRequirements: AndroidSDKRequirements?
        var sdkInstalled: [String: Bool] = [:]
        // RN preparation always covers both platforms, even with --platform ios.
        let preparationPlatforms: [ProjectPlatform] = anchor.framework == .reactNative || anchor.framework == .flutter
            ? [.ios, .android] : selected.platforms
        let flutter = anchor.framework == .flutter
            ? try await FlutterPreparation.inspect(directory: anchor.directory, entrypoint: input.entrypoint, environment: input.environment, runner: runner) : nil
        if let flutter {
            value.root = flutter.workspace?.directory ?? anchor.directory
            steps += flutter.steps
            sdkInstalled.merge(flutter.installed) { _, new in new }
            value.installationActions.merge(flutter.actions) { _, new in new }
            if let command = flutter.dependencyCommand { value.dependencyCommands.append(command) }
            if flutter.checks.contains(where: { $0.id == "flutter.declarations" && $0.kind != "reuse" }) {
                value.plan = try makePlan(project: selected.app, app: selected.id, kind: anchor.framework.rawValue,
                    platforms: preparationPlatforms.map { platform in PreparationPlatform(platform: platform, state: "waiting-manual",
                        checks: flutter.checks.filter { $0.platform == nil || $0.platform == platform }) },
                    steps: steps, files: approvalFiles(value.root, excluding: excluding), installed: sdkInstalled)
                return value
            }
        }
        let activatedRunner: any ProcessRunner = flutter.map { FlutterChildRunner(base: runner, environment: $0.activeEnvironment) } ?? runner
        let currentEnvironment = await ProjectExecutionEnvironment.resolve(anchor: anchor, hostRunner: activatedRunner)
        let toolRequirements = try await ToolRequirements.resolve(anchor: anchor, platforms: preparationPlatforms, runner: currentEnvironment.runner)
        let toolPreparation = try await ToolPreparation.inspect(requirements: toolRequirements, directory: anchor.directory,
            environment: input.environment, runner: runner, currentToolRunner: currentEnvironment.runner)
        steps += toolPreparation.steps
        sdkInstalled.merge(toolPreparation.installed) { _, new in new }
        value.installationActions.merge(toolPreparation.actions) { _, new in new }
        // Missing project tools must not make their own approved installation
        // depend on running Gradle, npm, or Bundle. Inspect those after tools exist.
        let pendingTools = !toolPreparation.actions.isEmpty
        for platform in preparationPlatforms {
            try Task.checkCancellation()
            guard selected.platforms.contains(platform) else {
                let item = PreparationStep(id: "\(platform.rawValue).host", platform: platform, kind: "migration", target: selected.app.path,
                    observed: "No \(platform.rawValue) host directory", required: "Existing host source; setup does not generate or migrate source",
                    source: CheckSource(tier: 1, origin: selected.app.path), command: nil,
                    remediation: Remediation(summary: "Prepare the host source manually, then inspect again."))
                steps.append(item)
                let checks = [item] + (flutter?.checks.filter { $0.platform == nil || $0.platform == platform } ?? []) + toolPreparation.checks
                platforms.append(PreparationPlatform(platform: platform, state: "waiting-manual", checks: checks))
                continue
            }
            let nativeReady = flutter == nil || flutter?.checks.contains { $0.id == "\(platform.rawValue).flutter.generated" && $0.kind == "reuse" } == true
            let context = await WorkflowContext.make(input: input, platform: platform, anchor: anchor, runner: runner,
                includeProjectEnvironment: !pendingTools && (platform != .android || nativeReady),
                projectEnvironmentOverride: flutter == nil ? nil : currentEnvironment.activatingTools(toolPreparation.activeTools, environment: input.environment))
            contexts[platform] = context
            let report = await context.engine.run()
            var sdkPreparation: AndroidSDKPreparation?
            if platform == .android, let android = context.androidContext {
                let requirements = try await android.sdkRequirements()
                androidRequirements = requirements
                sdkPreparation = try await AndroidSDKPreparation.inspect(requirements, runner: runner)
            }
            try Task.checkCancellation()
            if report.hasToolFailure { throw PreparationProbeError(failures: report.toolFailures.sorted()) }
            var checks = report.checks.sorted { $0.id < $1.id }.map { check in
                PreparationStep(id: "\(platform.rawValue).\(check.id)", platform: platform,
                    kind: check.status == .pass ? "reuse" : manualKind(check.id), target: check.outcome.source.origin,
                    observed: check.id == "host.storage" ? check.status.rawValue : check.outcome.observed,
                    required: check.outcome.required, source: check.outcome.source, command: nil,
                    remediation: check.outcome.remediation ?? (check.outcome.reason.map { Remediation(summary: $0) }))
            }
            checks += toolPreparation.checks
            if let flutter { checks += flutter.checks.filter { $0.platform == nil || $0.platform == platform } }
            if pendingTools {
                checks.append(PreparationStep(id: "\(platform.rawValue).tools.reinspect", platform: platform, kind: "provider", target: selected.app.path,
                    observed: "Project-dependent inspection is deferred until its tools are available", required: "Exact project tool paths",
                    source: CheckSource(origin: "approved tool preparation"), command: nil,
                    remediation: Remediation(summary: "Preserve completed tools. Inspect again and approve any newly observed dependency or SDK steps.")))
            }
            if flutter != nil, platform == .ios, !pendingTools, let requirement = anchor.cocoapods {
                if anchor.gemInstallProcess != nil {
                    checks.append(PreparationStep(id: "ios.cocoapods.version", platform: .ios, kind: "provider", target: anchor.iosDirectory.path,
                        observed: "Bundled CocoaPods was not executed during inspection", required: "Manually verified locked Bundle and CocoaPods",
                        source: CheckSource(tier: 1, origin: requirement.file), command: nil,
                        remediation: Remediation(summary: "Verify the declared locked Bundle manually. Setup inspection does not evaluate the project's Gemfile.")))
                } else {
                    let outcome = try await CocoaPodsVersionCheck(requirement: requirement, anchor: anchor, context: context.config,
                        runner: context.projectRunner).run()
                    checks.append(PreparationStep(id: "ios.cocoapods.version", platform: .ios,
                        kind: outcome.status == .pass ? "reuse" : "provider", target: anchor.iosDirectory.path,
                        observed: outcome.observed, required: outcome.required, source: outcome.source, command: nil, remediation: outcome.remediation))
                }
            }
            if let sdkPreparation {
                checks += sdkPreparation.checks
                sdkInstalled.merge(sdkPreparation.installed) { _, new in new }
                value.installationActions.merge(sdkPreparation.actions) { _, new in new }
            }
            if platform == .ios, !pendingTools, nativeReady {
                let iosPreparation = try await IOSPreparation.inspect(context: context, input: input)
                // Native deployment is measured by the provider. Replace only the
                // Matrix-only unknown when that provider confirms an exact runtime.
                if anchor.framework == .nativeIOS, let lookup = context.lookup,
                   case .unavailable(let reason, let source) = lookup.runtime,
                   report.checks.contains(where: { $0.id == "simulator.runtime" && $0.status == .unknown
                       && $0.outcome.reason == reason && $0.outcome.source == source }),
                   let runtime = iosPreparation.checks.first(where: { $0.id == "ios.runtime" && $0.kind == "reuse" }),
                   iosPreparation.resources.contains(where: { $0.kind == .runtime && $0.origin == .reused
                       && $0.runtimeIdentifier == runtime.target && $0.isAvailable == true
                       && $0.architecture == "arm64" && $0.runtimeBuild != nil && $0.version != nil }) {
                    checks.removeAll { $0.id == "ios.simulator.runtime" }
                }
                checks += iosPreparation.checks
                sdkInstalled.merge(iosPreparation.installed) { _, new in new }
                value.installationActions.merge(iosPreparation.actions) { _, new in new }
                value.resources += iosPreparation.resources
            }
            if anchor.framework == .reactNative, !pendingTools, !checks.contains(where: { $0.id.hasSuffix(".package-manager.version") }) {
                let output = try await optionalTool(ProcessCommand(anchor.packageManagerName, ["--version"],
                    workingDirectory: anchor.workspaceRoot?.directory ?? anchor.directory, timeout: .seconds(15)), runner: context.projectRunner)
                let version = output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                let usable = output.terminationStatus.isSuccess && SemanticVersion(version) != nil
                checks.append(PreparationStep(id: "\(platform.rawValue).package-manager.version", platform: platform,
                    kind: usable ? "reuse" : "provider", target: anchor.packageManagerName,
                    observed: usable ? version : output.combinedOutput.split(whereSeparator: \.isNewline).first.map(String.init),
                    required: "Usable \(anchor.packageManagerName) selected by existing lockfile", source: CheckSource(tier: 1, origin: anchor.workspaceRoot?.lockfile ?? "package.json"),
                    command: nil, remediation: usable ? nil : Remediation(summary: "Prepare the existing package manager separately, then inspect again.")))
            }
            var selectedTools: [String] = []
            if (anchor.framework == .reactNative || anchor.framework == .flutter), !pendingTools {
                selectedTools = anchor.framework == .reactNative ? ["node", anchor.packageManagerName] : []
                if anchor.gemInstallProcess != nil { selectedTools += ["ruby", "bundle"] }
                else if FileManager.default.fileExists(atPath: anchor.directory.appendingPathComponent("ios/Podfile").path) { selectedTools += ["pod"] }
            }
            for tool in Set(selectedTools).sorted() {
                let probe = try await optionalTool(ProcessCommand("/usr/bin/which", [tool],
                    workingDirectory: anchor.directory, timeout: .seconds(15)), runner: context.projectRunner)
                let path = probe.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                let known = probe.terminationStatus.isSuccess == true && path.hasPrefix("/") && !path.contains("\n")
                checks.append(PreparationStep(id: "\(platform.rawValue).tool.\(tool).path", platform: platform,
                    kind: known ? "reuse" : "provider", target: known ? path : "unknown \(tool) executable",
                    observed: known ? path : nil, required: "Known executable in the selected project toolchain",
                    source: CheckSource(origin: "project toolchain"), command: nil,
                    remediation: known ? nil : Remediation(summary: "Prepare the declared tool and inspect its executable path before approval.")))
            }
            // Scheme selection is a build input; setup does not silently pick one.
            steps += checks.filter { check in check.kind != "reuse" && !check.id.hasPrefix("tools.") && !check.id.hasSuffix(".config.values")
                && !steps.contains(where: { $0.id == check.id }) }
            platforms.append(PreparationPlatform(platform: platform, state: "waiting-manual", checks: checks))
        }
        let context = contexts[.ios] ?? contexts[.android]
        value.context = context
        value.dependencyRunner = context?.projectRunner ?? currentEnvironment.runner
        if anchor.framework != .reactNative && anchor.framework != .flutter {
            value.plan = try makePlan(project: selected.app, app: selected.id, kind: anchor.framework.rawValue,
                                     platforms: platforms, steps: steps, files: approvalFiles(root, excluding: excluding), installed: sdkInstalled,
                                     androidRequirements: androidRequirements, resources: value.resources)
            return value
        }
        var installed: [String: Bool] = sdkInstalled
        let node: PreparationStep
        if let flutter {
            node = flutter.checks.first { $0.id == "dependencies.flutter" } ?? PreparationStep(id: "dependencies.flutter",
                platform: nil, kind: "migration", target: value.root.path, observed: "Locked alignment is unavailable",
                required: "Resolved Dart workspace and lock", source: CheckSource(origin: "pubspec.lock"), command: nil, remediation: nil)
        } else {
            let nodeReady = platforms.flatMap(\.checks).contains { $0.id.hasSuffix(".node.version") && $0.kind == "reuse" }
                && platforms.flatMap(\.checks).contains { $0.id.hasSuffix(".package-manager.version") && $0.kind == "reuse" }
                && platforms.flatMap(\.checks).contains { $0.id.hasSuffix(".tool.node.path") && $0.kind == "reuse" }
                && platforms.flatMap(\.checks).contains { $0.id.hasSuffix(".tool.\(anchor.packageManagerName).path") && $0.kind == "reuse" }
            let dependencyRoot = anchor.workspaceRoot?.directory ?? anchor.directory
            let hasNodeLock = ["package-lock.json", "yarn.lock", "pnpm-lock.yaml", "npm-shrinkwrap.json"].contains {
                FileManager.default.fileExists(atPath: dependencyRoot.appendingPathComponent($0).path)
            }
            for relative in ["node_modules", "node_modules/.mobile-install.incomplete", "ios/Pods", "ios/Pods/Manifest.lock"] {
                let base = relative.hasPrefix("node_modules") ? dependencyRoot : anchor.directory
                installed[base.appendingPathComponent(relative).path] = FileManager.default.fileExists(atPath: base.appendingPathComponent(relative).path)
            }
            node = PreparationStep(id: "dependencies.node", platform: nil,
                kind: nodeReady && hasNodeLock ? "align" : "migration", target: dependencyRoot.appendingPathComponent("node_modules").path,
                observed: installed[dependencyRoot.appendingPathComponent("node_modules").path] == true ? "existing installation; native lockfile alignment required" : "missing",
                required: "existing lockfile and usable Node/package manager", source: CheckSource(tier: 1, origin: dependencyRoot.path),
                command: anchor.installProcess.description, remediation: Remediation(summary: "Use the declared locked package manager. Prepare missing tools separately; do not generate a lockfile in setup."))
            steps.append(node)
        }
        let ios = anchor.directory.appendingPathComponent("ios")
        if FileManager.default.fileExists(atPath: ios.appendingPathComponent("Podfile").path) {
            let generatedReady = flutter == nil || flutter?.checks.contains { $0.id == "ios.flutter.generated" && $0.kind == "reuse" } == true
            var podReady = platforms.first { $0.platform == .ios }?.checks.contains { $0.id.hasSuffix(".cocoapods.version") && $0.kind == "reuse" } == true
            if anchor.gemInstallProcess == nil, (flutter == nil || anchor.cocoapods == nil), let context {
                let podVersion = try await optionalTool(anchor.podVersionProcess, runner: context.projectRunner)
                podReady = podVersion.terminationStatus.isSuccess == true
                    && platforms.flatMap(\.checks).contains { $0.id.hasSuffix(".tool.pod.path") && $0.kind == "reuse" }
            }
            if flutter != nil, !toolPreparation.checks.contains(where: { $0.id == "tools.ruby" && $0.kind == "reuse" }) { podReady = false }
            let podLock = FileManager.default.fileExists(atPath: ios.appendingPathComponent("Podfile.lock").path)
            let manifest = try? Data(contentsOf: ios.appendingPathComponent("Pods/Manifest.lock"))
            let lockedPods = try? Data(contentsOf: ios.appendingPathComponent("Podfile.lock"))
            let podsAligned = manifest != nil && manifest == lockedPods
            let gemLock = anchor.gemInstallProcess == nil || FileManager.default.fileExists(atPath: (anchor.gemInstallProcess?.workingDirectory ?? anchor.directory).appendingPathComponent("Gemfile.lock").path)
            if let gems = anchor.gemInstallProcess, flutter != nil {
                steps.append(PreparationStep(id: "dependencies.gems", platform: .ios, kind: "migration",
                    target: (gems.workingDirectory ?? anchor.directory).path, observed: "Bundler destination was not inspected",
                    required: "Existing Gemfile.lock and manually verified Bundle destination", source: CheckSource(tier: 1, origin: "Gemfile.lock"),
                    command: nil, remediation: Remediation(summary: "Preserve the existing Bundle destination. Prepare the declared locked Bundle manually, then re-plan.")))
            } else if let gems = anchor.gemInstallProcess, let context {
                let gemRoot = gems.workingDirectory ?? anchor.directory
                let bundleVersion = try await optionalTool(ProcessCommand("bundle", ["--version"], workingDirectory: gemRoot), runner: context.projectRunner)
                let pathProbe = try await optionalTool(ProcessCommand("bundle", ["config", "get", "path", "--parseable"],
                    workingDirectory: gemRoot, timeout: .seconds(15)), runner: context.projectRunner)
                let ruby = platforms.first { $0.platform == .ios }?.checks.first { $0.id.hasSuffix(".ruby.version") }
                let destinationProbe = try await optionalTool(ProcessCommand("ruby", ["-rbundler", "-e", "print Bundler.bundle_path"], workingDirectory: gemRoot), runner: context.projectRunner)
                let destination = destinationProbe.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                var bundleReady = bundleVersion.terminationStatus.isSuccess == true && pathProbe.terminationStatus.isSuccess == true
                    && destinationProbe.terminationStatus.isSuccess == true && destination.hasPrefix("/") && !destination.contains("\n")
                    && (ruby == nil || ruby?.kind == "reuse")
                    && (flutter == nil || toolPreparation.checks.contains { $0.id == "tools.ruby" && $0.kind == "reuse" })
                    && ["ruby", "bundle"].allSatisfy { tool in platforms.flatMap(\.checks).contains { $0.id.hasSuffix(".tool.\(tool).path") && $0.kind == "reuse" } }
                let output = pathProbe.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                let declaredPath = output.hasPrefix("path=") ? String(output.dropFirst(5)).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) : ""
                var policy = ["BUNDLE_FROZEN": "true"]
                if !declaredPath.isEmpty {
                    let expanded = (declaredPath as NSString).expandingTildeInPath
                    policy["BUNDLE_PATH"] = URL(fileURLWithPath: expanded, relativeTo: gemRoot).standardizedFileURL.path
                    policy["BUNDLE_PATH__SYSTEM"] = "false"
                } else {
                    policy["BUNDLE_PATH__SYSTEM"] = "true"
                }
                // Pinning the base path must preserve Bundler's effective Ruby-specific destination.
                let effectiveProbe = try await optionalTool(ProcessCommand("ruby", ["-rbundler", "-e", "print Bundler.bundle_path"], environment: policy, workingDirectory: gemRoot), runner: context.projectRunner)
                bundleReady = bundleReady && effectiveProbe.terminationStatus.isSuccess == true
                    && effectiveProbe.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == destination
                podReady = bundleReady && (flutter == nil || platforms.first { $0.platform == .ios }?.checks.contains {
                    $0.id == "ios.cocoapods.version" && $0.kind == "reuse"
                } == true)
                var gemStep = PreparationStep(id: "dependencies.gems", platform: .ios,
                    kind: bundleReady && gemLock && node.kind == "align" && generatedReady ? "align" : "migration", target: destination.isEmpty ? "unknown Bundler destination" : destination,
                    observed: bundleVersion.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines), required: "existing Gemfile.lock; BUNDLE_FROZEN=true; preserve the existing Bundler destination",
                    source: CheckSource(tier: 1, origin: "Gemfile.lock"), command: gems.description,
                    remediation: Remediation(summary: "Prepare the declared locked Bundle manually if its tools, destination, or lockfile are unknown."))
                gemStep.environment = policy
                steps.append(gemStep)
                if anchor.framework == .flutter, gemStep.kind == "align" { value.dependencyCommands.append(gems) }
                if bundleReady { installed[destination] = FileManager.default.fileExists(atPath: destination) }
            }
            steps.append(PreparationStep(id: "dependencies.pods", platform: .ios,
                kind: podReady && podLock && gemLock && node.kind == "align" && generatedReady && (flutter == nil || isFrozenPodCommand(anchor.podInstallProcess)) ? "align" : "migration", target: ios.appendingPathComponent("Pods").path,
                observed: podsAligned ? "Pods Manifest.lock matches Podfile.lock; approved frozen alignment still runs"
                    : "Pods missing or Manifest.lock differs from Podfile.lock", required: "existing Podfile.lock; declared installation",
                source: CheckSource(tier: 1, origin: anchor.podInstallEvidence), command: frozenPodCommand(anchor.podInstallProcess).description,
                remediation: Remediation(summary: "Use the declared locked Pod installation. Source or lockfile migration requires manual handling.")))
            if anchor.framework == .flutter, steps.last?.kind == "align" {
                value.dependencyCommands.append(frozenPodCommand(anchor.podInstallProcess))
            }
        }
        var files = try approvalFiles(value.root, excluding: excluding)
        if let flutter {
            if let entrypoint = flutter.entrypoint { files[entrypoint.path] = digest(try Data(contentsOf: entrypoint)) }
            if let project = try? FlutterProject(directory: anchor.directory, entrypoint: input.entrypoint) {
                for pin in project.pinSources where !["mise.toml", ".mise.toml"].contains(pin.lastPathComponent) {
                    files[pin.path] = digest(try Data(contentsOf: pin))
                }
            }
        }
        value.plan = try makePlan(project: selected.app, app: selected.id, kind: anchor.framework.rawValue, platforms: platforms,
                                 steps: steps, files: files, installed: installed,
                                 androidRequirements: androidRequirements, resources: value.resources)
        return value
    }

    private static func optionalTool(_ command: ProcessCommand, runner: any ProcessRunner) async throws -> ProcessResult {
        do { return try await runner.run(command) }
        catch let error as ProcessError {
            guard case .spawnFailed = error else { throw error }
            return ProcessResult(terminationStatus: .exited(127), standardOutput: "", standardError: "Selected project tool is not installed")
        }
    }

    private static func manualKind(_ check: String) -> String {
        if check == "xcode.ready" || check.contains("license") { return "license" }
        if check == "project.execution-environment" { return "trust" }
        if check == "host.workspace-access" { return "permission" }
        return "provider"
    }

    private static func isFrozenPodCommand(_ command: ProcessCommand) -> Bool {
        command.executable == "pod" && command.arguments == ["install"]
            || command.executable == "bundle" && command.arguments == ["exec", "pod", "install"]
    }

    fileprivate static func frozenPodCommand(_ input: ProcessCommand) -> ProcessCommand {
        var command = input
        if command.executable == "pod" && command.arguments == ["install"]
            || command.executable == "bundle" && command.arguments == ["exec", "pod", "install"] {
            command.arguments.append("--deployment")
        }
        return command
    }

    private static func makePlan(project: FolderIdentity, app: String, kind: String,
                                 platforms: [PreparationPlatform], steps: [PreparationStep], files: [String: String], installed: [String: Bool],
                                 androidRequirements: AndroidSDKRequirements? = nil,
                                 resources: [IOSPreparationResource] = []) throws -> PreparationPlan {
        var plan = PreparationPlan(id: "", project: project, app: app, projectKind: kind,
                                   platforms: platforms, steps: steps.sorted { $0.id < $1.id }, files: files, installed: installed)
        plan.androidRequirements = androidRequirements
        plan.resources = resources.isEmpty ? nil : resources
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        plan.id = digest(try encoder.encode(plan))
        return plan
    }

    fileprivate static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func approvalFiles(_ root: URL, excluding: [URL] = []) throws -> [String: String] {
        let names: Set<String> = ["package.json", "package-lock.json", "npm-shrinkwrap.json", "yarn.lock", "pnpm-lock.yaml", "pnpm-workspace.yaml", "Podfile", "Podfile.lock", "Manifest.lock", "Gemfile", "Gemfile.lock", "pubspec.yaml", "pubspec.lock", "pubspec_overrides.yaml", ".fvmrc", ".flutter-version", "mobile.yml", ".nvmrc", ".node-version", ".ruby-version", ".java-version", ".tool-versions", ".xcode-version", "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts", "gradle-wrapper.properties", "project.pbxproj"]
        var result = try sourceFiles(root, excluding: excluding).filter { names.contains(URL(fileURLWithPath: $0.key).lastPathComponent) }
        for name in [".mise.toml", "mise.toml"] {
            let url = root.appendingPathComponent(name)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            var tools = false
            let declarations = text.split(whereSeparator: \.isNewline).compactMap { line -> String? in
                let value = line.trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("[") { tools = value == "[tools]" || value.hasPrefix("[tools.") }
                return tools || value.hasPrefix("tools =") ? value : nil
            }.joined(separator: "\n")
            // Environment/private values in mise config are not approval identity inputs.
            result[url.path] = digest(Data(declarations.utf8))
        }
        return result
    }

    /// Private source/lock observation. Digests never enter the public plan or its identity.
    fileprivate static func sourceFiles(_ root: URL, excluding destinations: [URL] = []) throws -> [String: String] {
        let excluded: Set<String> = [".git", "node_modules", "Pods", "vendor", "build", ".build", ".gradle", ".dart_tool", ".mobile", "graft"]
        var failure: (any Error)?
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            errorHandler: { _, error in failure = error; return false }) else { throw CocoaError(.fileReadNoPermission) }
        var result: [String: String] = [:]
        let destinationPaths = Set(destinations.map { $0.standardizedFileURL.resolvingSymlinksInPath().path })
        for case let url as URL in files {
            if destinationPaths.contains(url.standardizedFileURL.resolvingSymlinksInPath().path) {
                files.skipDescendants()
                continue
            }
            let attributes = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if excluded.contains(url.lastPathComponent) { files.skipDescendants(); continue }
            if url.pathExtension == "log" || url.lastPathComponent == ".DS_Store" { continue }
            if attributes.isSymbolicLink == true {
                files.skipDescendants()
                result[url.path] = "symlink:" + (try FileManager.default.destinationOfSymbolicLink(atPath: url.path))
            } else if attributes.isDirectory != true {
                result[url.path] = digest(try Data(contentsOf: url))
            }
        }
        if let failure { throw failure }
        return result
    }
}

private struct PreparationProbeError: Error { let failures: [String] }
private struct PreparationSourceChanged: Error { let files: [String] }

private final class PreparationEvents: @unchecked Sendable {
    let id = UUID().uuidString
    private let lock = NSLock()
    private var sequence = 0
    private let callback: (@Sendable (WorkflowEvent) -> Void)?
    init(_ callback: (@Sendable (WorkflowEvent) -> Void)?) { self.callback = callback }
    func emit(_ kind: String, stage: String? = nil, state: String, detail: String? = nil) {
        lock.withLock {
            sequence += 1
            callback?(WorkflowEvent(operationId: id, sequence: sequence, kind: kind, stageId: stage, state: state, detail: detail))
        }
    }
}

private final class PreparationRunner: ProcessRunner, @unchecked Sendable {
    let base: any ProcessRunner
    let plan: PreparationPlan
    let root: URL
    let files: [String: String]
    let excluded: [URL]
    let actions: [PreparationStep]
    let events: PreparationEvents
    let freshPlan: @Sendable () async throws -> PreparationPlan?
    private let lock = NSLock()
    private var finished: [String] = []
    private var changed: [String] = []
    private var logPath: String?
    var completed: [String] { lock.withLock { finished } }
    var changedFiles: [String] { lock.withLock { changed } }
    var log: String? { lock.withLock { logPath } }
    init(base: any ProcessRunner, plan: PreparationPlan, root: URL, files: [String: String], excluded: [URL], actions: [PreparationStep], events: PreparationEvents,
         freshPlan: @escaping @Sendable () async throws -> PreparationPlan?) {
        self.base = base; self.plan = plan; self.root = root; self.files = files; self.excluded = excluded; self.actions = actions; self.events = events
        self.freshPlan = freshPlan
    }
    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        try Task.checkCancellation()
        let frozen = PreparationExecution.frozenPodCommand(command)
        let action = actions.first { $0.command == frozen.description }
        guard action != nil || command.executable == "bundle" && command.arguments == ["check"] else {
            throw DomainError(summary: "Dependency command is outside the approved plan", remediation: Remediation(summary: "Re-plan before executing any other command."))
        }
        try checkFiles()
        try await verifyConditions(completed)
        try checkFiles()
        if case .streamed(let path) = command.output { lock.withLock { logPath = path.path } }
        if let action { events.emit("stage", stage: action.id, state: "running", detail: command.description) }
        do {
            var effective = frozen
            if let gems = actions.first(where: { $0.id == "dependencies.gems" }) {
                effective.environment.merge(gems.environment) { _, selected in selected }
            }
            let result = try await base.run(effective, onLine: onLine)
            if let action, result.terminationStatus.isSuccess {
                lock.withLock { if !finished.contains(action.id) { finished.append(action.id) } }
                events.emit("stage", stage: action.id, state: "succeeded")
            }
            try checkFiles()
            try Task.checkCancellation()
            return result
        } catch {
            try checkFiles()
            throw error
        }
    }
    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
        throw DomainError(summary: "Setup cannot spawn runtime processes", remediation: Remediation(summary: "Run build/up separately after preparation."))
    }
    private func verifyConditions(_ completed: [String]) async throws {
        guard let current = try await freshPlan(),
              current.project == plan.project, current.app == plan.app, current.files == plan.files,
              try Self.executionConditions(current, completed: completed) == Self.executionConditions(plan, completed: completed)
        else {
            throw DomainError(summary: "Preparation conditions changed before a dependency command",
                remediation: Remediation(summary: "Preserve completed resources. Inspect the current tools and approve a new plan."))
        }
    }
    private static func executionConditions(_ plan: PreparationPlan, completed: [String]) throws -> Data {
        // Installed resources change through this operation. Tool selection and destinations do not.
        struct Conditions: Encodable {
            let checks: [PreparationStep]
            let destinations: [String: [String: String]]
            let androidRequirements: AndroidSDKRequirements?
        }
        let checks = plan.platforms.flatMap(\.checks).filter {
            ($0.id.hasSuffix(".version") || $0.id.hasSuffix(".path") || $0.id.hasSuffix(".xcode.installed")
                || $0.id.hasSuffix(".xcode.ready") || $0.id.hasSuffix(".project.execution-environment")
                || $0.id.hasPrefix("flutter.") || $0.id.hasSuffix(".flutter.generated"))
                && !($0.id.hasSuffix(".cocoapods.version") && completed.contains("dependencies.gems"))
        }
        let destinations = Dictionary(uniqueKeysWithValues: plan.steps.filter { $0.id.hasPrefix("dependencies.") }.map {
            ($0.id, $0.environment.merging(["kind": $0.kind, "target": $0.target, "command": $0.command ?? ""]) { _, last in last })
        })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Conditions(checks: checks, destinations: destinations, androidRequirements: plan.androidRequirements))
    }
    private func checkFiles() throws {
        let now = try PreparationExecution.sourceFiles(root, excluding: excluded)
        let differences = Set(now.keys).union(files.keys).filter { now[$0] != files[$0] }.sorted()
        guard differences.isEmpty else {
            lock.withLock { changed = differences }
            throw DomainError(summary: "Source or lockfile changed during preparation", observed: differences.joined(separator: ", "),
                remediation: Remediation(summary: "Inspect the changed files. No files were automatically restored. Handle migrations manually and re-plan."))
        }
    }
}

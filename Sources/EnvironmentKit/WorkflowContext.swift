import AndroidKit
import Core
import Foundation
import SimulatorKit

/// What every command stands on: one logging bootstrap, one anchor detection, one
/// set of Checks. `build` and `up` reusing this is what keeps either from calling a
/// project broken that `doctor` just called fine — they read it the same way.
public struct WorkflowContext: Sendable {
    /// nil outside a selected project. What that means is the command's call:
    /// doctor says so and carries on with host checks; build and up have nothing to do.
    public let anchor: ProjectAnchor?
    public let engine: DoctorEngine
    /// What the Stages need and the Checks already had: workflows read the same
    /// mobile.yml, through the same runner, against the same Xcode.
    public let config: ConfigContext
    public let lookup: MatrixLookup?
    /// Machine commands: Xcode discovery, simulator control, install, launch, down.
    public let runner: any ProcessRunner
    /// Project commands: tool checks and build; RN also runs dependencies and Metro.
    public let projectRunner: any ProcessRunner
    /// One opaque actor supplies doctor and the read-only preparation requirements.
    public let androidContext: AndroidDoctorContext?
    public let locator: XcodeLocator
    let flutter: FlutterPreparation?

    public static func make(
        input: ProjectInspectionInput,
        platform: ProjectPlatform,
        anchor: ProjectAnchor?,
        runner: any ProcessRunner,
        includeProjectEnvironment: Bool = true,
        includeRuntimeSDKTools: Bool = true,
        projectEnvironmentOverride: ProjectExecutionEnvironment? = nil,
        projectRunnerOverride: (any ProcessRunner)? = nil,
        selectedConfig: ConfigContext? = nil,
        selectedConfiguration: String? = nil
    ) async -> WorkflowContext {
        let locator = XcodeLocator(runner: runner, developerDirOverride: input.environment["DEVELOPER_DIR"])
        let workingDirectory = input.directory.standardizedFileURL.resolvingSymlinksInPath()
        // mobile.yml is read before the matrix: its overrides are part of what the
        // Tier 2 checks compare against.
        let config = selectedConfig ?? ConfigContext.detect(anchor: anchor, workingDirectory: workingDirectory)
        let lookup = anchor.map { MatrixLookup.resolve(anchor: $0, config: config.configuration) }
        var flutter: FlutterPreparation?
        var flutterChecks: [any Check] = []
        if includeProjectEnvironment, projectEnvironmentOverride == nil, let anchor, anchor.framework == .flutter, platform == .ios {
            do {
                let prepared = try await FlutterPreparation.inspect(directory: anchor.directory, entrypoint: input.entrypoint,
                    environment: input.environment, runner: runner)
                flutter = prepared
                flutterChecks = prepared.checks.filter { $0.platform == nil || $0.platform == .ios }.map {
                    FlutterIOSPreparationCheck(step: $0, root: prepared.workspace?.directory ?? anchor.directory)
                }
                if let sdk = prepared.sdk { flutterChecks.append(FlutterIOSSDKCheck(sdk: sdk)) }
            } catch { flutterChecks = [ToolObservationFailureCheck(error: error)] }
        }
        var projectEnvironment: ProjectExecutionEnvironment?
        var toolObservationChecks: [any Check] = []
        if includeProjectEnvironment, let anchor {
            if let projectEnvironmentOverride { projectEnvironment = projectEnvironmentOverride }
            else {
                let selected: any ProcessRunner = flutter.map { FlutterChildRunner(base: runner, environment: $0.activeEnvironment) } ?? runner
                projectEnvironment = await ProjectExecutionEnvironment.resolve(anchor: anchor, hostRunner: selected)
            }
            if let current = projectEnvironment, anchor.framework != .flutter {
                do {
                    let requirements = try await ToolRequirements.resolve(anchor: anchor, platforms: [platform], runner: current.runner)
                    let tools = try await ToolPreparation.inspect(requirements: requirements, directory: anchor.directory,
                        environment: input.environment, runner: runner, currentToolRunner: current.runner, planInstallations: false)
                    projectEnvironment = current.activatingTools(tools.activeTools, environment: input.environment)
                    toolObservationChecks += tools.checks.map { ToolRequirementCheck(step: $0) }
                } catch {
                    toolObservationChecks.append(ToolObservationFailureCheck(error: error))
                }
            }
        } else {
            projectEnvironment = nil
        }
        let blockedFlutter = platform == .android && anchor?.framework == .flutter
            && includeProjectEnvironment && projectRunnerOverride == nil
        if blockedFlutter {
            projectEnvironment = nil
            toolObservationChecks.append(FlutterAndroidReadinessCheck())
        }
        let projectRunner: any ProcessRunner = blockedFlutter
            ? FlutterAndroidReadinessCheck() : projectRunnerOverride ?? projectEnvironment?.runner ?? runner
        var paths = [workingDirectory, FileManager.default.temporaryDirectory]
        if let anchor {
            paths.append(anchor.directory)
            if let root = anchor.workspaceRoot { paths.append(root.directory) }
        }
        let environment = input.environment
        var unresolvedCache: String?
        if let anchor, anchor.framework == .reactNative, let projectEnvironment, anchor.packageManagerName == "npm" {
            let command = ProcessCommand(
                "npm", ["config", "get", "cache"],
                workingDirectory: anchor.workspaceRoot?.directory ?? anchor.directory,
                timeout: .seconds(15)
            )
            do {
                let result = try await projectEnvironment.runner.run(command)
                let path = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                if result.terminationStatus.isSuccess, path.hasPrefix("/"), !path.contains("\n") {
                    paths.append(URL(fileURLWithPath: path))
                } else {
                    let diagnostic = result.combinedOutput.split(whereSeparator: \.isNewline).first.map(String.init)
                    unresolvedCache = "npm's effective cache path could not be read: \(diagnostic ?? String(describing: result.terminationStatus)). Run npm config get cache in the project's toolchain environment."
                }
            } catch {
                unresolvedCache = "npm's effective cache path could not be read: \(error). Run npm config get cache in the project's toolchain environment."
            }
        }
        if platform == .android {
            let gradle = environment["GRADLE_USER_HOME"].map { URL(fileURLWithPath: $0) }
                ?? environment["HOME"].map { URL(fileURLWithPath: $0).appendingPathComponent(".gradle") }
            if let gradle { paths.append(gradle) }
        }
        var uniquePaths: [URL] = []
        for path in paths where !uniquePaths.contains(path.standardizedFileURL) {
            uniquePaths.append(path.standardizedFileURL)
        }
        let workspaceChecks: [any Check] = [
            WorkspaceAccessCheck(paths: uniquePaths, unresolvedCache: unresolvedCache), WorkspaceStorageCheck(paths: uniquePaths),
            DeviceOriginRecordCheck(record: DeviceOriginRecord(environment: input.environment))
        ]
        let checks: [any Check]
        var androidContext: AndroidDoctorContext?
        switch platform {
        case .ios:
            let projectChecks = if let anchor, let projectEnvironment {
                projectEnvironment.checks(anchor: anchor, context: config).filter {
                    anchor.framework != .flutter || $0.id != "project.detected"
                }
            } else {
                [any Check]()
            }
            let nativeChecks: [any Check] = if let anchor, anchor.framework == .nativeIOS {
                [NativeIOSProjectCheck(anchor: anchor, config: config, lookup: lookup,
                    runner: projectEnvironment?.runner ?? runner, locator: locator,
                    configuration: selectedConfiguration ?? "Debug")]
            } else if let anchor, anchor.framework == .flutter, let sdk = flutter?.sdk {
                [FlutterIOSHostCheck(anchor: anchor, config: config, lookup: lookup,
                    runner: projectEnvironment?.runner ?? runner, locator: locator,
                    entrypoint: input.entrypoint, sdk: sdk.root, configuration: selectedConfiguration)]
            } else { [] }
            let platformChecks = iOSChecks(lookup: lookup, runner: runner, locator: locator).filter {
                // The prepared Flutter check grades its measured app deployment target.
                $0.id != "simulator.runtime" || anchor?.framework != .flutter || flutter?.sdk == nil
            }
            checks = flutterChecks + workspaceChecks + platformChecks
                + configChecks(context: config, lookup: lookup, runner: runner, locator: locator)
                + projectChecks + nativeChecks
        case .android:
            var android = config.checks()
            if let anchor, let projectEnvironment {
                let context = AndroidDoctorContext(anchor: anchor, config: config, hostRunner: runner,
                    projectRunner: projectRunner, environment: AndroidEnvironment(values: input.environment))
                androidContext = context
                let platformChecks = androidChecks(context: context, includeRuntimeSDKTools: includeRuntimeSDKTools)
                // The project identity is the first Android fact; the shared tool
                // environment and Node checks follow before Gradle requirements.
                android.append(platformChecks[0])
                android.append(contentsOf: projectEnvironment.commonChecks(anchor: anchor, context: config))
                android.append(contentsOf: platformChecks.dropFirst())
            } else if let anchor, anchor.framework == .flutter {
                // Source identity does not require a prepared model or an executable project environment.
                let refused = FlutterAndroidReadinessCheck()
                let identity = AndroidDoctorContext(anchor: anchor, config: config, hostRunner: refused,
                    projectRunner: refused, environment: AndroidEnvironment(values: input.environment))
                android.append(contentsOf: androidChecks(context: identity, includeRuntimeSDKTools: false).prefix(1))
            }
            checks = workspaceChecks + android
        }

        return WorkflowContext(
            anchor: anchor,
            engine: DoctorEngine(checks: toolObservationChecks + checks),
            config: config,
            lookup: lookup,
            runner: runner,
            projectRunner: projectRunner,
            androidContext: androidContext,
            locator: locator, flutter: flutter
        )
    }
}

private struct ToolObservationFailureCheck: Check {
    let error: any Error
    let id = "tools.observation"
    let category = "Project tools"
    let title = "Observe exact project tools without installation"
    func run() async throws -> CheckOutcome { throw error }
}

private struct ToolRequirementCheck: Check {
    let step: PreparationStep
    var id: String { step.id }
    let category = "Project tools"
    var title: String { "Exact prepared tool: \(step.id)" }
    func run() async throws -> CheckOutcome {
        if step.kind == "reuse" {
            return .pass(observed: step.observed, required: step.required, source: step.source)
        }
        return .error(observed: step.observed ?? "The exact project tool is not available", required: step.required,
            source: step.source, remediation: step.remediation ?? Remediation(summary: "Inspect and approve an exact setup plan before building."))
    }
}

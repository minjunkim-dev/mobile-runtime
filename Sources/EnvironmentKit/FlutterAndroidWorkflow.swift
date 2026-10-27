import Core
import Foundation
import OSLog

/// One internal seam permits caller fixtures without copying or running an actual SDK.
protocol FlutterAndroidExecutionView: Sendable {
    var sdk: URL { get }
    func runner(base: any ProcessRunner) -> any ProcessRunner
}

extension FlutterAndroidExecution: FlutterAndroidExecutionView {}

/// The same prepared, protected project runner supplies doctor, setup, build and up.
struct FlutterAndroidWorkflow: Sendable {
    typealias Factory = @Sendable (URL, FlutterPreparation, [URL]) throws -> any FlutterAndroidExecutionView
    static let defaultFactory: Factory = {
        try FlutterAndroidExecution.prepare(app: $0, preparation: $1, trackedFiles: $2)
    }
    /// The factory copies and checks the SDK synchronously but checks cancellation per file and per 4 MB read.
    static let preparingViewDetail = "Preparing the protected Flutter Android SDK view. Copying and checking the SDK can take minutes; cancellation stops it at the next file."
    static let viewReadyDetail = "The protected Flutter Android SDK view is ready. Running Android checks."

    let projectEnvironment: ProjectExecutionEnvironment
    let projectRunner: any ProcessRunner
    let workspace: FlutterWorkspace
    let entrypoint: URL

    static func make(input: ProjectInspectionInput, anchor: ProjectAnchor, runner: any ProcessRunner,
                     preparedDependencies: Bool = false,
                     preparation existing: FlutterPreparation? = nil, tools existingTools: ToolPreparation? = nil,
                     factory: Factory = defaultFactory) async throws -> Self {
        try Task.checkCancellation()
        guard anchor.framework == .flutter, anchor.hasAndroidDirectory else {
            throw failure()
        }
        var preparation: FlutterPreparation
        if let existing { preparation = existing }
        else {
            preparation = try await FlutterPreparation.inspect(directory: anchor.directory,
                entrypoint: input.entrypoint, environment: input.environment, runner: runner,
                preparedDependencies: preparedDependencies)
        }
        // Reuse the current graph/config validator. A workspace member never needs a local config.
        let inputs = try FlutterAndroidExecution.preparedInputs(app: anchor.directory, preparation: preparation, trackedFiles: [])
        guard let workspace = preparation.workspace else { throw failure() }
        let inventory = try PreparationExecution.sourceFiles(workspace.directory, packageRoots: workspace.packages)
        let tracked = inventory.keys.sorted().map { URL(fileURLWithPath: $0) }
        if preparedDependencies, let sdk = preparation.sdk {
            preparation.sourceLinks = try await FlutterSourceLinks.capture(root: workspace.directory,
                sources: Set(inventory.keys), links: Set(inventory.filter { $0.value.hasPrefix("symlink:") }.keys),
                forbidden: [sdk.root, inputs.entrypoint], packageRoots: workspace.packages, runner: runner)
        }
        try Task.checkCancellation()
        let view = try factory(anchor.directory, preparation, tracked)
        // Releasing the view removes its exclusive directory, after an interruption too.
        try Task.checkCancellation()
        var environment = preparation.activeEnvironment
        environment["FLUTTER_ROOT"] = view.sdk.path
        let host: any ProcessRunner
        if let execution = view as? FlutterAndroidExecution {
            host = try FlutterAndroidHostGuard(base: runner, execution: execution)
        } else {
            // Only internal caller fixtures supply another view implementation.
            host = runner
        }
        let observed = await ProjectExecutionEnvironment.resolve(anchor: anchor,
            hostRunner: FlutterChildRunner(base: host, environment: environment))
        let tools: ToolPreparation
        if let existingTools { tools = existingTools }
        else {
            let requirements = try await ToolRequirements.resolve(anchor: anchor, platforms: [.android], runner: observed.runner)
            tools = try await ToolPreparation.inspect(requirements: requirements, directory: anchor.directory,
                environment: input.environment, runner: host, currentToolRunner: observed.runner, planInstallations: false)
        }
        guard tools.checks.contains(where: { $0.id == "tools.java" && $0.kind == "reuse" }),
              !tools.checks.contains(where: { $0.id == "tools.java" && $0.kind != "reuse" }),
              tools.activeTools["java"] != nil else { throw failure() }
        let selected = observed.activatingTools(tools.activeTools, environment: input.environment)
        // This is outside mise/tool activation, so it sees the original ./gradlew request.
        let projectRunner: any ProcessRunner
        if let execution = view as? FlutterAndroidExecution, let java = tools.activeTools["java"] {
            var childEnvironment = environment
            childEnvironment["JAVA_HOME"] = java.deletingLastPathComponent().deletingLastPathComponent().path
            childEnvironment["PATH"] = java.deletingLastPathComponent().path + ":"
                + (environment["PATH"] ?? input.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
            childEnvironment["MISE_AUTO_INSTALL"] = "false"
            projectRunner = execution.runner(base: selected.runner, childRunner: runner, childEnvironment: childEnvironment)
        } else {
            projectRunner = view.runner(base: selected.runner)
        }
        return Self(projectEnvironment: selected, projectRunner: projectRunner,
                    workspace: workspace, entrypoint: inputs.entrypoint)
    }

    static func failure() -> DomainError {
        DomainError(summary: "Flutter Android needs prepared inputs, an existing exact JDK and a supported protected SDK view.",
            remediation: Remediation(summary:
                "Inspect mobile setup with the same app and entrypoint. Preserve source, lockfiles and the selected SDK. No tool installation or Gradle execution occurred."))
    }

    static func blockedStep(app: URL) -> PreparationStep {
        PreparationStep(id: "android.flutter.execution", platform: .android, kind: "provider", target: app.path,
            observed: "A protected Flutter Android execution view is not ready",
            required: "Prepared workspace inputs, an existing exact JDK and a supported SDK capability",
            source: CheckSource(tier: 1, origin: "Flutter Android preparation"), command: nil,
            remediation: failure().remediation)
    }
}

/// This final host boundary also encloses mise itself and activation-only checks.
struct FlutterAndroidHostGuard: ProcessRunner {
    let base: any ProcessRunner
    let policy: URL
    let check: @Sendable () throws -> Void
    let recordFailure: @Sendable (any Error, any Error) throws -> Void

    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        try check()
        let result: ProcessResult
        do {
            let wrapped = try FlutterAndroidExecution.policyCommand(command, file: policy)
            // Validation above and the view check bind this exact private policy.
            let alreadyOwned = command.executable == "/usr/bin/sandbox-exec" && command.arguments.count >= 3
                && command.arguments[0] == "-f" && command.arguments[1] == policy.path
            result = try await base.run(alreadyOwned ? command : wrapped, onLine: onLine)
        } catch {
            let primary = error
            do { try check() }
            catch is CancellationError {
                // An interrupted check is no evidence that protected inputs changed.
            }
            catch {
                do { try recordFailure(primary, error) }
                catch {
                    // Preserve timeout/cancellation/domain classification and avoid stdout/NDJSON corruption.
                    Logger(subsystem: "dev.runstir", category: "flutter-protection").fault(
                        "Flutter input protection failed after a project command error; the private receipt could not be written.")
                }
            }
            throw primary
        }
        try check()
        return result
    }

    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
        throw FlutterAndroidWorkflow.failure()
    }
}

extension FlutterAndroidHostGuard {
    /// Outside the private root, which is removed when its owner is released.
    static var receiptDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/dev.runstir/flutter-protection", isDirectory: true)
    }

    init(base: any ProcessRunner, execution: FlutterAndroidExecution,
         receipts: URL = FlutterAndroidHostGuard.receiptDirectory) throws {
        try execution.check()
        let root = execution.root
        self.base = base
        policy = root.appendingPathComponent("parent.sb")
        check = { try execution.check() }
        recordFailure = { try Self.writeReceipt(primary: $0, protection: $1, root: root, to: receipts) }
    }

    static func writeReceipt(primary: any Error, protection: any Error, root: URL, to receipts: URL) throws {
        try FileManager.default.createDirectory(at: receipts, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let receipt = try JSONSerialization.data(withJSONObject: ["schema": 1,
            "kind": "project-command-and-protection-failure", "root": root.path,
            "primary": String(describing: primary), "protection": String(describing: protection)], options: [.sortedKeys])
        try FlutterAndroidExecution.write(receipt, to: receipts.appendingPathComponent("protection-failure-\(UUID().uuidString).json"))
    }
}

/// A missed composition path must never fall back to an unprotected Gradle runner.
struct FlutterAndroidReadinessCheck: Check, ProcessRunner {
    let id = "android.flutter.execution"
    let category = "Flutter Android"
    let title = "Prepared protected Flutter Android execution"
    func run() async throws -> CheckOutcome {
        .error(observed: "A protected Flutter Android execution view is not ready",
            source: CheckSource(tier: 1, origin: "Flutter Android preparation"),
            remediation: FlutterAndroidWorkflow.failure().remediation)
    }
    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        throw FlutterAndroidWorkflow.failure()
    }
    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
        throw FlutterAndroidWorkflow.failure()
    }
}

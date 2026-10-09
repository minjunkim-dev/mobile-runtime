import AndroidKit
import Core
import Foundation
import SimulatorKit

/// What every command stands on: one logging bootstrap, one anchor detection, one
/// set of Checks. `build` and `up` reusing this is what keeps either from calling a
/// project broken that `doctor` just called fine — they read it the same way.
public struct WorkflowContext: Sendable {
    /// nil outside a React Native project. What that means is the command's call:
    /// doctor says so and carries on with host checks; build and up have nothing to do.
    public let anchor: ProjectAnchor?
    public let engine: DoctorEngine
    /// What the Stages need and the Checks already had: workflows read the same
    /// mobile.yml, through the same runner, against the same Xcode.
    public let config: ConfigContext
    public let lookup: MatrixLookup?
    /// Machine commands: Xcode discovery, simulator control, install, launch, down.
    public let runner: any ProcessRunner
    /// Project commands: version checks now; dependencies, Metro and build in #72.
    public let projectRunner: any ProcessRunner
    public let locator: XcodeLocator

    public static func make(
        input: ProjectInspectionInput,
        platform: ProjectPlatform,
        anchor: ProjectAnchor?,
        runner: any ProcessRunner,
        includeProjectEnvironment: Bool = true,
        includeRuntimeSDKTools: Bool = true
    ) async -> WorkflowContext {
        let locator = XcodeLocator(runner: runner, developerDirOverride: input.environment["DEVELOPER_DIR"])
        let workingDirectory = input.directory.standardizedFileURL.resolvingSymlinksInPath()
        // mobile.yml is read before the matrix: its overrides are part of what the
        // Tier 2 checks compare against.
        let config = ConfigContext.detect(anchor: anchor, workingDirectory: workingDirectory)
        let lookup = anchor.map { MatrixLookup.resolve(anchor: $0, config: config.configuration) }
        let projectEnvironment: ProjectExecutionEnvironment?
        if includeProjectEnvironment, let anchor {
            projectEnvironment = await ProjectExecutionEnvironment.resolve(
                anchor: anchor, hostRunner: runner
            )
        } else {
            projectEnvironment = nil
        }
        var paths = [workingDirectory, FileManager.default.temporaryDirectory]
        if let anchor {
            paths.append(anchor.directory)
            if let root = anchor.workspaceRoot { paths.append(root.directory) }
        }
        let environment = input.environment
        var unresolvedCache: String?
        if let anchor, let projectEnvironment, anchor.packageManagerName == "npm" {
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
            WorkspaceAccessCheck(paths: uniquePaths, unresolvedCache: unresolvedCache), WorkspaceStorageCheck(paths: uniquePaths)
        ]
        let checks: [any Check]
        switch platform {
        case .ios:
            let projectChecks = if let anchor, let projectEnvironment {
                projectEnvironment.checks(anchor: anchor, context: config)
            } else {
                [any Check]()
            }
            checks = workspaceChecks + iOSChecks(lookup: lookup, runner: runner, locator: locator)
                + configChecks(context: config, lookup: lookup, runner: runner, locator: locator)
                + projectChecks
        case .android:
            var android = config.checks()
            if let anchor, let projectEnvironment {
                let platformChecks = androidChecks(
                    anchor: anchor,
                    config: config,
                    hostRunner: runner,
                    projectRunner: projectEnvironment.runner,
                    environment: AndroidEnvironment(values: input.environment),
                    includeRuntimeSDKTools: includeRuntimeSDKTools
                )
                // The project identity is the first Android fact; the shared tool
                // environment and Node checks follow before Gradle requirements.
                android.append(platformChecks[0])
                android.append(contentsOf: projectEnvironment.commonChecks(anchor: anchor, context: config))
                android.append(contentsOf: platformChecks.dropFirst())
            }
            checks = workspaceChecks + android
        }

        return WorkflowContext(
            anchor: anchor,
            engine: DoctorEngine(checks: checks),
            config: config,
            lookup: lookup,
            runner: runner,
            projectRunner: projectEnvironment?.runner ?? runner,
            locator: locator
        )
    }
}

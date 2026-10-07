import AndroidKit
import Core
import Foundation
import Logging
import SimulatorKit

/// What every command stands on: one logging bootstrap, one anchor detection, one
/// set of Checks. `build` and `up` reusing this is what keeps either from calling a
/// project broken that `doctor` just called fine — they read it the same way.
struct Wiring {
    /// nil outside a React Native project. What that means is the command's call:
    /// doctor says so and carries on with host checks; build and up have nothing to do.
    let anchor: ProjectAnchor?
    let engine: DoctorEngine
    /// What the Stages need and the Checks already had: workflows read the same
    /// mobile.yml, through the same runner, against the same Xcode.
    let config: ConfigContext
    let lookup: MatrixLookup?
    /// Machine commands: Xcode discovery, simulator control, install, launch, down.
    let runner: any ProcessRunner
    /// Project commands: version checks now; dependencies, Metro and build in #72.
    let projectRunner: any ProcessRunner
    let locator: XcodeLocator

    static func bootstrap(
        verbose: Bool,
        platform: MobilePlatform = .ios,
        includeProjectEnvironment: Bool = true,
        includeRuntimeSDKTools: Bool = true
    ) async -> Wiring {
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardError(label: label)
            handler.logLevel = verbose ? .debug : .info
            return handler
        }

        let runner = SystemProcessRunner(logger: Logger(label: "mobile.process"))
        let locator = XcodeLocator(runner: runner)

        let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let anchor = ProjectAnchor.detect(from: workingDirectory)
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
        let environment = ProcessInfo.processInfo.environment
        if let anchor, anchor.workspaceRoot?.packageManagerName == "npm" || anchor.packageManager?.name == "npm" {
            paths.append(environment["npm_config_cache"].map { URL(fileURLWithPath: $0) }
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".npm"))
        }
        if platform == .android {
            let gradle = environment["GRADLE_USER_HOME"].map { URL(fileURLWithPath: $0) }
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gradle")
            paths.append(gradle)
        }
        var uniquePaths: [URL] = []
        for path in paths where !uniquePaths.contains(path.standardizedFileURL) {
            uniquePaths.append(path.standardizedFileURL)
        }
        let workspaceChecks: [any Check] = [
            WorkspaceAccessCheck(paths: uniquePaths), WorkspaceStorageCheck(paths: uniquePaths)
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

        return Wiring(
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

func writeError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

enum Terminal {
    /// isatty + NO_COLOR. No flag to remember.
    static var supportsColor: Bool {
        guard ProcessInfo.processInfo.environment["NO_COLOR"] == nil else { return false }
        return isatty(FileHandle.standardOutput.fileDescriptor) == 1
    }
}

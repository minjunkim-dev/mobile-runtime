import Core
import Foundation
import Logging
import SimulatorKit

/// What every command stands on: one logging bootstrap, one anchor detection, one
/// set of Checks. `up` reusing this is what keeps it from calling a project broken
/// that `doctor` just called fine — the two read the same project the same way.
struct Wiring {
    /// nil outside a React Native project. What that means is the command's call:
    /// doctor says so and carries on with host checks, up has nothing to do.
    let anchor: ProjectAnchor?
    let engine: DoctorEngine

    static func bootstrap(verbose: Bool) -> Wiring {
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

        return Wiring(
            anchor: anchor,
            engine: DoctorEngine(
                checks: iOSChecks(lookup: lookup, runner: runner, locator: locator)
                    + configChecks(context: config, lookup: lookup, runner: runner, locator: locator)
                    + (anchor?.checks(runner: runner) ?? [])
            )
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

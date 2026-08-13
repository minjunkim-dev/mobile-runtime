import ArgumentParser
import Core
import Foundation
import Logging
import SimulatorKit

enum Tool {
    static let version = "0.1.0"
}

@main
struct Mobile: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mobile",
        abstract: "Reproducible mobile development runtime.",
        version: Tool.version,
        subcommands: [Doctor.self]
    )

    // Bare `mobile` is exploration, not an error: help on stdout, exit 0.
    func run() throws {
        print(Mobile.helpMessage())
    }
}

struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check whether this machine can build and run the project."
    )

    @Flag(name: .long, help: "Emit a JSON document on stdout. Logs and notes stay on stderr.")
    var json = false

    @Flag(name: [.short, .long], help: "Show observed values, requirements and sources.")
    var verbose = false

    func run() async throws {
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardError(label: label)
            handler.logLevel = verbose ? .debug : .info
            return handler
        }

        let runner = SystemProcessRunner(logger: Logger(label: "mobile.process"))
        let locator = XcodeLocator(runner: runner)
        let engine = DoctorEngine(checks: [
            XcodeInstalledCheck(locator: locator),
            SimulatorDaemonCheck(runner: runner, locator: locator),
        ])

        // Project detection lands with the project checks; until then every run is host-only.
        writeError("note: no project detected — host checks only")

        let report = await engine.run()
        for failure in report.toolFailures { writeError("tool failure: \(failure)") }

        if json {
            print(try DoctorJSONDocument(report: report, toolVersion: Tool.version).encoded())
        } else {
            let renderer = HumanReportRenderer(useColor: Terminal.supportsColor, verbose: verbose)
            print(renderer.render(report))
        }

        // 64 (usage) comes from ArgumentParser; the rest is the report's verdict.
        if report.exitCode != 0 { throw ExitCode(report.exitCode) }
    }

    private func writeError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}

enum Terminal {
    /// isatty + NO_COLOR. No flag to remember.
    static var supportsColor: Bool {
        guard ProcessInfo.processInfo.environment["NO_COLOR"] == nil else { return false }
        return isatty(FileHandle.standardOutput.fileDescriptor) == 1
    }
}

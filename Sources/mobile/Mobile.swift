import ArgumentParser
import Core
import Foundation

enum MobilePlatform: String, ExpressibleByArgument, Sendable {
    case ios
    case android
}

enum Tool {
    static let version = "0.1.0"
}

@main
struct Mobile: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mobile",
        abstract: "Reproducible mobile development runtime.",
        version: Tool.version,
        subcommands: [Doctor.self, Build.self, Up.self, Down.self]
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

    @Option(name: .long, help: "Platform to diagnose: ios or android.")
    var platform: MobilePlatform = .ios

    func run() async throws {
        let wiring = await Wiring.bootstrap(verbose: verbose, platform: platform)

        // Standing outside a project is a legitimate use — a new machine has nothing
        // cloned yet — so it is a note, never an error.
        if wiring.anchor == nil { writeError("note: no project detected — host checks only") }

        let report = await wiring.engine.run()
        for failure in report.toolFailures { writeError("tool failure: \(failure)") }

        if json {
            print(
                try DoctorJSONDocument(
                    report: report,
                    toolVersion: Tool.version,
                    platform: platform == .android ? platform.rawValue : nil
                ).encoded()
            )
        } else {
            let renderer = HumanReportRenderer(useColor: Terminal.supportsColor, verbose: verbose)
            print(renderer.render(report))
        }

        // 64 (usage) comes from ArgumentParser; the rest is the report's verdict.
        if report.exitCode != 0 { throw ExitCode(report.exitCode) }
    }
}

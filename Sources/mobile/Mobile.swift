import ArgumentParser
import Core
import EnvironmentKit
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
    var platform: MobilePlatform?

    @Option(name: .long, help: "Project folder. Defaults to the current working directory.")
    var project: String?

    @Option(name: .long, help: "React Native app candidate id reported by doctor.")
    var app: String?

    @Flag(name: .long, help: "Do not ask for input. Missing selections are returned as candidates.")
    var nonInteractive = false

    func run() async throws {
        bootstrapLogging(verbose: verbose)
        let environment = ProcessInfo.processInfo.environment
        let input = ProjectInspectionInput(
            directory: URL(fileURLWithPath: project ?? FileManager.default.currentDirectoryPath),
            environment: environment, app: app,
            platform: platform.flatMap { ProjectPlatform(rawValue: $0.rawValue) }
        )
        let result: EnvironmentInspection
        do {
            result = try await EnvironmentInspection.run(input: input)
        } catch {
            throw ValidationError("Cannot inspect project folder: \(error.localizedDescription)")
        }

        // Standing outside a project is a legitimate use — a new machine has nothing
        // cloned yet — so it is a note, never an error.
        if result.selection.candidates.isEmpty { writeError("note: no project detected — host checks only") }
        if let error = result.selection.error { writeError(error) }
        for candidate in result.selection.candidates where !result.selection.requiredInput.isEmpty {
            writeError("candidate: \(candidate.id) — \(candidate.platforms.map(\.rawValue).joined(separator: ", "))")
        }
        if !result.selection.requiredInput.isEmpty {
            writeError("selection required: \(result.selection.requiredInput.joined(separator: ", "))")
        }

        let report = result.report
        for failure in report.toolFailures { writeError("tool failure: \(failure)") }

        if json {
            print(
                try result.document(toolVersion: Tool.version).encoded()
            )
        } else {
            let renderer = HumanReportRenderer(useColor: Terminal.supportsColor, verbose: verbose)
            print(renderer.render(report))
        }

        // 64 (usage) comes from ArgumentParser; the rest is the report's verdict.
        if result.exitCode != 0 { throw ExitCode(result.exitCode) }
    }
}

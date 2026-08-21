import ArgumentParser
import Core
import Foundation
import SimulatorKit

struct Up: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Get the project running on a simulator, checking the environment first."
    )

    @Flag(name: .long, help: "Emit a JSON document on stdout. Progress stays on stderr.")
    var json = false

    @Flag(name: [.short, .long], help: "Show the underlying tool invocations.")
    var verbose = false

    func run() async throws {
        let wiring = await Wiring.bootstrap(verbose: verbose)
        let writer = UpWriter(
            json: json,
            toolVersion: Tool.version,
            command: "up",
            renderer: HumanReportRenderer(useColor: Terminal.supportsColor, verbose: verbose),
            standardOutput: { print($0) },
            standardError: { writeError($0) }
        )

        let report = await runIOSPipeline(.up, wiring: wiring, writer: writer)
        try writer.finish(report)

        // 64 (usage) comes from ArgumentParser; the rest is the report's verdict.
        if report.exitCode != 0 { throw ExitCode(report.exitCode) }
    }
}

func runIOSPipeline(
    _ workflow: IOSWorkflow, wiring: Wiring, writer: UpWriter
) async -> UpReport {
    // Unlike doctor, build and up need a project: there is nothing to compile outside one.
    guard let anchor = wiring.anchor else {
        return UpReport(stages: [], failure: .domain(noProject))
    }

    let stages = iOSStages(
        workflow: workflow,
        anchor: anchor,
        doctor: wiring.engine,
        config: wiring.config,
        lookup: wiring.lookup,
        hostRunner: wiring.runner,
        projectRunner: wiring.projectRunner,
        locator: wiring.locator,
        note: { writer.note($0) }
    )
    return await UpPipeline(stages: stages).run { writer.progress($0) }
}

private let noProject = DomainError(
    summary: "no React Native project here",
    remediation: Remediation(
        summary: "Run this command from a React Native project directory — the one whose "
            + "package.json depends on react-native."
    )
)

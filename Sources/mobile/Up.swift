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
            renderer: HumanReportRenderer(useColor: Terminal.supportsColor, verbose: verbose),
            standardOutput: { print($0) },
            standardError: { writeError($0) }
        )

        let report = await runPipeline(wiring, writer)
        try writer.finish(report)

        // 64 (usage) comes from ArgumentParser; the rest is the report's verdict.
        if report.exitCode != 0 { throw ExitCode(report.exitCode) }
    }

    private func runPipeline(_ wiring: Wiring, _ writer: UpWriter) async -> UpReport {
        // Unlike doctor, up outside a project is an error: there is nothing to build.
        guard let anchor = wiring.anchor else {
            return UpReport(stages: [], failure: .domain(Self.noProject))
        }

        let stages = iOSUpStages(
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

    private static let noProject = DomainError(
        summary: "no React Native project here",
        remediation: Remediation(
            summary: "Run up from a React Native project directory — the one whose "
                + "package.json depends on react-native."
        )
    )
}

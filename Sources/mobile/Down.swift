import ArgumentParser
import Core
import Foundation
import SimulatorKit

struct Down: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Stop this project's Metro and the app it installed. Leaves the simulator running."
    )

    @Flag(name: .long, help: "Emit a JSON document on stdout. Everything else stays on stderr.")
    var json = false

    @Flag(name: [.short, .long], help: "Show the underlying tool invocations.")
    var verbose = false

    func run() async throws {
        let wiring = Wiring.bootstrap(verbose: verbose)
        let writer = DownWriter(
            json: json,
            toolVersion: Tool.version,
            renderer: HumanReportRenderer(useColor: Terminal.supportsColor, verbose: verbose),
            standardOutput: { print($0) },
            standardError: { writeError($0) }
        )

        let report = await teardown(wiring)
        try writer.finish(report)

        // 64 (usage) comes from ArgumentParser; the rest is the report's verdict.
        if report.exitCode != 0 { throw ExitCode(report.exitCode) }
    }

    private func teardown(_ wiring: Wiring) async -> TeardownReport {
        // Like up, down needs a project: the Metro verdict compares against the
        // anchor, and the install record is found by the project's path.
        guard let anchor = wiring.anchor else {
            return TeardownReport(items: [], failure: Self.noProject)
        }

        return await iOSTeardown(anchor: anchor, runner: wiring.runner, locator: wiring.locator).run()
    }

    private static let noProject = DomainError(
        summary: "no React Native project here",
        remediation: Remediation(
            summary: "Run down from the project directory whose Metro and app you want stopped — "
                + "the one whose package.json depends on react-native."
        )
    )
}

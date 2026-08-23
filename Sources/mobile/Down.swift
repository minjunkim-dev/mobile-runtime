import ArgumentParser
import AndroidKit
import Core
import Foundation
import SimulatorKit

struct Down: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Stop runtime resources owned by this project's selected platform."
    )

    @Flag(name: .long, help: "Emit a JSON document on stdout. Everything else stays on stderr.")
    var json = false

    @Flag(name: [.short, .long], help: "Show the underlying tool invocations.")
    var verbose = false

    @Option(name: .long, help: "Platform to stop: ios or android.")
    var platform: MobilePlatform = .ios

    func run() async throws {
        // Teardown uses only host capabilities. Resolving a project toolchain here
        // would make the recovery command wait on or fail with an unrelated Git probe.
        let wiring = await Wiring.bootstrap(
            verbose: verbose,
            platform: platform,
            includeProjectEnvironment: false
        )
        let writer = DownWriter(
            json: json,
            toolVersion: Tool.version,
            platform: platform == .android ? platform.rawValue : nil,
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

        switch platform {
        case .ios:
            return await iOSTeardown(
                anchor: anchor, runner: wiring.runner, locator: wiring.locator
            ).run()
        case .android:
            return await androidTeardown(
                anchor: anchor,
                config: wiring.config,
                runner: wiring.runner,
                projectRunner: wiring.projectRunner
            )
        }
    }

    private static let noProject = DomainError(
        summary: "no React Native project here",
        remediation: Remediation(
            summary: "Run down from the project directory whose Metro and app you want stopped — "
                + "the one whose package.json depends on react-native."
        )
    )
}

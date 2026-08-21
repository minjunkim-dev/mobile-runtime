import ArgumentParser
import Core

struct Build: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Build the project for a simulator without installing or launching it."
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
            command: "build",
            renderer: HumanReportRenderer(useColor: Terminal.supportsColor, verbose: verbose),
            standardOutput: { print($0) },
            standardError: { writeError($0) }
        )

        let report = await runIOSPipeline(.build, wiring: wiring, writer: writer)
        try writer.finish(report)

        if report.exitCode != 0 { throw ExitCode(report.exitCode) }
    }
}

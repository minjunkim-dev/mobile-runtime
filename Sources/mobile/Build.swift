import ArgumentParser
import AndroidKit
import Core

struct Build: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Build the project without installing or launching it."
    )

    @Flag(name: .long, help: "Emit a JSON document on stdout. Progress stays on stderr.")
    var json = false

    @Flag(name: [.short, .long], help: "Show the underlying tool invocations.")
    var verbose = false

    @Option(name: .long, help: "Platform to build: ios or android.")
    var platform: MobilePlatform = .ios

    func run() async throws {
        let wiring = await Wiring.bootstrap(
            verbose: verbose,
            platform: platform,
            includeRuntimeSDKTools: platform != .android
        )
        let writer = UpWriter(
            json: json,
            toolVersion: Tool.version,
            command: "build",
            platform: platform == .android ? platform.rawValue : nil,
            renderer: HumanReportRenderer(useColor: Terminal.supportsColor, verbose: verbose),
            standardOutput: { print($0) },
            standardError: { writeError($0) }
        )

        let report = switch platform {
        case .ios: await runIOSPipeline(.build, wiring: wiring, writer: writer)
        case .android: await runAndroidBuildPipeline(wiring: wiring, writer: writer)
        }
        try writer.finish(report)

        if report.exitCode != 0 { throw ExitCode(report.exitCode) }
    }
}

private func runAndroidBuildPipeline(wiring: Wiring, writer: UpWriter) async -> UpReport {
    guard let anchor = wiring.anchor else {
        return UpReport(stages: [], failure: .domain(noAndroidProject))
    }
    let stages = androidBuildStages(
        anchor: anchor,
        doctor: wiring.engine,
        config: wiring.config,
        hostRunner: wiring.runner,
        projectRunner: wiring.projectRunner,
        note: { writer.note($0) }
    )
    return await UpPipeline(stages: stages).run { writer.progress($0) }
}

private let noAndroidProject = DomainError(
    summary: "no React Native project here",
    remediation: Remediation(
        summary: "Run this command from a React Native project with a checked-in android directory."
    )
)

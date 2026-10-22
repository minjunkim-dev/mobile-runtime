import ArgumentParser
import Core
import Dispatch
import EnvironmentKit
import Foundation
import Logging

struct AppCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "app",
        abstract: "Inspect or directly install one Simulator .app, Development/Ad Hoc iOS device .app or .ipa, or Emulator APK without source.",
        subcommands: [AppInspect.self, AppRun.self])
}

struct AppInspect: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "inspect", abstract: "Inspect app bytes, devices and physical iOS conditions. Never installs or launches.")
    @OptionGroup var options: AppFileOptions

    func run() async throws { try await options.execute(inspectOnly: true) }
}

struct AppRun: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "run", abstract: "Approve the current file/device/replacement plan, install preserving data, and request launch.")
    @OptionGroup var options: AppFileOptions
    @Flag(name: .long, help: "Return the exact change plan without installing.") var plan = false
    @Option(name: .long, help: "Approve exactly the current plan-id. Older or unorderable builds require the displayed DOWNGRADE risk acknowledgement.") var approve: String?

    mutating func validate() throws {
        if plan && approve != nil { throw ValidationError("--plan and --approve cannot be combined.") }
    }

    func run() async throws { try await options.execute(planOnly: plan, approvedPlanID: approve) }
}

struct AppFileOptions: ParsableArguments {
    @Argument(help: "Path to an iOS Simulator or Development/Ad Hoc device .app directory, a Development/Ad Hoc .ipa, or one Android .apk file.") var file: String
    @Option(name: .long, help: "A current Simulator UDID, physical iOS device UDID or avd:<name>. The target never switches automatically.") var device: String?
    @Option(name: .long, help: "ios or android. Omit to use the inspected file's platform; an explicit mismatch is rejected.") var platform: MobilePlatform?
    @Flag(name: .long, help: "Never prompt. Installation requires exact --approve input.") var nonInteractive = false
    @Flag(name: .long, help: "Emit one versioned JSON document. Implies non-interactive input.") var json = false
    @Flag(name: .long, help: "Emit versioned NDJSON progress on stderr.") var progressJson = false
    @Flag(name: [.short, .long], help: "Show underlying platform tool invocations.") var verbose = false

    func execute(inspectOnly: Bool = false, planOnly: Bool = false, approvedPlanID: String? = nil) async throws {
        let silent = progressJson
        let logLevel: Logger.Level = verbose ? .debug : .info
        LoggingSystem.bootstrap { label in
            if silent { return SwiftLogNoOpLogHandler() }
            var handler = StreamLogHandler(label: label, stream: AppFileLogStream())
            handler.logLevel = logLevel
            return handler
        }
        let input = AppFileInput(file: URL(fileURLWithPath: file), environment: ProcessInfo.processInfo.environment,
            device: device, platform: platform.flatMap { ProjectPlatform(rawValue: $0.rawValue) })
        var approval = approvedPlanID
        if !inspectOnly, !planOnly, approval == nil, !nonInteractive, !json, !progressJson,
           isatty(FileHandle.standardInput.fileDescriptor) == 1 {
            let proposed = await AppFileExecution.run(input: input, planOnly: true)
            render(proposed)
            if let plan = proposed.operation.plan {
                writeError("Type the exact approval shown below, or press Return to stop. The file, target and installed state will be rechecked:")
                writeError(plan.approval)
                let answer = readLine()
                if answer == plan.approval { approval = answer }
            }
        }
        let exactApproval = approval
        let structured = progressJson
        let result = try await cancellingOnSignals {
            await AppFileExecution.run(input: input, inspectOnly: inspectOnly, planOnly: planOnly,
                approvedPlanID: exactApproval) { event in
                    if structured {
                        if let line = try? event.encoded() { writeError(line) }
                    } else {
                        writeError(AppFileHumanOutput.progress(event))
                    }
                }
        }
        if json { print(try result.encoded(toolVersion: Tool.version)) }
        else { render(result) }
        if result.exitCode != 0 { throw ExitCode(result.exitCode) }
    }

    private func render(_ result: AppFileResult) {
        let lines = AppFileHumanOutput.lines(result)
        lines.output.forEach { print($0) }
        lines.errors.forEach { writeError($0) }
    }
}

import ArgumentParser
import Core
import Dispatch
import EnvironmentKit
import Foundation

struct AppCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "app",
        abstract: "Inspect or directly install one Simulator .app or Emulator APK without source.",
        subcommands: [AppInspect.self, AppRun.self])
}

struct AppInspect: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "inspect", abstract: "Inspect app bytes and virtual devices. Never installs or launches.")
    @OptionGroup var options: AppFileOptions

    func run() async throws { try await options.execute(inspectOnly: true) }
}

struct AppRun: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "run", abstract: "Approve the current file/device/replacement plan, install preserving data, and request launch.")
    @OptionGroup var options: AppFileOptions
    @Flag(name: .long, help: "Return the exact change plan without installing.") var plan = false
    @Option(name: .long, help: "Approve exactly the current plan-id. Older builds require the displayed DOWNGRADE acknowledgement.") var approve: String?

    mutating func validate() throws {
        if plan && approve != nil { throw ValidationError("--plan and --approve cannot be combined.") }
    }

    func run() async throws { try await options.execute(planOnly: plan, approvedPlanID: approve) }
}

struct AppFileOptions: ParsableArguments {
    @Argument(help: "Path to an iOS Simulator .app directory or one Android .apk file.") var file: String
    @Option(name: .long, help: "A current Simulator UDID or avd:<name>. The target never switches automatically.") var device: String?
    @Flag(name: .long, help: "Never prompt. Installation requires exact --approve input.") var nonInteractive = false
    @Flag(name: .long, help: "Emit one versioned JSON document. Implies non-interactive input.") var json = false
    @Flag(name: .long, help: "Emit versioned NDJSON progress on stderr.") var progressJson = false
    @Flag(name: [.short, .long], help: "Show underlying platform tool invocations.") var verbose = false

    func execute(inspectOnly: Bool = false, planOnly: Bool = false, approvedPlanID: String? = nil) async throws {
        bootstrapLogging(verbose: verbose, silent: progressJson)
        let input = AppFileInput(file: URL(fileURLWithPath: file), environment: ProcessInfo.processInfo.environment, device: device)
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
        let task = Task {
            await AppFileExecution.run(input: input, inspectOnly: inspectOnly, planOnly: planOnly,
                approvedPlanID: exactApproval) { event in
                    if structured {
                        if let line = try? event.encoded() { writeError(line) }
                    } else {
                        writeError("\(event.stageId ?? event.kind): \(event.state)\(event.detail.map { " — \($0)" } ?? "")")
                    }
                }
        }
        let previousInterrupt = signal(SIGINT, SIG_IGN)
        let previousTerminate = signal(SIGTERM, SIG_IGN)
        let signals = [SIGINT, SIGTERM].map { number in
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler { task.cancel() }
            source.resume()
            return source
        }
        defer {
            signals.forEach { $0.cancel() }
            signal(SIGINT, previousInterrupt)
            signal(SIGTERM, previousTerminate)
        }
        let result = await task.value
        if json { print(try result.encoded(toolVersion: Tool.version)) }
        else { render(result) }
        if result.exitCode != 0 { throw ExitCode(result.exitCode) }
    }

    private func render(_ result: AppFileResult) {
        let operation = result.operation
        print("\(operation.command): \(operation.state)")
        if let artifact = operation.artifact {
            print("file: \(artifact.file.path)")
            print("origin: \(artifact.origin) — producer trust and safety are unverified")
            print("\(artifact.contentIdentityAlgorithm): \(artifact.contentIdentity)")
            print("\(artifact.metadata.platform.rawValue): \(artifact.metadata.appID), version \(artifact.metadata.version ?? "unknown"), build \(artifact.metadata.build)")
            print("architecture: \(artifact.metadata.architectures.joined(separator: ", ")); minimum OS: \(artifact.metadata.minimumOS)")
            print(artifact.metadata.signatureCondition)
            if let signer = artifact.metadata.signingIdentity { print("signer SHA-256: \(signer)") }
        }
        for device in operation.devices {
            print("device: \(device.id) — \(device.name), OS \(device.os), \(device.architectures.joined(separator: ", ")), \(device.ready ? "ready" : "manual preparation required")")
        }
        if let plan = operation.plan {
            print("plan-id: \(plan.id)")
            print("target: \(plan.device.id); installed: \(plan.installed.state), version \(plan.installed.version ?? "unknown"), build \(plan.installed.build ?? "unknown")")
            plan.warnings.forEach { writeError($0) }
            print("approval: \(plan.approval)")
        }
        print("installation: \(operation.installation); launch request: \(operation.launch); running: \(operation.running); first screen: \(operation.firstScreen)")
        print("external server: \(operation.externalServer)")
        if let error = operation.error { writeError(error) }
        if let next = operation.nextAction { print(next) }
    }
}

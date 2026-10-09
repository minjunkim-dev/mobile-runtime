import ArgumentParser
import Core
import Dispatch
import EnvironmentKit
import Foundation

struct WorkflowOptions: ParsableArguments {
    @Flag(name: .long, help: "Emit one final JSON document on stdout.") var json = false
    @Flag(name: .long, help: "Emit versioned NDJSON progress on stderr.") var progressJson = false
    @Flag(name: [.short, .long], help: "Show the underlying tool invocations.") var verbose = false
    @Option(name: .long, help: "Project folder. Defaults to the current working directory.") var project: String?
    @Option(name: .long, help: "React Native app candidate id.") var app: String?
    @Option(name: .long, help: "ios or android. Required for dual-platform apps; no implicit iOS default.") var platform: MobilePlatform?
    @Option(name: .long, help: "Simulator UDID or avd:<name>. Omit for build or down.") var device: String?
    @Option(name: .long, help: "iOS scheme. Defaults to mobile.yml or the only app scheme.") var scheme: String?
    @Option(name: .long, help: "iOS build configuration. Defaults to Debug only when it exists.") var configuration: String?
    @Option(name: .long, help: "Android application module. Defaults to mobile.yml or the only module.") var module: String?
    @Option(name: .long, help: "Android debuggable variant. Defaults to mobile.yml, debug, or the only variant.") var variant: String?
    @Flag(name: .long, help: "Do not ask questions. Missing selections return candidates without starting changes.") var nonInteractive = false

    func run(_ kind: WorkflowKind) async throws {
        bootstrapLogging(verbose: verbose, silent: progressJson)
        let input = WorkflowInput(project: ProjectInspectionInput(
            directory: URL(fileURLWithPath: project ?? FileManager.default.currentDirectoryPath),
            environment: ProcessInfo.processInfo.environment, app: app,
            platform: platform.flatMap { ProjectPlatform(rawValue: $0.rawValue) }),
            device: device, scheme: scheme, configuration: configuration, module: module, variant: variant)
        let structured = progressJson
        let task = Task {
            await WorkflowExecution.run(kind, input: input) { event in
                if structured {
                    if let line = try? event.encoded() { writeError(line) }
                } else if let stage = event.stageId {
                    writeError("\(stage): \(event.state)\(event.detail.map { " — \($0)" } ?? "")")
                } else if let detail = event.detail {
                    writeError(detail)
                }
            }
        }
        let oldInterrupt = signal(SIGINT, SIG_IGN)
        let oldTerminate = signal(SIGTERM, SIG_IGN)
        let signals = [SIGINT, SIGTERM].map { number in
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler { task.cancel() }
            source.resume()
            return source
        }
        defer {
            for source in signals { source.cancel() }
            signal(SIGINT, oldInterrupt)
            signal(SIGTERM, oldTerminate)
        }
        let result = await task.value
        if json {
            print(try result.encoded(toolVersion: Tool.version))
        } else if progressJson {
            print("\(kind.rawValue): \(result.operation.state)")
        } else {
            let renderer = HumanReportRenderer(useColor: Terminal.supportsColor, verbose: verbose)
            if let report = result.up {
                try UpWriter(json: false, toolVersion: Tool.version, command: kind.rawValue,
                             renderer: renderer, standardOutput: { print($0) }, standardError: { writeError($0) }).finish(report)
            }
            if let report = result.down {
                try DownWriter(json: false, toolVersion: Tool.version, renderer: renderer,
                               standardOutput: { print($0) }, standardError: { writeError($0) }).finish(report)
            }
            for candidate in result.operation.selection?.candidates ?? [] where result.operation.requiredInput.contains("--app") {
                writeError("app: \(candidate.id)")
            }
            for candidate in result.operation.devices { writeError("device: \(candidate.id) — \(candidate.name) / \(candidate.detail)") }
            if !result.operation.schemes.isEmpty { writeError("schemes: \(result.operation.schemes.joined(separator: ", "))") }
            if !result.operation.modules.isEmpty { writeError("modules: \(result.operation.modules.joined(separator: ", "))") }
            if !result.operation.variants.isEmpty { writeError("variants: \(result.operation.variants.joined(separator: ", "))") }
        }
        if result.exitCode != 0 { throw ExitCode(result.exitCode) }
    }
}

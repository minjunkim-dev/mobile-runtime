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
    @Option(name: .long, help: "Project app candidate id reported by doctor.") var app: String?
    @Option(name: .long, help: "ios or android. Required for dual-platform apps; no implicit iOS default.") var platform: MobilePlatform?
    @Option(name: .long, help: "Simulator UDID for iOS build/up, or avd:<name> for Android up. Omit for Android build and down.") var device: String?
    @Option(name: .long, help: "iOS scheme. Defaults to mobile.yml or the only app scheme.") var scheme: String?
    @Option(name: .long, help: "iOS build configuration. Defaults to Debug only when it exists.") var configuration: String?
    @Option(name: .long, help: "Android application module. Defaults to mobile.yml or the only module.") var module: String?
    @Option(name: .long, help: "Android debuggable variant. Defaults to mobile.yml, debug, or the only variant.") var variant: String?
    @Option(name: .long, help: "Flutter Dart entrypoint inside the selected app. Defaults to lib/main.dart.") var entrypoint: String?
    @Option(name: .long, help: "React Native build/up Metro port (default 8081), or Flutter up VM service port (automatic when omitted). Unsupported workflows stop before changes.") var port: Int?
    @Flag(name: .long, help: "Do not ask questions. Missing selections return candidates without starting changes.") var nonInteractive = false
    @Flag(name: .long, help: "React Native build/up에서 직접 준비한 의존성을 사용합니다. 재설치·lock 정렬 재검증을 생략하며 의존성 정합성은 사용자가 확인해야 합니다.") var preparedDependencies = false

    func run(_ kind: WorkflowKind) async throws {
        bootstrapLogging(verbose: verbose, silent: progressJson)
        let input = WorkflowInput(project: ProjectInspectionInput(
            directory: URL(fileURLWithPath: project ?? FileManager.default.currentDirectoryPath),
            environment: ProcessInfo.processInfo.environment, app: app,
            platform: platform.flatMap { ProjectPlatform(rawValue: $0.rawValue) }, entrypoint: entrypoint),
            device: device, scheme: scheme, configuration: configuration, module: module, variant: variant, port: port,
            preparedDependencies: preparedDependencies)
        let structured = progressJson
        let result = try await cancellingOnSignals {
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
        if json {
            print(try result.encoded(toolVersion: Tool.version))
        } else if progressJson {
            print("\(kind.rawValue): \(result.operation.state)")
        } else {
            let renderer = HumanReportRenderer(useColor: Terminal.supportsColor, verbose: verbose)
            if let uri = result.operation.developmentServiceURI { writeError("Flutter VM service: \(uri)") }
            if let report = result.up {
                UpWriter(command: kind.rawValue, renderer: renderer, standardError: { writeError($0) }).finish(report)
            }
            if let report = result.down {
                DownWriter(renderer: renderer, standardError: { writeError($0) }).finish(report)
            }
            for candidate in result.operation.selection?.candidates ?? [] where result.operation.requiredInput.contains("--app") {
                writeError("app: \(candidate.id)")
            }
            for candidate in result.operation.devices { writeError("device: \(candidate.id) — \(candidate.name) / \(candidate.detail)\(candidate.origin.map { " / " + $0.displayName } ?? "")\(candidate.avdDirectory.map { " / " + $0 } ?? "")") }
            if !result.operation.schemes.isEmpty { writeError("schemes: \(result.operation.schemes.joined(separator: ", "))") }
            if !result.operation.modules.isEmpty { writeError("modules: \(result.operation.modules.joined(separator: ", "))") }
            if !result.operation.variants.isEmpty { writeError("variants: \(result.operation.variants.joined(separator: ", "))") }
        }
        if result.exitCode != 0 { throw ExitCode(result.exitCode) }
    }
}

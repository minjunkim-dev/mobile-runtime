import ArgumentParser
import Core
import Dispatch
import EnvironmentKit
import Foundation

struct Setup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Inspect and approve environment preparation. Does not build or launch an app.")
    @Option(name: .long, help: "Project working folder.") var project: String?
    @Option(name: .long, help: "Detected app candidate id.") var app: String?
    @Option(name: .long, help: "Execution platform hint. RN and Flutter setup still cover both platforms.") var platform: MobilePlatform?
    @Flag(name: .long, help: "Inspect and return the change plan without making changes.") var plan = false
    @Option(name: .long, help: "Approve exactly the current plan-id. Conditions are rechecked before changes.") var approve: String?
    @Flag(name: .long, help: "Separately trust repository dependency scripts. Does not accept licenses or grant administrator permission.") var trustRepository = false
    @Flag(name: .long, help: "Never prompt. Requires an exact --approve plan-id to make changes.") var nonInteractive = false
    @Flag(name: .long, help: "Emit one final JSON document on stdout. Implies non-interactive input.") var json = false
    @Flag(name: .long, help: "Emit versioned NDJSON progress on stderr.") var progressJson = false
    @Flag(name: [.short, .long], help: "Show tool invocations.") var verbose = false

    mutating func validate() throws {
        if plan && approve != nil { throw ValidationError("--plan and --approve cannot be combined.") }
    }

    func run() async throws {
        bootstrapLogging(verbose: verbose, silent: progressJson)
        let input = ProjectInspectionInput(directory: URL(fileURLWithPath: project ?? FileManager.default.currentDirectoryPath),
            environment: ProcessInfo.processInfo.environment, app: app,
            platform: platform.flatMap { ProjectPlatform(rawValue: $0.rawValue) })
        var approved = approve
        var trusted = trustRepository
        if !plan, approved == nil, !nonInteractive, !json, !progressJson, isatty(FileHandle.standardInput.fileDescriptor) == 1 {
            let proposed = await PreparationExecution.run(input: input, planOnly: true)
            writeError(try proposed.encoded(toolVersion: Tool.version))
            if let id = proposed.plan?.id {
                writeError("Type this exact plan-id to approve, or press Return to stop: \(id)")
                if readLine() == id {
                    approved = id
                    if !trusted, proposed.plan?.steps.contains(where: { $0.kind == "align" }) == true {
                        writeError("Repository trust is separate. Inspect its scripts. Type TRUST to allow dependency scripts:")
                        trusted = readLine() == "TRUST"
                    }
                }
            }
        }
        let approvedID = approved
        let trust = trusted
        let structured = progressJson
        let task = Task {
            await PreparationExecution.run(input: input, planOnly: plan, approvedPlanID: approvedID, trustRepository: trust) { event in
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
        else {
            print("setup: \(result.operation.state)")
            if let plan = result.plan {
                print("plan-id: \(plan.id)")
                plan.inspectionLines.forEach { print($0) }
                for step in plan.steps {
                    print("\(step.id) [\(step.kind)] \(step.target)\(step.command.map { " — \($0)" } ?? "")")
                    if let advice = step.remediation { print(advice.summary) }
                }
                for platform in plan.platforms { print("\(platform.platform.rawValue): \(platform.state)") }
            }
            if let error = result.operation.error { writeError(error) }
            if let next = result.operation.nextAction { print(next) }
            for path in result.operation.changedFiles { print("changed file: \(path)") }
            if let log = result.operation.log { print("log: \(log)") }
        }
        if result.exitCode != 0 { throw ExitCode(result.exitCode) }
    }
}

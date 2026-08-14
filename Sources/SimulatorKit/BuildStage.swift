import Core
import Foundation

/// `build` — xcodebuild, Debug, on the simulator `device` chose.
///
/// The one step of `up` that takes minutes, which decides three of its rules: no
/// timeout (a slow machine's first clean build must not be killed by its own tool),
/// an elapsed line on stderr while it runs (so nobody wonders whether it died), and
/// on failure the whole log written to a file whose path goes in the remediation.
public struct BuildStage: Stage {
    public let id = "build"

    /// The same mobile.yml doctor read: `ios.scheme`, the anchor, and how this run
    /// spells paths.
    private let config: ConfigContext
    private let runner: any ProcessRunner
    private let locator: XcodeLocator
    /// Where a failed build's output goes.
    private let logs: RunLogs
    private let note: @Sendable (String) -> Void
    /// How often the elapsed line is printed. Long enough not to fill the terminal,
    /// short enough that a silent build never looks hung.
    private let heartbeat: Duration

    public init(
        config: ConfigContext,
        runner: any ProcessRunner,
        locator: XcodeLocator,
        logs: RunLogs? = nil,
        heartbeat: Duration = .seconds(15),
        note: @escaping @Sendable (String) -> Void
    ) {
        self.config = config
        self.runner = runner
        self.locator = locator
        // Outside a project there is nothing to build and `run` says so before
        // anything is written, so where the logs would have gone never matters.
        self.logs = logs ?? RunLogs(project: config.anchor?.directory ?? config.workingDirectory)
        self.heartbeat = heartbeat
        self.note = note
    }

    public func run(_ context: inout UpContext) async throws -> StageOutcome {
        guard let anchor = config.anchor, let target = XcodeBuildTarget.locate(inIOSDirectoryOf: anchor) else {
            throw Self.noTarget
        }
        // The pipeline runs `device` first. Reaching here without one is mobile's own
        // bug, not the project's, so it must not land on the project's exit code.
        guard let device = context.device else {
            throw ToolUnavailable(
                description: "build ran before a simulator was chosen — `device` comes first"
            )
        }

        let environment = await locator.pinnedEnvironment()
        let scheme = try await scheme(anchor, environment)
        let arguments =
            target.arguments + [
                "-scheme", scheme,
                "-configuration", "Debug",
                "-destination", "platform=iOS Simulator,id=\(device.udid)",
            ]

        try await build(arguments, environment)
        context.product = try await product(arguments, scheme: scheme, environment: environment)
        return .pass(scheme)
    }

    /// mobile.yml's scheme, else the only one there is. Listed off the `.xcodeproj`
    /// even when the build target is a workspace — see `XcodeSchemeList`.
    private func scheme(_ anchor: ProjectAnchor, _ environment: [String: String]) async throws -> String {
        guard let project = XcodeSchemeList.project(inIOSDirectoryOf: anchor) else { throw Self.noTarget }
        let list = XcodeSchemeList.command(project: project, environment: environment)
        let result = try await runner.run(list)
        guard result.terminationStatus.isSuccess,
            let schemes = XcodeSchemeList.decode(result.standardOutput)?.project.schemes, !schemes.isEmpty
        else {
            throw ToolUnavailable(
                description: "`\(list.description)` listed no schemes — "
                    + (result.standardError.firstLine ?? "its output was not a scheme list")
            )
        }

        // The same selector `config.values` grades a declaration with. doctor warns
        // where this errors — up has to pick one, and picking for the developer is
        // how a tool spends eight minutes building the wrong target (ADR-0004).
        switch SchemeSelector(schemes: schemes).resolve(declared: config.configuration?.scheme) {
        case .success(let resolved):
            return resolved
        case .failure(let miss):
            throw DomainError(
                summary: miss.observed,
                remediation: miss.remediation(
                    configFile: config.display(
                        anchor.directory.appendingPathComponent(MobileConfig.fileName)
                    ),
                    project: config.display(project)
                )
            )
        }
    }

    private func build(_ arguments: [String], _ environment: [String: String]) async throws {
        // No `-derivedDataPath`: Xcode's own location is the point, so opening the
        // project in Xcode shares this build's cache rather than doing it all again.
        let command = ProcessCommand(
            "xcodebuild", arguments + ["build"], environment: environment, timeout: nil
        )
        let result = try await elapsing { try await runner.run(command) }
        guard !result.terminationStatus.isSuccess else { return }

        // Both streams together, and the tail taken from the same text: xcodebuild
        // prints its `error:` lines on stdout and keeps stderr for its own noise, so
        // a tail that preferred stderr would show the least useful twenty lines.
        let output = result.combinedOutput
        let file = logs.write(output, to: "build.log")
        throw DomainError(
            summary: "the build failed",
            observed: output.lastLines(20),
            remediation: Remediation(
                summary: file.map { "The whole build log is at \($0.path)." }
                    ?? "Run the build by hand to see the whole log — mobile could not write one.",
                command: Self.pasteable(command)
            )
        )
    }

    /// What was built, asked of xcodebuild rather than read out of the log: log
    /// formats move between Xcode versions, and `install` must pick up this run's
    /// bundle and no other.
    private func product(
        _ arguments: [String],
        scheme: String,
        environment: [String: String]
    ) async throws -> BuiltProduct {
        let command = ProcessCommand(
            "xcodebuild", ["-showBuildSettings", "-json"] + arguments,
            environment: environment,
            timeout: .seconds(120)
        )
        let result = try await runner.run(command)
        guard result.terminationStatus.isSuccess,
            let product = XcodeBuildSettings.decode(result.standardOutput)?.application(scheme: scheme)
        else {
            throw ToolUnavailable(
                description: "`\(command.description)` did not say where the app was built — "
                    + (result.standardError.firstLine ?? "its output named no .app")
            )
        }
        return product
    }

    /// An elapsed line on stderr for as long as the work takes. Collected output is
    /// still the contract (ADR-0002) — this says the tool is alive, not what
    /// xcodebuild is doing.
    private func elapsing<T: Sendable>(_ work: () async throws -> T) async rethrows -> T {
        let start = ContinuousClock.now
        let ticker = Task { [id, note, heartbeat] in
            let lines = StageLineRenderer()
            while !Task.isCancelled {
                try await Task.sleep(for: heartbeat)
                note(lines.waiting(id, elapsed: start.duration(to: .now)))
            }
        }
        defer { ticker.cancel() }
        return try await work()
    }

    /// The same command, written so it survives being pasted into a shell. A
    /// destination carries a space — `platform=iOS Simulator,id=…` — and a
    /// remediation that has to be repaired before it runs is not a remediation.
    private static func pasteable(_ command: ProcessCommand) -> String {
        ([command.executable] + command.arguments)
            .map { $0.contains(" ") ? "'\($0)'" : $0 }
            .joined(separator: " ")
    }

    private static let noTarget = DomainError(
        summary: "no Xcode project to build in ios/",
        remediation: Remediation(
            summary: "mobile builds the single `ios/*.xcworkspace`, or the single "
                + "`ios/*.xcodeproj` when there is no workspace. A React Native project has "
                + "one of these; if this one does not, `npx react-native config` says what "
                + "the project thinks its iOS directory is."
        )
    )
}

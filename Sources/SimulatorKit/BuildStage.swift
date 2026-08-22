import Core
import Foundation

/// `build` — xcodebuild, Debug, on the simulator `device` chose.
///
/// The one step of `up` that takes minutes, which decides four of its rules: no
/// timeout (a slow machine's first clean build must not be killed by its own tool),
/// output streamed straight to a file rather than held (a first clean build of a real
/// app is tens of megabytes — ADR-0002's note on #44/#56), an elapsed line on stderr
/// with the latest Xcode target plus the lines worth reading as they arrive, and a
/// failure that names the log file it has already written.
public struct BuildStage: Stage {
    public let id = "build"

    /// The same mobile.yml doctor read: `ios.scheme`, the anchor, and how this run
    /// spells paths.
    private let config: ConfigContext
    private let runner: any ProcessRunner
    private let locator: XcodeLocator
    /// Where the build's output goes — every run, not just a failed one.
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

        context.buildLog = try await build(arguments, environment).path
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

    /// - Returns: the log file the whole build was streamed to, kept on a success too.
    private func build(_ arguments: [String], _ environment: [String: String]) async throws -> URL {
        let file = logs.url("build.log")
        // No `-derivedDataPath`: Xcode's own location is the point, so opening the
        // project in Xcode shares this build's cache rather than doing it all again.
        //
        // Streamed rather than collected: a real app's first clean build runs to tens
        // of megabytes, and the 4 MiB collected limit killed a healthy one (#55).
        let command = ProcessCommand(
            "xcodebuild", arguments + ["build"], environment: environment, timeout: nil,
            output: .streamed(to: file)
        )
        let watch = BuildWatch(logFile: file, note: note)
        // Deferred, not called after: a build that dies on its way out has printed the
        // same lines, and the reader needs the path to the rest of them either way.
        defer { watch.finish() }
        let result = try await elapsing(detail: { watch.progress }) {
            try await runner.run(command, onLine: { watch.saw($0) })
        }
        guard !result.terminationStatus.isSuccess else { return file }

        throw DomainError(
            summary: "the build failed",
            observed: watch.observed,
            remediation: Remediation(
                summary: "The whole build log is at \(file.path).",
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

    /// An elapsed line on stderr for as long as the work takes. It says the tool is
    /// alive; what xcodebuild is doing comes from `BuildWatch`, and only for the lines
    /// worth a reader's attention.
    private func elapsing<T: Sendable>(
        detail: @escaping @Sendable () -> String?,
        _ work: () async throws -> T
    ) async rethrows -> T {
        let start = ContinuousClock.now
        let ticker = Task { [id, note, heartbeat, detail] in
            let lines = StageLineRenderer()
            while !Task.isCancelled {
                try await Task.sleep(for: heartbeat)
                note(lines.waiting(id, detail: detail(), elapsed: start.duration(to: .now)))
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

    /// What `build` chooses to remember from an output it no longer holds. Which lines
    /// matter is xcodebuild knowledge, so it lives here and not in the runner — the
    /// day a gradle filter belongs somewhere, it will not be in `ProcessRunner`.
    ///
    /// Two things come out of it: the lines shown while the build runs, and the
    /// `observed` of a failure. Both prefer the notable lines, because xcodebuild
    /// writes the cause in the middle of the log and piles warnings on the end — a
    /// tail of twenty was almost always twenty warnings (#51).
    private final class BuildWatch: @unchecked Sendable {
        /// Enough to see a cascade of errors, few enough not to bury the run's own
        /// progress lines. The same number bounds the failure's `observed`.
        private static let limit = 20

        private let lock = NSLock()
        private let logFile: URL
        private let note: @Sendable (String) -> Void
        private let excerpt: LineExcerpt
        private var shown = 0
        private var latestTarget: String?

        init(logFile: URL, note: @escaping @Sendable (String) -> Void) {
            self.logFile = logFile
            self.note = note
            self.excerpt = LineExcerpt(limit: Self.limit, notable: Self.isNotable)
        }

        func saw(_ line: String) {
            lock.withLock {
                if let target = Self.target(in: line) {
                    latestTarget = target
                }
                guard let notable = excerpt.append(line) else { return }
                if shown < Self.limit {
                    shown += 1
                    note(notable)
                }
            }
        }

        /// The one line that says the screen stopped short, printed once the count is
        /// known. Nothing when everything notable was already shown.
        func finish() {
            lock.withLock {
                let omitted = excerpt.notableCount - shown
                guard omitted > 0 else { return }
                note("…and \(omitted) more — full log: \(logFile.path)")
            }
        }

        var progress: String? { lock.withLock { latestTarget } }
        var observed: String { excerpt.text }

        private static func target(in line: String) -> String? {
            let targetMarker = "(in target '"
            let projectMarker = "' from project '"
            guard
                let targetStart = line.range(of: targetMarker)?.upperBound,
                let projectRange = line.range(
                    of: projectMarker, range: targetStart..<line.endIndex
                ),
                let endRange = line.range(
                    of: "')", range: projectRange.upperBound..<line.endIndex
                )
            else { return nil }

            let target = line[targetStart..<projectRange.lowerBound]
            let project = line[projectRange.upperBound..<endRange.lowerBound]
            guard !target.isEmpty, !project.isEmpty else { return nil }
            return "target \(target) (\(project))"
        }

        /// `error:` covers `fatal error:` and the clang and Swift spellings alike; the
        /// starred lines are how xcodebuild announces that it is done, either way.
        private static func isNotable(_ line: String) -> Bool {
            line.contains("error:") || (line.hasPrefix("** ") && line.hasSuffix(" **"))
        }
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

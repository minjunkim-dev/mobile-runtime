import Foundation

/// The command environment project Checks and Stages share. Selection happens once
/// at composition: a committed mise config is authoritative; without one, the host
/// runner is already the correct direct-PATH adapter.
public struct ProjectExecutionEnvironment: Check, Sendable {
    public static let checkID = "project.execution-environment"

    public let id = Self.checkID
    public let category = "Project environment"
    public let title = "Project commands use the repository's toolchain"
    // A fresh clone has no node_modules yet, but dependency alignment already needs
    // this environment. The anchor exists before either Check, so activation stands
    // on it directly rather than waiting for an install it is meant to enable.
    public let dependsOn: [String] = []
    public let runner: any ProcessRunner
    private let activation: Activation
    private let preparedTools: [String: URL]
    private let inheritedPath: String?
    private let unpreparedRunner: any ProcessRunner

    private enum Activation: Sendable {
        case direct
        case mise(TrackedMiseConfig, any ProcessRunner)
        case trackingFailure(file: URL, root: URL, observed: String)
    }

    private init(runner: any ProcessRunner, activation: Activation,
                 preparedTools: [String: URL] = [:], inheritedPath: String? = nil,
                 unpreparedRunner: (any ProcessRunner)? = nil) {
        self.runner = runner
        self.activation = activation
        self.preparedTools = preparedTools
        self.inheritedPath = inheritedPath
        self.unpreparedRunner = unpreparedRunner ?? runner
    }

    init(directRunner: any ProcessRunner) {
        self.init(runner: directRunner, activation: .direct)
    }

    /// Selects already verified installations for this project's child processes.
    /// It does not alter a shell, manager configuration, or the inherited process.
    public func activatingTools(_ tools: [String: URL], environment: [String: String]) -> ProjectExecutionEnvironment {
        guard !tools.isEmpty else { return self }
        let selected = preparedTools.merging(tools) { _, new in new }
        let path = environment["PATH"] ?? inheritedPath
        let base: any ProcessRunner
        if case .mise(let config, let hostRunner) = activation {
            base = MiseProcessRunner(base: hostRunner, configDirectory: config.root,
                executable: selected["mise"]?.path ?? "mise")
        } else {
            base = unpreparedRunner
        }
        return ProjectExecutionEnvironment(
            runner: PreparedToolProcessRunner(base: base, tools: selected, inheritedPath: path),
            activation: activation, preparedTools: selected, inheritedPath: path, unpreparedRunner: unpreparedRunner)
    }

    public static func resolve(
        anchor: ProjectAnchor,
        hostRunner: any ProcessRunner,
        fileManager: FileManager = .default
    ) async -> ProjectExecutionEnvironment {
        switch await trackedMiseConfig(
            for: anchor, using: hostRunner, fileManager: fileManager
        ) {
        case .none:
            return ProjectExecutionEnvironment(runner: hostRunner, activation: .direct)
        case .found(let config):
            return ProjectExecutionEnvironment(
                runner: MiseProcessRunner(base: hostRunner, configDirectory: config.root),
                activation: .mise(config, hostRunner)
            )
        case .failure(let file, let root, let observed):
            return ProjectExecutionEnvironment(
                runner: hostRunner,
                activation: .trackingFailure(file: file, root: root, observed: observed)
            )
        }
    }

    /// The complete project Check set, with activation immediately after detection
    /// so every tool Check can depend on one measured environment.
    public func checks(anchor: ProjectAnchor, context: ConfigContext) -> [any Check] {
        var checks = anchor.checks(runner: runner, context: context, environment: self)
        for index in checks.indices where checks[index].id != "project.detected" {
            checks[index] = ActivationDependentCheck(base: checks[index])
        }
        checks.insert(self, at: min(1, checks.endIndex))
        return checks
    }

    /// Platform-neutral project tool checks, activated through the same committed
    /// toolchain as every later Gradle command.
    public func commonChecks(anchor: ProjectAnchor, context: ConfigContext) -> [any Check] {
        var checks: [any Check] = [self]
        checks.append(contentsOf: anchor.commonChecks(runner: runner, context: context, environment: self).map {
            ActivationDependentCheck(base: $0)
        })
        return checks
    }

    func remediationCommand(_ command: ProcessCommand) -> String {
        let command = PreparedToolProcessRunner(base: runner, tools: preparedTools, inheritedPath: inheritedPath).activated(command)
        let policy = preparedTools.isEmpty ? "" : command.environment.keys.sorted().filter { ["PATH", "JAVA_HOME", "MISE_AUTO_INSTALL"].contains($0) }
            .map { "\($0)=\(shellArgument(command.environment[$0]!))" }.joined(separator: " ") + " "
        if case .mise(let config, _) = activation {
            var selected = command
            if !preparedTools.isEmpty {
                selected.executable = "/usr/bin/env"
                selected.arguments = command.environment.keys.sorted().filter { ["PATH", "JAVA_HOME", "MISE_AUTO_INSTALL"].contains($0) }
                    .map { "\($0)=\(command.environment[$0]!)" } + [command.executable] + command.arguments
            }
            return MiseProcessRunner(base: runner, configDirectory: config.root,
                executable: preparedTools["mise"]?.path ?? "mise").remediationCommand(selected)
        }
        let invocation = ([command.executable] + command.arguments)
            .map(shellArgument).joined(separator: " ")
        guard let directory = command.workingDirectory else { return policy + invocation }
        return "cd \(shellArgument(directory.path)) && \(policy)\(invocation)"
    }

    public func run() async throws -> CheckOutcome {
        for (name, path) in preparedTools.sorted(by: { $0.key < $1.key }) {
            guard PreparedToolProcessRunner.valid(name: name, path: path), FileManager.default.isExecutableFile(atPath: path.path) else {
                return .error(observed: "Selected \(name) executable is missing or invalid",
                    required: "the exact prepared project tool path", source: CheckSource(origin: "approved tool preparation"),
                    remediation: Remediation(summary: "Inspect tool installations and approve a new preparation plan. Do not substitute another global version."))
            }
        }
        switch activation {
        case .direct:
            return .pass(observed: preparedTools.isEmpty ? "current PATH — no committed mise config"
                : "selected prepared tool paths; global PATH and selections unchanged")

        case .trackingFailure(let file, let root, let observed):
            let relative = relativePath(file, from: root)
            return .error(
                observed: "Could not verify whether \(relative) is committed: \(observed)",
                required: "readable Git tracking state before selecting the project PATH",
                source: CheckSource(tier: 1, origin: relative),
                remediation: Remediation(
                    summary: "Fix Git access for this checkout, then re-run mobile doctor.",
                    command: "git -C \(shellArgument(root.path)) status --short -- \(shellArgument(relative))"
                )
            )

        case .mise(let config, let hostRunner):
            let source = CheckSource(tier: 1, origin: relativePath(config.file, from: config.root))
            let command = ProcessCommand(
                "mise",
                ["exec", "--", "true"],
                environment: ["MISE_AUTO_INSTALL": "false"],
                workingDirectory: config.root,
                timeout: .seconds(15)
            )
            let result: ProcessResult
            do {
                result = try await PreparedToolProcessRunner(base: hostRunner, tools: preparedTools,
                    inheritedPath: inheritedPath).run(command)
            } catch let error as ProcessError {
                guard case .spawnFailed = error else { throw error }
                return .error(
                    observed: "mise is not on PATH",
                    required: "mise for \(relativePath(config.file, from: config.root))",
                    source: source,
                    remediation: Remediation(
                        summary: "This repo commits a mise config, so install mise or remove that declaration, then re-run mobile doctor.",
                        url: "https://mise.jdx.dev/getting-started.html"
                    )
                )
            }
            guard result.terminationStatus.isSuccess else {
                let observed = result.combinedOutput.lastLines(10)
                let trust = observed.localizedCaseInsensitiveContains("trust")
                return .error(
                    observed: observed.isEmpty ? "mise could not activate the project toolchain" : observed,
                    required: "usable tools from \(relativePath(config.file, from: config.root))",
                    source: source,
                    remediation: Remediation(
                        summary: trust
                            ? "Trust this repo's committed mise config, then re-run mobile doctor."
                            : "Fix the committed mise toolchain, then re-run mobile doctor. mobile will not install it automatically.",
                        command: trust
                            ? "\(shellArgument(preparedTools["mise"]?.path ?? "mise")) trust \(shellArgument(config.root.path))"
                            : "cd \(shellArgument(config.root.path)) && \(shellArgument(preparedTools["mise"]?.path ?? "mise")) doctor"
                    )
                )
            }
            return .pass(
                observed: "mise — automatic installation disabled",
                required: "tools from \(relativePath(config.file, from: config.root))",
                source: source
            )
        }
    }

    private func relativePath(_ file: URL, from root: URL) -> String {
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return file.path.hasPrefix(prefix) ? String(file.path.dropFirst(prefix.count)) : file.path
    }
}

private struct PreparedToolProcessRunner: ProcessRunner {
    let base: any ProcessRunner
    let tools: [String: URL]
    let inheritedPath: String?

    static func valid(name: String, path: URL) -> Bool {
        ["mise", "node", "npm", "npx", "corepack", "ruby", "gem", "bundle", "pod", "java", "javac", "flutter", "dart"].contains(name)
            && path.isFileURL && path.path.hasPrefix("/")
            && !path.path.contains(":")
            && !path.path.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    func activated(_ command: ProcessCommand) -> ProcessCommand {
        guard !tools.isEmpty else { return command }
        var selected = command
        if let executable = tools[command.executable], Self.valid(name: command.executable, path: executable) {
            selected.executable = executable.path
        }
        var directories: [String] = []
        for name in tools.keys.sorted() {
            guard let path = tools[name], Self.valid(name: name, path: path) else { continue }
            let directory = path.deletingLastPathComponent().path
            if !directories.contains(directory) { directories.append(directory) }
        }
        if let previous = command.environment["PATH"] ?? inheritedPath, !previous.isEmpty { directories.append(previous) }
        selected.environment["PATH"] = directories.joined(separator: ":")
        if let java = tools["java"], Self.valid(name: "java", path: java) {
            selected.environment["JAVA_HOME"] = java.deletingLastPathComponent().deletingLastPathComponent().path
        }
        selected.environment["MISE_AUTO_INSTALL"] = "false"
        return selected
    }

    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        try await base.run(activated(command), onLine: onLine)
    }

    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
        try await base.spawnDetached(activated(command), logFile: logFile)
    }
}

private struct ActivationDependentCheck: Check {
    let base: any Check

    var id: String { base.id }
    var category: String { base.category }
    var title: String { base.title }
    var dependsOn: [String] { base.dependsOn + [ProjectExecutionEnvironment.checkID] }

    func run() async throws -> CheckOutcome { try await base.run() }
}

struct TrackedMiseConfig: Sendable {
    let file: URL
    let root: URL
}

enum TrackedMiseConfigLookup: Sendable {
    case none
    case found(TrackedMiseConfig)
    case failure(file: URL, root: URL, observed: String)
}

func trackedMiseConfig(
    for anchor: ProjectAnchor,
    using runner: any ProcessRunner,
    fileManager: FileManager = .default
) async -> TrackedMiseConfigLookup {
    var directories = [anchor.directory]
    if let workspace = anchor.workspaceRoot?.directory, workspace != anchor.directory {
        directories.append(workspace)
    }
    let files = ["mise.toml", ".mise.toml", ".config/mise/config.toml"]

    for directory in directories {
        for file in files {
            let candidate = directory.appendingPathComponent(file)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
                !isDirectory.boolValue
            else { continue }

            let command = ProcessCommand(
                "git",
                ["-C", directory.path, "ls-files", "--error-unmatch", "--", file],
                timeout: .seconds(15)
            )
            let tracked: ProcessResult
            do {
                tracked = try await runner.run(command)
            } catch {
                return .failure(
                    file: candidate,
                    root: directory,
                    observed: String(describing: error).lastLines(5)
                )
            }
            switch tracked.terminationStatus {
            case .exited(0):
                return .found(TrackedMiseConfig(file: candidate, root: directory))
            case .exited(1):
                continue
            case .exited(let code):
                let details = tracked.combinedOutput.lastLines(5)
                return .failure(
                    file: candidate,
                    root: directory,
                    observed: details.isEmpty ? "git ls-files exited with \(code)" : details
                )
            case .signaled(let signal):
                return .failure(
                    file: candidate,
                    root: directory,
                    observed: "git ls-files was terminated by signal \(signal)"
                )
            }
        }
    }
    return .none
}

/// Runs project commands with the tools from a committed mise configuration.
/// The base runner still owns process behavior; this adapter only selects the
/// project environment and makes mise's otherwise-default installation impossible.
struct MiseProcessRunner: ProcessRunner {
    private let base: any ProcessRunner
    private let configDirectory: URL
    private let executable: String

    init(base: any ProcessRunner, configDirectory: URL, executable: String = "mise") {
        self.base = base
        self.configDirectory = configDirectory
        self.executable = executable
    }

    func run(
        _ command: ProcessCommand,
        onLine: (@Sendable (String) -> Void)?
    ) async throws -> ProcessResult {
        try await base.run(activated(command), onLine: onLine)
    }

    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
        try await base.spawnDetached(activated(command), logFile: logFile)
    }

    /// Renders an explicit, human-run provisioning command through the same
    /// committed mise context as normal project commands. Rendering does not run it.
    func remediationCommand(_ command: ProcessCommand) -> String {
        let activated = activated(command)
        let invocation = ([activated.executable] + activated.arguments)
            .map(shellArgument).joined(separator: " ")
        return "cd \(shellArgument(configDirectory.path)) && MISE_AUTO_INSTALL=false \(invocation)"
    }

    private func activated(_ command: ProcessCommand) -> ProcessCommand {
        var activated = command
        activated.executable = executable
        if let workingDirectory = command.workingDirectory,
            workingDirectory != configDirectory
        {
            activated.arguments = [
                "exec", "--", "sh", "-c", "cd \"$1\" && shift && exec \"$@\"",
                "mobile-mise", workingDirectory.path, command.executable,
            ] + command.arguments
        } else {
            activated.arguments = ["exec", "--", command.executable] + command.arguments
        }
        activated.environment["MISE_AUTO_INSTALL"] = "false"
        activated.workingDirectory = configDirectory
        return activated
    }
}

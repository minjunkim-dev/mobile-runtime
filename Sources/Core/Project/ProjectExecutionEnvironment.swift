import Foundation

/// The command environment project Checks and Stages share. Selection happens once
/// at composition: a committed mise config is authoritative; without one, the host
/// runner is already the correct direct-PATH adapter.
public struct ProjectExecutionEnvironment: Check, Sendable {
    public static let checkID = "project.execution-environment"

    public let id = Self.checkID
    public let category = "Project environment"
    public let title = "Project commands use the repository's toolchain"
    public let dependsOn = ["project.detected"]
    public let runner: any ProcessRunner
    private let activation: Activation

    private enum Activation: Sendable {
        case direct
        case mise(TrackedMiseConfig, any ProcessRunner)
        case trackingFailure(file: URL, root: URL, observed: String)
    }

    private init(runner: any ProcessRunner, activation: Activation) {
        self.runner = runner
        self.activation = activation
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
        var checks = anchor.checks(runner: runner, context: context)
        for index in checks.indices where checks[index].id != "project.detected" {
            checks[index] = ActivationDependentCheck(base: checks[index])
        }
        checks.insert(self, at: min(1, checks.endIndex))
        return checks
    }

    public func run() async throws -> CheckOutcome {
        switch activation {
        case .direct:
            return .pass(observed: "current PATH — no committed mise config")

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
                result = try await hostRunner.run(command)
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
                            ? "mise trust \(shellArgument(config.root.path))"
                            : "cd \(shellArgument(config.root.path)) && mise doctor"
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

    init(base: any ProcessRunner, configDirectory: URL) {
        self.base = base
        self.configDirectory = configDirectory
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

    private func activated(_ command: ProcessCommand) -> ProcessCommand {
        var activated = command
        activated.executable = "mise"
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

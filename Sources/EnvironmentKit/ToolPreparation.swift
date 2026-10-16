import Core
import Foundation

public enum PreparedTool: String, Codable, Sendable {
    case node, ruby, java
}

/// The caller supplies Tier 1 or an explicitly selected compatible exact build.
/// A range or an unknown vendor is retained as a manual requirement, not latest.
public struct ToolPreparationRequirement: Sendable {
    public let tool: PreparedTool
    public let version: String?
    public let source: CheckSource
    public let blocker: String?

    public init(tool: PreparedTool, version: String?, source: CheckSource, blocker: String? = nil) {
        self.tool = tool; self.version = version; self.source = source; self.blocker = blocker
    }

    var exactVersion: String? {
        guard var version else { return nil }
        if tool == .node, version.hasPrefix("v") { version.removeFirst() }
        if tool == .ruby, version.hasPrefix("ruby-") { version = String(version.dropFirst(5)) }
        let pattern = tool == .java ? #"^[a-z][a-z0-9-]*-[0-9]+\.[0-9]+\.[0-9]+(?:\.[0-9]+)?\+[0-9]+$"# : #"^[0-9]+\.[0-9]+\.[0-9]+$"#
        return version.range(of: pattern, options: .regularExpression) == nil ? nil : version
    }
}

public struct ToolPreparationHost: Sendable {
    public let architecture: String
    public let macOS: SemanticVersion
    public init(architecture: String, macOS: SemanticVersion) { self.architecture = architecture; self.macOS = macOS }

    public static var current: Self {
        let value = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "unsupported"
        #endif
        return Self(architecture: architecture, macOS: SemanticVersion(major: value.majorVersion, minor: value.minorVersion, patch: value.patchVersion))
    }
}

/// Provider output is merged into the existing PreparationExecution plan and loop.
/// No independent approval or manager installer exists here.
public struct ToolPreparation: Sendable {
    public var checks: [PreparationStep] = []
    public var steps: [PreparationStep] { checks.filter { $0.kind != "reuse" } }
    public var installed: [String: Bool] = [:]
    public var actions: [String: InstallationAction] = [:]
    /// Measured existing executables only. Call inspect again after installation.
    public var activeTools: [String: URL] = [:]

    /// Only initial tool observation uses currentToolRunner. Official metadata,
    /// manager/store observation and approved actions use the machine runner.
    public static func inspect(
        requirements: [ToolPreparationRequirement], directory: URL,
        environment: [String: String], runner: any ProcessRunner,
        currentToolRunner: (any ProcessRunner)? = nil,
        host: ToolPreparationHost = .current, planInstallations: Bool = true
    ) async throws -> Self {
        var plan = Self()
        guard host.architecture == "arm64" else {
            plan.checks = requirements.map { manual($0, "Only the macOS arm64 distribution is pinned by this provider") }
            return plan
        }
        let grouped = Dictionary(grouping: requirements, by: { $0.tool.rawValue })
        var bootstrap: ToolReleaseCatalog.Release?
        for tool in grouped.keys.sorted() {
            try Task.checkCancellation()
            let requests = grouped[tool]!
            guard let first = requests.first else { continue }
            if let blocker = requests.compactMap(\.blocker).first {
                plan.checks.append(manual(first, blocker))
                continue
            }
            guard Set(requests.map(\.exactVersion)).count == 1, let version = first.exactVersion else {
                plan.checks.append(manual(first, "An exact compatible version is required. Ranges, conflicting declarations and unsupported Java vendors are not replaced with a default vendor."))
                continue
            }
            let tiers = Set(requests.map { $0.source.tier })
            let request = ToolPreparationRequirement(tool: first.tool, version: version,
                source: CheckSource(tier: tiers.count == 1 ? first.source.tier : nil,
                    origin: Set(requests.map { $0.source.origin }).sorted().joined(separator: "; ")))
            let probeName = request.tool.rawValue
            let observedRunner = currentToolRunner ?? runner
            if let path = try await which(probeName, directory: directory, runner: observedRunner), FileManager.default.isExecutableFile(atPath: path.path) {
                if request.tool == .java {
                    if let java = try await ToolJavaObservation.observe(executable: path.path, directory: directory, runner: observedRunner), java.identity == version {
                        recordReuse(request, path: java.executable,
                            observed: "existing JDK properties \(java.properties.propertiesVersion ?? "unknown"); runtime \(java.properties.runtimeVersion ?? "unknown"); vendor \(java.properties.vendor ?? "unknown"); architecture \(java.properties.architecture ?? "unknown")", plan: &plan)
                        continue
                    }
                } else if try await matches(request, executable: path, runner: observedRunner) {
                    recordReuse(request, path: path, observed: "existing executable satisfies \(version)", plan: &plan)
                    continue
                }
            }
            if request.tool == .java, !version.hasPrefix("temurin-") {
                plan.checks.append(manual(request, "This exact vendor-qualified JDK was not verified in the selected project environment. Preserve its vendor and prepare it through the existing manager. Only an explicitly selected Temurin distribution can be newly installed."))
                continue
            }
            guard let root = dataRoot(environment) else {
                plan.checks.append(manual(request, "HOME or an explicit absolute MISE_DATA_DIR is required to identify the installation destination"))
                continue
            }
            let manager = try await which("mise", directory: directory, runner: runner)
            if environment["MISE_INSTALLS_DIR"] != nil || environment["MISE_INSTALL_LAYOUT"].map({ $0 != "legacy" }) == true {
                plan.checks.append(manual(request, "This mise installation uses a custom or identity store layout. Preserve it and prepare its exact tool through the existing manager."))
                continue
            }
            let ownManager = root.appendingPathComponent("manager/2026.10.7/bin/mise")
            let ownManagerDestination = ownManager.deletingLastPathComponent().deletingLastPathComponent()
            if manager == nil, FileManager.default.fileExists(atPath: ownManagerDestination.path),
               !FileManager.default.isExecutableFile(atPath: ownManager.path) {
                plan.checks.append(manual(request, "The proposed mise destination already contains an unverified installation. Preserve it and inspect it manually.", target: ownManagerDestination.path))
                continue
            }
            if manager == nil && !FileManager.default.isExecutableFile(atPath: ownManager.path),
               let other = try await existingManager(request.tool, directory: directory, environment: environment, runner: runner) {
                plan.checks.append(manual(request, "Existing \(other) was detected. Prepare its exact declared version with that manager and inspect again. Setup will not replace it with mise or authorize hidden manager downloads."))
                continue
            }
            if let executable = manager ?? (FileManager.default.isExecutableFile(atPath: ownManager.path) ? ownManager : nil),
               plan.activeTools["mise"] == nil {
                guard FileManager.default.isExecutableFile(atPath: executable.path),
                      let bytes = try? Data(contentsOf: executable, options: .mappedIfSafe) else {
                    plan.checks.append(manual(request, "The existing mise executable cannot be verified. Preserve it and inspect access manually.", target: executable.path))
                    continue
                }
                let measured = try await runner.run(ProcessCommand(executable.path, ["--version"], timeout: .seconds(15)))
                guard measured.terminationStatus.isSuccess,
                      measured.combinedOutput.range(of: #"\b[0-9]+\.[0-9]+\.[0-9]+\b"#, options: .regularExpression) != nil,
                      manager != nil || ToolInstallationValidation.versionMatches(measured.combinedOutput, version: "2026.10.7", tool: "mise") else {
                    plan.checks.append(manual(request, "The existing mise executable has an unexpected version. Preserve it and inspect it manually.", target: executable.path))
                    continue
                }
                plan.activeTools["mise"] = executable
                plan.checks.append(PreparationStep(id: "tools.00.mise", platform: nil, kind: "reuse", target: executable.path,
                    observed: measured.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines) + "; executable SHA256 " + ToolReleaseCatalog.sha(bytes),
                    required: "reuse this manager without changing its selections", source: CheckSource(origin: "existing mise executable"), command: nil, remediation: nil))
            }
            let destination = root.appendingPathComponent("installs/\(tool)/\(version)")
            let executable = destination.appendingPathComponent("bin/\(tool)")
            let present = FileManager.default.fileExists(atPath: destination.path)
                || (try? FileManager.default.destinationOfSymbolicLink(atPath: destination.path)) != nil
            plan.installed[destination.path] = present
            if present {
                if FileManager.default.isExecutableFile(atPath: executable.path), try await matches(request, executable: executable, runner: runner) {
                    recordReuse(request, path: executable, observed: "existing mise installation; project activation only", plan: &plan)
                } else {
                    plan.checks.append(manual(request, "The exact destination already exists but cannot be verified. Preserve it and inspect it manually.", target: destination.path))
                }
                continue
            }
            if !planInstallations {
                plan.checks.append(manual(request, "Prepare this exact tool through an approved setup plan, then inspect again.", target: destination.path))
                continue
            }
            do {
                if manager == nil && !FileManager.default.isExecutableFile(atPath: ownManager.path), bootstrap == nil {
                    bootstrap = try await ToolReleaseCatalog.mise(runner: runner)
                }
                let release = try await ToolReleaseCatalog.release(request, runner: runner)
                let metadata = metadata(release, package: "tools.\(tool)", destination: destination, root: root)
                try InstallationExecution.validateDestination(metadata)
                var step = PreparationStep(id: "tools.\(tool)", platform: nil, kind: "install", target: destination.path,
                    observed: "absent; \(plan.activeTools["mise"] == nil ? "pinned mise bootstrap proposed" : "reuse existing mise")",
                    required: "\(version); arm64; staged Mach-O minimum OS and contained/system libraries; owned scratch under \(root.path); no shared manager cache writes",
                    source: request.source, command: nil,
                    remediation: Remediation(summary: "Install this pinned archive beside existing versions. Global PATH, manager selections and repository declarations are preserved."))
                step.installation = metadata
                plan.checks.append(step)
                plan.actions[step.id] = InstallationAction(metadata: metadata) { runner, beforeCommit in
                    try await ToolArchive.installTarGzip(metadata, payloadRoot: release.payloadRoot, runner: runner, beforeCommit: beforeCommit) { stage, runner in
                        try await ToolInstallationValidation.validate(stage: stage, executable: release.executable,
                            version: version, tool: request.tool.rawValue, host: host, runner: runner)
                    }
                }
            } catch is CancellationError { throw CancellationError() }
            catch {
                plan.checks.append(manual(request, "Exact official archive identity or destination access is unavailable. Inspect the official metadata and path before approving.", target: destination.path))
            }
        }
        if let release = bootstrap, let root = dataRoot(environment), !plan.actions.isEmpty {
            let destination = root.appendingPathComponent("manager/\(release.version)")
            let metadata = metadata(release, package: "tools.mise", destination: destination, root: root)
            var step = PreparationStep(id: "tools.00.mise", platform: nil, kind: "install", target: destination.path,
                observed: "no supported manager", required: "mise \(release.version); exact official raw macos-arm64 binary; owned scratch under \(root.path)",
                source: CheckSource(origin: release.repository.absoluteString), command: nil,
                remediation: Remediation(summary: "Install only the proposed mise binary. No activation script, default packages, plugins, manager cache or global configuration is executed."))
            step.installation = metadata
            plan.installed[destination.path] = FileManager.default.fileExists(atPath: destination.path)
            plan.checks.append(step)
            plan.actions[step.id] = InstallationAction(metadata: metadata) { runner, beforeCommit in
                try await ToolArchive.installExecutable(metadata, runner: runner, beforeCommit: beforeCommit) { stage, runner in
                    try await ToolInstallationValidation.validate(stage: stage, executable: release.executable,
                        version: release.version, tool: "mise", host: host, runner: runner)
                }
            }
        }
        return plan
    }

    private static func metadata(_ release: ToolReleaseCatalog.Release, package: String, destination: URL, root: URL) -> InstallationMetadata {
        InstallationMetadata(package: package, revision: release.version, destination: destination, resourceRoot: root,
            artifact: release.artifact, repositoryURL: release.repository, repositorySHA256: release.identity,
            requiredFile: release.executable, executable: true)
    }

    private static func recordReuse(_ request: ToolPreparationRequirement, path: URL, observed: String, plan: inout Self) {
        guard let bytes = try? Data(contentsOf: path, options: .mappedIfSafe) else {
            plan.checks.append(manual(request, "The selected executable cannot be read for its preparation identity. Inspect access manually.", target: path.path))
            return
        }
        plan.activeTools[request.tool.rawValue] = path
        let siblings: [String] = switch request.tool {
        case .node: ["npm", "npx", "corepack"]
        case .ruby: ["gem", "bundle", "pod"]
        case .java: ["javac"]
        }
        for sibling in siblings {
            let candidate = path.deletingLastPathComponent().appendingPathComponent(sibling)
            if FileManager.default.isExecutableFile(atPath: candidate.path) { plan.activeTools[sibling] = candidate }
        }
        plan.checks.append(PreparationStep(id: "tools.\(request.tool.rawValue)", platform: nil, kind: "reuse", target: path.path,
            observed: observed + "; executable SHA256 " + ToolReleaseCatalog.sha(bytes),
            required: request.version, source: request.source, command: nil, remediation: nil))
    }

    private static func matches(_ request: ToolPreparationRequirement, executable: URL, runner: any ProcessRunner) async throws -> Bool {
        if request.tool == .java {
            guard let java = try await ToolJavaObservation.observe(executable: executable.path, directory: executable.deletingLastPathComponent(), runner: runner) else { return false }
            return java.identity == request.exactVersion && java.executable.resolvingSymlinksInPath() == executable.resolvingSymlinksInPath()
        }
        let arguments = request.tool == .java ? ["-version"] : ["--version"]
        let result = try await runner.run(ProcessCommand(executable.path, arguments, timeout: .seconds(15)))
        guard result.terminationStatus.isSuccess, let version = request.exactVersion else { return false }
        return ToolInstallationValidation.versionMatches(result.combinedOutput, version: version, tool: request.tool.rawValue)
    }

    private static func which(_ tool: String, directory: URL, runner: any ProcessRunner) async throws -> URL? {
        do {
            let result = try await runner.run(ProcessCommand("/usr/bin/which", [tool], workingDirectory: directory, timeout: .seconds(15)))
            let value = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard result.terminationStatus.isSuccess, value.hasPrefix("/"), !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
            return URL(fileURLWithPath: value)
        } catch let error as ProcessError {
            guard case .spawnFailed = error else { throw error }
            return nil
        }
    }

    private static func existingManager(_ tool: PreparedTool, directory: URL, environment: [String: String], runner: any ProcessRunner) async throws -> String? {
        if tool == .node, environment["NVM_DIR"] != nil { return "nvm" }
        if tool == .java, environment["SDKMAN_DIR"] != nil { return "SDKMAN" }
        let names: [String] = switch tool { case .node: ["fnm", "asdf"]; case .ruby: ["rbenv", "rvm", "asdf"]; case .java: ["asdf"] }
        for name in names {
            if try await which(name, directory: directory, runner: runner) != nil { return name }
        }
        return nil
    }

    private static func dataRoot(_ environment: [String: String]) -> URL? {
        let value = environment["MISE_DATA_DIR"] ?? environment["XDG_DATA_HOME"].map { $0 + "/mise" }
            ?? environment["HOME"].map { $0 + "/.local/share/mise" }
        guard let value, value.hasPrefix("/"), !value.contains(":"), !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return URL(fileURLWithPath: value).standardizedFileURL
    }

    private static func manual(_ request: ToolPreparationRequirement, _ reason: String, target: String? = nil) -> PreparationStep {
        PreparationStep(id: "tools.\(request.tool.rawValue)", platform: nil, kind: "provider", target: target ?? request.tool.rawValue,
            observed: reason, required: request.version ?? "exact declared/compatible version", source: request.source,
            command: nil, remediation: Remediation(summary: reason))
    }
}

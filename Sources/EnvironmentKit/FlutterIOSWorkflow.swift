import Core
import CryptoKit
import Darwin
import Foundation
import SimulatorKit

struct FlutterIOSPreparationCheck: Check {
    let step: PreparationStep
    let root: URL
    var id: String { step.id }
    let category = "Flutter iOS"
    var title: String { step.id }
    func run() async throws -> CheckOutcome {
        // Setup always proposes locked alignment. Execution only consumes existing generated inputs.
        let existing = step.id == "dependencies.flutter" && step.kind == "align"
            && FileManager.default.fileExists(atPath: root.appendingPathComponent(".dart_tool/package_config.json").path)
        let native = URL(fileURLWithPath: step.target)
        if step.id == "ios.flutter.generated", step.kind == "reuse",
           FileManager.default.fileExists(atPath: native.appendingPathComponent("Podfile").path) {
            guard let lock = try? Data(contentsOf: native.appendingPathComponent("Podfile.lock")),
                let manifest = try? Data(contentsOf: native.appendingPathComponent("Pods/Manifest.lock")), lock == manifest,
                let entries = try? FileManager.default.contentsOfDirectory(atPath: native.path),
                entries.filter({ $0.hasSuffix(".xcworkspace") }).count == 1 else {
                return .error(observed: "Flutter CocoaPods needs an existing workspace and matching Podfile.lock/Pods Manifest.lock.",
                    remediation: Remediation(summary: "Prepare the frozen Flutter Pods manually or through an approved setup plan. Build/up never runs pod install."))
            }
        }
        if step.kind == "reuse" || existing {
            return .pass(observed: step.observed, required: step.required, source: step.source)
        }
        return .error(observed: step.observed, required: step.required, source: step.source,
            remediation: step.remediation ?? Remediation(summary: "Inspect and approve mobile setup before building. Preserve source and lockfiles."))
    }
}

struct FlutterIOSSDKCheck: Check {
    let sdk: FlutterSDK
    let id = "flutter.ios-prepared-sdk"
    let category = "Flutter iOS"
    let title = "Flutter iOS build inputs are already prepared"
    func run() async throws -> CheckOutcome {
        func text(_ path: String) -> String? {
            (try? String(contentsOf: sdk.root.appendingPathComponent(path), encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let engine = text("bin/internal/engine.version")
        let manifest = sdk.root.appendingPathComponent("packages/flutter_tools/pubspec.yaml")
        let lock = sdk.root.appendingPathComponent("packages/flutter_tools/pubspec.lock")
        let manifestDate = try? manifest.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let lockDate = try? lock.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        guard text("bin/cache/flutter_tools.stamp") == sdk.revision + ":",
              let engine, engine.range(of: #"^[0-9a-f]{40}$"#, options: .regularExpression) != nil,
              text("bin/cache/engine.stamp") == engine,
              text("bin/cache/engine-dart-sdk.stamp") == engine,
              let manifestDate, let lockDate, manifestDate <= lockDate else {
            return .error(observed: "The selected Flutter SDK would need wrapper bootstrap or engine/Dart preparation.",
                remediation: Remediation(summary: "Prepare this exact SDK explicitly before build/up. Runstir never bootstraps, upgrades or downloads tools during app execution."))
        }
        return .pass(observed: "Existing exact Flutter/Dart snapshot and engine stamps; native child writes and downloads remain restricted.")
    }
}

struct FlutterIOSHostCheck: Check {
    let anchor: ProjectAnchor
    let config: ConfigContext
    let lookup: MatrixLookup?
    let runner: any ProcessRunner
    let locator: XcodeLocator
    let entrypoint: String?
    let sdk: URL
    let configuration: String?
    let id = "ios.flutter.project"
    let category = "Flutter iOS"
    let title = "Prepared Flutter iOS app target"
    func run() async throws -> CheckOutcome {
        do {
            let choices = try await IOSWorkflowCandidates.load(anchor: anchor, config: config, lookup: lookup,
                runner: runner, locator: locator, includeDevices: false, configuration: configuration,
                entrypoint: entrypoint, flutterSDKRoot: sdk)
            if let scheme = config.configuration?.scheme, !choices.schemes.contains(scheme) {
                return .error(observed: "The selected Flutter app scheme is not a shared runnable app scheme.",
                    remediation: Remediation(summary: "Select a reported shared app scheme, then retry."))
            }
            if choices.schemes.count > 1 && config.configuration?.scheme == nil {
                return .warning(observed: "Multiple shared Flutter app schemes need an explicit selection.",
                    remediation: Remediation(summary: "Select a reported scheme before building or running."))
            }
            if configuration == nil && !choices.configurations.isEmpty && !choices.configurations.contains("Debug") {
                return .warning(observed: "This Flutter app has no declared Debug configuration.",
                    remediation: Remediation(summary: "Select a reported configuration with --configuration and verify that its effective Flutter build mode is debug."))
            }
            return .pass(observed: "The selected shared app scheme resolves matching Flutter debug inputs.")
        } catch let error as DomainError {
            return .error(observed: error.summary, remediation: error.remediation)
        }
    }
}

/// Flutter adds preparation and preservation to the existing Simulator stages.
final class FlutterIOSWorkflow: @unchecked Sendable {
    let buildRunner: any ProcessRunner
    let childProfile: URL
    private let root: URL
    private let application: URL
    private let excludedSDK: URL
    private let directoryAliases: [String: String]
    private let original: [String: String]
    private let sdk: FlutterSDK
    private let lock = NSLock()
    private var changed: [String] = []
    var changedFiles: [String] { lock.withLock { changed } }

    init(anchor: ProjectAnchor, input: ProjectInspectionInput, preparation: FlutterPreparation?, runner: any ProcessRunner) throws {
        guard let preparation, let sdk = preparation.sdk, preparation.entrypoint != nil,
            let workspace = preparation.workspace else {
            throw Self.failure("Flutter iOS preparation is incomplete. Inspect mobile setup with the same entrypoint.")
        }
        let alternate = ["FLUTTER_TOOL_ARGS", "FLUTTER_ENGINE", "LOCAL_ENGINE", "LOCAL_ENGINE_HOST", "FLUTTER_ENGINE_SRC_PATH"]
        guard !alternate.contains(where: { input.environment[$0].map { !$0.isEmpty } == true }) else {
            throw Self.failure("Flutter execution cannot substitute local engine inputs or tool arguments for the selected exact SDK.")
        }
        root = workspace.directory
        application = anchor.directory
        excludedSDK = sdk.root
        self.sdk = sdk
        let sdkPath = try Self.physical(sdk.root.path)
        let workspacePath = try Self.physical(root.path)
        var aliases: [String: String] = [:]
        for package in workspace.packages {
            if let source = try? Self.aliasPath(package.appendingPathComponent(".fvm/flutter_sdk")) { aliases[source] = sdkPath }
        }
        let declaredSDKs = [input.environment["FLUTTER_ROOT"]].compactMap { $0 }
            + (input.environment["PATH"] ?? "").split(separator: ":").filter { $0.hasPrefix("/") && $0.hasSuffix("/bin") }
                .map { URL(fileURLWithPath: String($0)).deletingLastPathComponent().path }
        for path in declaredSDKs where path.hasPrefix("/") {
            let declared = URL(fileURLWithPath: path).standardizedFileURL
            if let source = try? Self.aliasPath(declared), source.hasPrefix(workspacePath + "/"),
               (try? Self.physical(declared.path)) == sdkPath {
                aliases[source] = sdkPath
            }
        }
        if preparation.checks.contains(where: { $0.id == "ios.flutter.generated" && $0.kind == "reuse" }) {
            for (name, target) in preparation.iosPluginDirectories where name.range(of: #"^[a-z_][a-z0-9_]*$"#, options: .regularExpression) != nil {
                if let source = try? Self.aliasPath(anchor.iosDirectory.appendingPathComponent(".symlinks/plugins/" + name)),
                   let destination = try? Self.physical(target.path) {
                    aliases[source] = destination
                }
            }
        }
        directoryAliases = aliases
        original = try Self.files(root, application: anchor.directory, excluding: sdk.root, aliases: aliases)
        let logs = RunLogs(project: anchor.directory)
        let protected = original.filter { !$0.value.hasPrefix("link:") }.map(\.key) + [
            sdk.root.appendingPathComponent("bin/cache/dart-sdk").path,
            sdk.root.appendingPathComponent("bin/cache/artifacts").path,
            sdk.root.appendingPathComponent("packages/flutter_tools").path,
            sdk.root.appendingPathComponent("bin/cache/flutter_tools.snapshot").path,
            sdk.root.appendingPathComponent("bin/cache/flutter.version.json").path,
        ]
        // Native scripts still call Flutter assemble. Restrict that child, not the user's host settings.
        func rule(_ path: String, filter: String) throws -> String {
            guard !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw Self.failure("Flutter iOS cannot protect a path containing control characters.")
            }
            return "(" + filter + " \"" + path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\")"
        }
        var physicalPaths = Set(protected)
        for path in protected { physicalPaths.insert(try Self.physical(path)) }
        var filters = try physicalPaths.sorted().map { try rule($0, filter: "subpath") }
        // Preserve the link itself; resolving its target could freeze an entire shared SDK/cache.
        for (path, value) in original where value.hasPrefix("link:") {
            let url = URL(fileURLWithPath: path)
            let parent = try Self.physical(url.deletingLastPathComponent().path)
            filters.append(try rule(URL(fileURLWithPath: parent).appendingPathComponent(url.lastPathComponent).path, filter: "literal"))
        }
        let rules = filters.joined(separator: " ")
        let profile = "(version 1)\n(allow default)\n(deny network-outbound (remote ip \"*:*\"))\n(deny file-write* (require-any " + rules + "))\n"
        guard let file = logs.write(profile, to: "flutter-build-\(UUID().uuidString).sb") else {
            throw Self.failure("Could not save the Flutter native child protection profile.")
        }
        childProfile = file
        buildRunner = FlutterIOSBuildRunner(base: runner, profile: file)
    }

    func guarding(_ stages: [any Stage]) -> [any Stage] {
        stages.map { FlutterIOSGuardedStage(base: $0, workflow: self) }
    }

    func check() throws {
        let now = try Self.files(root, application: application, excluding: excludedSDK, aliases: directoryAliases)
        let differences = Set(original.keys).union(now.keys).filter { original[$0] != now[$0] }.sorted()
        if !differences.isEmpty {
            lock.withLock { changed = differences }
            throw Self.failure("Flutter source or lockfiles changed unexpectedly: " + differences.joined(separator: ", ") + ". No files were restored.")
        }
        guard try FlutterSDK.read(sdk.root).fingerprint == sdk.fingerprint else {
            throw Self.failure("The selected Flutter/Dart SDK identity changed. No SDK was restored or removed.")
        }
    }

    private static func files(_ root: URL, application: URL, excluding sdk: URL, aliases: [String: String]) throws -> [String: String] {
        let ignored: Set<String> = [".git", "node_modules", "Pods", "vendor", "build", ".build", ".gradle", ".dart_tool", ".mobile", "graft"]
        var failure: (any Error)?
        let physicalRoot = try physical(root.path)
        let ephemeral = URL(fileURLWithPath: try physical(application.path)).appendingPathComponent("ios/Flutter/ephemeral").path
        guard let entries = FileManager.default.enumerator(at: URL(fileURLWithPath: physicalRoot),
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            errorHandler: { _, error in failure = error; return false }) else { throw CocoaError(.fileReadNoPermission) }
        var result: [String: String] = [:]
        for case let file as URL in entries {
            if ignored.contains(file.lastPathComponent) || file.path == ephemeral {
                entries.skipDescendants(); continue
            }
            let attributes = try file.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if attributes.isSymbolicLink == true {
                entries.skipDescendants()
                var target = file.resolvingSymlinksInPath()
                target.removeAllCachedResourceValues()
                let source = try? aliasPath(file)
                guard let source, let expected = aliases[source], (try? physical(target.path)) == expected,
                      (try? target.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                    let relative = source.map { String($0.dropFirst(physicalRoot.count + 1)) } ?? file.lastPathComponent
                    throw DomainError(summary: "Unsupported source symlink: \(relative).",
                        remediation: Remediation(summary: "Prepare source and lockfiles without aliases manually. Only the selected SDK and validated generated plugin directory aliases are supported. Preserve the existing link and target; Runstir did not change either."))
                }
                result[file.path] = "link:" + (try FileManager.default.destinationOfSymbolicLink(atPath: file.path))
            } else if file.standardizedFileURL.resolvingSymlinksInPath() == sdk {
                entries.skipDescendants()
            } else if attributes.isDirectory != true {
                let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
                result[file.path] = "\(mode?.intValue ?? 0):" + SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
            }
        }
        if let failure { throw failure }
        return result
    }

    private static func physical(_ path: String) throws -> String {
        guard let pointer = realpath(path, nil) else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { free(pointer) }
        return String(cString: pointer)
    }

    private static func aliasPath(_ file: URL) throws -> String {
        URL(fileURLWithPath: try physical(file.deletingLastPathComponent().path)).appendingPathComponent(file.lastPathComponent).path
    }

    static func selection(_ value: ProjectSelection, workspace: FlutterWorkspace?) throws -> ProjectSelection {
        guard let workspace, let selected = value.selected, selected.framework == .flutter else { return value }
        let resolved = selected.resolvingWorkspace(try FolderIdentity(directory: workspace.directory))
        return ProjectSelection(directory: value.directory,
            candidates: value.candidates.map { $0.id == selected.id ? resolved : $0 }, selected: resolved,
            platform: value.platform, requiredInput: value.requiredInput, error: value.error)
    }

    static func availablePort(_ requested: Int?) throws -> Int {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(requested ?? 0).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else { throw Self.failure("The Flutter VM service port is unavailable. Stop its owning app explicitly or select another port.") }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let observed = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        guard observed == 0 else { throw POSIXError(.EIO) }
        return Int(in_port_t(bigEndian: address.sin_port))
    }

    static func failure(_ summary: String) -> DomainError {
        DomainError(summary: summary, remediation: Remediation(summary: "Inspect the exact Flutter SDK and prepared project inputs, then retry. Preserve existing source, lockfiles and SDKs."))
    }
}

private struct FlutterIOSBuildRunner: ProcessRunner {
    let base: any ProcessRunner
    let profile: URL
    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        var command = command
        if command.executable == "xcodebuild", command.arguments.last == "build" {
            command = ProcessCommand("/usr/bin/sandbox-exec", ["-f", profile.path, "/usr/bin/xcodebuild"] + command.arguments,
                environment: command.environment, workingDirectory: command.workingDirectory,
                timeout: command.timeout, output: command.output)
        }
        return try await base.run(command, onLine: onLine)
    }
    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
        throw FlutterIOSWorkflow.failure("Flutter iOS execution cannot start an untracked detached tool.")
    }
}

private struct FlutterIOSGuardedStage: Stage {
    let base: any Stage
    let workflow: FlutterIOSWorkflow
    var id: String { base.id }
    func run(_ context: inout UpContext) async throws -> StageOutcome {
        try workflow.check()
        do {
            let result = try await base.run(&context)
            try workflow.check()
            return result
        } catch {
            let original = error
            do { try workflow.check() }
            catch { if !Task.isCancelled { throw error } }
            throw original
        }
    }
}

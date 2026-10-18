import Core
import CoreFoundation
import CryptoKit
import Foundation
import Yams

/// Provider facts and executable actions. Only explicit child policy enters plan steps.
struct FlutterPreparation {
    var checks: [PreparationStep] = []
    var steps: [PreparationStep] { checks.filter { $0.kind != "reuse" } }
    var installed: [String: Bool] = [:]
    var actions: [String: InstallationAction] = [:]
    var workspace: FlutterWorkspace?
    var entrypoint: URL?
    var dependencyCommand: ProcessCommand?
    var activeEnvironment: [String: String] = [:]
    var sdk: FlutterSDK?
    var iosPluginDirectories: [String: URL] = [:]

    static func inspect(directory: URL, entrypoint: String? = nil, environment: [String: String],
                        runner: any ProcessRunner, installationRoot: URL? = nil) async throws -> Self {
        try Task.checkCancellation()
        var plan = Self()
        let project: FlutterProject
        do { project = try FlutterProject(directory: directory, entrypoint: entrypoint) }
        catch {
            plan.checks = [manual("flutter.declarations", "migration", directory.path,
                "Read valid pubspec.yaml, pubspec_overrides.yaml and exact manager declarations. Resolve Flutter declarations and the entrypoint manually; raw declaration diagnostics stay private.")]
            return plan
        }
        plan.entrypoint = project.entrypoint
        let declarationSources = [project.directory.appendingPathComponent("pubspec.yaml")] + project.pinSources
        plan.checks.append(PreparationStep(id: "flutter.declarations", platform: nil, kind: "reuse", target: project.directory.path,
            observed: "Dart \(project.dartRequirement); Flutter \(project.flutterRequirement ?? "not declared"); exact pin \(project.pinnedVersion ?? "not declared")",
            required: "preserve declared constraints and exact manager pin", source: CheckSource(tier: 1, origin: declarationSources.map(\.path).joined(separator: "; ")),
            command: nil, remediation: nil))
        let home = URL(fileURLWithPath: environment["HOME"] ?? NSHomeDirectory())
        let canonicalRoot = (installationRoot ?? home.appendingPathComponent("Library/Application Support/dev.runstir/flutter"))
            .standardizedFileURL.resolvingSymlinksInPath()
        let root = URL(fileURLWithPath: canonicalRoot.path, isDirectory: true)
        let cache = root.appendingPathComponent("pub-cache")
        var candidates: [(root: URL, allowsExecution: Bool)] = []
        if let explicit = environment["FLUTTER_ROOT"], explicit.hasPrefix("/") {
            candidates.append((URL(fileURLWithPath: explicit), true))
        }
        candidates.append((project.directory.appendingPathComponent(".fvm/flutter_sdk"), false))
        for path in (environment["PATH"] ?? "").split(separator: ":") where path.hasPrefix("/") {
            let executable = URL(fileURLWithPath: String(path)).appendingPathComponent("flutter")
            if FileManager.default.isExecutableFile(atPath: executable.path) {
                candidates.append((executable.resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent(), true))
            }
        }
        let versions = root.appendingPathComponent("versions")
        // An uncommitted exclusive-rename stage is never a reusable installation.
        candidates += ((try? FileManager.default.contentsOfDirectory(at: versions, includingPropertiesForKeys: nil)) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") }.map { ($0, true) }
        var seen: Set<String> = []
        var executionRoots: Set<String> = []
        var compatible: [FlutterSDK] = []
        for candidate in candidates {
            try Task.checkCancellation()
            let path = candidate.root.standardizedFileURL.resolvingSymlinksInPath()
            // Preserve explicit or managed selection even when .fvm found the same SDK first.
            if candidate.allowsExecution { executionRoots.insert(path.path) }
            guard seen.insert(path.path).inserted else { continue }
            if let sdk = try? FlutterSDK.read(path), project.accepts(flutter: sdk.version, dart: sdk.dartVersion) {
                compatible.append(sdk)
            }
        }
        let version = compatible.first { executionRoots.contains($0.root.path) }?.version ?? compatible.first?.version ?? project.pinnedVersion ?? "3.41.9"
        let release: FlutterRelease
        do { release = try await FlutterRelease.fetch(version: version, runner: runner) }
        catch is CancellationError { throw CancellationError() }
        catch {
            plan.checks.append(manual("flutter.sdk", "provider", root.path,
                "No unambiguous official stable arm64 Flutter/Dart release identifies \(version). Inspect the official metadata and re-plan. No latest version was selected."))
            return plan
        }
        guard project.accepts(flutter: release.version, dart: release.dartVersion) else {
            plan.checks.append(manual("flutter.sdk", "migration", root.path,
                "The exact project Flutter/Dart constraints reject \(release.version)/\(release.dartVersion). Preserve declarations and choose a compatible official exact version manually."))
            return plan
        }
        let matching = compatible.filter { $0.version == release.version && $0.dartVersion == release.dartVersion && $0.revision == release.revision }
        let selected = matching.first { executionRoots.contains($0.root.path) } ?? matching.first
        if let sdk = selected, executionRoots.contains(sdk.root.path) {
            plan.sdk = sdk
            plan.installed[sdk.root.path] = true
            plan.checks.append(PreparationStep(id: "flutter.sdk", platform: nil, kind: "reuse", target: sdk.root.path,
                observed: "Flutter \(sdk.version); Dart \(sdk.dartVersion); stable arm64; revision \(sdk.revision); SDK evidence SHA256 \(sdk.fingerprint)",
                required: release.description, source: release.source, command: nil, remediation: nil))
            plan.activeEnvironment = ["FLUTTER_ROOT": sdk.root.path]
            try await plan.inspectDependencies(project, sdk: sdk, cache: cache, runner: runner)
        } else if let sdk = selected {
            plan.checks.append(manual("flutter.sdk", "provider", sdk.root.path,
                "An SDK found only through .fvm/flutter_sdk is repository-selected. Metadata matching an official release does not authorize its Dart executable. Select a trusted SDK explicitly through FLUTTER_ROOT or PATH, then inspect again."))
            plan.checks.append(manual("flutter.workspace", "provider", project.directory.path,
                "Dart workspace inspection was not run for this automatic project SDK. Select a trusted SDK explicitly, then re-plan."))
        } else {
            do { try await plan.proposeInstall(release, root: root, runner: runner) }
            catch is CancellationError { throw CancellationError() }
            catch {
                plan.checks.append(manual("flutter.sdk", "provider", root.path,
                    "The exact official archive size could not be established. Inspect metadata and destination before approving installation."))
            }
            plan.checks.append(manual("flutter.workspace", "provider", project.directory.path,
                "After the exact SDK installation, inspect Dart's dependency workspace and native inputs again. New Android or dependency changes require a new plan approval."))
        }
        if project.entrypoint == nil {
            plan.checks.append(manual("flutter.entrypoint", "migration", project.directory.path,
                "Choose an existing Dart entrypoint inside the selected app. Setup does not create source."))
        } else {
            plan.checks.append(PreparationStep(id: "flutter.entrypoint", platform: nil, kind: "reuse", target: project.entrypoint!.path,
                observed: "existing Dart file", required: "selected app entrypoint", source: CheckSource(tier: 1, origin: project.entrypoint!.path), command: nil, remediation: nil))
        }
        for platform in [ProjectPlatform.ios, .android] {
            let native = plan.nativeChecks(project: project, platform: platform)
            plan.checks += native
        }
        return plan
    }

    private mutating func proposeInstall(_ release: FlutterRelease, root: URL, runner: any ProcessRunner) async throws {
        let destination = root.appendingPathComponent("versions/\(release.version)-arm64-\(release.revision.prefix(12))")
        installed[destination.path] = FileManager.default.fileExists(atPath: destination.path)
        let artifact = try await release.artifact(runner: runner)
        let metadata = InstallationMetadata(package: "flutter;\(release.version);stable;arm64", revision: release.revision,
            destination: destination, resourceRoot: root, artifact: artifact,
            repositoryURL: FlutterRelease.url, repositorySHA256: release.metadataSHA256,
            requiredFile: "bin/cache/dart-sdk/bin/dart", executable: true)
        var kind = "install"
        var reason = "Install only this exact SDK side by side. Preserve existing SDKs, global PATH and global Pub cache. Re-plan after SDK installation."
        do { try InstallationExecution.validateDestination(metadata) }
        catch { kind = "permission"; reason = "The exact destination is occupied or needs separate write permission. Preserve existing content and choose an absent owned destination manually." }
        var step = PreparationStep(id: "flutter.sdk", platform: nil, kind: kind, target: destination.path,
            observed: installed[destination.path] == true ? "existing destination is preserved" : "absent",
            required: release.description, source: release.source, command: nil, remediation: Remediation(summary: reason))
        step.installation = metadata
        checks.append(step)
        actions[step.id] = InstallationAction(metadata: metadata, operation: { runner, beforeCommit in
            try InstallationExecution.validateDestination(metadata)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try await InstallationExecution.installZIP(metadata, payloadRoot: "flutter", runner: runner, beforeCommit: beforeCommit) { source, _ in
                let installed = try FlutterSDK.read(source)
                guard installed.version == release.version, installed.dartVersion == release.dartVersion,
                      installed.revision == release.revision else {
                    throw InstallationExecution.failure("Extracted Flutter/Dart identity differs from the approved official release")
                }
            }
        })
    }

    private mutating func inspectDependencies(_ project: FlutterProject, sdk: FlutterSDK, cache: URL,
                                              runner: any ProcessRunner) async throws {
        guard cache.standardizedFileURL.resolvingSymlinksInPath().path == cache.path else {
            checks.append(Self.manual("dependencies.flutter", "permission", cache.path,
                "The owned Pub cache path aliases another tree. Preserve the existing cache and choose a separate real owned directory manually."))
            return
        }
        activeEnvironment["PUB_CACHE"] = cache.path
        let command = ProcessCommand(sdk.dart.path, ["pub", "--suppress-analytics", "workspace", "list", "--json"],
            environment: activeEnvironment, workingDirectory: project.directory, timeout: .seconds(30))
        do {
            let result = try await runner.run(command)
            guard result.terminationStatus.isSuccess else {
                throw InstallationExecution.failure("Dart could not resolve the declared workspace. Inspect pubspec_overrides.yaml and workspace declarations manually.")
            }
            let workspace = try project.workspace(from: Data(result.standardOutput.utf8))
            self.workspace = workspace
            guard workspace.accepts(flutter: sdk.version, dart: sdk.dartVersion) else {
                throw InstallationExecution.failure("A workspace package rejects the selected exact Flutter/Dart SDK")
            }
            guard workspace.migrationFiles.isEmpty else {
                checks.append(Self.manual("dependencies.flutter", "migration", workspace.directory.path,
                    "Pub would remove member or ancestor lock/package_config files. Preserve and reconcile these files manually: \(workspace.migrationFiles.joined(separator: ", "))"))
                return
            }
            let generatedAliases = workspace.packages.flatMap { package in
                [".dart_tool", ".dart_tool/pub", ".dart_tool/package_config.json", ".dart_tool/package_graph.json"].compactMap { relative -> String? in
                    let path = package.appendingPathComponent(relative).standardizedFileURL
                    return path.resolvingSymlinksInPath().path == path.path ? nil : path.path
                }
            }
            guard generatedAliases.isEmpty else {
                checks.append(Self.manual("dependencies.flutter", "migration", workspace.directory.path,
                    "Pub output paths alias another location. Preserve those links and files, then prepare independent generated paths manually: \(generatedAliases.joined(separator: ", "))"))
                return
            }
            let lock = workspace.directory.appendingPathComponent("pubspec.lock")
            guard (try? lock.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                checks.append(Self.manual("dependencies.flutter", "migration", workspace.directory.path,
                    "The dependency workspace needs its existing pubspec.lock. Setup does not create a lockfile or upgrade dependency versions."))
                return
            }
            let alignment = ProcessCommand(sdk.dart.path, ["pub", "--suppress-analytics", "get", "--enforce-lockfile"],
                environment: activeEnvironment, workingDirectory: workspace.directory, timeout: .seconds(1800))
            dependencyCommand = alignment
            var step = PreparationStep(id: "dependencies.flutter", platform: nil, kind: "align", target: cache.path,
                observed: "workspace: \(workspace.directory.path); \(workspace.packages.count) packages; existing pubspec.lock",
                required: "bundled Dart locked alignment; preserve source and lockfiles", source: CheckSource(tier: 1, origin: lock.path),
                command: alignment.description, remediation: Remediation(summary: "Run the approved locked command in this exact dependency workspace. Native generated inputs and app execution have separate checks."))
            step.environment = activeEnvironment
            checks.append(step)
            installed[cache.path] = FileManager.default.fileExists(atPath: cache.path)
            installed[workspace.directory.appendingPathComponent(".dart_tool/package_config.json").path] = FileManager.default.fileExists(atPath: workspace.directory.appendingPathComponent(".dart_tool/package_config.json").path)
        } catch is CancellationError { throw CancellationError() }
        catch {
            checks.append(Self.manual("flutter.workspace", "migration", project.directory.path,
                "Dart workspace inspection could not establish a safe locked alignment. Inspect workspace declarations, package SDK constraints and pubspec_overrides.yaml manually. Raw tool diagnostics stay private."))
        }
    }

    private mutating func nativeChecks(project: FlutterProject, platform: ProjectPlatform) -> [PreparationStep] {
        let directory = project.directory.appendingPathComponent(platform.rawValue)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            let generatedModule = project.directory.appendingPathComponent("." + platform.rawValue)
            if FileManager.default.fileExists(atPath: generatedModule.path) {
                return [Self.manual("\(platform.rawValue).flutter.host", "migration", generatedModule.path,
                    "An existing generated Flutter module host (.\(platform.rawValue)) is outside this app-host preparation route. Preserve it and prepare the module's declared native host manually; setup does not reroute or regenerate it.", platform: platform)]
            }
            return [Self.manual("\(platform.rawValue).flutter.host", "migration", directory.path,
                "No \(platform.rawValue) host source exists. Prepare native host source manually; setup never runs flutter create.", platform: platform)]
        }
        guard let sdk else {
            return [Self.manual("\(platform.rawValue).flutter.generated", "provider", directory.path,
                "Inspect generated native inputs and engine artifacts after the exact SDK is available.", platform: platform)]
        }
        var issues: [String] = []
        let engine = sdk.root.appendingPathComponent("bin/cache/artifacts/engine/\(platform == .ios ? "ios/Flutter.xcframework/Info.plist" : "android-arm64/flutter.jar")")
        if (try? engine.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) != true {
            issues.append("selected SDK has no \(platform.rawValue) debug engine artifact marker")
        }
        if let issue = pluginMetadataIssue(project: project, sdk: sdk, platform: platform) { issues.append(issue) }
        if platform == .ios {
            let file = directory.appendingPathComponent("Flutter/Generated.xcconfig")
            let values = properties(file)
            if !pathMatches(values["FLUTTER_ROOT"], sdk.root, relativeTo: directory)
                || !pathMatches(values["FLUTTER_APPLICATION_PATH"], project.directory, relativeTo: directory)
                || !pathMatches(values["FLUTTER_TARGET"], project.entrypoint, relativeTo: project.directory) {
                issues.append("Generated.xcconfig does not identify this SDK, app and entrypoint")
            }
        } else if !pathMatches(properties(directory.appendingPathComponent("local.properties"))["flutter.sdk"], sdk.root, relativeTo: directory) {
            issues.append("android/local.properties does not identify this Flutter SDK")
        }
        let id = "\(platform.rawValue).flutter.generated"
        let generated = PreparationStep(id: id, platform: platform, kind: issues.isEmpty ? "reuse" : "provider", target: directory.path,
            observed: issues.isEmpty ? "existing debug engine marker and generated native input paths match selected Flutter/Dart and package paths" : issues.joined(separator: "; "),
            required: "existing matching native generated inputs; no source migration", source: CheckSource(tier: 1, origin: directory.path), command: nil,
            remediation: issues.isEmpty ? nil : Remediation(summary: "Prepare only the listed missing or stale generated inputs with the exact SDK manually. Preserve source and lockfiles, then inspect again. Locked Dart alignment alone does not establish native preparation."))
        return [generated]
    }

    private mutating func pluginMetadataIssue(project: FlutterProject, sdk: FlutterSDK, platform: ProjectPlatform) -> String? {
        if platform == .ios { iosPluginDirectories = [:] }
        let unknown = "plugin metadata cannot be confirmed from the current resolved package graph and package manifests"
        func json(_ file: URL) -> [String: Any]? {
            (try? JSONSerialization.jsonObject(with: Data(contentsOf: file))) as? [String: Any]
        }
        func jsonBoolean(_ value: Any?, missing: Bool? = nil) -> Bool? {
            guard let value else { return missing }
            // JSON numbers 0 and 1 also bridge to Bool; accept only JSON booleans.
            guard let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
            return value.boolValue
        }
        func manifest(_ root: URL) -> [String: Any]? {
            guard let text = try? String(contentsOf: root.appendingPathComponent("pubspec.yaml"), encoding: .utf8),
                  let resolver = try? Resolver.default.replacing(.bool, with: "^(?:true|True|TRUE|false|False|FALSE)$") else { return nil }
            var scalars = Constructor.defaultScalarMap
            // Explicit !!bool tags also use Dart's six canonical Boolean spellings.
            scalars[.bool] = { scalar in
                switch scalar.string {
                case "true", "True", "TRUE": return true
                case "false", "False", "FALSE": return false
                default: return nil
                }
            }
            return (try? Yams.load(yaml: text, resolver, Constructor(scalars))) as? [String: Any]
        }
        func names(_ value: Any?) -> Set<String>? {
            guard let value, !(value is NSNull) else { return [] }
            guard let map = value as? [String: Any] else { return nil }
            return Set(map.keys)
        }
        guard let workspace,
              let config = json(workspace.directory.appendingPathComponent(".dart_tool/package_config.json")),
              config["configVersion"] as? Int == 2, let packages = config["packages"] as? [[String: Any]],
              let graph = json(workspace.directory.appendingPathComponent(".dart_tool/package_graph.json")),
              graph["configVersion"] as? Int == 1, let graphRoots = graph["roots"] as? [String],
              let graphPackages = graph["packages"] as? [[String: Any]],
              let app = manifest(project.directory), let appName = app["name"] as? String else { return unknown }
        var roots: [String: URL] = [:]
        for package in packages {
            guard let name = package["name"] as? String, let uri = package["rootUri"] as? String,
                  let url = URL(string: uri, relativeTo: workspace.directory.appendingPathComponent(".dart_tool/"))?.absoluteURL,
                  url.isFileURL, url.query == nil, url.fragment == nil, roots[name] == nil else { return unknown }
            roots[name] = url.standardizedFileURL.resolvingSymlinksInPath()
        }
        guard roots["flutter"]?.path == sdk.root.appendingPathComponent("packages/flutter").standardizedFileURL.resolvingSymlinksInPath().path,
              roots[appName]?.path == project.directory.path, graphRoots.contains(appName) else { return unknown }
        var edges: [String: [String]] = [:]
        var devEdges: [String: [String]] = [:]
        for package in graphPackages {
            let dev = package["devDependencies"]
            guard let name = package["name"] as? String, edges[name] == nil,
                  let dependencies = package["dependencies"] as? [String],
                  dev == nil || dev is NSNull || dev is [String] else { return unknown }
            edges[name] = dependencies
            devEdges[name] = dev as? [String] ?? []
        }
        // Use Pub's resolved graph. Only the selected app's dev dependencies
        // participate; another workspace app does not supply this app's plugins.
        var pending = [appName]
        var visited: Set<String> = []
        var hasPlugins = false
        var expected: [String: (root: URL, native: Bool, shared: Bool)] = [:]
        while let name = pending.popLast() {
            if !visited.insert(name).inserted { continue }
            guard let root = roots[name], let document = manifest(root), document["name"] as? String == name,
                  let dependencies = names(document["dependencies"]), let resolved = edges[name],
                  dependencies == Set(resolved) else { return unknown }
            pending += resolved
            if name == appName {
                guard let dev = names(document["dev_dependencies"]), let resolvedDev = devEdges[name], dev == Set(resolvedDev) else { return unknown }
                pending += resolvedDev
            }
            guard let flutterValue = document["flutter"] else { continue }
            guard let flutter = flutterValue as? [String: Any] else { return unknown }
            guard let pluginValue = flutter["plugin"] else { continue }
            guard let plugin = pluginValue as? [String: Any], plugin["implements"] == nil,
                  let platforms = plugin["platforms"] as? [String: Any], !platforms.isEmpty,
                  platforms.values.allSatisfy({ value in
                      guard let declaration = value as? [String: Any] else { return false }
                      return declaration["default_package"] == nil
                  }) else {
                return "plugin metadata requires manual resolution of legacy or federated plugin declarations with the exact Flutter SDK"
            }
            hasPlugins = true
            guard let platformValue = platforms[platform.rawValue] else { continue }
            guard let implementation = platformValue as? [String: Any] else { return unknown }
            for key in ["pluginClass", "dartPluginClass"] where implementation[key] != nil {
                guard let value = implementation[key] as? String, !value.isEmpty else { return unknown }
            }
            for key in ["ffiPlugin", "sharedDarwinSource"] where implementation[key] != nil {
                guard implementation[key] is Bool else { return unknown }
            }
            let native = implementation["pluginClass"] != nil || implementation["ffiPlugin"] as? Bool == true
            guard native || implementation["dartPluginClass"] != nil else { return unknown }
            expected[name] = (root, native, implementation["sharedDarwinSource"] as? Bool == true)
        }
        let file = project.directory.appendingPathComponent(".flutter-plugins-dependencies")
        if !FileManager.default.fileExists(atPath: file.path),
           (try? FileManager.default.destinationOfSymbolicLink(atPath: file.path)) == nil {
            // Flutter deletes this generated file when findPlugins returns empty.
            return hasPlugins ? "plugin metadata is missing for reachable Flutter plugins" : nil
        }
        guard let metadata = json(file), metadata["version"] as? String == sdk.version,
              let plugins = metadata["plugins"] as? [String: Any], let selected = plugins[platform.rawValue] as? [[String: Any]],
              selected.count == expected.count else { return unknown }
        if !hasPlugins, !plugins.values.allSatisfy({ ($0 as? [[String: Any]])?.isEmpty == true }) { return unknown }
        var seen: Set<String> = []
        for plugin in selected {
            guard let name = plugin["name"] as? String, seen.insert(name).inserted,
                  let path = plugin["path"] as? String, path.hasPrefix("/"), let required = expected[name],
                  URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path == required.root.path,
                  jsonBoolean(plugin["native_build"]) == required.native,
                  jsonBoolean(plugin["shared_darwin_source"], missing: false) == required.shared else { return unknown }
        }
        if platform == .ios { iosPluginDirectories = expected.filter { $0.value.native }.mapValues(\.root) }
        return nil
    }

    private func properties(_ file: URL) -> [String: String] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [:] }
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 { values[String(parts[0]).trimmingCharacters(in: .whitespaces)] = String(parts[1]).trimmingCharacters(in: .whitespaces) }
        }
        return values
    }

    private func pathMatches(_ value: String?, _ expected: URL?, relativeTo root: URL) -> Bool {
        guard let value, let expected, !value.contains("$("), !value.isEmpty else { return false }
        return URL(fileURLWithPath: value, relativeTo: root).standardizedFileURL.resolvingSymlinksInPath() == expected
    }

    private static func manual(_ id: String, _ kind: String, _ target: String, _ reason: String,
                               platform: ProjectPlatform? = nil) -> PreparationStep {
        PreparationStep(id: id, platform: platform, kind: kind, target: target, observed: reason, required: "exact verified Flutter preparation inputs",
            source: CheckSource(tier: 1, origin: "Flutter project and SDK declarations"), command: nil, remediation: Remediation(summary: reason))
    }
}

struct FlutterRelease: Sendable {
    static let url = URL(string: "https://storage.googleapis.com/flutter_infra_release/releases/releases_macos.json")!
    static let base = "https://storage.googleapis.com/flutter_infra_release/releases"
    static let command = ProcessCommand("curl", ["--fail", "--silent", "--show-error", "--location", "--proto", "=https", "--proto-redir", "=https", "--max-redirs", "3", "--connect-timeout", "15", "--max-time", "30", "--max-filesize", "4194304", url.absoluteString], timeout: .seconds(40))
    let version: String
    let dartVersion: String
    let revision: String
    let archive: URL
    let checksum: String
    let metadataSHA256: String
    var source: CheckSource { CheckSource(tier: 1, origin: "\(Self.url.absoluteString); metadata SHA256 \(metadataSHA256)") }
    var description: String { "Flutter \(version); Dart \(dartVersion); stable arm64; revision \(revision); \(archive.absoluteString); SHA256 \(checksum)" }

    static func fetch(version: String, runner: any ProcessRunner) async throws -> Self {
        let result = try await runner.run(command)
        guard result.terminationStatus.isSuccess else { throw InstallationExecution.failure("Official Flutter release metadata could not be read") }
        return try Self(data: Data(result.standardOutput.utf8), version: version)
    }

    init(data: Data, version: String) throws {
        guard SemanticVersion(version)?.description == version,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], object["base_url"] as? String == Self.base,
              let releases = object["releases"] as? [[String: Any]] else { throw InstallationExecution.failure("Invalid official Flutter release metadata") }
        let matching = releases.filter { $0["version"] as? String == version && $0["channel"] as? String == "stable" && $0["dart_sdk_arch"] as? String == "arm64" }
        guard matching.count == 1, let entry = matching.first,
              let dart = entry["dart_sdk_version"] as? String, SemanticVersion(dart)?.description == dart,
              let revision = entry["hash"] as? String, revision.range(of: #"^[0-9a-f]{40}$"#, options: .regularExpression) != nil,
              let checksum = entry["sha256"] as? String, checksum.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil,
              entry["archive"] as? String == "stable/macos/flutter_macos_arm64_\(version)-stable.zip" else {
            throw InstallationExecution.failure("An exact stable arm64 Flutter release and bundled Dart identity are required")
        }
        self.version = version; dartVersion = dart; self.revision = revision; self.checksum = checksum
        archive = URL(string: Self.base + "/stable/macos/flutter_macos_arm64_\(version)-stable.zip")!
        metadataSHA256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func artifact(runner: any ProcessRunner) async throws -> InstallationArtifact {
        let command = ProcessCommand("curl", ["--fail", "--silent", "--show-error", "--head", "--proto", "=https", "--connect-timeout", "15", "--max-time", "30", archive.absoluteString], timeout: .seconds(40))
        let result = try await runner.run(command)
        let lengths = result.standardOutput.split(whereSeparator: \.isNewline).compactMap { line -> Int64? in
            let pair = line.split(separator: ":", maxSplits: 1)
            guard pair.count == 2, pair[0].lowercased() == "content-length" else { return nil }
            return Int64(pair[1].trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard result.terminationStatus.isSuccess, lengths.count == 1, let size = lengths.first, size > 0 else {
            throw InstallationExecution.failure("Official Flutter archive size is unavailable; inspect before approval")
        }
        return InstallationArtifact(url: archive, checksumAlgorithm: "sha256", checksum: checksum, size: size)
    }
}

struct FlutterSDK: Sendable {
    let root: URL
    let version: String
    let dartVersion: String
    let revision: String
    let fingerprint: String
    var dart: URL { root.appendingPathComponent("bin/cache/dart-sdk/bin/dart") }

    /// Never runs bin/flutter, which may bootstrap, download, update or rewrite cache files.
    static func read(_ root: URL) throws -> Self {
        let manager = FileManager.default
        let versionFile = root.appendingPathComponent("bin/cache/flutter.version.json")
        let data = try Data(contentsOf: versionFile)
        let dartFile = root.appendingPathComponent("bin/cache/dart-sdk/version")
        let dartData = try Data(contentsOf: dartFile)
        let dartVersion = String(decoding: dartData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = value["frameworkVersion"] as? String, SemanticVersion(version)?.description == version,
              value["channel"] as? String == "stable", value["dartSdkVersion"] as? String == dartVersion,
              SemanticVersion(dartVersion)?.description == dartVersion,
              let revision = value["frameworkRevision"] as? String, revision.range(of: #"^[0-9a-f]{40}$"#, options: .regularExpression) != nil else {
            throw InstallationExecution.failure("Existing Flutter SDK metadata is incomplete or inconsistent")
        }
        let binary = root.appendingPathComponent("bin/cache/dart-sdk/bin/dart")
        let snapshot = root.appendingPathComponent("bin/cache/flutter_tools.snapshot")
        for file in [binary, snapshot, root.appendingPathComponent("bin/flutter")] {
            let canonical = file.standardizedFileURL.resolvingSymlinksInPath()
            guard canonical.path.hasPrefix(root.path + "/"),
                  try canonical.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true,
                  file == snapshot || manager.isExecutableFile(atPath: file.path) else {
                throw InstallationExecution.failure("Existing Flutter SDK is incomplete; setup never bootstraps it in place")
            }
        }
        let binaryData = try Data(contentsOf: binary, options: .mappedIfSafe)
        guard binaryData.count >= 8, Array(binaryData.prefix(4)) == [0xcf, 0xfa, 0xed, 0xfe],
              Array(binaryData[4..<8]) == [0x0c, 0, 0, 1] else {
            throw InstallationExecution.failure("The bundled Dart executable is not an arm64 macOS SDK")
        }
        var digest = SHA256()
        let contents = [data, dartData, binaryData, try Data(contentsOf: snapshot, options: .mappedIfSafe),
                        try Data(contentsOf: root.appendingPathComponent("bin/flutter"), options: .mappedIfSafe)]
        for (index, file) in contents.enumerated() {
            digest.update(data: Data("\(index):\(file.count):".utf8))
            digest.update(data: Data(SHA256.hash(data: file)))
        }
        return Self(root: root, version: version, dartVersion: dartVersion, revision: revision,
            fingerprint: digest.finalize().map { String(format: "%02x", $0) }.joined())
    }
}

/// Exact Flutter selection is child policy; host probes keep their original runner.
struct FlutterChildRunner: ProcessRunner {
    let base: any ProcessRunner
    let environment: [String: String]
    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        var selected = command
        selected.environment.merge(environment) { _, exact in exact }
        return try await base.run(selected, onLine: onLine)
    }
    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
        throw InstallationExecution.failure("Flutter preparation cannot start runtime processes")
    }
}

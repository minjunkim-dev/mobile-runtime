import Core
@testable import EnvironmentKit
import Foundation
import SimulatorKit
import TestSupport
import Testing

@Suite("Flutter preparation")
struct FlutterPreparationTests {
    @Test("an automatically discovered project SDK never runs before approval", arguments: [false, true], ["plan", "unapproved", "stale"])
    func automaticProjectSDKDoesNotRun(externalSDK: Bool, mode: String) async throws {
        let fixture = try FlutterFixture()
        let outside = try FixtureRepo()
        try FlutterFixture.sdk(repo: outside, at: "sdk")
        let sdk = externalSDK ? outside.url("sdk") : fixture.repo.url("sdk")
        try fixture.repo.directory(".fvm")
        try FileManager.default.createSymbolicLink(at: fixture.repo.url(".fvm/flutter_sdk"), withDestinationURL: sdk)
        var environment = fixture.environment
        environment["FLUTTER_ROOT"] = nil
        environment["PATH"] = ""
        var runner = fixture.runner()
        runner.responses["xcode-select -p"] = .failed(1, "No Xcode in fixture")
        let result = await PreparationExecution.run(
            input: ProjectInspectionInput(directory: fixture.repo.root, environment: environment, platform: .android),
            planOnly: mode == "plan", approvedPlanID: mode == "stale" ? "stale-plan" : nil, runner: runner)
        #expect(!runner.log.all.contains { $0.executable.hasPrefix(sdk.path + "/") })
        #expect(!runner.log.all.contains { $0.arguments == ["pub", "--suppress-analytics", "workspace", "list", "--json"] })
        #expect(result.plan?.steps.contains { $0.id == "flutter.workspace" && $0.kind != "reuse" } == true)
        #expect(result.plan?.steps.contains { $0.id == "dependencies.flutter" && $0.kind == "align" } == false)
        #expect(result.operation.completed.isEmpty)
        withExtendedLifetime(outside) {}
    }

    @Test("an explicit selection authorizes the same SDK also discovered through fvm", arguments: ["FLUTTER_ROOT", "PATH"])
    func explicitProjectSDKSelection(source: String) async throws {
        let fixture = try FlutterFixture()
        let sdk = fixture.repo.url("sdk")
        try fixture.repo.directory(".fvm")
        try FileManager.default.createSymbolicLink(at: fixture.repo.url(".fvm/flutter_sdk"), withDestinationURL: sdk)
        var environment = fixture.environment
        environment["FLUTTER_ROOT"] = source == "FLUTTER_ROOT" ? sdk.path : nil
        environment["PATH"] = source == "PATH" ? sdk.appendingPathComponent("bin").path : ""
        let runner = fixture.runner()
        let plan = try await FlutterPreparation.inspect(directory: fixture.repo.root, environment: environment, runner: runner)
        #expect(runner.log.all.filter { $0.description == fixture.workspaceCommand }.count == 1)
        #expect(plan.sdk?.root == sdk)
        #expect(plan.dependencyCommand != nil)
        #expect(!plan.checks.contains { $0.id == "flutter.workspace" && $0.kind != "reuse" })
    }

    @Test("an explicit PATH SDK takes priority over a different fvm SDK of the same release")
    func explicitAlternativeSDKSelection() async throws {
        let fixture = try FlutterFixture()
        try FlutterFixture.sdk(repo: fixture.repo, at: "explicit-sdk")
        let sdk = fixture.repo.url("explicit-sdk")
        try fixture.repo.directory(".fvm")
        try FileManager.default.createSymbolicLink(at: fixture.repo.url(".fvm/flutter_sdk"), withDestinationURL: fixture.repo.url("sdk"))
        var environment = fixture.environment
        environment["FLUTTER_ROOT"] = nil
        environment["PATH"] = sdk.appendingPathComponent("bin").path
        var runner = fixture.runner()
        let command = ProcessCommand(sdk.appendingPathComponent("bin/cache/dart-sdk/bin/dart").path,
            ["pub", "--suppress-analytics", "workspace", "list", "--json"])
        runner.responses[command.description] = runner.responses[fixture.workspaceCommand]
        let plan = try await FlutterPreparation.inspect(directory: fixture.repo.root, environment: environment, runner: runner)
        #expect(plan.sdk?.root == sdk)
        #expect(plan.dependencyCommand != nil)
        #expect(runner.log.all.filter { $0.description == command.description }.count == 1)
        #expect(!runner.log.all.contains { $0.executable.hasPrefix(fixture.repo.url("sdk").path + "/") })
    }

    @Test("an explicit compatible SDK selects its own release before an automatic fvm SDK", arguments: ["automatic", "absent", "pinned"])
    func explicitSDKVersionPriority(_ mode: String) async throws {
        let fixture = try FlutterFixture()
        try FlutterFixture.sdk(repo: fixture.repo, at: "explicit-sdk", version: "3.47.2")
        let sdk = fixture.repo.url("explicit-sdk")
        if mode != "absent" {
            try fixture.repo.directory(".fvm")
            try FileManager.default.createSymbolicLink(at: fixture.repo.url(".fvm/flutter_sdk"), withDestinationURL: fixture.repo.url("sdk"))
        }
        if mode == "pinned" { try fixture.repo.write(".fvmrc", #"{"flutter":"3.41.9"}"#) }
        var environment = fixture.environment
        environment["FLUTTER_ROOT"] = nil
        environment["PATH"] = sdk.appendingPathComponent("bin").path
        var runner = fixture.runner()
        var metadata = try #require(JSONSerialization.jsonObject(with: FlutterFixture.releaseMetadata()) as? [String: Any])
        var releases = try #require(metadata["releases"] as? [[String: Any]])
        var release = releases[0]
        release["version"] = "3.47.2"
        release["archive"] = "stable/macos/flutter_macos_arm64_3.47.2-stable.zip"
        releases.append(release)
        metadata["releases"] = releases
        runner.responses[FlutterRelease.command.description] = .ok(String(decoding: try JSONSerialization.data(withJSONObject: metadata), as: UTF8.self))
        let command = ProcessCommand(sdk.appendingPathComponent("bin/cache/dart-sdk/bin/dart").path,
            ["pub", "--suppress-analytics", "workspace", "list", "--json"])
        runner.responses[command.description] = runner.responses[fixture.workspaceCommand]
        let project = try FlutterProject(directory: fixture.repo.root)
        #expect(project.accepts(flutter: "3.41.9", dart: "3.11.5"))
        #expect(project.accepts(flutter: "3.47.2", dart: "3.11.5") == (mode != "pinned"))
        let plan = try await FlutterPreparation.inspect(directory: fixture.repo.root, environment: environment, runner: runner)
        #expect((plan.sdk?.root == sdk) == (mode != "pinned"))
        #expect((plan.dependencyCommand != nil) == (mode != "pinned"))
        #expect(runner.log.all.filter { $0.description == command.description }.count == (mode == "pinned" ? 0 : 1))
        #expect(!runner.log.all.contains { $0.executable.hasPrefix(fixture.repo.url("sdk").path + "/") })
    }

    @Test("Flutter inspection never evaluates a Gemfile before exact approval and trust", arguments: ["plan", "unapproved", "stale"])
    func bundledPodsDoNotRunBeforeApproval(_ mode: String) async throws {
        let fixture = try FlutterFixture()
        let runner = try podTools(fixture, bundled: true)
        try fixture.repo.write("ios/Podfile.lock", "locked pods")
        let result = await PreparationExecution.run(
            input: ProjectInspectionInput(directory: fixture.repo.root, environment: fixture.environment),
            planOnly: mode == "plan", approvedPlanID: mode == "stale" ? "stale-plan" : nil,
            runner: runner, leases: ResourceLeases(directory: fixture.repo.url(".mobile/leases")))
        #expect(!runner.log.all.contains { $0.arguments.starts(with: ["exec", "pod"]) })
        #expect(!runner.log.all.contains { $0.arguments.contains("-rbundler") })
        #expect(result.plan?.steps.contains { $0.id == "ios.cocoapods.version" && $0.kind == "provider" } == true)
        #expect(result.plan?.steps.first { $0.id == "dependencies.pods" }?.kind == "migration")
        #expect(result.operation.completed.isEmpty)
    }

    @Test("Pub graph permits omitted or null transitive dev dependencies but rejects malformed values", arguments: ["absent", "null", "empty", "string", "number", "element"])
    func transitiveDevDependencies(_ mode: String) async throws {
        let f = try FlutterFixture()
        let file = f.repo.url(".dart_tool/package_graph.json")
        var graph = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        var packages = try #require(graph["packages"] as? [[String: Any]])
        switch mode {
        case "absent": packages[1].removeValue(forKey: "devDependencies")
        case "null": packages[1]["devDependencies"] = NSNull()
        case "string": packages[1]["devDependencies"] = "[]"
        case "number": packages[1]["devDependencies"] = 0
        case "element": packages[1]["devDependencies"] = [1]
        default: break
        }
        graph["packages"] = packages
        try JSONSerialization.data(withJSONObject: graph).write(to: file)
        let plan = try await f.inspect(f.runner())
        let reuse = ["absent", "null", "empty"].contains(mode)
        for platform in ["ios", "android"] {
            let generated = try #require(plan.checks.first { $0.id == "\(platform).flutter.generated" })
            #expect((generated.kind == "reuse") == reuse)
        }
    }

    @Test("the selected app's current dev dependency keys must still match the resolved graph")
    func selectedDevDependenciesRemainExact() async throws {
        let f = try FlutterFixture()
        let original = try String(contentsOf: f.repo.url("pubspec.yaml"), encoding: .utf8)
        try f.repo.write("pubspec.yaml", original + "dev_dependencies:\n  missing_from_graph: any\n")
        let plan = try await f.inspect(f.runner())
        for platform in ["ios", "android"] {
            #expect(plan.checks.contains { $0.id == "\(platform).flutter.generated" && $0.kind != "reuse" })
        }
    }

    @Test("shared Darwin metadata accepts only an absent field or a matching JSON Boolean", arguments: ["absent", "false", "true", "stringFalse", "numberZero", "numberOne", "null"])
    func sharedDarwinMetadata(_ mode: String) async throws {
        let shared = mode == "true" || mode == "numberOne"
        let f = try pluginFixture("pluginClass: FixturePlugin\nsharedDarwinSource: \(shared)")
        var value: Any?
        switch mode {
        case "false": value = false
        case "true": value = true
        case "stringFalse": value = "false"
        case "numberZero": value = 0
        case "numberOne": value = 1
        case "null": value = NSNull()
        default: break
        }
        try pluginMetadata(f, nativeBuild: true, shared: value)
        let plan = try await f.inspect(f.runner())
        let generated = try #require(plan.checks.first { $0.id == "ios.flutter.generated" })
        #expect((generated.kind == "reuse") == ["absent", "false", "true"].contains(mode))
        #expect(plan.checks.contains { $0.id == "android.flutter.generated" && $0.kind == "reuse" })
    }

    @Test("native build metadata requires an actual JSON Boolean", arguments: ["false", "true", "zero", "one", "string", "null", "absent"])
    func nativeBuildMetadata(_ mode: String) async throws {
        let native = mode == "true" || mode == "one"
        let f = try pluginFixture(native ? "pluginClass: FixturePlugin" : "dartPluginClass: FixturePlugin")
        let values: [String: Any] = ["false": false, "true": true, "zero": 0, "one": 1, "string": "false", "null": NSNull()]
        try pluginMetadata(f, nativeBuild: values[mode])
        let plan = try await f.inspect(f.runner())
        let generated = try #require(plan.checks.first { $0.id == "ios.flutter.generated" })
        #expect((generated.kind == "reuse") == ["false", "true"].contains(mode))
    }

    @Test("plugin flags use Dart YAML Boolean scalars, quotes, aliases and explicit tags", arguments: ["ffiPlugin", "sharedDarwinSource"], ["true", "True", "TRUE", "false", "False", "FALSE", "on", "yes", "off", "no", "\"true\"", "0", "!!bool true", "!!bool \"true\"", "!!bool on", "!!str true", "! true", "!fixture true", "booleanAlias", "stringAlias"])
    func pluginYAMLBooleans(_ field: String, _ scalar: String) async throws {
        let alias = scalar.hasSuffix("Alias")
        let anchor = alias ? "flag: &flag \(scalar == "booleanAlias" ? "true" : "\"true\"")\n" : ""
        let value = alias ? "*flag" : scalar
        let truth = ["true", "True", "TRUE", "on", "yes", "!!bool true", "!!bool \"true\"", "!!bool on", "booleanAlias"].contains(scalar)
        let f = try pluginFixture("dartPluginClass: FixturePlugin\n\(field): \(value)", anchor: anchor)
        try pluginMetadata(f, nativeBuild: field == "ffiPlugin" && truth, shared: field == "sharedDarwinSource" && truth)
        let plan = try await f.inspect(f.runner())
        let generated = try #require(plan.checks.first { $0.id == "ios.flutter.generated" })
        let valid = ["true", "True", "TRUE", "false", "False", "FALSE", "!!bool true", "!!bool \"true\"", "booleanAlias"].contains(scalar)
        #expect((generated.kind == "reuse") == valid)
    }

    private func pluginFixture(_ ios: String, anchor: String = "") throws -> FlutterFixture {
        let f = try FlutterFixture()
        let original = try String(contentsOf: f.repo.url("pubspec.yaml"), encoding: .utf8)
        try f.repo.write("pubspec.yaml", original + "  foo: any\n")
        let fields = ios.split(separator: "\n").map { "        " + $0 }.joined(separator: "\n")
        try f.repo.write("packages/foo/pubspec.yaml", "name: foo\n\(anchor)flutter:\n  plugin:\n    platforms:\n      ios:\n\(fields)\n      android:\n        package: dev.fixture\n        pluginClass: FixturePlugin\n")
        let packages = [["name": "example", "rootUri": f.repo.root.absoluteString],
                        ["name": "flutter", "rootUri": f.repo.url("sdk/packages/flutter").absoluteString],
                        ["name": "foo", "rootUri": f.repo.url("packages/foo").absoluteString]]
        try JSONSerialization.data(withJSONObject: ["configVersion": 2, "packages": packages]).write(to: f.repo.url(".dart_tool/package_config.json"))
        let graph: [[String: Any]] = [["name": "example", "dependencies": ["flutter", "foo"], "devDependencies": []],
                                     ["name": "flutter", "dependencies": []], ["name": "foo", "dependencies": []]]
        try JSONSerialization.data(withJSONObject: ["configVersion": 1, "roots": ["example"], "packages": graph]).write(to: f.repo.url(".dart_tool/package_graph.json"))
        return f
    }

    private func pluginMetadata(_ f: FlutterFixture, nativeBuild: Any?, shared: Any? = nil) throws {
        var ios: [String: Any] = ["name": "foo", "path": f.repo.url("packages/foo").path]
        if let nativeBuild { ios["native_build"] = nativeBuild }
        if let shared { ios["shared_darwin_source"] = shared }
        let android: [String: Any] = ["name": "foo", "path": f.repo.url("packages/foo").path, "native_build": true]
        try JSONSerialization.data(withJSONObject: ["version": "3.41.9", "plugins": ["ios": [ios], "android": [android]]]).write(to: f.repo.url(".flutter-plugins-dependencies"))
    }

    @Test("an existing compatible Flutter SDK plans locked alignment for both platforms")
    func compatibleSDK() async throws {
        let fixture = try FlutterFixture()
        var runner = fixture.runner()
        runner.responses["xcode-select -p"] = .failed(1, "No Xcode in fixture")
        let input = ProjectInspectionInput(directory: fixture.repo.root, environment: fixture.environment, platform: .android)
        let result = await PreparationExecution.run(input: input, planOnly: true, runner: runner)
        let plan = try #require(result.plan)
        #expect(plan.projectKind == "flutter")
        #expect(plan.platforms.map(\.platform) == [.ios, .android])
        #expect(plan.platforms.flatMap(\.checks).contains { $0.id == "flutter.sdk" && $0.kind == "reuse" })
        #expect(plan.steps.contains { $0.id == "dependencies.flutter" && $0.kind == "align" })
        #expect(!runner.log.all.contains { $0.arguments.contains("get") })
        #expect(!runner.log.all.contains { $0.executable.hasSuffix("/bin/flutter") })
    }
    @Test("SDK installation preserves a newly discovered unapproved locked alignment")
    func newlyDiscoveredAlignmentNeedsApproval() async throws {
        let (f, bytes) = try await FlutterInstallationTests().payload()
        let managed = f.repo.url("home/Library/Application Support/dev.runstir/flutter")
        let runner = FlutterPayloadRunner(data: bytes, directory: f.repo.root, installationRoot: managed)
        let input = ProjectInspectionInput(directory: f.repo.root, environment: f.environment)
        let leases = ResourceLeases(directory: f.repo.url(".mobile/leases"))
        let before = await PreparationExecution.run(input: input, planOnly: true, runner: runner, leases: leases)
        let plan = try #require(before.plan)
        #expect(plan.steps.contains { $0.id == "flutter.sdk" && $0.kind == "install" })
        #expect(!plan.steps.contains { $0.id == "dependencies.flutter" && $0.kind == "align" })
        let result = await PreparationExecution.run(input: input, approvedPlanID: plan.id, runner: runner, leases: leases)
        #expect(result.operation.error == nil)
        #expect(result.operation.completed == ["flutter.sdk"])
        #expect(result.operation.remaining.contains("dependencies.flutter"))
        #expect(result.plan?.steps.contains { $0.id == "dependencies.flutter" && $0.kind == "align" } == true)
        #expect(result.operation.state == "partial")
        #expect(result.plan?.id != plan.id)
        #expect(runner.downloads == 1)
        let installed = try #require(plan.steps.first { $0.id == "flutter.sdk" }?.installation?.destination)
        #expect(try FlutterSDK.read(installed).revision == FlutterFixture.revision)
        #expect(try String(contentsOf: f.repo.url("pubspec.lock"), encoding: .utf8) == "packages: {}\n")
    }

    @Test("source changed during the final SDK metadata inspection prevents the installation commit")
    func sourceChangesDuringFinalSDKInspection() async throws {
        let (f, bytes) = try await FlutterInstallationTests().payload()
        let feature = try f.repo.write("lib/feature.dart", "void feature() {}\n")
        let managed = f.repo.url("home/Library/Application Support/dev.runstir/flutter")
        let payload = FlutterPayloadRunner(data: bytes, directory: f.repo.root, installationRoot: managed)
        let runner = FlutterFinalInspectionMutationRunner(base: payload, feature: feature)
        let input = ProjectInspectionInput(directory: f.repo.root, environment: f.environment)
        let leases = ResourceLeases(directory: f.repo.url(".mobile/leases"))
        let proposed = await PreparationExecution.run(input: input, planOnly: true, runner: runner, leases: leases)
        let plan = try #require(proposed.plan)
        let destination = try #require(plan.steps.first { $0.id == "flutter.sdk" }?.installation?.destination)
        #expect(!plan.files.keys.contains { $0.hasSuffix("/lib/feature.dart") })
        let result = await PreparationExecution.run(input: input, approvedPlanID: plan.id, runner: runner, leases: leases)
        #expect(runner.mutations == 1)
        #expect(payload.downloads == 1)
        #expect(result.operation.state == "failed")
        #expect(result.operation.changedFiles.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath() }
            == [feature.resolvingSymlinksInPath()])
        #expect(!result.operation.completed.contains("flutter.sdk"))
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(try String(contentsOf: feature, encoding: .utf8) == "externally changed feature")
        let entries = FileManager.default.enumerator(at: managed, includingPropertiesForKeys: nil)
        let ownedStages = (entries?.allObjects as? [URL] ?? []).filter { $0.lastPathComponent.hasPrefix(".runstir-") }
        #expect(ownedStages.isEmpty)
    }

    @Test("Flutter declarations and entrypoint changes require fresh exact approval")
    func approvalInputs() async throws {
        for path in [".fvmrc", "pubspec_overrides.yaml", "lib/main.dart"] {
            let f = try FlutterFixture()
            var runner = f.runner()
            runner.responses["xcode-select -p"] = .failed(1, "No Xcode in fixture")
            if path == ".fvmrc" { try f.repo.write(path, #"{"flutter":"3.41.9"}"#) }
            if path == "pubspec_overrides.yaml" { try f.repo.write(path, "dependency_overrides: {}\n") }
            let input = ProjectInspectionInput(directory: f.repo.root, environment: f.environment)
            let before = await PreparationExecution.run(input: input, planOnly: true, runner: runner)
            let plan = try #require(before.plan)
            #expect(plan.files[f.repo.url("lib/main.dart").path] != nil)
            try f.repo.write(path, path == ".fvmrc" ? #"{"flutter":"3.47.2"}"# : "// changed input\n")
            let result = await PreparationExecution.run(input: input, approvedPlanID: plan.id, trustRepository: true, runner: runner)
            #expect(result.operation.state == "needs-approval")
            #expect(result.operation.completed.isEmpty)
            #expect(!runner.log.all.contains { $0.arguments.contains("get") })
        }
    }

    @Test("exact locked Dart alignment uses a child cache and stops on failure or cancellation")
    func lockedAlignmentAndCancellation() async throws {
        for mode in ["success", "failure", "cancel", "source"] {
            let f = try FlutterFixture()
            try FileManager.default.removeItem(at: f.repo.url("ios/Podfile"))
            var base = f.runner()
            base.responses["xcode-select -p"] = .failed(1, "No Xcode in fixture")
            let get = f.repo.url("sdk/bin/cache/dart-sdk/bin/dart").path + " pub --suppress-analytics get --enforce-lockfile"
            base.responses[get] = mode == "failure" ? .failed(1, "controlled locked get failure") : .ok("")
            if mode == "cancel" { base.failures[get] = CancellationError() }
            let cache = f.repo.url("home/Library/Application Support/dev.runstir/flutter/pub-cache")
            let runner = FlutterAlignmentRunner(base: base, mutate: mode == "source" ? f.repo.url("lib/main.dart") : nil, cache: cache)
            let input = ProjectInspectionInput(directory: f.repo.root, environment: f.environment)
            let leases = ResourceLeases(directory: f.repo.url(".mobile/leases"))
            let before = await PreparationExecution.run(input: input, planOnly: true, runner: runner, leases: leases)
            let plan = try #require(before.plan)
            let untrusted = await PreparationExecution.run(input: input, approvedPlanID: plan.id, runner: runner, leases: leases)
            #expect(untrusted.operation.requiredInput == ["--trust-repository"])
            let result = await PreparationExecution.run(input: input, approvedPlanID: plan.id, trustRepository: true, runner: runner, leases: leases)
            if mode == "cancel" {
                #expect(result.exitCode == 130)
                #expect(result.operation.state == "cancelled")
            } else if mode == "failure" {
                #expect(result.operation.state == "failed")
                #expect(!result.operation.completed.contains("dependencies.flutter"))
            } else {
                #expect(result.operation.completed.contains("dependencies.flutter"))
                if mode == "source" {
                    #expect(result.operation.state == "failed")
                    #expect(result.operation.changedFiles.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path } == [f.repo.url("lib/main.dart").resolvingSymlinksInPath().path])
                    #expect(try String(contentsOf: f.repo.url("lib/main.dart"), encoding: .utf8) == "unexpected source change")
                } else {
                    let command = try #require(base.log.first(matching: get))
                    #expect(command.workingDirectory?.path == f.repo.root.path)
                    #expect(command.environment == ["FLUTTER_ROOT": f.repo.url("sdk").path, "PUB_CACHE": cache.path])
                    #expect(result.operation.state == "partial")
                    #expect(result.operation.changedFiles.isEmpty)
                    #expect(FileManager.default.fileExists(atPath: cache.appendingPathComponent("fixture-cache").path))
                }
            }
            #expect(try String(contentsOf: f.repo.url("pubspec.lock"), encoding: .utf8) == "packages: {}\n")
            #expect(FileManager.default.fileExists(atPath: f.repo.url("sdk/bin/cache/flutter.version.json").path))
            #expect(!base.log.all.contains { $0.executable.hasSuffix("/bin/flutter") || $0.arguments.contains("upgrade") })
        }
    }

    @Test("the resolved workspace folder and shared owned Pub cache are leased before alignment")
    func workspaceAndCacheLeases() async throws {
        for resource in ["workspace", "cache"] {
            let f = try FlutterFixture()
            var runner = f.runner()
            runner.responses["xcode-select -p"] = .failed(1, "No Xcode in fixture")
            let input = ProjectInspectionInput(directory: f.repo.root, environment: f.environment)
            let leases = ResourceLeases(directory: f.repo.url(".mobile/leases"))
            let before = await PreparationExecution.run(input: input, planOnly: true, runner: runner, leases: leases)
            let plan = try #require(before.plan)
            let cache = try #require(plan.steps.first { $0.id == "dependencies.flutter" }?.target)
            let key = resource == "cache" ? ResourceKey.destination(URL(fileURLWithPath: cache)) : ResourceKey.folder(try FolderIdentity(directory: f.repo.root))
            let lease = try leases.acquire([key], owner: LeaseOwner(operationId: "other", command: "setup", project: f.repo.root.path))
            defer { lease.release() }
            let result = await PreparationExecution.run(input: input, approvedPlanID: plan.id, trustRepository: true, runner: runner, leases: leases)
            #expect(result.operation.conflict?.key == key)
            #expect(result.operation.completed.isEmpty)
            #expect(!runner.log.all.contains { $0.arguments.contains("get") })
        }
    }

    @Test("direct Pods preserve a declared CocoaPods version while an undeclared version uses availability", arguments: ["wrong", "matching", "unrequired"])
    func directPodVersionRequirement(_ mode: String) async throws {
        let fixture = try FlutterFixture()
        var runner = try podTools(fixture, bundled: false)
        try fixture.repo.write("ios/Podfile.lock", "locked pods")
        if mode != "unrequired" {
            try fixture.repo.write("Gemfile.lock", "GEM\n  specs:\n    cocoapods (1.16.1)\n")
        }
        let version = mode == "matching" ? "1.16.1" : "1.15.0"
        runner.responses["pod --version"] = .ok(version)
        runner.responses[fixture.repo.url(".mobile/tool-fixtures/pod").path + " --version"] = .ok(version)
        let input = ProjectInspectionInput(directory: fixture.repo.root, environment: fixture.environment)
        let leases = ResourceLeases(directory: fixture.repo.url(".mobile/leases"))
        let before = await PreparationExecution.run(input: input, planOnly: true, runner: runner, leases: leases)
        let plan = try #require(before.plan)
        let usable = mode != "wrong"
        #expect(plan.steps.first { $0.id == "dependencies.pods" }?.kind == (usable ? "align" : "migration"))
        if mode != "unrequired" {
            let versionCheck = plan.platforms.first { $0.platform == .ios }?.checks.first { $0.id == "ios.cocoapods.version" }
            #expect(versionCheck?.kind == (usable ? "reuse" : "provider"))
        }
        let result = await PreparationExecution.run(input: input, approvedPlanID: plan.id, trustRepository: true, runner: runner, leases: leases)
        #expect(result.operation.completed == (usable ? ["dependencies.flutter", "dependencies.pods"] : ["dependencies.flutter"]))
        #expect(runner.log.all.contains { $0.arguments == ["install", "--deployment"] } == usable)
        #expect(try String(contentsOf: fixture.repo.url("ios/Podfile.lock"), encoding: .utf8) == "locked pods")
    }

    @Test("direct frozen Pods require a lock while a declared Bundle stays manual without evaluation")
    func frozenPodsAndBundle() async throws {
        for bundled in [false, true] {
            let f = try FlutterFixture()
            let runner = try podTools(f, bundled: bundled)
            let input = ProjectInspectionInput(directory: f.repo.root, environment: f.environment)
            let leases = ResourceLeases(directory: f.repo.url(".mobile/leases"))
            let missing = await PreparationExecution.run(input: input, planOnly: true, runner: runner, leases: leases)
            #expect(missing.plan?.steps.first { $0.id == "dependencies.pods" }?.kind == "migration")
            try f.repo.write("ios/Podfile.lock", "locked pods")
            let before = await PreparationExecution.run(input: input, planOnly: true, runner: runner, leases: leases)
            let plan = try #require(before.plan)
            #expect(plan.steps.first { $0.id == "dependencies.pods" }?.kind == (bundled ? "migration" : "align"))
            let result = await PreparationExecution.run(input: input, approvedPlanID: plan.id, trustRepository: true, runner: runner, leases: leases)
            #expect(result.operation.completed == (bundled ? ["dependencies.flutter"] : ["dependencies.flutter", "dependencies.pods"]))
            if bundled {
                #expect(plan.steps.first { $0.id == "dependencies.gems" }?.kind == "migration")
                #expect(!runner.log.all.contains { $0.executable.hasSuffix("/bundle") && $0.arguments == ["install"] })
                #expect(!runner.log.all.contains { $0.arguments.starts(with: ["exec", "pod"]) || $0.arguments.contains("-rbundler") })
            } else {
                let pod = try #require(runner.log.all.first { $0.arguments == ["install", "--deployment"] })
                #expect(pod.workingDirectory?.path == f.repo.url("ios").path)
                #expect(pod.environment["FLUTTER_ROOT"] == f.repo.url("sdk").path)
            }
            #expect(try String(contentsOf: f.repo.url("ios/Podfile.lock"), encoding: .utf8) == "locked pods")
        }
    }

    @Test("new stale native generated input after locked Dart alignment prevents Pods")
    func generatedChangeStopsPods() async throws {
        let f = try FlutterFixture()
        let base = try podTools(f, bundled: false)
        try f.repo.write("ios/Podfile.lock", "locked pods")
        let runner = FlutterAlignmentRunner(base: base, mutate: f.repo.url(".flutter-plugins-dependencies"))
        let input = ProjectInspectionInput(directory: f.repo.root, environment: f.environment)
        let leases = ResourceLeases(directory: f.repo.url(".mobile/leases"))
        let before = await PreparationExecution.run(input: input, planOnly: true, runner: runner, leases: leases)
        let plan = try #require(before.plan)
        #expect(plan.steps.first { $0.id == "dependencies.pods" }?.kind == "align")
        let result = await PreparationExecution.run(input: input, approvedPlanID: plan.id, trustRepository: true, runner: runner, leases: leases)
        #expect(result.operation.completed == ["dependencies.flutter"])
        #expect(result.operation.state == "failed")
        #expect(!base.log.all.contains { $0.arguments == ["install", "--deployment"] })
        #expect(try String(contentsOf: f.repo.url(".flutter-plugins-dependencies"), encoding: .utf8) == "unexpected source change")
    }


    @Test("a selected workspace member aligns and leases its resolver root")
    func workspaceMemberUsesRoot() async throws {
        let f = try FlutterFixture()
        try f.repo.directory(".git")
        let original = try String(contentsOf: f.repo.url("pubspec.yaml"), encoding: .utf8)
        try f.repo.write("pubspec.yaml", original + "workspace:\n  - apps/*\n")
        try f.repo.write(".flutter-version", "3.41.9")
        try f.repo.write("apps/client/pubspec.yaml", "name: client\nenvironment:\n  sdk: ^3.6.0\nresolution: workspace\ndependencies:\n  flutter:\n    sdk: flutter\n")
        try f.repo.write("apps/client/lib/main.dart", "void main() {}\n")
        let app = f.repo.url("apps/client")
        let data = try JSONSerialization.data(withJSONObject: ["packages": [["path": f.repo.root.path], ["path": app.path]]])
        var runner = f.runner(workspace: String(decoding: data, as: UTF8.self))
        let get = f.repo.url("sdk/bin/cache/dart-sdk/bin/dart").path + " pub --suppress-analytics get --enforce-lockfile"
        runner.responses[get] = .ok("")
        let input = ProjectInspectionInput(directory: app, environment: f.environment)
        let leases = ResourceLeases(directory: f.repo.url(".mobile/leases"))
        let before = await PreparationExecution.run(input: input, planOnly: true, runner: runner, leases: leases)
        let plan = try #require(before.plan)
        #expect(plan.project.path == app.resolvingSymlinksInPath().path)
        #expect(plan.files.keys.contains { URL(fileURLWithPath: $0).lastPathComponent == "pubspec.lock" })
        #expect(plan.files[f.repo.url(".flutter-version").resolvingSymlinksInPath().path] != nil)
        let lease = try leases.acquire([.folder(try FolderIdentity(directory: f.repo.root))],
            owner: LeaseOwner(operationId: "workspace-owner", command: "setup", project: f.repo.root.path))
        let blocked = await PreparationExecution.run(input: input, approvedPlanID: plan.id, trustRepository: true, runner: runner, leases: leases)
        #expect(blocked.operation.conflict != nil)
        lease.release()
        let result = await PreparationExecution.run(input: input, approvedPlanID: plan.id, trustRepository: true, runner: runner, leases: leases)
        #expect(result.operation.completed == ["dependencies.flutter"])
        let command = try #require(runner.log.first(matching: get))
        #expect(command.workingDirectory?.resolvingSymlinksInPath().path == f.repo.root.resolvingSymlinksInPath().path)
        #expect(!FileManager.default.fileExists(atPath: app.appendingPathComponent("pubspec.lock").path))
    }


    @Test("Flutter platform identities never require React Native or node_modules")
    func flutterNativeIdentity() async throws {
        let f = try FlutterFixture()
        try f.repo.write("android/gradlew", "fixture wrapper")
        try f.repo.write("android/build.gradle", "plugins { id 'com.android.application' version '8.7.3' apply false }\n")
        try f.repo.write("android/app/build.gradle", "plugins { id 'com.android.application' }\n")
        var runner = f.runner()
        runner.responses["xcode-select -p"] = .failed(1, "No Xcode in fixture")
        let result = await PreparationExecution.run(input: ProjectInspectionInput(directory: f.repo.root, environment: f.environment), planOnly: true, runner: runner)
        let plan = try #require(result.plan)
        let android = try #require(plan.platforms.first { $0.platform == .android })
        #expect(android.checks.contains { $0.id == "android.android.project" && $0.kind == "reuse" })
        #expect(!plan.platforms.flatMap(\.checks).contains { $0.id == "ios.project.detected" })
        #expect(!plan.platforms.flatMap(\.checks).contains { $0.observed?.contains("React Native") == true })
        #expect(!runner.log.all.contains { $0.executable == "node" || $0.executable == "npm" })
    }

    @Test("the explicit public Flutter entrypoint changes approval identity and generated-input evidence")
    func publicEntrypoint() async throws {
        let f = try FlutterFixture()
        try f.repo.write("lib/other.dart", "void main() { print('other'); }\n")
        var runner = f.runner()
        runner.responses["xcode-select -p"] = .failed(1, "No Xcode in fixture")
        let base = ProjectInspectionInput(directory: f.repo.root, environment: f.environment)
        let selected = ProjectInspectionInput(directory: f.repo.root, environment: f.environment, entrypoint: "lib/other.dart")
        let before = await PreparationExecution.run(input: base, planOnly: true, runner: runner)
        let changed = await PreparationExecution.run(input: selected, planOnly: true, runner: runner)
        let plan = try #require(changed.plan)
        #expect(plan.id != before.plan?.id)
        #expect(plan.platforms.flatMap(\.checks).contains { $0.id == "flutter.entrypoint" && $0.target.hasSuffix("/lib/other.dart") })
        #expect(plan.files.keys.contains { $0.hasSuffix("/lib/other.dart") })
        #expect(plan.platforms.flatMap(\.checks).contains { $0.id == "ios.flutter.generated" && $0.kind != "reuse" })
        let stale = await PreparationExecution.run(input: selected, approvedPlanID: try #require(before.plan?.id), trustRepository: true, runner: runner)
        #expect(stale.operation.state == "needs-approval")
        #expect(!runner.log.all.contains { $0.arguments.contains("get") })
        let invalid = await PreparationExecution.run(input: ProjectInspectionInput(directory: f.repo.root, environment: f.environment, entrypoint: "../outside.dart"), planOnly: true, runner: runner)
        #expect(invalid.plan?.steps.contains { $0.id == "flutter.declarations" && $0.kind == "migration" } == true)
        try FileManager.default.removeItem(at: f.repo.url("lib/main.dart"))
        let onlyExplicit = await PreparationExecution.run(input: selected, planOnly: true, runner: runner)
        #expect(onlyExplicit.plan?.platforms.flatMap(\.checks).contains {
            $0.id == "flutter.entrypoint" && $0.kind == "reuse" && $0.target.hasSuffix("/lib/other.dart")
        } == true)
    }

    @Test("an explicit Flutter entrypoint is rejected for a native Android app without probing tools")
    func entrypointRequiresFlutter() async throws {
        let repo = try FixtureRepo()
        try repo.write("settings.gradle", "include ':app'")
        try repo.write("gradlew", "fixture")
        let runner = FakeProcessRunner()
        let result = await PreparationExecution.run(input: ProjectInspectionInput(directory: repo.root, environment: [:], entrypoint: "lib/main.dart"), planOnly: true, runner: runner)
        #expect(result.exitCode == 1)
        #expect(result.selection?.error?.contains("Flutter") == true)
        #expect(result.plan == nil)
        #expect(runner.log.all.isEmpty)
    }

    @Test("Flutter recovered-device continuation checks the whole resolver workspace", arguments: ["normal", "dart", "workspace"])
    func recoveredDeviceWorkspaceSource(_ mode: String) async throws {
        let f = try FlutterFixture()
        let home = try FixtureRepo()
        try f.repo.directory(".git")
        let original = try String(contentsOf: f.repo.url("pubspec.yaml"), encoding: .utf8)
        try f.repo.write("pubspec.yaml", original + "workspace:\n  - apps/*\n  - packages/*\n")
        let app = f.repo.url("apps/client")
        let shared = f.repo.url("packages/shared")
        try f.repo.write("apps/client/pubspec.yaml", "name: client\nenvironment:\n  sdk: ^3.6.0\nresolution: workspace\ndependencies:\n  flutter:\n    sdk: flutter\n")
        try f.repo.write("packages/shared/pubspec.yaml", "name: shared\nenvironment:\n  sdk: ^3.6.0\nresolution: workspace\n")
        for file in ["apps/client/lib/main.dart", "apps/client/lib/feature.dart", "packages/shared/lib/feature.dart"] {
            try f.repo.write(file, "void fixture() {}\n")
        }
        try f.repo.write("apps/client/mobile.yml", "ios:\n  runtime: '27.0'\n")
        try f.repo.write("apps/client/ios/Podfile", "platform :ios, '15.0'\n")
        try f.repo.write("apps/client/ios/Flutter/Generated.xcconfig", "FLUTTER_ROOT=\(f.repo.url("sdk").path)\nFLUTTER_APPLICATION_PATH=\(app.path)\nFLUTTER_TARGET=lib/main.dart\n")
        try f.repo.write("apps/client/android/settings.gradle", "include ':app'\n")
        try f.repo.write("apps/client/android/local.properties", "flutter.sdk=\(f.repo.url("sdk").path)\n")
        try f.repo.write("apps/client/.flutter-plugins-dependencies", "{\"version\":\"3.41.9\",\"plugins\":{\"ios\":[],\"android\":[]}}")
        let packages = [("example", f.repo.root), ("client", app), ("shared", shared), ("flutter", f.repo.url("sdk/packages/flutter"))]
        let config = try JSONSerialization.data(withJSONObject: ["configVersion": 2, "packages": packages.map { ["name": $0.0, "rootUri": $0.1.absoluteString] }])
        try config.write(to: f.repo.url(".dart_tool/package_config.json"))
        let graph = try JSONSerialization.data(withJSONObject: ["configVersion": 1, "roots": ["example", "client", "shared"], "packages": packages.map {
            ["name": $0.0, "dependencies": ["example", "client"].contains($0.0) ? ["flutter"] : [], "devDependencies": []] as [String: Any]
        }])
        try graph.write(to: f.repo.url(".dart_tool/package_graph.json"))
        let workspace = try JSONSerialization.data(withJSONObject: ["packages": [f.repo.root, app, shared].map { ["path": $0.path] }])
        var base = f.runner(workspace: String(decoding: workspace, as: UTF8.self))
        for (command, output) in [
            "xcode-select -p": "/test/Xcode", "xcodebuild -version": "Xcode 27.0\nBuild version 18A100",
            "xcodebuild -checkFirstLaunchStatus": "", "xcrun simctl list devices -j": #"{"devices":{}}"#,
            "xcrun simctl list devicetypes -j": #"{"devicetypes":[{"identifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-17","name":"iPhone 17","productFamily":"iPhone","minRuntimeVersionString":"26.0.0","maxRuntimeVersionString":"65535.255.255"}]}"#
        ] { base.responses[command] = .ok(output) }
        for process in ["xcodebuild", "Simulator", "launchd_sim"] { base.responses["pgrep -x " + process] = .failed(1, "") }
        base.responses[f.repo.url("sdk/bin/cache/dart-sdk/bin/dart").path + " pub --suppress-analytics get --enforce-lockfile"] = .ok("")
        var environment = f.environment
        environment["HOME"] = home.root.path
        let changed = mode == "normal" ? nil : f.repo.url(mode == "dart" ? "apps/client/lib/feature.dart" : "packages/shared/lib/feature.dart")
        let cache = home.url("Library/Application Support/dev.runstir/flutter/pub-cache")
        let runner = FlutterRuntimeRecoveryRunner(base: base, home: home.root, mutate: changed, cache: cache)
        let input = ProjectInspectionInput(directory: app, environment: environment)
        let leases = ResourceLeases(directory: home.url("leases"))
        let proposed = await PreparationExecution.run(input: input, planOnly: true, runner: runner, leases: leases)
        let plan = try #require(proposed.plan)
        #expect(plan.platforms.flatMap(\.checks).contains { $0.id == "ios.flutter.generated" && $0.kind == "reuse" })
        #expect(plan.steps.contains { $0.id == "ios.runtime.install" && $0.kind == "install" })
        #expect(!plan.steps.contains { $0.id == "ios.simulator.create" && $0.kind == "install" })
        let result = await PreparationExecution.run(input: input, approvedPlanID: plan.id, trustRepository: true, runner: runner, leases: leases)
        #expect(runner.installations == 1 && runner.creations == 0)
        #expect(result.operation.completed.contains("ios.runtime.install"))
        #expect(!result.operation.completed.contains("ios.simulator.create"))
        if let changed {
            #expect(result.operation.state == "failed")
            #expect(result.operation.changedFiles.count == 1)
            let observed = URL(fileURLWithPath: try #require(result.operation.changedFiles.first))
            #expect(observed.lastPathComponent == changed.lastPathComponent)
            #expect(try FolderIdentity(directory: observed.deletingLastPathComponent()) == FolderIdentity(directory: changed.deletingLastPathComponent()))
            #expect(result.operation.completed == ["ios.runtime.install"])
            #expect(!base.log.all.contains { $0.arguments.contains("get") })
            #expect(try String(contentsOf: changed, encoding: .utf8) == "externally changed Dart source")
        } else {
            #expect(result.operation.error == nil, Comment(rawValue: result.operation.error ?? ""))
            #expect(result.plan?.resources?.contains { $0.identifier == FlutterRuntimeRecoveryRunner.deviceID && $0.origin == .reused } == true)
            #expect(result.operation.completed.contains("dependencies.flutter"))
            #expect(result.operation.changedFiles.isEmpty)
            let get = try #require(base.log.all.first { $0.arguments.contains("get") })
            #expect(get.workingDirectory?.resolvingSymlinksInPath().path == f.repo.root.resolvingSymlinksInPath().path)
            #expect(get.environment["PUB_CACHE"] == cache.path)
            #expect(FileManager.default.fileExists(atPath: cache.appendingPathComponent("owned-cache").path))
        }
        #expect(try String(contentsOf: f.repo.url("pubspec.lock"), encoding: .utf8) == "packages: {}\n")
        withExtendedLifetime(home) {}
    }

    private func podTools(_ f: FlutterFixture, bundled: Bool) throws -> FakeProcessRunner {
        var runner = f.runner()
        runner.responses["xcode-select -p"] = .failed(1, "No Xcode in fixture")
        try f.repo.write(".ruby-version", "3.3.0")
        if bundled {
            try f.repo.write("Gemfile", "source 'https://rubygems.org'\ngem 'cocoapods'\n")
            try f.repo.write("Gemfile.lock", "GEM\n  specs:\n    cocoapods (1.16.1)\n")
        }
        for tool in ["ruby", "bundle", "pod"] {
            let file = try f.repo.write(".mobile/tool-fixtures/" + tool, "fixture executable")
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
            runner.responses["/usr/bin/which " + tool] = .ok(file.path)
        }
        let bin = f.repo.url(".mobile/tool-fixtures").path
        for prefix in ["", bin + "/"] {
            runner.responses[prefix + "ruby --version"] = .ok("ruby 3.3.0")
            runner.responses[prefix + "pod --version"] = .ok("1.16.1")
            runner.responses[prefix + "bundle exec pod --version"] = .ok("1.16.1")
            runner.responses[prefix + "bundle --version"] = .ok("Bundler version 2.6.9")
            runner.responses[prefix + "bundle config get path --parseable"] = .ok("path=vendor/bundle")
            runner.responses[prefix + "ruby -rbundler -e print Bundler.bundle_path"] = .ok(f.repo.url("vendor/bundle/ruby/3.3.0").path)
            runner.responses[prefix + "bundle install"] = .ok("")
            runner.responses[prefix + "pod install --deployment"] = .ok("")
            runner.responses[prefix + "bundle exec pod install --deployment"] = .ok("")
        }
        runner.responses[f.repo.url("sdk/bin/cache/dart-sdk/bin/dart").path + " pub --suppress-analytics get --enforce-lockfile"] = .ok("")
        return runner
    }

}



private final class FlutterFinalInspectionMutationRunner: ProcessRunner, @unchecked Sendable {
    let base: FlutterPayloadRunner
    let feature: URL
    private let lock = NSLock()
    private var mutationCount = 0
    var mutations: Int { lock.withLock { mutationCount } }

    init(base: FlutterPayloadRunner, feature: URL) {
        self.base = base; self.feature = feature
    }

    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        if command.executable == "curl", command.arguments.last == FlutterRelease.url.absoluteString,
           let entries = FileManager.default.enumerator(at: base.installationRoot, includingPropertiesForKeys: [.isDirectoryKey]),
           entries.allObjects.contains(where: { ($0 as? URL)?.lastPathComponent.hasPrefix(".runstir-stage-") == true }) {
            let mutate = lock.withLock {
                guard mutationCount == 0 else { return false }
                mutationCount += 1
                return true
            }
            if mutate { try Data("externally changed feature".utf8).write(to: feature) }
        }
        return try await base.run(command, onLine: onLine)
    }

    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
        throw FixtureMiss(command: command.description)
    }
}

private struct FlutterAlignmentRunner: ProcessRunner {
    let base: FakeProcessRunner
    let mutate: URL?
    var cache: URL? = nil
    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        let result = try await base.run(command, onLine: onLine)
        if command.executable.hasSuffix("/bin/dart"), command.arguments.contains("get"), result.terminationStatus.isSuccess {
            if let mutate { try Data("unexpected source change".utf8).write(to: mutate) }
            if let cache {
                try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
                try Data("completed dependency cache".utf8).write(to: cache.appendingPathComponent("fixture-cache"))
            }
        }
        return result
    }
    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
        throw FixtureMiss(command: command.description)
    }
}

private final class FlutterRuntimeRecoveryRunner: ProcessRunner, @unchecked Sendable {
    static let deviceID = "E00349BB-E8F0-4E8A-B5DD-BF3DDE20FBC0"
    let base: FakeProcessRunner
    let home: URL
    let mutate: URL?
    let cache: URL
    private let lock = NSLock()
    private var runtime = false
    private var deviceReads = 0
    private var installed = 0
    private var created = 0
    var installations: Int { lock.withLock { installed } }
    var creations: Int { lock.withLock { created } }

    init(base: FakeProcessRunner, home: URL, mutate: URL?, cache: URL) {
        self.base = base; self.home = home; self.mutate = mutate; self.cache = cache
    }

    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        var answer = base
        if command.arguments == ["simctl", "list", "runtimes", "-j"] {
            answer.responses[command.description] = .ok(lock.withLock { runtime }
                ? #"{"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-0","name":"iOS 27.0","version":"27.0","buildversion":"24A434","supportedArchitectures":["arm64"],"supportedDeviceTypes":[{"identifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-17"}],"isAvailable":true}]}"# : #"{"runtimes":[]}"#)
        } else if command.arguments == ["simctl", "--set", home.appendingPathComponent("Library/Developer/CoreSimulator/Devices").path, "list", "devices", "-j"] {
            let available = lock.withLock { runtime }
            let reads = lock.withLock { if runtime { deviceReads += 1 }; return deviceReads }
            if reads == 2, let mutate { try Data("externally changed Dart source".utf8).write(to: mutate) }
            let row: [String: Any] = ["udid": Self.deviceID, "name": "iPhone 17", "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17", "isAvailable": available, "state": "Shutdown"]
            let value = ["devices": ["com.apple.CoreSimulator.SimRuntime.iOS-27-0": [row]]]
            answer.responses[command.description] = .ok(String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self))
        } else if command.description == IOSRuntimeCatalog.command.description {
            let catalog: [String: Any] = ["downloadables": [["platform": "com.apple.platform.iphoneos", "downloadMethod": "mobileAsset", "contentType": "cryptexDiskImage", "dictionaryVersion": 2, "name": "iOS 27.0 Simulator Runtime", "identifier": "fixture-asset", "simulatorVersion": ["version": "27.0", "buildUpdate": "24A434"], "architectures": ["arm64"], "fileSize": Int64(12)]]]
            let data = try PropertyListSerialization.data(fromPropertyList: catalog, format: .xml, options: 0)
            answer.responses[command.description] = .ok(String(decoding: data, as: UTF8.self))
        } else if command.arguments.contains("-downloadPlatform") {
            lock.withLock { installed += 1; runtime = true }
            answer.responses[command.description] = .ok("")
        } else if command.arguments.contains("create") {
            lock.withLock { created += 1 }
            answer.responses[command.description] = .failed(1, "Redundant creation must not run")
        }
        let result = try await answer.run(command, onLine: onLine)
        if command.arguments.contains("get"), result.terminationStatus.isSuccess {
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            try Data("owned dependency cache".utf8).write(to: cache.appendingPathComponent("owned-cache"))
        }
        return result
    }

    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
        throw FixtureMiss(command: command.description)
    }
}

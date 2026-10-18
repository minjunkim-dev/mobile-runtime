import Core
@testable import EnvironmentKit
import Foundation
import TestSupport
import Testing

@Suite("Flutter provider")
struct FlutterProviderTests {
    @Test("read-only SDK reuse resolves the real workspace and keeps native inputs ready")
    func reuseAndNativeReadiness() async throws {
        let f = try FlutterFixture()
        let runner = f.runner()
        let before = try Data(contentsOf: f.repo.url("sdk/bin/cache/flutter.version.json"))
        let plan = try await f.inspect(runner)
        #expect(plan.checks.contains { $0.id == "flutter.sdk" && $0.kind == "reuse" })
        #expect(plan.checks.filter { $0.id.hasSuffix(".flutter.generated") && $0.kind == "reuse" }.count == 2)
        let command = try #require(plan.dependencyCommand)
        #expect(command.executable == f.repo.url("sdk/bin/cache/dart-sdk/bin/dart").path)
        #expect(command.arguments == ["pub", "--suppress-analytics", "get", "--enforce-lockfile"])
        #expect(command.workingDirectory?.path == f.repo.root.path)
        #expect(command.environment["FLUTTER_ROOT"] == f.repo.url("sdk").path)
        #expect(command.environment["PUB_CACHE"] == f.repo.url("managed/pub-cache").path)
        #expect(command.environment["PRIVATE_TOKEN"] == nil)
        #expect(runner.log.all.allSatisfy { !$0.arguments.contains("get") && !$0.executable.hasSuffix("/bin/flutter") })
        #expect(try Data(contentsOf: f.repo.url("sdk/bin/cache/flutter.version.json")) == before)
        #expect(!FileManager.default.fileExists(atPath: f.repo.url("managed").path))
    }

    @Test("generated Flutter module hosts stay explicit manual work without app-host rerouting")
    func generatedModuleHosts() async throws {
        let f = try FlutterFixture()
        for platform in ["ios", "android"] {
            try FileManager.default.removeItem(at: f.repo.url(platform))
            try f.repo.write("." + platform + "/preserve", "existing generated module host")
        }
        let runner = f.runner()
        let plan = try await f.inspect(runner)
        for platform in ["ios", "android"] {
            #expect(plan.checks.contains { $0.id == "\(platform).flutter.host" && $0.kind == "migration" && $0.target.hasSuffix("/." + platform) && $0.observed?.contains("module") == true })
            #expect(try String(contentsOf: f.repo.url("." + platform + "/preserve"), encoding: .utf8) == "existing generated module host")
        }
        #expect(!runner.log.all.contains { $0.arguments.contains("get") || $0.executable.hasSuffix("/bin/flutter") })
    }

    @Test("an incompatible SDK is preserved while the exact official release is planned side by side")
    func sideBySidePlan() async throws {
        let f = try FlutterFixture(sdkVersion: "3.47.2")
        try f.repo.write(".fvmrc", #"{"flutter":"3.41.9"}"#)
        let original = try Data(contentsOf: f.repo.url("sdk/bin/cache/flutter.version.json"))
        let runner = f.runner()
        let plan = try await f.inspect(runner)
        let step = try #require(plan.steps.first { $0.id == "flutter.sdk" && $0.kind == "install" })
        let metadata = try #require(step.installation)
        #expect(metadata.destination.path == f.repo.url("managed/versions/3.41.9-arm64-00b0c91f0620").path)
        #expect(metadata.artifact?.checksum == FlutterFixture.archiveSHA)
        #expect(metadata.artifact?.size == 2147160009)
        #expect(plan.dependencyCommand == nil)
        #expect(try Data(contentsOf: f.repo.url("sdk/bin/cache/flutter.version.json")) == original)
        #expect(!runner.log.all.contains { $0.arguments.contains("--output") })
    }

    @Test("the fixed candidate never overrides incompatible Dart declarations")
    func rejectFixedCandidate() async throws {
        let f = try FlutterFixture()
        try f.repo.write("pubspec.yaml", "name: example\nenvironment:\n  sdk: '>=3.12.0 <4.0.0'\ndependencies:\n  flutter:\n    sdk: flutter\n")
        let plan = try await f.inspect(f.runner())
        #expect(plan.steps.contains { $0.id == "flutter.sdk" && $0.kind == "migration" })
        #expect(plan.actions.isEmpty)
        #expect(plan.dependencyCommand == nil)
    }

    @Test("a resolver-selected workspace lock is used and stray member locks remain untouched")
    func workspaceMigration() async throws {
        let f = try FlutterFixture()
        try f.repo.write("apps/client/pubspec.yaml", "name: client\nenvironment:\n  sdk: ^3.6.0\nresolution: workspace\ndependencies:\n  flutter:\n    sdk: flutter\n")
        try f.repo.write("apps/client/lib/main.dart", "void main() {}\n")
        let workspace = try JSONSerialization.data(withJSONObject: ["packages": [["path": f.repo.root.path], ["path": f.repo.url("apps/client").path]]])
        let runner = f.runner(workspace: String(decoding: workspace, as: UTF8.self), app: "apps/client")
        let plan = try await FlutterPreparation.inspect(directory: f.repo.url("apps/client"), environment: f.environment,
            runner: runner, installationRoot: f.repo.url("managed"))
        #expect(plan.dependencyCommand?.workingDirectory?.path == f.repo.root.path)
        try f.repo.write("apps/pubspec.lock", "stray ancestor lock")
        try f.repo.write("apps/client/pubspec.lock", "stray member lock")
        let blocked = try await FlutterPreparation.inspect(directory: f.repo.url("apps/client"), environment: f.environment,
            runner: runner, installationRoot: f.repo.url("managed"))
        #expect(blocked.dependencyCommand == nil)
        #expect(blocked.steps.contains { $0.id == "dependencies.flutter" && $0.kind == "migration" })
        #expect(try String(contentsOf: f.repo.url("apps/pubspec.lock"), encoding: .utf8) == "stray ancestor lock")
        #expect(try String(contentsOf: f.repo.url("apps/client/pubspec.lock"), encoding: .utf8) == "stray member lock")
    }

    @Test("workspace SDK disagreement and missing lockfiles block alignment")
    func workspaceConstraintAndMissingLock() async throws {
        let f = try FlutterFixture()
        try FileManager.default.removeItem(at: f.repo.url("pubspec.lock"))
        let missing = try await f.inspect(f.runner())
        #expect(missing.dependencyCommand == nil)
        #expect(missing.steps.contains { $0.id == "dependencies.flutter" && $0.kind == "migration" })
        try f.repo.write("pubspec.lock", "packages: {}\n")
        try f.repo.write("packages/other/pubspec.yaml", "name: other\nenvironment:\n  sdk: ^3.12.0\nresolution: workspace\n")
        let body = try JSONSerialization.data(withJSONObject: ["packages": [["path": f.repo.root.path], ["path": f.repo.url("packages/other").path]]])
        let blocked = try await f.inspect(f.runner(workspace: String(decoding: body, as: UTF8.self)))
        #expect(blocked.dependencyCommand == nil)
        #expect(blocked.steps.contains { $0.id == "flutter.workspace" && $0.kind == "migration" })
    }

    @Test("cancellation from release or Dart workspace inspection is not converted to manual work")
    func cancellation() async throws {
        let f = try FlutterFixture()
        for description in [FlutterRelease.command.description, f.workspaceCommand] {
            var runner = f.runner()
            runner.failures[description] = CancellationError()
            await #expect(throws: CancellationError.self) { try await f.inspect(runner) }
        }
    }

    @Test("only a platform with stale derived inputs waits for manual preparation")
    func partialNativeReadiness() async throws {
        let f = try FlutterFixture()
        try f.repo.write("android/local.properties", "flutter.sdk=/missing/old-sdk\n")
        let plan = try await f.inspect(f.runner())
        #expect(plan.checks.contains { $0.id == "ios.flutter.generated" && $0.kind == "reuse" })
        #expect(plan.checks.contains { $0.id == "android.flutter.generated" && $0.kind == "provider" })
        #expect(try String(contentsOf: f.repo.url("android/local.properties"), encoding: .utf8) == "flutter.sdk=/missing/old-sdk\n")
    }

    @Test("official metadata must identify one stable arm64 archive and exact bundled Dart")
    func officialIdentity() throws {
        let valid = try FlutterFixture.releaseMetadata()
        #expect(try FlutterRelease(data: valid, version: "3.41.9").dartVersion == "3.11.5")
        for field in ["dart_sdk_arch", "channel", "archive", "dart_sdk_version"] {
            var document = try #require(JSONSerialization.jsonObject(with: valid) as? [String: Any])
            var rows = try #require(document["releases"] as? [[String: Any]])
            rows[0][field] = "unresolved"
            document["releases"] = rows
            let data = try JSONSerialization.data(withJSONObject: document)
            #expect(throws: (any Error).self) { try FlutterRelease(data: data, version: "3.41.9") }
        }
        var document = try #require(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        let rows = try #require(document["releases"] as? [[String: Any]])
        document["releases"] = rows + rows
        let ambiguous = try JSONSerialization.data(withJSONObject: document)
        #expect(throws: (any Error).self) { try FlutterRelease(data: ambiguous, version: "3.41.9") }
    }

    @Test("public manual steps omit raw declaration and tool diagnostics")
    func privateDiagnosticsStayPrivate() async throws {
        let f = try FlutterFixture()
        struct PrivateDiagnostic: Error, CustomStringConvertible {
            var description: String { "PRIVATE_PROBE_DIAGNOSTIC" }
        }
        var runner = f.runner()
        runner.failures[f.workspaceCommand] = PrivateDiagnostic()
        let failed = try await f.inspect(runner)
        let publicSteps = try JSONEncoder().encode(failed.checks)
        #expect(!String(decoding: publicSteps, as: UTF8.self).contains("PRIVATE_PROBE_DIAGNOSTIC"))
        try f.repo.write("pubspec.yaml", "name: [PRIVATE_DECLARATION_VALUE\n")
        let invalid = try await f.inspect(f.runner())
        #expect(!String(decoding: try JSONEncoder().encode(invalid.checks), as: UTF8.self).contains("PRIVATE_DECLARATION_VALUE"))
    }

    @Test("a Pub cache alias outside the owned root blocks the resolver and alignment")
    func preserveExternalCacheAlias() async throws {
        let f = try FlutterFixture()
        let existing = try FixtureRepo()
        try existing.write("keep", "original cache")
        try f.repo.directory("managed")
        try FileManager.default.createSymbolicLink(at: f.repo.url("managed/pub-cache"), withDestinationURL: existing.root)
        let runner = f.runner()
        let plan = try await f.inspect(runner)
        #expect(plan.dependencyCommand == nil)
        #expect(plan.steps.contains { $0.id == "dependencies.flutter" && $0.kind == "permission" })
        #expect(!runner.log.all.contains { $0.arguments.contains("workspace") })
        #expect(try String(contentsOf: existing.url("keep"), encoding: .utf8) == "original cache")
    }

    @Test("a generated Pub directory that aliases another tree is preserved for manual handling")
    func preserveExternalGeneratedAlias() async throws {
        let f = try FlutterFixture()
        let existing = try FixtureRepo()
        try FileManager.default.moveItem(at: f.repo.url(".dart_tool"), to: existing.url("generated"))
        try FileManager.default.createSymbolicLink(at: f.repo.url(".dart_tool"), withDestinationURL: existing.url("generated"))
        let plan = try await f.inspect(f.runner())
        #expect(plan.dependencyCommand == nil)
        #expect(plan.steps.contains { $0.id == "dependencies.flutter" && $0.kind == "migration" })
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: f.repo.url(".dart_tool").path) == existing.url("generated").path)
    }

    @Test("SDK fingerprints identify each file separately when two file boundaries change")
    func sdkFingerprintFileBoundaries() throws {
        let f = try FlutterFixture()
        let binary = f.repo.url("sdk/bin/cache/dart-sdk/bin/dart")
        let snapshot = f.repo.url("sdk/bin/cache/flutter_tools.snapshot")
        let header = try Data(contentsOf: binary)
        let tail = Data("changed bytes".utf8)
        let originalSnapshot = try Data(contentsOf: snapshot)
        try (header + tail).write(to: binary)
        let before = try FlutterSDK.read(f.repo.url("sdk")).fingerprint
        try header.write(to: binary)
        try (tail + originalSnapshot).write(to: snapshot)
        #expect(try FlutterSDK.read(f.repo.url("sdk")).fingerprint != before)
    }

    @Test("valid project constraints and exact pin provenance remain visible in the SDK plan")
    func declarationProvenance() async throws {
        let f = try FlutterFixture()
        try f.repo.write(".fvmrc", #"{"flutter":"3.41.9"}"#)
        let plan = try await f.inspect(f.runner())
        let evidence = try #require(plan.checks.first { $0.id == "flutter.declarations" && $0.kind == "reuse" })
        #expect(evidence.observed?.contains(">=3.6.0 <4.0.0") == true)
        #expect(evidence.observed?.contains("3.41.9") == true)
        #expect(evidence.source.origin.contains(f.repo.url(".fvmrc").path))
    }

    @Test("an exact project pin selects its own official release instead of the fixed fallback")
    func projectPinWins() async throws {
        let f = try FlutterFixture()
        try f.repo.write(".fvmrc", #"{"flutter":"3.47.2"}"#)
        let hash = String(repeating: "a", count: 40)
        let document: [String: Any] = ["base_url": FlutterRelease.base, "releases": [[
            "version": "3.47.2", "channel": "stable", "dart_sdk_arch": "arm64", "dart_sdk_version": "3.13.3", "hash": hash,
            "archive": "stable/macos/flutter_macos_arm64_3.47.2-stable.zip", "sha256": String(repeating: "b", count: 64)
        ]]]
        let data = try JSONSerialization.data(withJSONObject: document)
        var runner = f.runner()
        runner.responses[FlutterRelease.command.description] = .ok(String(decoding: data, as: UTF8.self))
        let head = "curl --fail --silent --show-error --head --proto =https --connect-timeout 15 --max-time 30 https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_3.47.2-stable.zip"
        runner.responses[head] = .ok("HTTP/2 200\r\ncontent-length: 1234\r\n")
        let plan = try await f.inspect(runner)
        let step = try #require(plan.steps.first { $0.id == "flutter.sdk" && $0.kind == "install" })
        #expect(step.required?.contains("Dart 3.13.3") == true)
        #expect(step.installation?.destination.lastPathComponent == "3.47.2-arm64-aaaaaaaaaaaa")
        #expect(step.installation?.artifact?.url.lastPathComponent == "flutter_macos_arm64_3.47.2-stable.zip")
    }

    @Test("an inconsistent existing SDK is preserved and is never bootstrapped")
    func inconsistentExistingSDK() async throws {
        let f = try FlutterFixture()
        try f.repo.write("sdk/bin/cache/dart-sdk/version", "3.12.0\n")
        let runner = f.runner()
        let plan = try await f.inspect(runner)
        #expect(plan.steps.contains { $0.id == "flutter.sdk" && $0.kind == "install" })
        #expect(try String(contentsOf: f.repo.url("sdk/bin/cache/dart-sdk/version"), encoding: .utf8) == "3.12.0\n")
        #expect(!runner.log.all.contains { $0.executable.hasSuffix("/bin/flutter") || $0.arguments.contains("workspace") })
    }

    @Test("workspace Flutter constraints are enforced even when all Dart constraints accept")
    func workspaceFlutterConstraint() async throws {
        let f = try FlutterFixture()
        try f.repo.write("packages/other/pubspec.yaml", "name: other\nenvironment:\n  sdk: ^3.6.0\n  flutter: '>=3.47.0'\nresolution: workspace\n")
        let body = try JSONSerialization.data(withJSONObject: ["packages": [["path": f.repo.root.path], ["path": f.repo.url("packages/other").path]]])
        let plan = try await f.inspect(f.runner(workspace: String(decoding: body, as: UTF8.self)))
        #expect(plan.workspace?.packages.count == 2)
        #expect(plan.dependencyCommand == nil)
        #expect(plan.steps.contains { $0.id == "flutter.workspace" && $0.kind == "migration" })
    }

    @Test("an explicit entrypoint is preserved and checked against existing iOS generated input")
    func explicitEntrypoint() async throws {
        let f = try FlutterFixture()
        try f.repo.write("lib/start.dart", "void main() {}\n")
        try f.repo.write("ios/Flutter/Generated.xcconfig", "FLUTTER_ROOT=\(f.repo.url("sdk").path)\nFLUTTER_APPLICATION_PATH=\(f.repo.root.path)\nFLUTTER_TARGET=lib/start.dart\n")
        let plan = try await FlutterPreparation.inspect(directory: f.repo.root, entrypoint: "lib/start.dart",
            environment: f.environment, runner: f.runner(), installationRoot: f.repo.url("managed"))
        #expect(plan.entrypoint?.path == f.repo.url("lib/start.dart").path)
        #expect(plan.checks.contains { $0.id == "ios.flutter.generated" && $0.kind == "reuse" })
    }
}

struct FlutterFixture {
    static let revision = "00b0c91f06209d9e4a41f71b7a512d6eb3b9c694"
    static let archiveSHA = "d692b030a63466c44d6b2bc88583380371ecbe328f22cc4057835f59739821a1"
    let repo: FixtureRepo
    var environment: [String: String] { ["HOME": repo.url("home").path, "FLUTTER_ROOT": repo.url("sdk").path, "PRIVATE_TOKEN": "not-plan-data"] }
    var workspaceCommand: String { repo.url("sdk/bin/cache/dart-sdk/bin/dart").path + " pub --suppress-analytics workspace list --json" }

    init(sdkVersion: String = "3.41.9") throws {
        repo = try FixtureRepo()
        try repo.write("pubspec.yaml", "name: example\nenvironment:\n  sdk: '>=3.6.0 <4.0.0'\n  flutter: '>=3.24.0'\ndependencies:\n  flutter:\n    sdk: flutter\n")
        try repo.write("pubspec.lock", "packages: {}\n")
        try repo.write("lib/main.dart", "void main() {}\n")
        try repo.write("ios/Podfile", "platform :ios, '15.0'\n")
        try repo.write("android/settings.gradle", "include ':app'\n")
        try Self.sdk(repo: repo, at: "sdk", version: sdkVersion)
        try repo.write("ios/Flutter/Generated.xcconfig", "FLUTTER_ROOT=\(repo.url("sdk").path)\nFLUTTER_APPLICATION_PATH=\(repo.root.path)\nFLUTTER_TARGET=lib/main.dart\n")
        try repo.write("android/local.properties", "flutter.sdk=\(repo.url("sdk").path)\n")
        try repo.write(".flutter-plugins-dependencies", "{\"version\":\"\(sdkVersion)\",\"plugins\":{\"ios\":[],\"android\":[]}}")
        let config = try JSONSerialization.data(withJSONObject: ["configVersion": 2, "packages": [
            ["name": "example", "rootUri": repo.root.absoluteString],
            ["name": "flutter", "rootUri": repo.url("sdk/packages/flutter").absoluteString]
        ]])
        try repo.directory(".dart_tool")
        try config.write(to: repo.url(".dart_tool/package_config.json"))
        let graph = try JSONSerialization.data(withJSONObject: ["configVersion": 1, "roots": ["example"], "packages": [
            ["name": "example", "dependencies": ["flutter"], "devDependencies": []],
            ["name": "flutter", "dependencies": [], "devDependencies": []]
        ]])
        try graph.write(to: repo.url(".dart_tool/package_graph.json"))
    }

    func inspect(_ runner: any ProcessRunner) async throws -> FlutterPreparation {
        try await FlutterPreparation.inspect(directory: repo.root, environment: environment, runner: runner, installationRoot: repo.url("managed"))
    }

    func runner(workspace: String? = nil, app: String = "") -> FakeProcessRunner {
        let body = workspace ?? "{\"packages\":[{\"name\":\"example\",\"path\":\"\(repo.root.path)\"}]}"
        let release = String(decoding: try! Self.releaseMetadata(), as: UTF8.self)
        let head = "curl --fail --silent --show-error --head --proto =https --connect-timeout 15 --max-time 30 https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_3.41.9-stable.zip"
        return FakeProcessRunner(responses: [FlutterRelease.command.description: .ok(release), workspaceCommand: .ok(body), head: .ok("HTTP/2 200\r\ncontent-length: 2147160009\r\n")])
    }

    static func releaseMetadata(checksum: String = archiveSHA) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["base_url": FlutterRelease.base, "releases": [[
            "version": "3.41.9", "channel": "stable", "dart_sdk_arch": "arm64", "dart_sdk_version": "3.11.5", "hash": revision,
            "archive": "stable/macos/flutter_macos_arm64_3.41.9-stable.zip", "sha256": checksum
        ]]], options: [.sortedKeys])
    }

    static func sdk(repo: FixtureRepo, at prefix: String, version: String = "3.41.9") throws {
        let data = try JSONSerialization.data(withJSONObject: ["frameworkVersion": version, "channel": "stable", "dartSdkVersion": "3.11.5", "frameworkRevision": revision])
        try repo.write(prefix + "/bin/cache/flutter.version.json", String(decoding: data, as: UTF8.self))
        try repo.write(prefix + "/bin/cache/dart-sdk/version", "3.11.5\n")
        try repo.write(prefix + "/bin/cache/flutter_tools.snapshot", "fixture prepared snapshot")
        try repo.write(prefix + "/bin/flutter", "fixture wrapper; never execute")
        try repo.write(prefix + "/bin/cache/dart-sdk/bin/dart", "")
        try Data([0xcf, 0xfa, 0xed, 0xfe, 0x0c, 0, 0, 1]).write(to: repo.url(prefix + "/bin/cache/dart-sdk/bin/dart"))
        for path in ["/bin/flutter", "/bin/cache/dart-sdk/bin/dart"] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: repo.url(prefix + path).path)
        }
        try repo.write(prefix + "/packages/flutter/pubspec.yaml", "name: flutter\ndependencies: {}\n")
        try repo.write(prefix + "/bin/cache/artifacts/engine/ios/Flutter.xcframework/Info.plist", "fixture engine marker")
        try repo.write(prefix + "/bin/cache/artifacts/engine/android-arm64/flutter.jar", "fixture engine marker")
    }
}

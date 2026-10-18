import Core
@testable import EnvironmentKit
import Foundation
import TestSupport
import Testing

@Suite("shared Flutter iOS workflow")
struct FlutterIOSWorkflowTests {
    @Test("prepared Flutter host builds without dependency alignment or installation")
    func build() async throws {
        let f = try FlutterIOSFixture()
        let runner = FlutterIOSRunner(fixture: f)
        let result = await WorkflowExecution.run(.build, input: f.input(), runner: runner, leases: f.leases)
        #expect(result.exitCode == 0, Comment(rawValue: result.up?.failure?.message ?? ""))
        #expect(result.operation.selection?.selected?.framework == .flutter)
        #expect(result.operation.selection?.candidates.count == 1)
        #expect(result.up?.stages.map(\.id) == ["validate", "build"])
        #expect(result.up?.context.product?.bundleIdentifier == "dev.test.flutter")
        #expect(!runner.commands.contains { $0.arguments.contains("install") || $0.arguments.contains("launch") || $0.arguments.contains("get") })
        #expect(!runner.commands.contains { $0.executable == "node" || $0.executable.hasSuffix("/bin/flutter") })
    }

    @Test("doctor shares prepared Flutter facts and keeps Android preparation independent")
    func doctor() async throws {
        let f = try FlutterIOSFixture()
        let runner = FlutterIOSRunner(fixture: f)
        let result = try await EnvironmentInspection.run(input: f.input().project, runner: runner)
        #expect(result.report.checks.contains { $0.id == "flutter.sdk" && $0.status == .pass })
        #expect(result.report.checks.contains { $0.id == "ios.flutter.generated" && $0.status == .pass })
        #expect(!runner.commands.contains { $0.arguments.contains("build") || $0.arguments.contains("get") })
    }

    @Test("up observes its own authenticated VM URI and down needs no SDK", arguments: [false, true])
    func upAndDown(_ workspace: Bool) async throws {
        let f = try FlutterIOSFixture(workspace: workspace)
        let runner = FlutterIOSRunner(fixture: f)
        let result = await WorkflowExecution.run(.up, input: f.input(), runner: runner, leases: f.leases)
        #expect(result.exitCode == 0, Comment(rawValue: result.up?.failure?.message ?? ""))
        let port = try #require(result.operation.port)
        #expect(result.operation.developmentServiceURI == "http://127.0.0.1:\(port)/auth/")
        #expect(result.up?.stages.map(\.id) == ["validate", "device", "build", "install", "launch"])
        let launch = try #require(runner.commands.first { $0.arguments.contains("launch") })
        #expect(launch.arguments.contains("--vm-service-port=\(port)"))
        #expect(launch.arguments.contains("A"))
        #expect(runner.commands.contains { $0.arguments.last == "http://127.0.0.1:\(port)/auth/getVM" })
        try FileManager.default.removeItem(at: f.repo.url("sdk"))
        let down = await WorkflowExecution.run(.down, input: f.input(), runner: runner, leases: f.leases)
        #expect(down.exitCode == 0)
        #expect(down.down?.items.map(\.id) == ["app"])
        #expect(down.down?.items.first?.status == .stopped)
        #expect(!runner.commands.contains { $0.arguments.contains("shutdown") || $0.arguments.contains("uninstall") || $0.arguments.contains("8081") })
    }

    @Test("effective Release, changed target and Xcode fallback never reach build", arguments: ["release", "target", "configuration"])
    func effectiveInputs(_ fault: String) async throws {
        let f = try FlutterIOSFixture()
        let runner = FlutterIOSRunner(fixture: f, fault: fault)
        let result = await WorkflowExecution.run(.build, input: f.input(), runner: runner, leases: f.leases)
        #expect(result.exitCode == 1)
        #expect(!runner.commands.contains { $0.arguments.last == "build" })
    }

    @Test("effective Xcode settings cannot select an alternate Flutter engine", arguments: [
        "FLUTTER_TOOL_ARGS", "FLUTTER_ENGINE", "LOCAL_ENGINE", "LOCAL_ENGINE_HOST", "FLUTTER_ENGINE_SRC_PATH",
    ])
    func alternateEngine(_ setting: String) async throws {
        let f = try FlutterIOSFixture()
        let runner = FlutterIOSRunner(fixture: f, fault: "engine:" + setting)
        let result = await WorkflowExecution.run(.build, input: f.input(), runner: runner, leases: f.leases)
        #expect(result.exitCode == 1)
        #expect(!runner.commands.contains { $0.arguments.last == "build" })
    }

    @Test("a custom debug configuration requires selection and is shared with doctor")
    func configurationSelection() async throws {
        let f = try FlutterIOSFixture()
        let missing = FlutterIOSRunner(fixture: f, fault: "no-debug")
        let selection = await WorkflowExecution.run(.build, input: f.input(), runner: missing, leases: f.leases)
        #expect(selection.operation.state == "needs-selection")
        #expect(selection.operation.requiredInput == ["--configuration"])
        #expect(selection.operation.configurations == ["Development", "Release"])
        #expect(!missing.commands.contains { $0.arguments.contains("-showBuildSettings") || $0.arguments.last == "build" })
        let doctor = try await EnvironmentInspection.run(input: f.input().project, runner: missing)
        #expect(doctor.report.checks.contains { $0.id == "ios.flutter.project" && $0.status == .warning })
        let selected = FlutterIOSRunner(fixture: f, fault: "no-debug")
        let ready = try await EnvironmentInspection.run(input: f.input().project, runner: selected,
            scheme: "Runner", configuration: "Development")
        #expect(ready.report.checks.contains { $0.id == "ios.flutter.project" && $0.status == .pass })
        let build = await WorkflowExecution.run(.build, input: f.input(configuration: "Development"), runner: selected, leases: f.leases)
        #expect(build.exitCode == 0, Comment(rawValue: build.up?.failure?.message ?? ""))
        #expect(build.operation.configuration == "Development")
        let invalid = try await EnvironmentInspection.run(input: f.input().project, runner: selected, scheme: "Missing")
        #expect(invalid.report.checks.contains { $0.id == "ios.flutter.project" && $0.status == .error })
    }

    @Test("an explicit matching entrypoint uses existing generated inputs without rewriting them")
    func entrypoint() async throws {
        let f = try FlutterIOSFixture()
        try f.repo.write("lib/start.dart", "void main() {}\n")
        let generated = "FLUTTER_ROOT=\(f.repo.url("sdk").path)\nFLUTTER_APPLICATION_PATH=\(f.repo.root.path)\nFLUTTER_TARGET=lib/start.dart\n"
        try f.repo.write("ios/Flutter/Generated.xcconfig", generated)
        let runner = FlutterIOSRunner(fixture: f, fault: "entrypoint")
        let result = await WorkflowExecution.run(.build, input: f.input(entrypoint: "lib/start.dart"), runner: runner, leases: f.leases)
        #expect(result.exitCode == 0, Comment(rawValue: result.up?.failure?.message ?? ""))
        #expect(result.operation.entrypoint == f.repo.url("lib/start.dart").path)
        #expect(try String(contentsOf: f.repo.url("ios/Flutter/Generated.xcconfig"), encoding: .utf8) == generated)
    }

    @Test("missing and escaping entrypoints stop before any child", arguments: ["lib/missing.dart", "../outside.dart"])
    func invalidEntrypoint(_ entrypoint: String) async throws {
        let f = try FlutterIOSFixture()
        let runner = FlutterIOSRunner(fixture: f)
        let result = await WorkflowExecution.run(.build, input: f.input(entrypoint: entrypoint), runner: runner, leases: f.leases)
        #expect(result.exitCode == 1)
        #expect(runner.commands.isEmpty)
    }

    @Test("stale generated input, SDK bootstrap and missing Pods stop before native changes", arguments: ["generated", "sdk", "pods"])
    func preparation(_ fault: String) async throws {
        let f = try FlutterIOSFixture()
        let file = fault == "generated" ? "ios/Flutter/Generated.xcconfig" : fault == "sdk" ? "sdk/bin/cache/flutter_tools.stamp" : "ios/Pods/Manifest.lock"
        try f.repo.write(file, "stale\n")
        let runner = FlutterIOSRunner(fixture: f)
        let result = await WorkflowExecution.run(.build, input: f.input(), runner: runner, leases: f.leases)
        #expect(result.exitCode == 1)
        #expect(!runner.commands.contains { $0.arguments.last == "build" || $0.arguments.contains("get") || $0.arguments.contains("install") })
        #expect(try String(contentsOf: f.repo.url(file), encoding: .utf8) == "stale\n")
    }

    @Test("build failure, cancellation and unexpected source changes preserve the failure boundary", arguments: ["build", "cancel", "source", "sdk-write"])
    func buildFailure(_ fault: String) async throws {
        let f = try FlutterIOSFixture()
        let runner = FlutterIOSRunner(fixture: f, fault: fault)
        let result = await WorkflowExecution.run(.up, input: f.input(), runner: runner, leases: f.leases)
        #expect(result.exitCode == (fault == "cancel" ? 130 : 1), Comment(rawValue: result.up?.failure?.message ?? ""))
        #expect(!runner.commands.contains { $0.arguments.contains("install") || $0.arguments.contains("launch") })
        if fault == "source" {
            #expect(try String(contentsOf: f.repo.url("pubspec.lock"), encoding: .utf8) == "changed\n")
            #expect(result.operation.remaining.contains { $0.contains("pubspec.lock") })
        }
    }

    @Test("install, launch and invalid service results do not report development readiness", arguments: ["install", "launch", "uri", "not-vm"])
    func runtimeFailure(_ fault: String) async throws {
        let f = try FlutterIOSFixture()
        let runner = FlutterIOSRunner(fixture: f, fault: fault)
        let result = await WorkflowExecution.run(.up, input: f.input(), runner: runner, leases: f.leases)
        #expect(result.exitCode == 1, Comment(rawValue: result.up?.failure?.message ?? ""))
        #expect(result.operation.developmentServiceURI == nil)
        if fault == "install" { #expect(!runner.commands.contains { $0.arguments.contains("launch") }) }
        if fault == "uri" { #expect(!runner.commands.contains { $0.arguments.last?.contains("example.com") == true }) }
    }

    @Test("a port lease conflict stops before build and preserves its owner")
    func portLease() async throws {
        let f = try FlutterIOSFixture()
        let port = try FlutterIOSWorkflow.availablePort(nil)
        let other = try f.leases.acquire([.port(port)], owner: LeaseOwner(operationId: "other", command: "up", project: "/other"))
        defer { other.release() }
        let runner = FlutterIOSRunner(fixture: f)
        let result = await WorkflowExecution.run(.up, input: f.input(port: port), runner: runner, leases: f.leases)
        #expect(result.exitCode == 1)
        #expect(result.operation.conflict?.key == .port(port))
        #expect(result.operation.conflict?.owner?.operationId == "other")
        #expect(!runner.commands.contains { $0.arguments.last == "build" || $0.arguments.contains("install") })
    }

    @Test("build rejects a development port before any tool")
    func buildPort() async throws {
        let f = try FlutterIOSFixture()
        let runner = FlutterIOSRunner(fixture: f)
        let result = await WorkflowExecution.run(.build, input: f.input(port: 12345), runner: runner, leases: f.leases)
        #expect(result.exitCode == 1)
        #expect(runner.commands.isEmpty)
    }

    @Test("Dart resolver workspace and selected app identity remain distinct in doctor and workflow")
    func workspaceIdentity() async throws {
        let f = try FlutterIOSFixture(workspace: true)
        let runner = FlutterIOSRunner(fixture: f)
        let staticSelection = try f.input().project.selection()
        let doctor = try await EnvironmentInspection.run(input: f.input().project, runner: runner)
        let result = await WorkflowExecution.run(.build, input: f.input(), runner: runner, leases: f.leases)
        #expect(result.exitCode == 0, Comment(rawValue: result.up?.failure?.message ?? ""))
        #expect(result.operation.selection?.selected?.id == staticSelection.selected?.id)
        #expect(result.operation.selection?.selected?.app == staticSelection.selected?.app)
        #expect(result.operation.selection?.selected?.workspace == (try FolderIdentity(directory: f.repo.root)))
        #expect(doctor.selection.selected == result.operation.selection?.selected)
        #expect(result.operation.selection?.selected?.app != result.operation.selection?.selected?.workspace)
        #expect(!runner.commands.contains { $0.arguments.contains("get") })
    }
}

struct FlutterIOSFixture {
    let flutter: FlutterFixture
    let inWorkspace: Bool
    var repo: FixtureRepo { flutter.repo }
    var app: URL { inWorkspace ? repo.url("apps/client") : repo.root }
    var leases: ResourceLeases { ResourceLeases(directory: repo.url("leases")) }
    var settings: [String: String] {
        ["CONFIGURATION": "Debug", "PLATFORM_NAME": "iphonesimulator", "IPHONEOS_DEPLOYMENT_TARGET": "15.0",
         "FULL_PRODUCT_NAME": "Runner.app", "BUILT_PRODUCTS_DIR": repo.url("build").path,
         "PRODUCT_BUNDLE_IDENTIFIER": "dev.test.flutter", "FLUTTER_BUILD_MODE": "debug",
         "FLUTTER_ROOT": repo.url("sdk").path, "FLUTTER_APPLICATION_PATH": app.path,
         "FLUTTER_TARGET": "lib/main.dart"]
    }
    init(workspace: Bool = false) throws {
        flutter = try FlutterFixture()
        inWorkspace = workspace
        try repo.write("ios/Runner.xcodeproj/project.pbxproj", "// fixture")
        try repo.write("ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme", "<Scheme><LaunchAction><BuildableProductRunnable><BuildableReference BlueprintName=\"Runner\" BuildableName=\"Runner.app\"/></BuildableProductRunnable></LaunchAction></Scheme>")
        try repo.write("ios/Runner.xcworkspace/contents.xcworkspacedata", "<Workspace><FileRef location=\"group:Runner.xcodeproj\"/></Workspace>")
        try repo.write("ios/Podfile.lock", "PODS:\n  - Flutter (1.0.0)\n")
        try repo.write("ios/Pods/Manifest.lock", "PODS:\n  - Flutter (1.0.0)\n")
        try repo.write(".xcode-version", "27.1\n")
        try repo.write("sdk/bin/cache/flutter_tools.stamp", FlutterFixture.revision + ":")
        try repo.write("sdk/bin/internal/engine.version", String(repeating: "a", count: 40))
        try repo.write("sdk/bin/cache/engine.stamp", String(repeating: "a", count: 40))
        try repo.write("sdk/bin/cache/engine-dart-sdk.stamp", String(repeating: "a", count: 40))
        try repo.write("sdk/packages/flutter_tools/pubspec.yaml", "name: flutter_tools\n")
        try repo.write("sdk/packages/flutter_tools/pubspec.lock", "packages: {}\n")
        try repo.write("sdk/bin/cache/artifacts/engine/ios/Flutter.xcframework/Info.plist", "engine")
        try repo.directory("home/Library/Application Support/dev.runstir/flutter/pub-cache")
        if workspace {
            try repo.directory("apps/client")
            for name in ["ios", "android", "lib", ".flutter-plugins-dependencies"] {
                try FileManager.default.moveItem(at: repo.url(name), to: app.appendingPathComponent(name))
            }
            let original = try String(contentsOf: repo.url("pubspec.yaml"), encoding: .utf8)
            try repo.write("pubspec.yaml", original + "workspace:\n  - apps/*\n")
            try repo.write("apps/client/pubspec.yaml", "name: client\nenvironment:\n  sdk: ^3.6.0\nresolution: workspace\ndependencies:\n  flutter:\n    sdk: flutter\n")
            try repo.write("apps/client/ios/Flutter/Generated.xcconfig", "FLUTTER_ROOT=\(repo.url("sdk").path)\nFLUTTER_APPLICATION_PATH=\(app.path)\nFLUTTER_TARGET=lib/main.dart\n")
            let packages = [("example", repo.root), ("client", app), ("flutter", repo.url("sdk/packages/flutter"))]
            try JSONSerialization.data(withJSONObject: ["configVersion": 2, "packages": packages.map { ["name": $0.0, "rootUri": $0.1.absoluteString] }]).write(to: repo.url(".dart_tool/package_config.json"))
            try JSONSerialization.data(withJSONObject: ["configVersion": 1, "roots": ["example", "client"], "packages": packages.map {
                ["name": $0.0, "dependencies": $0.0 == "flutter" ? [] : ["flutter"], "devDependencies": []] as [String: Any]
            }]).write(to: repo.url(".dart_tool/package_graph.json"))
        }
    }
    func input(entrypoint: String? = nil, port: Int? = nil, configuration: String? = nil) -> WorkflowInput {
        WorkflowInput(project: ProjectInspectionInput(directory: app, environment: flutter.environment,
            platform: .ios, entrypoint: entrypoint), configuration: configuration, port: port)
    }
}

final class FlutterIOSRunner: ProcessRunner, @unchecked Sendable {
    let fixture: FlutterIOSFixture
    let fault: String?
    private let lock = NSLock()
    private var recorded: [ProcessCommand] = []
    var commands: [ProcessCommand] { lock.withLock { recorded } }
    init(fixture: FlutterIOSFixture, fault: String? = nil) { self.fixture = fixture; self.fault = fault }
    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        lock.withLock { recorded.append(command) }
        var command = command
        if command.executable == "/usr/bin/sandbox-exec" {
            command = ProcessCommand("xcodebuild", Array(command.arguments.dropFirst(3)), environment: command.environment,
                workingDirectory: command.workingDirectory, timeout: command.timeout, output: command.output)
        }
        if command.executable == "xcodebuild" {
            if command.arguments == ["-version"] { return ok("Xcode 27.1\nBuild version 27A9275") }
            if command.arguments == ["-checkFirstLaunchStatus"] { return ok("") }
            if command.arguments.contains("-list") {
                let configurations = fault == "no-debug" ? ["Development", "Release"] : ["Debug", "Release"]
                return ok(String(decoding: try JSONSerialization.data(withJSONObject:
                    ["project": ["schemes": ["Runner"], "configurations": configurations]]), as: UTF8.self))
            }
            if command.arguments.contains("-showBuildSettings") {
                var settings = fixture.settings
                if fault == "release" { settings["FLUTTER_BUILD_MODE"] = "release" }
                if fault == "target" { settings["FLUTTER_TARGET"] = "lib/other.dart" }
                if fault == "entrypoint" { settings["FLUTTER_TARGET"] = "lib/start.dart" }
                if fault == "configuration" { settings["CONFIGURATION"] = "Release" }
                if let fault, fault.hasPrefix("engine:") { settings[String(fault.dropFirst("engine:".count))] = "/unapproved/engine" }
                if fault == "no-debug", let option = command.arguments.firstIndex(of: "-configuration") {
                    settings["CONFIGURATION"] = command.arguments[option + 1]
                }
                return ok(String(decoding: try JSONSerialization.data(withJSONObject: [["target": "Runner", "buildSettings": settings]]), as: UTF8.self))
            }
            if command.arguments.last == "build" {
                if fault == "real-child" {
                    try FileManager.default.createDirectory(at: fixture.repo.url("build"), withIntermediateDirectories: true)
                    let selected = try #require(commands.last)
                    let profile = try #require(selected.arguments.dropFirst().first)
                    return try await SystemProcessRunner(environment: ["PATH": "/usr/bin:/bin", "HOME": fixture.repo.url("home").path], workingDirectory: fixture.repo.root)
                        .run(ProcessCommand("/usr/bin/sandbox-exec", ["-f", profile, "/bin/sh", "-c", "echo $$ > \"$1\"; exec /bin/sleep 30", "_", fixture.repo.url("build/child.pid").path], timeout: .seconds(40)))
                }
                if fault == "source" { try fixture.repo.write("pubspec.lock", "changed\n") }
                if fault == "sdk-write" { try fixture.repo.write("sdk/bin/cache/flutter_tools.snapshot", "changed\n") }
                if fault == "cancel" { throw CancellationError() }
                if fault == "build" { return ProcessResult(terminationStatus: .exited(65), standardOutput: "", standardError: "build failed") }
                return ok("")
            }
        }
        if command.executable == "lsof" {
            return ProcessResult(terminationStatus: .exited(1), standardOutput: "", standardError: "")
        }
        if command.executable == "curl", command.arguments.last?.hasSuffix("getVM") == true {
            return ok(fault == "not-vm" ? "{}" : "{\"result\":{\"type\":\"VM\"}}")
        }
        if command.arguments.starts(with: ["simctl", "install"]) {
            if fault == "install" { return ProcessResult(terminationStatus: .exited(1), standardOutput: "", standardError: "install failed") }
            return ok("")
        }
        if command.arguments.starts(with: ["simctl", "terminate"]) { return ok("") }
        if command.arguments.starts(with: ["simctl", "launch"]) {
            if fault == "launch" { return ProcessResult(terminationStatus: .exited(1), standardOutput: "", standardError: "launch failed") }
            let output = try #require(command.arguments.first { $0.hasPrefix("--stdout=") })
            let path = String(output.dropFirst("--stdout=".count))
            let port = try #require(command.arguments.first { $0.hasPrefix("--vm-service-port=") })
            let value = String(port.dropFirst("--vm-service-port=".count))
            let uri = fault == "uri" ? "http://example.com:1/auth/" : "http://127.0.0.1:\(value)/auth/"
            let content = fault == "no-uri" ? "" : "The Dart VM service is listening on \(uri)\n"
            try Data(content.utf8).write(to: URL(fileURLWithPath: path))
            return ok("dev.test.flutter: 3538")
        }
        if command.executable == "xcode-select" { return ok("/test/Xcode") }
        if command.executable == "pod" { return ok("1.16.2") }
        if command.executable == "ruby" { return ok("ruby 3.2.2") }
        if command.arguments == ["simctl", "list", "runtimes", "-j"] { return ok("{\"runtimes\":[{\"identifier\":\"com.apple.CoreSimulator.SimRuntime.iOS-27-0\",\"name\":\"iOS 27.0\",\"version\":\"27.0\",\"isAvailable\":true}]}") }
        if command.arguments == ["simctl", "list", "devices", "-j"] { return ok("{\"devices\":{\"com.apple.CoreSimulator.SimRuntime.iOS-27-0\":[{\"name\":\"iPhone A\",\"udid\":\"A\",\"state\":\"Booted\",\"isAvailable\":true}]}}") }
        let workspace = fixture.inWorkspace ? "{\"packages\":[{\"path\":\"\(fixture.repo.root.path)\"},{\"path\":\"\(fixture.app.path)\"}]}" : nil
        return try await fixture.flutter.runner(workspace: workspace).run(command, onLine: onLine)
    }
    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 { throw FixtureMiss(command: command.description) }
    private func ok(_ text: String) -> ProcessResult { ProcessResult(terminationStatus: .exited(0), standardOutput: text, standardError: "") }
}

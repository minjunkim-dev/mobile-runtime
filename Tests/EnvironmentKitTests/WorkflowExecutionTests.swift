import Core
import EnvironmentKit
import Foundation
import TestSupport
import Testing

@Suite("shared CLI and GUI RN workflows")
struct WorkflowExecutionTests {
    @Test("dual-platform app needs selection before any subprocess or mutation")
    func missingPlatform() async throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies":{"react-native":"0.76.5"}}"#)
        try repo.directory("ios")
        try repo.directory("android")
        let runner = FakeProcessRunner()
        let result = await WorkflowExecution.run(.up, input: WorkflowInput(project: ProjectInspectionInput(
            directory: repo.root, environment: [:])), runner: runner)
        #expect(result.exitCode == 1)
        #expect(result.operation.state == "needs-selection")
        #expect(result.operation.requiredInput == ["--platform"])
        #expect(result.operation.selection?.selected?.id == ".")
        #expect(runner.log.all.isEmpty)
    }

    @Test("one iOS app builds a generic Simulator artifact without boot, install or launch")
    func genericBuild() async throws {
        let repo = try iosProject()
        let runner = iosRunner(repo)
        let events = EventLog()
        let result = await WorkflowExecution.run(.build, input: WorkflowInput(project: ProjectInspectionInput(
            directory: repo.root, environment: [:])), runner: runner, onEvent: { events.append($0) })
        #expect(result.exitCode == 0, Comment(rawValue: result.up?.failure?.message ?? ""))
        #expect(result.operation.state == "succeeded")
        #expect(result.operation.scheme == "MyApp")
        #expect(result.operation.device == nil)
        #expect(result.up?.stages.map(\.id) == ["validate", "dependencies", "build"])
        #expect(!runner.log.all.contains { $0.arguments.contains("bootstatus") || ($0.executable == "xcrun" && ($0.arguments.contains("install") || $0.arguments.contains("launch"))) })
        #expect(runner.log.spawned.isEmpty)
        #expect(events.all.map(\.sequence) == Array(1...events.all.count))
        #expect(Set(events.all.map(\.operationId)) == [result.operation.id])
        let data = Data(try result.encoded(toolVersion: "test").utf8)
        let document = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(document["command"] as? String == "build")
        #expect(document["schemaVersion"] as? Int == 1)
        #expect(document["result"] != nil)
        #expect(document["stages"] != nil)
        #expect(document["operation"] != nil)
    }

    @Test("several Simulator identities need an explicit device before dependencies")
    func missingDevice() async throws {
        let repo = try iosProject()
        var runner = iosRunner(repo)
        runner.responses["xcrun simctl list devices -j"] = .ok(#"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"name":"iPhone A","udid":"A","state":"Booted","isAvailable":true},{"name":"iPhone B","udid":"B","state":"Shutdown","isAvailable":true}]}}"#)
        let result = await WorkflowExecution.run(.up, input: WorkflowInput(project: ProjectInspectionInput(
            directory: repo.root, environment: [:], platform: .ios)), runner: runner)
        #expect(result.exitCode == 1)
        #expect(result.operation.state == "needs-selection")
        #expect(result.operation.requiredInput == ["--device"])
        #expect(result.operation.devices.map(\.id) == ["A", "B"])
        #expect(!runner.log.all.contains { $0.description == "yarn install --frozen-lockfile" })
        #expect(runner.log.spawned.isEmpty)
    }

    @Test("workspace-only apps confirm Debug from effective Xcode settings")
    func workspaceOnlyBuild() async throws {
        let repo = try iosProject(workspaceOnly: true)
        let runner = iosRunner(repo, workspaceOnly: true)
        let result = await WorkflowExecution.run(.build, input: WorkflowInput(project: ProjectInspectionInput(
            directory: repo.root, environment: [:])), runner: runner)
        #expect(result.exitCode == 0)
        #expect(result.operation.configuration == "Debug")
        #expect(result.up?.stages.map(\.id) == ["validate", "dependencies", "build"])
    }

    @Test("a workspace cannot accept an invalid configuration that Xcode silently resolves to Release")
    func workspaceInvalidConfiguration() async throws {
        let repo = try iosProject(workspaceOnly: true)
        var runner = iosRunner(repo, workspaceOnly: true)
        let command = "xcodebuild -showBuildSettings -json -workspace \(repo.url("ios/MyApp.xcworkspace").path) -scheme MyApp -configuration Missing -destination generic/platform=iOS Simulator"
        runner.responses[command] = .ok(#"[{"target":"MyApp","buildSettings":{"CONFIGURATION":"Release"}}]"#)
        let result = await WorkflowExecution.run(.build, input: WorkflowInput(project: ProjectInspectionInput(
            directory: repo.root, environment: [:]), configuration: "Missing"), runner: runner)
        #expect(result.exitCode == 1)
        #expect(result.operation.configurations == ["Release"])
        #expect(!runner.log.all.contains { $0.description == "yarn install --frozen-lockfile" })
    }

    @Test("invalid scheme and cross-platform selectors stop before dependency changes")
    func invalidSelectors() async throws {
        let repo = try iosProject()
        let runner = iosRunner(repo)
        let result = await WorkflowExecution.run(.build, input: WorkflowInput(project: ProjectInspectionInput(
            directory: repo.root, environment: [:], platform: .ios), scheme: "Wrong"), runner: runner)
        #expect(result.exitCode == 1)
        #expect(!runner.log.all.contains { $0.description == "yarn install --frozen-lockfile" })
        let unused = FakeProcessRunner()
        let wrongPlatform = await WorkflowExecution.run(.build, input: WorkflowInput(project: ProjectInspectionInput(
            directory: repo.root, environment: [:]), module: ":app"), runner: unused)
        #expect(wrongPlatform.exitCode == 1)
        #expect(unused.log.all.isEmpty)
    }

    @Test("a project without Debug requires configuration before dependency changes")
    func missingDebugConfiguration() async throws {
        let repo = try iosProject()
        var runner = iosRunner(repo)
        runner.responses["xcodebuild -list -json -project \(repo.url("ios/MyApp.xcodeproj").path)"] = .ok(#"{"project":{"schemes":["MyApp"],"configurations":["Release","Development"]}}"#)
        let result = await WorkflowExecution.run(.build, input: WorkflowInput(project: ProjectInspectionInput(
            directory: repo.root, environment: [:])), runner: runner)
        #expect(result.exitCode == 1)
        #expect(result.operation.state == "needs-selection")
        #expect(result.operation.requiredInput == ["--configuration"])
        #expect(result.operation.configuration == nil)
        #expect(!runner.log.all.contains { $0.description == "yarn install --frozen-lockfile" })
    }

    @Test("cancelled operation produces exit 130 and one correlated final event")
    func cancellation() async throws {
        let repo = try iosProject()
        let runner = FakeProcessRunner()
        let events = EventLog()
        let task = Task {
            await WorkflowExecution.run(.up, input: WorkflowInput(project: ProjectInspectionInput(
                directory: repo.root, environment: [:])), runner: runner, onEvent: { events.append($0) })
        }
        task.cancel()
        let result = await task.value
        #expect(result.exitCode == 130)
        #expect(result.operation.state == "cancelled")
        #expect(events.all.last?.kind == "cancelled")
        #expect(events.all.last?.operationId == result.operation.id)
        #expect(runner.log.spawned.isEmpty)
    }

    @Test("infrastructure failure keeps exit 2 and command-specific public fields")
    func infrastructureFailure() async throws {
        let repo = try iosProject()
        let result = await WorkflowExecution.run(.build, input: WorkflowInput(project: ProjectInspectionInput(
            directory: repo.root, environment: [:])), runner: FakeProcessRunner())
        #expect(result.exitCode == 2)
        #expect(result.operation.state == "failed")
        #expect(result.up?.failure != nil)
        #expect(result.up?.stages.isEmpty == true)
    }

    private func iosProject(workspaceOnly: Bool = false) throws -> FixtureRepo {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies":{"react-native":"0.81.0"}}"#)
        try repo.write("yarn.lock", "")
        try repo.directory("node_modules")
        try repo.directory(workspaceOnly ? "ios/MyApp.xcworkspace" : "ios/MyApp.xcodeproj")
        return repo
    }

    private func iosRunner(_ repo: FixtureRepo, workspaceOnly: Bool = false) -> FakeProcessRunner {
        let target = workspaceOnly ? "-workspace \(repo.url("ios/MyApp.xcworkspace").path)" : "-project \(repo.url("ios/MyApp.xcodeproj").path)"
        let destination = "\(target) -scheme MyApp -configuration Debug -destination generic/platform=iOS Simulator"
        return FakeProcessRunner(responses: [
            "xcode-select -p": .ok("/test/Xcode"),
            "xcodebuild -version": .ok("Xcode 27.0\nBuild version 18A100"),
            "xcodebuild -checkFirstLaunchStatus": .ok(""),
            "xcrun simctl list runtimes -j": .ok(#"{"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-0","name":"iOS 27.0","version":"27.0","isAvailable":true}]}"#),
            "node --version": .ok("v22.14.0"),
            "yarn --version": .ok("1.22.22"),
            "yarn install --frozen-lockfile": .ok(""),
            "xcodebuild -list -json \(target)": .ok(workspaceOnly ? #"{"workspace":{"schemes":["MyApp"]}}"# : #"{"project":{"schemes":["MyApp"],"configurations":["Debug","Release"]}}"#),
            "xcodebuild \(destination) build": .ok("** BUILD SUCCEEDED **"),
            "xcodebuild -showBuildSettings -json \(destination)": .ok(#"[{"target":"MyApp","buildSettings":{"CONFIGURATION":"Debug","BUILT_PRODUCTS_DIR":"/test/build","FULL_PRODUCT_NAME":"MyApp.app","PRODUCT_BUNDLE_IDENTIFIER":"com.test.MyApp"}}]"#),
        ])
    }
}

private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [WorkflowEvent] = []
    func append(_ event: WorkflowEvent) { lock.withLock { events.append(event) } }
    var all: [WorkflowEvent] { lock.withLock { events } }
}

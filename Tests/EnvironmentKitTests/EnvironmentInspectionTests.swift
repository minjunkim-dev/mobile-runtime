import Core
import EnvironmentKit
import Foundation
import TestSupport
import Testing

@Suite("shared CLI and GUI environment inspection")
struct EnvironmentInspectionTests {
    @Test("selected RN app shares existing doctor verdicts and explicit Xcode environment")
    func selectedReactNative() async throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies":{"react-native":"0.76.5"}}"#)
        try repo.directory("ios")
        let runner = FakeProcessRunner(responses: [
            "xcodebuild -version": .failed(1, "unavailable test Xcode"),
            "npm config get cache": .ok(repo.root.path),
            "node --version": .ok("v22.11.0"),
        ])
        let input = ProjectInspectionInput(directory: repo.root, environment: ["DEVELOPER_DIR": "/test/Xcode"], platform: .ios)
        let cli = try await EnvironmentInspection.run(input: input, runner: runner)
        let gui = try await EnvironmentInspection.run(input: input, runner: runner)
        #expect(try cli.document(toolVersion: "test").encoded() == gui.document(toolVersion: "test").encoded())
        #expect(cli.report.checks.contains { $0.id == "project.detected" && $0.status == .warning
            && $0.outcome.observed == "React Native 0.76.5, node_modules missing" })
        #expect(cli.selection.selected?.id == ".")
        #expect(runner.log.all.contains { $0.environment["DEVELOPER_DIR"] == "/test/Xcode" })
        #expect(!runner.log.all.contains { $0.executable == "xcode-select" })
        #expect(runner.log.spawned.isEmpty)
        #expect(!runner.log.all.contains { $0.arguments.contains("install") || $0.arguments.contains("build") })
    }

    @Test("managed RN inspection preserves doctor unknown rather than declaring a missing host unsupported")
    func managedReactNative() async throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies":{"react-native":"0.76.5"}}"#)
        let runner = FakeProcessRunner(responses: [
            "xcode-select -p": .failed(1, "not installed"),
            "npm config get cache": .ok(repo.root.path),
            "node --version": .ok("v22.11.0"),
        ])
        let result = try await EnvironmentInspection.run(
            input: ProjectInspectionInput(directory: repo.root, environment: [:], platform: .ios), runner: runner)
        #expect(result.selection.error == nil)
        #expect(result.report.checks.contains { $0.id == "project.detected" && $0.status == .unknown })
    }

    @Test("missing platform returns candidates without project subprocesses")
    func missingPlatform() async throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies":{"react-native":"0.76.5"}}"#)
        try repo.directory("ios")
        try repo.directory("android")
        let runner = FakeProcessRunner(responses: ["xcode-select -p": .failed(1, "not installed")])
        let result = try await EnvironmentInspection.run(input: ProjectInspectionInput(directory: repo.root, environment: [:]), runner: runner)
        #expect(result.selection.requiredInput == ["--platform"])
        #expect(result.exitCode == 1)
        #expect(result.selection.state == "needs-selection")
        #expect(runner.log.all.allSatisfy { $0.executable == "xcode-select" })
        #expect(runner.log.spawned.isEmpty)
    }

    @Test("both callers receive the same host report and additive JSON selection")
    func sameInput() async throws {
        let repo = try FixtureRepo()
        let runner = FakeProcessRunner(responses: ["xcode-select -p": .failed(1, "not installed")])
        let input = ProjectInspectionInput(directory: repo.root, environment: [:])
        let cli = try await EnvironmentInspection.run(input: input, runner: runner)
        let gui = try await EnvironmentInspection.run(input: input, runner: runner)
        #expect(try cli.document(toolVersion: "test").encoded() == gui.document(toolVersion: "test").encoded())
        #expect(cli.selection.candidates.isEmpty)
        #expect(cli.report.checks.contains { $0.id == "xcode.installed" })
        #expect(!cli.report.checks.contains { $0.id == "project.detected" })
        #expect(runner.log.spawned.isEmpty)
        let data = try #require(cli.document(toolVersion: "test").encoded().data(using: .utf8))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["schemaVersion"] as? Int == 1)
        #expect(json["command"] as? String == "doctor")
        #expect(json["selection"] != nil)
        #expect(json["environment"] == nil)
    }
}

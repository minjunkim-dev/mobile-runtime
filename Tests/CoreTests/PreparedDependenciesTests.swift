import Foundation
import TestSupport
import Testing

@testable import Core

@Suite("explicit manually prepared dependencies")
struct PreparedDependenciesTests {
    @Test("Flutter manual preparation reads workspace output and requires no Node installation", arguments: [false, true])
    func flutterWorkspace(_ workspace: Bool) async throws {
        let repo = try flutterFixture(workspace: workspace)
        let runner = FakeProcessRunner()
        let anchor = try #require(ProjectAnchor.detect(from: workspace ? repo.url("apps/client") : repo.root))
        var context = UpContext()
        let result = try await DependenciesStage(anchor: anchor, runner: runner, includePods: false,
            preparedDependencies: true).run(&context)
        #expect(result.status == .skipped)
        #expect(result.detail?.contains("plugin resolver") == true)
        #expect(runner.log.all.isEmpty)
        #expect(!context.nodeModulesReinstalled)
    }

    @Test("Flutter missing prepared output stops without installation", arguments: ["pubspec.lock", ".dart_tool/package_config.json", ".dart_tool/package_graph.json"])
    func flutterMissingOutput(_ name: String) async throws {
        let repo = try flutterFixture(workspace: true)
        try FileManager.default.removeItem(at: repo.url(name))
        let runner = FakeProcessRunner()
        let anchor = try #require(ProjectAnchor.detect(from: repo.url("apps/client")))
        var context = UpContext()
        await #expect(throws: DomainError.self) {
            try await DependenciesStage(anchor: anchor, runner: runner, includePods: false,
                preparedDependencies: true).run(&context)
        }
        #expect(runner.log.all.isEmpty)
    }

    @Test("manual preparation skips installers without claiming lock alignment", arguments: [false, true])
    func readyPreparedInputs(_ includePods: Bool) async throws {
        let repo = try fixture()
        let runner = FakeProcessRunner()
        var context = UpContext()
        let outcome = try await stage(repo, runner: runner, includePods: includePods).run(&context)
        #expect(outcome.status == .skipped)
        #expect(outcome.detail?.contains("lock") == true)
        #expect(!context.nodeModulesReinstalled)
        #expect(runner.log.all.isEmpty)
        #expect(try String(contentsOf: repo.url("node_modules/keep"), encoding: .utf8) == "prepared\n")
        #expect(try String(contentsOf: repo.url("ios/Podfile.lock"), encoding: .utf8) == "locked\n")
    }

    @Test("missing or incomplete prepared inputs stop without running installers", arguments: [
        "node-dir", "node-file", "incomplete", "dangling-marker", "pods-dir", "pods-file",
        "lock", "manifest", "stale", "workspace", "workspace-contents", "workspace-contents-directory",
    ])
    func invalidPreparedInputs(_ fault: String) async throws {
        let repo = try fixture()
        switch fault {
        case "node-dir", "node-file":
            try FileManager.default.removeItem(at: repo.url("node_modules"))
            if fault == "node-file" { try repo.write("node_modules", "not a directory") }
        case "incomplete": try repo.write("node_modules/.mobile-install.incomplete", "")
        case "dangling-marker":
            try FileManager.default.createSymbolicLink(at: repo.url("node_modules/.mobile-install.incomplete"),
                withDestinationURL: repo.url("missing-marker-target"))
        case "pods-dir", "pods-file":
            try FileManager.default.removeItem(at: repo.url("ios/Pods"))
            if fault == "pods-file" { try repo.write("ios/Pods", "not a directory") }
        case "lock": try FileManager.default.removeItem(at: repo.url("ios/Podfile.lock"))
        case "manifest": try FileManager.default.removeItem(at: repo.url("ios/Pods/Manifest.lock"))
        case "stale": try repo.write("ios/Pods/Manifest.lock", "other lock\n")
        case "workspace": try FileManager.default.removeItem(at: repo.url("ios/App.xcworkspace"))
        case "workspace-contents-directory":
            try FileManager.default.removeItem(at: repo.url("ios/App.xcworkspace/contents.xcworkspacedata"))
            try repo.directory("ios/App.xcworkspace/contents.xcworkspacedata")
        default: try FileManager.default.removeItem(at: repo.url("ios/App.xcworkspace/contents.xcworkspacedata"))
        }
        let runner = FakeProcessRunner()
        var context = UpContext()
        do {
            _ = try await stage(repo, runner: runner).run(&context)
            Issue.record("accepted invalid prepared input: \(fault)")
        } catch is DomainError {
            #expect(runner.log.all.isEmpty)
            #expect(!context.nodeModulesReinstalled)
        }
    }

    @Test("Android manual preparation requires no Apple dependency output")
    func androidWithoutPods() async throws {
        let repo = try fixture()
        try FileManager.default.removeItem(at: repo.url("ios"))
        let runner = FakeProcessRunner()
        var context = UpContext()
        let outcome = try await stage(repo, runner: runner, includePods: false).run(&context)
        #expect(outcome.status == .skipped)
        #expect(runner.log.all.isEmpty)
    }

    @Test("manual preparation reads the hoisted workspace root")
    func workspaceRoot() async throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"workspaces":["packages/*"]}"#)
        try repo.write("package-lock.json", "{}")
        try repo.directory("node_modules")
        try repo.write("packages/app/package.json", #"{"dependencies":{"react-native":"0.81.0"}}"#)
        let anchor = try #require(ProjectAnchor.detect(from: repo.url("packages/app")))
        let runner = FakeProcessRunner()
        var context = UpContext()
        let outcome = try await DependenciesStage(anchor: anchor, runner: runner, includePods: false,
            preparedDependencies: true).run(&context)
        #expect(outcome.status == .skipped)
        #expect(runner.log.all.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: repo.url("packages/app/node_modules").path))
    }

    @Test("manual preparation still observes cancellation")
    func cancellation() async throws {
        let repo = try fixture()
        let runner = FakeProcessRunner()
        let subject = try stage(repo, runner: runner)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            var context = UpContext()
            return try await subject.run(&context)
        }
        do {
            _ = try await task.value
            Issue.record("cancelled manual preparation succeeded")
        } catch is CancellationError {
            #expect(runner.log.all.isEmpty)
        }
    }

    @Test("approved setup alignment cannot silently become manual reuse")
    func conflictingModes() async throws {
        let repo = try fixture()
        let anchor = try #require(ProjectAnchor.detect(from: repo.root))
        let runner = FakeProcessRunner()
        var context = UpContext()
        await #expect(throws: DomainError.self) {
            try await DependenciesStage(anchor: anchor, runner: runner, forceLockedAlignment: true,
                preparedDependencies: true).run(&context)
        }
        #expect(runner.log.all.isEmpty)
    }

    private func flutterFixture(workspace: Bool) throws -> FixtureRepo {
        let repo = try FixtureRepo()
        let declaration = "name: example\nenvironment:\n  sdk: ^3.6.0\ndependencies:\n  flutter:\n    sdk: flutter\n"
        try repo.write("pubspec.yaml", declaration + (workspace ? "workspace:\n  - apps/*\n" : ""))
        if workspace { try repo.write("apps/client/pubspec.yaml", declaration.replacingOccurrences(of: "name: example", with: "name: client") + "resolution: workspace\n") }
        try repo.write("pubspec.lock", "packages: {}\n")
        try repo.write(".dart_tool/package_config.json", "{}")
        try repo.write(".dart_tool/package_graph.json", "{}")
        return repo
    }

    private func fixture() throws -> FixtureRepo {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies":{"react-native":"0.81.0"}}"#)
        try repo.write("package-lock.json", "{}")
        try repo.write("node_modules/keep", "prepared\n")
        try repo.write("ios/Podfile", "platform :ios, '16.4'\n")
        try repo.write("ios/Podfile.lock", "locked\n")
        try repo.write("ios/Pods/Manifest.lock", "locked\n")
        try repo.write("ios/App.xcworkspace/contents.xcworkspacedata", "<Workspace/>\n")
        return repo
    }

    private func stage(_ repo: FixtureRepo, runner: FakeProcessRunner, includePods: Bool = true) throws -> DependenciesStage {
        DependenciesStage(anchor: try #require(ProjectAnchor.detect(from: repo.root)), runner: runner,
            includePods: includePods, preparedDependencies: true, logs: try RunLogs.temporary())
    }
}

import Core
import EnvironmentKit
import Foundation
import TestSupport
import Testing

@Suite("approved environment preparation")
struct PreparationExecutionTests {
    @Test("plan includes both RN platforms without changing dependencies")
    func planOnly() async throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies":{"react-native":"0.81.0"}}"#)
        try repo.write("yarn.lock", "")
        let runner = FakeProcessRunner()
        let result = await PreparationExecution.run(input: ProjectInspectionInput(directory: repo.root, environment: [:], platform: .ios), planOnly: true, runner: runner)
        #expect(result.exitCode == 0)
        #expect(result.operation.state == "needs-approval")
        #expect(result.plan?.platforms.map(\.platform) == [.ios, .android])
        #expect(!runner.log.all.contains { $0.arguments.contains("install") })
        #expect(!FileManager.default.fileExists(atPath: repo.url("node_modules").path))
    }

    @Test("approval does not grant repository trust and changed declarations invalidate approval")
    func approvalBoundary() async throws {
        let repo = try project()
        let runner = tools(repo)
        let input = ProjectInspectionInput(directory: repo.root, environment: [:])
        let plan = await PreparationExecution.run(input: input, planOnly: true, runner: runner)
        let id = try #require(plan.plan?.id)
        let untrusted = await PreparationExecution.run(input: input, approvedPlanID: id, runner: runner)
        #expect(untrusted.operation.state == "waiting-manual")
        let diagnostic = try plan.encoded(toolVersion: "test")
        #expect(untrusted.operation.requiredInput == ["--trust-repository"], Comment(rawValue: diagnostic))
        #expect(!runner.log.all.contains { $0.description == "yarn install --frozen-lockfile" })
        var selectedTool = tools(repo)
        selectedTool.responses["/usr/bin/which node"] = .ok("/another/bin/node")
        let changedPath = await PreparationExecution.run(input: input, approvedPlanID: id, trustRepository: true, runner: selectedTool)
        #expect(changedPath.operation.state == "needs-approval")
        #expect(!selectedTool.log.all.contains { $0.description == "yarn install --frozen-lockfile" })
        var unknownTool = tools(repo)
        unknownTool.responses["/usr/bin/which node"] = .failed(1, "no known node executable")
        let unknownPlan = await PreparationExecution.run(input: input, planOnly: true, runner: unknownTool)
        #expect(unknownPlan.plan?.steps.first { $0.id == "dependencies.node" }?.kind == "migration")
        let unknownApproved = await PreparationExecution.run(input: input, approvedPlanID: try #require(unknownPlan.plan?.id),
            trustRepository: true, runner: unknownTool)
        #expect(unknownApproved.operation.state == "waiting-manual")
        #expect(!unknownTool.log.all.contains { $0.description == "yarn install --frozen-lockfile" })
        try repo.write("yarn.lock", "changed lock")
        let changed = await PreparationExecution.run(input: input, approvedPlanID: id, trustRepository: true, runner: runner)
        #expect(changed.operation.state == "needs-approval")
        #expect(changed.plan?.id != id)
        #expect(!runner.log.all.contains { $0.description == "yarn install --frozen-lockfile" })
    }

    @Test("completed Node alignment is preserved while the other platform waits manually")
    func partialPreparation() async throws {
        let repo = try project()
        let runner = tools(repo)
        let input = ProjectInspectionInput(directory: repo.root, environment: [:])
        let plan = await PreparationExecution.run(input: input, planOnly: true, runner: runner)
        let id = try #require(plan.plan?.id)
        let prepared = await PreparationExecution.run(input: input, approvedPlanID: id, trustRepository: true, runner: runner)
        #expect(prepared.exitCode == 1)
        #expect(prepared.operation.state == "partial")
        #expect(prepared.operation.completed == ["dependencies.node"])
        #expect(prepared.plan?.platforms.first { $0.platform == .ios }?.state == "succeeded")
        #expect(prepared.plan?.platforms.first { $0.platform == .android }?.state == "waiting-manual")
        #expect(FileManager.default.fileExists(atPath: repo.url("node_modules").path))
        #expect(try Data(contentsOf: repo.url("yarn.lock")) == Data())
    }

    @Test("a dependency script's source change stops later commands and is never restored")
    func sourceMutation() async throws {
        let repo = try project()
        let runner = MutatingRunner(base: tools(repo), file: repo.url("package.json"))
        let input = ProjectInspectionInput(directory: repo.root, environment: [:])
        let plan = await PreparationExecution.run(input: input, planOnly: true, runner: runner)
        let prepared = await PreparationExecution.run(input: input, approvedPlanID: try #require(plan.plan?.id), trustRepository: true, runner: runner)
        #expect(prepared.exitCode == 1)
        #expect(prepared.operation.state == "failed")
        #expect(prepared.operation.changedFiles.count == 1)
        let changed = URL(fileURLWithPath: try #require(prepared.operation.changedFiles.first))
        let changedFolder = try FolderIdentity(directory: changed.deletingLastPathComponent())
        let projectFolder = try FolderIdentity(directory: repo.root)
        #expect(changed.lastPathComponent == "package.json")
        #expect(changedFolder == projectFolder)
        #expect(prepared.operation.completed == ["dependencies.node"])
        #expect(try String(contentsOf: repo.url("package.json"), encoding: .utf8) == "unexpected source change")
        #expect(FileManager.default.fileExists(atPath: repo.url("node_modules").path))
    }

    @Test("Flutter plans express both platforms as provider work without fake installation")
    func flutterPlan() async throws {
        let repo = try FixtureRepo()
        try repo.write("pubspec.yaml", "name: example\n")
        let runner = FakeProcessRunner()
        let input = ProjectInspectionInput(directory: repo.root, environment: [:], platform: .android)
        let plan = await PreparationExecution.run(input: input, planOnly: true, runner: runner)
        #expect(plan.plan?.projectKind == "flutter")
        #expect(plan.plan?.platforms.map(\.platform) == [.ios, .android])
        let result = await PreparationExecution.run(input: input, approvedPlanID: try #require(plan.plan?.id), runner: runner)
        #expect(result.exitCode == 1)
        #expect(result.operation.state == "waiting-manual")
        #expect(result.operation.completed.isEmpty)
        #expect(runner.log.all.isEmpty)
    }

    @Test("cancellation preserves a completed install and prevents further preparation commands")
    func cancelledAfterInstall() async throws {
        let repo = try project()
        let base = tools(repo)
        let runner = CancellingRunner(base: base)
        let input = ProjectInspectionInput(directory: repo.root, environment: [:])
        let plan = await PreparationExecution.run(input: input, planOnly: true, runner: runner)
        let approvedID = try #require(plan.plan?.id)
        let task = Task { await PreparationExecution.run(input: input, approvedPlanID: approvedID, trustRepository: true, runner: runner) }
        let result = await task.value
        #expect(result.exitCode == 130)
        #expect(result.operation.state == "cancelled")
        #expect(result.operation.completed == ["dependencies.node"])
        #expect(FileManager.default.fileExists(atPath: repo.url("node_modules").path))
        #expect(FileManager.default.fileExists(atPath: repo.url("node_modules/.mobile-install.incomplete").path))
        #expect(base.log.all.last?.description == "yarn install --frozen-lockfile")
    }

    @Test("failed installer reports domain failure and retains its partial dependency marker for retry")
    func installFailure() async throws {
        let repo = try project()
        var runner = tools(repo)
        runner.responses["yarn install --frozen-lockfile"] = .failed(1, "fixture installer failed")
        let input = ProjectInspectionInput(directory: repo.root, environment: [:])
        let plan = await PreparationExecution.run(input: input, planOnly: true, runner: runner)
        let result = await PreparationExecution.run(input: input, approvedPlanID: try #require(plan.plan?.id), trustRepository: true, runner: runner)
        #expect(result.exitCode == 1)
        #expect(result.operation.state == "failed")
        #expect(result.operation.completed.isEmpty)
        #expect(result.operation.remaining.contains("dependencies.node"))
        #expect(FileManager.default.fileExists(atPath: repo.url("node_modules/.mobile-install.incomplete").path))
        let retry = await PreparationExecution.run(input: input, planOnly: true, runner: runner)
        #expect(retry.plan?.id != plan.plan?.id)
    }

    @Test("private environment values and logs never enter the public plan or invalidate approval")
    func privateValues() async throws {
        let repo = try project()
        try repo.write(".env", "API_KEY=first-private-value")
        try repo.write("debug.log", "one")
        let runner = tools(repo)
        let input = ProjectInspectionInput(directory: repo.root, environment: [:])
        let initial = await PreparationExecution.run(input: input, planOnly: true, runner: runner)
        try repo.write(".env", "API_KEY=second-private-value")
        try repo.write("debug.log", "two")
        let changed = await PreparationExecution.run(input: input, planOnly: true, runner: runner)
        #expect(initial.plan?.id == changed.plan?.id)
        #expect(changed.plan?.files.keys.contains { $0.hasSuffix("/.env") || $0.hasSuffix("/debug.log") } == false)
        let publicJSON = try changed.encoded(toolVersion: "test")
        #expect(!publicJSON.contains("private-value"))
        #expect(!publicJSON.contains("/.env"))
    }

    @Test("same dependency target rejects a second approved setup while the first owns it")
    func overlappingSetup() async throws {
        let repo = try project()
        let gate = InstallGate()
        let runner = WaitingRunner(base: tools(repo), gate: gate)
        let input = ProjectInspectionInput(directory: repo.root, environment: [:])
        let initial = await PreparationExecution.run(input: input, planOnly: true, runner: runner)
        let id = try #require(initial.plan?.id)
        let first = Task { await PreparationExecution.run(input: input, approvedPlanID: id, trustRepository: true, runner: runner) }
        await gate.waitUntilStarted()
        #expect(await gate.started)
        let current = await PreparationExecution.run(input: input, planOnly: true, runner: tools(repo))
        let second = await PreparationExecution.run(input: input, approvedPlanID: try #require(current.plan?.id), trustRepository: true, runner: tools(repo))
        #expect(second.exitCode == 1)
        #expect(second.operation.error?.contains("Another setup") == true)
        #expect(second.operation.completed.isEmpty)
        await gate.release()
        let completed = await first.value
        #expect(completed.operation.completed == ["dependencies.node"])
    }

    @Test("Bundle destination changes invalidate approval and execution preserves the frozen effective path")
    func bundleDestination() async throws {
        let repo = try project()
        try repo.write("Gemfile", "gem 'cocoapods', '1.16.1'\n")
        try repo.write("Gemfile.lock", "GEM\n  specs:\n    cocoapods (1.16.1)\n")
        try repo.write("ios/Podfile", "platform :ios, '15.1'\n")
        try repo.write("ios/Podfile.lock", "locked pods")
        var runner = tools(repo)
        runner.responses["bundle exec pod --version"] = .ok("1.16.1")
        runner.responses["bundle --version"] = .ok("Bundler version 2.6.9")
        runner.responses["bundle config get path --parseable"] = .ok("path=vendor/bundle")
        runner.responses["ruby -rbundler -e print Bundler.bundle_path"] = .ok(repo.url("vendor/bundle/ruby/3.3.0").path)
        runner.responses["bundle check"] = .failed(1, "missing locked gems")
        runner.responses["bundle install"] = .ok("")
        runner.responses["bundle exec pod install --deployment"] = .ok("")
        try repo.directory("node_modules")
        try repo.write("ios/Pods/Manifest.lock", "locked pods")
        let input = ProjectInspectionInput(directory: repo.root, environment: [:])
        let initial = await PreparationExecution.run(input: input, planOnly: true, runner: runner)
        let id = try #require(initial.plan?.id)
        #expect(initial.plan?.steps.first { $0.id == "dependencies.gems" }?.target == repo.url("vendor/bundle/ruby/3.3.0").path)
        var moved = runner
        moved.responses["bundle config get path --parseable"] = .ok("path=other-bundle")
        moved.responses["ruby -rbundler -e print Bundler.bundle_path"] = .ok(repo.url("other-bundle/ruby/3.3.0").path)
        let stale = await PreparationExecution.run(input: input, approvedPlanID: id, trustRepository: true, runner: moved)
        #expect(stale.operation.state == "needs-approval")
        #expect(!moved.log.all.contains { $0.description == "bundle install" })
        let prepared = await PreparationExecution.run(input: input, approvedPlanID: id, trustRepository: true, runner: runner)
        #expect(prepared.operation.completed == ["dependencies.node", "dependencies.gems", "dependencies.pods"])
        let install = try #require(runner.log.first(matching: "bundle install"))
        #expect(install.environment["BUNDLE_FROZEN"] == "true")
        #expect(install.environment["BUNDLE_PATH"]?.hasSuffix("/vendor/bundle") == true)
        #expect(install.environment["BUNDLE_PATH"]?.hasSuffix("/ruby/3.3.0") == false)
        #expect(runner.log.all.contains { $0.description == "bundle exec pod install --deployment" })
        #expect(try String(contentsOf: repo.url("ios/Podfile.lock"), encoding: .utf8) == "locked pods")
        var tilde = runner
        tilde.responses["bundle config get path --parseable"] = .ok("path=~/runstir-202-probe")
        let expanded = ("~/runstir-202-probe" as NSString).expandingTildeInPath
        tilde.responses["ruby -rbundler -e print Bundler.bundle_path"] = .ok(expanded + "/ruby/3.3.0")
        let tildePlan = await PreparationExecution.run(input: input, planOnly: true, runner: tilde)
        #expect(tildePlan.plan?.steps.first { $0.id == "dependencies.gems" }?.environment["BUNDLE_PATH"] == expanded)
        #expect(tildePlan.plan?.steps.first { $0.id == "dependencies.gems" }?.target == expanded + "/ruby/3.3.0")
        let mismatch = await PreparationExecution.run(input: input, planOnly: true,
            runner: ChangedBundleDestinationRunner(base: tilde))
        #expect(mismatch.plan?.steps.first { $0.id == "dependencies.gems" }?.kind == "migration")
        #expect(mismatch.plan?.steps.first { $0.id == "dependencies.pods" }?.kind == "migration")
        let changing = ChangedNodeVersionRunner(base: FakeProcessRunner(responses: runner.responses))
        let beforeChange = await PreparationExecution.run(input: input, planOnly: true, runner: changing)
        let changedTools = await PreparationExecution.run(input: input, approvedPlanID: try #require(beforeChange.plan?.id),
            trustRepository: true, runner: changing)
        #expect(changedTools.operation.state == "failed")
        #expect(changedTools.operation.completed == ["dependencies.node"])
        #expect(changedTools.operation.error?.contains("conditions changed") == true)
        #expect(!changing.base.log.all.contains { $0.description == "bundle install" })
        let movedDuringRun = ChangedEffectiveBundleRunner(base: FakeProcessRunner(responses: runner.responses))
        let stableBundlePlan = await PreparationExecution.run(input: input, planOnly: true, runner: movedDuringRun)
        let prevented = await PreparationExecution.run(input: input, approvedPlanID: try #require(stableBundlePlan.plan?.id),
            trustRepository: true, runner: movedDuringRun)
        #expect(prevented.operation.state == "failed")
        #expect(prevented.operation.completed == ["dependencies.node"])
        #expect(!movedDuringRun.base.log.all.contains { $0.description == "bundle install" })
    }

    @Test("different projects cannot prepare one shared Bundle destination concurrently")
    func sharedBundleTarget() async throws {
        let firstRepo = try project()
        let secondRepo = try project()
        let shared = try FixtureRepo()
        func bundled(_ repo: FixtureRepo) throws -> FakeProcessRunner {
            try repo.write("Gemfile", "gem 'cocoapods', '1.16.1'\n")
            try repo.write("Gemfile.lock", "GEM\n  specs:\n    cocoapods (1.16.1)\n")
            try repo.write("ios/Podfile", "platform :ios, '15.1'\n")
            try repo.write("ios/Podfile.lock", "locked pods")
            var runner = tools(repo)
            runner.responses["bundle exec pod --version"] = .ok("1.16.1")
            runner.responses["bundle --version"] = .ok("Bundler version 2.6.9")
            runner.responses["bundle config get path --parseable"] = .ok("path=\(shared.url("bundle").path)")
            runner.responses["ruby -rbundler -e print Bundler.bundle_path"] = .ok(shared.url("bundle/ruby/3.3.0").path)
            runner.responses["bundle check"] = .failed(1, "missing gems")
            runner.responses["bundle install"] = .ok("")
            runner.responses["bundle exec pod install --deployment"] = .ok("")
            return runner
        }
        let firstTools = try bundled(firstRepo)
        let secondTools = try bundled(secondRepo)
        let gate = InstallGate()
        let firstInput = ProjectInspectionInput(directory: firstRepo.root, environment: [:])
        let secondInput = ProjectInspectionInput(directory: secondRepo.root, environment: [:])
        let firstPlan = await PreparationExecution.run(input: firstInput, planOnly: true, runner: firstTools)
        let secondPlan = await PreparationExecution.run(input: secondInput, planOnly: true, runner: secondTools)
        let id = try #require(firstPlan.plan?.id)
        let task = Task { await PreparationExecution.run(input: firstInput, approvedPlanID: id,
            trustRepository: true, runner: WaitingRunner(base: firstTools, gate: gate)) }
        await gate.waitUntilStarted()
        #expect(await gate.started)
        let denied = await PreparationExecution.run(input: secondInput, approvedPlanID: try #require(secondPlan.plan?.id),
            trustRepository: true, runner: secondTools)
        #expect(denied.exitCode == 1)
        #expect(denied.operation.error?.contains("Another setup") == true)
        #expect(!secondTools.log.all.contains { $0.description == "yarn install --frozen-lockfile" })
        await gate.release()
        _ = await task.value
        let retry = await PreparationExecution.run(input: secondInput, approvedPlanID: try #require(secondPlan.plan?.id),
            trustRepository: true, runner: secondTools)
        #expect(retry.operation.completed == ["dependencies.node", "dependencies.gems", "dependencies.pods"])
    }

    private func project() throws -> FixtureRepo {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies":{"react-native":"0.81.0"}}"#)
        try repo.write("yarn.lock", "")
        try repo.directory("ios/MyApp.xcodeproj")
        return repo
    }

    private func tools(_ repo: FixtureRepo) -> FakeProcessRunner {
        FakeProcessRunner(responses: [
            "xcode-select -p": .ok("/test/Xcode"),
            "xcodebuild -version": .ok("Xcode 27.0\nBuild version 18A100"),
            "xcodebuild -checkFirstLaunchStatus": .ok(""),
            "xcrun simctl list runtimes -j": .ok(#"{"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-0","name":"iOS 27.0","version":"27.0","isAvailable":true}]}"#),
            "node --version": .ok("v22.14.0"),
            "/usr/bin/which node": .ok("/test/bin/node"),
            "/usr/bin/which yarn": .ok("/test/bin/yarn"),
            "/usr/bin/which ruby": .ok("/test/bin/ruby"),
            "/usr/bin/which bundle": .ok("/test/bin/bundle"),
            "/usr/bin/which pod": .ok("/test/bin/pod"),
            "yarn --version": .ok("1.22.22"),
            "yarn install --frozen-lockfile": .ok(""),
            "xcodebuild -list -json -project \(repo.url("ios/MyApp.xcodeproj").path)": .ok(#"{"project":{"schemes":["MyApp"]}}"#),
        ])
    }
}

private struct ChangedBundleDestinationRunner: ProcessRunner {
    let base: FakeProcessRunner
    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        let result = try await base.run(command, onLine: onLine)
        if command.description == "ruby -rbundler -e print Bundler.bundle_path", command.environment["BUNDLE_PATH"] != nil {
            return ProcessResult(terminationStatus: .exited(0), standardOutput: "/different/destination", standardError: "")
        }
        return result
    }
    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
        try await base.spawnDetached(command, logFile: logFile)
    }
}

private struct ChangedNodeVersionRunner: ProcessRunner {
    let base: FakeProcessRunner
    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        let result = try await base.run(command, onLine: onLine)
        if command.description == "node --version", base.log.all.contains(where: { $0.description == "yarn install --frozen-lockfile" }) {
            return ProcessResult(terminationStatus: .exited(0), standardOutput: "v22.15.0", standardError: "")
        }
        return result
    }
    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
        try await base.spawnDetached(command, logFile: logFile)
    }
}

private struct ChangedEffectiveBundleRunner: ProcessRunner {
    let base: FakeProcessRunner
    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        let result = try await base.run(command, onLine: onLine)
        if command.description == "ruby -rbundler -e print Bundler.bundle_path", command.environment["BUNDLE_PATH"] != nil,
           base.log.all.contains(where: { $0.description == "yarn install --frozen-lockfile" }) {
            return ProcessResult(terminationStatus: .exited(0), standardOutput: "/different/effective/destination", standardError: "")
        }
        return result
    }
    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
        try await base.spawnDetached(command, logFile: logFile)
    }
}

private struct MutatingRunner: ProcessRunner {
    let base: FakeProcessRunner
    let file: URL
    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        let result = try await base.run(command, onLine: onLine)
        if command.description == "yarn install --frozen-lockfile" {
            try Data("unexpected source change".utf8).write(to: file)
        }
        return result
    }
    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
        try await base.spawnDetached(command, logFile: logFile)
    }
}

private struct CancellingRunner: ProcessRunner {
    let base: FakeProcessRunner
    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        let result = try await base.run(command, onLine: onLine)
        if command.description == "yarn install --frozen-lockfile" { withUnsafeCurrentTask { $0?.cancel() } }
        return result
    }
    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
        try await base.spawnDetached(command, logFile: logFile)
    }
}

private actor InstallGate {
    private(set) var started = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        await withCheckedContinuation { continuation = $0 }
    }
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }
    func release() { continuation?.resume(); continuation = nil }
}

private struct WaitingRunner: ProcessRunner {
    let base: FakeProcessRunner
    let gate: InstallGate
    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        let result = try await base.run(command, onLine: onLine)
        if command.description == "yarn install --frozen-lockfile" { await gate.wait() }
        return result
    }
    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
        try await base.spawnDetached(command, logFile: logFile)
    }
}

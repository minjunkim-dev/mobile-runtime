import Core
import EnvironmentKit
import Foundation
import TestSupport
import Testing

@Suite("shared native iOS workflows")
struct NativeIOSWorkflowTests {
    @Test("native build uses the selected root container without JavaScript or installation")
    func nativeBuild() async throws {
        let repo = try project()
        let original = try Data(contentsOf: repo.url("App.xcodeproj/project.pbxproj"))
        let runner = runner(repo)
        let result = await WorkflowExecution.run(.build, input: input(repo), runner: runner)
        #expect(result.exitCode == 0, Comment(rawValue: result.up?.failure?.message ?? ""))
        #expect(result.up?.stages.map(\.id) == ["validate", "build"])
        #expect(result.operation.scheme == "App")
        #expect(result.operation.configuration == "Debug")
        #expect(result.up?.context.product?.bundleIdentifier == "com.test.App")
        #expect(try Data(contentsOf: repo.url("App.xcodeproj/project.pbxproj")) == original)
        #expect(!runner.log.all.contains { ["node", "npm", "yarn", "pnpm", "pod", "bundle"].contains($0.executable) })
        #expect(!runner.log.all.contains { $0.executable == "xcrun" && ($0.arguments.contains("install") || $0.arguments.contains("launch") || $0.arguments.contains("boot")) })
        #expect(runner.log.spawned.isEmpty)
    }

    @Test("a private scheme is rejected before build")
    func privateScheme() async throws {
        let repo = try project()
        var runner = runner(repo)
        runner.responses[list(repo)] = .ok(#"{"project":{"schemes":["App","Private"],"configurations":["Debug","Release"]}}"#)
        let result = await WorkflowExecution.run(.build, input: input(repo, scheme: "Private"), runner: runner)
        #expect(result.exitCode == 1)
        #expect(!runner.log.all.contains { $0.executable == "xcodebuild" && $0.arguments.contains("build") })
        #expect(!runner.log.all.contains { $0.executable == "xcrun" && $0.arguments.contains("install") })
    }

    @Test("native cancellation remains correlated and never starts detached work")
    func cancellation() async throws {
        let repo = try project()
        let runner = runner(repo)
        let task = Task { await WorkflowExecution.run(.up, input: input(repo), runner: runner) }
        task.cancel()
        let result = await task.value
        #expect(result.exitCode == 130)
        #expect(result.operation.state == "cancelled")
        #expect(runner.log.spawned.isEmpty)
    }

    @Test("native up installs and launches only the selected device without Metro")
    func nativeUp() async throws {
        let repo = try project()
        var runner = runner(repo)
        addUpResponses(&runner, repo)
        let leases = temporaryLeases()
        let result = await WorkflowExecution.run(.up, input: input(repo, device: "A"), runner: runner, leases: leases)
        #expect(result.exitCode == 0, Comment(rawValue: result.up?.failure?.message ?? ""))
        #expect(result.up?.stages.map(\.id) == ["validate", "device", "build", "install", "launch"])
        #expect(result.up?.context.appPid == 3538)
        #expect(result.operation.device == "A")
        #expect(runner.log.spawned.isEmpty)
        #expect(!runner.log.all.contains { $0.executable == "curl" || $0.executable == "node" || $0.arguments.contains("shutdown") })
        let claim = try await #require(throws: ResourceConflict.self) {
            try await leases.check(device: .device(.ios, "A"), project: "/other") { _ in .running("owned app") }
        }
        #expect(claim.owner?.operationId == result.operation.id)
    }

    @Test("native down stops its recorded app while another client owns Metro's port")
    func nativeDown() async throws {
        let repo = try project()
        let logs = RunLogs(project: repo.root)
        #expect(InstallRecord(udid: "A", bundleId: "com.test.App").write(to: logs) != nil)
        let leases = temporaryLeases()
        let owner = LeaseOwner(operationId: "other-metro", command: "up", project: "/other")
        let held = try leases.acquire([.port(8081)], owner: owner)
        defer { held.release() }
        var runner = runner(repo)
        runner.responses["xcrun simctl terminate A com.test.App"] = .ok("")
        let result = await WorkflowExecution.run(.down, input: input(repo), runner: runner, leases: leases)
        #expect(result.exitCode == 0)
        #expect(result.down?.items.map(\.id) == ["app"])
        #expect(runner.log.all.filter { $0.executable == "xcrun" }.map(\.description) == ["xcrun simctl terminate A com.test.App"])
        #expect(!runner.log.all.contains { $0.executable == "kill" || $0.executable == "curl" })
        #expect(InstallRecord.read(from: logs)?.bundleId == "com.test.App")
    }

    @Test("a native device lease conflict stops before build or installation")
    func nativeConflict() async throws {
        let repo = try project()
        var runner = runner(repo)
        addUpResponses(&runner, repo)
        let leases = temporaryLeases()
        let owner = LeaseOwner(operationId: "other-device", command: "up", project: "/other")
        let held = try leases.acquire([.device(.ios, "A")], owner: owner)
        defer { held.release() }
        let result = await WorkflowExecution.run(.up, input: input(repo, device: "A"), runner: runner, leases: leases)
        #expect(result.exitCode == 1)
        #expect(result.operation.conflict?.owner == owner)
        #expect(!runner.log.all.contains { $0.arguments.contains("build") || $0.arguments.contains("install") })
    }

    @Test("an unresolved app target and an effective Release fallback never become a successful Debug build", arguments: [false, true])
    func unresolvedTarget(fallback: Bool) async throws {
        let repo = try project()
        var runner = runner(repo)
        runner.responses[settings(repo)] = fallback
            ? .ok(#"[{"target":"App","buildSettings":{"CONFIGURATION":"Release","PLATFORM_NAME":"iphonesimulator","IPHONEOS_DEPLOYMENT_TARGET":"17.0","FULL_PRODUCT_NAME":"App.app"}}]"#)
            : .ok(#"[{"target":"Library","buildSettings":{"CONFIGURATION":"Debug","PLATFORM_NAME":"iphonesimulator","IPHONEOS_DEPLOYMENT_TARGET":"17.0","FULL_PRODUCT_NAME":"Library.framework"}}]"#)
        let result = await WorkflowExecution.run(.build, input: input(repo), runner: runner)
        #expect(result.exitCode == 1)
        #expect(!runner.log.all.contains { $0.arguments.contains("build") })
        if fallback { #expect(result.operation.requiredInput == ["--configuration"]) }
    }

    @Test("native CocoaPods preparation is manual and never starts an installer")
    func nativeDependencies() async throws {
        let repo = try project()
        try repo.write("Podfile", "platform :ios, '17.0'")
        let runner = runner(repo)
        let inspection = try await EnvironmentInspection.run(input: ProjectInspectionInput(directory: repo.root, environment: [:]), runner: runner)
        let check = try #require(inspection.report.checks.first { $0.id == "project.native-ios" })
        #expect(check.status == .error)
        #expect(check.outcome.remediation?.summary.contains("Prepare dependencies") == true)
        let result = await WorkflowExecution.run(.build, input: input(repo), runner: runner)
        #expect(result.exitCode == 1)
        #expect(!runner.log.all.contains { ["pod", "bundle", "npm", "yarn"].contains($0.executable) || $0.arguments.contains("build") })
    }

    @Test("only Simulators meeting the resolved app target remain selectable")
    func minimumRuntime() async throws {
        let repo = try project()
        var runner = runner(repo)
        addUpResponses(&runner, repo)
        runner.responses[settings(repo)] = .ok(#"[{"target":"App","buildSettings":{"CONFIGURATION":"Debug","PLATFORM_NAME":"iphonesimulator","IPHONEOS_DEPLOYMENT_TARGET":"27.0","FULL_PRODUCT_NAME":"App.app"}}]"#)
        runner.responses["xcrun simctl list devices -j"] = .ok(#"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":[{"name":"Old","udid":"OLD","state":"Booted","isAvailable":true}],"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"name":"Current","udid":"A","state":"Booted","isAvailable":true}]}}"#)
        let result = await WorkflowExecution.run(.up, input: input(repo, device: "OLD"), runner: runner, leases: temporaryLeases())
        #expect(result.exitCode == 1)
        #expect(result.operation.devices.map(\.id) == ["A"])
        #expect(!runner.log.all.contains { $0.arguments.contains("build") || $0.arguments.contains("install") })
    }

    @Test("a selected workspace uses shared schemes from its nested group members")
    func nativeWorkspace() async throws {
        let repo = try FixtureRepo()
        try repo.write("Chosen.xcworkspace/contents.xcworkspacedata", #"<Workspace><Group location="group:Apps"><FileRef location="group:Nested.xcodeproj"/></Group></Workspace>"#)
        try repo.write("Apps/Nested.xcodeproj/project.pbxproj", "nested app")
        try repo.write("Apps/Nested.xcodeproj/xcshareddata/xcschemes/App.xcscheme", "<Scheme/>")
        let target = "-workspace \(repo.url("Chosen.xcworkspace").path) -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile"
        let destination = "\(target) -scheme App -configuration Debug -destination generic/platform=iOS Simulator"
        let measured = #"[{"target":"App","buildSettings":{"CONFIGURATION":"Debug","PLATFORM_NAME":"iphonesimulator","IPHONEOS_DEPLOYMENT_TARGET":"17.0","FULL_PRODUCT_NAME":"App.app","BUILT_PRODUCTS_DIR":"/test/build","PRODUCT_BUNDLE_IDENTIFIER":"com.test.App"}}]"#
        let runner = FakeProcessRunner(responses: [
            "xcode-select -p": .ok("/test/Xcode"),
            "xcodebuild -version": .ok("Xcode 27.0\nBuild version 18A100"),
            "xcodebuild -checkFirstLaunchStatus": .ok(""),
            "xcrun simctl list runtimes -j": .ok(#"{"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-0","name":"iOS 27.0","version":"27.0","isAvailable":true}]}"#),
            "xcodebuild -list -json \(target)": .ok(#"{"workspace":{"schemes":["App","Private"]}}"#),
            "xcodebuild -showBuildSettings -json \(destination)": .ok(measured),
            "xcodebuild \(destination) CODE_SIGNING_ALLOWED=NO build": .ok("** BUILD SUCCEEDED **"),
            "xcodebuild -showBuildSettings -json \(destination) CODE_SIGNING_ALLOWED=NO": .ok(measured),
        ])
        let result = await WorkflowExecution.run(.build, input: input(repo), runner: runner)
        #expect(result.exitCode == 0, Comment(rawValue: result.up?.failure?.message ?? ""))
        #expect(result.operation.selection?.selected?.iosContainer == "Chosen.xcworkspace")
        #expect(result.operation.schemes == ["App"])
        #expect(result.operation.configuration == "Debug")
        #expect(!runner.log.all.contains { $0.executable == "xcodebuild" && $0.arguments.contains("-project") })
    }

    @Test("future framework candidates remain classified without entering React Native workflows")
    func futureFramework() async throws {
        let repo = try FixtureRepo()
        try repo.write("settings.gradle", "rootProject.name = 'native'")
        try repo.write("gradlew", "#!/bin/sh")
        let runner = FakeProcessRunner()
        let inspection = try await EnvironmentInspection.run(input: ProjectInspectionInput(directory: repo.root, environment: [:]), runner: runner)
        #expect(inspection.selection.selected?.framework == .nativeAndroid)
        #expect(inspection.exitCode == 1)
        let result = await WorkflowExecution.run(.up, input: input(repo), runner: runner)
        #expect(result.exitCode == 1)
        #expect(runner.log.all.isEmpty)
    }

    @Test("a missing locked package stays a project failure with Xcode's evidence")
    func lockedPackageFailure() async throws {
        let repo = try project()
        var runner = runner(repo)
        runner.responses[list(repo)] = .failed(74, "pinned revision is absent from the prepared cache")
        let inspection = try await EnvironmentInspection.run(input: ProjectInspectionInput(directory: repo.root, environment: [:]), runner: runner)
        let check = try #require(inspection.report.checks.first { $0.id == "project.native-ios" })
        #expect(check.status == .error)
        #expect(check.outcome.observed?.contains("pinned revision is absent") == true)
        #expect(inspection.exitCode == 1)
        #expect(!runner.log.all.contains { $0.arguments.contains("-resolvePackageDependencies") || $0.arguments.contains("build") })
    }

    @Test("native cancellation during build keeps exit 130 and never reaches install")
    func buildCancellation() async throws {
        let repo = try project()
        var runner = runner(repo)
        let build = "xcodebuild \(target(repo)) -scheme App -configuration Debug -destination generic/platform=iOS Simulator CODE_SIGNING_ALLOWED=NO build"
        runner.failures[build] = CancellationError()
        let result = await WorkflowExecution.run(.build, input: input(repo), runner: runner)
        #expect(result.exitCode == 130)
        #expect(result.operation.state == "cancelled")
        #expect(result.up?.stages.last?.id == "build")
        #expect(!runner.log.all.contains { $0.arguments.contains("install") || $0.arguments.contains("launch") })
    }

    private func project() throws -> FixtureRepo {
        let repo = try FixtureRepo()
        try repo.write("App.xcodeproj/project.pbxproj", "// native fixture")
        try repo.write("App.xcodeproj/xcshareddata/xcschemes/App.xcscheme", "<Scheme/>")
        return repo
    }

    private func input(_ repo: FixtureRepo, scheme: String? = nil, device: String? = nil) -> WorkflowInput {
        WorkflowInput(project: ProjectInspectionInput(directory: repo.root, environment: [:]), device: device, scheme: scheme)
    }

    private func list(_ repo: FixtureRepo) -> String {
        "xcodebuild -list -json \(target(repo))"
    }

    private func target(_ repo: FixtureRepo) -> String {
        "-project \(repo.url("App.xcodeproj").path) -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile"
    }

    private func settings(_ repo: FixtureRepo) -> String {
        "xcodebuild -showBuildSettings -json \(target(repo)) -scheme App -configuration Debug -destination generic/platform=iOS Simulator"
    }

    private func temporaryLeases() -> ResourceLeases {
        ResourceLeases(directory: FileManager.default.temporaryDirectory.appendingPathComponent("runstir-native-leases-\(UUID().uuidString)"))
    }

    private func addUpResponses(_ runner: inout FakeProcessRunner, _ repo: FixtureRepo) {
        let destination = "\(target(repo)) -scheme App -configuration Debug -destination platform=iOS Simulator,id=A CODE_SIGNING_ALLOWED=NO"
        runner.responses["xcrun simctl list devices -j"] = .ok(#"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"name":"iPhone A","udid":"A","state":"Booted","isAvailable":true}]}}"#)
        runner.responses["xcodebuild \(destination) build"] = .ok("** BUILD SUCCEEDED **")
        runner.responses["xcodebuild -showBuildSettings -json \(destination)"] = .ok(#"[{"target":"App","buildSettings":{"CONFIGURATION":"Debug","BUILT_PRODUCTS_DIR":"/test/build","FULL_PRODUCT_NAME":"App.app","PRODUCT_BUNDLE_IDENTIFIER":"com.test.App"}}]"#)
        runner.responses["xcrun simctl install A /test/build/App.app"] = .ok("")
        runner.responses["xcrun simctl terminate A com.test.App"] = .ok("")
        runner.responses["xcrun simctl launch A com.test.App"] = .ok("com.test.App: 3538")
    }

    private func runner(_ repo: FixtureRepo) -> FakeProcessRunner {
        let destination = "\(target(repo)) -scheme App -configuration Debug -destination generic/platform=iOS Simulator CODE_SIGNING_ALLOWED=NO"
        return FakeProcessRunner(responses: [
            "xcode-select -p": .ok("/test/Xcode"),
            "xcodebuild -version": .ok("Xcode 27.0\nBuild version 18A100"),
            "xcodebuild -checkFirstLaunchStatus": .ok(""),
            "xcrun simctl list runtimes -j": .ok(#"{"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-0","name":"iOS 27.0","version":"27.0","isAvailable":true}]}"#),
            list(repo): .ok(#"{"project":{"schemes":["App"],"configurations":["Debug","Release"]}}"#),
            settings(repo): .ok(#"[{"target":"App","buildSettings":{"CONFIGURATION":"Debug","PLATFORM_NAME":"iphonesimulator","IPHONEOS_DEPLOYMENT_TARGET":"17.0","FULL_PRODUCT_NAME":"App.app"}}]"#),
            "xcodebuild \(destination) build": .ok("** BUILD SUCCEEDED **"),
            "xcodebuild -showBuildSettings -json \(destination)": .ok(#"[{"target":"App","buildSettings":{"CONFIGURATION":"Debug","BUILT_PRODUCTS_DIR":"/test/build","FULL_PRODUCT_NAME":"App.app","PRODUCT_BUNDLE_IDENTIFIER":"com.test.App"}}]"#),
        ])
    }
}

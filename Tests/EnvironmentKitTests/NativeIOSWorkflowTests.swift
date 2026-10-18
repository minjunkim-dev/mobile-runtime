import Core
import EnvironmentKit
import Foundation
import TestSupport
import Testing

@Suite("shared native iOS workflows")
struct NativeIOSWorkflowTests {
    @Test("native preparation preserves its selected container and only observes its declared Ruby tools", arguments: [false, true])
    func nativePreparation(multiple: Bool) async throws {
        let repo = try project()
        if multiple { try repo.write("Other.xcodeproj/project.pbxproj", "other app") }
        try repo.write("Gemfile", "source 'https://rubygems.org'\ngem 'cocoapods'\n")
        try repo.write("Gemfile.lock", "fixture")
        try repo.write("Podfile", "platform :ios, '17.0'")
        var runner = try runner(repo)
        runner.responses["xcrun simctl list runtimes -j"] = .ok(#"{"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-0","name":"iOS 27.0","version":"27.0","buildversion":"24A434","supportedArchitectures":["arm64"],"isAvailable":true}]}"#)
        runner.responses["xcrun simctl --set \(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Developer/CoreSimulator/Devices").path) list devices -j"] = .ok(#"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"udid":"B38C3447-963B-42CB-959F-F5234F5A1092","name":"iPhone 17","deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-17","isAvailable":true,"state":"Shutdown"}]}}"#)
        runner.responses["xcrun simctl list devicetypes -j"] = .ok(#"{"devicetypes":[{"identifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-17","name":"iPhone 17","productFamily":"iPhone","minRuntimeVersionString":"26.0.0","maxRuntimeVersionString":"65535.255.255"}]}"#)
        let result = await PreparationExecution.run(input: ProjectInspectionInput(
            directory: repo.root, environment: [:], app: "App.xcodeproj"), planOnly: true, runner: runner)
        #expect(result.exitCode == 0)
        #expect(result.plan?.app == "App.xcodeproj")
        #expect(result.plan?.projectKind == "native-ios")
        #expect(result.plan?.platforms.map(\.platform) == [.ios])
        #expect(result.plan?.steps.contains { $0.id.hasPrefix("dependencies.") } == false)
        #expect(result.plan?.steps.first { $0.id == "ios.project.native-ios" }?.observed?.contains("CocoaPods") == true)
        let approved = await PreparationExecution.run(input: ProjectInspectionInput(
            directory: repo.root, environment: [:], app: "App.xcodeproj"),
            approvedPlanID: try #require(result.plan?.id), trustRepository: true,
            runner: runner, leases: temporaryLeases())
        #expect(approved.exitCode == 1)
        #expect(approved.operation.state == "waiting-manual")
        #expect(!runner.log.all.contains { ["node", "npm", "yarn", "pnpm", "pod", "bundle"].contains($0.executable)
            || $0.executable == "ruby" && $0.arguments != ["--version"]
            || ($0.executable == "/usr/bin/which" && $0.arguments.contains("node")) })
        #expect(!runner.log.all.contains { $0.executable == "curl" || $0.arguments.contains("install") })
        #expect(!FileManager.default.fileExists(atPath: repo.url("node_modules").path))
    }

    @Test("invalid Flutter or incomplete native preparation stays manual without executing tools", arguments: [
        ProjectFramework.flutter, .nativeAndroid
    ])
    func futurePreparation(framework: ProjectFramework) async throws {
        let repo = try FixtureRepo()
        if framework == .flutter {
            try repo.write("pubspec.yaml", "dependencies:\n  flutter:\n    sdk: flutter\n")
            try repo.directory("ios")
            try repo.directory("android")
        } else {
            try repo.write("settings.gradle", "rootProject.name = 'native'")
            try repo.write("gradlew", "#!/bin/sh")
        }
        let input = ProjectInspectionInput(directory: repo.root, environment: [:])
        let runner = FakeProcessRunner()
        let result = await PreparationExecution.run(input: input, planOnly: true, runner: runner)
        #expect(result.exitCode == 0)
        #expect(result.plan?.projectKind == framework.rawValue)
        #expect(result.plan?.platforms.map(\.platform) == (framework == .flutter ? [.ios, .android] : [.android]))
        if framework == .flutter {
            #expect(result.plan?.steps.contains { $0.id == "flutter.declarations" && $0.kind == "migration" } == true)
        } else {
            #expect(result.plan?.steps.contains { $0.kind == "provider" } == true)
        }
        let approved = await PreparationExecution.run(input: input,
            approvedPlanID: try #require(result.plan?.id), trustRepository: true, runner: runner)
        #expect(approved.exitCode == 1)
        #expect(approved.operation.state == "waiting-manual")
        #expect(runner.log.all.isEmpty)
    }

    @Test("native build uses the selected root container without JavaScript or installation")
    func nativeBuild() async throws {
        let repo = try project()
        let original = try Data(contentsOf: repo.url("App.xcodeproj/project.pbxproj"))
        let runner = try runner(repo)
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

    @Test("a native build remediation preserves literal shell arguments", arguments: [
        "App${INJECTED}.xcodeproj", "App$(printf\tinjected).xcodeproj", "O'Reilly Native.xcodeproj"
    ])
    func literalRemediation(container: String) async throws {
        let repo = try project()
        let originalPath = repo.url("App.xcodeproj").path
        let containerPath = repo.url(container).path
        try FileManager.default.moveItem(atPath: originalPath, toPath: containerPath)
        let responses = try runner(repo).responses.map { key, value in
            (key.replacingOccurrences(of: originalPath, with: containerPath), value)
        }
        var runner = FakeProcessRunner(responses: Dictionary(uniqueKeysWithValues: responses))
        let build = "xcodebuild -project \(containerPath) -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile -scheme App -configuration Debug -destination generic/platform=iOS Simulator -derivedDataPath \(try RunLogs(project: repo.root).derivedDataDirectory.path) CODE_SIGNING_ALLOWED=NO build"
        runner.responses[build] = .failed(65, "error: fixture build failed")
        let result = await WorkflowExecution.run(.build, input: input(repo), runner: runner)
        #expect(result.exitCode == 1)
        guard case .domain(let failure) = result.up?.failure else {
            Issue.record("Expected the build failure and its remediation")
            return
        }
        let command = try #require(failure.remediation.command)
        let expected = try #require(runner.log.all.first { $0.arguments.last == "build" })
        let output = repo.url("shell-arguments")
        try repo.write("bin/xcodebuild", "#!/bin/sh\nprintf '%s\\0' \"$@\" > \"$ARGV_OUTPUT\"\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: repo.url("bin/xcodebuild").path)
        let shell = SystemProcessRunner(environment: ["PATH": repo.url("bin").path + ":/bin",
            "ARGV_OUTPUT": output.path, "INJECTED": "expanded"], workingDirectory: repo.root)
        let parsed = try await shell.run(ProcessCommand("/bin/sh", ["-c", command], timeout: .seconds(5)))
        #expect(parsed.terminationStatus.isSuccess)
        guard parsed.terminationStatus.isSuccess else { return }
        let actual = try String(contentsOf: output, encoding: .utf8).split(separator: "\0", omittingEmptySubsequences: false)
            .dropLast().map(String.init)
        #expect(actual == expected.arguments)
    }

    @Test("a private scheme is rejected before build")
    func privateScheme() async throws {
        let repo = try project()
        var runner = try runner(repo)
        runner.responses[list(repo)] = .ok(#"{"project":{"schemes":["App","Private"],"configurations":["Debug","Release"]}}"#)
        let result = await WorkflowExecution.run(.build, input: input(repo, scheme: "Private"), runner: runner)
        #expect(result.exitCode == 1)
        #expect(!runner.log.all.contains { $0.executable == "xcodebuild" && $0.arguments.contains("build") })
        #expect(!runner.log.all.contains { $0.executable == "xcrun" && $0.arguments.contains("install") })
    }

    @Test("native Xcode declarations remain authoritative over mobile.yml overrides", arguments: [false, true])
    func nativeXcodeDeclaration(overrideIsNewer: Bool) async throws {
        let repo = try project()
        let declared = overrideIsNewer ? "27.0" : "27.1"
        let override = overrideIsNewer ? "27.1" : "27.0"
        try repo.write(".xcode-version", declared)
        try repo.write("mobile.yml", "overrides:\n  xcode: '\(override)'\n")
        let runner = try runner(repo)
        let inspection = try await EnvironmentInspection.run(input: ProjectInspectionInput(
            directory: repo.root, environment: [:]), runner: runner)
        let check = try #require(inspection.report.checks.first { $0.id == "xcode.version" })
        #expect(check.status == (overrideIsNewer ? .pass : .error))
        #expect(check.outcome.source.origin.contains(".xcode-version \(declared)"))
        #expect(check.outcome.source.origin.contains("mobile.yml overrides.xcode \(override) cannot override"))
        let result = await WorkflowExecution.run(.build, input: input(repo), runner: runner)
        #expect(result.exitCode == (overrideIsNewer ? 0 : 1), Comment(rawValue: result.up?.failure?.message ?? ""))
        #expect(runner.log.all.contains { $0.arguments.contains("build") } == overrideIsNewer)
    }

    @Test("an explicit native configuration uses its own deployment target", arguments: [false, true])
    func explicitConfiguration(requiresNewerRuntime: Bool) async throws {
        let repo = try project()
        var runner = try runner(repo)
        let debugTarget = requiresNewerRuntime ? "17.0" : "27.0"
        let releaseTarget = requiresNewerRuntime ? "27.0" : "17.0"
        runner.responses[try settings(repo)] = .ok(#"[{"target":"App","buildSettings":{"CONFIGURATION":"Debug","PLATFORM_NAME":"iphonesimulator","IPHONEOS_DEPLOYMENT_TARGET":"\#(debugTarget)","FULL_PRODUCT_NAME":"App.app"}}]"#)
        runner.responses["xcrun simctl list runtimes -j"] = .ok(#"{"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-0","name":"iOS 18.0","version":"18.0","isAvailable":true}]}"#)
        let destination = "\(target(repo)) -scheme App -configuration Release -destination generic/platform=iOS Simulator -derivedDataPath \(try RunLogs(project: repo.root).derivedDataDirectory.path)"
        let measured = #"[{"target":"App","buildSettings":{"CONFIGURATION":"Release","PLATFORM_NAME":"iphonesimulator","IPHONEOS_DEPLOYMENT_TARGET":"\#(releaseTarget)","FULL_PRODUCT_NAME":"App.app","BUILT_PRODUCTS_DIR":"/test/build","PRODUCT_BUNDLE_IDENTIFIER":"com.test.App"}}]"#
        runner.responses["xcodebuild -showBuildSettings -json \(destination)"] = .ok(measured)
        runner.responses["xcodebuild \(destination) CODE_SIGNING_ALLOWED=NO build"] = .ok("** BUILD SUCCEEDED **")
        runner.responses["xcodebuild -showBuildSettings -json \(destination) CODE_SIGNING_ALLOWED=NO"] = .ok(measured)
        let result = await WorkflowExecution.run(.build, input: WorkflowInput(
            project: ProjectInspectionInput(directory: repo.root, environment: [:]), configuration: "Release"), runner: runner)
        #expect(result.exitCode == (requiresNewerRuntime ? 1 : 0), Comment(rawValue: result.up?.failure?.message ?? ""))
        #expect(runner.log.all.contains { $0.arguments.contains("build") } == !requiresNewerRuntime)
        if !requiresNewerRuntime { #expect(result.operation.configuration == "Release") }
        let unrequested = try settings(repo)
        #expect(!runner.log.all.contains { $0.description == unrequested })
    }

    @Test("native cancellation remains correlated and never starts detached work")
    func cancellation() async throws {
        let repo = try project()
        let runner = try runner(repo)
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
        var runner = try runner(repo)
        try addUpResponses(&runner, repo)
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

    @Test("native up follows the scheme's runnable app instead of a same-named build target")
    func runnableApp() async throws {
        let repo = try project()
        try repo.write("App.xcodeproj/xcshareddata/xcschemes/App.xcscheme", """
            <Scheme><LaunchAction><BuildableProductRunnable>
            <BuildableReference BlueprintIdentifier="CHOSEN" BuildableName="Chosen.app"
                BlueprintName="Chosen" ReferencedContainer="container:App.xcodeproj"/>
            </BuildableProductRunnable></LaunchAction></Scheme>
            """)
        var runner = try runner(repo)
        try addUpResponses(&runner, repo)
        let measured = #"[{"target":"App","buildSettings":{"CONFIGURATION":"Debug","PLATFORM_NAME":"iphonesimulator","IPHONEOS_DEPLOYMENT_TARGET":"17.0","BUILT_PRODUCTS_DIR":"/test/build","FULL_PRODUCT_NAME":"App.app","PRODUCT_BUNDLE_IDENTIFIER":"com.test.App"}},{"target":"Chosen","buildSettings":{"CONFIGURATION":"Debug","PLATFORM_NAME":"iphonesimulator","IPHONEOS_DEPLOYMENT_TARGET":"17.0","BUILT_PRODUCTS_DIR":"/test/build","FULL_PRODUCT_NAME":"Chosen.app","PRODUCT_BUNDLE_IDENTIFIER":"com.test.Chosen"}}]"#
        runner.responses[try settings(repo)] = .ok(measured)
        let destination = "\(target(repo)) -scheme App -configuration Debug -destination platform=iOS Simulator,id=A -derivedDataPath \(try RunLogs(project: repo.root).derivedDataDirectory.path) CODE_SIGNING_ALLOWED=NO"
        runner.responses["xcodebuild -showBuildSettings -json \(destination)"] = .ok(measured)
        runner.responses["xcrun simctl install A /test/build/Chosen.app"] = .ok("")
        runner.responses["xcrun simctl terminate A com.test.Chosen"] = .ok("")
        runner.responses["xcrun simctl launch A com.test.Chosen"] = .ok("com.test.Chosen: 3538")
        let result = await WorkflowExecution.run(.up, input: input(repo, device: "A"), runner: runner, leases: temporaryLeases())
        #expect(result.exitCode == 0, Comment(rawValue: result.up?.failure?.message ?? ""))
        #expect(result.up?.context.product?.bundleIdentifier == "com.test.Chosen")
        #expect(runner.log.all.contains { $0.description == "xcrun simctl install A /test/build/Chosen.app" })
        #expect(!runner.log.all.contains { $0.executable == "xcrun" && $0.arguments.contains("com.test.App") })
    }

    @Test("a missing, malformed or ambiguous native runnable never starts changes", arguments: [
        "<Scheme><BuildAction><BuildableReference BlueprintName=\"App\" BuildableName=\"App.app\"/></BuildAction></Scheme>",
        "<Scheme><LaunchAction><BuildableProductRunnable><BuildableReference BlueprintName=\"App\" BuildableName=\"App.app\"/><BuildableReference BlueprintName=\"Other\" BuildableName=\"Other.app\"/></BuildableProductRunnable></LaunchAction></Scheme>",
        "<Scheme><LaunchAction><BuildableProductRunnable>",
        "<Scheme><LaunchAction><BuildableProductRunnable><BuildableReference BlueprintName=\"Missing\" BuildableName=\"Missing.app\"/></BuildableProductRunnable></LaunchAction></Scheme>"
    ])
    func unresolvedRunnable(scheme: String) async throws {
        let repo = try project()
        try repo.write("App.xcodeproj/xcshareddata/xcschemes/App.xcscheme", scheme)
        let runner = try runner(repo)
        let result = await WorkflowExecution.run(.build, input: input(repo), runner: runner)
        #expect(result.exitCode == 1)
        #expect(!runner.log.all.contains { $0.arguments.contains("build") || $0.arguments.contains("install") })
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
        var runner = try runner(repo)
        runner.responses["xcrun simctl terminate A com.test.App"] = .ok("")
        let result = await WorkflowExecution.run(.down, input: input(repo), runner: runner, leases: leases)
        #expect(result.exitCode == 0)
        #expect(result.down?.items.map(\.id) == ["app"])
        #expect(runner.log.all.filter { $0.executable == "xcrun" }.map(\.description) == ["xcrun simctl terminate A com.test.App"])
        #expect(!runner.log.all.contains { $0.executable == "kill" || $0.executable == "curl" })
        #expect(try InstallRecord.read(from: logs)?.bundleId == "com.test.App")
    }

    @Test("a native device lease conflict stops before build or installation")
    func nativeConflict() async throws {
        let repo = try project()
        var runner = try runner(repo)
        try addUpResponses(&runner, repo)
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
        var runner = try runner(repo)
        runner.responses[try settings(repo)] = fallback
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
        let runner = try runner(repo)
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
        var runner = try runner(repo)
        try addUpResponses(&runner, repo)
        runner.responses[try settings(repo)] = .ok(#"[{"target":"App","buildSettings":{"CONFIGURATION":"Debug","PLATFORM_NAME":"iphonesimulator","IPHONEOS_DEPLOYMENT_TARGET":"27.0","FULL_PRODUCT_NAME":"App.app"}}]"#)
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
        try repo.write("Apps/Nested.xcodeproj/xcshareddata/xcschemes/App.xcscheme", appScheme)
        let target = "-workspace \(repo.url("Chosen.xcworkspace").path) -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile"
        let destination = "\(target) -scheme App -configuration Debug -destination generic/platform=iOS Simulator -derivedDataPath \(try RunLogs(project: repo.root).derivedDataDirectory.path)"
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

    @Test("Flutter candidates remain classified without entering React Native workflows")
    func futureFramework() async throws {
        let repo = try FixtureRepo()
        try repo.write("pubspec.yaml", "name: fixture\ndependencies:\n  flutter:\n    sdk: flutter\n")
        try repo.directory("android")
        let runner = FakeProcessRunner()
        let inspection = try await EnvironmentInspection.run(input: ProjectInspectionInput(directory: repo.root, environment: [:]), runner: runner)
        #expect(inspection.selection.selected?.framework == .flutter)
        #expect(inspection.exitCode == 1)
        let result = await WorkflowExecution.run(.up, input: input(repo), runner: runner)
        #expect(result.exitCode == 1)
        #expect(runner.log.all.isEmpty)
    }

    @Test("a missing locked package stays a project failure with Xcode's evidence")
    func lockedPackageFailure() async throws {
        let repo = try project()
        var runner = try runner(repo)
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
        var runner = try runner(repo)
        let build = "xcodebuild \(target(repo)) -scheme App -configuration Debug -destination generic/platform=iOS Simulator -derivedDataPath \(try RunLogs(project: repo.root).derivedDataDirectory.path) CODE_SIGNING_ALLOWED=NO build"
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
        try repo.write("App.xcodeproj/xcshareddata/xcschemes/App.xcscheme", appScheme)
        return repo
    }

    private var appScheme: String {
        """
        <Scheme><LaunchAction><BuildableProductRunnable>
        <BuildableReference BlueprintIdentifier="APP" BuildableName="App.app" BlueprintName="App"/>
        </BuildableProductRunnable></LaunchAction></Scheme>
        """
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

    private func settings(_ repo: FixtureRepo) throws -> String {
        "xcodebuild -showBuildSettings -json \(target(repo)) -scheme App -configuration Debug -destination generic/platform=iOS Simulator -derivedDataPath \(try RunLogs(project: repo.root).derivedDataDirectory.path)"
    }

    private func temporaryLeases() -> ResourceLeases {
        ResourceLeases(directory: FileManager.default.temporaryDirectory.appendingPathComponent("runstir-native-leases-\(UUID().uuidString)"))
    }

    private func addUpResponses(_ runner: inout FakeProcessRunner, _ repo: FixtureRepo) throws {
        let destination = "\(target(repo)) -scheme App -configuration Debug -destination platform=iOS Simulator,id=A -derivedDataPath \(try RunLogs(project: repo.root).derivedDataDirectory.path) CODE_SIGNING_ALLOWED=NO"
        runner.responses["xcrun simctl list devices -j"] = .ok(#"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"name":"iPhone A","udid":"A","state":"Booted","isAvailable":true}]}}"#)
        runner.responses["xcodebuild \(destination) build"] = .ok("** BUILD SUCCEEDED **")
        runner.responses["xcodebuild -showBuildSettings -json \(destination)"] = .ok(#"[{"target":"App","buildSettings":{"CONFIGURATION":"Debug","BUILT_PRODUCTS_DIR":"/test/build","FULL_PRODUCT_NAME":"App.app","PRODUCT_BUNDLE_IDENTIFIER":"com.test.App"}}]"#)
        runner.responses["xcrun simctl install A /test/build/App.app"] = .ok("")
        runner.responses["xcrun simctl terminate A com.test.App"] = .ok("")
        runner.responses["xcrun simctl launch A com.test.App"] = .ok("com.test.App: 3538")
    }

    private func runner(_ repo: FixtureRepo) throws -> FakeProcessRunner {
        let destination = "\(target(repo)) -scheme App -configuration Debug -destination generic/platform=iOS Simulator -derivedDataPath \(try RunLogs(project: repo.root).derivedDataDirectory.path) CODE_SIGNING_ALLOWED=NO"
        return FakeProcessRunner(responses: [
            "xcode-select -p": .ok("/test/Xcode"),
            "xcodebuild -version": .ok("Xcode 27.0\nBuild version 18A100"),
            "xcodebuild -checkFirstLaunchStatus": .ok(""),
            "xcrun simctl list runtimes -j": .ok(#"{"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-0","name":"iOS 27.0","version":"27.0","isAvailable":true}]}"#),
            list(repo): .ok(#"{"project":{"schemes":["App"],"configurations":["Debug","Release"]}}"#),
            try settings(repo): .ok(#"[{"target":"App","buildSettings":{"CONFIGURATION":"Debug","PLATFORM_NAME":"iphonesimulator","IPHONEOS_DEPLOYMENT_TARGET":"17.0","FULL_PRODUCT_NAME":"App.app"}}]"#),
            "xcodebuild \(destination) build": .ok("** BUILD SUCCEEDED **"),
            "xcodebuild -showBuildSettings -json \(destination)": .ok(#"[{"target":"App","buildSettings":{"CONFIGURATION":"Debug","BUILT_PRODUCTS_DIR":"/test/build","FULL_PRODUCT_NAME":"App.app","PRODUCT_BUNDLE_IDENTIFIER":"com.test.App"}}]"#),
        ])
    }
}

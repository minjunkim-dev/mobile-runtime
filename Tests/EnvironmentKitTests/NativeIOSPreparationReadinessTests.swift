import Core
import EnvironmentKit
import Foundation
import TestSupport
import Testing

@Suite("native iOS preparation readiness")
struct NativeIOSPreparationReadinessTests {
    @Test("an exact reused native runtime completes setup while doctor grades the measured scheme")
    func exactRuntimeReadiness() async throws {
        let fixture = try Fixture()
        let runner = try fixture.runner()
        let doctor = try await EnvironmentInspection.run(input: fixture.input, runner: runner)
        let runtime = try #require(doctor.report.checks.first { $0.id == "simulator.runtime" })
        #expect(runtime.status == .pass)
        #expect(runtime.outcome.required == "an iOS 17.0 or newer simulator runtime, available")
        #expect(runtime.outcome.source.origin.contains("IPHONEOS_DEPLOYMENT_TARGET"))
        #expect(doctor.report.checks.first { $0.id == "project.native-ios" }?.status == .pass)
        #expect(doctor.report.status == .pass, Comment(rawValue: doctor.report.checks.filter { $0.status != .pass }.map(\.id).description))
        // project.native-ios and simulator.runtime share one scheme measurement.
        #expect(runner.log.all.filter { $0.arguments.contains("-showBuildSettings") }.count == 1)
        let planned = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: runner)
        let plan = try #require(planned.plan)
        #expect(plan.resources?.contains { $0.kind == .runtime && $0.runtimeBuild == "24A434"
            && $0.architecture == "arm64" && $0.origin == .reused } == true)
        #expect(plan.resources?.contains { $0.kind == .simulator && $0.identifier == fixture.deviceID
            && $0.state == "Shutdown" && $0.origin == .reused } == true)
        #expect(!plan.steps.contains { $0.id == "ios.simulator.runtime" })
        #expect(plan.steps.isEmpty)

        let approved = await PreparationExecution.run(input: fixture.input, approvedPlanID: plan.id,
            runner: runner, leases: fixture.leases)
        #expect(approved.exitCode == 0, Comment(rawValue: approved.operation.error ?? ""))
        #expect(approved.operation.state == "succeeded")
        #expect(approved.operation.manual.isEmpty && approved.operation.remaining.isEmpty)
        #expect(approved.plan?.platforms.first { $0.platform == .ios }?.state == "succeeded")
        let rechecked = try await EnvironmentInspection.run(input: fixture.input, runner: runner)
        #expect(rechecked.report.checks.first { $0.id == "simulator.runtime" }?.status == .pass)
        fixture.assertNoMutations(runner)
    }

    @Test("an unselected native scheme leaves simulator.runtime unknown with the selection to make")
    func unmeasuredRuntime() async throws {
        let fixture = try Fixture(config: nil, schemes: ["App", "Other"])
        let runner = try fixture.runner()
        let doctor = try await EnvironmentInspection.run(input: fixture.input, runner: runner)
        let runtime = try #require(doctor.report.checks.first { $0.id == "simulator.runtime" })
        #expect(runtime.status == .unknown)
        #expect(runtime.outcome.reason?.contains("Choose a shared app scheme") == true)
        #expect(!runner.log.all.contains { $0.arguments.contains("-showBuildSettings") })
        fixture.assertNoMutations(runner)
    }

    @Test("a mobile.yml iOS runtime override still outranks the measured scheme")
    func declaredRuntimeWins() async throws {
        let fixture = try Fixture(config: "ios:\n  scheme: App\noverrides:\n  iosRuntime: '26.0'\n")
        let runner = try fixture.runner()
        let doctor = try await EnvironmentInspection.run(input: fixture.input, runner: runner)
        let runtime = try #require(doctor.report.checks.first { $0.id == "simulator.runtime" })
        #expect(runtime.status == .pass)
        #expect(runtime.outcome.required == "an iOS 26.0 or newer simulator runtime, available")
        #expect(runtime.outcome.source == CheckSource(tier: 3, origin: "mobile.yml overrides.iosRuntime"))
        fixture.assertNoMutations(runner)
    }

    @Test("an incomplete native runtime observation retains manual setup blockers", arguments: [
        "missingBuild", "missingArchitecture", "missingDeploymentTarget"
    ])
    func incompleteRuntimeReadiness(missing: String) async throws {
        let fixture = try Fixture()
        let runner = try fixture.runner(missing: missing)
        if missing == "missingDeploymentTarget" {
            // A scheme Xcode cannot measure is project.native-ios's error; the runtime stays unknown (ADR-0004).
            let doctor = try await EnvironmentInspection.run(input: fixture.input, runner: runner)
            let runtime = try #require(doctor.report.checks.first { $0.id == "simulator.runtime" })
            #expect(runtime.status == .unknown)
            #expect(runtime.outcome.reason?.contains("project.native-ios") == true)
            #expect(doctor.report.checks.first { $0.id == "project.native-ios" }?.status == .error)
        }
        let planned = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: runner)
        let plan = try #require(planned.plan)
        #expect(plan.resources?.contains { $0.kind == .runtime && $0.origin == .reused } != true)
        // The measured scheme grades simulator.runtime; only a failed measurement leaves it manual.
        #expect(plan.steps.contains { $0.id == "ios.simulator.runtime" && $0.kind == "provider" }
            == (missing == "missingDeploymentTarget"))
        #expect(plan.steps.contains { $0.id == "ios.resources" && $0.kind == "provider" })
        #expect(plan.steps.count == (missing == "missingDeploymentTarget" ? 3 : 1))
        #expect(!plan.steps.contains { $0.kind == "install" || $0.kind == "align" })
        let approved = await PreparationExecution.run(input: fixture.input, approvedPlanID: plan.id,
            runner: runner, leases: fixture.leases)
        #expect(approved.exitCode == 1)
        #expect(approved.operation.state == "waiting-manual")
        fixture.assertNoMutations(runner)
    }

    private struct Fixture {
        let repo: FixtureRepo
        let home: FixtureRepo
        let deviceID = "B38C3447-963B-42CB-959F-F5234F5A1092"
        var deviceSet: URL { home.url("Library/Developer/CoreSimulator/Devices") }
        var leases: ResourceLeases { ResourceLeases(directory: home.url("leases")) }
        var input: ProjectInspectionInput {
            ProjectInspectionInput(directory: repo.root, environment: ["HOME": home.root.path], app: "App.xcodeproj")
        }

        let schemes: [String]

        init(config: String? = "ios:\n  scheme: App\n", schemes: [String] = ["App"]) throws {
            repo = try FixtureRepo()
            home = try FixtureRepo()
            self.schemes = schemes
            try repo.write("App.xcodeproj/project.pbxproj", "// native Swift app fixture")
            for scheme in schemes {
                try repo.write("App.xcodeproj/xcshareddata/xcschemes/\(scheme).xcscheme", """
                    <Scheme><LaunchAction><BuildableProductRunnable>
                    <BuildableReference BlueprintIdentifier="\(scheme.uppercased())" BuildableName="\(scheme).app" BlueprintName="\(scheme)"/>
                    </BuildableProductRunnable></LaunchAction></Scheme>
                    """)
            }
            if let config { try repo.write("mobile.yml", config) }
        }

        func runner(missing: String? = nil) throws -> FakeProcessRunner {
            let container = "-project \(repo.url("App.xcodeproj").path) -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile"
            let build = missing == "missingBuild" ? "" : ",\"buildversion\":\"24A434\""
            let architecture = missing == "missingArchitecture" ? "" : ",\"supportedArchitectures\":[\"arm64\"]"
            let deployment = missing == "missingDeploymentTarget" ? "" : ",\"IPHONEOS_DEPLOYMENT_TARGET\":\"17.0\""
            let runtime = #"{"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-0","name":"iOS 27.0","version":"27.0","isAvailable":true\#(build)\#(architecture)}]}"#
            let devices = #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"udid":"\#(deviceID)","name":"iPhone 17","deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-17","isAvailable":true,"state":"Shutdown"}]}}"#
            return FakeProcessRunner(responses: [
                "xcode-select -p": .ok("/test/Xcode"),
                "xcodebuild -version": .ok("Xcode 27.0\nBuild version 18A100"),
                "xcodebuild -checkFirstLaunchStatus": .ok(""),
                "xcodebuild -list -json \(container)": .ok(#"{"project":{"schemes":[\#(schemes.map { "\"\($0)\"" }.joined(separator: ","))],"configurations":["Debug","Release"]}}"#),
                "xcodebuild -showBuildSettings -json \(container) -scheme App -configuration Debug -destination generic/platform=iOS Simulator -derivedDataPath \(try RunLogs(project: repo.root).derivedDataDirectory.path)": .ok(#"[{"target":"App","buildSettings":{"CONFIGURATION":"Debug","PLATFORM_NAME":"iphonesimulator","FULL_PRODUCT_NAME":"App.app"\#(deployment)}}]"#),
                "xcrun simctl list runtimes -j": .ok(runtime),
                "xcrun simctl list devices -j": .ok(devices),
                "xcrun simctl --set \(deviceSet.path) list devices -j": .ok(devices),
                "xcrun simctl list devicetypes -j": .ok(#"{"devicetypes":[{"identifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-17","name":"iPhone 17","productFamily":"iPhone","minRuntimeVersionString":"26.0.0","maxRuntimeVersionString":"65535.255.255"}]}"#),
            ])
        }

        func assertNoMutations(_ runner: FakeProcessRunner) {
            #expect(!runner.log.all.contains { $0.arguments.contains("-downloadPlatform")
                || $0.arguments.contains("-importPlatform")
                || ["create", "boot", "shutdown", "delete", "erase", "build", "install", "launch"].contains(where: $0.arguments.contains) })
            #expect(!runner.log.all.contains { ["node", "npm", "yarn", "pnpm", "ruby", "pod", "bundle"].contains($0.executable) })
            #expect(runner.log.spawned.isEmpty)
        }
    }
}

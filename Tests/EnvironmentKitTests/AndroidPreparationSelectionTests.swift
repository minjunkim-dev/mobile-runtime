import Core
import EnvironmentKit
import Foundation
import TestSupport
import Testing
@testable import AndroidKit

@Suite("Android module and variant selection in preparation")
struct AndroidPreparationSelectionTests {
    @Test("an explicit selection resolves the target that multiple application modules leave manual")
    func explicitSelection() async throws {
        let fixture = try await Self.multiModule()
        let runner = fixture.runner()
        let unselected = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: runner)
        #expect(unselected.plan?.steps.contains { $0.id == "android.android.target" } == true)
        let selected = await PreparationExecution.run(input: fixture.input, planOnly: true,
            module: ":app", variant: "demoDebug", runner: runner)
        let diagnostic = try selected.encoded(toolVersion: "fixture")
        #expect(selected.exitCode == 0, Comment(rawValue: diagnostic))
        #expect(selected.plan?.steps.contains { $0.id == "android.android.target" } == false, Comment(rawValue: diagnostic))
        #expect(Self.targetOrigin(selected.plan) == "evaluated Gradle model; explicit android.module=:app; explicit android.variant=demoDebug")
        // The base fixture's own manual items (JDK, unpublished archives) remain; the selection adds none.
        let single = try await SDKFixture()
        let baseline = await PreparationExecution.run(input: single.input, planOnly: true, runner: single.runner())
        #expect(selected.operation.manual.map(\.id) == baseline.operation.manual.map(\.id), Comment(rawValue: diagnostic))
        #expect(unselected.operation.manual.map(\.id) != baseline.operation.manual.map(\.id))
    }

    @Test("the effective selection is plan identity: mobile.yml and an equal explicit choice share one plan-id")
    func planIdentity() async throws {
        let fixture = try await Self.multiModule()
        try fixture.repo.write("project/mobile.yml", "android:\n  module: \":app\"\n  variant: demoDebug\n")
        let runner = fixture.runner()
        let declared = try #require(await PreparationExecution.run(input: fixture.input, planOnly: true, runner: runner).plan)
        let same = try #require(await PreparationExecution.run(input: fixture.input, planOnly: true,
            module: ":app", variant: "demoDebug", runner: runner).plan)
        let other = try #require(await PreparationExecution.run(input: fixture.input, planOnly: true,
            module: ":app", variant: "prodDebug", runner: runner).plan)
        #expect(declared.id == same.id)
        #expect(declared.id != other.id)
        #expect(Self.targetOrigin(declared) == "evaluated Gradle model; mobile.yml android.module=:app; mobile.yml android.variant=demoDebug")
        #expect(Self.targetOrigin(same) == Self.targetOrigin(declared))
        #expect(Self.targetOrigin(other) == "evaluated Gradle model; mobile.yml android.module=:app; explicit android.variant=prodDebug")
    }

    @Test("a module written without its leading colon is the same plan identity")
    func moduleSpellingIdentity() async throws {
        let fixture = try await Self.multiModule()
        try fixture.repo.write("project/mobile.yml", "android:\n  module: app\n  variant: demoDebug\n")
        let runner = fixture.runner()
        let declared = try #require(await PreparationExecution.run(input: fixture.input, planOnly: true, runner: runner).plan)
        let explicit = try #require(await PreparationExecution.run(input: fixture.input, planOnly: true,
            module: ":app", variant: "demoDebug", runner: runner).plan)
        #expect(declared.androidModule == ":app")
        #expect(declared.id == explicit.id)
        // The config check reports the file, not the explicit selection layered over it.
        let syntax = explicit.platforms.flatMap(\.checks).first { $0.id == "android.config.syntax" }
        #expect(syntax?.observed == "mobile.yml declares android.module: app, android.variant: demoDebug")
    }

    @Test("a plan-id approved under another selection is rejected before any change")
    func staleSelectionApproval() async throws {
        let fixture = try await Self.multiModule()
        let runner = fixture.runner()
        let plan = try #require(await PreparationExecution.run(input: fixture.input, planOnly: true,
            module: ":app", variant: "demoDebug", runner: runner).plan)
        let result = await PreparationExecution.run(input: fixture.input, approvedPlanID: plan.id,
            module: ":app", variant: "prodDebug", runner: runner)
        #expect(result.operation.state == "needs-approval")
        #expect(result.operation.error == "Plan conditions changed. No preparation changes started.")
        #expect(result.operation.completed.isEmpty)
        #expect(runner.downloads.isEmpty)
    }

    @Test("an unknown module fails with the workflow target error before any change")
    func unknownModule() async throws {
        let fixture = try await Self.multiModule()
        let runner = fixture.runner()
        let plan = try #require(await PreparationExecution.run(input: fixture.input, planOnly: true,
            module: ":app", variant: "demoDebug", runner: runner).plan)
        let result = await PreparationExecution.run(input: fixture.input, approvedPlanID: plan.id,
            module: ":missing", variant: "demoDebug", runner: runner)
        #expect(result.exitCode != 0)
        #expect(result.operation.state == "failed")
        #expect(result.operation.error?.hasPrefix("android.module names :missing, available application modules: :app, :app-nia-catalog") == true)
        #expect(result.operation.completed.isEmpty)
        #expect(runner.downloads.isEmpty)
    }

    @Test("an unknown variant of an existing module fails before any change")
    func unknownVariant() async throws {
        let fixture = try await Self.multiModule()
        let runner = fixture.runner()
        let plan = try #require(await PreparationExecution.run(input: fixture.input, planOnly: true,
            module: ":app", variant: "demoDebug", runner: runner).plan)
        let result = await PreparationExecution.run(input: fixture.input, approvedPlanID: plan.id,
            module: ":app", variant: "missingDebug", runner: runner)
        #expect(result.operation.state == "failed")
        #expect(result.operation.error?.hasPrefix("android.variant names missingDebug, runnable debuggable variants: demoDebug, prodDebug") == true)
        #expect(result.operation.completed.isEmpty)
        #expect(runner.downloads.isEmpty)
    }

    @Test("a failed Gradle model probe stays a plan item rather than a selection failure")
    func modelFailureKeepsPlan() async throws {
        let fixture = try await Self.multiModule()
        fixture.modelJSON = "not a model"
        let result = await PreparationExecution.run(input: fixture.input, planOnly: true,
            module: ":app", variant: "demoDebug", runner: fixture.runner())
        let diagnostic = try result.encoded(toolVersion: "fixture")
        #expect(result.operation.state == "needs-approval", Comment(rawValue: diagnostic))
        #expect(result.plan?.steps.contains { $0.id == "android.android.target" } == true, Comment(rawValue: diagnostic))
    }

    @Test("a selection the final recheck rejects after approved installs is not reported as success")
    func finalRecheckRejection() async throws {
        let fixture = try await Self.multiModule()
        let runner = RejectingAfterInstallRunner(base: fixture.runner(), fixture: fixture)
        let plan = try #require(await PreparationExecution.run(input: fixture.input, planOnly: true,
            module: ":app", variant: "demoDebug", runner: runner).plan)
        let result = await PreparationExecution.run(input: fixture.input, approvedPlanID: plan.id,
            module: ":app", variant: "demoDebug", runner: runner)
        let diagnostic = try result.encoded(toolVersion: "fixture")
        #expect(result.operation.completed.count == 2, Comment(rawValue: diagnostic))
        #expect(result.exitCode == 1)
        #expect(result.operation.state == "partial")
        #expect(result.operation.error?.hasPrefix("android.variant names demoDebug") == true, Comment(rawValue: diagnostic))
    }

    @Test("an iOS-only setup rejects Android selectors like build and up")
    func iosOnlyRejection() async throws {
        let repo = try FixtureRepo()
        try repo.write("App.xcodeproj/project.pbxproj", "// native project fixture")
        let runner = FakeProcessRunner()
        let result = await PreparationExecution.run(input: ProjectInspectionInput(directory: repo.root, environment: [:]),
            planOnly: true, module: ":app", runner: runner)
        #expect(result.exitCode != 0)
        #expect(result.operation.state == "failed")
        #expect(result.operation.error == "--module and --variant apply only to Android.")
        #expect(result.plan == nil)
        #expect(runner.log.all.isEmpty)
    }

    private static func targetOrigin(_ plan: PreparationPlan?) -> String? {
        plan?.platforms.flatMap(\.checks).first { $0.id == "android.android.target" }?.source.origin
    }

    /// Now in Android's shape: two application modules, and flavored debug variants in :app.
    private static func multiModule() async throws -> SDKFixture {
        let fixture = try await SDKFixture()
        func module(_ path: String, _ variants: [String]) -> String {
            let name = path.dropFirst().split(separator: "-").enumerated()
                .map { $0.offset == 0 ? String($0.element) : $0.element.capitalized }.joined()
            let entries = variants.map { variant in
                let task = variant.prefix(1).uppercased() + variant.dropFirst()
                return #"{"name":"\#(variant)","debuggable":true,"assembleTask":"\#(path):assemble\#(task)","installTask":"\#(path):install\#(task)","compileSdk":"36","minSdk":"24","targetSdk":"36","applicationId":"dev.fixture.\#(name)","abiFilters":["arm64-v8a"]}"#
            }
            return #"{"path":"\#(path)","agpVersion":"8.13.2","compileSdk":"36","buildToolsVersion":"35.0.0","minSdk":"24","targetSdk":"36","ndkVersion":null,"cmakeVersion":null,"nativeBuildConfigured":false,"abiFilters":["arm64-v8a"],"variants":[\#(entries.joined(separator: ","))]}"#
        }
        fixture.modelJSON = #"{"gradleVersion":"8.13","daemonJavaVersion":"17.0.12","daemonJavaVendor":"Fixture","daemonJavaHome":"/private-jdk-home","modules":["#
            + module(":app", ["demoDebug", "prodDebug"]) + "," + module(":app-nia-catalog", ["debug"]) + "]}"
        try fixture.repo.write("project/settings.gradle.kts", "include(\":app\", \":app-nia-catalog\")")
        try fixture.repo.write("project/app-nia-catalog/build.gradle.kts", "plugins { id(\"com.android.application\") }")
        return fixture
    }
}

/// Once both approved SDK packages exist, the evaluated model drops :app demoDebug.
private struct RejectingAfterInstallRunner: ProcessRunner {
    let base: SDKPreparationRunner
    let fixture: SDKFixture

    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        let installed = ["sdk/build-tools/35.0.0", "sdk/platforms/android-36"].allSatisfy {
            FileManager.default.fileExists(atPath: fixture.repo.url($0).path)
        }
        guard installed, command.description == fixture.modelCommand, let model = fixture.modelJSON else {
            return try await base.run(command, onLine: onLine)
        }
        let rejecting = model.replacingOccurrences(of: #"{"name":"demoDebug""#, with: #"{"name":"stagingDebug""#)
        return ProcessResult(terminationStatus: .exited(0), standardOutput: AndroidGradleModelProbe.marker + rejecting, standardError: "")
    }

    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
        try await base.spawnDetached(command, logFile: logFile)
    }
}

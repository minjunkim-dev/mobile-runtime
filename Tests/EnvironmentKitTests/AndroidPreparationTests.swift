import Core
import CryptoKit
import EnvironmentKit
import Foundation
import TestSupport
import Testing
@testable import AndroidKit

@Suite("approved Android SDK preparation")
struct AndroidPreparationTests {
    @Test("a writable SDK root does not bypass a read-only existing package parent")
    func nestedPackagePermission() async throws {
        let fixture = try await SDKFixture()
        try fixture.repo.write("sdk/platforms/android-36/android.jar", "existing platform")
        try fixture.repo.write("sdk/platforms/android-36/source.properties", "Pkg.Revision=2\n")
        try fixture.repo.write("sdk/platforms/android-36/package.xml", "<repository><license id=\"fixture-license\">\(SDKFixture.licenseText)</license><localPackage><uses-license ref=\"fixture-license\"/></localPackage></repository>")
        let parent = try fixture.repo.directory("sdk/build-tools")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: parent.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: parent.path) }
        let runner = fixture.runner()
        let plan = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: runner)
        let installation = try #require(plan.plan?.steps.first { $0.installation != nil })
        #expect(installation.kind == "permission")
        let result = await PreparationExecution.run(input: fixture.input, approvedPlanID: try #require(plan.plan?.id), runner: runner)
        #expect(result.operation.state == "waiting-manual")
        #expect(result.operation.completed.isEmpty)
        #expect(runner.downloads.isEmpty)
    }

    @Test("WorkflowContext doctor and SDK requirements reuse one opaque actor and one model evaluation")
    func sharedWorkflowSDKContext() async throws {
        let fixture = try await SDKFixture()
        let runner = fixture.runner()
        let selected = try #require(fixture.input.selection().selected)
        let anchor = try #require(ProjectAnchor.detect(candidate: selected))
        let workflow = await WorkflowContext.make(input: fixture.input, platform: .android, anchor: anchor, runner: runner)
        _ = await workflow.engine.run()
        let context = try #require(workflow.androidContext)
        let requirements = try await context.sdkRequirements()
        #expect(requirements.blockers.isEmpty)
        #expect(runner.modelReadCount == 1)
    }

    @Test("an SDK inside the project preserves source and commits both approved packages")
    func projectLocalSDK() async throws {
        let fixture = try await SDKFixture()
        let destination = fixture.repo.url("project/local-sdk")
        try FileManager.default.moveItem(at: fixture.repo.url("sdk"), to: destination)
        try fixture.repo.write("project/local.properties", "sdk.dir=\(destination.path)\n")
        var environment = fixture.input.environment
        environment["ANDROID_HOME"] = destination.path
        let input = ProjectInspectionInput(directory: fixture.input.directory, environment: environment)
        let runner = fixture.runner()
        let plan = await PreparationExecution.run(input: input, planOnly: true, runner: runner)
        let result = await PreparationExecution.run(input: input, approvedPlanID: try #require(plan.plan?.id), runner: runner)
        let diagnostic = try result.encoded(toolVersion: "fixture")
        #expect(result.operation.completed.count == 2, Comment(rawValue: diagnostic))
        #expect(result.operation.changedFiles.isEmpty)
        #expect(try String(contentsOf: destination.appendingPathComponent("keep"), encoding: .utf8) == "original SDK file")
    }

    @Test("destination permissions stay manual and setup never requests administrator privileges")
    func manualPermission() async throws {
        let fixture = try await SDKFixture()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: fixture.repo.url("sdk").path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.repo.url("sdk").path) }
        let runner = fixture.runner()
        let plan = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: runner)
        #expect(plan.plan?.steps.filter { $0.installation != nil }.allSatisfy { $0.kind == "permission" } == true)
        let result = await PreparationExecution.run(input: fixture.input, approvedPlanID: try #require(plan.plan?.id), runner: runner)
        #expect(result.operation.state == "waiting-manual")
        #expect(result.operation.completed.isEmpty)
        #expect(runner.downloads.isEmpty)
    }

    @Test("plan-only pins exact artifacts and waits for separate license consent")
    func planAndLicense() async throws {
        let fixture = try await SDKFixture(licensed: false)
        let runner = fixture.runner()
        let plan = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: runner)
        let sdk = try #require(plan.plan?.steps.filter { $0.installation != nil })
        #expect(sdk.count == 2)
        #expect(sdk.allSatisfy { $0.kind == "license" })
        #expect(sdk.allSatisfy { $0.installation?.artifact.size ?? 0 > 0 })
        #expect(sdk.allSatisfy { $0.installation?.repositorySHA256.count == 64 })
        let waiting = await PreparationExecution.run(input: fixture.input, approvedPlanID: try #require(plan.plan?.id), runner: runner)
        #expect(waiting.operation.state == "waiting-manual")
        #expect(waiting.operation.completed.isEmpty)
        #expect(runner.downloads.isEmpty)
        let json = try plan.encoded(toolVersion: "fixture")
        #expect(!json.contains("private-jdk-home"))
        #expect(!json.contains("PRIVATE_ENV_CANARY"))
        try fixture.acceptFixtureLicense()
        let approved = await PreparationExecution.run(input: fixture.input, approvedPlanID: try #require(plan.plan?.id), runner: runner)
        #expect(approved.operation.state == "needs-approval")
        #expect(runner.downloads.isEmpty)
    }

    @Test("approved SDK packages complete while absent runtime stays manual")
    func sharedPreparation() async throws {
        let fixture = try await SDKFixture()
        let runner = fixture.runner()
        let plan = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: runner)
        #expect(plan.plan?.androidRequirements?.modules.first?.agpVersion == "8.13.2")
        let id = try #require(plan.plan?.id)
        let result = await PreparationExecution.run(input: fixture.input, approvedPlanID: id, runner: runner)
        let diagnostic = try result.encoded(toolVersion: "fixture")
        #expect(result.operation.completed.count == 2, Comment(rawValue: diagnostic))
        #expect(result.operation.state == "partial")
        #expect(result.operation.remaining.contains { $0.contains("android.avd") })
        #expect(result.operation.remaining.allSatisfy { !$0.hasPrefix("android.sdk.package.") })
        #expect(FileManager.default.fileExists(atPath: fixture.repo.url("sdk/platforms/android-36/android.jar").path))
        #expect(try String(contentsOf: fixture.repo.url("sdk/keep"), encoding: .utf8) == "original SDK file")
        #expect(try String(contentsOf: fixture.repo.url("project/settings.gradle.kts"), encoding: .utf8) == "include(\":app\")")
        let again = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: runner)
        #expect(again.plan?.steps.allSatisfy { $0.kind != "install" } == true)
        #expect(runner.downloads.count == 2)
    }

    @Test("failed second package preserves the first and retry installs only the remaining package")
    func partialFailureAndRetry() async throws {
        let fixture = try await SDKFixture()
        let failing = fixture.runner(failPlatform: true)
        let plan = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: failing)
        let failed = await PreparationExecution.run(input: fixture.input, approvedPlanID: try #require(plan.plan?.id), runner: failing)
        #expect(failed.operation.state == "failed")
        #expect(failed.operation.completed == ["android.sdk.package.build-tools;35.0.0"])
        #expect(FileManager.default.fileExists(atPath: fixture.repo.url("sdk/build-tools/35.0.0/aapt2").path))
        #expect(!FileManager.default.fileExists(atPath: fixture.repo.url("sdk/platforms/android-36").path))
        let runner = fixture.runner()
        let remaining = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: runner)
        #expect(remaining.plan?.id != plan.plan?.id)
        #expect(remaining.plan?.steps.filter { $0.kind == "install" }.map(\.id) == ["android.sdk.package.platforms;android-36"])
        let retried = await PreparationExecution.run(input: fixture.input, approvedPlanID: try #require(remaining.plan?.id), runner: runner)
        #expect(retried.operation.completed == ["android.sdk.package.platforms;android-36"])
        #expect(runner.downloads.count == 1)
    }

    @Test("cancellation after a committed package blocks the next package without deleting completion")
    func cancellation() async throws {
        let fixture = try await SDKFixture()
        let runner = fixture.runner()
        let plan = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: runner)
        let approved = try #require(plan.plan?.id)
        let task = Task {
            await PreparationExecution.run(input: fixture.input, approvedPlanID: approved, runner: runner, onEvent: { event in
                if event.stageId == "android.sdk.package.build-tools;35.0.0", event.state == "succeeded" {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            })
        }
        let result = await task.value
        #expect(result.exitCode == 130)
        #expect(result.operation.state == "cancelled")
        #expect(result.operation.completed == ["android.sdk.package.build-tools;35.0.0"])
        #expect(runner.downloads.count == 1)
        #expect(FileManager.default.fileExists(atPath: fixture.repo.url("sdk/build-tools/35.0.0/aapt2").path))
    }

    @Test("one SDK root lease blocks another setup and changed archive metadata invalidates approval")
    func sdkConflictAndChangedPin() async throws {
        let fixture = try await SDKFixture()
        let runner = fixture.runner()
        let plan = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: runner)
        let pin = try #require(plan.plan?.steps.compactMap(\.installation).first)
        let leases = ResourceLeases(directory: fixture.repo.url("leases"))
        let held = try leases.acquire([pin.resourceKey], owner: LeaseOwner(operationId: "other", command: "setup", project: "other project"))
        let denied = await PreparationExecution.run(input: fixture.input, approvedPlanID: try #require(plan.plan?.id), runner: runner, leases: leases)
        #expect(denied.operation.conflict?.key == pin.resourceKey)
        #expect(denied.operation.conflict?.owner?.operationId == "other")
        #expect(runner.downloads.isEmpty)
        held.release()
        let moved = fixture.runner(repositorySuffix: "\n")
        let stale = await PreparationExecution.run(input: fixture.input, approvedPlanID: try #require(plan.plan?.id), runner: moved, leases: leases)
        #expect(stale.operation.state == "needs-approval")
        #expect(moved.downloads.isEmpty)
    }

    @Test("fresh metadata is checked before and after acquiring the SDK lease", arguments: [3, 4])
    func metadataChangesAtExecution(read: Int) async throws {
        let fixture = try await SDKFixture()
        let runner = fixture.runner(metadataChangesAfter: read)
        let plan = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: runner)
        let result = await PreparationExecution.run(input: fixture.input, approvedPlanID: try #require(plan.plan?.id), runner: runner)
        #expect(result.operation.state == "needs-approval")
        #expect(result.operation.completed.isEmpty)
        #expect(runner.downloads.isEmpty)
        #expect(result.operation.error?.contains(read == 3 ? "immediately" : "acquiring") == true)
    }

    @Test("source mutation during download blocks package commit without restoring source")
    func sourceChangesDuringDownload() async throws {
        let fixture = try await SDKFixture()
        let runner = fixture.runner(mutateSource: true)
        let plan = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: runner)
        let result = await PreparationExecution.run(input: fixture.input, approvedPlanID: try #require(plan.plan?.id), runner: runner)
        #expect(result.operation.state == "failed")
        #expect(result.operation.completed.isEmpty)
        #expect(result.operation.changedFiles.contains { $0.hasSuffix("settings.gradle.kts") })
        #expect(runner.downloads.count == 1)
        #expect(!FileManager.default.fileExists(atPath: fixture.repo.url("sdk/build-tools/35.0.0").path))
        #expect(try String(contentsOf: fixture.repo.url("project/settings.gradle.kts"), encoding: .utf8) == "unexpected source mutation")
    }
}

private final class SDKFixture: @unchecked Sendable {
    let repo: FixtureRepo
    let input: ProjectInspectionInput
    let modelCommand: String
    let artifacts: [String: Data]
    let repository: String
    static let licenseText = "Synthetic test license; not an Android license"
    static var licenseHash: String { Insecure.SHA1.hash(data: Data(licenseText.utf8)).map { String(format: "%02x", $0) }.joined() }

    init(licensed: Bool = true) async throws {
        let repo = try FixtureRepo()
        self.repo = repo
        try repo.write("project/settings.gradle.kts", "include(\":app\")")
        try repo.write("project/build.gradle.kts", "plugins {}")
        try repo.write("project/app/build.gradle.kts", "plugins { id(\"com.android.application\") }")
        try repo.write("project/gradlew", "fixture")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: repo.url("project/gradlew").path)
        try repo.write("project/gradle/wrapper/gradle-wrapper.jar", "fixture")
        try repo.write("project/gradle/wrapper/gradle-wrapper.properties", "distributionUrl=https\\://services.gradle.org/distributions/gradle-8.13-bin.zip\n")
        try repo.write("project/local.properties", "sdk.dir=\(repo.url("sdk").path)\n")
        try repo.write("cache/wrapper/dists/gradle-8.13-bin/hash/gradle-8.13/bin/gradle", "fixture")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: repo.url("cache/wrapper/dists/gradle-8.13-bin/hash/gradle-8.13/bin/gradle").path)
        try repo.write("cache/wrapper/dists/gradle-8.13-bin/hash/gradle-8.13-bin.zip.ok", "")
        try repo.write("sdk/keep", "original SDK file")
        for (directory, executable) in [("platform-tools", "adb"), ("emulator", "emulator")] {
            try repo.write("sdk/\(directory)/\(executable)", "fixture")
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: repo.url("sdk/\(directory)/\(executable)").path)
            try repo.write("sdk/\(directory)/source.properties", "Pkg.Revision=1.0.0\n")
            try repo.write("sdk/\(directory)/package.xml", "<repository><license id=\"fixture-license\">\(Self.licenseText)</license><localPackage><uses-license ref=\"fixture-license\"/></localPackage></repository>")
        }
        if licensed { try repo.write("sdk/licenses/fixture-license", Self.licenseHash + "\n") }
        input = ProjectInspectionInput(directory: repo.url("project"), environment: ["HOME": repo.url("home").path,
            "GRADLE_USER_HOME": repo.url("cache").path, "ANDROID_HOME": repo.url("sdk").path,
            "ANDROID_AVD_HOME": repo.url("avds").path, "PRIVATE_ENV_CANARY": "never-public"])
        modelCommand = try #require(AndroidGradleModelProbe.command(androidDirectory: repo.url("project"))).description
        var payloads: [String: Data] = [:]
        var packages: [String] = []
        for (path, revision, file, archive) in [("build-tools;35.0.0", "35.0.0", "aapt2", "build-tools_r35_macosx.zip"),
                                               ("platforms;android-36", "2", "android.jar", "platform-36_r02.zip")] {
            let source = repo.url("archives/\(archive)")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try repo.write("archives/\(archive)/payload/source.properties", "Pkg.Revision=\(revision)\n")
            try repo.write("archives/\(archive)/payload/settings.gradle.kts", "// SDK sample, not project configuration\n")
            try repo.write("archives/\(archive)/payload/\(file)", "fixture")
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.appendingPathComponent("payload/\(file)").path)
            let archiveFile = repo.url(archive)
            let command = ProcessCommand("zip", ["-q", "-r", archiveFile.path, "payload"], workingDirectory: source)
            #expect(try await SystemProcessRunner().run(command).terminationStatus.isSuccess)
            let data = try Data(contentsOf: archiveFile)
            payloads[archive] = data
            let sha1 = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let parts = revision.split(separator: ".")
            let revisionXML = zip(["major", "minor", "micro"], parts).map { "<\($0.0)>\($0.1)</\($0.0)>" }.joined()
            let type = path.hasPrefix("platforms") ? "<api-level>36</api-level><extension-level>17</extension-level><base-extension>true</base-extension>" : ""
            packages.append("<remotePackage path=\"\(path)\"><type-details>\(type)</type-details><revision>\(revisionXML)</revision><uses-license ref=\"fixture-license\"/><channelRef ref=\"channel-0\"/><archives><archive><host-os>macosx</host-os><complete><size>\(data.count)</size><checksum type=\"sha1\">\(sha1)</checksum><url>\(archive)</url></complete></archive></archives></remotePackage>")
        }
        artifacts = payloads
        repository = "<sdk:sdk-repository xmlns:sdk=\"http://schemas.android.com/sdk/android/repo/repository2/03\" xmlns:common=\"http://schemas.android.com/repository/android/common/02\"><license id=\"fixture-license\">\(Self.licenseText)</license>\(packages.joined())</sdk:sdk-repository>"
    }
    func acceptFixtureLicense() throws { try repo.write("sdk/licenses/fixture-license", Self.licenseHash + "\n") }
    func runner(failPlatform: Bool = false, repositorySuffix: String = "", metadataChangesAfter: Int? = nil, mutateSource: Bool = false) -> SDKPreparationRunner {
        SDKPreparationRunner(fixture: self, failPlatform: failPlatform, repository: repository + repositorySuffix,
                             metadataChangesAfter: metadataChangesAfter, mutateSource: mutateSource)
    }
}

private final class SDKPreparationRunner: ProcessRunner, @unchecked Sendable {
    let fixture: SDKFixture
    let failPlatform: Bool
    let repository: String
    let metadataChangesAfter: Int?
    let mutateSource: Bool
    private let lock = NSLock()
    private var downloaded: [String] = []
    private var metadataReads = 0
    private var modelReads = 0
    var modelReadCount: Int { lock.withLock { modelReads } }
    var downloads: [String] { lock.withLock { downloaded } }
    init(fixture: SDKFixture, failPlatform: Bool, repository: String, metadataChangesAfter: Int?, mutateSource: Bool) {
        self.fixture = fixture; self.failPlatform = failPlatform; self.repository = repository
        self.metadataChangesAfter = metadataChangesAfter; self.mutateSource = mutateSource
    }
    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        if command.description == fixture.modelCommand { lock.withLock { modelReads += 1 } }
        if command.executable == "curl", let index = command.arguments.firstIndex(of: "--output") {
            let name = URL(string: command.arguments.last!)!.lastPathComponent
            lock.withLock { downloaded.append(name) }
            if failPlatform, name.hasPrefix("platform-") { return ProcessResult(terminationStatus: .exited(1), standardOutput: "", standardError: "fixture network failure") }
            try #require(fixture.artifacts[name]).write(to: URL(fileURLWithPath: command.arguments[index + 1]))
            if mutateSource { try fixture.repo.write("project/settings.gradle.kts", "unexpected source mutation") }
            return ProcessResult(terminationStatus: .exited(0), standardOutput: "", standardError: "")
        }
        if command.executable == "unzip" { return try await SystemProcessRunner().run(command, onLine: onLine) }
        if command.description == AndroidSDKRepository.command.description {
            let count = lock.withLock { metadataReads += 1; return metadataReads }
            let changed = metadataChangesAfter.map { count >= $0 } ?? false
            return ProcessResult(terminationStatus: .exited(0), standardOutput: repository + (changed ? "\n" : ""), standardError: "")
        }
        let model = #"{"gradleVersion":"8.13","daemonJavaVersion":"17.0.12","daemonJavaVendor":"Fixture","daemonJavaHome":"/private-jdk-home","modules":[{"path":":app","agpVersion":"8.13.2","compileSdk":"36","buildToolsVersion":"35.0.0","minSdk":"24","targetSdk":"36","ndkVersion":null,"cmakeVersion":null,"nativeBuildConfigured":false,"abiFilters":["arm64-v8a"],"variants":[{"name":"debug","debuggable":true,"assembleTask":":app:assembleDebug","installTask":":app:installDebug","compileSdk":"36","minSdk":"24","targetSdk":"36","applicationId":"dev.fixture","abiFilters":["arm64-v8a"]}]}]}"#
        return try await FakeProcessRunner(responses: [
            AndroidSDKRepository.command.description: .ok(repository),
            fixture.modelCommand: .ok(AndroidGradleModelProbe.marker + model),
            "java -XshowSettings:properties -version": .ok("java.version = 17.0.12\njava.vendor = Fixture\njava.home = /private-jdk-home\n"),
            "emulator -list-avds": .ok(""), "emulator -accel-check": .ok("accel:\n0\nHypervisor.Framework\n"),
        ]).run(command, onLine: onLine)
    }
    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 { fatalError("SDK preparation cannot spawn a runtime") }
}

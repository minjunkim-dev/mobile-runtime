import Core
import CryptoKit
import EnvironmentKit
import Foundation
import TestSupport
import Testing
@testable import AndroidKit

@Suite("native Android shared workflow")
struct NativeAndroidWorkflowTests {
    @Test("native doctor uses evaluated Gradle and SDK facts without React Native inputs")
    func doctor() async throws {
        let fixture = try NativeAndroidFixture()
        let runner = try fixture.runner()
        let result = try await EnvironmentInspection.run(input: fixture.input, runner: runner)
        #expect(result.selection.selected?.framework == .nativeAndroid)
        #expect(result.selection.platform == .android)
        #expect(!result.report.hasToolFailure)
        #expect(result.report.checks.contains { $0.id == "android.project" && $0.status == .pass })
        #expect(result.report.checks.contains { $0.id == "android.sdk" && $0.status == .pass })
        #expect(!result.report.checks.contains { ["project.framework", "node.version", "package-manager.version"].contains($0.id) })
        #expect(runner.log.all.filter { $0.arguments.contains("help") }.count == 1)
        #expect(!runner.log.all.contains { $0.arguments.contains(":app:assembleDebug") })
        try fixture.assertPreserved()
    }

    @Test("shared native build selects exact debug and produces an APK without runtime actions")
    func build() async throws {
        let fixture = try NativeAndroidFixture()
        let runner = try fixture.runner(variants: ["debugOptimized", "debug"])
        let result = await WorkflowExecution.run(.build, input: fixture.workflowInput, runner: runner, leases: fixture.leases)
        #expect(result.exitCode == 0, Comment(rawValue: result.up?.failure?.message ?? ""))
        #expect(result.operation.module == ":app")
        #expect(result.operation.variant == "debug")
        #expect(result.up?.context.androidProduct?.applicationId == NativeAndroidFixture.appID)
        #expect(result.up?.context.androidProduct?.abis == [])
        #expect(result.operation.completed == ["validate", "android.build"])
        #expect(runner.log.spawned.isEmpty)
        #expect(!runner.log.all.contains { ["adb", "emulator", "npm", "node", "curl"].contains($0.executable) })
        try fixture.assertPreserved()
    }

    @Test("native shared build does not require or probe absent runtime SDK tools")
    func buildWithoutRuntimeTools() async throws {
        let fixture = try NativeAndroidFixture()
        try FileManager.default.removeItem(at: fixture.repo.url("sdk/emulator/emulator"))
        try FileManager.default.removeItem(at: fixture.repo.url("sdk/platform-tools/adb"))
        var runner = try fixture.runner()
        runner.responses.removeValue(forKey: "emulator -accel-check")
        let result = await WorkflowExecution.run(.build, input: fixture.workflowInput, runner: runner, leases: fixture.leases)
        #expect(result.exitCode == 0, Comment(rawValue: result.up?.failure?.message ?? ""))
        #expect(!runner.log.all.contains { ["adb", "emulator"].contains($0.executable) })
    }

    @Test("native flavors require selection and accept only the explicitly selected runnable variant")
    func flavors() async throws {
        let fixture = try NativeAndroidFixture()
        let runner = try fixture.runner(variants: ["stagingDebug", "prodDebug"], builtVariant: "stagingDebug")
        let missing = await WorkflowExecution.run(.build, input: fixture.workflowInput, runner: runner, leases: fixture.leases)
        #expect(missing.operation.state == "needs-selection")
        #expect(missing.operation.requiredInput == ["--variant"])
        #expect(missing.operation.variants == ["prodDebug", "stagingDebug"])
        #expect(!runner.log.all.contains { $0.arguments.contains { $0.hasPrefix(":app:assemble") } })
        let selected = await WorkflowExecution.run(.build,
            input: WorkflowInput(project: fixture.input, variant: "stagingDebug"), runner: runner, leases: fixture.leases)
        #expect(selected.exitCode == 0, Comment(rawValue: selected.up?.failure?.message ?? ""))
        #expect(selected.up?.context.androidProduct?.variant == "stagingDebug")
        #expect(runner.log.all.contains { $0.arguments.first == ":app:assembleStagingDebug" })
        #expect(!runner.log.all.contains { $0.arguments.first == ":app:assembleProdDebug" })
        try fixture.assertPreserved()
    }

    @Test("native up and down retain app ownership and preserve a reused Emulator without Metro")
    func upAndDown() async throws {
        let fixture = try NativeAndroidFixture()
        let metro = try fixture.leases.acquire([.port(MetroVerdict.port)],
            owner: LeaseOwner(operationId: "other-metro", command: "fixture", project: "/another-project"))
        defer { metro.release() }
        let runner = try fixture.runner()
        let up = await WorkflowExecution.run(.up, input: fixture.workflowInput, runner: runner, leases: fixture.leases)
        #expect(up.exitCode == 0, Comment(rawValue: up.up?.failure?.message ?? ""))
        #expect(up.up?.context.androidProduct?.device?.state == .reused)
        #expect(up.up?.context.androidProduct?.appPid == 8123)
        #expect(up.up?.context.metro == nil)
        #expect(up.operation.completed == ["validate", "android.build", "android.device", "android.install", "android.launch"])
        var cleanup = try fixture.runner()
        cleanup.responses["adb -s emulator-5554 shell pidof \(NativeAndroidFixture.appID)"] = .failed(1, "")
        let down = await WorkflowExecution.run(.down, input: fixture.workflowInput, runner: cleanup, leases: fixture.leases)
        #expect(down.exitCode == 0, Comment(rawValue: down.down?.failure?.message ?? ""))
        #expect(down.down?.items.contains { $0.id == "android.app" && $0.status == .stopped } == true)
        #expect(down.down?.items.contains { $0.id == "android.emulator" && $0.status == .skipped } == true)
        #expect(cleanup.log.spawned.isEmpty)
        #expect(!cleanup.log.all.contains { ["./gradlew", "java", "npm", "node", "kill", "lsof"].contains($0.executable) || $0.arguments.contains("reverse") || $0.arguments.contains("uninstall") })
        try fixture.assertPreserved()
    }

    @Test("native cancellation preserves completed installation and existing runtime resources", arguments: [false, true])
    func cancellation(afterInstall: Bool) async throws {
        let fixture = try NativeAndroidFixture()
        var runner = try fixture.runner()
        let cancelledCommand = afterInstall
            ? "adb -s emulator-5554 shell am start -W -n \(NativeAndroidFixture.appID)/\(NativeAndroidFixture.appID).MainActivity"
            : fixture.assemble("debug")
        runner.failures[cancelledCommand] = CancellationError()
        let result = await WorkflowExecution.run(afterInstall ? .up : .build,
            input: fixture.workflowInput, runner: runner, leases: fixture.leases)
        #expect(result.exitCode == 130)
        #expect(result.operation.state == "cancelled")
        #expect(!runner.log.all.contains { ["npm", "sdkmanager", "curl", "kill"].contains($0.executable)
            || $0.arguments.contains("uninstall") || $0.arguments.contains("clear") || $0.arguments.contains("reverse") })
        if afterInstall {
            #expect(result.operation.completed.contains("android.install"))
            #expect(result.up?.context.androidProduct?.rollback?.contains { $0.id == "android.emulator" && $0.status == .skipped } == true)
        } else {
            #expect(!runner.log.all.contains { ["adb", "emulator"].contains($0.executable) })
        }
        try fixture.assertPreserved()
    }

    @Test("native install failure preserves existing devices and installed packages")
    func installFailure() async throws {
        let fixture = try NativeAndroidFixture()
        var runner = try fixture.runner()
        runner.responses["adb -s emulator-5554 install -r \(fixture.apk.path)"] = .failed(1, "INSTALL_FAILED_TEST")
        let result = await WorkflowExecution.run(.up, input: fixture.workflowInput, runner: runner, leases: fixture.leases)
        #expect(result.exitCode == 1)
        #expect(result.up?.failure?.message.contains("INSTALL_FAILED_TEST") == true)
        #expect(!runner.log.all.contains { $0.arguments.contains("uninstall") || $0.arguments.contains("clear") || $0.arguments.contains("reverse") || $0.executable == "kill" })
        #expect(!runner.log.all.contains { $0.arguments.contains("start") })
        try fixture.assertPreserved()
    }

    @Test("native shared workflow respects existing folder and device leases before assembly", arguments: [false, true])
    func resourceConflict(device: Bool) async throws {
        let fixture = try NativeAndroidFixture()
        let identity = try FolderIdentity(directory: fixture.project)
        let key: ResourceKey = device ? .device(.android, "avd:Pixel") : .folder(identity)
        let held = try fixture.leases.acquire([key],
            owner: LeaseOwner(operationId: "other", command: "fixture", project: identity.path))
        defer { held.release() }
        let runner = try fixture.runner()
        let result = await WorkflowExecution.run(device ? .up : .build,
            input: fixture.workflowInput, runner: runner, leases: fixture.leases)
        #expect(result.exitCode == 1)
        #expect(result.operation.conflict != nil)
        #expect(!runner.log.all.contains { $0.arguments.contains(":app:assembleDebug") })
        try fixture.assertPreserved()
    }
}

private final class NativeAndroidFixture {
    static let appID = "dev.fixture.native"
    let repo: FixtureRepo
    let modelScript: URL
    let source = "include(\":app\")\n"
    var project: URL { repo.url("project") }
    var apk: URL { repo.url("project/app/build/outputs/apk/app.apk") }
    var leases: ResourceLeases { ResourceLeases(directory: repo.url("leases")) }
    var input: ProjectInspectionInput {
        ProjectInspectionInput(directory: project, environment: ["HOME": repo.url("home").path,
            "GRADLE_USER_HOME": repo.url("cache").path, "ANDROID_HOME": repo.url("sdk").path,
            "ANDROID_AVD_HOME": repo.url("avds").path])
    }
    var workflowInput: WorkflowInput { WorkflowInput(project: input) }

    init() throws {
        repo = try FixtureRepo()
        modelScript = try #require(AndroidGradleModelProbe.scriptURL)
        try repo.write("project/settings.gradle.kts", source)
        try executable("project/gradlew")
        try repo.write("project/gradle/wrapper/gradle-wrapper.jar", "fixture jar")
        try repo.write("project/gradle/wrapper/gradle-wrapper.properties", "distributionUrl=https\\://services.gradle.org/distributions/gradle-8.13-bin.zip\n")
        try repo.write("project/local.properties", "sdk.dir=\(repo.url("sdk").path)\n")
        try executable("cache/wrapper/dists/gradle-8.13-bin/hash/gradle-8.13/bin/gradle")
        try repo.write("cache/wrapper/dists/gradle-8.13-bin/hash/gradle-8.13-bin.zip.ok", "")
        let license = "Synthetic fixture license"
        let hash = Insecure.SHA1.hash(data: Data(license.utf8)).map { String(format: "%02x", $0) }.joined()
        try repo.write("sdk/licenses/fixture-license", hash + "\n")
        for (path, file, revision) in [("build-tools/35.0.0", "aapt2", "35.0.0"),
                                       ("platforms/android-36", "android.jar", "2"),
                                       ("platform-tools", "adb", "1"), ("emulator", "emulator", "1")] {
            try executable("sdk/\(path)/\(file)")
            try repo.write("sdk/\(path)/source.properties", "Pkg.Revision=\(revision)\n")
            try repo.write("sdk/\(path)/package.xml", "<repository><license id=\"fixture-license\">\(license)</license><localPackage><uses-license ref=\"fixture-license\"/></localPackage></repository>")
        }
        try repo.directory("sdk/system-images/android-36/google_apis/arm64-v8a")
        try repo.write("avds/Pixel.avd/config.ini", "image.sysdir.1=system-images/android-36/google_apis/arm64-v8a/\nabi.type=arm64-v8a\ntarget=android-36\n")
        try repo.write("project/app/build/outputs/apk/app.apk", "fixture APK")
        try repo.write("project/app/build/AndroidManifest.xml", "<manifest xmlns:android=\"http://schemas.android.com/apk/res/android\" package=\"\(Self.appID)\"><uses-sdk android:minSdkVersion=\"24\" android:targetSdkVersion=\"36\"/><application><activity android:name=\".MainActivity\"><intent-filter><action android:name=\"android.intent.action.MAIN\"/><category android:name=\"android.intent.category.LAUNCHER\"/></intent-filter></activity></application></manifest>")
    }

    deinit { try? FileManager.default.removeItem(at: RunLogs(project: project).directory) }

    func executable(_ path: String) throws {
        try repo.write(path, "fixture")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: repo.url(path).path)
    }

    func assemble(_ variant: String) -> String {
        let task = ":app:assemble" + variant.prefix(1).uppercased() + variant.dropFirst()
        return "./gradlew \(task) --no-daemon --no-configuration-cache -Dorg.gradle.unsafe.isolated-projects=false --console=plain -Dorg.gradle.java.installations.auto-download=false -Pandroid.builder.sdkDownload=false -I \(modelScript.path)"
    }

    func runner(variants: [String] = ["debug"], builtVariant: String = "debug") throws -> FakeProcessRunner {
        try repo.write("project/app/build/outputs/apk/output-metadata.json", "{\"applicationId\":\"\(Self.appID)\",\"variantName\":\"\(builtVariant)\",\"elements\":[{\"type\":\"SINGLE\",\"filters\":[],\"outputFile\":\"app.apk\"}]}")
        let outputs = repo.url("project/app/build/outputs/apk").path
        let manifest = repo.url("project/app/build/AndroidManifest.xml").path
        let data = variants.map { name in
            "{\"name\":\"\(name)\",\"debuggable\":true,\"assembleTask\":\":app:assemble\(name.prefix(1).uppercased() + name.dropFirst())\",\"installTask\":\":app:install\(name.prefix(1).uppercased() + name.dropFirst())\",\"applicationId\":\"\(Self.appID)\",\"abiFilters\":[],\"apkDirectory\":\"\(outputs)\",\"mergedManifest\":\"\(manifest)\"}"
        }.joined(separator: ",")
        let model = "{\"gradleVersion\":\"8.13\",\"daemonJavaVersion\":\"17.0.12\",\"daemonJavaHome\":\"/fixture-jdk\",\"modules\":[{\"path\":\":app\",\"agpVersion\":\"8.13.2\",\"compileSdk\":\"36\",\"buildToolsVersion\":\"35.0.0\",\"minSdk\":\"24\",\"targetSdk\":\"36\",\"nativeBuildConfigured\":false,\"abiFilters\":[],\"variants\":[\(data)]}]}"
        var responses: [String: FakeProcessRunner.Response] = [
            "java -XshowSettings:properties -version": .ok("java.version = 17.0.12\njava.home = /fixture-jdk\n"),
            "emulator -accel-check": .ok("accel:\n0\nHypervisor.Framework\n"),
            "emulator -list-avds": .ok("Pixel\n"),
            "aapt2 dump badging \(apk.path)": .ok("package: name='\(Self.appID)' versionCode='1'\nminSdkVersion:'24'\ntargetSdkVersion:'36'\nlaunchable-activity: name='\(Self.appID).MainActivity' label='' icon=''\n"),
            "adb devices": .ok("List of devices attached\nemulator-5554 device\n"),
            "adb -s emulator-5554 emu avd name": .ok("Pixel\n"),
            "adb -s emulator-5554 shell getprop sys.boot_completed": .ok("1\n"),
            "adb -s emulator-5554 shell getprop ro.build.version.sdk": .ok("36\n"),
            "adb -s emulator-5554 shell getprop ro.product.cpu.abilist": .ok("arm64-v8a\n"),
            "adb -s emulator-5554 shell pm path android": .ok("package:/system/framework/framework-res.apk\n"),
            "adb -s emulator-5554 install -r \(apk.path)": .ok("Success\n"),
            "adb -s emulator-5554 shell pm path \(Self.appID)": .ok("package:/data/app/base.apk\n"),
            "adb -s emulator-5554 shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER \(Self.appID)": .ok("\(Self.appID)/.MainActivity\n"),
            "adb -s emulator-5554 shell am force-stop \(Self.appID)": .ok(""),
            "adb -s emulator-5554 shell am start -W -n \(Self.appID)/\(Self.appID).MainActivity": .ok("Status: ok\n"),
            "adb -s emulator-5554 shell pidof \(Self.appID)": .ok("8123\n"),
            "adb -s emulator-5554 shell dumpsys activity activities": .ok("mResumedActivity \(Self.appID)/\(Self.appID).MainActivity\n"),
        ]
        for offline in [false, true] {
            let command = try #require(AndroidGradleModelProbe.command(androidDirectory: project, offline: offline, timeout: nil))
            responses[command.description] = .ok(AndroidGradleModelProbe.marker + model)
        }
        for variant in variants { responses[assemble(variant)] = .ok("BUILD SUCCESSFUL\n") }
        return FakeProcessRunner(responses: responses)
    }

    func assertPreserved() throws {
        #expect(try String(contentsOf: repo.url("project/settings.gradle.kts"), encoding: .utf8) == source)
        #expect(!FileManager.default.fileExists(atPath: repo.url("project/package.json").path))
        #expect(try String(contentsOf: apk, encoding: .utf8) == "fixture APK")
    }
}

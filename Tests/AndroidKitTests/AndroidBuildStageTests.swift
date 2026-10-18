import Core
import Foundation
import TestSupport
import Testing

@testable import AndroidKit

private struct BuildScenario {
    let repo: FixtureRepo
    let anchor: ProjectAnchor
    let config: ConfigContext
    let runner: FakeProcessRunner
    let environment: AndroidEnvironment
    let stage: AndroidBuildStage
}

private struct AAPTAnsweringRunner: ProcessRunner {
    let base: FakeProcessRunner
    let badging: String

    func run(
        _ command: ProcessCommand,
        onLine: (@Sendable (String) -> Void)?
    ) async throws -> ProcessResult {
        var runner = base
        if command.executable == "aapt2" {
            runner.responses[command.description] = .ok(badging)
        }
        return try await runner.run(command, onLine: onLine)
    }

    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
        try await base.spawnDetached(command, logFile: logFile)
    }
}

private func buildExecutable(_ repo: FixtureRepo, _ path: String) throws {
    try repo.write(path, "tool")
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: repo.url(path).path)
}

private func buildModel(
    _ variants: String,
    apkDirectory: String,
    mergedManifest: String,
    includeArtifacts: Bool
) -> String {
    let evaluatedVariants = includeArtifacts
        ? variants.replacingOccurrences(
            of: "\"abiFilters\":[\"arm64-v8a\"]}",
            with: "\"abiFilters\":[\"arm64-v8a\"],\"apkDirectory\":\"\(apkDirectory)\",\"mergedManifest\":\"\(mergedManifest)\"}"
        )
        : variants
    return """
    {"gradleVersion":"8.13","daemonJavaVersion":"17.0.12","daemonJavaVendor":"Temurin","daemonJavaHome":"/jdk/17","modules":[{"path":":app","agpVersion":"8.13.2","compileSdk":"36","buildToolsVersion":"35.0.0","minSdk":"24","targetSdk":"36","ndkVersion":null,"cmakeVersion":null,"nativeBuildConfigured":false,"abiFilters":["arm64-v8a"],"variants":\(evaluatedVariants)}]}
    """
}

private let oneVariant =
    #"[{"name":"debug","debuggable":true,"assembleTask":":app:assembleDebug","installTask":":app:installDebug","compileSdk":"36","minSdk":"24","targetSdk":"36","applicationId":"dev.mobile.fixture","abiFilters":["arm64-v8a"]}]"#

private let healthyBadging = """
package: name='dev.mobile.fixture' versionCode='1' versionName='1.0'
minSdkVersion:'24'
targetSdkVersion:'36'
launchable-activity: name='dev.mobile.fixture.MainActivity'  label='' icon=''
native-code: 'arm64-v8a'
"""

private func buildScenario(
    variants: String = oneVariant,
    apkElement: String = #"{"type":"SINGLE","filters":[],"outputFile":"app-debug.apk"}"#,
    badging: String = healthyBadging,
    assembleResponse: FakeProcessRunner.Response = .ok("BUILD SUCCESSFUL\n"),
    modelArtifacts: Bool = true,
    emitArtifacts: Bool = false,
    native: Bool = false,
    metroPort: Int? = nil
) throws -> BuildScenario {
    let repo = try FixtureRepo()
    if native {
        try repo.write("settings.gradle.kts", "include(\":app\")")
    } else {
        try repo.write("package.json", #"{"dependencies":{"react-native":"0.83.1"},"devDependencies":{"@react-native/gradle-plugin":"0.83.1"}}"#)
        try repo.write("node_modules/react-native/package.json", #"{"version":"0.83.1"}"#)
        try repo.write("node_modules/@react-native/gradle-plugin/package.json", #"{"version":"0.83.1"}"#)
    }
    func path(_ value: String) -> String { native ? value : "android/" + value }
    try buildExecutable(repo, "gradle-home/wrapper/dists/gradle-8.13-bin/hash/gradle-8.13/bin/gradle")
    try repo.write("gradle-home/wrapper/dists/gradle-8.13-bin/hash/gradle-8.13-bin.zip.ok", "")
    if !native { try repo.directory("android") }
    if !native { try repo.write("android/gradle.properties", "reactNativeDevServerPort=8097\n") }
    try buildExecutable(repo, path("gradlew"))
    try repo.write(path("gradle/wrapper/gradle-wrapper.jar"), "jar")
    try repo.write(
        path("gradle/wrapper/gradle-wrapper.properties"),
        "distributionUrl=https\\://services.gradle.org/distributions/gradle-8.13-bin.zip\n"
    )
    let sdk = repo.url("sdk")
    try buildExecutable(repo, "sdk/build-tools/35.0.0/aapt2")
    try repo.write(path("local.properties"), "sdk.dir=\(sdk.path)\n")

    try repo.write(
        path("app/build/outputs/apk/debug/output-metadata.json"),
        """
        {"applicationId":"dev.mobile.fixture","variantName":"debug","elements":[\(apkElement)]}
        """
    )
    try repo.write(path("app/build/outputs/apk/debug/app-debug.apk"), "apk")
    try repo.write(
        path("app/build/intermediates/merged_manifests/debug/processDebugManifest/output-metadata.json"),
        #"{"applicationId":"dev.mobile.fixture","variantName":"debug","elements":[{"type":"SINGLE","filters":[],"outputFile":"AndroidManifest.xml"}]}"#
    )
    try repo.write(
        path("app/build/intermediates/merged_manifests/debug/processDebugManifest/AndroidManifest.xml"),
        """
        <manifest xmlns:android="http://schemas.android.com/apk/res/android" package="dev.mobile.fixture">
          <uses-sdk android:minSdkVersion="24" android:targetSdkVersion="36" />
          <application>
            <activity android:name=".MainActivity">
              <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
              </intent-filter>
            </activity>
          </application>
        </manifest>
        """
    )

    let anchor = try #require(ProjectAnchor.detect(from: repo.root))
    let config = ConfigContext.detect(anchor: anchor, workingDirectory: repo.root)
    let environment = AndroidEnvironment(values: [
        "ANDROID_HOME": sdk.path,
        "GRADLE_USER_HOME": repo.url("gradle-home").path,
        "PATH": "/usr/bin:/bin",
    ])
    let modelCommand = try #require(
        AndroidGradleModelProbe.command(
            androidDirectory: native ? repo.root : repo.url("android"), offline: false, timeout: nil
        )
    )
    let apkDirectory = repo.url(path("app/build/outputs/apk/debug")).path
    let mergedManifest = repo.url(
        path("app/build/intermediates/merged_manifests/debug/processDebugManifest/AndroidManifest.xml")
    ).path
    let modelScript = try #require(AndroidGradleModelProbe.scriptURL)
    let assemble = "./gradlew :app:assembleDebug --no-daemon "
        + (native ? "" : metroPort.map { "-PreactNativeDevServerPort=\($0) " } ?? "")
        + "--no-configuration-cache -Dorg.gradle.unsafe.isolated-projects=false --console=plain "
        + "-Dorg.gradle.java.installations.auto-download=false -Pandroid.builder.sdkDownload=false -I \(modelScript.path)"
    let emittedArtifacts = AndroidGradleModelProbe.artifactMarker
        + "{\"variant\":\"debug\",\"apkDirectory\":\"\(apkDirectory)\","
        + "\"mergedManifest\":\"\(mergedManifest)\"}\n"
    let buildResponse = emitArtifacts
        ? .ok("BUILD SUCCESSFUL\n" + emittedArtifacts)
        : assembleResponse
    let runner = FakeProcessRunner(responses: [
        modelCommand.description: .ok(
            AndroidGradleModelProbe.marker
                + buildModel(
                    variants,
                    apkDirectory: apkDirectory,
                    mergedManifest: mergedManifest,
                    includeArtifacts: modelArtifacts
                ) + "\n"
        ),
        assemble: buildResponse,
    ])
    let answering = AAPTAnsweringRunner(base: runner, badging: badging)
    let stage = AndroidBuildStage(
        anchor: anchor,
        config: config,
        hostRunner: answering,
        projectRunner: answering,
        environment: environment,
        logs: try .temporary(project: repo.root),
        metroPort: metroPort
    )
    return BuildScenario(
        repo: repo,
        anchor: anchor,
        config: config,
        runner: runner,
        environment: environment,
        stage: stage
    )
}

@Suite("Android build stage")
struct AndroidBuildStageTests {
    @Test("every explicit Metro endpoint overrides the declared native app resource port", arguments: [8081, 8097])
    func selectedDevelopmentPort(port: Int) async throws {
        let scenario = try buildScenario(metroPort: port)
        var context = UpContext()
        let outcome = try await scenario.stage.run(&context)
        #expect(outcome.status == .pass)
        #expect(scenario.runner.log.all.contains {
            $0.arguments.contains(":app:assembleDebug") && $0.arguments.contains("-PreactNativeDevServerPort=\(port)")
        })
        #expect(try String(contentsOf: scenario.repo.url("android/gradle.properties"), encoding: .utf8) == "reactNativeDevServerPort=8097\n")
        #expect(context.androidProduct?.applicationId == "dev.mobile.fixture")
    }
    @Test("native Android builds from its Gradle root without Node dependencies")
    func nativeBuildPipeline() async throws {
        let scenario = try buildScenario(native: true)
        let runner = AAPTAnsweringRunner(base: scenario.runner, badging: healthyBadging)
        let stages = androidBuildStages(anchor: scenario.anchor, doctor: DoctorEngine(checks: []),
            config: scenario.config, hostRunner: runner, projectRunner: runner,
            environment: scenario.environment, note: { _ in })
        let result = await UpPipeline(stages: stages).run()
        #expect(result.exitCode == 0, Comment(rawValue: result.failure?.message ?? ""))
        #expect(result.context.androidProduct?.applicationId == "dev.mobile.fixture")
        let commands = scenario.runner.log.all
        #expect(commands.filter { $0.executable == "./gradlew" }.allSatisfy { $0.workingDirectory == scenario.anchor.directory })
        #expect(!commands.contains { ["node", "npm", "yarn", "pnpm", "corepack"].contains($0.executable) })
        #expect(!FileManager.default.fileExists(atPath: scenario.repo.url("package.json").path))
    }

    @Test("only native Java or Kotlin APKs may omit native library ABI metadata", arguments: [false, true])
    func nativeUniversalAPK(native: Bool) async throws {
        let scenario = try buildScenario(badging: healthyBadging.replacingOccurrences(of: "native-code: 'arm64-v8a'", with: ""), native: native)
        var context = UpContext()
        if !native {
            await #expect(throws: DomainError.self) { try await scenario.stage.run(&context) }
            return
        }
        let outcome = try await scenario.stage.run(&context)
        #expect(outcome.status == .pass)
        #expect(context.androidProduct?.abis.isEmpty == true)
    }

    @Test("up rollback and down share SDK root domain failures", arguments: [true, false])
    func sdkRootFailureAcrossLifecycle(conflicting: Bool) async throws {
        let scenario = try buildScenario()
        try scenario.repo.directory("node_modules")
        let logs = try RunLogs.temporary(project: scenario.repo.root)
        let store = AndroidActiveRunStore(project: scenario.repo.root, logs: logs)
        let product = AndroidBuiltProduct(apkPath: "unused", module: ":app", variant: "debug",
            assembleTask: ":app:assembleDebug", applicationId: "dev.mobile.fixture", minSdk: "24",
            targetSdk: "36", abis: ["arm64-v8a"], launcherActivity: "dev.mobile.fixture.MainActivity")
        var record = AndroidActiveRun(project: scenario.repo.root, product: product)
        record.device = .init(avd: "Pixel", launcherPID: 7001, serial: "emulator-5554", api: 35,
                              abi: "arm64-v8a", state: .started)
        record.reverse = .init(serial: "emulator-5554", state: .created)
        record.app = .init(serial: "emulator-5554", applicationId: product.applicationId,
                           launched: true, pid: 8123)
        try store.write(record)
        let runner = AAPTAnsweringRunner(base: scenario.runner, badging: healthyBadging)
        var values = scenario.environment.values
        if !conflicting { values.removeValue(forKey: "ANDROID_HOME") }
        let environment = AndroidEnvironment(values: values)
        let properties = scenario.repo.url("android/local.properties")
        let changedProperties = Data((conflicting ? "sdk.dir=/different-sdk\n" : "").utf8)
        let up = await runAndroidUp(anchor: scenario.anchor, doctor: DoctorEngine(checks: []),
            config: scenario.config, hostRunner: runner, projectRunner: runner,
            environment: environment, logs: logs, note: { _ in }, onStageFinished: { stage in
                if stage.id == "android.build", stage.status == .pass {
                    do { try changedProperties.write(to: properties, options: .atomic) }
                    catch { Issue.record("Could not change SDK root after build: \(error)") }
                }
            })

        #expect(up.stages.last?.id == "android.device")
        #expect(up.exitCode == 1)
        #expect(up.context.androidRollbackExitCode == 1)
        #expect(up.context.androidRequiresTeardown)
        let remediation = try #require(up.failure?.remediation)
        let rollback = try #require(up.context.androidProduct?.rollback)
        #expect(rollback.map(\.status) == [.unknown, .unknown, .skipped, .unknown])
        for item in rollback where item.status == .unknown {
            #expect(item.remediation == remediation)
            #expect(item.detail == up.failure?.message)
        }
        #expect(try store.read() == record)

        let down = await androidTeardown(anchor: scenario.anchor, config: scenario.config,
            runner: runner, projectRunner: runner, environment: environment, logs: logs)
        #expect(down.exitCode == up.exitCode)
        #expect(down.failure?.remediation == remediation)
        #expect(down.items == rollback)
        #expect(try store.read() == record)
        #expect(!scenario.runner.log.all.contains { ["adb", "emulator", "kill"].contains($0.executable) })
        #expect(scenario.runner.log.spawned.isEmpty)
    }

    @Test("workflow target candidates use the existing debug default and normalized module", arguments: [false, true])
    func workflowTargetDefault(native: Bool) async throws {
        let scenario = try buildScenario(native: native)
        var runner = scenario.runner
        let offline = try #require(AndroidGradleModelProbe.command(androidDirectory: native ? scenario.repo.root : scenario.repo.url("android"), offline: true))
        let online = try #require(AndroidGradleModelProbe.command(androidDirectory: native ? scenario.repo.root : scenario.repo.url("android"), offline: false, timeout: nil))
        runner.responses[offline.description] = runner.responses[online.description]
        let target = try await AndroidWorkflowTarget.load(anchor: scenario.anchor,
            config: scenario.config.selecting(module: "app"), hostRunner: runner, projectRunner: runner,
            environment: scenario.environment)
        #expect(target.module == ":app")
        #expect(target.variant == "debug")
        #expect(target.requiredInput.isEmpty)
        #expect(target.modules == [":app"])
        #expect(!runner.log.all.contains { $0.arguments.contains(":app:assembleDebug") })
    }

    @Test("workflow target returns flavor candidates without assembling before selection", arguments: [false, true])
    func workflowFlavorSelection(native: Bool) async throws {
        let flavors = #"[{"name":"stagingDebug","debuggable":true,"assembleTask":":app:assembleStagingDebug","installTask":":app:installStagingDebug"},{"name":"prodDebug","debuggable":true,"assembleTask":":app:assembleProdDebug","installTask":":app:installProdDebug"}]"#
        let scenario = try buildScenario(variants: flavors, native: native)
        var runner = scenario.runner
        let offline = try #require(AndroidGradleModelProbe.command(androidDirectory: native ? scenario.repo.root : scenario.repo.url("android"), offline: true))
        let online = try #require(AndroidGradleModelProbe.command(androidDirectory: native ? scenario.repo.root : scenario.repo.url("android"), offline: false, timeout: nil))
        runner.responses[offline.description] = runner.responses[online.description]
        let target = try await AndroidWorkflowTarget.load(anchor: scenario.anchor, config: scenario.config,
            hostRunner: runner, projectRunner: runner, environment: scenario.environment)
        #expect(target.requiredInput == ["--variant"])
        #expect(target.variants == ["prodDebug", "stagingDebug"])
        #expect(target.variant == nil)
        #expect(runner.log.all.allSatisfy { $0.arguments.contains("--offline") })
    }
    @Test("one evaluated debug target builds one verified APK with the project wrapper")
    func buildsVerifiedAPK() async throws {
        let scenario = try buildScenario()
        var context = UpContext()

        let outcome = try await scenario.stage.run(&context)

        #expect(outcome.status == .pass)
        #expect(outcome.detail == ":app debug")
        #expect(context.androidProduct?.applicationId == "dev.mobile.fixture")
        #expect(context.androidProduct?.launcherActivity == "dev.mobile.fixture.MainActivity")
        #expect(context.androidProduct?.abis == ["arm64-v8a"])
        #expect(context.buildLog?.contains("android-build.log") == true)
        let gradle = scenario.runner.log.all.filter { $0.executable == "./gradlew" }
        #expect(gradle.count == 2)
        #expect(gradle[0].arguments.contains("--offline") == false)
        #expect(gradle[0].arguments.last == "help")
        #expect(gradle[1].arguments.first == ":app:assembleDebug")
        #expect(!gradle[1].arguments.contains { $0.hasPrefix("-PreactNativeDevServerPort=") })
        #expect(try String(contentsOf: scenario.repo.url("android/gradle.properties"), encoding: .utf8) == "reactNativeDevServerPort=8097\n")
        #expect(gradle[1].arguments.contains("clean") == false)
        #expect(gradle[1].arguments.contains("--offline") == false)
        #expect(gradle[1].arguments.contains("-I"))
        #expect(gradle[1].arguments.filter { $0.hasPrefix(":") }.count == 1)
        #expect(scenario.runner.log.all.contains { $0.executable == "gradle" } == false)
    }

    @Test("public AGP artifacts emitted by assemble replace unavailable configuration-time paths")
    func readsPostBuildArtifacts() async throws {
        let scenario = try buildScenario(modelArtifacts: false, emitArtifacts: true)
        var context = UpContext()

        let outcome = try await scenario.stage.run(&context)

        #expect(outcome.status == .pass)
        #expect(context.androidProduct?.applicationId == "dev.mobile.fixture")
    }

    @Test("multiple runnable variants fail before an assemble task is guessed")
    func variantAmbiguity() async throws {
        let variants =
            #"[{"name":"stagingDebug","debuggable":true,"assembleTask":":app:assembleStagingDebug","installTask":":app:installStagingDebug"},{"name":"prodDebug","debuggable":true,"assembleTask":":app:assembleProdDebug","installTask":":app:installProdDebug"}]"#
        let scenario = try buildScenario(variants: variants)
        var context = UpContext()

        let error = await #expect(throws: DomainError.self) {
            try await scenario.stage.run(&context)
        }

        #expect(error?.summary.contains("multiple runnable variants") == true)
        #expect(scenario.runner.log.all.filter { $0.executable == "./gradlew" }.count == 1)
        #expect(context.androidProduct == nil)
    }

    @Test("debug is assembled when debugOptimized is also runnable")
    func defaultDebugVariantBuilds() async throws {
        let variants =
            #"[{"name":"debugOptimized","debuggable":true,"assembleTask":":app:assembleDebugOptimized","installTask":":app:installDebugOptimized"},{"name":"debug","debuggable":true,"assembleTask":":app:assembleDebug","installTask":":app:installDebug","compileSdk":"36","minSdk":"24","targetSdk":"36","applicationId":"dev.mobile.fixture","abiFilters":["arm64-v8a"]}]"#
        let scenario = try buildScenario(variants: variants)
        var context = UpContext()

        let outcome = try await scenario.stage.run(&context)

        #expect(outcome.status == .pass)
        #expect(outcome.detail == ":app debug")
        let gradle = scenario.runner.log.all.filter { $0.executable == "./gradlew" }
        #expect(gradle.contains { $0.arguments.first == ":app:assembleDebug" })
        #expect(gradle.contains { $0.arguments.first == ":app:assembleDebugOptimized" } == false)
    }

    @Test("split APK output is rejected after Gradle succeeds")
    func rejectsSplitAPK() async throws {
        let scenario = try buildScenario(
            apkElement: #"{"type":"SPLIT","filters":[{"filterType":"ABI","value":"arm64-v8a"}],"outputFile":"app-arm64.apk"}"#
        )
        var context = UpContext()

        let error = await #expect(throws: DomainError.self) {
            try await scenario.stage.run(&context)
        }

        #expect(error?.summary.contains("one installable APK") == true)
        #expect(context.androidProduct == nil)
    }

    @Test("APK metadata mismatch is a domain failure, not a silent override")
    func rejectsMetadataMismatch() async throws {
        let scenario = try buildScenario(
            badging: healthyBadging.replacingOccurrences(
                of: "targetSdkVersion:'36'", with: "targetSdkVersion:'35'"
            )
        )
        var context = UpContext()

        let error = await #expect(throws: DomainError.self) {
            try await scenario.stage.run(&context)
        }

        #expect(error?.summary.contains("targetSdk") == true)
        #expect(context.androidProduct == nil)
    }

    @Test("Gradle non-zero is a domain failure with the streamed log retained")
    func gradleFailure() async throws {
        let scenario = try buildScenario(
            assembleResponse: .failed(1, "FAILURE: Build failed with an exception.\n")
        )
        var context = UpContext()

        let error = await #expect(throws: DomainError.self) {
            try await scenario.stage.run(&context)
        }

        #expect(error?.summary == "the Android build failed")
        #expect(error?.observed?.contains("FAILURE:") == true)
        #expect(context.buildLog?.contains("android-build.log") == true)
        #expect(context.androidProduct == nil)
        #expect(scenario.runner.log.all.contains { $0.executable == "aapt2" } == false)
    }

    @Test("pipeline is validate, Node dependencies, then Android build only")
    func pipelineOrder() throws {
        let scenario = try buildScenario()
        let stages = androidBuildStages(
            anchor: scenario.anchor,
            doctor: DoctorEngine(checks: []),
            config: scenario.config,
            hostRunner: scenario.runner,
            projectRunner: scenario.runner,
            environment: scenario.environment,
            note: { _ in }
        )

        #expect(stages.map(\.id) == ["validate", "dependencies", "android.build"])
        #expect(AndroidWorkflowValidation.checkIDs.contains("android.avd") == false)
        #expect(AndroidWorkflowValidation.checkIDs.contains("android.emulator.acceleration") == false)
    }
}

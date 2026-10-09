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
    emitArtifacts: Bool = false
) throws -> BuildScenario {
    let repo = try FixtureRepo()
    try repo.write(
        "package.json",
        #"{"dependencies":{"react-native":"0.83.1"},"devDependencies":{"@react-native/gradle-plugin":"0.83.1"}}"#
    )
    try repo.directory("android")
    try buildExecutable(repo, "android/gradlew")
    try repo.write("android/gradle/wrapper/gradle-wrapper.jar", "jar")
    try repo.write(
        "android/gradle/wrapper/gradle-wrapper.properties",
        "distributionUrl=https\\://services.gradle.org/distributions/gradle-8.13-bin.zip\n"
    )
    let sdk = repo.url("sdk")
    try buildExecutable(repo, "sdk/build-tools/35.0.0/aapt2")
    try repo.write("android/local.properties", "sdk.dir=\(sdk.path)\n")

    try repo.write(
        "android/app/build/outputs/apk/debug/output-metadata.json",
        """
        {"applicationId":"dev.mobile.fixture","variantName":"debug","elements":[\(apkElement)]}
        """
    )
    try repo.write("android/app/build/outputs/apk/debug/app-debug.apk", "apk")
    try repo.write(
        "android/app/build/intermediates/merged_manifests/debug/processDebugManifest/output-metadata.json",
        #"{"applicationId":"dev.mobile.fixture","variantName":"debug","elements":[{"type":"SINGLE","filters":[],"outputFile":"AndroidManifest.xml"}]}"#
    )
    try repo.write(
        "android/app/build/intermediates/merged_manifests/debug/processDebugManifest/AndroidManifest.xml",
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
        "PATH": "/usr/bin:/bin",
    ])
    let modelCommand = try #require(
        AndroidGradleModelProbe.command(
            androidDirectory: repo.url("android"), offline: false, timeout: nil
        )
    )
    let apkDirectory = repo.url("android/app/build/outputs/apk/debug").path
    let mergedManifest = repo.url(
        "android/app/build/intermediates/merged_manifests/debug/processDebugManifest/AndroidManifest.xml"
    ).path
    let modelScript = try #require(AndroidGradleModelProbe.scriptURL)
    let assemble = "./gradlew :app:assembleDebug --no-daemon --console=plain "
        + "-Porg.gradle.java.installations.auto-download=false -I \(modelScript.path)"
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
        logs: try .temporary(project: repo.root)
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
    @Test("workflow target candidates use the existing debug default and normalized module")
    func workflowTargetDefault() async throws {
        let scenario = try buildScenario()
        var runner = scenario.runner
        let offline = try #require(AndroidGradleModelProbe.command(androidDirectory: scenario.repo.url("android"), offline: true))
        let online = try #require(AndroidGradleModelProbe.command(androidDirectory: scenario.repo.url("android"), offline: false, timeout: nil))
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

    @Test("workflow target returns flavor candidates without assembling before selection")
    func workflowFlavorSelection() async throws {
        let flavors = #"[{"name":"stagingDebug","debuggable":true,"assembleTask":":app:assembleStagingDebug","installTask":":app:installStagingDebug"},{"name":"prodDebug","debuggable":true,"assembleTask":":app:assembleProdDebug","installTask":":app:installProdDebug"}]"#
        let scenario = try buildScenario(variants: flavors)
        var runner = scenario.runner
        let offline = try #require(AndroidGradleModelProbe.command(androidDirectory: scenario.repo.url("android"), offline: true))
        let online = try #require(AndroidGradleModelProbe.command(androidDirectory: scenario.repo.url("android"), offline: false, timeout: nil))
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

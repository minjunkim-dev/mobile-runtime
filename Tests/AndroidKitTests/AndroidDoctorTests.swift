import Core
import Foundation
import TestSupport
import Testing

@testable import AndroidKit

private struct AndroidScenario {
    let repo: FixtureRepo
    let anchor: ProjectAnchor
    let config: ConfigContext
    let runner: FakeProcessRunner
    let environment: AndroidEnvironment
    let modelCommand: ProcessCommand
}

private func executable(_ repo: FixtureRepo, _ path: String, contents: String = "tool") throws {
    try repo.write(path, contents)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: repo.url(path).path)
}

private func modelJSON(variants: String? = nil, abiFilters: String = #"["arm64-v8a"]"#) -> String {
    let variants = variants ??
        """
        [{"name":"debug","debuggable":true,"assembleTask":":app:assembleDebug","installTask":":app:installDebug","compileSdk":"36","minSdk":"24","targetSdk":"36","applicationId":"dev.mobile.fixture","abiFilters":\(abiFilters)}]
        """
    return """
    {"gradleVersion":"8.13","daemonJavaVersion":"17.0.12","daemonJavaVendor":"Temurin","daemonJavaHome":"/jdk/17","modules":[{"path":":app","agpVersion":"8.13.2","compileSdk":"36","buildToolsVersion":"35.0.0","minSdk":"24","targetSdk":"36","ndkVersion":null,"cmakeVersion":null,"nativeBuildConfigured":false,"abiFilters":\(abiFilters),"variants":\(variants)}]}
    """
}

private func nativeModelJSON(agp: String? = "8.12.0", cmake: String? = nil, cmakeConfigured: Bool = true) -> String {
    modelJSON()
        .replacingOccurrences(of: #""agpVersion":"8.13.2""#, with: "\"agpVersion\":\(agp.map { "\"\($0)\"" } ?? "null")")
        .replacingOccurrences(
            of: #""ndkVersion":null,"cmakeVersion":null,"nativeBuildConfigured":false"#,
            with: "\"ndkVersion\":\"27.1.12297006\",\"cmakeVersion\":\(cmake.map { "\"\($0)\"" } ?? "null"),\"nativeBuildConfigured\":true,\"cmakeConfigured\":\(cmakeConfigured)"
        )
}

private func scenario(
    materializedWrapper: Bool = true,
    modelResponse: FakeProcessRunner.Response? = nil,
    variants: String? = nil,
    avdNames: [String] = ["Pixel_API_35"],
    sdkDir: String? = nil,
    androidHome: String? = nil,
    adbResponse: FakeProcessRunner.Response = .ok("List of devices attached\n\n"),
    installSystemImage: Bool = true
) throws -> AndroidScenario {
    let repo = try FixtureRepo()
    try repo.write(
        "package.json",
        #"{"dependencies":{"react-native":"0.83.1"},"devDependencies":{"@react-native/gradle-plugin":"0.83.1"}}"#
    )
    try repo.write("node_modules/react-native/package.json", #"{"version":"0.83.1"}"#)
    try repo.write("node_modules/@react-native/gradle-plugin/package.json", #"{"version":"0.83.1"}"#)
    try repo.directory("android")
    try executable(repo, "android/gradlew")
    try repo.write("android/gradle/wrapper/gradle-wrapper.jar", "jar")
    try repo.write(
        "android/gradle/wrapper/gradle-wrapper.properties",
        "distributionUrl=https\\://services.gradle.org/distributions/gradle-8.13-bin.zip\n"
    )

    let gradleHome = repo.url("gradle-home")
    if materializedWrapper {
        try executable(
            repo,
            "gradle-home/wrapper/dists/gradle-8.13-bin/hash/gradle-8.13/bin/gradle"
        )
        try repo.write("gradle-home/wrapper/dists/gradle-8.13-bin/hash/gradle-8.13-bin.zip.ok", "")
    }

    let sdk = repo.url("sdk")
    try repo.write("sdk/platforms/android-36/android.jar", "android")
    try executable(repo, "sdk/build-tools/35.0.0/aapt2")
    try executable(repo, "sdk/platform-tools/adb")
    try executable(repo, "sdk/emulator/emulator")
    if installSystemImage {
        try repo.directory("sdk/system-images/android-35/google_apis/arm64-v8a")
    }

    let avdHome = repo.url("avd-home")
    for name in avdNames {
        let directory = repo.url("avds/\(name).avd")
        try repo.write("avd-home/\(name).ini", "path=\(directory.path)\n")
        try repo.write(
            "avds/\(name).avd/config.ini",
            "image.sysdir.1=system-images/android-35/google_apis/arm64-v8a/\nabi.type=arm64-v8a\n"
        )
    }

    let localSDK = sdkDir ?? sdk.path
    try repo.write("android/local.properties", "sdk.dir=\(localSDK)\n")
    let environment = AndroidEnvironment(values: [
        "HOME": repo.url("home").path,
        "GRADLE_USER_HOME": gradleHome.path,
        "ANDROID_HOME": androidHome ?? sdk.path,
        "ANDROID_AVD_HOME": avdHome.path,
        "PATH": "/usr/bin:/bin",
    ])
    let modelCommand = try #require(AndroidGradleModelProbe.command(androidDirectory: repo.url("android")))
    let response = modelResponse ?? .ok(AndroidGradleModelProbe.marker + modelJSON(variants: variants) + "\n")
    let runner = FakeProcessRunner(responses: [
        "node --version": .ok("v20.19.0\n"),
        "java -XshowSettings:properties -version": FakeProcessRunner.Response(
            standardError: "java.version = 17.0.12\njava.vendor = Temurin\njava.home = /jdk/17\n"
        ),
        modelCommand.description: response,
        "emulator -list-avds": .ok(avdNames.joined(separator: "\n") + "\n"),
        "adb devices": adbResponse,
        "emulator -accel-check": .ok("accel:\n0\nHypervisor.Framework OS X Version 13+\n"),
    ])
    let anchor = try #require(ProjectAnchor.detect(from: repo.root))
    return AndroidScenario(
        repo: repo,
        anchor: anchor,
        config: ConfigContext.detect(anchor: anchor, workingDirectory: repo.root),
        runner: runner,
        environment: environment,
        modelCommand: modelCommand
    )
}

private func checks(_ scenario: AndroidScenario) -> [any Check] {
    androidChecks(
        anchor: scenario.anchor,
        config: scenario.config,
        hostRunner: scenario.runner,
        projectRunner: scenario.runner,
        environment: scenario.environment
    )
}

private func composedChecks(_ scenario: AndroidScenario) async -> [any Check] {
    let projectEnvironment = await ProjectExecutionEnvironment.resolve(
        anchor: scenario.anchor,
        hostRunner: scenario.runner
    )
    let platform = checks(scenario)
    var composed: [any Check] = [platform[0]]
    composed.append(contentsOf: projectEnvironment.commonChecks(anchor: scenario.anchor, context: scenario.config))
    composed.append(contentsOf: platform.dropFirst())
    return composed
}

@Suite("Android doctor")
struct AndroidDoctorTests {
    @Test("Java versions with a fourth component or suffix order by the first three")
    func javaVersionShapes() {
        #expect(SemanticVersion(java: "21.0.12.1") == SemanticVersion("21.0.12"))
        #expect(SemanticVersion(java: "21.0.12.1+7") == SemanticVersion("21.0.12"))
        #expect(SemanticVersion(java: "21.0.12.1-ea") == SemanticVersion("21.0.12"))
        #expect(SemanticVersion(java: "17.0.12") == SemanticVersion("17.0.12"))
        #expect(SemanticVersion(java: "21.0.12.beta") == nil)
        #expect(SemanticVersion(java: "21.0.12.") == nil)
        #expect(SemanticVersion(java: "21.0.12..1") == nil)
        // Lock files and declarations stay strict: a fourth component is not silently dropped.
        #expect(SemanticVersion("1.16.0.1") == nil)
    }

    @Test("a complete local tuple passes all eight stable Android checks without build or provisioning tasks")
    func healthyTuple() async throws {
        let scenario = try scenario()
        let composed = await composedChecks(scenario)

        let report = await DoctorEngine(checks: composed).run()
        let android = report.checks.filter { $0.id.hasPrefix("android.") }

        #expect(android.map(\.id) == [
            "android.project",
            "android.gradle.wrapper",
            "android.jdk",
            "android.target",
            "android.gradle.compatibility",
            "android.sdk",
            "android.avd",
            "android.emulator.acceleration",
        ])
        #expect(android.allSatisfy { $0.status == .pass })
        #expect(report.exitCode == 0)
        let gradleCommands = scenario.runner.log.all.filter { $0.executable == "./gradlew" }
        #expect(gradleCommands.count == 1)
        #expect(gradleCommands[0].arguments.contains("--offline"))
        #expect(gradleCommands[0].arguments.contains("--no-daemon"))
        #expect(gradleCommands[0].arguments.contains("-Porg.gradle.java.installations.auto-download=false"))
        #expect(gradleCommands[0].arguments.last == "help")
        #expect(gradleCommands[0].arguments.contains {
            $0.hasPrefix(":") && $0.localizedCaseInsensitiveContains("assemble")
        } == false)
        #expect(gradleCommands[0].arguments.contains {
            $0.hasPrefix(":") && $0.localizedCaseInsensitiveContains("install")
        } == false)
    }

    @Test("build validation does not require adb or Emulator packages")
    func buildSDKSubset() async throws {
        let scenario = try scenario()
        try FileManager.default.removeItem(at: scenario.repo.url("sdk/platform-tools/adb"))
        try FileManager.default.removeItem(at: scenario.repo.url("sdk/emulator/emulator"))
        let buildChecks = androidChecks(
            anchor: scenario.anchor,
            config: scenario.config,
            hostRunner: scenario.runner,
            projectRunner: scenario.runner,
            environment: scenario.environment,
            includeRuntimeSDKTools: false
        )

        let report = await DoctorEngine(checks: buildChecks).run(only: ["android.sdk"])

        #expect(report.checks.first { $0.id == "android.sdk" }?.status == .pass)
        #expect(scenario.runner.log.all.contains { $0.executable == "adb" } == false)
        #expect(scenario.runner.log.all.contains { $0.executable == "emulator" } == false)
    }

    @Test("a pinned wrapper that is not local warns and never runs Gradle")
    func wrapperNotMaterialized() async throws {
        let scenario = try scenario(materializedWrapper: false)

        let report = await DoctorEngine(checks: checks(scenario)).run(only: ["android.gradle.wrapper"])
        let wrapper = try #require(report.checks.first { $0.id == "android.gradle.wrapper" })

        #expect(wrapper.status == .warning)
        #expect(wrapper.outcome.remediation?.command?.contains("./gradlew --version") == true)
        #expect(scenario.runner.log.all.contains { $0.executable == "./gradlew" } == false)
    }

    @Test("missing dependencies warn only when exact RN and RNGP inputs are declared")
    func missingExactFrameworkInputs() async throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies":{"react-native":"^0.83.0"}}"#)
        try repo.directory("android")
        let anchor = try #require(ProjectAnchor.detect(from: repo.root))
        let runner = FakeProcessRunner(responses: [:])
        let platform = androidChecks(
            anchor: anchor,
            config: ConfigContext.detect(anchor: anchor, workingDirectory: repo.root),
            hostRunner: runner,
            projectRunner: runner,
            environment: AndroidEnvironment(values: [:])
        )

        let report = await DoctorEngine(checks: platform).run(only: ["android.project"])
        let project = try #require(report.checks.first)

        #expect(project.status == .error)
        #expect(project.outcome.required?.contains("exact react-native") == true)
    }

    @Test("an offline model cache miss is a materialization warning, not a download or a false pass")
    func modelNotMaterialized() async throws {
        let scenario = try scenario(
            modelResponse: .failed(1, "No cached version of com.android.tools.build:gradle available for offline mode")
        )

        let report = await DoctorEngine(checks: checks(scenario)).run(only: ["android.target"])
        let target = try #require(report.checks.first { $0.id == "android.target" })

        #expect(target.status == .warning)
        #expect(target.outcome.observed?.contains("offline") == true)
        #expect(target.outcome.remediation?.command?.contains("./gradlew help") == true)
        #expect(report.exitCode == 0)
    }

    @Test("multiple runnable variants require the Android selector")
    func variantAmbiguity() async throws {
        let variants = #"[{"name":"debug","debuggable":true,"assembleTask":":app:assembleDebug","installTask":":app:installDebug"},{"name":"stagingDebug","debuggable":true,"assembleTask":":app:assembleStagingDebug","installTask":":app:installStagingDebug"}]"#
        let scenario = try scenario(variants: variants)

        let report = await DoctorEngine(checks: checks(scenario)).run(only: ["android.target"])
        let target = try #require(report.checks.first { $0.id == "android.target" })

        #expect(target.status == .warning)
        #expect(target.outcome.required == "android.variant in mobile.yml")
        #expect(target.outcome.observed?.contains("stagingDebug") == true)
    }

    @Test("conflicting sdk.dir and ANDROID_HOME is an error instead of choosing one")
    func sdkRootConflict() async throws {
        let scenario = try scenario(
            materializedWrapper: false,
            androidHome: "/another/android-sdk"
        )

        let report = await DoctorEngine(checks: checks(scenario)).run(only: ["android.sdk"])
        let sdk = try #require(report.checks.first { $0.id == "android.sdk" })

        #expect(sdk.status == .error)
        #expect(sdk.outcome.observed?.contains("different SDK roots") == true)
        #expect(sdk.outcome.remediation != nil)
    }

    @Test("daemon JVM criteria must match the JDK that evaluated Gradle")
    func daemonJVMCriteriaMismatch() async throws {
        let scenario = try scenario()
        try scenario.repo.write("android/gradle/gradle-daemon-jvm.properties", "toolchainVersion=21\n")
        let composed = await composedChecks(scenario)

        let report = await DoctorEngine(checks: composed).run(only: ["android.jdk"])
        let jdk = try #require(report.checks.first { $0.id == "android.jdk" })

        #expect(jdk.status == .error)
        #expect(jdk.outcome.required?.contains("JDK 21") == true)
    }

    @Test("daemon JVM vendor criteria must match the evaluated JDK")
    func daemonJVMVendorMismatch() async throws {
        let scenario = try scenario()
        try scenario.repo.write(
            "android/gradle/gradle-daemon-jvm.properties",
            "toolchainVersion=17\ntoolchainVendor=AZUL\n"
        )

        let report = await DoctorEngine(checks: await composedChecks(scenario)).run(only: ["android.jdk"])
        let jdk = try #require(report.checks.first { $0.id == "android.jdk" })

        #expect(jdk.status == .error)
        #expect(jdk.outcome.required?.contains("AZUL") == true)
    }

    @Test("a distinct compiler toolchain stays unknown until independently selected")
    func compilerToolchainUnknown() async throws {
        let model = modelJSON().replacingOccurrences(
            of: #""nativeBuildConfigured":false,"abiFilters""#,
            with: #""nativeBuildConfigured":false,"toolchainJavaVersion":"21","abiFilters""#
        )
        let scenario = try scenario(
            modelResponse: .ok(AndroidGradleModelProbe.marker + model + "\n")
        )

        let report = await DoctorEngine(checks: await composedChecks(scenario)).run(only: ["android.jdk"])
        let jdk = try #require(report.checks.first { $0.id == "android.jdk" })

        #expect(jdk.status == .unknown)
        #expect(jdk.outcome.reason?.contains("compiler toolchain JDK 21") == true)
    }

    @Test("AVD compatibility stays unknown until Gradle exposes a pre-build ABI")
    func avdABIUnknown() async throws {
        let response = FakeProcessRunner.Response.ok(
            AndroidGradleModelProbe.marker + modelJSON(abiFilters: "[]") + "\n"
        )
        let scenario = try scenario(modelResponse: response)

        let report = await DoctorEngine(checks: checks(scenario)).run(only: ["android.avd"])
        let avd = try #require(report.checks.first { $0.id == "android.avd" })

        #expect(avd.status == .unknown)
        #expect(avd.outcome.reason?.contains("no pre-build ABI evidence") == true)
        #expect(scenario.runner.log.all.contains { $0.arguments.contains("-list-avds") } == false)
    }

    @Test("AVD compatibility falls back to a declared module ABI when the variant exposes none")
    func avdModuleABIFallback() async throws {
        let variants = #"[{"name":"debug","debuggable":true,"assembleTask":":app:assembleDebug","installTask":":app:installDebug","compileSdk":"36","minSdk":"24","targetSdk":"36","applicationId":"dev.mobile.fixture","abiFilters":[]}]"#
        let response = FakeProcessRunner.Response.ok(
            AndroidGradleModelProbe.marker + modelJSON(variants: variants) + "\n"
        )
        let scenario = try scenario(modelResponse: response)

        let report = await DoctorEngine(checks: checks(scenario)).run(only: ["android.avd"])
        let avd = try #require(report.checks.first { $0.id == "android.avd" })

        #expect(avd.status == .pass)
        #expect(avd.outcome.observed?.contains("arm64-v8a") == true)
    }

    @Test("selected variant compileSdk outranks the module default")
    func variantCompileSDK() async throws {
        let variant = #"[{"name":"debug","debuggable":true,"assembleTask":":app:assembleDebug","installTask":":app:installDebug","compileSdk":"37","minSdk":"24","targetSdk":"37","applicationId":"dev.mobile.fixture","abiFilters":["arm64-v8a"]}]"#
        let response = FakeProcessRunner.Response.ok(
            AndroidGradleModelProbe.marker + modelJSON(variants: variant) + "\n"
        )
        let scenario = try scenario(modelResponse: response)

        let report = await DoctorEngine(checks: checks(scenario)).run(only: ["android.sdk"])
        let sdk = try #require(report.checks.first { $0.id == "android.sdk" })

        #expect(sdk.status == .error)
        #expect(sdk.outcome.observed?.contains("SDK Platform android-37") == true)
    }

    @Test("selected variant minSdk outranks the module default for AVD selection")
    func variantMinSDK() async throws {
        let variant = #"[{"name":"debug","debuggable":true,"assembleTask":":app:assembleDebug","installTask":":app:installDebug","compileSdk":"36","minSdk":"40","targetSdk":"40","applicationId":"dev.mobile.fixture","abiFilters":["arm64-v8a"]}]"#
        let response = FakeProcessRunner.Response.ok(
            AndroidGradleModelProbe.marker + modelJSON(variants: variant) + "\n"
        )
        let scenario = try scenario(modelResponse: response)

        let report = await DoctorEngine(checks: checks(scenario)).run(only: ["android.avd"])
        let avd = try #require(report.checks.first { $0.id == "android.avd" })

        #expect(avd.status == .error)
        #expect(avd.outcome.observed?.contains("minSdk 40") == true)
    }

    @Test("a stale AVD config does not stand in for an installed system image")
    func staleAVDSystemImage() async throws {
        let scenario = try scenario(installSystemImage: false)

        let report = await DoctorEngine(checks: checks(scenario)).run(only: ["android.avd"])
        let avd = try #require(report.checks.first { $0.id == "android.avd" })

        #expect(avd.status == .error)
        #expect(avd.outcome.observed?.contains("no existing AVD") == true)
    }

    @Test("a native build without exact native tool versions stays unknown")
    func nativeToolVersionsUnknown() async throws {
        let model = modelJSON().replacingOccurrences(
            of: #""ndkVersion":null,"cmakeVersion":null,"nativeBuildConfigured":false"#,
            with: #""ndkVersion":null,"cmakeVersion":null,"nativeBuildConfigured":true,"cmakeConfigured":true,"ndkBuildConfigured":false"#
        )
        let scenario = try scenario(
            modelResponse: .ok(AndroidGradleModelProbe.marker + model + "\n")
        )

        let report = await DoctorEngine(checks: checks(scenario)).run(only: ["android.sdk"])
        let sdk = try #require(report.checks.first { $0.id == "android.sdk" })

        #expect(sdk.status == .unknown)
        #expect(sdk.outcome.reason?.contains("exact NDK version") == true)
    }

    @Test("unspecified CMake uses the bundled AGP default without provisioning", arguments: [false, true])
    func defaultCMakePackage(installed: Bool) async throws {
        let scenario = try scenario(modelResponse: .ok(AndroidGradleModelProbe.marker + nativeModelJSON() + "\n"))
        try scenario.repo.directory("sdk/ndk/27.1.12297006")
        try executable(scenario.repo, "sdk/cmdline-tools/latest/bin/sdkmanager")
        if installed { try scenario.repo.directory("sdk/cmake/3.22.1") }

        let report = await DoctorEngine(checks: checks(scenario)).run(only: ["android.sdk"])
        let sdk = try #require(report.checks.first { $0.id == "android.sdk" })

        #expect(sdk.status == (installed ? .pass : .error))
        #expect(sdk.outcome.observed?.contains("CMake 3.22.1") == true)
        #expect(sdk.outcome.source.tier == 2)
        #expect(sdk.outcome.source.origin.contains("AGP 8.12.0 → CMake 3.22.1"))
        if !installed {
            #expect(sdk.outcome.remediation?.command?.contains("cmake;3.22.1") == true)
            #expect(!FileManager.default.fileExists(atPath: scenario.repo.url("sdk/cmake/3.22.1").path))
        }
    }

    @Test("an explicit CMake version wins over the bundled default", arguments: ["8.12.0", "99.0.0"])
    func explicitCMakePackage(agp: String) async throws {
        let model = nativeModelJSON(agp: agp, cmake: "3.18.1")
        let scenario = try scenario(modelResponse: .ok(AndroidGradleModelProbe.marker + model + "\n"))
        try scenario.repo.directory("sdk/ndk/27.1.12297006")
        try scenario.repo.directory("sdk/cmake/3.18.1")

        let report = await DoctorEngine(checks: checks(scenario)).run(only: ["android.sdk"])
        let sdk = try #require(report.checks.first { $0.id == "android.sdk" })

        #expect(sdk.status == .pass)
        #expect(sdk.outcome.observed?.contains("CMake 3.18.1") == true)
        #expect(sdk.outcome.source.tier == 1)
    }

    @Test("unspecified CMake with an unbundled or unavailable AGP stays unknown", arguments: ["8.10.0", "99.0.0", "invalid", nil] as [String?])
    func unknownDefaultCMake(agp: String?) async throws {
        let scenario = try scenario(modelResponse: .ok(AndroidGradleModelProbe.marker + nativeModelJSON(agp: agp) + "\n"))
        try scenario.repo.directory("sdk/ndk/27.1.12297006")
        try scenario.repo.directory("sdk/cmake/3.22.1")

        let report = await DoctorEngine(checks: checks(scenario)).run(only: ["android.sdk"])
        let sdk = try #require(report.checks.first { $0.id == "android.sdk" })

        #expect(sdk.status == .unknown)
        #expect(sdk.outcome.reason?.contains("no bundled AGP-to-CMake row") == true)
        #expect(sdk.outcome.source.tier == 2)
    }

    @Test("a native build without CMake does not require the AGP default")
    func nativeBuildWithoutCMake() async throws {
        let model = nativeModelJSON(cmakeConfigured: false)
        let scenario = try scenario(modelResponse: .ok(AndroidGradleModelProbe.marker + model + "\n"))
        try scenario.repo.directory("sdk/ndk/27.1.12297006")

        let report = await DoctorEngine(checks: checks(scenario)).run(only: ["android.sdk"])
        let sdk = try #require(report.checks.first { $0.id == "android.sdk" })

        #expect(sdk.status == .pass)
        #expect(sdk.outcome.source.tier == 1)
    }

    @Test("an unreadable adb inventory is an error instead of an installed-AVD guess")
    func adbInventoryFailure() async throws {
        let scenario = try scenario(adbResponse: .failed(1, "adb server unavailable"))

        let report = await DoctorEngine(checks: checks(scenario)).run(only: ["android.avd"])
        let avd = try #require(report.checks.first { $0.id == "android.avd" })

        #expect(avd.status == .error)
        #expect(avd.outcome.observed?.contains("Could not inspect running Android emulators") == true)
    }

    @Test("multiple compatible installed AVDs warn until android.avd selects one")
    func avdAmbiguity() async throws {
        let scenario = try scenario(avdNames: ["Pixel_API_35", "Tablet_API_35"])

        let report = await DoctorEngine(checks: checks(scenario)).run(only: ["android.avd"])
        let avd = try #require(report.checks.first { $0.id == "android.avd" })

        #expect(avd.status == .warning)
        #expect(avd.outcome.required == "android.avd in mobile.yml")
        #expect(avd.outcome.observed?.contains("Tablet_API_35") == true)
    }
}

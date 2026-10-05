import Core
import Foundation

public func androidChecks(
    anchor: ProjectAnchor,
    config: ConfigContext,
    hostRunner: any ProcessRunner,
    projectRunner: any ProcessRunner,
    environment: AndroidEnvironment = AndroidEnvironment(),
    includeRuntimeSDKTools: Bool = true
) -> [any Check] {
    let context = AndroidDoctorContext(
        anchor: anchor,
        config: config,
        hostRunner: hostRunner,
        projectRunner: projectRunner,
        environment: environment
    )
    return [
        AndroidProjectCheck(context: context),
        AndroidGradleWrapperCheck(context: context),
        AndroidJDKCheck(context: context),
        AndroidTargetCheck(context: context),
        AndroidGradleCompatibilityCheck(context: context),
        AndroidSDKCheck(context: context, includeRuntimeTools: includeRuntimeSDKTools),
        AndroidAVDCheck(context: context),
        AndroidEmulatorAccelerationCheck(context: context),
    ]
}

private struct AndroidProjectCheck: Check {
    let id = "android.project"
    let category = "Android project"
    let title = "React Native Android project and exact framework inputs are present"
    let context: AndroidDoctorContext

    func run() async throws -> CheckOutcome {
        let anchor = context.anchor
        guard anchor.hasAndroidDirectory else {
            return .error(
                observed: "the React Native anchor has no android/ directory",
                required: "a checked-in React Native Android project",
                source: CheckSource(tier: 1, origin: "package.json + android/"),
                remediation: Remediation(
                    summary: "Use a React Native project with a native Android directory; Phase 4A does not generate one."
                )
            )
        }

        let reactNative = anchor.reactNativeVersion
        let gradlePlugin = context.gradlePluginVersion()
        if !anchor.hasNodeModules {
            let observed = [
                reactNative.map { "React Native \($0.described)" } ?? "React Native exact version unresolved",
                gradlePlugin.map { "RNGP \($0.value) from \($0.origin)" } ?? "RNGP exact version unresolved",
                "node_modules missing",
            ].joined(separator: ", ")
            guard reactNative != nil, gradlePlugin != nil else {
                return .error(
                    observed: observed,
                    required: "exact react-native and @react-native/gradle-plugin declarations",
                    source: CheckSource(tier: 1, origin: "package.json + lockfile + android/"),
                    remediation: Remediation(
                        summary: "Commit an exact lockfile for both framework inputs before materializing dependencies."
                    )
                )
            }
            return .warning(
                observed: observed,
                required: "locally materialized project dependencies before Gradle model evaluation",
                source: CheckSource(tier: 1, origin: "package.json + lockfile + android/"),
                remediation: Remediation(
                    summary: "Install exactly the dependencies declared by the lockfile, then re-run mobile doctor.",
                    command: anchor.installCommand
                )
            )
        }
        guard let reactNative else {
            return .error(
                observed: "React Native is installed but its exact version could not be resolved",
                required: "an exact react-native version from node_modules, lockfile, or an exact pin",
                source: CheckSource(tier: 1, origin: "react-native evidence chain"),
                remediation: Remediation(
                    summary: "Fix the installed dependency and lockfile disagreement, then re-run mobile doctor."
                )
            )
        }
        guard let gradlePlugin else {
            return .error(
                observed: "@react-native/gradle-plugin is not installed or exactly resolved",
                required: "an exact React Native Gradle Plugin version",
                source: CheckSource(tier: 1, origin: "@react-native/gradle-plugin evidence chain"),
                remediation: Remediation(
                    summary: "Align project dependencies with the lockfile; Phase 4A does not infer RNGP from the React Native version.",
                    command: anchor.installCommand
                )
            )
        }
        return .pass(
            observed: "React Native \(reactNative.value), RNGP \(gradlePlugin.value), android/ present",
            required: "exact React Native and RNGP inputs",
            source: CheckSource(
                tier: 1,
                origin: "\(reactNative.described); \(gradlePlugin.origin); android/"
            )
        )
    }
}

private struct AndroidGradleWrapperCheck: Check {
    let id = "android.gradle.wrapper"
    let category = "Gradle"
    let title = "Gradle wrapper is complete, exact, and locally materialized"
    let context: AndroidDoctorContext

    func run() async throws -> CheckOutcome {
        switch context.wrapper() {
        case .failure(let failure):
            return .error(
                observed: failure.description,
                required: "executable gradlew, wrapper JAR/properties, and an exact distributionUrl",
                source: CheckSource(tier: 1, origin: "android/gradle/wrapper"),
                remediation: Remediation(
                    summary: "Restore the project's Gradle wrapper from its source repository; mobile will not substitute system Gradle."
                )
            )
        case .success(let wrapper) where !wrapper.materialized:
            return .warning(
                observed: "Gradle \(wrapper.versionText) is pinned but absent from the local wrapper cache",
                required: "the declared distribution available locally for an offline model query",
                source: wrapper.source,
                remediation: Remediation(
                    summary: "Materialize the declared wrapper distribution explicitly, then re-run mobile doctor. mobile will not download it.",
                    command: "cd \(shellQuote(context.androidDirectory.path)) && ./gradlew --version"
                )
            )
        case .success(let wrapper):
            return .pass(
                observed: "Gradle \(wrapper.versionText), local \(wrapper.distributionName)",
                required: "exact, locally available wrapper distribution",
                source: wrapper.source
            )
        }
    }
}

private struct AndroidJDKCheck: Check {
    let id = "android.jdk"
    let category = "JDK"
    let title = "Gradle client and selected daemon JDKs are observable"
    let dependsOn = ["android.gradle.wrapper", ProjectExecutionEnvironment.checkID]
    let context: AndroidDoctorContext

    func run() async throws -> CheckOutcome {
        let client: AndroidJavaObservation
        switch try await context.java() {
        case .failure(let failure):
            return .error(
                observed: failure.description,
                required: "a usable JDK in the activated project environment",
                source: CheckSource(tier: 1, origin: "project execution environment java"),
                remediation: Remediation(
                    summary: "Activate a locally installed JDK compatible with this project; mobile will not install one.",
                    url: "https://developer.android.com/build/jdks"
                )
            )
        case .success(let observation): client = observation
        }

        let daemonRequirement = context.daemonJDKRequirement()
        switch try await context.model() {
        case .model(let model):
            guard let daemon = SemanticVersion(java: model.daemonJavaVersion) else {
                return .unknown(
                    reason: "the evaluated Gradle daemon reported an unreadable JDK version",
                    source: CheckSource(tier: 1, origin: daemonRequirement.origin)
                )
            }
            if let required = daemonRequirement.version, daemon.major != required {
                return .error(
                    observed: "daemon JDK \(model.daemonJavaVersion)",
                    required: "JDK \(required) selected by \(daemonRequirement.origin)",
                    source: CheckSource(tier: 1, origin: daemonRequirement.origin),
                    remediation: Remediation(
                        summary: "Make the locally installed daemon JDK satisfy the committed Gradle criteria; mobile will not provision it.",
                        url: "https://docs.gradle.org/current/userguide/gradle_daemon.html"
                    )
                )
            }
            if let requiredVendor = daemonRequirement.vendor {
                guard let observedVendor = model.daemonJavaVendor else {
                    return .unknown(
                        reason: "Gradle did not report the daemon JDK vendor required by \(daemonRequirement.origin)",
                        source: CheckSource(tier: 1, origin: daemonRequirement.origin)
                    )
                }
                guard let matches = daemonVendorMatches(required: requiredVendor, observed: observedVendor) else {
                    return .unknown(
                        reason: "daemon vendor criterion \(requiredVendor) cannot be compared safely with \(observedVendor)",
                        source: CheckSource(tier: 1, origin: daemonRequirement.origin)
                    )
                }
                if !matches {
                    return .error(
                        observed: "daemon JDK vendor \(observedVendor)",
                        required: "\(requiredVendor) selected by \(daemonRequirement.origin)",
                        source: CheckSource(tier: 1, origin: daemonRequirement.origin),
                        remediation: Remediation(
                            summary: "Select a locally installed daemon JDK matching the committed Gradle vendor criteria."
                        )
                    )
                }
            }
            if let requiredHome = daemonRequirement.home {
                guard let observedHome = model.daemonJavaHome else {
                    return .unknown(
                        reason: "Gradle did not report the daemon JDK home selected by \(daemonRequirement.origin)",
                        source: CheckSource(tier: 1, origin: daemonRequirement.origin)
                    )
                }
                if URL(fileURLWithPath: requiredHome).standardizedFileURL.resolvingSymlinksInPath().path
                    != URL(fileURLWithPath: observedHome).standardizedFileURL.resolvingSymlinksInPath().path
                {
                    return .error(
                        observed: "the daemon used a JDK other than \(daemonRequirement.origin)",
                        required: "the JDK selected by org.gradle.java.home",
                        source: CheckSource(tier: 1, origin: daemonRequirement.origin),
                        remediation: Remediation(summary: "Fix org.gradle.java.home or the selected local JDK, then re-run mobile doctor.")
                    )
                }
            }
            let toolchains = Set(model.modules.compactMap(\.toolchainJavaVersion)).sorted()
            let toolchainMajors = toolchains.compactMap {
                $0.split(separator: ".").first.flatMap { Int($0) }
            }
            guard toolchainMajors.count == toolchains.count else {
                return .unknown(
                    reason: "the evaluated compiler toolchain JDK version is unreadable",
                    source: CheckSource(tier: 1, origin: "evaluated Gradle model")
                )
            }
            let unobservedToolchains = toolchainMajors.filter { $0 != daemon.major }
            if !unobservedToolchains.isEmpty {
                return .unknown(
                    reason: "compiler toolchain JDK \(unobservedToolchains.map(String.init).joined(separator: ",")) "
                        + "is declared but was not independently selected by this model-only diagnostic",
                    observed: "daemon JDK \(model.daemonJavaVersion)",
                    source: CheckSource(tier: 1, origin: "evaluated Gradle model")
                )
            }
            let toolchainText = toolchains.isEmpty ? "" : "; compiler toolchain JDK \(toolchains.joined(separator: ","))"
            return .pass(
                observed: "client JDK \(client.versionText); daemon JDK \(model.daemonJavaVersion)"
                    + (model.daemonJavaVendor.map { " (\($0))" } ?? "") + toolchainText,
                required: "separately observable Gradle client and daemon JDK selections",
                source: CheckSource(
                    tier: 1,
                    origin: "project execution environment; \(daemonRequirement.origin); evaluated Gradle model"
                )
            )
        case .unavailable(let reason):
            return .unknown(
                reason: "client JDK \(client.versionText) is usable, but the offline Gradle model cannot select a daemon yet — \(reason)",
                observed: "client JDK \(client.versionText)",
                source: CheckSource(tier: 1, origin: "project execution environment; Gradle model unavailable")
            )
        case .failure(let reason):
            return .unknown(
                reason: "client JDK \(client.versionText) is usable, but Gradle did not expose the selected daemon JDK — \(reason)",
                observed: "client JDK \(client.versionText)",
                source: CheckSource(tier: 1, origin: "project execution environment; Gradle model failed")
            )
        }
    }
}

enum AndroidTargetResolution {
    case selected(AndroidGradleModel.Module, AndroidGradleModel.Module.Variant, CheckSource)
    case warning(observed: String, required: String, remediation: Remediation, source: CheckSource)
    case error(observed: String, required: String, remediation: Remediation, source: CheckSource)
}

enum AndroidTargetSelector {
    static func resolve(
        model: AndroidGradleModel,
        configuration: MobileConfig?,
        configFile: String
    ) -> AndroidTargetResolution {
        let moduleSelector = configuration?.androidModule.map(normalizeModule)
        let source = CheckSource(
            tier: moduleSelector == nil && configuration?.androidVariant == nil ? 1 : 3,
            origin: [
                "evaluated Gradle model",
                moduleSelector.map { "mobile.yml android.module=\($0)" },
                configuration?.androidVariant.map { "mobile.yml android.variant=\($0)" },
            ].compactMap { $0 }.joined(separator: "; ")
        )

        let module: AndroidGradleModel.Module
        if let moduleSelector {
            guard let selected = model.modules.first(where: { normalizeModule($0.path) == moduleSelector }) else {
                return .error(
                    observed: "android.module names \(moduleSelector), available application modules: \(names(model.modules.map(\.path)))",
                    required: "an evaluated com.android.application module",
                    remediation: Remediation(summary: "Choose one of the evaluated modules in \(configFile)."),
                    source: source
                )
            }
            module = selected
        } else if model.modules.count == 1, let only = model.modules.first {
            module = only
        } else if model.modules.isEmpty {
            return .error(
                observed: "the evaluated Gradle build has no com.android.application module",
                required: "one runnable Android application module",
                remediation: Remediation(summary: "Apply com.android.application to the app module; mobile does not infer one from filenames."),
                source: source
            )
        } else {
            return .warning(
                observed: "multiple application modules: \(names(model.modules.map(\.path)))",
                required: "android.module in mobile.yml",
                remediation: Remediation(summary: "Set android.module in \(configFile) to one evaluated module."),
                source: source
            )
        }

        let runnable = module.variants.filter {
            $0.debuggable && $0.assembleTask != nil && $0.installTask != nil
        }
        let variant: AndroidGradleModel.Module.Variant
        if let selector = configuration?.androidVariant {
            guard let selected = runnable.first(where: { $0.name == selector }) else {
                return .error(
                    observed: "android.variant names \(selector), runnable debuggable variants: \(names(runnable.map(\.name)))",
                    required: "an evaluated debuggable variant with assemble/install tasks",
                    remediation: Remediation(summary: "Choose one of the evaluated variants in \(configFile)."),
                    source: source
                )
            }
            variant = selected
        } else if let debug = runnable.first(where: { $0.name == "debug" }) {
            // RN's default mode. Flavor names such as stagingDebug stay ambiguous.
            variant = debug
        } else if runnable.count == 1, let only = runnable.first {
            variant = only
        } else if runnable.isEmpty {
            return .error(
                observed: "\(module.path) has no debuggable variant with assemble/install tasks",
                required: "one runnable debuggable Android variant",
                remediation: Remediation(summary: "Fix the Gradle variant configuration; mobile does not synthesize a debug task."),
                source: source
            )
        } else {
            return .warning(
                observed: "multiple runnable variants in \(module.path): \(names(runnable.map(\.name)))",
                required: "android.variant in mobile.yml",
                remediation: Remediation(summary: "Set android.variant in \(configFile) to one evaluated debuggable variant."),
                source: source
            )
        }
        return .selected(module, variant, source)
    }

    private static func normalizeModule(_ value: String) -> String {
        value.hasPrefix(":") ? value : ":\(value)"
    }

    private static func names(_ values: [String]) -> String {
        values.isEmpty ? "none" : values.sorted().joined(separator: ", ")
    }
}

private struct AndroidTargetCheck: Check {
    let id = "android.target"
    let category = "Android target"
    let title = "One application module and runnable debuggable variant are selected"
    let dependsOn = ["android.gradle.wrapper"]
    let context: AndroidDoctorContext

    func run() async throws -> CheckOutcome {
        if case .invalid = context.config.parse {
            return .unknown(
                reason: "mobile.yml did not parse, so Android selectors were not applied — see config.syntax",
                source: CheckSource(tier: 3, origin: MobileConfig.fileName)
            )
        }
        let model: AndroidGradleModel
        switch try await context.model() {
        case .unavailable(let reason):
            return .warning(
                observed: "the offline Gradle model is not locally materialized — \(reason)",
                required: "an offline evaluated application model",
                source: CheckSource(tier: 1, origin: "./gradlew --offline help + mobile init script"),
                remediation: Remediation(
                    summary: "Materialize the project's declared Gradle inputs explicitly, then re-run mobile doctor.",
                    command: "cd \(shellQuote(context.androidDirectory.path)) && ./gradlew help"
                )
            )
        case .failure(let reason):
            return .error(
                observed: reason,
                required: "a Gradle build that can be evaluated offline without running build tasks",
                source: CheckSource(tier: 1, origin: "./gradlew --offline help + mobile init script"),
                remediation: Remediation(
                    summary: "Fix the Gradle configuration, then repeat the same side-effect-free model query.",
                    command: "cd \(shellQuote(context.androidDirectory.path)) && ./gradlew --offline --no-daemon help"
                )
            )
        case .model(let value): model = value
        }

        let file = context.config.display(anchorConfigFile(context.anchor))
        switch AndroidTargetSelector.resolve(
            model: model, configuration: context.config.configuration, configFile: file
        ) {
        case .selected(let module, let variant, let source):
            return .pass(
                observed: "\(module.path) \(variant.name) — \(variant.assembleTask ?? "assemble task unavailable"), "
                    + "\(variant.installTask ?? "install task unavailable")",
                required: "one evaluated application module and runnable debuggable variant",
                source: source
            )
        case .warning(let observed, let required, let remediation, let source):
            return .warning(observed: observed, required: required, source: source, remediation: remediation)
        case .error(let observed, let required, let remediation, let source):
            return .error(observed: observed, required: required, source: source, remediation: remediation)
        }
    }
}

private struct AndroidGradleCompatibilityCheck: Check {
    let id = "android.gradle.compatibility"
    let category = "Android compatibility"
    let title = "Gradle, AGP, daemon JDK, and compileSdk form an official tuple"
    let dependsOn = ["android.jdk", "android.target"]
    let context: AndroidDoctorContext

    func run() async throws -> CheckOutcome {
        guard case .success(let wrapper) = context.wrapper(),
            case .model(let model) = try await context.model(),
            case .selected(let module, let variant, _) = AndroidTargetSelector.resolve(
                model: model,
                configuration: context.config.configuration,
                configFile: context.config.display(anchorConfigFile(context.anchor))
            )
        else {
            return .unknown(reason: "the evaluated Android tuple is unavailable", source: AndroidCompatibility.source)
        }
        let compileSDK = variant.compileSdk ?? module.compileSdk
        let result = AndroidCompatibility.evaluate(
            wrapper: wrapper,
            model: model,
            module: module,
            compileSDK: compileSDK
        )
        let observed = "Gradle \(model.gradleVersion), AGP \(module.agpVersion ?? "unknown"), "
            + "daemon JDK \(model.daemonJavaVersion), compileSdk \(compileSDK ?? "unknown")"
        let required = result.required.isEmpty ? nil : result.required.joined(separator: "; ")
        if !result.violations.isEmpty {
            return .error(
                observed: result.violations.joined(separator: "; "),
                required: required,
                source: AndroidCompatibility.source,
                remediation: Remediation(
                    summary: "Align the project's declared wrapper, AGP, JDK, and compileSdk tuple; mobile.yml cannot override it.",
                    url: "https://developer.android.com/build/releases/about-agp"
                )
            )
        }
        if !result.unknown.isEmpty {
            return .unknown(
                reason: result.unknown.joined(separator: "; "),
                observed: observed,
                required: required,
                source: AndroidCompatibility.source
            )
        }
        return .pass(observed: observed, required: required, source: AndroidCompatibility.source)
    }
}

private struct AndroidSDKCheck: Check {
    let id = "android.sdk"
    let category = "Android SDK"
    let title = "The selected SDK root contains every package this variant requires"
    let context: AndroidDoctorContext
    let includeRuntimeTools: Bool

    func run() async throws -> CheckOutcome {
        let (sdk, rootSource): (URL, CheckSource)
        switch context.sdkRoot() {
        case .conflict(let message), .missing(let message):
            return .error(
                observed: message,
                required: "one unambiguous Android SDK root",
                source: CheckSource(tier: 1, origin: "android/local.properties + ANDROID_HOME"),
                remediation: Remediation(
                    summary: "Make android/local.properties sdk.dir and ANDROID_HOME name the same installed SDK."
                )
            )
        case .resolved(let url, let source): (sdk, rootSource) = (url, source)
        }
        guard case .model(let model) = try await context.model(),
            case .selected(let module, let variant, _) = AndroidTargetSelector.resolve(
                model: model,
                configuration: context.config.configuration,
                configFile: context.config.display(anchorConfigFile(context.anchor))
            )
        else {
            return .unknown(reason: "the selected Gradle target is unavailable", source: rootSource)
        }
        guard let compileSDK = variant.compileSdk ?? module.compileSdk,
            let buildTools = module.buildToolsVersion
        else {
            return .unknown(
                reason: "the evaluated application module did not expose compileSdk and effective Build Tools",
                source: CheckSource(tier: 1, origin: "evaluated Gradle model")
            )
        }
        if module.nativeBuildConfigured, module.ndkVersion == nil {
            return .unknown(
                reason: "the evaluated native build does not expose an exact NDK version",
                source: CheckSource(tier: 1, origin: "evaluated Gradle model")
            )
        }
        if module.cmakeConfigured == true, module.cmakeVersion == nil {
            return .unknown(
                reason: "the evaluated CMake build does not expose an exact CMake version",
                source: CheckSource(tier: 1, origin: "evaluated Gradle model")
            )
        }

        let manager = FileManager.default
        var missing: [(label: String, package: String)] = []
        func require(_ relative: String, _ label: String, _ package: String, executable: Bool = false) {
            let path = sdk.appendingPathComponent(relative).path
            let exists = executable ? manager.isExecutableFile(atPath: path) : manager.fileExists(atPath: path)
            if !exists { missing.append((label, package)) }
        }
        require("platforms/android-\(compileSDK)/android.jar", "SDK Platform android-\(compileSDK)", "platforms;android-\(compileSDK)")
        require("build-tools/\(buildTools)/aapt2", "Build Tools \(buildTools)", "build-tools;\(buildTools)", executable: true)
        if includeRuntimeTools {
            require("platform-tools/adb", "Platform-Tools/adb", "platform-tools", executable: true)
            require("emulator/emulator", "Android Emulator", "emulator", executable: true)
        }
        if module.nativeBuildConfigured, let ndk = module.ndkVersion {
            require("ndk/\(ndk)", "NDK \(ndk)", "ndk;\(ndk)")
        }
        if module.nativeBuildConfigured, let cmake = module.cmakeVersion {
            require("cmake/\(cmake)", "CMake \(cmake)", "cmake;\(cmake)")
        }

        let source = CheckSource(
            tier: 1,
            origin: "evaluated Gradle model; \(rootSource.origin)"
        )
        guard missing.isEmpty else {
            let packages = Array(Set(missing.map(\.package))).sorted()
            let sdkmanager = findSDKManager(in: sdk)
            return .error(
                observed: "missing \(missing.map(\.label).joined(separator: ", "))",
                required: "all SDK packages required by \(module.path)",
                source: source,
                remediation: Remediation(
                    summary: "Install the missing SDK packages explicitly; mobile will not download or license them.",
                    command: sdkmanager.map {
                        ([shellQuote($0.path)] + packages.map(shellQuote)).joined(separator: " ")
                    },
                    url: sdkmanager == nil ? "https://developer.android.com/tools/sdkmanager" : nil
                )
            )
        }
        return .pass(
            observed: "android-\(compileSDK), Build Tools \(buildTools)"
                + (includeRuntimeTools ? ", adb, Emulator" : "")
                + (module.nativeBuildConfigured ? ", declared native tools" : ""),
            required: "variant SDK inventory",
            source: source
        )
    }
}

private struct AndroidAVDCheck: Check {
    let id = "android.avd"
    let category = "Android Emulator"
    let title = "One compatible existing AVD can be selected before build"
    let dependsOn = ["android.target", "android.sdk"]
    let context: AndroidDoctorContext

    func run() async throws -> CheckOutcome {
        guard case .resolved(let sdk, let rootSource) = context.sdkRoot(),
            case .model(let model) = try await context.model(),
            case .selected(let module, let variant, _) = AndroidTargetSelector.resolve(
                model: model,
                configuration: context.config.configuration,
                configFile: context.config.display(anchorConfigFile(context.anchor))
            ),
            let minSDKText = variant.minSdk ?? module.minSdk, let minSDK = Int(minSDKText)
        else {
            return .unknown(
                reason: "the selected target did not expose an exact minSdk for pre-build AVD selection",
                source: CheckSource(tier: 1, origin: "evaluated Gradle model")
            )
        }
        let abiFilters = variant.abiFilters.flatMap { $0.isEmpty ? nil : $0 } ?? module.abiFilters
        guard !abiFilters.isEmpty else {
            return .unknown(
                reason: "the evaluated variant exposes no pre-build ABI evidence; the APK will be authoritative after build",
                observed: "minSdk \(minSDK), ABI unresolved",
                source: CheckSource(tier: 1, origin: "evaluated Gradle model")
            )
        }

        let list = try await context.hostRunner.run(
            context.toolCommand("emulator", ["-list-avds"], sdk: sdk)
        )
        guard list.terminationStatus.isSuccess else {
            return .error(
                observed: list.combinedOutput.lastLines(8),
                required: "readable existing AVD inventory",
                source: rootSource,
                remediation: Remediation(summary: "Fix the installed Emulator package, then run emulator -list-avds.", command: "emulator -list-avds")
            )
        }
        let names = list.standardOutput.split(separator: "\n").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        let avds = context.avds(names: names, sdk: sdk)
        let compatible = avds.filter { avd in
            guard let api = avd.apiLevel, api >= minSDK, avd.config != nil,
                avd.systemImagePresent
            else { return false }
            return avd.abi.map(abiFilters.contains) == true
        }
        let source = CheckSource(
            tier: context.config.configuration?.androidAVD == nil ? 1 : 3,
            origin: "emulator -list-avds + AVD config.ini"
                + (context.config.configuration?.androidAVD.map { "; mobile.yml android.avd=\($0)" } ?? "")
        )
        guard !compatible.isEmpty else {
            return .error(
                observed: "no existing AVD satisfies minSdk \(minSDK)"
                    + " and ABI \(abiFilters.joined(separator: ","))",
                required: "an existing compatible AVD; Phase 4A does not create one",
                source: source,
                remediation: Remediation(
                    summary: "Create or install a compatible AVD explicitly, then re-run mobile doctor.",
                    command: "emulator -list-avds"
                )
            )
        }

        if let declared = context.config.configuration?.androidAVD {
            guard let selected = compatible.first(where: { $0.name == declared }) else {
                return .error(
                    observed: "android.avd names \(declared), compatible AVDs: \(compatible.map(\.name).sorted().joined(separator: ", "))",
                    required: "a compatible AVD selector",
                    source: source,
                    remediation: Remediation(summary: "Set android.avd to one compatible existing AVD in mobile.yml.")
                )
            }
            return .pass(
                observed: "\(selected.name) — API \(selected.apiLevel.map(String.init) ?? "unknown"), "
                    + "ABI \(selected.abi ?? "unspecified")",
                required: "selected AVD compatible with minSdk \(minSDK)",
                source: source
            )
        }

        let running = try await runningAVDNames(sdk: sdk)
        let runningCompatible = compatible.filter { running.contains($0.name) }
        if runningCompatible.count == 1, let selected = runningCompatible.first {
            return .pass(
                observed: "running \(selected.name) — API \(selected.apiLevel.map(String.init) ?? "unknown"), "
                    + "ABI \(selected.abi ?? "unspecified")",
                required: "one compatible running or installed AVD",
                source: source
            )
        }
        let candidates = runningCompatible.isEmpty ? compatible : runningCompatible
        guard candidates.count == 1, let selected = candidates.first else {
            return .warning(
                observed: "multiple compatible \(runningCompatible.isEmpty ? "installed" : "running") AVDs: "
                    + candidates.map(\.name).sorted().joined(separator: ", "),
                required: "android.avd in mobile.yml",
                source: source,
                remediation: Remediation(summary: "Set android.avd to one compatible AVD in mobile.yml.")
            )
        }
        return .pass(
            observed: "\(selected.name) — API \(selected.apiLevel.map(String.init) ?? "unknown"), "
                + "ABI \(selected.abi ?? "unspecified")",
            required: "one compatible existing AVD",
            source: source
        )
    }

    private func runningAVDNames(sdk: URL) async throws -> Set<String> {
        let devices = try await context.hostRunner.run(
            context.toolCommand("adb", ["devices"], sdk: sdk)
        )
        guard devices.terminationStatus.isSuccess else {
            throw DomainError(
                summary: "Could not inspect running Android emulators",
                observed: devices.combinedOutput.lastLines(8),
                remediation: Remediation(
                    summary: "Fix adb before selecting an installed AVD; mobile will not guess around an unreadable running device.",
                    command: "adb devices"
                )
            )
        }
        let serials = devices.standardOutput.split(separator: "\n").compactMap { line -> String? in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2, fields[0].hasPrefix("emulator-"), fields[1] == "device" else { return nil }
            return String(fields[0])
        }
        var names = Set<String>()
        for serial in serials {
            let result = try await context.hostRunner.run(
                context.toolCommand("adb", ["-s", serial, "emu", "avd", "name"], sdk: sdk)
            )
            guard result.terminationStatus.isSuccess,
                let name = androidAVDName(from: result.standardOutput),
                !name.isEmpty
            else {
                throw DomainError(
                    summary: "Could not identify running emulator \(serial)",
                    observed: result.combinedOutput.lastLines(8),
                    remediation: Remediation(
                        summary: "Restore adb emulator identity before choosing another AVD.",
                        command: "adb -s \(serial) emu avd name"
                    )
                )
            }
            names.insert(name)
        }
        return names
    }
}

private struct AndroidEmulatorAccelerationCheck: Check {
    let id = "android.emulator.acceleration"
    let category = "Android Emulator"
    let title = "Emulator acceleration is observable"
    let dependsOn = ["android.sdk"]
    let context: AndroidDoctorContext

    func run() async throws -> CheckOutcome {
        guard case .resolved(let sdk, let source) = context.sdkRoot() else {
            return .unknown(reason: "the Android SDK root is unavailable")
        }
        let result = try await context.hostRunner.run(
            context.toolCommand("emulator", ["-accel-check"], sdk: sdk)
        )
        let observed = result.combinedOutput.lastLines(5)
        if result.terminationStatus.isSuccess {
            guard !observed.isEmpty else {
                return .unknown(reason: "emulator -accel-check returned no result", source: source)
            }
            return .pass(observed: observed, source: source)
        }
        return .warning(
            observed: observed.isEmpty ? "hardware acceleration is unavailable" : observed,
            required: "acceleration when available; absence is not a compatibility failure",
            source: source,
            remediation: Remediation(
                summary: "Review the host hypervisor setup if emulator performance is unusable.",
                url: "https://developer.android.com/studio/run/emulator-acceleration"
            )
        )
    }
}

private func anchorConfigFile(_ anchor: ProjectAnchor) -> URL {
    anchor.directory.appendingPathComponent(MobileConfig.fileName)
}

private func findSDKManager(in sdk: URL) -> URL? {
    let root = sdk.appendingPathComponent("cmdline-tools")
    guard let versions = try? FileManager.default.contentsOfDirectory(
        at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
    ) else { return nil }
    return versions.sorted { $0.lastPathComponent > $1.lastPathComponent }
        .map { $0.appendingPathComponent("bin/sdkmanager") }
        .first { FileManager.default.isExecutableFile(atPath: $0.path) }
}

private func daemonVendorMatches(required: String, observed: String) -> Bool? {
    func normalized(_ value: String) -> String {
        value.lowercased().filter(\.isLetter)
    }
    let required = normalized(required)
    let observed = normalized(observed)
    let known: [String: [String]] = [
        "adoptopenjdk": ["adoptopenjdk"],
        "adoptium": ["adoptium"],
        "amazon": ["amazon"],
        "apple": ["apple"],
        "azul": ["azul"],
        "bellsoft": ["bellsoft"],
        "ibm": ["ibm"],
        "ibmsemeru": ["semeru"],
        "jetbrains": ["jetbrains"],
        "microsoft": ["microsoft"],
        "oracle": ["oracle"],
        "sap": ["sap"],
        "tencent": ["tencent"],
    ]
    guard let tokens = known[required] else { return nil }
    return tokens.contains { observed.contains($0) }
}

private func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

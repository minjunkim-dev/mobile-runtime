import Core
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public enum AndroidWorkflowValidation {
    public static let checkIDs: Set<String> = [
        "config.syntax",
        "project.execution-environment",
        "node.version",
        "package-manager.version",
        "android.project",
        "android.gradle.wrapper",
        "android.jdk",
        "android.target",
        "android.gradle.compatibility",
        "android.sdk",
    ]
}

public enum AndroidUpValidation {
    public static let checkIDs = AndroidWorkflowValidation.checkIDs.union(["android.avd"])
}

/// The complete Phase 4A Android build pipeline. It deliberately ends at an APK:
/// Emulator selection, install, Metro and launch belong to the later `up` stages.
public func androidBuildStages(
    anchor: ProjectAnchor,
    doctor: DoctorEngine,
    config: ConfigContext,
    hostRunner: any ProcessRunner,
    projectRunner: any ProcessRunner,
    environment: AndroidEnvironment = AndroidEnvironment(),
    validationCheckIDs: Set<String> = AndroidWorkflowValidation.checkIDs,
    note: @escaping @Sendable (String) -> Void
) -> [any Stage] {
    [
        ValidateStage(engine: doctor, checkIDs: validationCheckIDs),
        DependenciesStage(anchor: anchor, runner: projectRunner, includePods: false),
        AndroidBuildStage(
            anchor: anchor,
            config: config,
            hostRunner: hostRunner,
            projectRunner: projectRunner,
            environment: environment,
            note: note
        ),
    ]
}

public struct AndroidBuildStage: Stage {
    public let id = "android.build"

    private let anchor: ProjectAnchor
    private let config: ConfigContext
    private let hostRunner: any ProcessRunner
    private let projectRunner: any ProcessRunner
    private let environment: AndroidEnvironment
    private let logs: RunLogs
    private let note: @Sendable (String) -> Void

    public init(
        anchor: ProjectAnchor,
        config: ConfigContext,
        hostRunner: any ProcessRunner,
        projectRunner: any ProcessRunner,
        environment: AndroidEnvironment = AndroidEnvironment(),
        logs: RunLogs? = nil,
        note: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.anchor = anchor
        self.config = config
        self.hostRunner = hostRunner
        self.projectRunner = projectRunner
        self.environment = environment
        self.logs = logs ?? RunLogs(project: anchor.directory)
        self.note = note
    }

    public func run(_ pipeline: inout UpContext) async throws -> StageOutcome {
        let context = AndroidDoctorContext(
            anchor: anchor,
            config: config,
            hostRunner: hostRunner,
            projectRunner: projectRunner,
            environment: environment
        )
        let model: AndroidGradleModel
        switch try await context.buildModel() {
        case .model(let value): model = value
        case .unavailable(let reason), .failure(let reason):
            throw DomainError(
                summary: "the Android Gradle model could not be evaluated",
                observed: reason,
                remediation: Remediation(
                    summary: "Fix or materialize the declared Gradle inputs, then run the same wrapper model query.",
                    command: "cd \(shell(anchor.directory.appendingPathComponent("android").path)) && ./gradlew help"
                )
            )
        }

        let module: AndroidGradleModel.Module
        let variant: AndroidGradleModel.Module.Variant
        switch AndroidTargetSelector.resolve(
            model: model,
            configuration: config.configuration,
            configFile: config.display(anchor.directory.appendingPathComponent(MobileConfig.fileName))
        ) {
        case .selected(let selectedModule, let selectedVariant, _):
            (module, variant) = (selectedModule, selectedVariant)
        case .warning(let observed, _, let remediation, _),
            .error(let observed, _, let remediation, _):
            throw DomainError(summary: observed, remediation: remediation)
        }

        guard let assembleTask = variant.assembleTask,
            let applicationId = variant.applicationId,
            let minSdk = variant.minSdk ?? module.minSdk,
            let targetSdk = variant.targetSdk ?? module.targetSdk,
            let buildTools = module.buildToolsVersion,
            let apkDirectory = variant.apkDirectory,
            let mergedManifest = variant.mergedManifest
        else {
            throw DomainError(
                summary: "the selected Android variant did not expose complete build metadata",
                remediation: Remediation(
                    summary: "Fix the evaluated application variant so it exposes its task, metadata and public AGP artifacts."
                )
            )
        }

        let sdk: URL
        switch context.sdkRoot() {
        case .resolved(let value, _): sdk = value
        case .conflict(let reason), .missing(let reason):
            throw DomainError(
                summary: reason,
                remediation: Remediation(
                    summary: "Make android/local.properties sdk.dir and ANDROID_HOME name one installed SDK."
                )
            )
        }
        let aapt2 = sdk.appendingPathComponent("build-tools/\(buildTools)/aapt2")
        guard FileManager.default.isExecutableFile(atPath: aapt2.path) else {
            throw DomainError(
                summary: "Build Tools \(buildTools) is missing aapt2",
                remediation: Remediation(
                    summary: "Install build-tools;\(buildTools) explicitly; mobile will not download or license it."
                )
            )
        }

        let log = logs.url("android-build.log")
        pipeline.buildLog = log.path
        let command = ProcessCommand(
            "./gradlew",
            [
                assembleTask,
                "--no-daemon",
                "--console=plain",
                "-Porg.gradle.java.installations.auto-download=false",
            ],
            workingDirectory: anchor.directory.appendingPathComponent("android"),
            timeout: nil,
            output: .streamed(to: log)
        )
        note("android.build running… — \(assembleTask)")
        let excerpt = LineExcerpt(limit: 10) { line in
            line.hasPrefix("FAILURE:") || line.hasPrefix("* What went wrong:")
                || line.localizedCaseInsensitiveContains("error:")
        }
        let built = try await projectRunner.run(command, onLine: { excerpt.append($0) })
        guard built.terminationStatus.isSuccess else {
            throw DomainError(
                summary: "the Android build failed",
                observed: excerpt.text,
                remediation: Remediation(
                    summary: "The whole Gradle log is at \(log.path).",
                    command: pasteable(command)
                )
            )
        }

        let apkOutput = try singleAPK(
            variant: variant.name,
            directory: URL(fileURLWithPath: apkDirectory)
        )
        guard apkOutput.element.type == "SINGLE",
            apkOutput.element.filters?.isEmpty != false,
            apkOutput.file.pathExtension == "apk"
        else {
            throw unsupportedOutput("the selected variant produced a split or non-APK output")
        }
        guard FileManager.default.fileExists(atPath: apkOutput.file.path) else {
            throw unsupportedOutput("Gradle named an APK that does not exist")
        }
        guard apkOutput.metadata.applicationId == applicationId else {
            throw mismatch(
                "applicationId",
                expected: applicationId,
                actual: apkOutput.metadata.applicationId ?? "missing"
            )
        }

        let manifest = try MergedManifest.read(URL(fileURLWithPath: mergedManifest))
        let aapt = try await inspectAPK(
            apkOutput.file,
            context: context,
            sdk: sdk,
            buildTools: buildTools
        )

        try require("applicationId", applicationId, aapt.applicationId)
        try require("minSdk", minSdk, manifest.minSdk)
        try require("minSdk", minSdk, aapt.minSdk)
        try require("targetSdk", targetSdk, manifest.targetSdk)
        try require("targetSdk", targetSdk, aapt.targetSdk)

        let declaredABIs = Set(variant.abiFilters ?? module.abiFilters)
        guard !aapt.abis.isEmpty else {
            throw unsupportedOutput("the APK exposes no native ABI metadata")
        }
        if !declaredABIs.isEmpty, declaredABIs != Set(aapt.abis) {
            throw mismatch(
                "native ABI",
                expected: declaredABIs.sorted().joined(separator: ","),
                actual: aapt.abis.joined(separator: ",")
            )
        }

        let launcher = try selectedLauncher(from: manifest)
        try require("launcher activity", launcher, aapt.launcherActivity)

        pipeline.androidProduct = AndroidBuiltProduct(
            apkPath: apkOutput.file.path,
            module: module.path,
            variant: variant.name,
            assembleTask: assembleTask,
            applicationId: applicationId,
            minSdk: minSdk,
            targetSdk: targetSdk,
            abis: aapt.abis,
            launcherActivity: launcher
        )
        return .pass("\(module.path) \(variant.name)")
    }

    private func inspectAPK(
        _ apk: URL,
        context: AndroidDoctorContext,
        sdk: URL,
        buildTools: String
    ) async throws -> APKBadging {
        let command = context.toolCommand(
            "aapt2", ["dump", "badging", apk.path], sdk: sdk, buildToolsVersion: buildTools
        )
        let result = try await hostRunner.run(command)
        guard result.terminationStatus.isSuccess else {
            throw unsupportedOutput(
                result.combinedOutput.lastLines(8).isEmpty
                    ? "aapt2 could not inspect the APK"
                    : result.combinedOutput.lastLines(8)
            )
        }
        return try APKBadging.read(result.standardOutput)
    }

    private func selectedLauncher(from manifest: MergedManifest) throws -> String {
        let candidates = manifest.launcherActivities.sorted()
        if let declared = config.configuration?.androidLauncherActivity {
            let normalized = manifest.qualified(declared)
            guard candidates.contains(normalized) else {
                throw DomainError(
                    summary: "android.launcherActivity names \(declared), merged manifest launchers: \(names(candidates))",
                    remediation: Remediation(
                        summary: "Set android.launcherActivity to one merged-manifest launcher in mobile.yml."
                    )
                )
            }
            return normalized
        }
        guard candidates.count == 1, let launcher = candidates.first else {
            throw DomainError(
                summary: candidates.isEmpty
                    ? "the merged manifest has no launcher activity"
                    : "multiple merged-manifest launcher activities: \(names(candidates))",
                remediation: Remediation(
                    summary: candidates.isEmpty
                        ? "Declare one MAIN/LAUNCHER activity in the Android manifest."
                        : "Set android.launcherActivity to one merged-manifest launcher in mobile.yml."
                )
            )
        }
        return launcher
    }

    private func require(_ field: String, _ expected: String, _ actual: String?) throws {
        guard actual == expected else {
            throw mismatch(field, expected: expected, actual: actual ?? "missing")
        }
    }

    private func mismatch(_ field: String, expected: String, actual: String) -> DomainError {
        DomainError(
            summary: "the APK \(field) does not match the evaluated variant",
            observed: "expected \(expected), APK reports \(actual)",
            remediation: Remediation(
                summary: "Fix the Gradle variant or manifest; mobile will not silently accept stale or mismatched output."
            )
        )
    }

    private func unsupportedOutput(_ observed: String) -> DomainError {
        DomainError(
            summary: "the Android build did not produce one installable APK",
            observed: observed,
            remediation: Remediation(
                summary: "Phase 4A supports one universal APK only; disable splits or choose a supported debug variant."
            )
        )
    }
}

private struct GradleOutputMetadata: Decodable {
    struct Element: Decodable {
        struct Filter: Decodable {}
        let type: String
        let filters: [Filter]?
        let outputFile: String
    }

    let applicationId: String?
    let variantName: String
    let elements: [Element]
}

private struct GradleOutput {
    let metadata: GradleOutputMetadata
    let element: GradleOutputMetadata.Element
    let file: URL
}

private func singleAPK(variant: String, directory: URL) throws -> GradleOutput {
    let metadataFile = directory.appendingPathComponent("output-metadata.json")
    guard let data = FileManager.default.contents(atPath: metadataFile.path),
        let metadata = try? JSONDecoder().decode(GradleOutputMetadata.self, from: data),
        metadata.variantName == variant
    else {
        throw outputFailure("the public APK artifact has no readable metadata for \(variant)")
    }
    guard metadata.elements.count == 1, let element = metadata.elements.first else {
        throw outputFailure("APK metadata for \(variant) names \(metadata.elements.count) outputs")
    }
    return GradleOutput(
        metadata: metadata,
        element: element,
        file: directory.appendingPathComponent(element.outputFile)
    )
}

private func outputFailure(_ observed: String) -> DomainError {
    DomainError(
        summary: "the selected Android variant has ambiguous or missing output metadata",
        observed: observed,
        remediation: Remediation(
            summary: "Fix the selected Gradle variant output; mobile does not guess among artifacts."
        )
    )
}

private struct APKBadging {
    let applicationId: String
    let minSdk: String
    let targetSdk: String
    let abis: [String]
    let launcherActivity: String

    static func read(_ text: String) throws -> APKBadging {
        guard let applicationId = capture(#"(?m)^package: name='([^']+)'"#, in: text),
            let minSdk = capture(#"(?m)^sdkVersion:'([^']+)'"#, in: text),
            let targetSdk = capture(#"(?m)^targetSdkVersion:'([^']+)'"#, in: text),
            let launcher = capture(#"(?m)^launchable-activity: name='([^']+)'"#, in: text)
        else {
            throw outputFailure("aapt2 did not report applicationId, SDK levels and one launcher activity")
        }
        let nativeLine = capture(#"(?m)^native-code: (.+)$"#, in: text) ?? ""
        return APKBadging(
            applicationId: applicationId,
            minSdk: minSdk,
            targetSdk: targetSdk,
            abis: captures(#"'([^']+)'"#, in: nativeLine).sorted(),
            launcherActivity: launcher
        )
    }
}

private final class MergedManifest: NSObject, XMLParserDelegate {
    private struct Component {
        let name: String
        var main = false
        var launcher = false
    }

    private(set) var packageName: String?
    private(set) var minSdk: String?
    private(set) var targetSdk: String?
    private(set) var launcherActivities: [String] = []
    private var component: Component?

    static func read(_ file: URL) throws -> MergedManifest {
        guard let data = FileManager.default.contents(atPath: file.path) else {
            throw outputFailure("the merged manifest output does not exist")
        }
        let manifest = MergedManifest()
        let parser = XMLParser(data: data)
        parser.delegate = manifest
        guard parser.parse(), manifest.packageName != nil else {
            throw outputFailure("the merged manifest could not be parsed")
        }
        return manifest
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "manifest": packageName = attributeDict["package"]
        case "uses-sdk":
            minSdk = android("minSdkVersion", in: attributeDict)
            targetSdk = android("targetSdkVersion", in: attributeDict)
        case "activity", "activity-alias":
            if let name = android("name", in: attributeDict) { component = Component(name: name) }
        case "action":
            if android("name", in: attributeDict) == "android.intent.action.MAIN" { component?.main = true }
        case "category":
            if android("name", in: attributeDict) == "android.intent.category.LAUNCHER" {
                component?.launcher = true
            }
        default: break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName == "activity" || elementName == "activity-alias", let component else {
            return
        }
        if component.main && component.launcher { launcherActivities.append(qualified(component.name)) }
        self.component = nil
    }

    func qualified(_ name: String) -> String {
        guard let packageName else { return name }
        if name.hasPrefix(".") { return packageName + name }
        if !name.contains(".") { return packageName + "." + name }
        return name
    }

    private func android(_ name: String, in attributes: [String: String]) -> String? {
        attributes["android:\(name)"]
            ?? attributes.first { $0.key.hasSuffix(":\(name)") }?.value
    }
}

private func capture(_ pattern: String, in text: String) -> String? {
    captures(pattern, in: text).first
}

private func captures(_ pattern: String, in text: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
        Range($0.range(at: 1), in: text).map { String(text[$0]) }
    }
}

private func names(_ values: [String]) -> String {
    values.isEmpty ? "none" : values.joined(separator: ", ")
}

private func shell(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

private func pasteable(_ command: ProcessCommand) -> String {
    "cd \(shell(command.workingDirectory?.path ?? ".")) && "
        + ([command.executable] + command.arguments).map(shell).joined(separator: " ")
}

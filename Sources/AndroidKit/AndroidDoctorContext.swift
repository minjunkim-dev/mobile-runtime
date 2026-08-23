import Core
import Foundation

public struct AndroidEnvironment: Sendable {
    public let values: [String: String]

    public init(values: [String: String] = ProcessInfo.processInfo.environment) {
        self.values = values
    }

    var home: URL? { values["HOME"].map(URL.init(fileURLWithPath:)) }
    var gradleHome: URL? {
        values["GRADLE_USER_HOME"].map(URL.init(fileURLWithPath:))
            ?? home?.appendingPathComponent(".gradle")
    }
    var avdHome: URL? {
        values["ANDROID_AVD_HOME"].map(URL.init(fileURLWithPath:))
            ?? values["ANDROID_USER_HOME"].map { URL(fileURLWithPath: $0).appendingPathComponent("avd") }
            ?? home?.appendingPathComponent(".android/avd")
    }
}

struct AndroidPackageVersion: Sendable, Equatable {
    let value: String
    let origin: String
}

struct AndroidGradleWrapper: Sendable, Equatable {
    let version: SemanticVersion
    let versionText: String
    let distributionURL: String
    let distributionName: String
    let source: CheckSource
    let materialized: Bool
}

struct AndroidGradleModel: Sendable, Decodable, Equatable {
    struct Module: Sendable, Decodable, Equatable {
        struct Variant: Sendable, Decodable, Equatable {
            let name: String
            let debuggable: Bool
            let assembleTask: String?
            let installTask: String?
            let compileSdk: String?
            let minSdk: String?
            let targetSdk: String?
            let applicationId: String?
            let abiFilters: [String]?
        }

        let path: String
        let agpVersion: String?
        let compileSdk: String?
        let buildToolsVersion: String?
        let minSdk: String?
        let targetSdk: String?
        let ndkVersion: String?
        let cmakeVersion: String?
        let nativeBuildConfigured: Bool
        let cmakeConfigured: Bool?
        let ndkBuildConfigured: Bool?
        let toolchainJavaVersion: String?
        let sourceCompatibility: String?
        let targetCompatibility: String?
        let abiFilters: [String]
        let variants: [Variant]
    }

    let gradleVersion: String
    let daemonJavaVersion: String
    let daemonJavaVendor: String?
    let daemonJavaHome: String?
    let modules: [Module]
}

enum AndroidModelProbeOutcome: Sendable, Equatable {
    case model(AndroidGradleModel)
    case unavailable(String)
    case failure(String)
}

struct AndroidJavaObservation: Sendable, Equatable {
    let version: SemanticVersion
    let versionText: String
    let vendor: String?
    let home: String?
}

struct AndroidDaemonJDKRequirement: Sendable, Equatable {
    let version: Int?
    let vendor: String?
    let home: String?
    let origin: String
}

struct AndroidObservationFailure: Error, Sendable, Equatable, CustomStringConvertible {
    let description: String

    init(_ description: String) { self.description = description }
}

enum AndroidSDKRootResolution: Sendable, Equatable {
    case resolved(URL, source: CheckSource)
    case conflict(String)
    case missing(String)
}

struct AndroidAVD: Sendable, Equatable {
    let name: String
    let apiLevel: Int?
    let abi: String?
    let config: URL?
    let systemImagePresent: Bool
}

actor AndroidDoctorContext {
    nonisolated let anchor: ProjectAnchor
    nonisolated let config: ConfigContext
    nonisolated let hostRunner: any ProcessRunner
    nonisolated let projectRunner: any ProcessRunner
    nonisolated let environment: AndroidEnvironment

    private var modelTask: Task<AndroidModelProbeOutcome, any Error>?

    init(
        anchor: ProjectAnchor,
        config: ConfigContext,
        hostRunner: any ProcessRunner,
        projectRunner: any ProcessRunner,
        environment: AndroidEnvironment
    ) {
        self.anchor = anchor
        self.config = config
        self.hostRunner = hostRunner
        self.projectRunner = projectRunner
        self.environment = environment
    }

    nonisolated var androidDirectory: URL { anchor.directory.appendingPathComponent("android") }

    nonisolated func gradlePluginVersion() -> AndroidPackageVersion? {
        Self.packageVersion("@react-native/gradle-plugin", anchor: anchor)
    }

    nonisolated func wrapper() -> Result<AndroidGradleWrapper, AndroidObservationFailure> {
        let directory = androidDirectory
        let script = directory.appendingPathComponent("gradlew")
        let jar = directory.appendingPathComponent("gradle/wrapper/gradle-wrapper.jar")
        let properties = directory.appendingPathComponent("gradle/wrapper/gradle-wrapper.properties")
        let manager = FileManager.default

        var missing: [String] = []
        if !manager.isExecutableFile(atPath: script.path) { missing.append("executable android/gradlew") }
        if (try? jar.resourceValues(forKeys: [.fileSizeKey]).fileSize).map({ $0 > 0 }) != true {
            missing.append("android/gradle/wrapper/gradle-wrapper.jar")
        }
        guard let data = manager.contents(atPath: properties.path) else {
            missing.append("android/gradle/wrapper/gradle-wrapper.properties")
            return .failure(AndroidObservationFailure("missing \(missing.joined(separator: ", "))"))
        }
        guard missing.isEmpty else {
            return .failure(AndroidObservationFailure("missing \(missing.joined(separator: ", "))"))
        }

        let values = Self.properties(String(decoding: data, as: UTF8.self))
        guard let rawURL = values["distributionUrl"] else {
            return .failure(AndroidObservationFailure("gradle-wrapper.properties has no distributionUrl"))
        }
        let distributionURL = rawURL
            .replacingOccurrences(of: "\\:", with: ":")
            .replacingOccurrences(of: "\\=", with: "=")
        let filename = URL(string: distributionURL)?.lastPathComponent
            ?? distributionURL.split(separator: "/").last.map(String.init)
            ?? ""
        let pattern = #"^gradle-([0-9]+(?:\.[0-9]+){1,2}(?:-[A-Za-z0-9.-]+)?)-(bin|all)\.zip$"#
        guard let match = filename.firstMatch(pattern), let version = SemanticVersion(match[1]) else {
            return .failure(
                AndroidObservationFailure(
                    "distributionUrl does not pin an exact Gradle distribution: \(distributionURL)"
                )
            )
        }

        let base: URL?
        switch values["distributionBase"] ?? "GRADLE_USER_HOME" {
        case "GRADLE_USER_HOME": base = environment.gradleHome
        case "PROJECT": base = directory
        case let value: return .failure(AndroidObservationFailure("unsupported distributionBase \(value)"))
        }
        let path = values["distributionPath"] ?? "wrapper/dists"
        let distributionName = String(filename.dropLast(4))
        let root = base?.appendingPathComponent(path).appendingPathComponent(distributionName)
        let materialized = root.map {
            Self.containsGradle(
                version: match[1],
                distributionName: distributionName,
                below: $0,
                fileManager: manager
            )
        } ?? false

        return .success(
            AndroidGradleWrapper(
                version: version,
                versionText: match[1],
                distributionURL: distributionURL,
                distributionName: distributionName,
                source: CheckSource(tier: 1, origin: "android/gradle/wrapper/gradle-wrapper.properties"),
                materialized: materialized
            )
        )
    }

    nonisolated func daemonJDKRequirement() -> AndroidDaemonJDKRequirement {
        let criteria = androidDirectory.appendingPathComponent("gradle/gradle-daemon-jvm.properties")
        if let data = FileManager.default.contents(atPath: criteria.path) {
            let values = Self.properties(String(decoding: data, as: UTF8.self))
            return AndroidDaemonJDKRequirement(
                version: values["toolchainVersion"].flatMap(Int.init),
                vendor: values["toolchainVendor"],
                home: nil,
                origin: "android/gradle/gradle-daemon-jvm.properties"
            )
        }
        for (file, origin) in [
            (androidDirectory.appendingPathComponent("gradle.properties"), "android/gradle.properties"),
            (environment.gradleHome?.appendingPathComponent("gradle.properties"), "GRADLE_USER_HOME/gradle.properties"),
        ] {
            guard let file, let data = FileManager.default.contents(atPath: file.path),
                let home = Self.properties(String(decoding: data, as: UTF8.self))["org.gradle.java.home"]
            else { continue }
            return AndroidDaemonJDKRequirement(
                version: nil,
                vendor: nil,
                home: Self.unescapeProperty(home),
                origin: "\(origin) org.gradle.java.home"
            )
        }
        return AndroidDaemonJDKRequirement(
            version: nil,
            vendor: nil,
            home: nil,
            origin: "activated JAVA_HOME/PATH"
        )
    }

    func java() async throws -> Result<AndroidJavaObservation, AndroidObservationFailure> {
        let command = ProcessCommand(
            "java", ["-XshowSettings:properties", "-version"],
            workingDirectory: androidDirectory, timeout: .seconds(15)
        )
        let result = try await projectRunner.run(command)
        guard result.terminationStatus.isSuccess else {
            let detail = result.combinedOutput.lastLines(8)
            return .failure(AndroidObservationFailure(detail.isEmpty ? "java exited unsuccessfully" : detail))
        }
        let output = result.combinedOutput
        let versionText = Self.property(named: "java.version", in: output)
            ?? output.firstMatch(#"(?:java|openjdk) version \"([^\"]+)\""#)?[1]
        guard let versionText, let version = SemanticVersion(versionText) else {
            return .failure(AndroidObservationFailure("java did not report a parseable version"))
        }
        return .success(
            AndroidJavaObservation(
                version: version,
                versionText: versionText,
                vendor: Self.property(named: "java.vendor", in: output),
                home: Self.property(named: "java.home", in: output)
            )
        )
    }

    func model() async throws -> AndroidModelProbeOutcome {
        if let modelTask { return try await modelTask.value }
        let directory = androidDirectory
        let runner = projectRunner
        let task = Task<AndroidModelProbeOutcome, any Error> {
            guard let command = AndroidGradleModelProbe.command(androidDirectory: directory) else {
                return .failure("mobile's bundled Android model script is unavailable")
            }
            let result = try await runner.run(command)
            let output = result.combinedOutput
            guard result.terminationStatus.isSuccess else {
                let detail = output.lastLines(12)
                let missing = [
                    "offline mode", "no cached version", "could not resolve", "not available for offline",
                    "could not find", "plugin was not found",
                ].contains { output.localizedCaseInsensitiveContains($0) }
                return missing
                    ? .unavailable(detail.isEmpty ? "Gradle inputs are not materialized locally" : detail)
                    : .failure(detail.isEmpty ? "Gradle model query failed" : detail)
            }
            guard let marker = output.split(separator: "\n").last(where: {
                $0.hasPrefix(AndroidGradleModelProbe.marker)
            }) else {
                return .failure("Gradle completed without returning the Android model")
            }
            let json = marker.dropFirst(AndroidGradleModelProbe.marker.count)
            do {
                return .model(try JSONDecoder().decode(AndroidGradleModel.self, from: Data(json.utf8)))
            } catch {
                return .failure("Gradle returned an unreadable Android model: \(error)")
            }
        }
        modelTask = task
        return try await task.value
    }

    nonisolated func sdkRoot() -> AndroidSDKRootResolution {
        let local = androidDirectory.appendingPathComponent("local.properties")
        let localPath: String? = FileManager.default.contents(atPath: local.path).flatMap { data in
            Self.properties(String(decoding: data, as: UTF8.self))["sdk.dir"]
        }.map(Self.unescapeProperty)
        let homePath = environment.values["ANDROID_HOME"]
        let deprecatedPath = environment.values["ANDROID_SDK_ROOT"]

        func normalized(_ path: String) -> URL {
            URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        }
        if let localPath, let homePath, normalized(localPath).path != normalized(homePath).path {
            return .conflict("android/local.properties sdk.dir and ANDROID_HOME point to different SDK roots")
        }
        if let homePath, let deprecatedPath, normalized(homePath).path != normalized(deprecatedPath).path {
            return .conflict("ANDROID_SDK_ROOT disagrees with ANDROID_HOME")
        }
        if deprecatedPath != nil, homePath == nil, localPath == nil {
            return .missing("ANDROID_SDK_ROOT is deprecated and is not promoted to the SDK root")
        }
        if let localPath {
            return .resolved(normalized(localPath), source: CheckSource(tier: 1, origin: "android/local.properties sdk.dir"))
        }
        if let homePath {
            return .resolved(normalized(homePath), source: CheckSource(tier: 1, origin: "ANDROID_HOME"))
        }
        return .missing("neither android/local.properties sdk.dir nor ANDROID_HOME declares the SDK root")
    }

    nonisolated func toolCommand(
        _ executable: String,
        _ arguments: [String],
        sdk: URL,
        timeout: Duration = .seconds(15)
    ) -> ProcessCommand {
        let inherited = environment.values["PATH"] ?? ""
        let path = [
            sdk.appendingPathComponent("platform-tools").path,
            sdk.appendingPathComponent("emulator").path,
            inherited,
        ].filter { !$0.isEmpty }.joined(separator: ":")
        return ProcessCommand(
            executable, arguments, environment: ["PATH": path], timeout: timeout
        )
    }

    nonisolated func avds(names: [String], sdk: URL) -> [AndroidAVD] {
        guard let avdHome = environment.avdHome else {
            return names.map {
                AndroidAVD(name: $0, apiLevel: nil, abi: nil, config: nil, systemImagePresent: false)
            }
        }
        return names.map { name in
            let pointer = avdHome.appendingPathComponent("\(name).ini")
            let pointerValues = FileManager.default.contents(atPath: pointer.path).map {
                Self.properties(String(decoding: $0, as: UTF8.self))
            } ?? [:]
            let directory = pointerValues["path"].map(URL.init(fileURLWithPath:))
                ?? avdHome.appendingPathComponent("\(name).avd")
            let config = directory.appendingPathComponent("config.ini")
            let values = FileManager.default.contents(atPath: config.path).map {
                Self.properties(String(decoding: $0, as: UTF8.self))
            } ?? [:]
            let image = values["image.sysdir.1"] ?? ""
            let imageDirectory = image.hasPrefix("/")
                ? URL(fileURLWithPath: image)
                : sdk.appendingPathComponent(image)
            let api = image.firstMatch(#"android-([0-9]+)"#).flatMap { Int($0[1]) }
                ?? values["target"].flatMap { $0.firstMatch(#"android-([0-9]+)"#) }.flatMap { Int($0[1]) }
            let abi = values["abi.type"] ?? image.firstMatch(#"/(arm64-v8a|x86_64|x86|armeabi-v7a)/?"#)?[1]
            return AndroidAVD(
                name: name,
                apiLevel: api,
                abi: abi,
                config: FileManager.default.fileExists(atPath: config.path) ? config : nil,
                systemImagePresent: !image.isEmpty
                    && FileManager.default.fileExists(atPath: imageDirectory.path)
            )
        }
    }

    private static func packageVersion(_ package: String, anchor: ProjectAnchor) -> AndroidPackageVersion? {
        let installed = anchor.directory.appendingPathComponent("node_modules/\(package)/package.json")
        let measured: AndroidPackageVersion? = FileManager.default.contents(atPath: installed.path).flatMap { data in
            ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["version"] as? String
        }.flatMap { SemanticVersion($0) == nil ? nil : AndroidPackageVersion(value: $0, origin: "node_modules/\(package)") }

        let locked: AndroidPackageVersion? = anchor.workspaceRoot.flatMap { workspace in
            let lock = workspace.directory.appendingPathComponent(workspace.lockfile)
            guard let data = FileManager.default.contents(atPath: lock.path) else { return nil }
            let text = String(decoding: data, as: UTF8.self)
            switch workspace.lockfile {
            case "package-lock.json":
                guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                    let packages = json["packages"] as? [String: Any]
                else { return nil }
                let relative = anchor.directory.path.replacingOccurrences(of: workspace.directory.path + "/", with: "")
                let candidates = [
                    "\(relative)/node_modules/\(package)",
                    "node_modules/\(package)",
                ]
                for key in candidates {
                    if let version = (packages[key] as? [String: Any])?["version"] as? String,
                        SemanticVersion(version) != nil
                    {
                        return AndroidPackageVersion(value: version, origin: workspace.lockfile)
                    }
                }
                return nil
            case "yarn.lock", "pnpm-lock.yaml":
                let escaped = NSRegularExpression.escapedPattern(for: package)
                let patterns = [
                    "\(escaped)@(?:npm:)?([0-9]+\\.[0-9]+\\.[0-9]+)",
                    "\"?\(escaped)\"?[^\\n]*\\n\\s+version[: ]+\"?([0-9]+\\.[0-9]+\\.[0-9]+)",
                ]
                for pattern in patterns {
                    if let match = text.firstMatch(pattern) {
                        return AndroidPackageVersion(value: match[1], origin: workspace.lockfile)
                    }
                }
                return nil
            default: return nil
            }
        }

        if let measured {
            guard let locked, locked.value != measured.value else { return measured }
            return AndroidPackageVersion(
                value: measured.value,
                origin: "\(measured.origin) — but \(locked.origin) resolves \(locked.value)"
            )
        }
        if let locked { return locked }

        let manifest = anchor.directory.appendingPathComponent("package.json")
        guard let data = FileManager.default.contents(atPath: manifest.path),
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        for field in ["dependencies", "devDependencies"] {
            if let value = (json[field] as? [String: Any])?[package] as? String,
                SemanticVersion(value) != nil
            {
                return AndroidPackageVersion(value: value, origin: "package.json \(field).\(package)")
            }
        }
        return nil
    }

    private static func properties(_ text: String) -> [String: String] {
        text.split(separator: "\n").reduce(into: [:]) { values, raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("!"),
                let separator = line.firstIndex(where: { $0 == "=" || $0 == ":" })
            else { return }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            values[key] = value
        }
    }

    private static func unescapeProperty(_ value: String) -> String {
        value.replacingOccurrences(of: "\\ ", with: " ")
            .replacingOccurrences(of: "\\:", with: ":")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func containsGradle(
        version: String,
        distributionName: String,
        below root: URL,
        fileManager: FileManager
    ) -> Bool {
        guard let hashes = try? fileManager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return false }
        return hashes.contains { hash in
            fileManager.fileExists(
                atPath: hash.appendingPathComponent("\(distributionName).zip.ok").path
            ) && fileManager.isExecutableFile(
                atPath: hash.appendingPathComponent("gradle-\(version)/bin/gradle").path
            )
        }
    }

    private static func property(named name: String, in output: String) -> String? {
        output.split(separator: "\n").compactMap { line -> String? in
            let parts = line.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            return parts.count == 2 && parts[0] == name ? parts[1] : nil
        }.first
    }
}

enum AndroidGradleModelProbe {
    static let marker = "MOBILE_ANDROID_MODEL="

    static func command(androidDirectory: URL) -> ProcessCommand? {
        guard let script = Bundle.module.url(forResource: "mobile-doctor", withExtension: "gradle") else {
            return nil
        }
        return ProcessCommand(
            "./gradlew",
            [
                "--offline", "--no-daemon", "--no-configuration-cache", "--console=plain",
                "--warning-mode=none", "-Porg.gradle.java.installations.auto-download=false",
                "-q", "-I", script.path, "help",
            ],
            workingDirectory: androidDirectory,
            timeout: .seconds(90)
        )
    }
}

private extension String {
    func firstMatch(_ pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self))
        else { return nil }
        return (0..<match.numberOfRanges).compactMap { index in
            Range(match.range(at: index), in: self).map { String(self[$0]) }
        }
    }
}

import Core
import CryptoKit
import Foundation

public struct AndroidAVDRequest: Codable, Sendable, Equatable {
    public let name: String
    public let sdkRoot: URL
    public let avdHome: URL
    public let imagePackage: String
    public let imageRevision: String
    public let imageMetadataSHA256: String
    public let deviceProfile: String
    public let profileSHA256: String
    public let avdManager: URL
    public let avdManagerRevision: String
    public let emulatorRevision: String
    public let repositorySHA256: String
    public var directory: URL { avdHome.appendingPathComponent("\(name).avd", isDirectory: true) }
    public var pointer: URL { avdHome.appendingPathComponent("\(name).ini") }
    public var imageDirectory: URL { sdkRoot.appendingPathComponent(imagePackage.replacingOccurrences(of: ";", with: "/")) }

    public init(name: String, sdkRoot: URL, avdHome: URL, imagePackage: String, imageRevision: String,
                imageMetadataSHA256: String, deviceProfile: String, profileSHA256: String,
                avdManager: URL, avdManagerRevision: String, emulatorRevision: String, repositorySHA256: String) {
        self.name = name
        self.sdkRoot = URL(fileURLWithPath: sdkRoot.standardizedFileURL.resolvingSymlinksInPath().path, isDirectory: true)
        self.avdHome = URL(fileURLWithPath: avdHome.standardizedFileURL.resolvingSymlinksInPath().path, isDirectory: true)
        self.imagePackage = imagePackage; self.imageRevision = imageRevision; self.imageMetadataSHA256 = imageMetadataSHA256
        self.deviceProfile = deviceProfile; self.profileSHA256 = profileSHA256
        self.avdManager = avdManager.standardizedFileURL.resolvingSymlinksInPath(); self.avdManagerRevision = avdManagerRevision
        self.emulatorRevision = emulatorRevision; self.repositorySHA256 = repositorySHA256
    }
}

public struct AndroidPreparationResource: Codable, Sendable, Equatable {
    public enum Origin: String, Codable, Sendable { case created, reused, unknown }
    public let name: String
    public let directory: URL
    public let imageDirectory: URL
    public let imageRevision: String?
    public let abi: String?
    public let deviceProfile: String?
    public let state: String
    public let origin: Origin
    public let metadataSHA256: String?
}

/// Read-only provider projection. The private Gradle model and environment stay in AndroidKit.
public struct AndroidEmulatorEnvironment: Sendable {
    public let sdkRoot: URL
    public let avdHome: URL
    public let minSDK: Int
    public let abis: [String]
    public let declaredAVD: String?
    public let compatible: [AndroidPreparationResource]
    public let names: [String]
    public let running: Set<String>
    public let avdManager: URL?
    public let avdManagerRevision: String?
    public let source: CheckSource

    public static func inspect(context: AndroidDoctorContext) async throws -> Self {
        guard case .resolved(let sdk, _) = context.sdkRoot(), let home = context.environment.avdHome,
              case .model(let model) = try await context.model(),
              case .selected(let module, let variant, let source) = AndroidTargetSelector.resolve(model: model,
                configuration: context.config.configuration, configFile: context.anchor.directory.appendingPathComponent(MobileConfig.fileName).path),
              let text = variant.minSdk ?? module.minSdk, let minimum = Int(text), minimum > 0 else {
            throw failure("Exact SDK root, AVD home, selected Gradle target and minSdk are required before Emulator preparation.")
        }
        let abis = variant.abiFilters.flatMap { $0.isEmpty ? nil : $0 } ?? module.abiFilters
        guard !abis.isEmpty || context.anchor.framework == .nativeAndroid else {
            throw failure("The selected variant has no pre-build ABI evidence. Inspect the built APK before choosing a system image.")
        }
        var names: [String] = []
        if FileManager.default.isExecutableFile(atPath: sdk.appendingPathComponent("emulator/emulator").path) {
            let result = try await context.hostRunner.run(context.toolCommand("emulator", ["-list-avds"], sdk: sdk))
            guard result.terminationStatus.isSuccess else { throw failure("Existing AVD inventory could not be read. Preserve it and inspect the Emulator installation.") }
            names = result.standardOutput.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            guard Set(names).count == names.count, names.allSatisfy(safeName) else { throw failure("Existing AVD inventory contains ambiguous names.") }
        }
        let resources = context.avds(names: names, sdk: sdk).compactMap { avd -> AndroidPreparationResource? in
            guard let api = avd.apiLevel, api >= minimum, let abi = avd.abi,
                  abis.isEmpty || abis.contains(abi), let config = avd.config,
                  let image = avd.systemImageDirectory, avd.systemImagePresent,
                  FileManager.default.fileExists(atPath: image.appendingPathComponent("system.img").path),
                  AndroidSDKLicenses.check(packages: [image], sdk: sdk, command: nil) == nil,
                  let revision = revision(in: image), let data = bounded(config),
                  let imageDigest = imageDigest(in: image) else { return nil }
            let values = AndroidDoctorContext.properties(String(decoding: data, as: UTF8.self))
            guard let properties = bounded(image.appendingPathComponent("source.properties")) else { return nil }
            let imageValues = AndroidDoctorContext.properties(String(decoding: properties, as: UTF8.self))
            guard imageValues["AndroidVersion.ApiLevel"].flatMap(Int.init) == api, imageValues["SystemImage.Abi"] == abi else { return nil }
            return AndroidPreparationResource(name: avd.name, directory: config.deletingLastPathComponent(), imageDirectory: image,
                imageRevision: revision, abi: abi, deviceProfile: values["hw.device.name"], state: "available", origin: .reused,
                metadataSHA256: digest(data + Data(imageDigest.utf8)))
        }
        var running = Set<String>()
        if resources.count > 1, context.config.configuration?.androidAVD == nil {
            let devices = try await context.hostRunner.run(context.toolCommand("adb", ["devices"], sdk: sdk))
            guard devices.terminationStatus.isSuccess else { throw failure("Running Emulator identities could not be observed.") }
            for line in devices.standardOutput.split(whereSeparator: \.isNewline) {
                let parts = line.split(whereSeparator: \.isWhitespace)
                guard parts.count >= 2, parts[0].hasPrefix("emulator-"), parts[1] == "device" else { continue }
                let value = try await context.hostRunner.run(context.toolCommand("adb", ["-s", String(parts[0]), "emu", "avd", "name"], sdk: sdk))
                guard value.terminationStatus.isSuccess, let name = androidAVDName(from: value.standardOutput) else {
                    throw failure("A running Emulator's AVD identity is unknown. Preserve it and inspect again.")
                }
                running.insert(name)
            }
        }
        let tools = sdk.appendingPathComponent("cmdline-tools")
        let manager = (try? FileManager.default.contentsOfDirectory(at: tools, includingPropertiesForKeys: nil))?
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { $0.appendingPathComponent("bin/avdmanager") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path)
                && revision(in: $0.deletingLastPathComponent().deletingLastPathComponent()) != nil }
        return Self(sdkRoot: sdk, avdHome: home.standardizedFileURL.resolvingSymlinksInPath(), minSDK: minimum, abis: abis.sorted(),
            declaredAVD: context.config.configuration?.androidAVD, compatible: resources, names: names.sorted(), running: running,
            avdManager: manager, avdManagerRevision: manager.flatMap { revision(in: $0.deletingLastPathComponent().deletingLastPathComponent()) }, source: source)
    }

    public static func profile(_ id: String, runner: any ProcessRunner, manager: URL, environment: [String: String]) async throws -> String {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("runstir-android-profile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: scratch) }
        var isolated = environment
        // Inspect the same built-in profiles as creation, without user profile overrides.
        for (key, child) in [("ANDROID_USER_HOME", "user"), ("ANDROID_AVD_HOME", "avds"), ("ANDROID_EMULATOR_HOME", "emulator")] {
            let directory = scratch.appendingPathComponent(child)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            isolated[key] = directory.path
        }
        let result = try await runner.run(ProcessCommand(manager.path, ["list", "device"], environment: isolated, timeout: .seconds(30)))
        guard result.terminationStatus.isSuccess else { throw failure("Android device profiles could not be read.") }
        let pattern = #"(?m)^\s*id:\s*[0-9]+\s+or\s+""# + NSRegularExpression.escapedPattern(for: id) + #"""#
        let profiles = result.standardOutput.components(separatedBy: "---------").filter {
            $0.range(of: pattern, options: .regularExpression) != nil
        }
        guard profiles.count == 1 else { throw failure("The exact device profile \(id) is unavailable or ambiguous.") }
        return profiles[0].trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    public static func observe(_ request: AndroidAVDRequest, origin: AndroidPreparationResource.Origin) -> AndroidPreparationResource? {
        guard exists(request.directory) || exists(request.pointer) else { return nil }
        let config = request.directory.appendingPathComponent("config.ini")
        let data = bounded(config)
        let values = data.map { AndroidDoctorContext.properties(String(decoding: $0, as: UTF8.self)) } ?? [:]
        let pointer = bounded(request.pointer).map { AndroidDoctorContext.properties(String(decoding: $0, as: UTF8.self)) } ?? [:]
        let image = values["image.sysdir.1"].map { value in value.hasPrefix("/") ? URL(fileURLWithPath: value) : request.sdkRoot.appendingPathComponent(value) }
        let complete = pointer["path"] == request.directory.path && values["AvdId"] == request.name
            && values["abi.type"] == "arm64-v8a" && values["hw.device.name"] == request.deviceProfile
            && image?.standardizedFileURL.resolvingSymlinksInPath() == request.imageDirectory.standardizedFileURL.resolvingSymlinksInPath()
            && revision(in: request.imageDirectory) == request.imageRevision
        return AndroidPreparationResource(name: request.name, directory: request.directory, imageDirectory: request.imageDirectory,
            imageRevision: revision(in: request.imageDirectory), abi: values["abi.type"], deviceProfile: values["hw.device.name"],
            state: complete ? "available" : "incomplete", origin: complete ? origin : .unknown, metadataSHA256: data.map(digest))
    }

    public static func validateImage(_ request: AndroidAVDRequest) throws {
        let values = bounded(request.imageDirectory.appendingPathComponent("source.properties"))
            .map { AndroidDoctorContext.properties(String(decoding: $0, as: UTF8.self)) } ?? [:]
        let parts = request.imagePackage.components(separatedBy: ";")
        guard imageDigest(in: request.imageDirectory) == request.imageMetadataSHA256,
              parts.count == 4, values["AndroidVersion.ApiLevel"] == String(parts[1].dropFirst(8)),
              values["SystemImage.TagId"] == parts[2], values["SystemImage.Abi"] == parts[3],
              revision(in: request.imageDirectory) == request.imageRevision,
              FileManager.default.fileExists(atPath: request.imageDirectory.appendingPathComponent("system.img").path),
              AndroidSDKLicenses.check(packages: [request.imageDirectory, request.avdManager.deletingLastPathComponent().deletingLastPathComponent(),
                request.sdkRoot.appendingPathComponent("emulator")], sdk: request.sdkRoot, command: nil) == nil,
              revision(in: request.avdManager.deletingLastPathComponent().deletingLastPathComponent()) == request.avdManagerRevision,
              revision(in: request.sdkRoot.appendingPathComponent("emulator")) == request.emulatorRevision,
              FileManager.default.isExecutableFile(atPath: request.avdManager.path) else {
            throw failure("System image, license or AVD manager identity changed. Preserve resources and approve a new plan.")
        }
    }

    /// Exact validation candidates, never latest aliases or replacements for existing packages.
    public func sdkRequirements(includeImage: Bool, includeManager: Bool) -> AndroidSDKRequirements {
        var packages = [("platform-tools", "adb"), ("emulator", "emulator")]
        if includeManager {
            let version = avdManager?.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent ?? "23.0"
            packages.append(("cmdline-tools;\(version)", "bin/avdmanager"))
        }
        if includeImage { packages.append(("system-images;android-35;google_apis;arm64-v8a", "system.img")) }
        return AndroidSDKRequirements(sdkRoot: sdkRoot, packages: packages.map {
            AndroidSDKPackageRequirement(packagePath: $0.0, requiredFile: $0.1, executable: $0.1 != "system.img", source: source)
        }, modules: [], blockers: [])
    }

    public static func imageDigest(in directory: URL) -> String? {
        guard let properties = bounded(directory.appendingPathComponent("source.properties")),
              let metadata = bounded(directory.appendingPathComponent("package.xml")) else { return nil }
        return digest(properties + Data([0]) + metadata)
    }
    public static func revision(in directory: URL) -> String? {
        guard let data = bounded(directory.appendingPathComponent("source.properties")) else { return nil }
        return AndroidDoctorContext.properties(String(decoding: data, as: UTF8.self))["Pkg.Revision"].flatMap {
            $0.range(of: #"^[0-9]+(?:\.[0-9]+){0,2}$"#, options: .regularExpression) == nil ? nil : $0
        }
    }
    public static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    public static func safeName(_ name: String) -> Bool {
        name.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$"#, options: .regularExpression) != nil
    }
    public static func exists(_ file: URL) -> Bool { (try? FileManager.default.attributesOfItem(atPath: file.path)) != nil }
    private static func bounded(_ file: URL) -> Data? {
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 2 * 1024 * 1024 else { return nil }
        return try? Data(contentsOf: file)
    }
    private static func failure(_ message: String) -> DomainError {
        DomainError(summary: message, remediation: Remediation(summary: "Inspect the existing Android resources. Preserve them and re-plan; setup does not replace or delete them."))
    }
}

import Core
import CryptoKit
import Foundation
#if canImport(Darwin)
import Darwin
#endif

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
            guard let imageAPI = imageValues["AndroidVersion.ApiLevel"],
                  imageAPI.range(of: #"^[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil,
                  imageAPI.split(separator: ".").first.flatMap({ Int($0) }) == api,
                  imageValues["SystemImage.Abi"] == abi else { return nil }
            return AndroidPreparationResource(name: avd.name, directory: config.deletingLastPathComponent(), imageDirectory: image,
                imageRevision: revision, abi: abi, deviceProfile: values["hw.device.name"], state: "available", origin: .reused,
                metadataSHA256: digest(data + Data(imageDigest.utf8)))
        }
        var running = Set<String>()
        let platformTools = AndroidSDKPackageRequirement(packagePath: "platform-tools", requiredFile: "adb", executable: true, source: source)
        if resources.count > 1, context.config.configuration?.androidAVD == nil, platformTools.observation(in: sdk).ready {
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
            .map { tools.appendingPathComponent($0.lastPathComponent, isDirectory: true).appendingPathComponent("bin/avdmanager") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path)
                && revision(in: $0.deletingLastPathComponent().deletingLastPathComponent()) != nil }
        return Self(sdkRoot: sdk, avdHome: home.standardizedFileURL.resolvingSymlinksInPath(), minSDK: minimum, abis: abis.sorted(),
            declaredAVD: context.config.configuration?.androidAVD, compatible: resources, names: names.sorted(), running: running,
            avdManager: manager, avdManagerRevision: manager.flatMap { revision(in: $0.deletingLastPathComponent().deletingLastPathComponent()) }, source: source)
    }

    public static func profile(_ id: String, runner: any ProcessRunner, manager: URL, environment: [String: String]) async throws -> String {
        guard let sdk = environment["ANDROID_SDK_ROOT"], environment["ANDROID_HOME"] == sdk else {
            throw failure("An exact SDK root is required to inspect device profile payloads.")
        }
        let root = URL(fileURLWithPath: sdk, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        let payload = try await profilePayload(manager: manager, sdk: root, runner: runner)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("runstir-android-profile-\(UUID().uuidString)")
        var isolated = environment
        // Inspect the same built-in profiles as creation, without user profile overrides.
        for (key, child) in [("ANDROID_USER_HOME", "user"), ("ANDROID_AVD_HOME", "avds"), ("ANDROID_EMULATOR_HOME", "emulator")] {
            isolated[key] = scratch.appendingPathComponent(child).path
        }
        let command = try sdkReadOnlyCommand(ProcessCommand(manager.path, ["list", "device"], environment: isolated, timeout: .seconds(30)),
            sdk: root, writableDirectories: [scratch])
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: scratch) }
        for child in ["user", "avds", "emulator"] {
            try FileManager.default.createDirectory(at: scratch.appendingPathComponent(child), withIntermediateDirectories: false)
        }
        let result = try await runner.run(command)
        guard result.terminationStatus.isSuccess else { throw failure("Android device profiles could not be read.") }
        let pattern = #"(?m)^\s*id:\s*[0-9]+\s+or\s+""# + NSRegularExpression.escapedPattern(for: id) + #"""#
        let profiles = result.standardOutput.components(separatedBy: "---------").filter {
            $0.range(of: pattern, options: .regularExpression) != nil
        }
        guard profiles.count == 1 else { throw failure("The exact device profile \(id) is unavailable or ambiguous.") }
        guard try await profilePayload(manager: manager, sdk: root, runner: runner) == payload else {
            throw failure("Device profile tool or catalog payload changed during inspection. Approve a new plan.")
        }
        return profiles[0].trimmingCharacters(in: .whitespacesAndNewlines) + "\nPayload SHA-256: \(payload)\n"
    }

    /// Both AVD-manager operations may write only outside the selected SDK, including descendant JVMs.
    public static func sdkReadOnlyCommand(_ command: ProcessCommand, sdk: URL, writableDirectories: [URL]) throws -> ProcessCommand {
        let files = FileManager.default
        guard files.isExecutableFile(atPath: "/usr/bin/sandbox-exec"), command.executable.hasPrefix("/"), !writableDirectories.isEmpty else {
            throw failure("SDK write protection is unavailable. Prepare the Android resource manually; no unprotected command will run.")
        }
        var directory: ObjCBool = false
        guard files.fileExists(atPath: sdk.path, isDirectory: &directory), directory.boolValue else { throw failure("The selected SDK directory is unavailable.") }
        let protected = try protectionPath(sdk)
        let tool = try protectionPath(URL(fileURLWithPath: command.executable))
        let prefix = protected + "/"
        let parts = tool.hasPrefix(prefix) ? String(tool.dropFirst(prefix.count)).split(separator: "/") : []
        guard parts.count == 4, parts[0] == "cmdline-tools", parts[2] == "bin", parts[3] == "avdmanager",
              files.isExecutableFile(atPath: command.executable) else { throw failure("The AVD manager is outside the exact selected SDK tool boundary.") }
        let writable = try writableDirectories.map(protectionPath)
        func contains(_ parent: String, _ child: String) -> Bool { parent == child || child.hasPrefix(parent + "/") }
        guard writable.allSatisfy({ !contains(protected, $0) && !contains($0, protected) }) else {
            throw failure("SDK and owned AVD/temporary directories overlap. Select separate resources and re-plan.")
        }
        for key in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            if let path = command.environment[key] {
                guard path.hasPrefix("/"), try protectionPath(URL(fileURLWithPath: path)) == protected else {
                    throw failure("The child SDK environment differs from its protected SDK.")
                }
            }
        }
        for key in ["ANDROID_USER_HOME", "ANDROID_AVD_HOME", "ANDROID_EMULATOR_HOME"] {
            if let path = command.environment[key] {
                guard path.hasPrefix("/") else { throw failure("An Android child home is not absolute.") }
                let target = try protectionPath(URL(fileURLWithPath: path))
                guard writable.contains(where: { contains($0, target) }) else { throw failure("An Android child home is outside its owned writable directories.") }
            }
        }
        if case .streamed(let file) = command.output {
            let log = try protectionPath(file)
            guard !contains(protected, log), !contains(log, protected) else { throw failure("A child output file overlaps the protected SDK.") }
        }
        // SBPL is passed as one argv value, with Scheme string quoting rather than shell quoting.
        let escaped = protected.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let profile = "(version 1)(allow default)(deny file-write* (subpath \"\(escaped)\"))"
        var wrapped = command
        wrapped.executable = "/usr/bin/sandbox-exec"
        wrapped.arguments = ["-p", profile, command.executable] + command.arguments
        return wrapped
    }

    private static func protectionPath(_ url: URL) throws -> String {
        guard url.isFileURL, url.path.hasPrefix("/"), url.query == nil, url.fragment == nil,
              !url.path.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
              !url.path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else {
            throw failure("An Android protection path is not an unambiguous absolute file path.")
        }
        var ancestor = url
        var suffix: [String] = []
        while !exists(ancestor), ancestor.path != "/" { suffix.insert(ancestor.lastPathComponent, at: 0); ancestor.deleteLastPathComponent() }
        let standard = ancestor.standardizedFileURL
        guard standard.path == ancestor.resolvingSymlinksInPath().standardizedFileURL.path,
              (try? FileManager.default.attributesOfItem(atPath: ancestor.path)[.type] as? FileAttributeType) != .typeSymbolicLink else {
            throw failure("An Android protection path uses a symbolic alias. Preserve it and select a canonical resource.")
        }
        #if canImport(Darwin)
        guard let physical = realpath(ancestor.path, nil) else { throw failure("An Android protection path cannot be resolved safely.") }
        defer { free(physical) }
        return suffix.reduce(String(cString: physical)) { ($0 as NSString).appendingPathComponent($1) }
        #else
        throw failure("Android SDK write protection is unavailable on this host.")
        #endif
    }

    /// Hash only this tool's reachable JARs and the SDK inputs that can supply/override a device definition.
    private static func profilePayload(manager: URL, sdk: URL, runner: any ProcessRunner) async throws -> String {
        do {
            let tool = manager.deletingLastPathComponent().deletingLastPathComponent()
            let library = tool.appendingPathComponent("lib", isDirectory: true)
            guard tool.path.hasPrefix(sdk.path + "/cmdline-tools/"), manager.path == tool.appendingPathComponent("bin/avdmanager").path else {
                throw failure("The AVD manager layout is unknown.")
            }
            var records: [String] = []
            var bytes = 0
            func record(_ file: URL, limit: Int) throws {
                try Task.checkCancellation()
                let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                guard file.standardizedFileURL.resolvingSymlinksInPath().path == file.path,
                      file.path.hasPrefix(sdk.path + "/"), values.isRegularFile == true, values.isSymbolicLink != true,
                      let size = values.fileSize, size >= 0, size <= limit,
                      records.count < 512, bytes <= 256 * 1024 * 1024 - size else {
                    throw failure("Device profile payload exceeds its safe file, path or byte boundary.")
                }
                let handle = try FileHandle(forReadingFrom: file)
                defer { try? handle.close() }
                var hash = SHA256()
                var read = 0
                while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
                    try Task.checkCancellation()
                    read += data.count
                    guard read <= size else { throw failure("Device profile payload changed while reading.") }
                    hash.update(data: data)
                }
                guard read == size else { throw failure("Device profile payload changed while reading.") }
                bytes += size
                let name = String(file.path.dropFirst(sdk.path.count + 1))
                records.append(name + "\u{0}" + hash.finalize().map { String(format: "%02x", $0) }.joined())
            }
            try record(manager, limit: 2 * 1024 * 1024)
            var pending = [library.appendingPathComponent("avdmanager-classpath.jar")]
            var visited = Set<String>()
            while let jar = pending.popLast() {
                guard visited.insert(jar.path).inserted else { continue }
                guard visited.count <= 128 else { throw failure("The AVD manager classpath exceeds its file limit.") }
                guard jar.standardizedFileURL.resolvingSymlinksInPath().path == jar.path,
                      jar.path.hasPrefix(library.path + "/") else { throw failure("The AVD manager classpath leaves its tool library.") }
                if !exists(jar), jar != library.appendingPathComponent("avdmanager-classpath.jar") {
                    // Java ignores missing transitive references. Pin absence so adding one invalidates approval.
                    records.append(String(jar.path.dropFirst(sdk.path.count + 1)) + "\u{0}absent")
                    continue
                }
                try record(jar, limit: 64 * 1024 * 1024)
                let manifest = try await runner.run(ProcessCommand("/usr/bin/unzip", ["-p", jar.path, "META-INF/MANIFEST.MF"], timeout: .seconds(10)))
                guard manifest.terminationStatus.isSuccess || (manifest.terminationStatus == .exited(11) && manifest.standardOutput.isEmpty),
                      manifest.standardOutput.utf8.count <= 64 * 1024 else {
                    throw failure("The AVD manager JAR manifest is unavailable or exceeds its limit.")
                }
                var headers: [String] = []
                for line in manifest.standardOutput.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
                    if line.isEmpty { break }
                    if line.hasPrefix(" "), !headers.isEmpty { headers[headers.count - 1] += line.dropFirst() }
                    else {
                        guard line.contains(":"), !line.hasPrefix(" ") else { throw failure("The AVD manager manifest has an ambiguous header.") }
                        headers.append(line)
                    }
                }
                let paths = headers.filter { $0.lowercased().hasPrefix("class-path:") }
                let declared = manifest.standardOutput.components(separatedBy: .newlines).filter { $0.lowercased().hasPrefix("class-path:") }
                guard paths.count <= 1, declared.count == paths.count else { throw failure("The AVD manager manifest has duplicate or ambiguous classpaths.") }
                if jar == library.appendingPathComponent("avdmanager-classpath.jar"), paths.first?.dropFirst("Class-Path:".count).trimmingCharacters(in: .whitespaces).isEmpty != false {
                    throw failure("The AVD manager root classpath layout is unknown.")
                }
                for path in paths.first.map({ String($0.dropFirst("Class-Path:".count)) })?.split(whereSeparator: \.isWhitespace) ?? [] {
                    let value = String(path)
                    guard value.range(of: #"^[A-Za-z0-9_./-]+\.jar$"#, options: .regularExpression) != nil,
                          !value.hasPrefix("/"), value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
                        throw failure("The AVD manager classpath contains an unsupported relative path.")
                    }
                    let dependency = jar.deletingLastPathComponent().appendingPathComponent(value)
                    guard dependency.path.hasPrefix(library.path + "/") else { throw failure("The AVD manager classpath leaves its tool library.") }
                    pending.append(dependency)
                }
            }
            let files = FileManager.default
            var directories = 0
            func catalogs(_ directory: URL, depth: Int) throws {
                guard exists(directory) else { return }
                directories += 1
                let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard directories <= 512, directory.standardizedFileURL.resolvingSymlinksInPath().path == directory.path,
                      values.isDirectory == true, values.isSymbolicLink != true else {
                    throw failure("The SDK device catalog layout is unknown or exceeds its directory limit: \(directory.path).")
                }
                if depth == 0 {
                    for name in ["devices.xml", "source.properties", "package.xml"] {
                        let file = directory.appendingPathComponent(name)
                        if exists(file) { try record(file, limit: 2 * 1024 * 1024) }
                    }
                } else {
                    let children = try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    guard children.count <= 512 else { throw failure("The SDK device catalog inventory exceeds its limit.") }
                    for child in children.sorted(by: { $0.path < $1.path }) {
                        let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                        guard values.isSymbolicLink != true else { throw failure("The SDK device catalog contains a link.") }
                        if values.isDirectory == true { try catalogs(directory.appendingPathComponent(child.lastPathComponent, isDirectory: true), depth: depth - 1) }
                    }
                }
            }
            try catalogs(sdk.appendingPathComponent("extras"), depth: 2)
            try catalogs(sdk.appendingPathComponent("system-images"), depth: 3)
            return digest(Data(records.sorted().joined(separator: "\n").utf8))
        } catch is CancellationError { throw CancellationError() }
        catch let error as DomainError { throw error }
        catch { throw failure("Device profile payload could not be inspected safely. Preserve it and re-plan.") }
    }

    public static func observe(_ request: AndroidAVDRequest, origin: AndroidPreparationResource.Origin) -> AndroidPreparationResource? {
        guard exists(request.directory) || exists(request.pointer) else { return nil }
        let config = request.directory.appendingPathComponent("config.ini")
        let data = bounded(config)
        let values = data.map { AndroidDoctorContext.properties(String(decoding: $0, as: UTF8.self)) } ?? [:]
        let pointer = bounded(request.pointer).map { AndroidDoctorContext.properties(String(decoding: $0, as: UTF8.self)) } ?? [:]
        let image = values["image.sysdir.1"].map { value in value.hasPrefix("/") ? URL(fileURLWithPath: value) : request.sdkRoot.appendingPathComponent(value) }
        let complete = pointer["path"] == request.directory.path && (values["AvdId"] == nil || values["AvdId"] == request.name)
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

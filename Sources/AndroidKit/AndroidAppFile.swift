import Core
import Foundation

/// An installed SDK inspects a single APK. No Gradle, source project or SDK setup is involved.
public struct AndroidAppFile: Sendable {
    private let runner: any ProcessRunner
    private let sdk: URL
    private let buildTools: URL
    private let javaHome: URL

    public init(runner: any ProcessRunner, environment: [String: String]) throws {
        self.runner = runner
        guard let home = environment["ANDROID_HOME"], home.hasPrefix("/"), !home.isEmpty else {
            throw Self.failure("ANDROID_HOME must identify the installed SDK for source-free APK inspection.")
        }
        sdk = URL(fileURLWithPath: home).standardizedFileURL.resolvingSymlinksInPath()
        if let other = environment["ANDROID_SDK_ROOT"],
           URL(fileURLWithPath: other).standardizedFileURL.resolvingSymlinksInPath() != sdk {
            throw Self.failure("ANDROID_SDK_ROOT disagrees with ANDROID_HOME.")
        }
        guard let declaredJava = environment["JAVA_HOME"], declaredJava.hasPrefix("/"), !declaredJava.contains(":"),
              !declaredJava.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw Self.failure("JAVA_HOME must identify an installed JDK for APK signature inspection. Runstir does not invoke project-aware Java shims or install a JDK.")
        }
        javaHome = URL(fileURLWithPath: declaredJava).standardizedFileURL.resolvingSymlinksInPath()
        guard FileManager.default.isExecutableFile(atPath: javaHome.appendingPathComponent("bin/java").path) else {
            throw Self.failure("JAVA_HOME has no installed bin/java. Prepare it manually and inspect again.")
        }
        let directory = sdk.appendingPathComponent("build-tools")
        guard let installed = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            throw Self.failure("The installed SDK build-tools inventory is missing or unreadable. Prepare it manually, then inspect again.")
        }
        let versions = installed
            .compactMap { url -> (URL, SemanticVersion)? in
                guard let version = SemanticVersion(url.lastPathComponent),
                      FileManager.default.isExecutableFile(atPath: url.appendingPathComponent("aapt2").path),
                      FileManager.default.isExecutableFile(atPath: url.appendingPathComponent("apksigner").path) else { return nil }
                return (url, version)
            }.sorted { $0.1 < $1.1 }
        guard let tools = versions.last?.0,
              FileManager.default.isExecutableFile(atPath: sdk.appendingPathComponent("platform-tools/adb").path) else {
            throw Self.failure("Installed aapt2/apksigner build-tools and platform-tools/adb are required. No download was started.")
        }
        buildTools = tools
    }

    public func metadata(_ file: URL) async throws -> AppFileMetadata {
        let result = try await runner.run(ProcessCommand(buildTools.appendingPathComponent("aapt2").path,
            ["dump", "badging", file.path]))
        let text = result.standardOutput
        guard result.terminationStatus.isSuccess,
              let package = Self.capture(#"(?m)^package: (.+)$"#, text),
              let badge = try? APKBadging.read(text),
              badge.applicationId.range(of: #"^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+$"#, options: .regularExpression) != nil,
              let versionCode = badge.versionCode, let low = UInt32(versionCode),
              Int(badge.minSdk) != nil, Int(badge.targetSdk) != nil,
              badge.launcherActivity.range(of: #"^[A-Za-z_.][A-Za-z0-9_.$]*$"#, options: .regularExpression) != nil,
              Self.capture(#"(?:^| )split='([^']+)'"#, package) == nil,
              !text.contains("uses-split:"), !text.contains("isFeatureSplit='true'") else {
            throw Self.failure("The APK lacks required package/build/OS/launcher metadata or is a split APK. AAB and split bundles are excluded.")
        }
        let architectures: [String]
        if text.range(of: #"(?m)^native-code:"#, options: .regularExpression) != nil {
            architectures = badge.abis
            guard !architectures.isEmpty,
                  architectures.allSatisfy({ ["arm64-v8a", "armeabi-v7a", "x86", "x86_64"].contains($0) }) else {
                throw Self.failure("The APK's native ABI metadata is unknown or unsupported.")
            }
        } else { architectures = ["any"] }
        let majorText = Self.capture(#"(?:^| )versionCodeMajor='([^']*)'"#, package) ?? "0"
        guard let major = UInt32(majorText) else { throw Self.failure("The APK major version code is invalid.") }
        let build = String(UInt64(major) << 32 | UInt64(low))
        let manifest = try await runner.run(ProcessCommand(buildTools.appendingPathComponent("aapt2").path,
            ["dump", "xmltree", file.path, "--file", "AndroidManifest.xml"]))
        guard manifest.terminationStatus.isSuccess, manifest.standardOutput.contains("E: manifest") else {
            throw Self.failure("The APK's compiled manifest cannot confirm that this is a complete standalone app.")
        }
        for line in manifest.standardOutput.split(whereSeparator: \.isNewline).map(String.init) {
            guard let attribute = Self.capture(#"^\s*A:\s+([^\s=(]+)"#, line) else { continue }
            let name = attribute.split(separator: ":").last.map(String.init) ?? attribute
            if ["isSplitRequired", "isFeatureSplit"].contains(name) {
                guard line.range(of: #"=(?:\(type 0x12\)0x0|false)(?:\s|$)"#, options: .regularExpression) != nil else {
                    throw Self.failure("The APK requires split installation or has unknown split requirements.")
                }
            }
            if name == "configForSplit" || name == "split" && !line.contains("=\"\"") {
                throw Self.failure("A split APK is not a standalone app input.")
            }
        }
        let signature = try await runner.run(ProcessCommand(buildTools.appendingPathComponent("apksigner").path,
            ["verify", "--verbose", "--print-certs", file.path],
            environment: ["JAVA_HOME": javaHome.path, "PATH": javaHome.appendingPathComponent("bin").path + ":/usr/bin:/bin",
                "JAVA_TOOL_OPTIONS": "", "_JAVA_OPTIONS": "", "JDK_JAVA_OPTIONS": "", "JAVA_OPTS": "-Djava.awt.headless=true"],
            workingDirectory: sdk))
        let expression = try NSRegularExpression(pattern: #"(?m)^Signer #[0-9]+ certificate SHA-256 digest: ([A-Fa-f0-9]{64})\s*$"#)
        let signers = expression.matches(in: signature.standardOutput,
            range: NSRange(signature.standardOutput.startIndex..., in: signature.standardOutput)).compactMap {
                Range($0.range(at: 1), in: signature.standardOutput).map { String(signature.standardOutput[$0]).lowercased() }
            }.sorted()
        guard signature.terminationStatus.isSuccess, !signers.isEmpty else {
            throw Self.failure("The APK signature or signer identity could not be verified. Configure the installed SDK's Java requirements manually if needed; no tool installation or re-signing was attempted.")
        }
        return AppFileMetadata(platform: .android, appID: badge.applicationId,
            name: badge.displayName, version: badge.versionName, build: build,
            architectures: architectures, minimumOS: badge.minSdk, launcherActivity: badge.launcherActivity,
            signatureCondition: "APK signature verified by apksigner. Compatibility with an installed signer is finally checked by adb install -r. Runstir does not re-sign, uninstall or clear data.",
            signingIdentity: signers.joined(separator: ","))
    }

    public func devices() async throws -> [AppFileDevice] {
        let result = try await adb(["devices", "-l"])
        guard result.terminationStatus.isSuccess, result.standardOutput.contains("List of devices attached") else {
            throw Self.failure("adb could not list connected Emulator identities.")
        }
        var devices: [AppFileDevice] = []
        for line in result.standardOutput.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 2, fields[0].range(of: #"^emulator-[0-9]+$"#, options: .regularExpression) != nil,
                  fields[1] == "device" else { continue }
            let serial = fields[0]
            let nameResult = try await adb(["-s", serial, "emu", "avd", "name"])
            guard nameResult.terminationStatus.isSuccess, let name = androidAVDName(from: nameResult.standardOutput),
                  name.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil else { continue }
            let sdkResult = try await adb(["-s", serial, "shell", "getprop", "ro.build.version.sdk"])
            let abiResult = try await adb(["-s", serial, "shell", "getprop", "ro.product.cpu.abilist"])
            let boot = try await adb(["-s", serial, "shell", "getprop", "sys.boot_completed"])
            let os = sdkResult.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            let abis = abiResult.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: ",").map(String.init)
            let ready = sdkResult.terminationStatus.isSuccess && Int(os) != nil
                && abiResult.terminationStatus.isSuccess && !abis.isEmpty
                && abis.allSatisfy({ ["arm64-v8a", "armeabi-v7a", "armeabi", "x86", "x86_64"].contains($0) })
                && boot.terminationStatus.isSuccess && boot.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
            devices.append(AppFileDevice(id: "avd:" + name, handle: serial, name: name, os: os,
                architectures: abis, ready: ready, toolIdentity: "\(sdk.path); build-tools \(buildTools.lastPathComponent); JAVA_HOME \(javaHome.path)"))
        }
        guard Set(devices.map(\.id)).count == devices.count else {
            throw Self.failure("More than one Emulator reports the same AVD identity. Resolve the ambiguity before choosing a target.")
        }
        return devices.sorted { $0.id < $1.id }
    }

    public func installed(appID: String, device: AppFileDevice) async throws -> AppFileInstalledState {
        try await requireIdentity(device)
        let result = try await adb(["-s", device.handle, "shell", "pm", "list", "packages", "--show-versioncode", appID])
        guard result.terminationStatus.isSuccess else {
            return AppFileInstalledState(state: "unknown", detail: result.combinedOutput.lastLines(4))
        }
        let lines = result.standardOutput.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.allSatisfy({ $0.hasPrefix("package:") }) else {
            return AppFileInstalledState(state: "unknown", detail: "pm did not return a package inventory")
        }
        let escaped = NSRegularExpression.escapedPattern(for: appID)
        let builds = lines.compactMap { Self.capture("^package:" + escaped + #" versionCode:([0-9]+)$"#, $0) }
        let matching = lines.filter { $0.split(whereSeparator: \.isWhitespace).first == Substring("package:" + appID) }
        if !matching.isEmpty, matching.count != 1 || builds.count != 1 {
            return AppFileInstalledState(state: "unknown", detail: "the installed version code is ambiguous or missing")
        }
        guard let build = builds.first else { return AppFileInstalledState(state: "absent") }
        guard UInt64(build) != nil else {
            return AppFileInstalledState(state: "unknown", detail: "the observed version code is invalid")
        }
        let details = try await adb(["-s", device.handle, "shell", "dumpsys", "package", appID])
        return AppFileInstalledState(state: "installed",
            version: details.terminationStatus.isSuccess ? Self.capture(#"(?m)^\s*versionName=(\S+)"#, details.standardOutput) : nil,
            build: build,
            location: details.terminationStatus.isSuccess ? Self.capture(#"(?m)^\s*codePath=(\S+)"#, details.standardOutput) : nil)
    }

    public func install(file: URL, device: AppFileDevice) async throws {
        try await requireIdentity(device)
        let result = try await adb(["-s", device.handle, "install", "-r", file.path], timeout: .seconds(120))
        guard result.terminationStatus.isSuccess else {
            throw Self.failure("adb refused the data-preserving installation: " + result.combinedOutput.lastLines(8))
        }
    }

    public func launch(metadata: AppFileMetadata, device: AppFileDevice) async throws {
        try await requireIdentity(device)
        guard let activity = metadata.launcherActivity else { throw Self.failure("The APK launcher is unknown.") }
        let component = metadata.appID + "/" + (activity.hasPrefix(".") ? metadata.appID + activity : activity)
        let result = try await adb(["-s", device.handle, "shell", "am", "start", "-W", "-n", shellArgument(component)], timeout: .seconds(60))
        guard result.terminationStatus.isSuccess,
              !result.combinedOutput.contains("Error:"), !result.combinedOutput.contains("Exception") else {
            throw Self.failure("Android refused the launch request: " + result.combinedOutput.lastLines(8))
        }
    }

    public func observe(_ claim: ResourceClaim) async throws -> ClaimObservation {
        guard claim.platform == .android else { return .unknown("the recorded claim belongs to another platform") }
        let identity = try await adb(["-s", claim.handle, "emu", "avd", "name"])
        guard identity.terminationStatus.isSuccess,
              let name = androidAVDName(from: identity.standardOutput),
              ResourceKey.device(.android, "avd:" + name) == claim.device else {
            return .unknown("the recorded serial no longer confirms the selected AVD")
        }
        let result = try await adb(["-s", claim.handle, "shell", "pidof", claim.appID])
        let output = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.terminationStatus.isSuccess,
           !output.isEmpty, output.split(whereSeparator: \.isWhitespace).allSatisfy({ Int32($0).map { $0 > 0 } == true }) {
            return .running("\(claim.appID) pid \(output) on \(claim.handle)")
        }
        if result.terminationStatus == .exited(1), result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .stopped }
        return .unknown("the app's running state could not be confirmed: " + result.combinedOutput.lastLines(3))
    }

    private func requireIdentity(_ device: AppFileDevice) async throws {
        let result = try await adb(["-s", device.handle, "emu", "avd", "name"])
        guard result.terminationStatus.isSuccess,
              let name = androidAVDName(from: result.standardOutput), "avd:" + name == device.id else {
            throw Self.failure("The selected serial no longer identifies the approved Emulator. Inspect and approve the target again.")
        }
    }

    private func adb(_ arguments: [String], timeout: Duration = .seconds(30)) async throws -> ProcessResult {
        try await runner.run(ProcessCommand(sdk.appendingPathComponent("platform-tools/adb").path,
            arguments, timeout: timeout))
    }

    private static func capture(_ pattern: String, _ text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func failure(_ summary: String) -> DomainError {
        DomainError(summary: summary, remediation: Remediation(summary: "Use one complete APK and a prepared, booted Android Emulator. Inspect again after fixing the reported condition. No SDK install, app deletion or data reset was attempted."))
    }
}

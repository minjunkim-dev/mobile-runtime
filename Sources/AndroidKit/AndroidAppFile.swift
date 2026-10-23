import Core
import Foundation

/// The native signer-mismatch rejection, with no accepted installation.
public struct AndroidInstallRejection: Error, Sendable {
    public let failure: DomainError
    public let appID: String
}

/// An installed SDK inspects a single APK. No Gradle, source project or SDK setup is involved.
public struct AndroidAppFile: Sendable {
    private let runner: any ProcessRunner
    private let sdk: URL
    private let buildTools: URL
    private let javaHome: URL
    private let environment: AndroidEnvironment

    public init(runner: any ProcessRunner, environment: [String: String]) throws {
        self.runner = runner
        self.environment = AndroidEnvironment(values: environment)
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
        // Build Tools 37 adds scheme/range labels; source stamps are not APK signing identities.
        let schemeSigner = #"V(?:[12]|3\.[01]|3\.2 Hybrid (?:Classical|PQC)) Signer(?: #[0-9]+)?:"#
            + #"(?: \(minSdkVersion=[0-9]+(?: \(dev release=true\))?, maxSdkVersion=[0-9]+\))?"#
        let expression = try NSRegularExpression(pattern: #"(?m)^(?:Signer #[0-9]+|"# + schemeSigner
            + #") certificate SHA-256 digest: ([A-Fa-f0-9]{64})[ \t]*\r?$"#)
        let signers = Set(expression.matches(in: signature.standardOutput,
            range: NSRange(signature.standardOutput.startIndex..., in: signature.standardOutput)).compactMap {
                Range($0.range(at: 1), in: signature.standardOutput).map { String(signature.standardOutput[$0]).lowercased() }
            }).sorted()
        guard signature.terminationStatus.isSuccess, !signers.isEmpty else {
            throw Self.failure("The APK signature or signer identity could not be verified. Configure the installed SDK's Java requirements manually if needed; no tool installation or re-signing was attempted.")
        }
        return AppFileMetadata(platform: .android, appID: badge.applicationId,
            name: badge.displayName, version: badge.versionName, build: build,
            architectures: architectures, minimumOS: badge.minSdk, launcherActivity: badge.launcherActivity,
            signatureCondition: "APK signature verified by apksigner. Compatibility with an installed signer is finally checked by adb install -r. Runstir does not re-sign, uninstall or clear data.",
            signingIdentity: signers.joined(separator: ","))
    }

    /// Running Emulators, then installed AVDs that no Emulator runs. Runstir boots one of
    /// those only after approval; it never creates an AVD or downloads a system image.
    public func devices() async throws -> [AppFileDevice] {
        let (running, names) = try await runningDevices()
        var devices = running
        let emulator = sdk.appendingPathComponent("emulator/emulator")
        // An unlistable AVD inventory only removes boot candidates; running Emulators stay usable.
        if let names, FileManager.default.isExecutableFile(atPath: emulator.path),
           case let listed = try await runner.run(ProcessCommand(emulator.path, ["-list-avds"])),
           listed.terminationStatus.isSuccess {
            let installed = listed.standardOutput.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.range(of: #"^[A-Za-z0-9_][A-Za-z0-9_.-]*$"#, options: .regularExpression) != nil && !names.contains($0) }
            for avd in environment.avds(names: installed, sdk: sdk) {
                let bootable = avd.config != nil && avd.systemImagePresent && avd.apiLevel != nil && avd.abi != nil
                // The config and image paths join the plan identity, so a re-pointed AVD needs a new approval.
                devices.append(AppFileDevice(id: "avd:" + avd.name, handle: "avd:" + avd.name, name: avd.name,
                    os: avd.apiLevel.map(String.init) ?? "unknown", architectures: avd.abi.map { [$0] } ?? [],
                    ready: false, toolIdentity: toolIdentity,
                    architectureSource: "AVD \(avd.config?.path ?? "config missing") abi.type; system image \(avd.systemImageDirectory?.path ?? "missing"); not measured device CPU",
                    boot: bootable ? "required" : nil))
            }
        }
        guard Set(devices.map(\.id)).count == devices.count else {
            throw Self.failure("More than one Emulator reports the same AVD identity. Resolve the ambiguity before choosing a target.")
        }
        return devices.map { device in
            var device = device
            // ADB reports a name, not the running Emulator's AVD directory.
            let avd = device.handle.hasPrefix("avd:") ? environment.avds(names: [device.name], sdk: sdk).first : nil
            device.avdDirectory = avd?.directory?.path
            device.origin = DeviceOriginStore.user.origin(platform: .android, id: device.name, directory: avd?.directory)
            return device
        }.sorted { $0.id < $1.id }
    }

    /// Starts the approved AVD the way `up` does: `emulator -avd <name>`, detached so it
    /// outlives this operation. The record lets the caller report what Runstir started.
    public func startBoot(_ device: AppFileDevice, operation: String) async throws -> AppFileDeviceBoot {
        let emulator = sdk.appendingPathComponent("emulator/emulator")
        guard device.boot == "required", device.id.hasPrefix("avd:"),
              FileManager.default.isExecutableFile(atPath: emulator.path) else {
            throw Self.failure("The selected AVD cannot be booted by Runstir.")
        }
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("dev.runstir-app-file-\(operation)-emulator.log")
        let pid = try await runner.spawnDetached(ProcessCommand(emulator.path, ["-avd", device.name]), logFile: log)
        return AppFileDeviceBoot(state: "requested", device: device.id, launcherPID: pid, log: log.path,
            detail: "Runstir started this Emulator and leaves it running. Stop it yourself when finished.")
    }

    /// Waits as long as `up` does for the started AVD to become ready. A ready AVD counts only
    /// while Runstir's launcher lives: otherwise another Emulator holds that AVD, not the one Runstir started.
    public func awaitBooted(_ device: AppFileDevice, boot: AppFileDeviceBoot) async throws -> AppFileDevice {
        guard let pid = boot.launcherPID else { throw Self.failure("The started Emulator launcher is unknown.") }
        let timeouts = AndroidRuntimeTimeouts()
        let deadline = ContinuousClock.now + timeouts.boot
        while true {
            let live = try await runningDevices().devices.first { $0.id == device.id }
            switch try await androidLauncherPresence(pid, runner: runner) {
            case false?:
                throw Self.failure("The Emulator launcher Runstir started (pid \(pid)) exited before \(device.name) became ready. See \(boot.log ?? "its log"). Another Emulator may hold this AVD; Runstir did not stop or replace it.")
            case nil:
                throw Self.failure("Whether the Emulator launcher Runstir started (pid \(pid)) is alive could not be confirmed.")
            case true?:
                if var live, live.ready {
                    live.avdDirectory = device.avdDirectory
                    live.origin = DeviceOriginStore.user.origin(platform: .android, id: live.name,
                        directory: device.avdDirectory.map { URL(fileURLWithPath: $0) })
                    return live
                }
            }
            guard ContinuousClock.now < deadline else {
                throw Self.failure("Android Emulator \(device.name) did not become ready within \(timeouts.boot). Runstir left it running and did not replace or recreate it.")
            }
            try await Task.sleep(for: timeouts.poll)
        }
    }

    /// nil names: an Emulator's AVD could not be read, so no installed AVD is offered for boot.
    private func runningDevices() async throws -> (devices: [AppFileDevice], names: Set<String>?) {
        let result = try await adb(["devices", "-l"])
        guard result.terminationStatus.isSuccess, result.standardOutput.contains("List of devices attached") else {
            throw Self.failure("adb could not list connected Emulator identities.")
        }
        var devices: [AppFileDevice] = []
        var names: Set<String>? = []
        for line in result.standardOutput.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 2, fields[0].range(of: #"^emulator-[0-9]+$"#, options: .regularExpression) != nil else { continue }
            let serial = fields[0]
            let nameResult = try await adb(["-s", serial, "emu", "avd", "name"])
            guard nameResult.terminationStatus.isSuccess, let name = androidAVDName(from: nameResult.standardOutput),
                  name.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil else {
                names = nil
                continue
            }
            names?.insert(name)
            guard fields[1] == "device" else { continue }
            let ready = try await androidEmulatorReadiness(serial: serial) { try await adb($0) }
            let abis = ready?.abis ?? []
            devices.append(AppFileDevice(id: "avd:" + name, handle: serial, name: name, os: ready.map { String($0.api) } ?? "unknown",
                architectures: abis,
                ready: ready != nil && abis.allSatisfy({ ["arm64-v8a", "armeabi-v7a", "armeabi", "x86", "x86_64"].contains($0) }),
                toolIdentity: toolIdentity))
        }
        return (devices, names)
    }

    private var toolIdentity: String {
        "\(sdk.path); build-tools \(buildTools.lastPathComponent); JAVA_HOME \(javaHome.path)"
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
            let failure = Self.failure("adb refused the data-preserving installation: " + result.combinedOutput.lastLines(8))
            // Only the observed terminal refusal qualifies; transport or unfamiliar output stays reserved.
            let refusal = #"\Aadb: failed to install "# + NSRegularExpression.escapedPattern(for: file.path)
                + #": Failure \[INSTALL_FAILED_UPDATE_INCOMPATIBLE: Existing package ([A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+) signatures do not match newer version; ignoring!\](?:\r?\n){1,2}\z"#
            if result.terminationStatus == .exited(1),
               result.standardOutput == "Performing Streamed Install\n",
               let appID = Self.capture(refusal, result.standardError) {
                throw AndroidInstallRejection(failure: failure, appID: appID)
            }
            throw failure
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
        DomainError(summary: summary, remediation: Remediation(summary: "Use one complete APK and a booted Android Emulator, or an installed AVD that Runstir boots after approval. Inspect again after fixing the reported condition. No SDK install, AVD creation, app deletion or data reset was attempted."))
    }
}

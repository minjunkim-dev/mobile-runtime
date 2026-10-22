import Core
import CryptoKit
import Foundation

/// The physical iOS path reads the embedded profile and signature with platform tools
/// and installs with devicectl. It never registers devices, re-signs apps or reads
/// account credentials; unmet conditions are reported for the user to fix manually.
public struct IOSDeviceAppFile: Sendable {
    private let runner: any ProcessRunner
    private let locator: XcodeLocator

    public init(runner: any ProcessRunner, environment: [String: String]) {
        self.runner = runner
        locator = XcodeLocator(runner: runner, developerDirOverride: environment["DEVELOPER_DIR"])
    }

    /// A peek at the declared platform that routes the file; full validation is `metadata`.
    public static func declaresDevice(_ file: URL) -> Bool { IOSAppBundle.declaresDevice(file) }

    public func metadata(_ file: URL) async throws -> AppFileMetadata {
        let bundle = try await IOSAppBundle.read(file, target: .device, runner: runner, failure: Self.failure)
        let profileURL = file.appendingPathComponent("embedded.mobileprovision")
        guard let values = try? profileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, let size = values.fileSize, size <= 1_048_576 else {
            throw Self.failure("The device .app has no embedded provisioning profile. Only Development and Ad Hoc builds are supported.")
        }
        let decoded = try await runner.run(ProcessCommand("/usr/bin/security", ["cms", "-D", "-i", profileURL.path]))
        guard decoded.terminationStatus.isSuccess,
              let profile = try? PropertyListSerialization.propertyList(from: Data(decoded.standardOutput.utf8), format: nil) as? [String: Any],
              let uuid = profile["UUID"] as? String,
              let team = (profile["TeamIdentifier"] as? [String])?.first,
              let entitlements = profile["Entitlements"] as? [String: Any],
              let applicationIdentifier = entitlements["application-identifier"] as? String,
              let expiration = profile["ExpirationDate"] as? Date,
              let certificates = profile["DeveloperCertificates"] as? [Data], !certificates.isEmpty,
              (profile["Platform"] as? [String])?.contains("iOS") == true else {
            throw Self.failure("The embedded provisioning profile could not be read completely.")
        }
        if profile["ProvisionsAllDevices"] as? Bool == true {
            throw Self.failure("Enterprise profiles that provision all devices are excluded from direct installation. Use a Development or Ad Hoc build.")
        }
        guard let devices = profile["ProvisionedDevices"] as? [String], !devices.isEmpty else {
            throw Self.failure("The profile lists no devices. App Store distribution builds are excluded; use a Development or Ad Hoc build.")
        }
        let kind = entitlements["get-task-allow"] as? Bool == true ? "development" : "ad-hoc"
        let verified = try await runner.run(ProcessCommand("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R=anchor apple generic", file.path],
            timeout: .seconds(120)))
        let display = try await runner.run(ProcessCommand("/usr/bin/codesign", ["--display", "--verbose=2", file.path]))
        // A bundle path or executable name can contain a line break; more than one team line is unknown.
        let teamLines = display.combinedOutput.split(whereSeparator: \.isNewline).filter { $0.hasPrefix("TeamIdentifier=") }
        let signingTeam = display.terminationStatus.isSuccess && teamLines.count == 1
            ? String(teamLines[0].dropFirst("TeamIdentifier=".count)) : nil
        let signer = try await signingCertificate(file)
        let authorized = Set(certificates.map(Self.sha256))
        let provisioning = AppFileProvisioning(kind: kind, profileUUID: uuid, profileName: profile["Name"] as? String,
            teamID: team, applicationIdentifierPrefixes: profile["ApplicationIdentifierPrefix"] as? [String] ?? [team],
            applicationIdentifier: applicationIdentifier,
            expiration: ISO8601DateFormatter().string(from: expiration), provisionedDevices: devices.sorted(),
            signatureVerified: verified.terminationStatus.isSuccess,
            signingTeamID: signingTeam == "not set" ? nil : signingTeam,
            signingCertificateInProfile: signer.map(authorized.contains) ?? false)
        return AppFileMetadata(platform: .ios, appID: bundle.appID, name: bundle.name, version: bundle.version,
            build: bundle.build, architectures: bundle.architectures, minimumOS: bundle.minimumOS,
            signatureCondition: "iOS device \(kind) build; devicectl install is the final platform acceptance. No device registration, signing or re-signing is performed.",
            signingIdentity: signer, provisioning: provisioning)
    }

    /// Lists physical iOS devices. Only the selected one is contacted for current details.
    public func devices(selected: String?) async throws -> [AppFileDevice] {
        let installation = try await locator.locate()
        let (listed, json) = try await devicectl(["list", "devices"])
        guard let rows = (json?["result"] as? [String: Any])?["devices"] as? [[String: Any]] else {
            throw Self.failure("The physical device list could not be read: " + listed.standardError.lastLines(2))
        }
        var devices = rows.compactMap { Self.device($0, tool: installation.summary) }
        guard Set(devices.map(\.id)).count == devices.count else {
            throw Self.failure("A physical device UDID appears more than once. Its target is unknown.")
        }
        if let index = devices.firstIndex(where: { $0.id == selected }), devices[index].pairing != "paired" {
            // Contacting an untrusted device could prompt it to pair; the user does that manually.
            devices[index] = Self.device(rows.first { Self.udid($0) == devices[index].id } ?? [:], tool: installation.summary,
                connection: "not contacted: the device is not paired with this Mac", contacted: true) ?? devices[index]
        } else if let index = devices.firstIndex(where: { $0.id == selected }) {
            // Reading details connects this device when it is reachable; a failure is a connection fact.
            let (details, detailJSON) = try await devicectl(["device", "info", "details", "--device", devices[index].handle])
            if let row = detailJSON?["result"] as? [String: Any], let current = Self.device(row, tool: installation.summary, contacted: true),
               current.id == devices[index].id {
                devices[index] = current
            } else {
                devices[index] = Self.device(rows.first { Self.udid($0) == devices[index].id } ?? [:], tool: installation.summary,
                    connection: "unreachable: " + details.standardError.lastLines(1), contacted: true) ?? devices[index]
            }
        }
        return devices.sorted { $0.id < $1.id }
    }

    public func installed(appID: String, device: AppFileDevice) async throws -> AppFileInstalledState {
        try await installed(appID: appID, handle: device.handle)
    }

    public func install(file: URL, device: AppFileDevice) async throws {
        let (result, json) = try await devicectl(["device", "install", "app", "--device", device.handle, file.path], timeout: 300)
        guard json != nil else {
            throw DomainError(summary: "devicectl refused the app installation: " + result.standardError.lastLines(8),
                remediation: Remediation(summary: "If the connection was lost, reconnect and unlock the selected device. Inspect again to check its connection and installed app state before approving a new plan. If the error reports a signing or profile problem, correct that condition manually first. Runstir did not delete the existing app or its data, register a device or re-sign the app."))
        }
    }

    public func launch(appID: String, device: AppFileDevice) async throws {
        let (result, json) = try await devicectl(["device", "process", "launch", "--device", device.handle, appID], timeout: 60)
        guard json != nil else {
            throw DomainError(summary: "devicectl refused the launch request: " + result.standardError.lastLines(8),
                remediation: Remediation(summary: "The installed app remains. Unlock the device. For a Development build signed by a developer this device does not yet trust, trust that developer in Settings > General > VPN & Device Management. Then open the app on the device or run again after inspecting. Runstir did not terminate or delete any app."))
        }
    }

    public func observe(_ claim: ResourceClaim) async throws -> ClaimObservation {
        guard claim.platform == .ios, claim.device == .device(.ios, claim.handle) else {
            return .unknown("the recorded claim does not identify this physical iOS device")
        }
        let app = try await installed(appID: claim.appID, handle: claim.handle)
        if app.state == "absent" { return .stopped }
        guard app.state == "installed", let location = app.location else {
            return .unknown(app.detail ?? "the installed app location is unknown")
        }
        let (result, json) = try await devicectl(["device", "info", "processes", "--device", claim.handle])
        guard let processes = (json?["result"] as? [String: Any])?["runningProcesses"] as? [[String: Any]] else {
            return .unknown("devicectl could not list processes: " + result.standardError.lastLines(1))
        }
        // A stopped verdict releases another owner's claim, so anything not comparable stays unknown.
        // Real devicectl 651 output gives every row a file URL executable and a pid.
        guard let bundle = Self.devicePath(location) else { return .unknown("the installed app location could not be compared") }
        var pids: [Int] = []
        for process in processes {
            guard let executable = (process["executable"] as? String).flatMap(Self.devicePath) else {
                return .unknown("devicectl reported a process location that could not be compared")
            }
            // The main executable sits directly in the bundle; extensions live deeper under PlugIns.
            guard executable.deletingLastPathComponent().path == bundle.path else { continue }
            guard let pid = process["processIdentifier"] as? Int else { return .unknown("the app's process has no identifier") }
            pids.append(pid)
        }
        return pids.isEmpty ? .stopped : .running("pid " + pids.map(String.init).joined(separator: ", "))
    }

    private func installed(appID: String, handle: String) async throws -> AppFileInstalledState {
        let (result, json) = try await devicectl(["device", "info", "apps", "--device", handle, "--include-all-apps", "--bundle-id", appID])
        guard let apps = (json?["result"] as? [String: Any])?["apps"] as? [[String: Any]] else {
            return AppFileInstalledState(state: "unknown", detail: "devicectl could not confirm the installed state: " + result.standardError.lastLines(2))
        }
        let matches = apps.filter { $0["bundleIdentifier"] as? String == appID }
        guard let app = matches.first else { return AppFileInstalledState(state: "absent") }
        guard matches.count == 1 else { return AppFileInstalledState(state: "unknown", detail: "devicectl reported the app ID more than once") }
        return AppFileInstalledState(state: "installed", version: app["version"] as? String,
            build: app["bundleVersion"] as? String, location: app["url"] as? String)
    }

    /// SHA-256 of the leaf certificate that signed the bundle; nil when it cannot be read.
    private func signingCertificate(_ file: URL) async throws -> String? {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dev.runstir-signer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let prefix = directory.appendingPathComponent("certificate").path
        let result = try await runner.run(ProcessCommand("/usr/bin/codesign", ["--display", "--extract-certificates=" + prefix, file.path]))
        guard result.terminationStatus.isSuccess, let leaf = try? Data(contentsOf: URL(fileURLWithPath: prefix + "0")) else { return nil }
        return Self.sha256(leaf)
    }

    private func devicectl(_ arguments: [String], timeout: Int = 30) async throws -> (ProcessResult, [String: Any]?) {
        let result = try await runner.run(ProcessCommand("xcrun", ["devicectl"] + arguments
            + ["--timeout", String(timeout), "--quiet", "--omit-deprecated-fields-in-json", "--json-output", "-"],
            environment: await locator.pinnedEnvironment(), timeout: .seconds(timeout + 15)))
        // Only a successful exit with a successful outcome is evidence; anything else is a fact to report.
        guard result.terminationStatus.isSuccess,
              let json = try? JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [String: Any],
              (json["info"] as? [String: Any])?["outcome"] as? String == "success" else { return (result, nil) }
        return (result, json)
    }

    /// Device-side file URL with `/private/var` folded to `/var`, the two spellings CoreDevice may use.
    private static func devicePath(_ value: String) -> URL? {
        guard let url = URL(string: value), url.isFileURL, !url.path.isEmpty else { return nil }
        let path = url.standardized.path
        return URL(fileURLWithPath: path.hasPrefix("/private/var/") ? String(path.dropFirst("/private".count)) : path)
    }

    private static func udid(_ row: [String: Any]) -> String? {
        ((row["properties"] as? [String: Any])?["hardware"] as? [String: Any])?["udid"] as? String
    }

    /// A listed device that was not contacted reports an idle tunnel as disconnected, so only a
    /// contacted device's connection counts toward readiness.
    static func device(_ row: [String: Any], tool: String, connection override: String? = nil,
                       contacted: Bool = false) -> AppFileDevice? {
        let properties = row["properties"] as? [String: Any] ?? [:]
        let hardware = properties["hardware"] as? [String: Any] ?? [:]
        guard hardware["reality"] as? String == "physical", hardware["platform"] as? String == "iOS",
              let udid = hardware["udid"] as? String,
              udid.range(of: #"^[0-9A-Fa-f][0-9A-Fa-f-]*$"#, options: .regularExpression) != nil else { return nil }
        let connection = properties["connection"] as? [String: Any] ?? [:]
        let state = properties["state"] as? [String: Any] ?? [:]
        let os = ((properties["software"] as? [String: Any])?["osVersionNumber"] as? [String: Any])?["stringValue"] as? String
        // CoreDevice encodes the status as a one-key object such as {"enabled": {...}}.
        let developerMode = (state["developerModeStatus"] as? [String: Any]).flatMap { $0.count == 1 ? $0.keys.first : nil }
        let architectures = Set((hardware["supportedCPUTypes"] as? [[String: Any]] ?? []).compactMap(architecture))
        let pairing = connection["pairingState"] as? String
        let link = override ?? connection["state"] as? String
        return AppFileDevice(id: udid, handle: udid, name: state["name"] as? String ?? hardware["marketingName"] as? String ?? udid,
            os: os ?? "unknown", architectures: architectures.sorted(),
            ready: pairing == "paired" && developerMode == "enabled" && (!contacted || link == "connected"), toolIdentity: tool,
            architectureSource: "devicectl supportedCPUTypes; CPU capabilities reported by CoreDevice",
            pairing: pairing, developerMode: developerMode, connection: link)
    }

    private static func architecture(_ cpu: [String: Any]) -> String? {
        // CPU_TYPE_ARM64. The low 24 subtype bits name the slice; the high bits are capability flags.
        guard (cpu["type"] as? NSNumber)?.int64Value == 0x0100_000C, let subtype = cpu["subtype"] as? NSNumber else { return nil }
        switch subtype.uint64Value & 0x00FF_FFFF {
        case 0: return "arm64"
        case 2: return "arm64e"
        default: return nil
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func failure(_ summary: String) -> DomainError {
        DomainError(summary: summary, remediation: Remediation(summary: "Choose a Development or Ad Hoc iOS device .app and a connected, trusted device with Developer Mode, then inspect again. Runstir did not register a device, re-sign the app, collect an account or delete an app."))
    }
}

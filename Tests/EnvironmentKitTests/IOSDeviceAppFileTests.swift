import Core
@testable import EnvironmentKit
import Foundation
import TestSupport
import Testing

@Suite("physical iOS device conditions reuse the exact app-file approval path")
struct IOSDeviceAppFileTests {
    @Test("a satisfied Development build installs only after the exact approval and reports every condition")
    func satisfied() async throws {
        let fixture = try DeviceFixture()
        let inspected = await fixture.run(inspectOnly: true, selected: false)
        #expect(inspected.exitCode == 0)
        #expect(inspected.operation.devices.map(\.id) == [DeviceFixture.udid])
        #expect(inspected.operation.prerequisites == nil)
        // An uncontacted device's idle tunnel is not a missing preparation.
        #expect(inspected.operation.devices.first?.ready == true)
        #expect(!fixture.runner.commands.contains { $0.arguments.contains("details") })

        let proposed = await fixture.run(planOnly: true)
        let plan = try #require(proposed.operation.plan)
        let checks = try #require(proposed.operation.prerequisites)
        #expect(checks.map(\.id) == ["signature", "profile-app-id", "profile-expiration", "profile-device",
                                     "os", "architecture", "trust", "developer-mode", "connection"])
        #expect(checks.allSatisfy { $0.state == "satisfied" && $0.action == nil })
        #expect(plan.artifact.metadata.provisioning?.kind == "development")
        #expect(plan.device.architectures == ["arm64", "arm64e"])
        #expect(!fixture.runner.commands.contains(where: mutation))

        let installed = await fixture.run(approval: plan.approval)
        #expect(installed.exitCode == 0)
        #expect(installed.operation.completed == ["inspect", "install", "launch"])
        #expect(installed.operation.installed?.build == "2")
        #expect(installed.operation.running == "running: pid 4242")
        #expect(installed.operation.firstScreen == "unverified")
        let staged = try #require(fixture.runner.commands.first { $0.arguments.prefix(3) == ["devicectl", "device", "install"] })
        #expect(staged.arguments.contains { $0.contains("dev.runstir-app-file-") })
        #expect(!fixture.runner.commands.contains(where: forbidden))

        let json = try JSONSerialization.jsonObject(with: Data(installed.encoded(toolVersion: "test").utf8)) as? [String: Any]
        let operation = try #require(json?["operation"] as? [String: Any])
        #expect((operation["prerequisites"] as? [[String: Any]])?.count == 9)
        let metadata = try #require(((operation["artifact"] as? [String: Any])?["metadata"] as? [String: Any]))
        let profile = try #require(metadata["provisioning"] as? [String: Any])
        #expect(profile["provisionedDeviceCount"] as? Int == 1)
        #expect(profile["provisionedDevices"] == nil)
        let lines = AppFileHumanOutput.lines(installed).output
        #expect(lines.contains { $0.hasPrefix("condition profile-device: satisfied") })
        #expect(lines.contains { $0.hasPrefix("profile: development") })
    }

    @Test("each unmet condition stops before installation with a manual step and re-check", arguments: [
        "profile-device", "developer-mode", "trust", "connection", "signature", "certificate", "team-lines", "display-fails", "extract-fails",
        "profile-expiration", "os", "profile-app-id", "app-id-prefix", "architecture"
    ])
    func unmet(_ defect: String) async throws {
        let fixture = try DeviceFixture()
        let id: String
        switch defect {
        case "profile-device": fixture.runner.provisioned = ["00008110-000A0C123456001F"]; id = defect
        case "developer-mode": fixture.runner.developerMode = "disabled"; id = defect
        case "trust": fixture.runner.pairing = "unpaired"; id = defect
        case "connection": fixture.runner.unreachable = true; id = defect
        case "signature": fixture.runner.signatureValid = false; id = defect
        case "certificate": fixture.runner.profileCertificate = Data("another certificate".utf8); id = "signature"
        case "team-lines": fixture.runner.injectedTeamLine = true; id = "signature"
        case "display-fails": fixture.runner.displayFails = true; id = "signature"
        case "extract-fails": fixture.runner.extractFails = true; id = "signature"
        case "profile-expiration": fixture.runner.expiration = Date(timeIntervalSinceNow: -60); id = defect
        case "os": fixture.runner.deviceOS = "16.4"; id = defect
        case "profile-app-id": fixture.runner.applicationIdentifier = "TEAM123456.com.fixture.Other"; id = defect
        case "app-id-prefix": fixture.runner.applicationIdentifier = "OTHERPREFX." + DeviceRunner.appID; id = "profile-app-id"
        default: fixture.runner.cpuSubtypes = [5]; id = "architecture"
        }
        let result = await fixture.run(planOnly: true)
        #expect(result.exitCode == 1)
        #expect(result.operation.state == "failed")
        #expect(result.operation.plan == nil)
        let check = try #require(result.operation.prerequisites?.first { $0.id == id })
        #expect(check.state != "satisfied")
        #expect(check.action?.isEmpty == false)
        #expect(result.operation.error?.contains(id) == true)
        #expect(result.operation.nextAction?.contains("inspect again") == true)
        #expect(result.operation.nextAction?.contains("did not register a device, re-sign the app or collect an account") == true)
        #expect(result.operation.installation == "not-requested")
        #expect(!fixture.runner.commands.contains(where: mutation))
        #expect(!fixture.runner.commands.contains(where: forbidden))
        // An untrusted device is never contacted, so it cannot be prompted to pair.
        if defect == "trust" { #expect(!fixture.runner.commands.contains { $0.arguments.contains("details") }) }
    }

    @Test("a fixed condition is accepted on the next inspection without changing the file")
    func recheck() async throws {
        let fixture = try DeviceFixture()
        fixture.runner.developerMode = "disabled"
        let blocked = await fixture.run(planOnly: true)
        #expect(blocked.operation.plan == nil)
        fixture.runner.developerMode = "enabled"
        let ready = await fixture.run(planOnly: true)
        #expect(ready.operation.plan != nil)
        #expect(blocked.operation.artifact?.contentIdentity == ready.operation.artifact?.contentIdentity)
    }

    @Test("a legacy App ID prefix listed by the profile is accepted, and CPU order does not change the plan")
    func legacyPrefixAndCPUOrder() async throws {
        let fixture = try DeviceFixture()
        fixture.runner.legacyPrefix = "LEGACY0001"
        fixture.runner.applicationIdentifier = "LEGACY0001." + DeviceRunner.appID
        let first = try #require(await fixture.run(planOnly: true).operation.plan)
        fixture.runner.cpuSubtypes.reverse()
        let second = try #require(await fixture.run(planOnly: true).operation.plan)
        #expect(first.id == second.id)
        #expect(second.device.architectures == ["arm64", "arm64e"])
    }

    @Test("excluded signing forms and an unreadable profile stop at inspection",
          arguments: ["enterprise", "app-store", "missing-profile", "unreadable-profile"])
    func excluded(_ form: String) async throws {
        let fixture = try DeviceFixture()
        switch form {
        case "enterprise": fixture.runner.allDevices = true
        case "app-store": fixture.runner.provisioned = []
        case "unreadable-profile": fixture.runner.profileUnreadable = true
        default: try FileManager.default.removeItem(at: fixture.file.appendingPathComponent("embedded.mobileprovision"))
        }
        let result = await fixture.run(inspectOnly: true)
        #expect(result.exitCode == 1)
        #expect(result.operation.artifact == nil)
        #expect(!fixture.runner.commands.contains { $0.arguments.first == "devicectl" })
    }

    @Test("an unreadable or ambiguous device list stops before any device is contacted", arguments: [true, false])
    func unreadableDeviceList(_ refused: Bool) async throws {
        let fixture = try DeviceFixture()
        if refused { fixture.runner.listRefused = true } else { fixture.runner.duplicateDevice = true }
        let result = await fixture.run(planOnly: true)
        #expect(result.exitCode == 1)
        #expect(result.operation.plan == nil)
        #expect(result.operation.devices.isEmpty)
        #expect(!fixture.runner.commands.contains { $0.arguments.contains("details") })
        #expect(!fixture.runner.commands.contains(where: mutation))
    }

    @Test("an unparseable process location is unknown, never a stopped claim owner")
    func unparseableProcess() async throws {
        let fixture = try DeviceFixture()
        let plan = try #require(await fixture.run(planOnly: true).operation.plan)
        fixture.runner.unparseableProcess = true
        let result = await fixture.run(approval: plan.approval)
        #expect(result.operation.installation == "installed")
        #expect(result.operation.running.hasPrefix("unknown:"))
        #expect(result.operation.state == "partially-completed")
    }

    @Test("a disconnect after approval stops before installation without switching targets")
    func disconnectBeforeInstall() async throws {
        let fixture = try DeviceFixture()
        let plan = try #require(await fixture.run(planOnly: true).operation.plan)
        fixture.runner.unreachable = true
        let result = await fixture.run(approval: plan.approval)
        #expect(result.exitCode == 1)
        #expect(result.operation.installation == "not-requested")
        #expect(result.operation.prerequisites?.first { $0.id == "connection" }?.state == "unsatisfied")
        #expect(!fixture.runner.commands.contains(where: mutation))
    }

    @Test("cancel after the installer request reobserves the device and deletes nothing")
    func cancelled() async throws {
        let fixture = try DeviceFixture()
        let plan = try #require(await fixture.run(planOnly: true).operation.plan)
        fixture.runner.cancelAfterInstall = true
        let result = await fixture.run(approval: plan.approval)
        #expect(result.exitCode == 130)
        #expect(result.operation.installation == "unconfirmed")
        #expect(result.operation.installed?.state == "installed")
        #expect(result.operation.installed?.build == "2")
        #expect(result.operation.launch == "not-requested")
        #expect(!fixture.runner.commands.contains(where: forbidden))
    }

    @Test("an older installed build reuses the separate DOWNGRADE acknowledgement")
    func downgrade() async throws {
        let fixture = try DeviceFixture(installedBuild: "3")
        let plan = try #require(await fixture.run(planOnly: true).operation.plan)
        #expect(plan.replacement)
        #expect(plan.downgrade)
        #expect(plan.approval == "DOWNGRADE:" + plan.id)
        let refused = await fixture.run(approval: plan.id)
        #expect(refused.operation.state == "needs-approval")
        #expect(!fixture.runner.commands.contains(where: mutation))
    }

    @Test("a platform install refusal or unobserved build is unconfirmed, reobserved and never launched", arguments: [true, false])
    func installNotConfirmed(_ refused: Bool) async throws {
        let fixture = try DeviceFixture()
        let plan = try #require(await fixture.run(planOnly: true).operation.plan)
        if refused { fixture.runner.installRefused = true } else { fixture.runner.installUnobserved = true }
        let result = await fixture.run(approval: plan.approval)
        #expect(result.exitCode == 1)
        #expect(result.operation.state == "failed")
        #expect(result.operation.installation == "unconfirmed")
        #expect(result.operation.installed?.state == "absent")
        #expect(result.operation.launch == "not-requested")
        if refused { #expect(result.operation.error?.contains("valid provisioning profile") == true) }
        #expect(!fixture.runner.commands.contains { $0.arguments.contains("launch") })
        #expect(!fixture.runner.commands.contains(where: forbidden))
    }

    @Test("a launch refusal keeps the observed installation and says what to do next")
    func launchRefused() async throws {
        let fixture = try DeviceFixture()
        let plan = try #require(await fixture.run(planOnly: true).operation.plan)
        fixture.runner.launchRefused = true
        let result = await fixture.run(approval: plan.approval)
        #expect(result.exitCode == 1)
        #expect(result.operation.state == "failed")
        #expect(result.operation.installation == "installed")
        #expect(result.operation.installed?.build == "2")
        #expect(result.operation.launch == "requested")
        #expect(result.operation.error?.contains("device is locked") == true)
        #expect(result.operation.nextAction?.contains("Unlock the device") == true)
        #expect(result.operation.nextAction?.contains("VPN & Device Management") == true)
        #expect(!fixture.runner.commands.contains(where: forbidden))
    }

    private func mutation(_ command: ProcessCommand) -> Bool {
        command.arguments.contains("install") || command.arguments.contains("launch")
    }

    private func forbidden(_ command: ProcessCommand) -> Bool {
        ["uninstall", "terminate", "--terminate-existing", "unpair", "pair", "manage", "--sign", "-s", "--force", "--remove-signature"]
            .contains(where: command.arguments.contains)
            || command.executable == "xcodebuild" && command.arguments != ["-version"]
    }
}

private final class DeviceFixture {
    static let udid = "00008110-000A0C123456001E"
    let repo: FixtureRepo
    let file: URL
    let runner: DeviceRunner
    let leases: ResourceLeases

    init(installedBuild: String? = nil) throws {
        repo = try FixtureRepo()
        leases = ResourceLeases(directory: repo.url("leases"))
        file = try repo.directory("Device.app")
        _ = try repo.write("Device.app/Program", "approved bytes")
        _ = try repo.write("Device.app/embedded.mobileprovision", "CMS envelope; decoded only by the fixture")
        let plist: [String: Any] = ["CFBundlePackageType": "APPL", "CFBundleIdentifier": DeviceRunner.appID,
            "CFBundleExecutable": "Program", "CFBundleVersion": "2", "CFBundleShortVersionString": "1.2",
            "MinimumOSVersion": "17.0", "CFBundleSupportedPlatforms": ["iPhoneOS"]]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: file.appendingPathComponent("Info.plist"))
        runner = DeviceRunner(installedBuild: installedBuild)
    }

    func run(inspectOnly: Bool = false, planOnly: Bool = false, approval: String? = nil, selected: Bool = true) async -> AppFileResult {
        await AppFileExecution.run(input: AppFileInput(file: file, environment: [:], device: selected ? Self.udid : nil),
            inspectOnly: inspectOnly, planOnly: planOnly, approvedPlanID: approval, runner: runner, leases: leases)
    }
}

/// Models codesign, security and devicectl observations; no device or signing tool runs.
private final class DeviceRunner: ProcessRunner, @unchecked Sendable {
    static let appID = "com.fixture.Device"
    static let certificate = Data("leaf certificate".utf8)
    private let lock = NSLock()
    private var recorded: [ProcessCommand] = []
    private var installedBuild: String?
    var provisioned = [DeviceFixture.udid.lowercased()]
    var allDevices = false
    var applicationIdentifier = "TEAM123456." + DeviceRunner.appID
    var legacyPrefix: String?
    var expiration = Date(timeIntervalSinceNow: 86_400 * 30)
    var profileCertificate = DeviceRunner.certificate
    var signatureValid = true
    var pairing = "paired"
    var developerMode = "enabled"
    var deviceOS = "27.0.1"
    var cpuSubtypes: [UInt64] = [18_446_744_071_562_067_970, 0]
    var unreachable = false
    var cancelAfterInstall = false
    var injectedTeamLine = false
    var unparseableProcess = false
    var displayFails = false
    var extractFails = false
    var profileUnreadable = false
    var listRefused = false
    var duplicateDevice = false
    var installRefused = false
    var installUnobserved = false
    var launchRefused = false
    var commands: [ProcessCommand] { lock.withLock { recorded } }

    init(installedBuild: String?) { self.installedBuild = installedBuild }

    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        try lock.withLock {
            recorded.append(command)
            let args = command.arguments
            func ok(_ output: String = "", _ error: String = "") -> ProcessResult {
                ProcessResult(terminationStatus: .exited(0), standardOutput: output, standardError: error)
            }
            func fail(_ error: String) -> ProcessResult { ProcessResult(terminationStatus: .exited(1), standardOutput: "", standardError: error) }
            // devicectl still writes its JSON envelope on failure, with a failed outcome.
            func refused(_ error: String) -> ProcessResult {
                ProcessResult(terminationStatus: .exited(1),
                    standardOutput: #"{"info":{"outcome":"failed"},"error":{"userInfo":{"NSLocalizedDescription":"\#(error)"}}}"#,
                    standardError: "ERROR: " + error)
            }
            func json(_ result: Any) throws -> ProcessResult {
                ok(String(decoding: try JSONSerialization.data(withJSONObject: ["info": ["outcome": "success"], "result": result]), as: UTF8.self))
            }
            if command.description == "xcode-select -p" { return ok("/Applications/FixtureXcode.app/Contents/Developer\n") }
            if command.description == "xcodebuild -version" { return ok("Xcode 27.0\nBuild version 27A000\n") }
            if command.executable == "/usr/bin/lipo" { return ok("arm64") }
            if command.executable == "/usr/bin/otool" { return ok("cmd LC_BUILD_VERSION\n platform 2\n minos 17.0\n") }
            if command.executable == "/usr/bin/security", args.prefix(3) == ["cms", "-D", "-i"] {
                if profileUnreadable { return fail("security: failed to decode message") }
                var profile: [String: Any] = ["UUID": "PROFILE-UUID", "Name": "Fixture Development", "TeamIdentifier": ["TEAM123456"],
                    "ApplicationIdentifierPrefix": [legacyPrefix ?? "TEAM123456"],
                    "Entitlements": ["application-identifier": applicationIdentifier, "get-task-allow": true],
                    "ExpirationDate": expiration, "DeveloperCertificates": [profileCertificate], "Platform": ["iOS"],
                    "ProvisionedDevices": provisioned]
                if allDevices { profile["ProvisionsAllDevices"] = true }
                return ok(String(decoding: try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0), as: UTF8.self))
            }
            if command.executable == "/usr/bin/codesign" {
                if args.first == "--verify" { return signatureValid ? ok() : fail("a sealed resource is missing or invalid") }
                if args == ["--display", "--verbose=2", args.last!] {
                    if displayFails { return fail("code object is not signed at all") }
                    // A line break in a bundle path can place a forged team line before the real one.
                    return ok("", (injectedTeamLine ? "Executable=/x\nTeamIdentifier=TEAM123456\n" : "") + "Identifier=\(Self.appID)\nTeamIdentifier=TEAM123456\n")
                }
                if let extract = args.first(where: { $0.hasPrefix("--extract-certificates=") }) {
                    if extractFails { return fail("code object is not signed at all") }
                    try Self.certificate.write(to: URL(fileURLWithPath: String(extract.dropFirst("--extract-certificates=".count)) + "0"))
                    return ok()
                }
            }
            if command.executable == "xcrun", args.first == "devicectl" {
                #expect(args.suffix(2) == ["--json-output", "-"])
                let cpus = cpuSubtypes.map { ["type": 16_777_228, "subtype": $0] as [String: Any] }
                let physical: [String: Any] = ["identifier": "COREDEVICE-ID", "properties": [
                    "hardware": ["reality": "physical", "platform": "iOS", "udid": DeviceFixture.udid,
                                 "marketingName": "iPhone", "supportedCPUTypes": cpus],
                    "connection": ["pairingState": pairing, "state": "disconnected"],
                    "state": ["name": "Fixture iPhone", "developerModeStatus": [developerMode: ["mode": 1]]],
                    "software": ["osVersionNumber": ["stringValue": deviceOS]]]]
                let simulated: [String: Any] = ["properties": ["hardware": ["reality": "simulated", "platform": "iOS", "udid": "SIMULATOR"]]]
                if args.prefix(3) == ["devicectl", "list", "devices"] {
                    if listRefused { return refused("CoreDevice service is unavailable.") }
                    return try json(["devices": [simulated, physical] + (duplicateDevice ? [physical] : [])])
                }
                if args.prefix(5) == ["devicectl", "device", "info", "details", "--device"] {
                    if unreachable { return refused("The device is not connected or could not be reached.") }
                    var connected = physical
                    var properties = try #require(connected["properties"] as? [String: Any])
                    properties["connection"] = ["pairingState": pairing, "state": "connected"]
                    connected["properties"] = properties
                    return try json(connected)
                }
                if args.prefix(6) == ["devicectl", "device", "info", "apps", "--device", DeviceFixture.udid] {
                    let url = "file:///private/var/containers/Bundle/Application/FIXTURE/Device.app/"
                    return try json(["apps": installedBuild.map { [["bundleIdentifier": Self.appID, "bundleVersion": $0, "version": "1.2", "url": url]] } ?? []])
                }
                if args.prefix(5) == ["devicectl", "device", "install", "app", "--device"] {
                    if installRefused { return refused("Failed to install the app: A valid provisioning profile for this executable was not found.") }
                    if !installUnobserved { installedBuild = "2" }
                    if cancelAfterInstall { throw CancellationError() }
                    return try json(["installedApplications": []])
                }
                if args.prefix(6) == ["devicectl", "device", "process", "launch", "--device", DeviceFixture.udid] {
                    if launchRefused { return refused("The request was denied by service delegate (SBMainWorkspace): the device is locked.") }
                    return try json(["process": ["processIdentifier": 4242]])
                }
                if args.prefix(5) == ["devicectl", "device", "info", "processes", "--device"] {
                    // CoreDevice may spell the container without /private.
                    let base = "file:///var/containers/Bundle/Application/FIXTURE/Device.app/"
                    if unparseableProcess { return try json(["runningProcesses": [["executable": "not a url", "processIdentifier": 1]]]) }
                    return try json(["runningProcesses": [["executable": base + "Program", "processIdentifier": 4242],
                        ["executable": base + "PlugIns/Widget.appex/Widget", "processIdentifier": 4343]]])
                }
            }
            throw FixtureMiss(command: command.description)
        }
    }

    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
        throw FixtureMiss(command: "unexpected detached child: " + command.description)
    }
}

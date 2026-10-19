import Core
import EnvironmentKit
import Foundation
import TestSupport
import Testing

@Suite("source-free app inspection and exact approved installation")
struct AppFileExecutionTests {
    @Test("excluded formats stop before any tool call or installation", arguments: ["ipa", "aab", "apks", "zip"])
    func excluded(_ ext: String) async throws {
        let repo = try FixtureRepo()
        let file = try repo.write("input." + ext, "original")
        let runner = FakeProcessRunner()
        let result = await AppFileExecution.run(input: AppFileInput(file: file, environment: [:]), inspectOnly: true, runner: runner)
        #expect(result.exitCode == 1)
        #expect(result.operation.installation == "not-requested")
        #expect(runner.log.all.isEmpty)
        #expect(try String(contentsOf: file, encoding: .utf8) == "original")
    }

    @Test("escaping bundle links stop before metadata tools and preserve their target")
    func escapingLink() async throws {
        let fixture = try AppFileFixture(platform: .ios)
        let outside = try fixture.repo.write("outside", "private")
        try FileManager.default.createSymbolicLink(at: fixture.file.appendingPathComponent("escape"), withDestinationURL: outside)
        let result = await fixture.run(inspectOnly: true)
        #expect(result.exitCode == 1)
        #expect(fixture.runner.commands.isEmpty)
        #expect(try String(contentsOf: outside, encoding: .utf8) == "private")
    }

    @Test("inspection needs no source, never installs and reports evidence boundaries", arguments: [ProjectPlatform.ios, .android])
    func inspection(_ platform: ProjectPlatform) async throws {
        let fixture = try AppFileFixture(platform: platform)
        let result = await fixture.run(inspectOnly: true, selected: false)
        #expect(result.exitCode == 0)
        #expect(result.operation.artifact?.origin == "user-selected-file")
        #expect(result.operation.artifact?.contentIdentity.count == 64)
        #expect(result.operation.firstScreen == "unverified")
        #expect(result.operation.devices.map(\.id) == [fixture.device])
        #expect(!FileManager.default.fileExists(atPath: fixture.leases.directory.path))
        #expect(!fixture.runner.commands.contains(where: mutation))
        let encoded = try result.encoded(toolVersion: "test")
        let document = try #require(JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any])
        #expect(document["schemaVersion"] as? Int == 1)
        #expect(document["command"] as? String == "app inspect")
        let operation = try #require(document["operation"] as? [String: Any])
        #expect(operation["firstScreen"] as? String == "unverified")
        #expect(operation["externalServer"] as? String == "unverified; Runstir did not start or connect a development server")
    }

    @Test("a missing device remains a selection and cannot start changes")
    func missingDevice() async throws {
        let fixture = try AppFileFixture(platform: .ios)
        let result = await fixture.run(selected: false)
        #expect(result.exitCode == 1)
        #expect(result.operation.state == "needs-selection")
        #expect(result.operation.requiredInput == ["--device"])
        #expect(!fixture.runner.commands.contains(where: mutation))
    }

    @Test("an iPhoneOS executable never passes as a Simulator artifact")
    func wrongBinaryPlatform() async throws {
        let fixture = try AppFileFixture(platform: .ios)
        fixture.runner.simulatorPlatform = "2"
        let result = await fixture.run(planOnly: true)
        #expect(result.exitCode == 1)
        #expect(result.operation.plan == nil)
        #expect(!fixture.runner.commands.contains(where: mutation))
    }

    @Test("required bundle metadata and executable paths fail closed", arguments: ["CFBundleIdentifier", "CFBundleVersion", "MinimumOSVersion", "CFBundleExecutable"])
    func missingBundleMetadata(_ key: String) async throws {
        let fixture = try AppFileFixture(platform: .ios)
        let url = fixture.file.appendingPathComponent("Info.plist")
        var values = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        if key == "CFBundleExecutable" { values[key] = "../outside" }
        else { values.removeValue(forKey: key) }
        try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0).write(to: url)
        let result = await fixture.run(planOnly: true)
        #expect(result.exitCode == 1)
        #expect(fixture.runner.commands.isEmpty)
    }

    @Test("split APKs and missing required metadata never produce an install plan", arguments: ["split", "missing-package", "missing-build", "missing-launcher", "missing-os", "unknown-abi"])
    func invalidAPK(_ defect: String) async throws {
        let fixture = try AppFileFixture(platform: .android)
        var text = AppFileRunner.badging
        switch defect {
        case "split": text = text.replacingOccurrences(of: "versionCode='2'", with: "versionCode='2' split='config.arm64_v8a'")
        case "missing-package": text = text.replacingOccurrences(of: "name='com.fixture.Local'", with: "unidentified='com.fixture.Local'")
        case "missing-build": text = text.replacingOccurrences(of: "versionCode='2'", with: "")
        case "missing-launcher": text = text.replacingOccurrences(of: "launchable-activity:", with: "not-a-launcher:")
        case "missing-os": text = text.replacingOccurrences(of: "sdkVersion:'23'", with: "sdkVersion:'unknown'")
        default: text = text.replacingOccurrences(of: "'arm64-v8a'", with: "'unknown-abi'")
        }
        fixture.runner.badgingOverride = text
        let result = await fixture.run(planOnly: true)
        #expect(result.exitCode == 1)
        #expect(result.operation.plan == nil)
        #expect(!fixture.runner.commands.contains(where: mutation))
    }

    @Test("an installed package without its version is unknown and never treated as absent")
    func unknownInstalledVersion() async throws {
        let fixture = try AppFileFixture(platform: .android)
        fixture.runner.installedInventoryOverride = "package:com.fixture.Local\n"
        let result = await fixture.run(planOnly: true)
        #expect(result.exitCode == 1)
        #expect(result.operation.installed?.state == "unknown")
        #expect(result.operation.plan == nil)
        #expect(!fixture.runner.commands.contains(where: mutation))
    }

    @Test("a base APK requiring splits and an unsigned APK stop before approval", arguments: ["required-splits", "unsigned"])
    func incompleteAPK(_ defect: String) async throws {
        let fixture = try AppFileFixture(platform: .android)
        if defect == "required-splits" { fixture.runner.requiresSplits = true }
        else { fixture.runner.invalidSignature = true }
        let result = await fixture.run(planOnly: true)
        #expect(result.exitCode == 1)
        #expect(result.operation.plan == nil)
        #expect(!fixture.runner.commands.contains(where: mutation))
    }

    @Test("canonical aliases share a file lease while a different path keeps its own task")
    func fileIdentity() throws {
        let repo = try FixtureRepo()
        let first = try repo.write("first.apk", "same bytes")
        let alias = repo.url("alias.apk")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: first)
        let second = try repo.write("second.apk", "same bytes")
        let before = try AppFileIdentity(url: first)
        #expect(ResourceKey.appFile(before) == ResourceKey.appFile(try AppFileIdentity(url: alias)))
        #expect(ResourceKey.appFile(before) != ResourceKey.appFile(try AppFileIdentity(url: second)))
        try Data("replacement bytes".utf8).write(to: first, options: .atomic)
        #expect(ResourceKey.appFile(before) == ResourceKey.appFile(try AppFileIdentity(url: first)))
    }

    @Test("changed bytes invalidate an earlier approval without installing", arguments: [ProjectPlatform.ios, .android])
    func changedApproval(_ platform: ProjectPlatform) async throws {
        let fixture = try AppFileFixture(platform: platform)
        let first = await fixture.run(planOnly: true)
        let plan = try #require(first.operation.plan)
        try Data("changed bytes".utf8).write(to: fixture.payload)
        let result = await fixture.run(approval: plan.approval)
        #expect(result.operation.state == "needs-approval")
        #expect(result.operation.plan?.id != plan.id)
        #expect(!fixture.runner.commands.contains(where: mutation))
    }

    @Test("a file change during private staging needs a new approval")
    func changedDuringStaging() async throws {
        let fixture = try AppFileFixture(platform: .ios)
        let proposed = await fixture.run(planOnly: true)
        let plan = try #require(proposed.operation.plan)
        fixture.runner.mutateOriginalDuringStagedInspection = true
        let result = await fixture.run(approval: plan.approval)
        #expect(result.exitCode == 1)
        #expect(result.operation.state == "needs-approval")
        #expect(result.operation.plan?.id != plan.id)
        #expect(!fixture.runner.commands.contains(where: mutation))
    }

    @Test("disconnect before installation never switches to another target")
    func disconnected() async throws {
        let fixture = try AppFileFixture(platform: .ios)
        let proposed = await fixture.run(planOnly: true)
        let plan = try #require(proposed.operation.plan)
        fixture.runner.disconnectOnFinalRecheck = true
        let result = await fixture.run(approval: plan.approval)
        #expect(result.exitCode == 1)
        #expect(result.operation.installation == "not-requested")
        #expect(!fixture.runner.commands.contains(where: mutation))
    }

    @Test("approved app bytes install once without build, cleanup or server startup", arguments: [ProjectPlatform.ios, .android])
    func installAndRun(_ platform: ProjectPlatform) async throws {
        let fixture = try AppFileFixture(platform: platform)
        let proposed = await fixture.run(planOnly: true)
        let plan = try #require(proposed.operation.plan)
        #expect(!fixture.runner.commands.contains(where: mutation))
        let result = await fixture.run(approval: plan.approval)
        #expect(result.exitCode == 0, Comment(rawValue: result.operation.error ?? ""))
        #expect(result.operation.completed == ["inspect", "install", "launch"])
        #expect(result.operation.installation == "installed")
        #expect(result.operation.launch == "accepted")
        #expect(result.operation.running.hasPrefix("running:"))
        #expect(result.operation.firstScreen == "unverified")
        let installs = fixture.runner.commands.filter { $0.arguments.contains("install") }
        #expect(installs.count == 1)
        let installedInput = try #require(installs.first?.arguments.last)
        #expect(installedInput != fixture.file.path)
        #expect(!FileManager.default.fileExists(atPath: installedInput))
        #expect(try String(contentsOf: fixture.payload, encoding: .utf8) == "approved bytes")
        #expect(!fixture.runner.commands.contains(where: forbidden))
        if platform == .android { #expect(installs.first?.arguments.contains("-r") == true) }
    }

    @Test("older builds need a separate warning acknowledgement", arguments: [ProjectPlatform.ios, .android])
    func downgrade(_ platform: ProjectPlatform) async throws {
        let fixture = try AppFileFixture(platform: platform, installedBuild: "3")
        let proposed = await fixture.run(planOnly: true)
        let plan = try #require(proposed.operation.plan)
        #expect(plan.downgrade)
        #expect(plan.replacement)
        let refused = await fixture.run(approval: plan.id)
        #expect(refused.operation.state == "needs-approval")
        #expect(!fixture.runner.commands.contains(where: mutation))
        let accepted = await fixture.run(approval: plan.approval)
        #expect(accepted.exitCode == 0)
        #expect(!fixture.runner.commands.contains(where: forbidden))
    }

    @Test("project claims block direct installation under the same shared device lease")
    func projectConflict() async throws {
        let fixture = try AppFileFixture(platform: .ios)
        let proposed = await fixture.run(planOnly: true)
        let plan = try #require(proposed.operation.plan)
        let owner = LeaseOwner(operationId: "project-up", command: "up", project: "/other-project")
        let key = ResourceKey.device(.ios, fixture.device)
        let lease = try fixture.leases.acquire([key], owner: owner)
        try fixture.leases.record(ResourceClaim(device: key, platform: .ios, handle: fixture.device,
            appID: AppFileFixture.appID, owner: owner))
        lease.release()
        let result = await fixture.run(approval: plan.approval)
        #expect(result.exitCode == 1)
        #expect(result.operation.conflict?.owner == owner)
        #expect(!fixture.runner.commands.contains(where: mutation))
    }

    @Test("cancel after an installer change reobserves state and never deletes the app")
    func cancelledInstall() async throws {
        let fixture = try AppFileFixture(platform: .ios)
        let proposed = await fixture.run(planOnly: true)
        let plan = try #require(proposed.operation.plan)
        fixture.runner.cancelAfterInstall = true
        let result = await fixture.run(approval: plan.approval)
        #expect(result.exitCode == 130)
        #expect(result.operation.installation == "unconfirmed")
        #expect(result.operation.installed?.state == "installed")
        #expect(result.operation.installed?.build == "2")
        #expect(result.operation.launch == "not-requested")
        #expect(!fixture.runner.commands.contains(where: forbidden))
    }

    @Test("launch failure preserves a confirmed installation and has no delete-and-retry")
    func failedLaunch() async throws {
        let fixture = try AppFileFixture(platform: .android)
        let proposed = await fixture.run(planOnly: true)
        let plan = try #require(proposed.operation.plan)
        fixture.runner.failLaunch = true
        let result = await fixture.run(approval: plan.approval)
        #expect(result.exitCode == 1)
        #expect(result.operation.installation == "installed")
        #expect(result.operation.installed?.build == "2")
        #expect(result.operation.firstScreen == "unverified")
        #expect(!fixture.runner.commands.contains(where: forbidden))
    }

    private func mutation(_ command: ProcessCommand) -> Bool {
        command.arguments.contains("install") || command.arguments.contains("launch") || command.arguments.contains("start")
    }

    private func forbidden(_ command: ProcessCommand) -> Bool {
        ["uninstall", "clear", "reset", "terminate", "force-stop", "reverse", "kill-server", "boot", "create", "delete", "assemble", "build"].contains(where: command.arguments.contains)
            || ["gradlew", "flutter", "dart", "node", "npm", "pod", "emulator"].contains(command.executable)
            || command.executable == "xcodebuild" && command.arguments != ["-version"]
    }
}

private final class AppFileFixture {
    static let appID = "com.fixture.Local"
    let repo: FixtureRepo
    let file: URL
    let payload: URL
    let runner: AppFileRunner
    let leases: ResourceLeases
    let environment: [String: String]
    let device: String

    init(platform: ProjectPlatform, installedBuild: String? = nil) throws {
        repo = try FixtureRepo()
        leases = ResourceLeases(directory: repo.url("leases"))
        if platform == .ios {
            file = try repo.directory("Local.app")
            payload = try repo.write("Local.app/Program", "approved bytes")
            let plist: [String: Any] = ["CFBundlePackageType": "APPL", "CFBundleIdentifier": Self.appID,
                "CFBundleExecutable": "Program", "CFBundleVersion": "2", "CFBundleShortVersionString": "1.2",
                "CFBundleName": "Local", "MinimumOSVersion": "17.0", "CFBundleSupportedPlatforms": ["iPhoneSimulator"]]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: file.appendingPathComponent("Info.plist"))
            environment = [:]
            device = "FIXTURE-UDID"
        } else {
            file = try repo.write("Local.apk", "approved bytes")
            payload = file
            let sdk = try repo.directory("sdk")
            for name in ["build-tools/36.0.0/aapt2", "build-tools/36.0.0/apksigner", "platform-tools/adb"] {
                let tool = try repo.write("sdk/" + name, "fixture boundary; never executed")
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
            }
            let java = try repo.write("jdk/bin/java", "fixture boundary; never executed")
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: java.path)
            environment = ["ANDROID_HOME": sdk.path, "JAVA_HOME": repo.url("jdk").path]
            device = "avd:Fixture"
        }
        runner = AppFileRunner(file: file, payload: payload, platform: platform, installedBuild: installedBuild)
    }

    func run(inspectOnly: Bool = false, planOnly: Bool = false, approval: String? = nil, selected: Bool = true) async -> AppFileResult {
        await AppFileExecution.run(input: AppFileInput(file: file, environment: environment, device: selected ? device : nil),
            inspectOnly: inspectOnly, planOnly: planOnly, approvedPlanID: approval, runner: runner, leases: leases)
    }
}

/// The one ProcessRunner seam models platform observations; it never runs an SDK.
private final class AppFileRunner: ProcessRunner, @unchecked Sendable {
    static let badging = "package: name='com.fixture.Local' versionCode='2' versionName='1.2'\nsdkVersion:'23'\ntargetSdkVersion:'36'\nlaunchable-activity: name='com.fixture.Local.MainActivity'\nnative-code: 'arm64-v8a'\n"
    let file: URL
    let payload: URL
    let platform: ProjectPlatform
    private let lock = NSLock()
    private var recorded: [ProcessCommand] = []
    private var installedBuild: String?
    private var deviceLists = 0
    var mutateOriginalDuringStagedInspection = false
    var disconnectOnFinalRecheck = false
    var cancelAfterInstall = false
    var failLaunch = false
    var simulatorPlatform = "7"
    var badgingOverride: String?
    var installedInventoryOverride: String?
    var invalidSignature = false
    var requiresSplits = false
    var commands: [ProcessCommand] { lock.withLock { recorded } }

    init(file: URL, payload: URL, platform: ProjectPlatform, installedBuild: String?) {
        self.file = file
        self.payload = payload
        self.platform = platform
        self.installedBuild = installedBuild
    }

    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        try lock.withLock {
            recorded.append(command)
            let args = command.arguments
            func ok(_ output: String = "") -> ProcessResult { ProcessResult(terminationStatus: .exited(0), standardOutput: output, standardError: "") }
            if command.executable == "/usr/bin/lipo", args.first == "-archs" {
                if mutateOriginalDuringStagedInspection, args.last != payload.path {
                    try Data("changed during staging".utf8).write(to: payload)
                    mutateOriginalDuringStagedInspection = false
                }
                return ok("arm64")
            }
            if command.executable == "/usr/bin/otool", args.prefix(3) == ["-arch", "arm64", "-l"] {
                return ok("cmd LC_BUILD_VERSION\n platform \(simulatorPlatform)\n minos 17.0\n")
            }
            if command.description == "xcode-select -p" { return ok("/Applications/FixtureXcode.app/Contents/Developer\n") }
            if command.description == "xcodebuild -version" { return ok("Xcode 27.0\nBuild version 27A000\n") }
            if command.executable == "xcrun", args.prefix(3) == ["simctl", "list", "devices"] {
                deviceLists += 1
                if disconnectOnFinalRecheck && deviceLists >= 3 { return ok(#"{"devices":{}}"#) }
                return ok(#"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"name":"Fixture","udid":"FIXTURE-UDID","state":"Booted","isAvailable":true}]}}"#)
            }
            if command.executable == "xcrun", args == ["simctl", "spawn", "FIXTURE-UDID", "uname", "-m"] { return ok("arm64\n") }
            if command.executable == "xcrun", args == ["simctl", "listapps", "FIXTURE-UDID"] {
                let apps: [String: [String: String]] = installedBuild.map {
                    [AppFileFixture.appID: ["CFBundleVersion": $0, "CFBundleShortVersionString": "1.2", "Path": "/fixture/installed.app"]]
                } ?? [:]
                return ok(String(decoding: try PropertyListSerialization.data(fromPropertyList: apps, format: .xml, options: 0), as: UTF8.self))
            }
            if command.executable == "xcrun", args.prefix(3) == ["simctl", "install", "FIXTURE-UDID"] {
                installedBuild = "2"
                if cancelAfterInstall { throw CancellationError() }
                return ok()
            }
            if command.executable == "xcrun", args == ["simctl", "launch", "FIXTURE-UDID", AppFileFixture.appID] { return ok("\(AppFileFixture.appID): 42\n") }
            if command.executable == "xcrun", args == ["simctl", "spawn", "FIXTURE-UDID", "launchctl", "list"] {
                return ok("42\t0\tUIKitApplication:\(AppFileFixture.appID)[record]\n")
            }
            if command.executable.hasSuffix("/aapt2"), args.prefix(2) == ["dump", "badging"] {
                return ok(badgingOverride ?? Self.badging)
            }
            if command.executable.hasSuffix("/aapt2"), args.prefix(2) == ["dump", "xmltree"], args.suffix(2) == ["--file", "AndroidManifest.xml"] {
                return ok("E: manifest\n A: package=\"com.fixture.Local\"\n" + (requiresSplits ? " A: android:isSplitRequired(0x01010591)=(type 0x12)0xffffffff\n" : ""))
            }
            if command.executable.hasSuffix("/apksigner"), args.prefix(3) == ["verify", "--verbose", "--print-certs"] {
                if invalidSignature { return ProcessResult(terminationStatus: .exited(1), standardOutput: "", standardError: "fixture unsigned APK") }
                return ok("Verifies\nSigner #1 certificate SHA-256 digest: " + String(repeating: "a", count: 64) + "\n")
            }
            if command.executable.hasSuffix("/adb") {
                if args == ["devices", "-l"] { return ok("List of devices attached\nemulator-5554 device product:fixture\n") }
                if args == ["-s", "emulator-5554", "emu", "avd", "name"] { return ok("Fixture\nOK\n") }
                let prefix = ["-s", "emulator-5554", "shell"]
                if args == prefix + ["getprop", "ro.build.version.sdk"] { return ok("36\n") }
                if args == prefix + ["getprop", "ro.product.cpu.abilist"] { return ok("arm64-v8a\n") }
                if args == prefix + ["getprop", "sys.boot_completed"] { return ok("1\n") }
                if args == prefix + ["pm", "list", "packages", "--show-versioncode", AppFileFixture.appID] {
                    return ok(installedInventoryOverride ?? installedBuild.map { "package:\(AppFileFixture.appID) versionCode:\($0)\n" } ?? "")
                }
                if args == prefix + ["dumpsys", "package", AppFileFixture.appID] { return ok("  versionName=1.2\n  codePath=/fixture/installed.apk\n") }
                if args.prefix(4) == ["-s", "emulator-5554", "install", "-r"] { installedBuild = "2"; return ok("Success\n") }
                if args == prefix + ["am", "start", "-W", "-n", "com.fixture.Local/com.fixture.Local.MainActivity"] {
                    if failLaunch { return ProcessResult(terminationStatus: .exited(1), standardOutput: "", standardError: "fixture launch failure") }
                    return ok("Status: ok\n")
                }
                if args == prefix + ["pidof", AppFileFixture.appID] { return ok("42\n") }
            }
            throw FixtureMiss(command: command.description)
        }
    }

    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
        throw FixtureMiss(command: "unexpected detached child: " + command.description)
    }
}

import AndroidKit
import Core
import CryptoKit
import Foundation
import TestSupport
import Testing
@testable import EnvironmentKit

@Suite("Android Emulator shared setup")
struct AndroidEmulatorSetupTests {
    @Test("CLI and GUI common interface creates only an approved exact AVD and reuses it")
    func approvedCreation() async throws {
        let fixture = try await EmulatorSetupFixture()
        let plan = await PreparationExecution.run(input: fixture.sdk.input, planOnly: true, runner: fixture.runner)
        #expect(plan.plan?.steps.contains { $0.id == "android.virtual-device.create" && $0.kind == "install" } == true)
        #expect(fixture.runner.creator.commands.filter { $0.arguments.contains("create") }.isEmpty)
        let result = await PreparationExecution.run(input: fixture.sdk.input, approvedPlanID: try #require(plan.plan?.id), runner: fixture.runner, leases: fixture.leases)
        let diagnostic = try result.encoded(toolVersion: "fixture")
        #expect(result.operation.completed.contains("android.virtual-device.create"), Comment(rawValue: diagnostic))
        #expect(result.operation.androidResources?.first?.origin == .created)
        let created = try #require(result.operation.androidResources?.first)
        #expect(DeviceOriginStore(leases: fixture.leases).origin(platform: .android, id: created.name,
            directory: created.directory) == .runstir)
        let again = await PreparationExecution.run(input: fixture.sdk.input, planOnly: true, runner: fixture.runner)
        let reuseDiagnostic = try again.encoded(toolVersion: "fixture")
        #expect(again.plan?.androidResources?.first?.origin == .reused, Comment(rawValue: reuseDiagnostic))
        #expect(again.plan?.steps.allSatisfy { $0.id != "android.virtual-device.create" } == true)
        #expect(fixture.runner.creator.commands.filter { $0.arguments.contains("create") }.count == 1)
        #expect(try String(contentsOf: fixture.sdk.repo.url("sdk/keep"), encoding: .utf8) == "original SDK file")
    }

    @Test("changed device profile rejects old approval without creating an AVD")
    func changedProfile() async throws {
        let fixture = try await EmulatorSetupFixture()
        let plan = await PreparationExecution.run(input: fixture.sdk.input, planOnly: true, runner: fixture.runner)
        fixture.runner.profileSuffix = "    Tag : changed\n"
        let result = await PreparationExecution.run(input: fixture.sdk.input, approvedPlanID: try #require(plan.plan?.id), runner: fixture.runner, leases: fixture.leases)
        #expect(result.operation.state == "needs-approval")
        #expect(fixture.runner.creator.commands.filter { $0.arguments.contains("create") }.isEmpty)
    }

    @Test("hardware and boot property changes invalidate approval even when profile labels stay identical", arguments: ["hardware", "boot-props"])
    func changedProfileDefinition(section: String) async throws {
        let fixture = try await EmulatorSetupFixture()
        let path = "sdk/system-images/android-35/google_apis/arm64-v8a/devices.xml"
        try fixture.sdk.repo.write(path, "<devices><device id=\"pixel_7\"><\(section)>original</\(section)></device></devices>")
        let plan = await PreparationExecution.run(input: fixture.sdk.input, planOnly: true, runner: fixture.runner)
        try fixture.sdk.repo.write(path, "<devices><device id=\"pixel_7\"><\(section)>changed</\(section)></device></devices>")
        let result = await PreparationExecution.run(input: fixture.sdk.input, approvedPlanID: try #require(plan.plan?.id), runner: fixture.runner, leases: fixture.leases)
        #expect(result.operation.state == "needs-approval")
        #expect(fixture.runner.creator.commands.filter { $0.arguments.contains("create") }.isEmpty)
    }

    @Test("a profile payload change during creation prevents registration and preserves the changed catalog")
    func changedPayloadBeforeCommit() async throws {
        let fixture = try await EmulatorSetupFixture()
        fixture.runner.mutateCatalog = true
        let plan = await PreparationExecution.run(input: fixture.sdk.input, planOnly: true, runner: fixture.runner)
        let result = await PreparationExecution.run(input: fixture.sdk.input, approvedPlanID: try #require(plan.plan?.id), runner: fixture.runner, leases: fixture.leases)
        #expect(result.operation.state == "failed")
        #expect(fixture.runner.creator.commands.filter { $0.arguments.contains("create") }.count == 1)
        #expect(!FileManager.default.fileExists(atPath: fixture.sdk.repo.url("avds/Runstir_API_35_google_apis_arm64.ini").path))
        #expect(try String(contentsOf: fixture.image.appendingPathComponent("devices.xml"), encoding: .utf8) == "changed boot properties")
    }

    @Test("AVD home and device lease conflicts stop before creation", arguments: [false, true])
    func sharedLease(device: Bool) async throws {
        let fixture = try await EmulatorSetupFixture()
        let plan = await PreparationExecution.run(input: fixture.sdk.input, planOnly: true, runner: fixture.runner)
        let metadata = try #require(plan.plan?.steps.first { $0.id == "android.virtual-device.create" }?.installation)
        let key = try #require(metadata.resourceKeys.first { device ? $0.description.hasPrefix("device:") : $0 == metadata.resourceKey })
        let held = try fixture.leases.acquire([key], owner: LeaseOwner(operationId: "other", command: "setup", project: "other project"))
        defer { held.release() }
        let result = await PreparationExecution.run(input: fixture.sdk.input, approvedPlanID: try #require(plan.plan?.id), runner: fixture.runner, leases: fixture.leases)
        #expect(result.operation.conflict?.owner?.operationId == "other")
        #expect(fixture.runner.creator.commands.filter { $0.arguments.contains("create") }.isEmpty)
    }

    @Test("source changes during generation block commit and preserve image and source bytes")
    func sourceMutation() async throws {
        let fixture = try await EmulatorSetupFixture()
        fixture.runner.mutateSource = true
        let plan = await PreparationExecution.run(input: fixture.sdk.input, planOnly: true, runner: fixture.runner)
        let result = await PreparationExecution.run(input: fixture.sdk.input, approvedPlanID: try #require(plan.plan?.id), runner: fixture.runner, leases: fixture.leases)
        #expect(result.operation.state == "failed")
        #expect(result.operation.changedFiles.contains { $0.hasSuffix("settings.gradle.kts") })
        #expect(try String(contentsOf: fixture.sdk.repo.url("project/settings.gradle.kts"), encoding: .utf8) == "unexpected mutation")
        #expect(FileManager.default.fileExists(atPath: fixture.image.appendingPathComponent("system.img").path))
        #expect(!FileManager.default.fileExists(atPath: fixture.sdk.repo.url("avds/Runstir_API_35_google_apis_arm64.ini").path))
    }

    @Test("image installation is preserved and new AVD creation requires a newly inspected approval")
    func imageThenCreation() async throws {
        let fixture = try await EmulatorSetupFixture(imagePresent: false)
        let initial = await PreparationExecution.run(input: fixture.sdk.input, planOnly: true, runner: fixture.runner)
        #expect(initial.plan?.steps.contains { $0.installation?.package.hasPrefix("system-images;") == true && $0.kind == "install" } == true)
        #expect(initial.plan?.steps.allSatisfy { $0.id != "android.virtual-device.create" } == true)
        let installed = await PreparationExecution.run(input: fixture.sdk.input, approvedPlanID: try #require(initial.plan?.id), runner: fixture.runner, leases: fixture.leases)
        let diagnostic = try installed.encoded(toolVersion: "fixture")
        #expect(installed.operation.completed.contains("android.sdk.package.system-images;android-35;google_apis;arm64-v8a"), Comment(rawValue: diagnostic))
        #expect(fixture.runner.creator.commands.filter { $0.arguments.contains("create") }.isEmpty)
        #expect(FileManager.default.fileExists(atPath: fixture.image.appendingPathComponent("system.img").path))
        #expect(installed.plan?.id != initial.plan?.id)
        let ready = await PreparationExecution.run(input: fixture.sdk.input, approvedPlanID: try #require(installed.plan?.id), runner: fixture.runner, leases: fixture.leases)
        #expect(ready.operation.completed.contains("android.virtual-device.create"))
    }

    @Test("project requirements beyond the fixed image and old Emulators stay manual", arguments: [false, true])
    func unsupportedCandidate(oldEmulator: Bool) async throws {
        let fixture = try await EmulatorSetupFixture()
        if oldEmulator { try fixture.sdk.repo.write("sdk/emulator/source.properties", "Pkg.Revision=32.0.0\n") }
        else { fixture.runner.minimumSDK = 36 }
        let plan = await PreparationExecution.run(input: fixture.sdk.input, planOnly: true, runner: fixture.runner)
        #expect(plan.plan?.steps.contains { $0.id == "android.emulator.preparation" && $0.kind == "provider" } == true)
        #expect(plan.plan?.steps.allSatisfy { $0.id != "android.virtual-device.create" } == true)
        #expect(fixture.runner.creator.commands.filter { $0.arguments.contains("create") }.isEmpty)
        #expect(try String(contentsOf: fixture.sdk.repo.url("sdk/keep"), encoding: .utf8) == "original SDK file")
    }

    @Test("common cancellation preserves the image and no new registered AVD appears")
    func cancelCreation() async throws {
        let fixture = try await EmulatorSetupFixture()
        let plan = await PreparationExecution.run(input: fixture.sdk.input, planOnly: true, runner: fixture.runner)
        fixture.runner.creator.cancelled = true
        let result = await PreparationExecution.run(input: fixture.sdk.input, approvedPlanID: try #require(plan.plan?.id), runner: fixture.runner, leases: fixture.leases)
        #expect(result.exitCode == 130)
        #expect(result.operation.state == "cancelled")
        #expect(!FileManager.default.fileExists(atPath: DeviceOriginStore(leases: fixture.leases).file.path))
        #expect(FileManager.default.fileExists(atPath: fixture.image.appendingPathComponent("system.img").path))
        #expect(!FileManager.default.fileExists(atPath: fixture.sdk.repo.url("avds/Runstir_API_35_google_apis_arm64.ini").path))
    }

    @Test("an incomplete AVD directory blocks recreation and survives reinspection")
    func preservePartial() async throws {
        let fixture = try await EmulatorSetupFixture()
        let data = try fixture.sdk.repo.write("avds/Runstir_API_35_google_apis_arm64.avd/keep", "partial data")
        let plan = await PreparationExecution.run(input: fixture.sdk.input, planOnly: true, runner: fixture.runner)
        #expect(plan.plan?.steps.allSatisfy { $0.id != "android.virtual-device.create" } == true)
        #expect(plan.plan?.androidResources?.first?.state == "incomplete")
        #expect(plan.plan?.androidResources?.first?.origin == .unknown)
        let result = await PreparationExecution.run(input: fixture.sdk.input, approvedPlanID: try #require(plan.plan?.id), runner: fixture.runner, leases: fixture.leases)
        #expect(result.operation.completed.isEmpty)
        #expect(try String(contentsOf: data, encoding: .utf8) == "partial data")
        #expect(fixture.runner.creator.commands.filter { $0.arguments.contains("create") }.isEmpty)
    }

    @Test("a compatible existing API 36 AVD is reused instead of forcing the API 35 candidate")
    func reuseOtherImage() async throws {
        let fixture = try await EmulatorSetupFixture()
        fixture.runner.minimumSDK = 36
        let directory = try fixture.sdk.repo.directory("avds/Existing_API_36.avd")
        try fixture.sdk.repo.write("avds/Existing_API_36.ini", "path=\(directory.path)\ntarget=android-36\n")
        try fixture.sdk.repo.write("avds/Existing_API_36.avd/config.ini", "AvdId=Existing_API_36\nabi.type=arm64-v8a\nimage.sysdir.1=system-images/android-36/google_apis/arm64-v8a/\nhw.device.name=pixel_7\n")
        let image = "sdk/system-images/android-36/google_apis/arm64-v8a"
        try fixture.sdk.repo.write("\(image)/source.properties", "Pkg.Revision=1\nAndroidVersion.ApiLevel=36\nSystemImage.Abi=arm64-v8a\nSystemImage.TagId=google_apis\n")
        try fixture.sdk.repo.write("\(image)/system.img", "existing API 36 image")
        try fixture.sdk.repo.write("\(image)/package.xml", "<repository><license id=\"fixture-license\">\(SDKFixture.licenseText)</license><localPackage><uses-license ref=\"fixture-license\"/></localPackage></repository>")
        let plan = await PreparationExecution.run(input: fixture.sdk.input, planOnly: true, runner: fixture.runner)
        #expect(plan.plan?.androidResources?.first?.name == "Existing_API_36")
        #expect(plan.plan?.steps.allSatisfy { $0.kind != "install" } == true)
        #expect(fixture.runner.creator.commands.isEmpty)
        #expect(try String(contentsOf: fixture.sdk.repo.url("\(image)/system.img"), encoding: .utf8) == "existing API 36 image")
    }

    @Test("an AVD whose image content disappeared is preserved and never reported reusable")
    func missingImageContent() async throws {
        let fixture = try await EmulatorSetupFixture()
        let plan = await PreparationExecution.run(input: fixture.sdk.input, planOnly: true, runner: fixture.runner)
        _ = await PreparationExecution.run(input: fixture.sdk.input, approvedPlanID: try #require(plan.plan?.id), runner: fixture.runner, leases: fixture.leases)
        try FileManager.default.removeItem(at: fixture.image.appendingPathComponent("system.img"))
        let after = await PreparationExecution.run(input: fixture.sdk.input, planOnly: true, runner: fixture.runner)
        #expect(after.plan?.androidResources?.contains { $0.origin == .reused } != true)
        #expect(FileManager.default.fileExists(atPath: fixture.sdk.repo.url("avds/Runstir_API_35_google_apis_arm64.ini").path))
    }
}

private final class EmulatorSetupFixture {
    let sdk: SDKFixture
    let image: URL
    let runner: EmulatorSetupRunner
    let leases: ResourceLeases
    init(imagePresent: Bool = true) async throws {
        sdk = try await SDKFixture()
        image = sdk.repo.url("sdk/system-images/android-35/google_apis/arm64-v8a")
        leases = ResourceLeases(directory: sdk.repo.url("leases"))
        let license = "<repository><license id=\"fixture-license\">\(SDKFixture.licenseText)</license><localPackage><uses-license ref=\"fixture-license\"/></localPackage></repository>"
        for (path, revision, marker) in [("platforms/android-36", "2", "android.jar"), ("build-tools/35.0.0", "35.0.0", "aapt2"),
                                        ("cmdline-tools/23.0", "23.0", "bin/avdmanager")] {
            try sdk.repo.write("sdk/\(path)/\(marker)", "fixture")
            try sdk.repo.write("sdk/\(path)/source.properties", "Pkg.Revision=\(revision)\n")
            try sdk.repo.write("sdk/\(path)/package.xml", license)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sdk.repo.url("sdk/\(path)/\(marker)").path)
        }
        try await AVDCreationRunner.installToolPayload(in: sdk.repo)
        try sdk.repo.write("sdk/emulator/source.properties", "Pkg.Revision=37.2.12\n")
        let properties = "Pkg.Revision=9\nAndroidVersion.ApiLevel=35\nSystemImage.Abi=arm64-v8a\nSystemImage.TagId=google_apis\n"
        try sdk.repo.write("image-payload/arm64-v8a/source.properties", properties)
        try sdk.repo.write("image-payload/arm64-v8a/system.img", "synthetic image bytes")
        let archive = sdk.repo.url("image.zip")
        #expect(try await SystemProcessRunner().run(ProcessCommand("zip", ["-q", "-r", archive.path, "arm64-v8a"], workingDirectory: sdk.repo.url("image-payload"))).terminationStatus.isSuccess)
        let payload = try Data(contentsOf: archive)
        if imagePresent {
            try sdk.repo.write("sdk/system-images/android-35/google_apis/arm64-v8a/source.properties", properties)
            try sdk.repo.write("sdk/system-images/android-35/google_apis/arm64-v8a/system.img", "synthetic image bytes")
            try sdk.repo.write("sdk/system-images/android-35/google_apis/arm64-v8a/package.xml", license)
        }
        runner = EmulatorSetupRunner(sdk: sdk, payload: payload)
    }
}

private final class EmulatorSetupRunner: ProcessRunner, @unchecked Sendable {
    let sdk: SDKFixture
    let base: SDKPreparationRunner
    let payload: Data
    let creator = AVDCreationRunner()
    var profileSuffix = ""
    var mutateSource = false
    var mutateCatalog = false
    var minimumSDK = 24
    init(sdk: SDKFixture, payload: Data) { self.sdk = sdk; self.base = sdk.runner(); self.payload = payload }
    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        if command.executable == "/usr/bin/unzip" { return try await creator.run(command, onLine: onLine) }
        if command.description == sdk.modelCommand {
            let value = try await base.run(command, onLine: onLine)
            return .init(terminationStatus: value.terminationStatus,
                standardOutput: value.standardOutput.replacingOccurrences(of: "\"minSdk\":\"24\"", with: "\"minSdk\":\"\(minimumSDK)\""), standardError: value.standardError)
        }
        if command.description == "adb devices" {
            return .init(terminationStatus: .exited(0), standardOutput: "List of devices attached\n", standardError: "")
        }
        if command.executable == "/usr/bin/sandbox-exec", command.arguments.count >= 3, command.arguments[2].hasSuffix("/avdmanager") {
            if command.arguments.suffix(2) == ["list", "device"] {
                let result = try await creator.run(command, onLine: onLine)
                return .init(terminationStatus: result.terminationStatus, standardOutput: result.standardOutput + profileSuffix, standardError: result.standardError)
            }
            let result = try await creator.run(command, onLine: onLine)
            if mutateSource { try sdk.repo.write("project/settings.gradle.kts", "unexpected mutation") }
            if mutateCatalog { try sdk.repo.write("sdk/system-images/android-35/google_apis/arm64-v8a/devices.xml", "changed boot properties") }
            return result
        }
        if command.arguments == ["-list-avds"] {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: sdk.repo.url("avds").path))?.filter { $0.hasSuffix(".ini") }.map { String($0.dropLast(4)) } ?? []
            return .init(terminationStatus: .exited(0), standardOutput: names.sorted().joined(separator: "\n"), standardError: "")
        }
        if command.description == AndroidSDKRepositorySource.googleAPIs.command.description {
            let sha = Insecure.SHA1.hash(data: payload).map { String(format: "%02x", $0) }.joined()
            let xml = "<sys-img:sdk-sys-img xmlns:sys-img=\"http://schemas.android.com/sdk/android/repo/sys-img2/04\"><license id=\"fixture-license\">\(SDKFixture.licenseText)</license><remotePackage path=\"system-images;android-35;google_apis;arm64-v8a\"><type-details><api-level>35</api-level><tag><id>google_apis</id></tag><abi>arm64-v8a</abi></type-details><revision><major>9</major></revision><uses-license ref=\"fixture-license\"/><channelRef ref=\"channel-0\"/><dependencies><dependency path=\"emulator\"><min-revision><major>33</major><minor>1</minor><micro>24</micro></min-revision></dependency></dependencies><archives><archive><complete><size>\(payload.count)</size><checksum type=\"sha1\">\(sha)</checksum><url>fixture-image.zip</url></complete></archive></archives></remotePackage></sys-img:sdk-sys-img>"
            return .init(terminationStatus: .exited(0), standardOutput: xml, standardError: "")
        }
        if command.executable == "curl", command.arguments.last?.hasSuffix("fixture-image.zip") == true,
           let output = command.arguments.firstIndex(of: "--output") {
            try payload.write(to: URL(fileURLWithPath: command.arguments[output + 1]))
            return .init(terminationStatus: .exited(0), standardOutput: "", standardError: "")
        }
        return try await base.run(command, onLine: onLine)
    }
    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 { fatalError("setup must not boot") }
}

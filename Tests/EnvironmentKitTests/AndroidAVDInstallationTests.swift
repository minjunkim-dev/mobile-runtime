import AndroidKit
import Core
import CryptoKit
import Foundation
import TestSupport
import Testing
@testable import EnvironmentKit

@Suite("approved Android AVD creation")
struct AndroidAVDInstallationTests {
    @Test("creation pins identity, shares SDK and AVD leases, and never boots")
    func createAndReuse() async throws {
        let fixture = try await AVDFixture()
        let metadata = fixture.metadata
        try metadata.validate()
        #expect(metadata.resourceKeys.contains(.destination(fixture.request.sdkRoot)))
        #expect(metadata.resourceKeys.contains(.destination(fixture.request.avdHome)))
        #expect(metadata.resourceKeys.contains(.device(.android, "avd:Runstir_API_35")))
        let result = try await AndroidEmulatorPreparation.create(fixture.request, runner: fixture.runner) { _ in }
        #expect(result.androidResources.first?.origin == .created)
        #expect(!(try String(contentsOf: fixture.request.directory.appendingPathComponent("config.ini"), encoding: .utf8)).contains("AvdId="))
        #expect(try String(contentsOf: fixture.request.pointer, encoding: .utf8).contains(fixture.request.directory.path))
        #expect(!fixture.runner.commands.contains { $0.arguments.contains("--force") })
        #expect(fixture.runner.commands.filter { $0.arguments.contains("create") }.count == 1)
        let profileCommands = fixture.runner.commands.filter { $0.arguments.suffix(2) == ["list", "device"] }
        #expect(!profileCommands.isEmpty)
        #expect(profileCommands.allSatisfy {
            $0.environment["ANDROID_USER_HOME"]?.contains("runstir-android-profile-") == true
        })
        #expect(fixture.runner.commands.filter { $0.arguments.contains("create") || $0.arguments.suffix(2) == ["list", "device"] }.allSatisfy {
            $0.executable == "/usr/bin/sandbox-exec" && $0.arguments[1].contains("deny file-write*")
        })
        await #expect(throws: InstallationActionFailure.self) {
            try await AndroidEmulatorPreparation.create(fixture.request, runner: fixture.runner) { _ in }
        }
        #expect(fixture.runner.commands.filter { $0.arguments.contains("create") }.count == 1)
    }

    @Test("an optional AvdId must agree with the approved name")
    func mismatchedAvdID() async throws {
        let fixture = try await AVDFixture()
        fixture.runner.generatedAvdID = "another-device"
        await #expect(throws: InstallationActionFailure.self) {
            try await AndroidEmulatorPreparation.create(fixture.request, runner: fixture.runner) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.request.directory.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.request.pointer.path))
    }

    @Test("a matching optional AvdId remains valid")
    func matchingAvdID() async throws {
        let fixture = try await AVDFixture()
        fixture.runner.generatedAvdID = fixture.request.name
        let result = try await AndroidEmulatorPreparation.create(fixture.request, runner: fixture.runner) { _ in }
        #expect(result.androidResources.first?.origin == .created)
    }

    @Test("a payload change after staging permission is rejected before the create command")
    func changedBeforeCreation() async throws {
        let fixture = try await AVDFixture()
        let catalog = fixture.request.imageDirectory.appendingPathComponent("devices.xml")
        await #expect(throws: InstallationActionFailure.self) {
            try await AndroidEmulatorPreparation.create(fixture.request, runner: fixture.runner) { scratch in
                if !scratch.isEmpty { try Data("changed hardware".utf8).write(to: catalog) }
            }
        }
        #expect(fixture.runner.commands.filter { $0.arguments.contains("create") }.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.request.pointer.path))
        #expect(try String(contentsOf: catalog, encoding: .utf8) == "changed hardware")
    }

    @Test("overlapping SDK and AVD roots are rejected before host staging writes")
    func overlappingRoots() async throws {
        let fixture = try await AVDFixture(avdInsideSDK: true)
        await #expect(throws: InstallationActionFailure.self) {
            try await AndroidEmulatorPreparation.create(fixture.request, runner: fixture.runner) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.request.avdHome.path))
        #expect(!fixture.runner.commands.contains { $0.arguments.contains("create") })
    }

    @Test("existing pointer, directory and dangling links survive without invoking creation", arguments: ["pointer", "directory", "link"])
    func collisions(kind: String) async throws {
        let fixture = try await AVDFixture()
        switch kind {
        case "pointer": try Data("keep".utf8).write(to: fixture.request.pointer)
        case "directory": try FileManager.default.createDirectory(at: fixture.request.directory, withIntermediateDirectories: false)
        default: try FileManager.default.createSymbolicLink(atPath: fixture.request.pointer.path, withDestinationPath: fixture.repo.url("absent").path)
        }
        await #expect(throws: InstallationActionFailure.self) {
            try await AndroidEmulatorPreparation.create(fixture.request, runner: fixture.runner) { _ in }
        }
        #expect(fixture.runner.commands.isEmpty)
        #expect(FileManager.default.fileExists(atPath: fixture.request.directory.path)
            || FileManager.default.fileExists(atPath: fixture.request.pointer.path)
            || (try? FileManager.default.destinationOfSymbolicLink(atPath: fixture.request.pointer.path)) != nil)
    }

    @Test("failed and cancelled staging leave existing resources unchanged", arguments: [false, true])
    func interrupted(cancelled: Bool) async throws {
        let fixture = try await AVDFixture()
        fixture.runner.cancelled = cancelled
        fixture.runner.failed = !cancelled
        await #expect(throws: InstallationActionFailure.self) {
            try await AndroidEmulatorPreparation.create(fixture.request, runner: fixture.runner) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.request.directory.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.request.pointer.path))
        #expect(try String(contentsOf: fixture.repo.url("avds/keep"), encoding: .utf8) == "existing AVD data")
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.request.avdHome.path) == ["keep"])
    }

    @Test("a staged registration link is rejected without writing through it")
    func unsafeRegistration() async throws {
        let fixture = try await AVDFixture()
        let outside = fixture.repo.url("outside.ini")
        fixture.runner.pointerLinkTarget = outside
        await #expect(throws: InstallationActionFailure.self) {
            try await AndroidEmulatorPreparation.create(fixture.request, runner: fixture.runner) { _ in }
        }
        #expect(try String(contentsOf: outside, encoding: .utf8).contains(".runstir-avd-"))
        #expect(!FileManager.default.fileExists(atPath: fixture.request.directory.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.request.pointer.path))
    }
}

private final class AVDFixture {
    let repo: FixtureRepo
    let request: AndroidAVDRequest
    let runner = AVDCreationRunner()
    var metadata: InstallationMetadata {
        InstallationMetadata(package: "android.avd", revision: request.imageRevision,
            destination: request.directory, resourceRoot: request.avdHome, managed: .androidAVD(request), requiredFile: "config.ini")
    }
    init(avdInsideSDK: Bool = false) async throws {
        repo = try FixtureRepo()
        try repo.write("avds/keep", "existing AVD data")
        try repo.write("sdk/system-images/android-35/google_apis/arm64-v8a/system.img", "fixture image")
        let properties = "Pkg.Revision=9\nAndroidVersion.ApiLevel=35\nSystemImage.Abi=arm64-v8a\nSystemImage.TagId=google_apis\n"
        try repo.write("sdk/system-images/android-35/google_apis/arm64-v8a/source.properties", properties)
        let license = "Synthetic license"
        let hash = Insecure.SHA1.hash(data: Data(license.utf8)).map { String(format: "%02x", $0) }.joined()
        try repo.write("sdk/licenses/fixture-license", hash)
        try repo.write("sdk/system-images/android-35/google_apis/arm64-v8a/package.xml", "<repository><license id=\"fixture-license\">\(license)</license><localPackage><uses-license ref=\"fixture-license\"/></localPackage></repository>")
        try repo.write("sdk/cmdline-tools/23.0/source.properties", "Pkg.Revision=23.0\n")
        try repo.write("sdk/emulator/source.properties", "Pkg.Revision=37.2.12\n")
        for path in ["cmdline-tools/23.0", "emulator"] {
            try repo.write("sdk/\(path)/package.xml", "<repository><license id=\"fixture-license\">\(license)</license><localPackage><uses-license ref=\"fixture-license\"/></localPackage></repository>")
        }
        try repo.write("sdk/cmdline-tools/23.0/bin/avdmanager", "fixture")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: repo.url("sdk/cmdline-tools/23.0/bin/avdmanager").path)
        try await AVDCreationRunner.installToolPayload(in: repo)
        let profile = try await AndroidEmulatorEnvironment.profile("pixel_7", runner: runner, manager: repo.url("sdk/cmdline-tools/23.0/bin/avdmanager"),
            environment: ["ANDROID_HOME": repo.url("sdk").path, "ANDROID_SDK_ROOT": repo.url("sdk").path])
        runner.commands = []
        request = AndroidAVDRequest(name: "Runstir_API_35", sdkRoot: repo.url("sdk"), avdHome: repo.url(avdInsideSDK ? "sdk/avds" : "avds"),
            imagePackage: "system-images;android-35;google_apis;arm64-v8a", imageRevision: "9", imageMetadataSHA256: AndroidEmulatorEnvironment.imageDigest(in: repo.url("sdk/system-images/android-35/google_apis/arm64-v8a"))!,
            deviceProfile: "pixel_7", profileSHA256: AndroidEmulatorEnvironment.digest(Data(profile.utf8)),
            avdManager: repo.url("sdk/cmdline-tools/23.0/bin/avdmanager"), avdManagerRevision: "23.0",
            emulatorRevision: "37.2.12", repositorySHA256: String(repeating: "a", count: 64))
    }
}

final class AVDCreationRunner: ProcessRunner, @unchecked Sendable {
    static let profile = "id: 1 or \"pixel_7\"\n    Name: Pixel 7\n    OEM : Google\n"
    var commands: [ProcessCommand] = []
    var failed = false
    var cancelled = false
    var pointerLinkTarget: URL?
    var generatedAvdID: String?
    static func installToolPayload(in repo: FixtureRepo) async throws {
        for (name, manifest, resource) in [
            ("avdmanager-classpath.jar", "Manifest-Version: 1.0\r\nClass-Path: sdklib/profile.jar \r\n sdklib/dependency.jar\r\n\r\n", "launcher"),
            ("sdklib/profile.jar", "Manifest-Version: 1.0\nClass-Path: dependency.jar\n\n", "<devices><device id=\"pixel_7\"><hardware/><boot-props/></device></devices>"),
            ("sdklib/dependency.jar", "Manifest-Version: 1.0\n\n", "dependency")
        ] {
            let input = "tool-payload/\(name)"
            try repo.write("\(input)/META-INF/MANIFEST.MF", manifest)
            try repo.write("\(input)/devices.xml", resource)
            let output = repo.url("sdk/cmdline-tools/23.0/lib/\(name)")
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            #expect(try await SystemProcessRunner().run(ProcessCommand("zip", ["-q", "-r", output.path, "."], workingDirectory: repo.url(input))).terminationStatus.isSuccess)
        }
    }
    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        commands.append(command)
        if command.executable == "/usr/bin/unzip" { return try await SystemProcessRunner().run(command, onLine: onLine) }
        #expect(command.executable == "/usr/bin/sandbox-exec")
        #expect(command.arguments.first == "-p")
        let arguments = Array(command.arguments.dropFirst(3))
        if arguments == ["list", "device"] { return .init(terminationStatus: .exited(0), standardOutput: Self.profile, standardError: "") }
        let name = arguments[arguments.firstIndex(of: "--name")! + 1]
        let directory = URL(fileURLWithPath: arguments[arguments.firstIndex(of: "--path")! + 1])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Official createAvd writes no AvdId; duplication can add that optional key.
        let identity = generatedAvdID.map { "AvdId=\($0)\n" } ?? ""
        try Data("\(identity)abi.type=arm64-v8a\nimage.sysdir.1=system-images/android-35/google_apis/arm64-v8a/\nhw.device.name=pixel_7\n".utf8).write(to: directory.appendingPathComponent("config.ini"))
        let home = URL(fileURLWithPath: command.environment["ANDROID_AVD_HOME"]!)
        try Data("path=\(directory.path)\ntarget=android-35\n".utf8).write(to: home.appendingPathComponent("\(name).ini"))
        if let pointerLinkTarget {
            let pointer = home.appendingPathComponent("\(name).ini")
            try FileManager.default.moveItem(at: pointer, to: pointerLinkTarget)
            try FileManager.default.createSymbolicLink(at: pointer, withDestinationURL: pointerLinkTarget)
        }
        if cancelled { throw CancellationError() }
        return .init(terminationStatus: .exited(failed ? 1 : 0), standardOutput: "", standardError: failed ? "fixture creation failure" : "")
    }
    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 { fatalError("preparation must not boot") }
}

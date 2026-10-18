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
        let fixture = try AVDFixture()
        let metadata = fixture.metadata
        try metadata.validate()
        #expect(metadata.resourceKeys.contains(.destination(fixture.request.sdkRoot)))
        #expect(metadata.resourceKeys.contains(.destination(fixture.request.avdHome)))
        #expect(metadata.resourceKeys.contains(.device(.android, "avd:Runstir_API_35")))
        let result = try await AndroidEmulatorPreparation.create(fixture.request, runner: fixture.runner) { _ in }
        #expect(result.androidResources.first?.origin == .created)
        #expect(try String(contentsOf: fixture.request.pointer, encoding: .utf8).contains(fixture.request.directory.path))
        #expect(!fixture.runner.commands.contains { $0.arguments.contains("--force") })
        #expect(fixture.runner.commands.filter { $0.arguments.contains("create") }.count == 1)
        #expect(fixture.runner.commands.filter { $0.arguments == ["list", "device"] }.allSatisfy {
            $0.environment["ANDROID_USER_HOME"]?.contains("runstir-android-profile-") == true
        })
        await #expect(throws: InstallationActionFailure.self) {
            try await AndroidEmulatorPreparation.create(fixture.request, runner: fixture.runner) { _ in }
        }
        #expect(fixture.runner.commands.filter { $0.arguments.contains("create") }.count == 1)
    }

    @Test("existing pointer, directory and dangling links survive without invoking creation", arguments: ["pointer", "directory", "link"])
    func collisions(kind: String) async throws {
        let fixture = try AVDFixture()
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
        let fixture = try AVDFixture()
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
        let fixture = try AVDFixture()
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
    init() throws {
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
        request = AndroidAVDRequest(name: "Runstir_API_35", sdkRoot: repo.url("sdk"), avdHome: repo.url("avds"),
            imagePackage: "system-images;android-35;google_apis;arm64-v8a", imageRevision: "9", imageMetadataSHA256: AndroidEmulatorEnvironment.imageDigest(in: repo.url("sdk/system-images/android-35/google_apis/arm64-v8a"))!,
            deviceProfile: "pixel_7", profileSHA256: AndroidEmulatorEnvironment.digest(Data(AVDCreationRunner.profile.utf8)),
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
    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        commands.append(command)
        if command.arguments == ["list", "device"] { return .init(terminationStatus: .exited(0), standardOutput: Self.profile, standardError: "") }
        let name = command.arguments[command.arguments.firstIndex(of: "--name")! + 1]
        let directory = URL(fileURLWithPath: command.arguments[command.arguments.firstIndex(of: "--path")! + 1])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("AvdId=\(name)\navd.ini.displayname=\(name)\nabi.type=arm64-v8a\nimage.sysdir.1=system-images/android-35/google_apis/arm64-v8a/\nhw.device.name=pixel_7\n".utf8).write(to: directory.appendingPathComponent("config.ini"))
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

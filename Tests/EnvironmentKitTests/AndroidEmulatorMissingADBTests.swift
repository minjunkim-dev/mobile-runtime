import AndroidKit
import Core
import Foundation
import Testing
@testable import EnvironmentKit

@Suite("Android Emulator preparation without adb")
struct AndroidEmulatorMissingADBTests {
    @Test("multiple existing AVDs do not prevent planning a missing Platform-Tools installation")
    func missingADBWithExistingAVDs() async throws {
        let fixture = try await existingAVDs()
        try FileManager.default.removeItem(at: fixture.repo.url("sdk/platform-tools"))
        let runner = MissingADBPreparationRunner(fixture: fixture)
        print("review Foundation home: \(FileManager.default.homeDirectoryForCurrentUser.path)")
        print("review lease directory: \(ResourceLeases.user.directory.path)")
        let result = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: runner,
                                                   leases: ResourceLeases(directory: fixture.repo.url("leases")))
        let diagnostic = try result.encoded(toolVersion: "fixture")
        #expect(result.plan != nil, Comment(rawValue: diagnostic))
        #expect(result.plan?.steps.contains { $0.id == "android.sdk.package.platform-tools" && $0.kind == "install" } == true,
                Comment(rawValue: diagnostic))
        #expect(!runner.adbWasProbed)
        #expect(try String(contentsOf: fixture.repo.url("avds/ExistingOne.avd/config.ini"), encoding: .utf8).contains("AvdId=ExistingOne"))
        #expect(try String(contentsOf: fixture.repo.url("avds/ExistingTwo.avd/config.ini"), encoding: .utf8).contains("AvdId=ExistingTwo"))
        #expect(!FileManager.default.fileExists(atPath: fixture.repo.url("sdk/platform-tools").path))
    }

    @Test("incomplete Platform-Tools are preserved while the running probe stays deferred")
    func incompleteADB() async throws {
        let fixture = try await existingAVDs()
        try FileManager.default.removeItem(at: fixture.repo.url("sdk/platform-tools/adb"))
        let keep = try fixture.repo.write("sdk/platform-tools/keep", "incomplete existing package")
        let runner = MissingADBPreparationRunner(fixture: fixture)
        let result = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: runner,
                                                   leases: ResourceLeases(directory: fixture.repo.url("leases")))
        #expect(result.plan?.steps.contains { $0.id == "android.sdk.package.platform-tools" && $0.kind == "provider" } == true)
        #expect(!runner.adbWasProbed)
        #expect(try String(contentsOf: keep, encoding: .utf8) == "incomplete existing package")
    }

    @Test("ready Platform-Tools retain ambiguity and prefer the compatible running AVD", arguments: [false, true])
    func readyADB(running: Bool) async throws {
        let fixture = try await existingAVDs()
        let runner = MissingADBPreparationRunner(fixture: fixture)
        runner.adbAvailable = true
        runner.runningAVD = running ? "ExistingTwo" : nil
        let result = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: runner,
                                                   leases: ResourceLeases(directory: fixture.repo.url("leases")))
        let plan = try #require(result.plan)
        #expect(runner.adbWasProbed)
        #expect(!plan.steps.contains { $0.kind == "install" })
        if running {
            #expect(plan.androidResources?.first?.name == "ExistingTwo")
            #expect(plan.androidResources?.first?.origin == .reused)
        } else {
            #expect(plan.steps.contains { $0.id == "android.emulator.preparation" && $0.observed?.contains("Multiple compatible AVDs") == true })
            #expect(plan.androidResources?.isEmpty != false)
        }
    }

    private func existingAVDs() async throws -> SDKFixture {
        let fixture = try await SDKFixture()
        let license = "<repository><license id=\"fixture-license\">\(SDKFixture.licenseText)</license><localPackage><uses-license ref=\"fixture-license\"/></localPackage></repository>"
        for (path, revision, marker) in [("platforms/android-36", "2", "android.jar"), ("build-tools/35.0.0", "35.0.0", "aapt2")] {
            try fixture.repo.write("sdk/\(path)/source.properties", "Pkg.Revision=\(revision)\n")
            try fixture.repo.write("sdk/\(path)/package.xml", license)
            let file = try fixture.repo.write("sdk/\(path)/\(marker)", "fixture package")
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        let image = "sdk/system-images/android-35/google_apis/arm64-v8a"
        try fixture.repo.write("\(image)/source.properties", "Pkg.Revision=9\nAndroidVersion.ApiLevel=35\nSystemImage.Abi=arm64-v8a\nSystemImage.TagId=google_apis\n")
        try fixture.repo.write("\(image)/package.xml", license)
        try fixture.repo.write("\(image)/system.img", "existing fixture image")
        for name in ["ExistingOne", "ExistingTwo"] {
            let directory = try fixture.repo.directory("avds/\(name).avd")
            try fixture.repo.write("avds/\(name).ini", "path=\(directory.path)\ntarget=android-35\n")
            try fixture.repo.write("avds/\(name).avd/config.ini", "AvdId=\(name)\nabi.type=arm64-v8a\nimage.sysdir.1=system-images/android-35/google_apis/arm64-v8a/\nhw.device.name=pixel_7\n")
        }
        return fixture
    }

}

private final class MissingADBPreparationRunner: ProcessRunner, @unchecked Sendable {
    let base: SDKPreparationRunner
    let repository: String
    private let lock = NSLock()
    private var probed = false
    var adbAvailable = false
    var runningAVD: String?
    var adbWasProbed: Bool { lock.withLock { probed } }

    init(fixture: SDKFixture) {
        base = fixture.runner()
        let package = "<remotePackage path=\"platform-tools\"><revision><major>37</major><minor>0</minor><micro>1</micro></revision><uses-license ref=\"fixture-license\"/><channelRef ref=\"channel-0\"/><archives><archive><host-os>macosx</host-os><complete><size>123</size><checksum type=\"sha1\">1111111111111111111111111111111111111111</checksum><url>fixture-platform-tools.zip</url></complete></archive></archives></remotePackage>"
        repository = fixture.repository.replacingOccurrences(of: "</sdk:sdk-repository>", with: package + "</sdk:sdk-repository>")
    }

    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        if command.executable == "adb" {
            lock.withLock { probed = true }
            guard adbAvailable else { throw ProcessError.spawnFailed(command: command.description, underlying: CocoaError(.fileNoSuchFile)) }
            let output = command.arguments == ["devices"]
                ? "List of devices attached\n" + (runningAVD == nil ? "" : "emulator-5554\tdevice\n")
                : (runningAVD ?? "") + "\nOK\n"
            return ProcessResult(terminationStatus: .exited(0), standardOutput: output, standardError: "")
        }
        if command.arguments == ["-list-avds"] {
            return ProcessResult(terminationStatus: .exited(0), standardOutput: "ExistingOne\nExistingTwo\n", standardError: "")
        }
        if command.description == AndroidSDKRepository.command.description {
            return ProcessResult(terminationStatus: .exited(0), standardOutput: repository, standardError: "")
        }
        return try await base.run(command, onLine: onLine)
    }

    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
        fatalError("preparation inspection must not start a runtime")
    }
}

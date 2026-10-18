import Core
import CryptoKit
import Foundation
import TestSupport
import Testing
@testable import AndroidKit

@Suite("Android Emulator preparation")
struct AndroidEmulatorPreparationTests {
    @Test("system image metadata pins API, ABI, archive and Emulator dependency")
    func imageMetadata() throws {
        let repository = try AndroidSDKRepository(data: Data(imageXML.utf8), source: .googleAPIs)
        let package = try repository.package("system-images;android-35;google_apis;arm64-v8a")
        #expect(package.revision == "9")
        #expect(package.archiveURL.absoluteString == "https://dl.google.com/android/repository/sys-img/google_apis/image.zip")
        #expect(package.minimumEmulatorRevision == "33.1.24")
        #expect(package.systemImage?.apiLevel == 35)
        #expect(package.systemImage?.abi == "arm64-v8a")
        #expect(package.systemImage?.tag == "google_apis")
    }

    @Test("system image metadata rejects package/detail mismatch and missing dependency")
    func invalidImages() throws {
        for xml in [imageXML.replacingOccurrences(of: "<abi>arm64-v8a</abi>", with: "<abi>x86_64</abi>"),
                    imageXML.replacingOccurrences(of: "<dependencies><dependency path=\"emulator\"><min-revision><major>33</major><minor>1</minor><micro>24</micro></min-revision></dependency></dependencies>", with: ""),
                    imageXML.replacingOccurrences(of: "<major>33</major>", with: "")] {
            let repository = try AndroidSDKRepository(data: Data(xml.utf8), source: .googleAPIs)
            #expect(throws: DomainError.self) { try repository.package("system-images;android-35;google_apis;arm64-v8a") }
        }
        #expect(throws: DomainError.self) { try AndroidSDKRepository(data: Data(imageXML.utf8)) }
    }

    @Test("classpath paths cannot leave the exact tool payload", arguments: ["../outside.jar", "/outside.jar", "file:outside.jar", "sdklib//bad.jar", "sdklib/%2e%2e/bad.jar"])
    func unsafeClasspath(path: String) async throws {
        let fixture = try ProfilePayloadFixture(manifest: "Class-Path: \(path)\n\n")
        await #expect(throws: DomainError.self) { try await fixture.profile() }
        #expect(!fixture.runner.log.all.contains { $0.arguments == ["list", "device"] })
    }

    @Test("missing transitive classpath entries pin absence and newly added entries change approval")
    func missingReference() async throws {
        var fixture = try ProfilePayloadFixture(manifest: "Class-Path: sdklib/missing.jar\n\n")
        let before = try await fixture.profile()
        let jar = try fixture.repo.write("sdk/cmdline-tools/23.0/lib/sdklib/missing.jar", "new tool dependency")
        fixture.runner.responses[ProfilePayloadFixture.manifestCommand(jar)] = .ok("Manifest-Version: 1.0\n\n")
        #expect(try await fixture.profile() != before)
    }

    @Test("payload limits and missing root manifests fail closed", arguments: ["root", "jar-bytes", "manifest-bytes", "count", "duplicate", "duplicate-section", "missing-classpath"])
    func payloadLimits(kind: String) async throws {
        var fixture = try ProfilePayloadFixture()
        switch kind {
        case "root": try FileManager.default.removeItem(at: fixture.jar)
        case "jar-bytes":
            let handle = try FileHandle(forWritingTo: fixture.jar)
            defer { try? handle.close() }
            try handle.truncate(atOffset: 64 * 1024 * 1024 + 1)
        case "manifest-bytes": fixture.runner.responses[ProfilePayloadFixture.manifestCommand(fixture.jar)] = .ok(String(repeating: "x", count: 64 * 1024 + 1))
        case "duplicate": fixture.runner.responses[ProfilePayloadFixture.manifestCommand(fixture.jar)] = .ok("Class-Path: one.jar\nClass-Path: two.jar\n\n")
        case "duplicate-section": fixture.runner.responses[ProfilePayloadFixture.manifestCommand(fixture.jar)] = .ok("Class-Path: dependency.jar\n\nClass-Path: another.jar\n\n")
        case "missing-classpath": fixture.runner.responses[ProfilePayloadFixture.manifestCommand(fixture.jar)] = .ok("Manifest-Version: 1.0\n\n")
        default:
            let paths = (0..<128).map { "missing\($0).jar" }.joined(separator: " ")
            fixture.runner.responses[ProfilePayloadFixture.manifestCommand(fixture.jar)] = .ok("Class-Path: \(paths)\n\n")
        }
        await #expect(throws: DomainError.self) { try await fixture.profile() }
        #expect(!fixture.runner.log.all.contains { $0.arguments == ["list", "device"] })
    }

    @Test("tool and catalog links fail closed", arguments: [false, true])
    func payloadLinks(catalog: Bool) async throws {
        let fixture = try ProfilePayloadFixture(manifest: catalog ? "Class-Path: dependency.jar\n\n" : "Class-Path: linked.jar\n\n")
        let outside = try fixture.repo.write("outside", "preserve this file")
        let link: URL
        if catalog {
            link = fixture.repo.url("sdk/system-images/android-35/google_apis/arm64-v8a/devices.xml")
            try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        } else { link = fixture.jar.deletingLastPathComponent().appendingPathComponent("linked.jar") }
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        await #expect(throws: DomainError.self) { try await fixture.profile() }
        #expect(try String(contentsOf: outside, encoding: .utf8) == "preserve this file")
    }

    @Test("profile identity pins tool/catalog bytes and excludes image payload and unrelated tools")
    func precisePayload() async throws {
        let fixture = try ProfilePayloadFixture()
        let first = try await fixture.profile()
        try fixture.repo.write("sdk/system-images/android-35/google_apis/arm64-v8a/system.img", "unrelated image payload")
        try fixture.repo.write("sdk/cmdline-tools/23.0/lib/lint.jar", "unrelated tool")
        #expect(try await fixture.profile() == first)
        try fixture.repo.write("sdk/cmdline-tools/23.0/bin/avdmanager", "changed launcher")
        let changedTool = try await fixture.profile()
        #expect(changedTool != first)
        try fixture.repo.write("sdk/system-images/android-35/google_apis/arm64-v8a/package.xml", "changed catalog selection metadata")
        #expect(try await fixture.profile() != changedTool)
    }

    private var imageXML: String {
        """
        <sys-img:sdk-sys-img xmlns:sys-img="http://schemas.android.com/sdk/android/repo/sys-img2/04">
        <license id="fixture-license">Synthetic license</license>
        <remotePackage path="system-images;android-35;google_apis;arm64-v8a">
        <type-details><api-level>35</api-level><tag><id>google_apis</id></tag><abi>arm64-v8a</abi><abis>arm64-v8a</abis></type-details>
        <revision><major>9</major></revision><uses-license ref="fixture-license"/><channelRef ref="channel-0"/>
        <dependencies><dependency path="emulator"><min-revision><major>33</major><minor>1</minor><micro>24</micro></min-revision></dependency></dependencies>
        <archives><archive><complete><size>123</size><checksum type="sha1">1111111111111111111111111111111111111111</checksum><url>image.zip</url></complete></archive></archives>
        </remotePackage></sys-img:sdk-sys-img>
        """
    }
}

private struct ProfilePayloadFixture {
    let repo: FixtureRepo
    let manager: URL
    let jar: URL
    var runner: FakeProcessRunner
    init(manifest: String = "Class-Path: dependency.jar\n\n") throws {
        repo = try FixtureRepo()
        manager = try repo.write("sdk/cmdline-tools/23.0/bin/avdmanager", "fixture launcher")
        jar = try repo.write("sdk/cmdline-tools/23.0/lib/avdmanager-classpath.jar", "fixture tool JAR")
        let dependency = try repo.write("sdk/cmdline-tools/23.0/lib/dependency.jar", "fixture dependency")
        runner = FakeProcessRunner(responses: [Self.manifestCommand(jar): .ok(manifest),
            Self.manifestCommand(dependency): .ok("Manifest-Version: 1.0\n\n"),
            "\(manager.path) list device": .ok("id: 1 or \"pixel_7\"\n    Name: Pixel 7\n    OEM : Google\n")])
    }
    static func manifestCommand(_ jar: URL) -> String { "/usr/bin/unzip -p \(jar.path) META-INF/MANIFEST.MF" }
    func profile() async throws -> String {
        try await AndroidEmulatorEnvironment.profile("pixel_7", runner: runner, manager: manager,
            environment: ["ANDROID_HOME": repo.url("sdk").path, "ANDROID_SDK_ROOT": repo.url("sdk").path])
    }
}

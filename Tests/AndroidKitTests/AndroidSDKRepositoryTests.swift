import AndroidKit
import Core
import Foundation
import TestSupport
import Testing

@Suite("official Android SDK archive selection")
struct AndroidSDKRepositoryTests {
    @Test("schema 3 preserves base platform revision, archive identity, and exact license text")
    func exactArchive() throws {
        let repository = try AndroidSDKRepository(data: Data(xml().utf8))
        let package = try repository.package("platforms;android-36")
        #expect(package.revision == "2")
        #expect(package.archiveURL.absoluteString == "https://dl.google.com/android/repository/platform-36_r02.zip")
        #expect(package.size == 65878410)
        #expect(package.sha1 == "2c1a80dd4d9f7d0e6dd336ec603d9b5c55a6f576")
        let repo = try FixtureRepo()
        #expect(!package.licenseAccepted(in: repo.root))
        try repo.write("licenses/android-sdk-license", package.licenseSHA1 + "\n")
        #expect(package.licenseAccepted(in: repo.root))
        let local = String(decoding: package.localMetadata, as: UTF8.self)
        #expect(local.contains("localPackage"))
        #expect(!local.contains("<archives>"))
    }

    @Test("ambiguous duplicate paths, wrong extension paths, and old metadata cannot select an archive")
    func ambiguity() throws {
        let base = xml()
        let package = base.components(separatedBy: "<remotePackage")[1].components(separatedBy: "</remotePackage>")[0]
        let duplicate = base.replacingOccurrences(of: "</sdk:sdk-repository>", with: "<remotePackage" + package + "</remotePackage></sdk:sdk-repository>")
        let repository = try AndroidSDKRepository(data: Data(duplicate.utf8))
        #expect(throws: DomainError.self) { try repository.package("platforms;android-36") }
        let wrongExtension = base.replacingOccurrences(of: "<base-extension>true", with: "<base-extension>false")
        let extensions = try AndroidSDKRepository(data: Data(wrongExtension.utf8))
        #expect(throws: DomainError.self) { try extensions.package("platforms;android-36") }
        #expect(throws: DomainError.self) { try AndroidSDKRepository(data: Data(base.replacingOccurrences(of: "repository2/03", with: "repository2/01").utf8)) }
        #expect(throws: DomainError.self) { try AndroidSDKRepository(data: Data("<!DOCTYPE x><x/>".utf8)) }
    }

    @Test("host archive selection rejects x64 and preview-only inputs")
    func hostAndChannel() throws {
        for body in [xml().replacingOccurrences(of: "<archive>", with: "<archive><host-arch>x64</host-arch>"),
                     xml().replacingOccurrences(of: "channel-0", with: "channel-2")] {
            let repository = try AndroidSDKRepository(data: Data(body.utf8))
            #expect(throws: DomainError.self) { try repository.package("platforms;android-36") }
        }
    }

    private func xml() -> String {
        // Tiny schema fixture. Only package fields match the observed official response;
        // the license is synthetic and is never evidence of actual license acceptance.
        """
        <sdk:sdk-repository xmlns:sdk="http://schemas.android.com/sdk/android/repo/repository2/03" xmlns:common="http://schemas.android.com/repository/android/common/02" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
        <license id="android-sdk-license" type="text">Fixture license text</license>
        <remotePackage path="platforms;android-36"><type-details xsi:type="sdk:platformDetailsType"><api-level>36</api-level><extension-level>17</extension-level><base-extension>true</base-extension></type-details>
        <revision><major>2</major></revision><display-name>Android SDK Platform 36</display-name><uses-license ref="android-sdk-license"/><channelRef ref="channel-0"/>
        <archives><archive><complete><size>65878410</size><checksum type="sha1">2c1a80dd4d9f7d0e6dd336ec603d9b5c55a6f576</checksum><url>platform-36_r02.zip</url></complete></archive></archives></remotePackage>
        </sdk:sdk-repository>
        """
    }
}

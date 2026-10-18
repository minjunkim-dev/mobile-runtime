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

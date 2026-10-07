import Foundation
import TestSupport
import Testing
@testable import AndroidKit

@Suite("SDK license records")
struct AndroidSDKLicensesTests {
    @Test("exact text hash is required; an arbitrary existing license file is not acceptance", arguments: ["", "bad-hash", "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d\n"])
    func accepted(hash: String) throws {
        let repo = try FixtureRepo()
        try repo.write("sdk/package/package.xml", "<repository><license id='test-license'>hello</license><localPackage><uses-license ref='test-license'/></localPackage></repository>")
        if !hash.isEmpty { try repo.write("sdk/licenses/test-license", hash) }
        let result = AndroidSDKLicenses.check(packages: [repo.url("sdk/package")], sdk: repo.url("sdk"), command: "sdkmanager --licenses")
        #expect(hash.hasPrefix("aaf4") ? result == nil : result?.status == .error)
        if !hash.hasPrefix("aaf4") { #expect(result?.remediation?.command == "sdkmanager --licenses") }
        #expect(!FileManager.default.fileExists(atPath: repo.url("sdk/licenses/test-license").path) || !hash.isEmpty)
    }

    @Test("missing or malformed metadata cannot pass", arguments: ["", "<broken>", "<repository><localPackage><uses-license ref='../outside'/></localPackage></repository>"])
    func unavailable(xml: String) throws {
        let repo = try FixtureRepo()
        if !xml.isEmpty { try repo.write("sdk/package/package.xml", xml) }
        let result = AndroidSDKLicenses.check(packages: [repo.url("sdk/package")], sdk: repo.url("sdk"), command: nil)
        #expect(result?.status == .unknown)
    }
}

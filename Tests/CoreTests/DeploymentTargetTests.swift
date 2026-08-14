import Foundation
import TestSupport
import Testing

@testable import Core

/// The second evidence chain ADR-0003 names: `ios/Podfile.properties.json` →
/// the Podfile's own `platform :ios` literal → nothing. The matrix only carries the
/// framework's floor, so without this a repo asking for iOS 16.4 passes on a host
/// that only has 15.x — and the app does not even install.
@Suite("deployment target evidence chain")
struct DeploymentTargetTests {
    /// The whole chain runs at detection, so a scenario is just the files a repo has.
    private func target(podfile: String? = nil, properties: String? = nil) throws -> DeploymentTarget? {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies": {"react-native": "0.81.6"}}"#)
        if let podfile { try repo.write("ios/Podfile", podfile) }
        if let properties { try repo.write("ios/Podfile.properties.json", properties) }
        return ProjectAnchor.detect(from: repo.root)?.deploymentTarget
    }

    /// mattermost-mobile: the properties file carries the value the Podfile then
    /// reads, and it is higher than the matrix floor for its React Native version.
    @Test("Podfile.properties.json answers first")
    func propertiesFile() throws {
        let declared = try #require(try target(
                podfile: "platform :ios, podfile_properties['deploymentTarget'] || '16.4'",
                properties: #"{"buildReactNativeFromSource": "true", "deploymentTarget": "16.4"}"#
            )
        )

        #expect(declared.value == "16.4")
        #expect(declared.file == "ios/Podfile.properties.json")
    }

    /// joplin: a properties file exists but declares no deployment target, so the
    /// literal the Podfile falls back to is the answer. A parser that stopped at the
    /// file's existence would report nothing here.
    @Test("a properties file without the key falls through to the Podfile literal")
    func propertiesWithoutTheKey() throws {
        let declared = try #require(try target(
                podfile: "platform :ios, podfile_properties['ios.deploymentTarget'] || '15.1'",
                properties: #"{"newArchEnabled": "true"}"#
            )
        )

        #expect(declared.value == "15.1")
        #expect(declared.file == "ios/Podfile")
    }

    /// The Podfile names the key it reads, and Expo's generated one names
    /// `ios.deploymentTarget`. Reading a fixed key would miss the declaration and take
    /// the Podfile's fallback literal instead — which is by construction the lower
    /// value, so the under-read lands on `pass` and the app still will not install.
    @Test("the properties key is the one the Podfile actually reads")
    func propertiesKeyComesFromThePodfile() throws {
        let declared = try #require(try target(
            podfile: "platform :ios, podfile_properties['ios.deploymentTarget'] || '15.1'",
            properties: #"{"ios.deploymentTarget": "16.4"}"#
        ))

        #expect(declared.value == "16.4")
        #expect(declared.file == "ios/Podfile.properties.json")
    }

    /// The file is hand-edited as often as it is generated, and JSON has numbers.
    @Test("a numeric deployment target is still a declaration")
    func numericProperty() throws {
        let declared = try #require(try target(
            podfile: "platform :ios, podfile_properties['deploymentTarget'] || '15.1'",
            properties: #"{"deploymentTarget": 16.4}"#
        ))

        #expect(declared.value == "16.4")
    }

    /// A version inside a trailing comment is not a declaration. Believing it would
    /// raise the requirement on no evidence — a false `error`, which is worse than
    /// the miss it would be covering.
    @Test("a comment on the platform line is not evidence")
    func trailingComment() throws {
        let declared = try #require(try target(podfile: "platform :ios, '15.1' # was '18.0'\n"))

        #expect(declared.value == "15.1")
    }

    /// rainbow: no properties file at all, just the literal.
    @Test("a plain platform literal is the declaration")
    func plainLiteral() throws {
        let declared = try #require(try target(podfile: "platform :ios, '15.1'\n"))

        #expect(declared.value == "15.1")
        #expect(declared.file == "ios/Podfile")
    }

    /// The React Native template's default. It resolves inside CocoaPods, not here,
    /// so there is no declaration to read — silence, and the matrix floor stands.
    @Test("a platform line with no version literal declares nothing")
    func noLiteral() throws {
        #expect(try target(podfile: "platform :ios, min_ios_version_supported\n") == nil)
    }

    /// `platform :osx` is not this platform, and a commented-out line is not a
    /// declaration either.
    @Test("only the iOS platform line counts")
    func otherPlatformLines() throws {
        #expect(
            try target(
                podfile: """
                    # platform :ios, '18.0'
                    platform :osx, '14.0'
                    """
            ) == nil
        )
    }

    @Test("a project with no ios/ declares no deployment target")
    func noPodfile() throws {
        #expect(try target() == nil)
    }
}

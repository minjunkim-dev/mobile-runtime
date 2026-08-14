import Foundation
import TestSupport
import Testing

@testable import Core

/// The anchor is the project's single detection rule, so these scenarios are the
/// contract every project-scoped feature inherits.
@Suite("anchor detection")
struct ProjectAnchorTests {
    @Test("walks up from the working directory to the nearest package.json that has react-native")
    func findsAnchorAbove() throws {
        let repo = try FixtureRepo()
        try repo.write("app/package.json", #"{"dependencies": {"react-native": "0.76.5"}}"#)
        try repo.directory("app/src/screens")

        let anchor = try #require(ProjectAnchor.detect(from: repo.url("app/src/screens")))

        #expect(anchor.directory.path == repo.url("app").path)
        #expect(anchor.declaredReactNativeVersion == "0.76.5")
    }

    @Test("in a monorepo the nearest react-native package.json wins")
    func nearestPackageWins() throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies": {"react-native": "0.70.0"}}"#)
        try repo.write("packages/app/package.json", #"{"dependencies": {"react-native": "0.76.5"}}"#)

        let anchor = try #require(ProjectAnchor.detect(from: repo.url("packages/app")))

        #expect(anchor.directory.path == repo.url("packages/app").path)
        #expect(anchor.declaredReactNativeVersion == "0.76.5")
    }

    @Test("a package.json without react-native is not an anchor — the search keeps climbing")
    func skipsNonReactNativePackages() throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies": {"react-native": "0.76.5"}}"#)
        try repo.write("packages/tools/package.json", #"{"dependencies": {"typescript": "5.4.0"}}"#)

        let anchor = try #require(ProjectAnchor.detect(from: repo.url("packages/tools")))

        #expect(anchor.directory.path == repo.root.path)
    }

    @Test("no react-native anywhere above means no anchor — not an error")
    func noAnchor() throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies": {"typescript": "5.4.0"}}"#)

        #expect(ProjectAnchor.detect(from: repo.root) == nil)
    }

    @Test("the search stops at the git root")
    func stopsAtGitRoot() throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies": {"react-native": "0.76.5"}}"#)
        try repo.directory("checkout/.git")
        try repo.directory("checkout/src")

        #expect(ProjectAnchor.detect(from: repo.url("checkout/src")) == nil)
    }

    @Test("reads the installed react-native version, ios/ and node_modules from disk")
    func readsProjectFacts() throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies": {"react-native": "^0.76.0"}}"#)
        try repo.write("node_modules/react-native/package.json", #"{"version": "0.76.5"}"#)
        try repo.directory("ios")

        let anchor = try #require(ProjectAnchor.detect(from: repo.root))

        #expect(anchor.declaredReactNativeVersion == "^0.76.0")
        #expect(anchor.installedReactNativeVersion == "0.76.5")
        #expect(anchor.hasIOSDirectory)
        #expect(anchor.hasNodeModules)
    }

    @Test("a project with neither ios/ nor node_modules reports both as missing")
    func missingDirectories() throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies": {"react-native": "0.76.5"}}"#)

        let anchor = try #require(ProjectAnchor.detect(from: repo.root))

        #expect(anchor.installedReactNativeVersion == nil)
        #expect(anchor.hasIOSDirectory == false)
        #expect(anchor.hasNodeModules == false)
    }

    @Test("reads the Tier 1 declarations: node pin, engines and packageManager")
    func readsTier1Declarations() throws {
        let repo = try FixtureRepo()
        try repo.write(
            "package.json",
            """
            {
              "dependencies": {"react-native": "0.76.5"},
              "engines": {"node": ">=18"},
              "packageManager": "yarn@3.6.4+sha224.abcdef"
            }
            """
        )
        try repo.write(".nvmrc", "v20.11.1\n")

        let anchor = try #require(ProjectAnchor.detect(from: repo.root))

        #expect(anchor.nodePin?.value == "v20.11.1")
        #expect(anchor.nodePin?.file == ".nvmrc")
        #expect(anchor.nodeEngines == ">=18")
        // The corepack hash is not part of the version being compared.
        #expect(anchor.packageManager == PackageManagerRequirement(name: "yarn", version: "3.6.4"))
    }

    @Test("a .node-version file pins Node just like .nvmrc")
    func nodeVersionFileIsAPin() throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies": {"react-native": "0.76.5"}}"#)
        try repo.write(".node-version", "20.11.1")

        let anchor = try #require(ProjectAnchor.detect(from: repo.root))

        #expect(anchor.nodePin?.file == ".node-version")
    }

    @Test("unparsable package.json is not an anchor")
    func brokenManifest() throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", "{ this is not json")

        #expect(ProjectAnchor.detect(from: repo.root) == nil)
    }
}

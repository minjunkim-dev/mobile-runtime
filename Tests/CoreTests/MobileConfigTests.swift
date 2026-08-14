import Foundation
import TestSupport
import Testing

@testable import Core

private let packageJSON = #"{"dependencies": {"react-native": "0.81.0"}}"#

/// Lays down an anchor and runs discovery the way the CLI does: from a working
/// directory, with the anchor detected first.
private func discover(_ repo: FixtureRepo, from subdirectory: String? = nil) throws -> ConfigContext {
    let workingDirectory = subdirectory.map { repo.url($0) } ?? repo.root
    return ConfigContext.detect(
        anchor: ProjectAnchor.detect(from: workingDirectory),
        workingDirectory: workingDirectory
    )
}

@Suite("mobile.yml discovery")
struct MobileConfigDiscoveryTests {
    /// zero-config is the North Star: no file, nothing to say, no Check to show.
    @Test("no mobile.yml is silence — no parse, no checks")
    func absent() throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", packageJSON)

        let context = try discover(repo)

        #expect(context.file == nil)
        #expect(context.parse == nil)
        #expect(context.configuration == nil)
        #expect(context.checks().isEmpty)
    }

    @Test("reads mobile.yml next to the anchor")
    func nextToAnchor() throws {
        let repo = try FixtureRepo()
        try repo.write("packages/app/package.json", packageJSON)
        try repo.write("packages/app/mobile.yml", "ios:\n  scheme: MyApp\n")

        let context = try discover(repo, from: "packages/app")

        #expect(context.file?.path == repo.url("packages/app/mobile.yml").path)
        #expect(context.configuration?.scheme == "MyApp")
    }

    /// No upward search and no repo-root fallback: one anchor, one location.
    @Test("does not search upward for a mobile.yml above the anchor")
    func noUpwardSearch() throws {
        let repo = try FixtureRepo()
        try repo.write("packages/app/package.json", packageJSON)
        try repo.write("mobile.yml", "ios:\n  scheme: MyApp\n")

        let context = try discover(repo, from: "packages/app")

        #expect(context.file == nil)
        #expect(context.configuration == nil)
        #expect(context.strayFile == nil)
    }

    /// A file in the wrong place looks like it works. Silence is the worst answer.
    @Test("a mobile.yml below the anchor is a stray, not a configuration")
    func strayBelowAnchor() throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", packageJSON)
        try repo.write("ios/mobile.yml", "ios:\n  scheme: MyApp\n")

        let context = try discover(repo, from: "ios")

        #expect(context.file == nil)
        #expect(context.strayFile?.path == repo.url("ios/mobile.yml").path)
    }

    @Test("a mobile.yml with no React Native project anywhere above it is a stray")
    func strayWithoutAnchor() throws {
        let repo = try FixtureRepo()
        try repo.write("mobile.yml", "ios:\n  scheme: MyApp\n")

        let context = try discover(repo)

        #expect(context.anchorDirectory == nil)
        #expect(context.strayFile?.path == repo.url("mobile.yml").path)
    }

    @Test("mobile.yaml next to the anchor is found, and not read")
    func misspelled() throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", packageJSON)
        try repo.write("mobile.yaml", "ios:\n  scheme: MyApp\n")

        let context = try discover(repo)

        #expect(context.file == nil)
        #expect(context.misspelledFile?.path == repo.url("mobile.yaml").path)
        #expect(context.configuration == nil)
    }

    /// Dotfile variants are not part of the schema, so they are not a stray either.
    @Test("a dotfile variant is not recognised at all")
    func dotfileVariant() throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", packageJSON)
        try repo.write(".mobile.yml", "ios:\n  scheme: MyApp\n")

        let context = try discover(repo)

        #expect(context.file == nil)
        #expect(context.misspelledFile == nil)
        #expect(context.strayFile == nil)
    }
}

@Suite("mobile.yml parsing")
struct MobileConfigParsingTests {
    private func parse(_ yaml: String) throws -> MobileConfigParse {
        let repo = try FixtureRepo()
        try repo.write("package.json", packageJSON)
        try repo.write("mobile.yml", yaml)
        return try #require(try discover(repo).parse)
    }

    @Test("reads the four v0 fields")
    func allFields() throws {
        let parsed = try parse(
            """
            ios:
              device: iPhone 16 Pro
              scheme: MyApp
            overrides:
              xcode: "26"
              iosRuntime: 18.0
            """
        )

        guard case .parsed(let config, let unknown) = parsed else {
            Issue.record("expected a parse, got \(parsed)")
            return
        }
        #expect(config.device == "iPhone 16 Pro")
        #expect(config.scheme == "MyApp")
        #expect(config.xcode == MinimumVersion("26"))
        #expect(config.iosRuntime == MinimumVersion("18.0"))
        #expect(unknown.isEmpty)
    }

    /// Every field is optional; declaring one says nothing about the others.
    @Test("a partial file leaves the undeclared fields absent")
    func partial() throws {
        let parsed = try parse("overrides:\n  xcode: '26.1'\n")

        guard case .parsed(let config, _) = parsed else {
            Issue.record("expected a parse, got \(parsed)")
            return
        }
        #expect(config.device == nil)
        #expect(config.scheme == nil)
        #expect(config.iosRuntime == nil)
        #expect(config.xcode == MinimumVersion("26.1"))
    }

    @Test("an empty file parses to an empty configuration")
    func empty() throws {
        let parsed = try parse("# nothing declared yet\n")

        guard case .parsed(let config, let unknown) = parsed else {
            Issue.record("expected a parse, got \(parsed)")
            return
        }
        #expect(config == MobileConfig())
        #expect(unknown.isEmpty)
    }

    /// A silent fallback to inference would run with the override quietly void.
    @Test("broken YAML is invalid, and says where it broke")
    func syntaxError() throws {
        // A tab where YAML demands spaces — the indentation mistake everyone makes.
        let parsed = try parse("ios:\n\tdevice: iPhone 16 Pro\n")

        guard case .invalid(let message) = parsed else {
            Issue.record("expected an invalid file, got \(parsed)")
            return
        }
        #expect(message.contains("line 2"))
    }

    @Test("typo keys are collected rather than ignored")
    func unknownKeys() throws {
        let parsed = try parse(
            """
            ios:
              devise: iPhone 16 Pro
              scheme: MyApp
            overides:
              xcode: "26"
            """
        )

        guard case .parsed(let config, let unknown) = parsed else {
            Issue.record("expected a parse, got \(parsed)")
            return
        }
        #expect(unknown == ["ios.devise", "overides"])
        #expect(config.scheme == "MyApp")
        #expect(config.device == nil)
    }

    /// The schema shape is the boundary's documentation: an inferable value is
    /// only sayable under `overrides:`.
    @Test("an override written at the top level is an unknown key, not an override")
    func overrideAtTopLevel() throws {
        let parsed = try parse("xcode: \"26\"\n")

        guard case .parsed(let config, let unknown) = parsed else {
            Issue.record("expected a parse, got \(parsed)")
            return
        }
        #expect(unknown == ["xcode"])
        #expect(config.xcode == nil)
    }

    @Test("a section written as a scalar is invalid, not an unknown key")
    func sectionIsScalar() throws {
        let parsed = try parse("ios: iPhone 16 Pro\n")

        guard case .invalid(let message) = parsed else {
            Issue.record("expected an invalid file, got \(parsed)")
            return
        }
        #expect(message.contains("ios"))
    }

    @Test("an override that is not a version is invalid")
    func overrideNotAVersion() throws {
        let parsed = try parse("overrides:\n  xcode: latest\n")

        guard case .invalid(let message) = parsed else {
            Issue.record("expected an invalid file, got \(parsed)")
            return
        }
        #expect(message.contains("latest"))
    }
}

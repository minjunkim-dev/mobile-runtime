import Foundation
import TestSupport
import Testing

@testable import Core

private let packageJSON = #"{"dependencies": {"react-native": "0.81.0"}}"#

/// Through the engine, like every other Check scenario: `id`, `status` and the
/// presence of a remediation are the contract.
private func runConfigChecks(_ repo: FixtureRepo) async throws -> CheckResult {
    let context = ConfigContext.detect(
        anchor: ProjectAnchor.detect(from: repo.root),
        workingDirectory: repo.root
    )
    let report = await DoctorEngine(checks: context.checks()).run()
    return try #require(report.checks.first { $0.id == "config.syntax" })
}

@Suite("config.syntax")
struct ConfigSyntaxCheckTests {
    private func repo(_ files: (name: String, contents: String)...) throws -> FixtureRepo {
        let repo = try FixtureRepo()
        try repo.write("package.json", packageJSON)
        for file in files { try repo.write(file.name, file.contents) }
        return repo
    }

    @Test("passes and echoes the declarations back")
    func clean() async throws {
        let repo = try repo(("mobile.yml", "ios:\n  scheme: MyApp\noverrides:\n  xcode: \"26\"\n"))

        let check = try await runConfigChecks(repo)

        #expect(check.status == .pass)
        #expect(check.outcome.observed?.contains("ios.scheme: MyApp") == true)
        #expect(check.outcome.observed?.contains("overrides.xcode: 26") == true)
        #expect(check.outcome.source.tier == 3)
    }

    /// A file that does not parse is an error, not a quiet fallback to inference:
    /// proceeding would run with an override that may be void.
    @Test("errors, with the location, when the YAML does not parse")
    func broken() async throws {
        let repo = try repo(("mobile.yml", "ios:\n\tdevice: iPhone 16 Pro\n"))

        let check = try await runConfigChecks(repo)

        #expect(check.status == .error)
        #expect(check.outcome.observed?.contains("line 2") == true)
        #expect(check.outcome.remediation != nil)
    }

    @Test("warns about typo keys instead of ignoring them")
    func unknownKeys() async throws {
        let repo = try repo(("mobile.yml", "ios:\n  devise: iPhone 16 Pro\n"))

        let check = try await runConfigChecks(repo)

        #expect(check.status == .warning)
        #expect(check.outcome.observed == "unknown key: ios.devise")
        #expect(check.outcome.remediation?.summary.contains("ios.device") == true)
    }

    /// The file exists, reads correctly, and does nothing. Silence is the one
    /// answer that leaves the author with no way to find out.
    @Test("warns, with the rename, when the file is called mobile.yaml")
    func misspelledFileName() async throws {
        let repo = try repo(("mobile.yaml", "ios:\n  scheme: MyApp\n"))

        let check = try await runConfigChecks(repo)

        #expect(check.status == .warning)
        #expect(check.outcome.observed?.contains("mobile.yaml") == true)
        #expect(check.outcome.remediation?.command?.hasPrefix("mv ") == true)
        #expect(check.outcome.remediation?.command?.hasSuffix("mobile.yml") == true)
    }

    @Test("reports both a typo key and a stray mobile.yaml in one line")
    func bothComplaints() async throws {
        let repo = try repo(
            ("mobile.yml", "ios:\n  devise: iPhone 16 Pro\n"),
            ("mobile.yaml", "ios:\n  scheme: MyApp\n")
        )

        let check = try await runConfigChecks(repo)

        #expect(check.status == .warning)
        #expect(check.outcome.observed?.contains("ios.devise") == true)
        #expect(check.outcome.observed?.contains("mobile.yaml") == true)
    }
}

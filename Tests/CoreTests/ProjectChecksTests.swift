import Foundation
import TestSupport
import Testing

@testable import Core

/// Scenarios go through the engine, not through individual Checks: `id`, `status`
/// and the presence of remediation/reason are the contract, and nothing below them is.
private func runProjectChecks(
    _ repo: FixtureRepo,
    at subdirectory: String? = nil,
    node: FakeProcessRunner.Response? = .ok("v20.11.1\n"),
    packageManager: [String: FakeProcessRunner.Response] = [:],
    failures: [String: any Error] = [:]
) async -> (DoctorReport, FakeProcessRunner) {
    var responses = packageManager
    if let node { responses["node --version"] = node }
    let runner = FakeProcessRunner(responses: responses, failures: failures)

    let directory = subdirectory.map { repo.url($0) } ?? repo.root
    let checks = ProjectAnchor.detect(from: directory)?.checks(runner: runner) ?? []
    return (await DoctorEngine(checks: checks).run(), runner)
}

private func standardApp(_ repo: FixtureRepo, packageJSON: String) throws {
    try repo.write("package.json", packageJSON)
    try repo.write("node_modules/react-native/package.json", #"{"version": "0.76.5"}"#)
    try repo.directory("ios")
}

@Suite("project.detected")
struct ProjectDetectedCheckTests {
    @Test("passes with the installed react-native version when ios/ and node_modules are there")
    func healthyProject() async throws {
        let repo = try FixtureRepo()
        try standardApp(repo, packageJSON: #"{"dependencies": {"react-native": "^0.76.0"}}"#)

        let (report, _) = await runProjectChecks(repo)
        let check = try #require(report.checks.first { $0.id == "project.detected" })

        #expect(check.status == .pass)
        #expect(check.outcome.observed?.contains("0.76.5") == true)
        #expect(check.outcome.source.tier == 1)
        #expect(check.outcome.remediation == nil)
    }

    @Test("a project without ios/ is unknown with a reason, never an error")
    func managedProjectWithoutIOS() async throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies": {"react-native": "0.76.5"}}"#)
        try repo.write("node_modules/react-native/package.json", #"{"version": "0.76.5"}"#)

        let (report, _) = await runProjectChecks(repo)
        let check = try #require(report.checks.first { $0.id == "project.detected" })

        #expect(check.status == .unknown)
        #expect(check.outcome.reason?.contains("ios/") == true)
        #expect(report.exitCode == 0)
    }

    @Test("missing node_modules is surfaced as a warning that names the install command")
    func missingDependencies() async throws {
        let repo = try FixtureRepo()
        try repo.write(
            "package.json",
            #"{"dependencies": {"react-native": "0.76.5"}, "packageManager": "yarn@3.6.4"}"#
        )
        try repo.directory("ios")

        let (report, _) = await runProjectChecks(repo, packageManager: ["yarn --version": .ok("3.6.4\n")])
        let check = try #require(report.checks.first { $0.id == "project.detected" })

        #expect(check.status == .warning)
        #expect(check.outcome.observed?.contains("node_modules") == true)
        #expect(check.outcome.remediation?.command == "yarn install")
    }

    @Test("with neither ios/ nor node_modules, both facts survive into the one verdict")
    func neitherIOSNorDependencies() async throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies": {"react-native": "0.76.5"}}"#)

        let (report, _) = await runProjectChecks(repo)
        let check = try #require(report.checks.first { $0.id == "project.detected" })

        #expect(check.status == .unknown)
        #expect(check.outcome.reason?.contains("ios/") == true)
        // The missing dependencies are what later makes the Tier 2 checks unknown,
        // so the ios/ verdict must not swallow them.
        #expect(check.outcome.reason?.contains("node_modules") == true)
        #expect(check.outcome.observed?.contains("no node_modules") == true)
    }

    @Test("no anchor means no project checks at all — host checks stand alone")
    func noProjectDetected() async throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies": {"typescript": "5.4.0"}}"#)

        let (report, _) = await runProjectChecks(repo)

        #expect(ProjectAnchor.detect(from: repo.root) == nil)
        #expect(report.checks.isEmpty)
        #expect(report.exitCode == 0)
    }

    @Test("in a monorepo the checks describe the nearest app, not the workspace root")
    func monorepoAnchor() async throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies": {"react-native": "0.70.0"}}"#)
        try repo.write("packages/app/package.json", #"{"dependencies": {"react-native": "0.76.5"}}"#)
        try repo.write("packages/app/node_modules/react-native/package.json", #"{"version": "0.76.5"}"#)
        try repo.directory("packages/app/ios")

        let (report, _) = await runProjectChecks(repo, at: "packages/app")
        let check = try #require(report.checks.first { $0.id == "project.detected" })

        #expect(check.status == .pass)
        #expect(check.outcome.observed?.contains("0.76.5") == true)
    }
}

@Suite("node.version")
struct NodeVersionCheckTests {
    @Test("passes when the installed Node satisfies both the pin and engines")
    func satisfied() async throws {
        let repo = try FixtureRepo()
        try standardApp(
            repo,
            packageJSON: #"{"dependencies": {"react-native": "0.76.5"}, "engines": {"node": ">=18"}}"#
        )
        try repo.write(".nvmrc", "20\n")

        let (report, _) = await runProjectChecks(repo)
        let check = try #require(report.checks.first { $0.id == "node.version" })

        #expect(check.status == .pass)
        #expect(check.outcome.observed?.contains("20.11.1") == true)
    }

    @Test("a pin mismatch is a warning — team convention, not a contract")
    func pinMismatchWarns() async throws {
        let repo = try FixtureRepo()
        try standardApp(repo, packageJSON: #"{"dependencies": {"react-native": "0.76.5"}}"#)
        try repo.write(".nvmrc", "18.19.0\n")

        let (report, _) = await runProjectChecks(repo)
        let check = try #require(report.checks.first { $0.id == "node.version" })

        #expect(check.status == .warning)
        #expect(check.outcome.required?.contains("18.19.0") == true)
        #expect(check.outcome.remediation != nil)
        #expect(report.exitCode == 0)
    }

    @Test("an engines violation is an error — an explicit contract, broken")
    func enginesViolationErrors() async throws {
        let repo = try FixtureRepo()
        try standardApp(
            repo,
            packageJSON: #"{"dependencies": {"react-native": "0.76.5"}, "engines": {"node": ">=22"}}"#
        )

        let (report, _) = await runProjectChecks(repo)
        let check = try #require(report.checks.first { $0.id == "node.version" })

        #expect(check.status == .error)
        #expect(check.outcome.remediation != nil)
        #expect(report.exitCode == 1)
    }

    @Test("engines wins over the pin when both are broken")
    func enginesOutranksPin() async throws {
        let repo = try FixtureRepo()
        try standardApp(
            repo,
            packageJSON: #"{"dependencies": {"react-native": "0.76.5"}, "engines": {"node": "^18"}}"#
        )
        try repo.write(".nvmrc", "18.19.0\n")

        let (report, _) = await runProjectChecks(repo)
        let check = try #require(report.checks.first { $0.id == "node.version" })

        #expect(check.status == .error)
    }

    @Test("Node missing from PATH is a domain error, not a tool failure")
    func nodeNotInstalled() async throws {
        let repo = try FixtureRepo()
        try standardApp(repo, packageJSON: #"{"dependencies": {"react-native": "0.76.5"}}"#)

        let (report, _) = await runProjectChecks(
            repo,
            node: nil,
            failures: [
                "node --version": ProcessError.spawnFailed(
                    command: "node --version", underlying: FixtureMiss(command: "node --version")
                )
            ]
        )
        let check = try #require(report.checks.first { $0.id == "node.version" })

        #expect(check.status == .error)
        #expect(check.outcome.remediation != nil)
        #expect(report.hasToolFailure == false)
        #expect(report.exitCode == 1)
    }

    @Test("a timeout while probing Node is a tool failure")
    func nodeProbeTimeout() async throws {
        let repo = try FixtureRepo()
        try standardApp(repo, packageJSON: #"{"dependencies": {"react-native": "0.76.5"}}"#)

        let (report, _) = await runProjectChecks(
            repo,
            node: nil,
            failures: ["node --version": ProcessError.timedOut(command: "node --version", timeout: .seconds(15))]
        )
        let check = try #require(report.checks.first { $0.id == "node.version" })

        #expect(check.status == .unknown)
        #expect(report.hasToolFailure)
        #expect(report.exitCode == 2)
    }

    @Test("a Node probe that fails is unknown, and the reason quotes what the tool said")
    func nodeProbeFails() async throws {
        let repo = try FixtureRepo()
        try standardApp(repo, packageJSON: #"{"dependencies": {"react-native": "0.76.5"}}"#)

        let (report, _) = await runProjectChecks(
            repo,
            node: .failed(1, "No version is set for shim: node\n")
        )
        let check = try #require(report.checks.first { $0.id == "node.version" })

        #expect(check.status == .unknown)
        #expect(check.outcome.reason?.contains("No version is set for shim: node") == true)
    }

    @Test("a pin mobile cannot resolve is unknown with a reason, never a silent pass")
    func unresolvablePin() async throws {
        let repo = try FixtureRepo()
        try standardApp(repo, packageJSON: #"{"dependencies": {"react-native": "0.76.5"}}"#)
        try repo.write(".nvmrc", "lts/hydrogen\n")

        let (report, _) = await runProjectChecks(repo)
        let check = try #require(report.checks.first { $0.id == "node.version" })

        #expect(check.status == .unknown)
        #expect(check.outcome.reason?.contains("lts/hydrogen") == true)
    }

    @Test("an engines range mobile cannot read is unknown, not a pass")
    func unreadableEngines() async throws {
        let repo = try FixtureRepo()
        try standardApp(
            repo,
            packageJSON: #"{"dependencies": {"react-native": "0.76.5"}, "engines": {"node": "18 - 20"}}"#
        )

        let (report, _) = await runProjectChecks(repo)
        let check = try #require(report.checks.first { $0.id == "node.version" })

        #expect(check.status == .unknown)
        #expect(check.outcome.reason?.contains("18 - 20") == true)
    }

    @Test("an unreadable engines range says the pin went unjudged too")
    func unreadableEnginesMentionsThePin() async throws {
        let repo = try FixtureRepo()
        try standardApp(
            repo,
            packageJSON: #"{"dependencies": {"react-native": "0.76.5"}, "engines": {"node": "18 - 20"}}"#
        )
        try repo.write(".nvmrc", "18.19.0\n")

        let (report, _) = await runProjectChecks(repo)
        let check = try #require(report.checks.first { $0.id == "node.version" })

        #expect(check.status == .unknown)
        #expect(check.outcome.reason?.contains(".nvmrc") == true)
    }

    @Test("a project that declares nothing still gets a verdict on whether Node is installed")
    func noDeclarationsStillChecksInstallation() async throws {
        let repo = try FixtureRepo()
        try standardApp(repo, packageJSON: #"{"dependencies": {"react-native": "0.76.5"}}"#)

        let (report, _) = await runProjectChecks(repo)
        let check = try #require(report.checks.first { $0.id == "node.version" })

        #expect(check.status == .pass)
        #expect(check.outcome.required == "no Node version declared")
    }
}

@Suite("package-manager.version")
struct PackageManagerCheckTests {
    @Test("passes when the installed package manager matches the declaration")
    func matches() async throws {
        let repo = try FixtureRepo()
        try standardApp(
            repo,
            packageJSON: #"{"dependencies": {"react-native": "0.76.5"}, "packageManager": "yarn@3.6.4"}"#
        )

        let (report, runner) = await runProjectChecks(repo, packageManager: ["yarn --version": .ok("3.6.4\n")])
        let check = try #require(report.checks.first { $0.id == "package-manager.version" })

        #expect(check.status == .pass)
        #expect(runner.log.first(matching: "yarn --version") != nil)
    }

    @Test("a version mismatch is a warning that names the corepack fix")
    func versionMismatch() async throws {
        let repo = try FixtureRepo()
        try standardApp(
            repo,
            packageJSON: #"{"dependencies": {"react-native": "0.76.5"}, "packageManager": "pnpm@8.15.0"}"#
        )

        let (report, _) = await runProjectChecks(repo, packageManager: ["pnpm --version": .ok("9.1.0\n")])
        let check = try #require(report.checks.first { $0.id == "package-manager.version" })

        #expect(check.status == .warning)
        #expect(check.outcome.observed?.contains("9.1.0") == true)
        #expect(check.outcome.remediation?.command == "corepack use pnpm@8.15.0")
    }

    @Test("a declared package manager that is not installed is an error")
    func notInstalled() async throws {
        let repo = try FixtureRepo()
        try standardApp(
            repo,
            packageJSON: #"{"dependencies": {"react-native": "0.76.5"}, "packageManager": "yarn@3.6.4"}"#
        )

        let (report, _) = await runProjectChecks(
            repo,
            failures: [
                "yarn --version": ProcessError.spawnFailed(
                    command: "yarn --version", underlying: FixtureMiss(command: "yarn --version")
                )
            ]
        )
        let check = try #require(report.checks.first { $0.id == "package-manager.version" })

        #expect(check.status == .error)
        #expect(check.outcome.remediation?.command == "corepack enable")
    }

    @Test("no packageManager field means no check — nothing was declared to compare against")
    func undeclared() async throws {
        let repo = try FixtureRepo()
        try standardApp(repo, packageJSON: #"{"dependencies": {"react-native": "0.76.5"}}"#)

        let (report, _) = await runProjectChecks(repo)

        #expect(report.checks.contains { $0.id == "package-manager.version" } == false)
    }
}

@Suite("project checks in the --json document")
struct ProjectChecksJSONTests {
    @Test("every project check lands in checks[] under its stable id")
    func stableIDs() async throws {
        let repo = try FixtureRepo()
        try standardApp(
            repo,
            packageJSON: """
            {
              "dependencies": {"react-native": "0.76.5"},
              "engines": {"node": ">=18"},
              "packageManager": "yarn@3.6.4"
            }
            """
        )

        let (report, _) = await runProjectChecks(repo, packageManager: ["yarn --version": .ok("3.6.4\n")])
        let text = try DoctorJSONDocument(report: report, toolVersion: "9.9.9").encoded()
        let json = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let checks = try #require(json["checks"] as? [[String: Any]])

        #expect(
            checks.compactMap { $0["id"] as? String }
                == ["project.detected", "node.version", "package-manager.version"]
        )
        for check in checks {
            #expect((check["source"] as? [String: Any])?["tier"] as? Int == 1)
        }
    }
}

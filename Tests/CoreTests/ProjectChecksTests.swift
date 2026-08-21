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
    tools: [String: FakeProcessRunner.Response] = [:],
    failures: [String: any Error] = [:]
) async -> (DoctorReport, FakeProcessRunner) {
    var responses = tools
    if let node { responses["node --version"] = node }
    let runner = FakeProcessRunner(responses: responses, failures: failures)

    let directory = subdirectory.map { repo.url($0) } ?? repo.root
    let anchor = ProjectAnchor.detect(from: directory)
    let context = ConfigContext.detect(anchor: anchor, workingDirectory: directory)
    let checks = anchor?.checks(runner: runner, context: context) ?? []
    return (await DoctorEngine(checks: checks).run(), runner)
}

private func standardApp(_ repo: FixtureRepo, packageJSON: String) throws {
    try repo.write("package.json", packageJSON)
    try repo.write("node_modules/react-native/package.json", #"{"version": "0.76.5"}"#)
    try repo.directory("ios")
}

/// The same app one level down, for the scenarios where the anchor and the
/// workspace root are different places.
private func monorepoApp(_ repo: FixtureRepo, packageJSON: String) throws {
    try repo.write("packages/app/package.json", packageJSON)
    try repo.write("packages/app/node_modules/react-native/package.json", #"{"version": "0.81.6"}"#)
    try repo.directory("packages/app/ios")
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

    /// The miss #22 reports: stubbing `node_modules/react-native/package.json` was
    /// enough to be told the dependencies were installed, on a repo where `npm install`
    /// had never run. The Check judges that a React Native project is here — nothing
    /// it can see proves an install finished, so it no longer says one did.
    @Test("a pass never claims the dependencies are installed")
    func passClaimsOnlyDetection() async throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies": {"react-native": "0.83.9"}}"#)
        try repo.write("node_modules/react-native/package.json", #"{"version": "0.83.9"}"#)
        try repo.directory("ios")

        let (report, _) = await runProjectChecks(repo)
        let check = try #require(report.checks.first { $0.id == "project.detected" })

        #expect(check.status == .pass)
        #expect(check.outcome.required?.contains("dependencies") == false)
        #expect(check.outcome.observed?.contains("installed") == false)
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

        let (report, _) = await runProjectChecks(repo, tools: ["yarn --version": .ok("3.6.4\n")])
        let check = try #require(report.checks.first { $0.id == "project.detected" })

        #expect(check.status == .warning)
        #expect(check.outcome.observed?.contains("node_modules") == true)
        #expect(check.outcome.remediation?.command == "yarn install")
    }

    /// The lockfile is what picked `yarn` over `npm` and the workspace root over the
    /// sub-package. A command a user is asked to paste has to say what chose it.
    @Test("the install remediation names the lockfile it read the command from")
    func installCommandNamesItsEvidence() async throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", "{}")
        try repo.write("yarn.lock", "")
        try repo.write("packages/app/package.json", #"{"dependencies": {"react-native": "0.81.6"}}"#)
        try repo.directory("packages/app/ios")

        let (report, _) = await runProjectChecks(repo, at: "packages/app")
        let check = try #require(report.checks.first { $0.id == "project.detected" })

        #expect(check.status == .warning)
        #expect(check.outcome.remediation?.command == "cd \(repo.root.path) && yarn install")
        #expect(check.outcome.remediation?.summary.contains("yarn.lock") == true)
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

    /// joplin: the root asks for `>=22.12` and the sub-package for `>=20`. Reading
    /// only the anchor passed a host the workspace would have refused.
    @Test("the workspace root's engines binds the sub-package — the stricter range decides")
    func workspaceRootEngines() async throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"engines": {"node": ">=22.12"}}"#)
        try repo.write("yarn.lock", "")
        try monorepoApp(
            repo,
            packageJSON: #"{"dependencies": {"react-native": "0.81.6"}, "engines": {"node": ">=20"}}"#
        )

        let (report, _) = await runProjectChecks(repo, at: "packages/app")
        let check = try #require(report.checks.first { $0.id == "node.version" })

        #expect(check.status == .error)
        #expect(check.outcome.required?.contains(">=22.12") == true)
        #expect(check.outcome.source.origin == "workspace root package.json engines")
    }

    /// Reading the anchor first must not mean judging only the anchor: a range
    /// mobile cannot parse is one requirement going unanswered, not all of them.
    @Test("an unreadable range in the sub-package does not swallow the workspace root's contract")
    func unreadableAnchorEnginesKeepsTheRootJudged() async throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"engines": {"node": ">=22.12"}}"#)
        try repo.write("yarn.lock", "")
        try monorepoApp(
            repo,
            packageJSON: #"{"dependencies": {"react-native": "0.81.6"}, "engines": {"node": "18 - 20"}}"#
        )

        let (report, _) = await runProjectChecks(repo, at: "packages/app")
        let check = try #require(report.checks.first { $0.id == "node.version" })

        #expect(check.status == .error)
        #expect(check.outcome.required?.contains(">=22.12") == true)
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

    /// Nothing was declared about Node, so "is it installed" is the whole question and
    /// a Node that cannot answer leaves it open. The grade follows the requirement,
    /// and there is none (ADR-0004).
    @Test("a Node probe that fails is unknown when the project declared nothing")
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

    /// The same mute Node against a project that pinned one: a Node that cannot report
    /// its version cannot be checked against the pin and cannot run the build either.
    /// Absent and mute are the same state once something asks (ADR-0004).
    @Test("a Node probe that fails is an error once the project declared a version")
    func nodeProbeFailsWithDeclaration() async throws {
        let repo = try FixtureRepo()
        try standardApp(repo, packageJSON: #"{"dependencies": {"react-native": "0.76.5"}}"#)
        try repo.write(".nvmrc", "24.15.0\n")

        let (report, _) = await runProjectChecks(
            repo,
            node: .failed(1, "No version is set for shim: node\n"),
            tools: ["mise --version": .ok("2026.8.1\n")]
        )
        let check = try #require(report.checks.first { $0.id == "node.version" })

        #expect(check.status == .error)
        #expect(check.outcome.observed?.contains("No version is set for shim: node") == true)
        // node is on PATH — it answered — so "install Node" would be advice for a
        // different fault. What provides it is the thing to fix, and only the tool's
        // own words know which that is (#33).
        #expect(check.outcome.remediation?.command == nil)
        #expect(check.outcome.remediation?.summary.contains("reports no version") == true)
    }

    /// A range cannot be handed to a version manager, so this branch has a verdict
    /// but no command — the declaration still settles that the Node here is unusable.
    @Test("engines alone is enough of a declaration to make a mute Node an error")
    func nodeProbeFailsWithEngines() async throws {
        let repo = try FixtureRepo()
        try standardApp(
            repo, packageJSON: #"{"dependencies": {"react-native": "0.76.5"}, "engines": {"node": ">=20"}}"#
        )

        let (report, _) = await runProjectChecks(repo, node: .failed(1, "shim has no version\n"))
        let check = try #require(report.checks.first { $0.id == "node.version" })

        #expect(check.status == .error)
    }

    /// The dogfooding host ran mise and was told to run `nvm use`. The remediation
    /// names the manager this machine has, and mise leads the search, so a host with
    /// it installed gets its command whatever else is around.
    @Test("the pin remediation is the command this host can actually run")
    func pinRemediationFollowsTheHost() async throws {
        let repo = try FixtureRepo()
        try standardApp(repo, packageJSON: #"{"dependencies": {"react-native": "0.76.5"}}"#)
        try repo.write(".nvmrc", "24.15.0\n")

        let (report, _) = await runProjectChecks(
            repo, node: .ok("v24.19.0\n"), tools: ["mise --version": .ok("2026.8.1\n")]
        )
        let check = try #require(report.checks.first { $0.id == "node.version" })

        #expect(check.status == .warning)
        #expect(check.outcome.remediation?.command == "mise use node@24.15.0")
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

@Suite("unreadable tool remediation")
struct UnreadableToolRemediationTests {
    @Test("mise shims point every unreadable required tool at the committed config")
    func miseConfig() async throws {
        let repo = try FixtureRepo()
        try standardApp(
            repo,
            packageJSON: #"{"dependencies": {"react-native": "0.76.5"}, "packageManager": "yarn@3.6.4"}"#
        )
        try repo.write(".nvmrc", "20.11.1\n")
        try repo.write(".ruby-version", "3.2.2\n")
        try repo.write("Gemfile.lock", gemfileLock)
        try repo.write("mise.toml", "")

        let unreadable = FakeProcessRunner.Response.failed(1, "mise ERROR config is not trusted\n")
        let shims = "/Users/example/.local/share/mise/shims"
        let trackedConfig = "git -C \(repo.root.path) ls-files --error-unmatch -- mise.toml"
        let (report, runner) = await runProjectChecks(
            repo,
            node: unreadable,
            tools: [
                "which node": .ok("\(shims)/node\n"),
                "yarn --version": unreadable,
                "which yarn": .ok("\(shims)/yarn\n"),
                "pod --version": unreadable,
                "which pod": .ok("\(shims)/pod\n"),
                "ruby --version": unreadable,
                "which ruby": .ok("\(shims)/ruby\n"),
                trackedConfig: .ok("mise.toml\n"),
            ]
        )

        for id in ["node.version", "package-manager.version", "cocoapods.version", "ruby.version"] {
            let check = try #require(report.checks.first { $0.id == id })
            #expect(check.status == .error)
            #expect(check.outcome.remediation?.summary.contains("provided by mise") == true)
            #expect(check.outcome.remediation?.command == "mise trust .")
        }
        for executable in ["node", "yarn", "pod", "ruby"] {
            #expect(runner.log.all.count { $0.description == "which \(executable)" } == 1)
        }
    }

    @Test("mise without a tracked config recommends mise doctor")
    func miseWithoutTrackedConfig() async throws {
        let repo = try FixtureRepo()
        try standardApp(repo, packageJSON: #"{"dependencies": {"react-native": "0.76.5"}}"#)
        try repo.write("Gemfile.lock", gemfileLock)
        try repo.write(".tool-versions", "ruby 3.2.2\n")
        try repo.write("mise.toml", "")

        let (report, _) = await runProjectChecks(
            repo,
            tools: [
                "pod --version": .failed(1, "mise ERROR No version is set for shim: pod\n"),
                "which pod": .ok("/Users/example/.local/share/mise/shims/pod\n"),
            ]
        )
        let check = try #require(report.checks.first { $0.id == "cocoapods.version" })

        #expect(check.outcome.remediation?.summary.contains("provided by mise") == true)
        #expect(check.outcome.remediation?.command == "mise doctor")
    }

    @Test("mise trust quotes a config directory that contains spaces")
    func miseConfigPathWithSpaces() async throws {
        let repo = try FixtureRepo()
        let app = "app space"
        try repo.write(
            "\(app)/package.json",
            #"{"dependencies": {"react-native": "0.76.5"}}"#
        )
        try repo.write("\(app)/node_modules/react-native/package.json", #"{"version": "0.76.5"}"#)
        try repo.directory("\(app)/ios")
        try repo.write("\(app)/Gemfile.lock", gemfileLock)
        try repo.write("\(app)/mise.toml", "")

        let appDirectory = repo.url(app)
        let trackedConfig = "git -C \(appDirectory.path) ls-files --error-unmatch -- mise.toml"
        let (report, _) = await runProjectChecks(
            repo,
            at: "\(app)/ios",
            tools: [
                "pod --version": .failed(1, "mise ERROR config is not trusted\n"),
                "which pod": .ok("/Users/example/.local/share/mise/shims/pod\n"),
                trackedConfig: .ok("mise.toml\n"),
            ]
        )
        let check = try #require(report.checks.first { $0.id == "cocoapods.version" })

        #expect(check.outcome.remediation?.command == "mise trust '\(appDirectory.path)'")
    }

    @Test("an asdf shim names asdf without inventing a command")
    func asdfShim() async throws {
        let repo = try FixtureRepo()
        try standardApp(repo, packageJSON: #"{"dependencies": {"react-native": "0.76.5"}}"#)
        try repo.write("Gemfile.lock", gemfileLock)

        let (report, _) = await runProjectChecks(
            repo,
            tools: [
                "pod --version": .failed(1, "asdf rejected the shim\n"),
                "which pod": .ok("/Users/example/.asdf/shims/pod\n"),
            ]
        )
        let check = try #require(report.checks.first { $0.id == "cocoapods.version" })

        #expect(check.outcome.remediation?.summary.contains("provided by asdf") == true)
        #expect(check.outcome.remediation?.command == nil)
    }

    @Test("an unowned executable keeps the generic remediation")
    func unknownOwner() async throws {
        let repo = try FixtureRepo()
        try standardApp(repo, packageJSON: #"{"dependencies": {"react-native": "0.76.5"}}"#)
        try repo.write("Gemfile.lock", gemfileLock)

        let (report, _) = await runProjectChecks(
            repo,
            tools: [
                "pod --version": .failed(1, "pod failed\n"),
                "which pod": .ok("/usr/local/bin/pod\n"),
            ]
        )
        let check = try #require(report.checks.first { $0.id == "cocoapods.version" })

        #expect(
            check.outcome.remediation?.summary
                == "`pod` is on PATH but reports no version, so it cannot be used. "
                    + "Fix whatever provides it — the diagnostic above is what it said — then re-run mobile doctor."
        )
        #expect(check.outcome.remediation?.command == nil)
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

        let (report, runner) = await runProjectChecks(repo, tools: ["yarn --version": .ok("3.6.4\n")])
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

        let (report, _) = await runProjectChecks(repo, tools: ["pnpm --version": .ok("9.1.0\n")])
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

    /// `packageManager` is the declaration, so the requirement is settled the moment
    /// this Check exists. A manager that runs and reports nothing cannot install the
    /// dependencies (ADR-0004).
    @Test("a package manager that runs but reports nothing is an error")
    func packageManagerProbeFails() async throws {
        let repo = try FixtureRepo()
        try standardApp(
            repo,
            packageJSON: #"{"dependencies": {"react-native": "0.76.5"}, "packageManager": "yarn@3.6.4"}"#
        )

        let stderr = "mise ERROR error parsing config file: /tmp/app/mise.toml\r\n"
            + " \r\n"
            + "mise ERROR Config files in /tmp/app/mise.toml are not trusted.\r\n"
            + "Trust them with `mise trust`. See https://mise.jdx.dev/cli/trust.html\r\n"
            + "mise ERROR Run with --verbose for more information."
        let failure = FakeProcessRunner.Response(
            status: .exited(1),
            standardOutput: "yarn ERROR version probe failed\r\n",
            standardError: stderr
        )
        let (report, _) = await runProjectChecks(
            repo, tools: ["yarn --version": failure]
        )
        let check = try #require(report.checks.first { $0.id == "package-manager.version" })

        #expect(check.status == .error)
        #expect(check.outcome.observed?.contains("yarn ERROR version probe failed") == true)
        #expect(check.outcome.observed?.contains("error parsing config file: /tmp/app/mise.toml") == true)
        #expect(check.outcome.observed?.contains("Config files in /tmp/app/mise.toml are not trusted.") == true)
        #expect(check.outcome.observed?.contains("Trust them with `mise trust`") == true)
        #expect(check.outcome.observed?.contains("Run with --verbose for more information.") == true)
        #expect(check.outcome.observed?.contains("\r\n") == true)
        #expect(check.outcome.headline?.contains("\n") == false)
        #expect(check.outcome.remediation?.command == nil)
    }

    /// corepack does not carry bun, so `corepack enable` would be a line that cannot do
    /// what it says — the same fault #27 fixed for nvm and rbenv.
    @Test("bun gets no corepack command, because corepack does not manage it")
    func bunGetsNoCorepackCommand() async throws {
        let repo = try FixtureRepo()
        try standardApp(
            repo,
            packageJSON: #"{"dependencies": {"react-native": "0.76.5"}, "packageManager": "bun@1.1.30"}"#
        )

        let (report, _) = await runProjectChecks(repo)
        let check = try #require(report.checks.first { $0.id == "package-manager.version" })

        #expect(check.status == .error)
        #expect(check.outcome.remediation?.command == nil)
        #expect(check.outcome.remediation?.summary.contains("bun") == true)
    }

    @Test("no packageManager field means no check — nothing was declared to compare against")
    func undeclared() async throws {
        let repo = try FixtureRepo()
        try standardApp(repo, packageJSON: #"{"dependencies": {"react-native": "0.76.5"}}"#)

        let (report, _) = await runProjectChecks(repo)

        #expect(report.checks.contains { $0.id == "package-manager.version" } == false)
    }

    /// The monorepo silence from #21: the root declared the manager, the anchor did
    /// not, and the Check disappeared on a host that had no yarn at all.
    @Test("a workspace root declaration keeps the check alive in a sub-package")
    func declaredAtWorkspaceRoot() async throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"packageManager": "yarn@4.16.0"}"#)
        try repo.write("yarn.lock", "")
        try monorepoApp(repo, packageJSON: #"{"dependencies": {"react-native": "0.81.6"}}"#)

        let (report, _) = await runProjectChecks(
            repo,
            at: "packages/app",
            failures: [
                "yarn --version": ProcessError.spawnFailed(
                    command: "yarn --version", underlying: FixtureMiss(command: "yarn --version")
                )
            ]
        )
        let check = try #require(report.checks.first { $0.id == "package-manager.version" })

        #expect(check.status == .error)
        #expect(check.outcome.required?.contains("yarn 4.16.0") == true)
        #expect(check.outcome.source.origin == "workspace root package.json packageManager")
    }
}

/// A real RN `Gemfile.lock`: the locked version sits under `specs:`, while
/// `DEPENDENCIES` repeats the name with the range the Gemfile asked for.
private let gemfileLock = """
GEM
  remote: https://rubygems.org/
  specs:
    CFPropertyList (3.0.6)
    activesupport (7.1.3)
    cocoapods (1.15.2)
      addressable (~> 2.8)
      cocoapods-core (= 1.15.2)
    cocoapods-core (1.15.2)

PLATFORMS
  ruby

DEPENDENCIES
  activesupport (>= 6.1.7.5, != 7.1.0)
  cocoapods (>= 1.13, != 1.15.0, != 1.15.1)

BUNDLED WITH
   2.5.6
"""

@Suite("cocoapods.version")
struct CocoaPodsVersionCheckTests {
    @Test("passes when the installed CocoaPods is the one Gemfile.lock locks")
    func matchesLock() async throws {
        let repo = try FixtureRepo()
        try standardApp(repo, packageJSON: #"{"dependencies": {"react-native": "0.76.5"}}"#)
        try repo.write("Gemfile.lock", gemfileLock)

        let (report, _) = await runProjectChecks(
            repo, tools: ["pod --version": .ok("1.15.2\n")]
        )
        let check = try #require(report.checks.first { $0.id == "cocoapods.version" })

        #expect(check.status == .pass)
        #expect(check.outcome.source.tier == 1)
    }

    @Test("a version other than the locked one is a warning — Podfile.lock gets rewritten")
    func versionMismatch() async throws {
        let repo = try FixtureRepo()
        try standardApp(repo, packageJSON: #"{"dependencies": {"react-native": "0.76.5"}}"#)
        try repo.write("Gemfile.lock", gemfileLock)

        let (report, _) = await runProjectChecks(
            repo, tools: ["pod --version": .ok("1.14.3\n")]
        )
        let check = try #require(report.checks.first { $0.id == "cocoapods.version" })

        #expect(check.status == .warning)
        #expect(check.outcome.observed?.contains("1.14.3") == true)
        #expect(check.outcome.required?.contains("1.15.2") == true)
        #expect(check.outcome.remediation != nil)
    }

    @Test("CocoaPods missing while the project locks it is an error")
    func notInstalled() async throws {
        let repo = try FixtureRepo()
        try standardApp(repo, packageJSON: #"{"dependencies": {"react-native": "0.76.5"}}"#)
        try repo.write("Gemfile.lock", gemfileLock)

        let (report, _) = await runProjectChecks(repo)
        let check = try #require(report.checks.first { $0.id == "cocoapods.version" })

        #expect(check.status == .error)
        #expect(check.outcome.remediation != nil)
        #expect(report.exitCode == 1)
    }

    @Test("no gem files at all means no check — absence, not a quiet pass")
    func withoutGemFiles() async throws {
        let repo = try FixtureRepo()
        try standardApp(repo, packageJSON: #"{"dependencies": {"react-native": "0.76.5"}}"#)

        let (report, runner) = await runProjectChecks(repo)

        #expect(report.checks.contains { $0.id == "cocoapods.version" } == false)
        #expect(runner.log.first(matching: "pod --version") == nil)
    }

    /// joplin: a `Gemfile` asking for CocoaPods, no lock committed. The Check used to
    /// vanish, which is the silence ADR-0004 forbids — `gem 'cocoapods'` is a
    /// declaration, so whether it is installed is a settled question.
    @Test("a Gemfile that declares cocoapods requires it even with no lock")
    func gemfileWithoutLock() async throws {
        let repo = try FixtureRepo()
        try standardApp(repo, packageJSON: #"{"dependencies": {"react-native": "0.76.5"}}"#)
        try repo.write("Gemfile", "source 'https://rubygems.org'\ngem 'cocoapods'\n")

        let (report, _) = await runProjectChecks(repo)
        let check = try #require(report.checks.first { $0.id == "cocoapods.version" })

        #expect(check.status == .error)
        #expect(check.outcome.source.origin == "Gemfile")
        #expect(check.outcome.remediation != nil)
    }

    @Test("a declared but unlocked CocoaPods passes on any installed version")
    func gemfileWithoutLockInstalled() async throws {
        let repo = try FixtureRepo()
        try standardApp(repo, packageJSON: #"{"dependencies": {"react-native": "0.76.5"}}"#)
        try repo.write("Gemfile", "gem \"cocoapods\", \"~> 1.15\"\n")

        let (report, _) = await runProjectChecks(
            repo, tools: ["bundle exec pod --version": .ok("1.15.2\n")]
        )
        let check = try #require(report.checks.first { $0.id == "cocoapods.version" })

        #expect(check.status == .pass)
        #expect(check.outcome.observed?.contains("1.15.2") == true)
    }

    /// `cocoapods-core` is a different gem, and a project that manages gems without
    /// asking for CocoaPods has not asked for it.
    @Test("a Gemfile that never names cocoapods confirms no requirement")
    func gemfileWithoutCocoaPods() async throws {
        let repo = try FixtureRepo()
        try standardApp(repo, packageJSON: #"{"dependencies": {"react-native": "0.76.5"}}"#)
        try repo.write("Gemfile", "gem 'fastlane'\ngem 'cocoapods-core'\n")

        let (report, _) = await runProjectChecks(repo)
        let check = try #require(report.checks.first { $0.id == "cocoapods.version" })

        #expect(check.status == .unknown)
        #expect(report.exitCode == 0)
    }

    @Test("a Gemfile.lock that locks no CocoaPods still judges whether it is installed")
    func lockWithoutCocoaPods() async throws {
        let repo = try FixtureRepo()
        try standardApp(repo, packageJSON: #"{"dependencies": {"react-native": "0.76.5"}}"#)
        try repo.write("Gemfile.lock", "GEM\n  specs:\n    xcodeproj (1.24.0)\n")

        let (report, _) = await runProjectChecks(
            repo, tools: ["pod --version": .ok("1.15.2\n")]
        )
        let check = try #require(report.checks.first { $0.id == "cocoapods.version" })

        #expect(check.status == .pass)
        #expect(check.outcome.observed?.contains("1.15.2") == true)
    }

    @Test("a lock that never asked for CocoaPods does not error over it missing")
    func lockWithoutCocoaPodsAndNotInstalled() async throws {
        let repo = try FixtureRepo()
        try standardApp(repo, packageJSON: #"{"dependencies": {"react-native": "0.76.5"}}"#)
        try repo.write("Gemfile.lock", "GEM\n  specs:\n    fastlane (2.219.0)\n")

        let (report, _) = await runProjectChecks(repo)
        let check = try #require(report.checks.first { $0.id == "cocoapods.version" })

        #expect(check.status == .unknown)
        #expect(check.outcome.reason?.contains("Gemfile.lock") == true)
        #expect(report.exitCode == 0)
    }

    @Test("a locked version mobile cannot resolve is unknown with a reason, never a silent pass")
    func unresolvableLockedVersion() async throws {
        let repo = try FixtureRepo()
        try standardApp(repo, packageJSON: #"{"dependencies": {"react-native": "0.76.5"}}"#)
        try repo.write("Gemfile.lock", "GEM\n  specs:\n    cocoapods (1.16.0.beta.1)\n")

        let (report, _) = await runProjectChecks(
            repo, tools: ["pod --version": .ok("1.15.2\n")]
        )
        let check = try #require(report.checks.first { $0.id == "cocoapods.version" })

        #expect(check.status == .unknown)
        #expect(check.outcome.reason?.contains("1.16.0.beta.1") == true)
    }

    /// mattermost-mobile on the dogfooding host: `pod` was on PATH as a mise shim
    /// with no version set, so it ran and said nothing. A tool that cannot report a
    /// version cannot run `pod install` either — with the requirement settled, that
    /// is an error, not a shrug (ADR-0004). The tool's own words carry the cause.
    @Test("a pod that runs but reports nothing is an error when the project locks it")
    func probeFails() async throws {
        let repo = try FixtureRepo()
        try standardApp(repo, packageJSON: #"{"dependencies": {"react-native": "0.76.5"}}"#)
        try repo.write("Gemfile.lock", gemfileLock)

        let (report, _) = await runProjectChecks(
            repo,
            tools: [
                "pod --version": .failed(
                    1, "mise ERROR No version is set for shim: pod\n"
                )
            ]
        )
        let check = try #require(report.checks.first { $0.id == "cocoapods.version" })

        #expect(check.status == .error)
        #expect(check.outcome.observed?.contains("No version is set for shim") == true)
        #expect(check.outcome.remediation?.command == nil)
    }

    /// Same failure, no requirement behind it: the grade follows the requirement, not
    /// the reason the measurement failed.
    @Test("the same unreadable pod is unknown when nothing asked for CocoaPods")
    func probeFailsWithoutRequirement() async throws {
        let repo = try FixtureRepo()
        try standardApp(repo, packageJSON: #"{"dependencies": {"react-native": "0.76.5"}}"#)
        try repo.write("Gemfile.lock", "GEM\n  specs:\n    fastlane (2.219.0)\n")

        let (report, _) = await runProjectChecks(
            repo,
            tools: [
                "pod --version": .failed(
                    1, "mise ERROR No version is set for shim: pod\n"
                )
            ]
        )
        let check = try #require(report.checks.first { $0.id == "cocoapods.version" })

        #expect(check.status == .unknown)
        #expect(check.outcome.reason?.contains("No version is set for shim") == true)
        #expect(report.exitCode == 0)
    }
}

@Suite("ruby.version")
struct RubyVersionCheckTests {
    private static let installed = FakeProcessRunner.Response.ok(
        "ruby 3.2.2 (2023-03-30 revision e51014f9c0) [arm64-darwin23]\n"
    )

    @Test("passes when the installed Ruby matches the pin")
    func matchesPin() async throws {
        let repo = try FixtureRepo()
        try standardApp(repo, packageJSON: #"{"dependencies": {"react-native": "0.76.5"}}"#)
        try repo.write(".ruby-version", "3.2.2\n")

        let (report, _) = await runProjectChecks(repo, tools: ["ruby --version": Self.installed])
        let check = try #require(report.checks.first { $0.id == "ruby.version" })

        #expect(check.status == .pass)
        #expect(check.outcome.observed?.contains("3.2.2") == true)
    }

    /// `.ruby-version` is what makes this Check exist, so the requirement is settled
    /// whenever it runs. The dogfooding host's mise shim reports no version, and gems
    /// cannot be built by a Ruby that cannot say what it is (ADR-0004).
    @Test("a Ruby that runs but reports nothing is an error")
    func rubyProbeFails() async throws {
        let repo = try FixtureRepo()
        try standardApp(repo, packageJSON: #"{"dependencies": {"react-native": "0.76.5"}}"#)
        try repo.write(".ruby-version", "3.2.2\n")

        let (report, _) = await runProjectChecks(
            repo,
            tools: [
                "ruby --version": .failed(1, "mise ERROR No version is set for shim: ruby\n"),
                "rbenv --version": .ok("rbenv 1.2.0\n"),
            ]
        )
        let check = try #require(report.checks.first { $0.id == "ruby.version" })

        #expect(check.status == .error)
        #expect(check.outcome.observed?.contains("No version is set for shim: ruby") == true)
        #expect(check.outcome.remediation?.command == nil)
    }

    @Test("the RVM spelling of the pin resolves to the same version")
    func rvmSpelling() async throws {
        let repo = try FixtureRepo()
        try standardApp(repo, packageJSON: #"{"dependencies": {"react-native": "0.76.5"}}"#)
        try repo.write(".ruby-version", "ruby-3.2.2\n")

        let (report, _) = await runProjectChecks(repo, tools: ["ruby --version": Self.installed])
        let check = try #require(report.checks.first { $0.id == "ruby.version" })

        #expect(check.status == .pass)
    }

    @Test("a pin mismatch is a warning — team convention, not a contract")
    func pinMismatch() async throws {
        let repo = try FixtureRepo()
        try standardApp(repo, packageJSON: #"{"dependencies": {"react-native": "0.76.5"}}"#)
        try repo.write(".ruby-version", "3.3.0\n")

        let (report, _) = await runProjectChecks(repo, tools: ["ruby --version": Self.installed])
        let check = try #require(report.checks.first { $0.id == "ruby.version" })

        #expect(check.status == .warning)
        #expect(check.outcome.required?.contains("3.3.0") == true)
        #expect(check.outcome.remediation != nil)
        #expect(report.exitCode == 0)
    }

    @Test("no .ruby-version means no check at all — not even an unknown")
    func withoutPin() async throws {
        let repo = try FixtureRepo()
        try standardApp(repo, packageJSON: #"{"dependencies": {"react-native": "0.76.5"}}"#)

        let (report, runner) = await runProjectChecks(repo)

        #expect(report.checks.contains { $0.id == "ruby.version" } == false)
        #expect(runner.log.first(matching: "ruby --version") == nil)
    }

    @Test("Ruby missing from PATH while the project pins it is an error")
    func notInstalled() async throws {
        let repo = try FixtureRepo()
        try standardApp(repo, packageJSON: #"{"dependencies": {"react-native": "0.76.5"}}"#)
        try repo.write(".ruby-version", "3.2.2\n")

        let (report, _) = await runProjectChecks(repo)
        let check = try #require(report.checks.first { $0.id == "ruby.version" })

        #expect(check.status == .error)
        #expect(check.outcome.remediation != nil)
    }

    @Test("a pin mobile cannot resolve is unknown with a reason, never a silent pass")
    func unresolvablePin() async throws {
        let repo = try FixtureRepo()
        try standardApp(repo, packageJSON: #"{"dependencies": {"react-native": "0.76.5"}}"#)
        try repo.write(".ruby-version", "truffleruby+graalvm-23.1.1\n")

        let (report, _) = await runProjectChecks(repo, tools: ["ruby --version": Self.installed])
        let check = try #require(report.checks.first { $0.id == "ruby.version" })

        #expect(check.status == .unknown)
        #expect(check.outcome.reason?.contains("truffleruby") == true)
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
        try repo.write("Gemfile.lock", gemfileLock)
        try repo.write(".ruby-version", "3.2.2\n")

        let (report, _) = await runProjectChecks(
            repo,
            tools: [
                "yarn --version": .ok("3.6.4\n"),
                "pod --version": .ok("1.15.2\n"),
                "ruby --version": .ok("ruby 3.2.2 (2023-03-30 revision e51014f9c0) [arm64-darwin23]\n"),
            ]
        )
        let text = try DoctorJSONDocument(report: report, toolVersion: "9.9.9").encoded()
        let json = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let checks = try #require(json["checks"] as? [[String: Any]])

        #expect(
            checks.compactMap { $0["id"] as? String } == [
                "project.detected", "node.version", "package-manager.version",
                "cocoapods.version", "ruby.version",
            ]
        )
        for check in checks {
            #expect((check["source"] as? [String: Any])?["tier"] as? Int == 1)
        }
    }
}

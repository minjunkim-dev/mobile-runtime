import Foundation
import TestSupport
import Testing

@testable import Core

@Suite("project execution environment")
struct ProjectExecutionEnvironmentTests {
    @Test("a fresh clone validates its toolchain before installing dependencies")
    func freshCloneValidatesActivation() async throws {
        let repo = try FixtureRepo()
        try repo.write(
            "package.json",
            #"{"dependencies":{"react-native":"0.83.10"},"engines":{"node":">=22"}}"#
        )
        try repo.directory("ios")
        try repo.write("mise.toml", "[tools]\nnode = \"22.23.2\"\n")

        let tracked = "git -C \(repo.root.path) ls-files --error-unmatch -- mise.toml"
        let host = FakeProcessRunner(responses: [
            tracked: .ok("mise.toml\n"),
            "mise exec -- true": .failed(1, "mise ERROR tool node@22.23.2 is not installed"),
        ])
        let anchor = try #require(ProjectAnchor.detect(from: repo.root))
        let environment = await ProjectExecutionEnvironment.resolve(
            anchor: anchor, hostRunner: host
        )
        let context = ConfigContext.detect(anchor: anchor, workingDirectory: repo.root)

        let report = await DoctorEngine(
            checks: environment.checks(anchor: anchor, context: context)
        ).run()

        #expect(report.checks.first { $0.id == "project.detected" }?.status == .warning)
        #expect(
            report.checks.first { $0.id == "project.execution-environment" }?.status == .error
        )
        #expect(host.log.first(matching: "mise exec -- true") != nil)
        #expect(host.log.first(matching: "mise exec -- node --version") == nil)
    }

    @Test("mise activation preserves the command and disables automatic installation")
    func miseActivation() async throws {
        let repo = try FixtureRepo()
        let host = FakeProcessRunner(
            responses: ["mise exec -- node --version": .ok("v22.23.2\n")]
        )
        let runner = MiseProcessRunner(base: host, configDirectory: repo.root)

        let result = try await runner.run(
            ProcessCommand(
                "node",
                ["--version"],
                environment: ["EXAMPLE": "kept", "MISE_AUTO_INSTALL": "true"],
                timeout: .seconds(15)
            )
        )

        #expect(result.standardOutput == "v22.23.2\n")
        let command = try #require(host.log.first(matching: "mise exec -- node --version"))
        #expect(command.environment["EXAMPLE"] == "kept")
        #expect(command.environment["MISE_AUTO_INSTALL"] == "false")
        #expect(command.workingDirectory == repo.root)
        #expect(command.timeout == .seconds(15))
        #expect(command.output == .collected)
    }

    @Test("mise activation selects its config without changing a detached command's directory")
    func detachedActivation() async throws {
        let repo = try FixtureRepo()
        let config = try repo.directory("config")
        let project = try repo.directory("packages/app")
        let commandLog = repo.url("command.log")
        let processLog = repo.url("process.log")
        let host = FakeProcessRunner()
        let runner = MiseProcessRunner(base: host, configDirectory: config)

        let pid = try await runner.spawnDetached(
            ProcessCommand(
                "yarn",
                ["start", "--reset-cache"],
                environment: ["EXAMPLE": "kept", "MISE_AUTO_INSTALL": "true"],
                workingDirectory: project,
                timeout: nil,
                output: .streamed(to: commandLog)
            ),
            logFile: processLog
        )

        #expect(pid == host.spawnedPID)
        let spawn = try #require(host.log.spawned.first)
        #expect(spawn.command.executable == "mise")
        #expect(
            spawn.command.arguments == [
                "exec", "--", "sh", "-c", "cd \"$1\" && shift && exec \"$@\"",
                "mobile-mise", project.path, "yarn", "start", "--reset-cache",
            ]
        )
        #expect(spawn.command.environment["EXAMPLE"] == "kept")
        #expect(spawn.command.environment["MISE_AUTO_INSTALL"] == "false")
        #expect(spawn.command.workingDirectory == config)
        #expect(spawn.command.timeout == nil)
        #expect(spawn.command.output == .streamed(to: commandLog))
        #expect(spawn.logFile == processLog)
    }

    @Test("a committed mise config is authoritative for project checks")
    func committedMiseConfig() async throws {
        let repo = try FixtureRepo()
        try repo.write(
            "package.json",
            #"{"dependencies":{"react-native":"0.83.10"},"engines":{"node":">=22"}}"#
        )
        try repo.write("node_modules/react-native/package.json", #"{"version":"0.83.10"}"#)
        try repo.directory("ios")
        try repo.write("mise.toml", "[tools]\nnode = \"22.23.2\"\n")

        let tracked = "git -C \(repo.root.path) ls-files --error-unmatch -- mise.toml"
        let host = FakeProcessRunner(
            responses: [
                tracked: .ok("mise.toml\n"),
                "mise exec -- true": .ok(""),
                "mise exec -- node --version": .ok("v22.23.2\n"),
            ]
        )
        let anchor = try #require(ProjectAnchor.detect(from: repo.root))
        let environment = await ProjectExecutionEnvironment.resolve(
            anchor: anchor, hostRunner: host
        )
        let context = ConfigContext.detect(anchor: anchor, workingDirectory: repo.root)

        let report = await DoctorEngine(checks: environment.checks(anchor: anchor, context: context))
            .run()

        let node = try #require(report.checks.first { $0.id == "node.version" })
        #expect(node.status == .pass)
        #expect(host.log.first(matching: "mise exec -- node --version") != nil)
        #expect(host.log.first(matching: "node --version") == nil)
    }

    @Test("without a committed mise config project checks keep using PATH")
    func directPath() async throws {
        let repo = try FixtureRepo()
        try repo.write(
            "package.json",
            #"{"dependencies":{"react-native":"0.83.10"},"engines":{"node":">=22"}}"#
        )
        try repo.write("node_modules/react-native/package.json", #"{"version":"0.83.10"}"#)
        try repo.directory("ios")
        try repo.write("mise.toml", "[tools]\nnode = \"20\"\n")

        let tracked = "git -C \(repo.root.path) ls-files --error-unmatch -- mise.toml"
        let host = FakeProcessRunner(
            responses: [
                tracked: .failed(1, "not tracked"),
                "node --version": .ok("v22.23.2\n"),
            ]
        )
        let anchor = try #require(ProjectAnchor.detect(from: repo.root))
        let environment = await ProjectExecutionEnvironment.resolve(
            anchor: anchor, hostRunner: host
        )
        let context = ConfigContext.detect(anchor: anchor, workingDirectory: repo.root)

        let report = await DoctorEngine(checks: environment.checks(anchor: anchor, context: context))
            .run()

        let node = try #require(report.checks.first { $0.id == "node.version" })
        #expect(node.status == .pass)
        #expect(host.log.first(matching: "node --version") != nil)
    }

    @Test("a Git tracking failure cannot silently fall back to PATH")
    func trackingFailure() async throws {
        let repo = try FixtureRepo()
        try repo.write(
            "package.json",
            #"{"dependencies":{"react-native":"0.83.10"},"engines":{"node":">=22"}}"#
        )
        try repo.write("node_modules/react-native/package.json", #"{"version":"0.83.10"}"#)
        try repo.directory("ios")
        try repo.write("mise.toml", "[tools]\nnode = \"22.23.2\"\n")

        let tracked = "git -C \(repo.root.path) ls-files --error-unmatch -- mise.toml"
        let host = FakeProcessRunner(
            responses: ["node --version": .ok("v22.23.2\n")],
            failures: [
                tracked: ProcessError.spawnFailed(
                    command: tracked, underlying: FixtureMiss(command: "git")
                )
            ]
        )
        let anchor = try #require(ProjectAnchor.detect(from: repo.root))
        let environment = await ProjectExecutionEnvironment.resolve(
            anchor: anchor, hostRunner: host
        )
        let context = ConfigContext.detect(anchor: anchor, workingDirectory: repo.root)
        let report = await DoctorEngine(checks: environment.checks(anchor: anchor, context: context))
            .run()

        let activation = try #require(
            report.checks.first { $0.id == "project.execution-environment" }
        )
        let node = try #require(report.checks.first { $0.id == "node.version" })
        #expect(activation.status == .error)
        #expect(activation.outcome.observed?.contains("Could not verify whether mise.toml is committed") == true)
        #expect(node.status == .unknown)
        #expect(host.log.first(matching: "node --version") == nil)
        #expect(host.log.first(matching: "mise exec -- node --version") == nil)
    }

    @Test("a workspace-root .config mise file is authoritative")
    func workspaceRootConfig() async throws {
        let repo = try FixtureRepo()
        let app = try repo.directory("packages/app")
        try repo.write("yarn.lock", "")
        try repo.write(
            "packages/app/package.json",
            #"{"dependencies":{"react-native":"0.83.10"},"engines":{"node":">=22"}}"#
        )
        try repo.write(
            "packages/app/node_modules/react-native/package.json", #"{"version":"0.83.10"}"#
        )
        try repo.directory("packages/app/ios")
        try repo.write(".config/mise/config.toml", "[tools]\nnode = \"22.23.2\"\n")

        let tracked = "git -C \(repo.root.path) ls-files --error-unmatch -- .config/mise/config.toml"
        let host = FakeProcessRunner(
            responses: [
                tracked: .ok(".config/mise/config.toml\n"),
                "mise exec -- true": .ok(""),
                "mise exec -- node --version": .ok("v22.23.2\n"),
            ]
        )
        let anchor = try #require(ProjectAnchor.detect(from: app))
        let environment = await ProjectExecutionEnvironment.resolve(
            anchor: anchor, hostRunner: host
        )
        let context = ConfigContext.detect(anchor: anchor, workingDirectory: app)
        let report = await DoctorEngine(checks: environment.checks(anchor: anchor, context: context))
            .run()

        let activation = try #require(
            report.checks.first { $0.id == "project.execution-environment" }
        )
        #expect(activation.status == .pass)
        #expect(
            host.log.first(matching: "mise exec -- node --version")?.workingDirectory?.path
                == repo.root.path
        )
        #expect(host.log.first(matching: "node --version") == nil)
    }

    @Test("an unusable committed mise config fails once and blocks tool checks")
    func unusableMiseConfig() async throws {
        let repo = try FixtureRepo()
        try repo.write(
            "package.json",
            #"{"dependencies":{"react-native":"0.83.10"},"engines":{"node":">=22"}}"#
        )
        try repo.write("node_modules/react-native/package.json", #"{"version":"0.83.10"}"#)
        try repo.directory("ios")
        try repo.write("mise.toml", "[tools]\nnode = \"22.23.2\"\n")

        let tracked = "git -C \(repo.root.path) ls-files --error-unmatch -- mise.toml"
        let preflight = "mise exec -- true"
        let host = FakeProcessRunner(
            responses: [tracked: .ok("mise.toml\n")],
            failures: [
                preflight: ProcessError.spawnFailed(
                    command: preflight, underlying: FixtureMiss(command: "mise")
                )
            ]
        )
        let anchor = try #require(ProjectAnchor.detect(from: repo.root))
        let environment = await ProjectExecutionEnvironment.resolve(
            anchor: anchor, hostRunner: host
        )
        let context = ConfigContext.detect(anchor: anchor, workingDirectory: repo.root)
        let report = await DoctorEngine(checks: environment.checks(anchor: anchor, context: context))
            .run()

        let activation = try #require(
            report.checks.first { $0.id == "project.execution-environment" }
        )
        let node = try #require(report.checks.first { $0.id == "node.version" })
        #expect(activation.status == .error)
        #expect(activation.outcome.observed?.contains("mise is not on PATH") == true)
        #expect(activation.outcome.remediation != nil)
        #expect(node.status == .unknown)
        #expect(node.outcome.reason?.contains("project.execution-environment") == true)
        #expect(host.log.first(matching: "mise exec -- node --version") == nil)
    }

    @Test("an untrusted config gives the measured trust command without falling back")
    func untrustedMiseConfig() async throws {
        let repo = try FixtureRepo()
        try repo.write(
            "package.json",
            #"{"dependencies":{"react-native":"0.83.10"},"engines":{"node":">=22"}}"#
        )
        try repo.write("node_modules/react-native/package.json", #"{"version":"0.83.10"}"#)
        try repo.directory("ios")
        try repo.write(".mise.toml", "[tools]\nnode = \"22.23.2\"\n")

        let tracked = "git -C \(repo.root.path) ls-files --error-unmatch -- .mise.toml"
        let host = FakeProcessRunner(
            responses: [
                tracked: .ok(".mise.toml\n"),
                "mise exec -- true": .failed(
                    1, "mise ERROR Config files in \(repo.root.path) are not trusted. Trust them with `mise trust`.\n"
                ),
            ]
        )
        let anchor = try #require(ProjectAnchor.detect(from: repo.root))
        let environment = await ProjectExecutionEnvironment.resolve(
            anchor: anchor, hostRunner: host
        )
        let context = ConfigContext.detect(anchor: anchor, workingDirectory: repo.root)

        let report = await DoctorEngine(checks: environment.checks(anchor: anchor, context: context))
            .run()

        let activation = try #require(
            report.checks.first { $0.id == "project.execution-environment" }
        )
        #expect(activation.status == .error)
        #expect(activation.outcome.remediation?.command == "mise trust \(repo.root.path)")
        #expect(host.log.first(matching: "mise exec -- node --version") == nil)
        #expect(host.log.first(matching: "node --version") == nil)
    }

    @Test("a missing managed version fails without installing it")
    func missingManagedVersion() async throws {
        let repo = try FixtureRepo()
        try repo.write(
            "package.json",
            #"{"dependencies":{"react-native":"0.83.10"},"engines":{"node":">=22"}}"#
        )
        try repo.write("node_modules/react-native/package.json", #"{"version":"0.83.10"}"#)
        try repo.directory("ios")
        try repo.write("mise.toml", "[tools]\nnode = \"22.23.2\"\n")

        let tracked = "git -C \(repo.root.path) ls-files --error-unmatch -- mise.toml"
        let host = FakeProcessRunner(
            responses: [
                tracked: .ok("mise.toml\n"),
                "mise exec -- true": .failed(1, "mise ERROR tool node@22.23.2 is not installed"),
            ]
        )
        let anchor = try #require(ProjectAnchor.detect(from: repo.root))
        let environment = await ProjectExecutionEnvironment.resolve(
            anchor: anchor, hostRunner: host
        )
        let context = ConfigContext.detect(anchor: anchor, workingDirectory: repo.root)
        let report = await DoctorEngine(checks: environment.checks(anchor: anchor, context: context))
            .run()

        let activation = try #require(
            report.checks.first { $0.id == "project.execution-environment" }
        )
        #expect(activation.status == .error)
        #expect(activation.outcome.remediation?.command == "cd \(repo.root.path) && mise doctor")
        let commands = host.log.all.map(\.description).joined(separator: "\n")
        #expect(!commands.contains("mise install"))
        #expect(!commands.contains("mise trust"))
        #expect(!commands.contains("mise use"))
    }
}

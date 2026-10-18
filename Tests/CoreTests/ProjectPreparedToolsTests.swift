@testable import Core
import Foundation
import TestSupport
import Testing

@Suite("project prepared tool activation")
struct ProjectPreparedToolsTests {
    @Test("project checks and detached children receive exact paths without changing globals")
    func exactPaths() async throws {
        let repo = try FixtureRepo()
        let node = try repo.write("node/bin/node", "fixture node")
        let java = try repo.write("jdk/Contents/Home/bin/java", "fixture java")
        for path in [node, java] { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path) }
        let host = FakeProcessRunner(responses: ["node --version": .ok("v20.0.0"), "\(node.path) --version": .ok("v22.23.2")])
        let original = ["PATH": "/original/bin:/usr/bin", "JAVA_HOME": "/original/jdk", "KEEP": "value"]
        let environment = ProjectExecutionEnvironment(directRunner: host).activatingTools(["node": node, "java": java], environment: original)
        let output = try await environment.runner.run(ProcessCommand("node", ["--version"], workingDirectory: repo.root))
        #expect(output.standardOutput == "v22.23.2")
        _ = try await environment.runner.spawnDetached(ProcessCommand("node", ["server.js"], workingDirectory: repo.root), logFile: repo.url("child.log"))
        let invocation = try #require(host.log.first(matching: "\(node.path) --version"))
        #expect(invocation.environment["JAVA_HOME"] == java.deletingLastPathComponent().deletingLastPathComponent().path)
        #expect(invocation.environment["PATH"]?.hasSuffix(original["PATH"]!) == true)
        #expect(invocation.environment["PATH"]?.contains(node.deletingLastPathComponent().path) == true)
        #expect(invocation.workingDirectory == repo.root)
        #expect(host.log.spawned.first?.command.executable == node.path)
        #expect(original["JAVA_HOME"] == "/original/jdk")
        #expect(try await environment.run().status == .pass)
    }

    @Test("a missing selected executable blocks activation instead of using another version")
    func missingPath() async throws {
        let repo = try FixtureRepo()
        let environment = ProjectExecutionEnvironment(directRunner: FakeProcessRunner())
            .activatingTools(["node": repo.url("missing/bin/node")], environment: ["PATH": "/usr/bin"])
        #expect(try await environment.run().status == .error)
    }

    @Test("a pasteable remediation receives the same prepared JAVA_HOME through mise")
    func remediationEnvironment() async throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies":{"react-native":"0.83.10"}}"#)
        try repo.write("mise.toml", "[tools]\nnode = \"22.23.2\"\n")
        let node = try repo.write("node/bin/node", "#!/bin/sh\nprintf '%s' \"$JAVA_HOME\"\n")
        let java = try repo.write("jdk/Contents/Home/bin/java", "fixture java")
        let mise = try repo.write("fake/bin/mise", "#!/bin/sh\nshift\nshift\nexec \"$@\"\n")
        for file in [node, java, mise] { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path) }
        let anchor = try #require(ProjectAnchor.detect(from: repo.root))
        let host = FakeProcessRunner(responses: ["git -C \(repo.root.path) ls-files --error-unmatch -- mise.toml": .ok("mise.toml\n")])
        let selected = await ProjectExecutionEnvironment.resolve(anchor: anchor, hostRunner: host)
            .activatingTools(["node": node, "java": java], environment: ["PATH": mise.deletingLastPathComponent().path + ":/usr/bin:/bin"])
        let command = selected.remediationCommand(ProcessCommand("node", ["--version"], workingDirectory: repo.root))
        let result = try await SystemProcessRunner(environment: ["PATH": mise.deletingLastPathComponent().path + ":/usr/bin:/bin", "JAVA_HOME": "/old/jdk"])
            .run(ProcessCommand("sh", ["-c", command], workingDirectory: repo.root))
        #expect(result.terminationStatus.isSuccess)
        #expect(result.standardOutput == java.deletingLastPathComponent().deletingLastPathComponent().path)
    }

    @Test("an exact prepared executable runs without a working directory", arguments: [false, true])
    func actualExactExecutable(_ streamed: Bool) async throws {
        let repo = try FixtureRepo()
        let node = try repo.write("prepared node/bin/node", "#!/bin/sh\nprintf 'selected exact tool'\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: node.path)
        let log = repo.url("output.log")
        let environment = ProjectExecutionEnvironment(directRunner: SystemProcessRunner(environment: ["PATH": "/usr/bin:/bin"]))
            .activatingTools(["node": node], environment: ["PATH": "/usr/bin:/bin"])
        let result = try await environment.runner.run(ProcessCommand("node", ["--version"], output: streamed ? .streamed(to: log) : .collected))
        #expect(result.terminationStatus.isSuccess)
        let output = streamed ? try String(contentsOf: log, encoding: .utf8) : result.standardOutput
        #expect(output == "selected exact tool")
    }

    @Test("a prepared mise runs activation and project commands without a global mise")
    func exactMiseBootstrap() async throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies":{"react-native":"0.83.10"}}"#)
        try repo.write("mise.toml", "[tools]\nnode = \"22.23.2\"\n")
        let mise = try repo.write("approved manager/bin/mise", "#!/bin/sh\n[ \"$1\" = exec ] || exit 42\nshift\nshift\nexec \"$@\"\n")
        let node = try repo.write("prepared node/bin/node", "#!/bin/sh\nprintf 'exact project node'\n")
        for path in [mise, node] { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path) }
        let host = SystemProcessRunner(environment: ["PATH": "/usr/bin:/bin"])
        for arguments in [["-C", repo.root.path, "init", "--quiet"], ["-C", repo.root.path, "add", "mise.toml"]] {
            #expect(try await host.run(ProcessCommand("git", arguments)).terminationStatus.isSuccess)
        }
        let anchor = try #require(ProjectAnchor.detect(from: repo.root))
        let selected = await ProjectExecutionEnvironment.resolve(anchor: anchor, hostRunner: host)
            .activatingTools(["mise": mise, "node": node], environment: ["PATH": "/usr/bin:/bin"])
        #expect(try await selected.run().status == .pass)
        let command = ProcessCommand("node", ["--version"], workingDirectory: repo.root)
        #expect(try await selected.runner.run(command).standardOutput == "exact project node")
        let remediation = selected.remediationCommand(command)
        let result = try await host.run(ProcessCommand("sh", ["-c", remediation], workingDirectory: repo.root))
        #expect(result.terminationStatus.isSuccess)
        #expect(result.standardOutput == "exact project node")
    }
}

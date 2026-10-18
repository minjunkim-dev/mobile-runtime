import Core
import Foundation
import TestSupport
import Testing

@Suite("exact executable process boundary")
struct AbsoluteExecutableTests {
    @Test("an absolute fixture runs without cwd in either output mode", arguments: [false, true])
    func absolute(_ streamed: Bool) async throws {
        let repo = try FixtureRepo()
        let executable = try repo.write("tools with spaces/selected tool", "#!/bin/sh\nprintf 'selected executable'\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let log = repo.url("output.log")
        let result = try await SystemProcessRunner(environment: ["PATH": "/usr/bin:/bin"]).run(
            ProcessCommand(executable.path, output: streamed ? .streamed(to: log) : .collected))
        #expect(result.terminationStatus.isSuccess)
        let output = streamed ? try String(contentsOf: log, encoding: .utf8) : result.standardOutput
        #expect(output == "selected executable")
    }

    @Test("a command name still resolves through the supplied PATH")
    func namedLookup() async throws {
        let repo = try FixtureRepo()
        let executable = try repo.write("bin/runstir-owned-process-fixture", "#!/bin/sh\nprintf 'PATH executable'\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let result = try await SystemProcessRunner(environment: ["PATH": executable.deletingLastPathComponent().path + ":/usr/bin:/bin"])
            .run(ProcessCommand("runstir-owned-process-fixture"))
        #expect(result.terminationStatus.isSuccess)
        #expect(result.standardOutput == "PATH executable")
    }
}

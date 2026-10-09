import Core
import Foundation
import TestSupport
import Testing

@Suite("explicit process environment")
struct ExplicitProcessEnvironmentTests {
    @Test("the supplied environment and directory replace ambient process state")
    func explicitInput() async throws {
        let repo = try FixtureRepo()
        let runner = SystemProcessRunner(environment: ["PATH": "/usr/bin:/bin", "RUNSTIR_TEST": "input"], workingDirectory: repo.root)
        let result = try await runner.run(ProcessCommand("sh", ["-c", "printf '%s\\n%s\\n%s' \"$RUNSTIR_TEST\" \"$HOME\" \"$PWD\""], environment: ["RUNSTIR_TEST": "command"]))
        #expect(result.terminationStatus.isSuccess)
        #expect(result.standardOutput == "command\n\n\(repo.root.path)")
    }
}

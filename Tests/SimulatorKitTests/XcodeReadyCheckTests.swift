import Core
import TestSupport
import Testing
@testable import SimulatorKit

@Suite("Xcode initial setup")
struct XcodeReadyCheckTests {
    @Test("initial setup is observed without running provisioning commands", arguments: [true, false])
    func setup(ready: Bool) async throws {
        let directory = "/Applications/Xcode Test.app/Contents/Developer"
        let runner = FakeProcessRunner(responses: [
            "xcodebuild -version": .ok("Xcode 27.0\nBuild version 27A266a\n"),
            "xcodebuild -checkFirstLaunchStatus": ready ? .ok("") : .failed(1, "additional system content needs installation"),
        ])
        let locator = XcodeLocator(runner: runner, developerDirOverride: directory)
        let result = try await XcodeReadyCheck(runner: runner, locator: locator).run()
        #expect(result.status == (ready ? .pass : .error))
        #expect(runner.log.all.allSatisfy { !$0.arguments.contains("-runFirstLaunch") && !$0.arguments.contains("-license") })
        #expect(runner.log.first(matching: "xcodebuild -checkFirstLaunchStatus")?.environment["DEVELOPER_DIR"] == directory)
        if !ready {
            #expect(result.remediation?.command == "open '/Applications/Xcode Test.app'")
        }
    }
}

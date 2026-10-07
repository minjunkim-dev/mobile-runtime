import Core
import Foundation

/// This probe observes setup status. It never runs first-launch tasks or accepts a license.
public struct XcodeReadyCheck: Check {
    public let id = "xcode.ready"
    public let category = "Xcode"
    public let title = "Xcode initial setup is complete"
    public let dependsOn = ["xcode.installed"]
    private let runner: any ProcessRunner
    private let locator: XcodeLocator

    public init(runner: any ProcessRunner, locator: XcodeLocator) {
        self.runner = runner
        self.locator = locator
    }

    public func run() async throws -> CheckOutcome {
        let installation = try await locator.locate()
        let result = try await runner.run(ProcessCommand(
            "xcodebuild", ["-checkFirstLaunchStatus"],
            environment: ["DEVELOPER_DIR": installation.developerDirectory],
            timeout: .seconds(30)
        ))
        guard result.terminationStatus.isSuccess else {
            let output = result.combinedOutput.lowercased()
            let knownSetupFailure = output.contains("additional system content")
                || output.contains("license agreement")
                || output.contains("license has not been accepted")
            guard case .exited = result.terminationStatus, knownSetupFailure else {
                return .unknown(
                    reason: "Xcode initial setup probe did not return a usable verdict. Run xcodebuild -checkFirstLaunchStatus with the selected DEVELOPER_DIR and inspect its output.",
                    observed: "\(String(describing: result.terminationStatus)): \(result.combinedOutput.firstLine ?? "no output")"
                )
            }
            let app = URL(fileURLWithPath: installation.developerDirectory)
                .deletingLastPathComponent().deletingLastPathComponent()
            let quotedApp = "'" + app.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
            return .error(
                observed: result.combinedOutput.firstLine ?? "Xcode reports incomplete initial setup",
                required: "Xcode license approval and first-launch tasks completed",
                remediation: Remediation(
                    summary: "Open the selected Xcode. Review its license and finish initial setup, then run mobile doctor again.",
                    command: app.pathExtension == "app" ? "open \(quotedApp)" : nil,
                    url: "https://developer.apple.com/xcode/"
                )
            )
        }
        return .pass(observed: "Xcode initial setup complete", source: .host)
    }
}

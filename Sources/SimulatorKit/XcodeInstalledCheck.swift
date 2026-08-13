import Core

/// `xcode.installed` — Xcode present and the developer directory (xcode-select or
/// DEVELOPER_DIR) pointing at it. Everything else iOS-side hangs off this.
public struct XcodeInstalledCheck: Check {
    public let id = "xcode.installed"
    public let category = "Xcode"
    public let title = "Xcode installed with a valid developer directory"

    private let locator: XcodeLocator

    public init(locator: XcodeLocator) {
        self.locator = locator
    }

    public func run() async throws -> CheckOutcome {
        let installation = try await locator.locate()
        return .pass(
            observed: installation.summary,
            required: "a full Xcode install reachable through the developer directory"
        )
    }
}

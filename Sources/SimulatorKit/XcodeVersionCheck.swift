import Core

/// `xcode.version` — the installed Xcode against what this React Native version
/// needs. No repo file declares that requirement, so this is the first verdict a
/// host-only or project-only tool cannot reach.
public struct XcodeVersionCheck: Check {
    public let id = "xcode.version"
    public let category = "Xcode"
    public let title = "Xcode version satisfies what this React Native version needs"
    public let dependsOn = ["xcode.installed"]

    private let lookup: MatrixLookup
    private let locator: XcodeLocator

    public init(lookup: MatrixLookup, locator: XcodeLocator) {
        self.lookup = lookup
        self.locator = locator
    }

    public func run() async throws -> CheckOutcome {
        let requirements: CompatibilityMatrix.IOSRequirements
        switch lookup {
        case .requirements(let resolved, _): requirements = resolved
        case .unavailable(let reason): return .unknown(reason: reason, source: lookup.source)
        }

        let required = "Xcode \(requirements.xcode) or newer"
        // xcode.installed passed, so locating cannot fail here — but reading the
        // version string still can.
        let installation = try await locator.locate()
        guard let installed = SemanticVersion(installation.version) else {
            return .unknown(
                reason: "`xcodebuild -version` reported `\(installation.version)`, "
                    + "which mobile cannot resolve to a version",
                observed: installation.summary, required: required, source: lookup.source
            )
        }

        let observed = "Xcode \(installation.version) (\(installation.build))"
        guard requirements.xcode.isSatisfied(by: installed) else {
            return .error(
                observed: observed,
                required: required,
                source: lookup.source,
                remediation: Remediation(
                    summary: "Install Xcode \(requirements.xcode) or newer and select it — "
                        + "this React Native version does not build with an older toolchain.",
                    command: "sudo xcode-select -s /Applications/Xcode.app/Contents/Developer",
                    url: "https://developer.apple.com/xcode/"
                )
            )
        }
        return .pass(observed: observed, required: required, source: lookup.source)
    }
}

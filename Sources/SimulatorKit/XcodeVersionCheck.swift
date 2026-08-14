import Core

/// `xcode.version` — the installed Xcode against what this project needs: the
/// framework floor from the matrix, raised by `.xcode-version` when the repo asks
/// for more. Composing the two is a verdict a host-only or project-only tool
/// cannot reach; which evidence won is in the source.
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
        let minimum: MinimumVersion
        switch lookup.xcode {
        case .requirement(let version, _): minimum = version
        case .unavailable(let reason, let source): return .unknown(reason: reason, source: source)
        }
        let source = lookup.xcode.source

        let required = "Xcode \(minimum) or newer"
        // xcode.installed passed, so locating cannot fail here — but reading the
        // version string still can.
        let installation = try await locator.locate()
        // The requirement is settled by the time this runs — the unavailable case
        // returned above — so an Xcode that cannot say what version it is is an
        // unusable tool the project requires, which ADR-0004 grades as an error. An
        // `error` carries no reason, so what xcodebuild printed rides in `observed`.
        guard let installed = SemanticVersion(installation.version) else {
            return .error(
                observed: "`xcodebuild -version` reported `\(installation.version)`, "
                    + "which mobile cannot resolve to a version",
                required: required,
                source: source,
                remediation: Remediation(
                    summary: "Check that `xcodebuild -version` prints a version — "
                        + "an Xcode that cannot report one cannot be built with either.",
                    command: "xcodebuild -version"
                )
            )
        }

        let observed = "Xcode \(installation.version) (\(installation.build))"
        guard minimum.isSatisfied(by: installed) else {
            return .error(
                observed: observed,
                required: required,
                source: source,
                remediation: Remediation(
                    // Which evidence set the floor is in `source`; the fix is the same
                    // either way, so the summary does not guess at the cause.
                    summary: "Install Xcode \(minimum) or newer and select it — "
                        + "this project does not build with an older toolchain.",
                    command: "sudo xcode-select -s /Applications/Xcode.app/Contents/Developer",
                    url: "https://developer.apple.com/xcode/"
                )
            )
        }
        return .pass(observed: observed, required: required, source: source)
    }
}

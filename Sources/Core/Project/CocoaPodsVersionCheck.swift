import Foundation

/// `cocoapods.version` — the CocoaPods on PATH against the version `Gemfile.lock`
/// locks. The Check exists only where a `Gemfile.lock` does: a project that does
/// not manage its gems never asked, and inventing a verdict for it is noise.
public struct CocoaPodsVersionCheck: Check {
    public let id = "cocoapods.version"
    public let category = "CocoaPods"
    public let title = "CocoaPods matches the version Gemfile.lock locks"

    private static let source = CheckSource(tier: 1, origin: "Gemfile.lock")

    /// nil when the lock exists but pins no CocoaPods — then "is it installed" is
    /// the whole verdict.
    private let lockedVersion: String?
    private let runner: any ProcessRunner

    public init(lockedVersion: String?, runner: any ProcessRunner) {
        self.lockedVersion = lockedVersion
        self.runner = runner
    }

    public func run() async throws -> CheckOutcome {
        let required = lockedVersion.map { "CocoaPods \($0) (Gemfile.lock)" }
            ?? "CocoaPods installed (Gemfile.lock locks no version of it)"

        let installed: SemanticVersion
        switch try await probeVersion(of: "pod", using: runner) {
        case .reported(let version):
            installed = version
        case .notOnPath:
            // A lock that pins no CocoaPods is not a project asking for CocoaPods,
            // and `bundle install` cannot install a gem the Gemfile never declared.
            // Demanding it there is the noise this Check is conditional to avoid.
            guard lockedVersion != nil else {
                return .unknown(
                    reason: "pod is not on PATH, and `Gemfile.lock` locks no CocoaPods — "
                        + "mobile cannot tell whether this project needs it",
                    observed: "pod is not on PATH", required: required, source: Self.source
                )
            }
            return .error(
                observed: "pod is not on PATH",
                required: required,
                source: Self.source,
                remediation: Remediation(
                    summary: "Install the gems the project locks — pod install runs out of them.",
                    command: "bundle install"
                )
            )
        case .unreadable(let reason):
            return .unknown(reason: reason, required: required, source: Self.source)
        }
        let observed = "CocoaPods \(installed)"

        guard let lockedVersion else {
            return .pass(observed: observed, required: required, source: Self.source)
        }
        guard let locked = SemanticVersion(lockedVersion) else {
            return .unknown(
                reason: "`Gemfile.lock` locks CocoaPods `\(lockedVersion)`, which mobile cannot resolve to a version",
                observed: observed, required: required, source: Self.source
            )
        }
        guard installed == locked else {
            return .warning(
                observed: observed,
                required: required,
                source: Self.source,
                remediation: Remediation(
                    summary: "Run pod through bundler — a different CocoaPods rewrites Podfile.lock.",
                    command: "bundle install && bundle exec pod install"
                )
            )
        }
        return .pass(observed: observed, required: required, source: Self.source)
    }
}

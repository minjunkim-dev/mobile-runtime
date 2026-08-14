import Foundation

/// `cocoapods.version` — the CocoaPods on PATH against what the project's gem files
/// ask for. The Check exists wherever a `Gemfile` or a `Gemfile.lock` does: a project
/// that manages no gems never asked, and inventing a verdict for it is noise.
public struct CocoaPodsVersionCheck: Check {
    public let id = "cocoapods.version"
    public let category = "CocoaPods"
    /// Both halves of the question, because a project without a lock only asks the
    /// first one and the title has to stay true for it.
    public let title = "CocoaPods is installed at the version the project asks for"

    private let requirement: CocoaPodsRequirement
    private let runner: any ProcessRunner

    public init(requirement: CocoaPodsRequirement, runner: any ProcessRunner) {
        self.requirement = requirement
        self.runner = runner
    }

    private var source: CheckSource { CheckSource(tier: 1, origin: requirement.file) }

    private var required: String {
        switch requirement.level {
        case .version(let locked): "CocoaPods \(locked) (\(requirement.file))"
        case .installed: "CocoaPods installed (\(requirement.file) declares the gem)"
        case .unconfirmed: "nothing — `\(requirement.file)` asks for no CocoaPods"
        }
    }

    /// Bundler owns the install either way: with a lock it installs the pinned
    /// version, without one the version the Gemfile's range resolves to.
    private static let remediation = Remediation(
        summary: "Install the gems the project declares — pod install runs out of them.",
        command: "bundle install"
    )

    public func run() async throws -> CheckOutcome {
        // What the tool is, before what it says: a `pod` that cannot report a version
        // cannot run `pod install` either, so absent and mute are the same state.
        let unusable: String
        switch try await probeVersion(of: "pod", using: runner) {
        case .reported(let installed):
            return judge(installed: installed)
        case .notOnPath:
            unusable = "pod is not on PATH"
        case .unreadable(let complaint):
            unusable = complaint
        }

        // The requirement picks the grade, not the reason the measurement failed
        // (ADR-0004). Nothing asked for CocoaPods here, so nothing is broken.
        guard requirement.level != .unconfirmed else {
            return .unknown(
                reason: "\(unusable), and `\(requirement.file)` asks for no CocoaPods — "
                    + "mobile cannot tell whether this project needs it",
                observed: unusable, required: required, source: source
            )
        }
        // An `error` carries no `reason`, so the tool's own words — the sentence that
        // named mise's unset shim in dogfooding — ride in `observed` instead. They are
        // what makes this verdict actionable, and they are not dropped.
        return .error(
            observed: unusable, required: required, source: source, remediation: Self.remediation
        )
    }

    private func judge(installed: SemanticVersion) -> CheckOutcome {
        let observed = "CocoaPods \(installed)"

        guard case .version(let lockedVersion) = requirement.level else {
            return .pass(observed: observed, required: required, source: source)
        }
        guard let locked = SemanticVersion(lockedVersion) else {
            return .unknown(
                reason: "`\(requirement.file)` locks CocoaPods `\(lockedVersion)`, "
                    + "which mobile cannot resolve to a version",
                observed: observed, required: required, source: source
            )
        }
        guard installed == locked else {
            return .warning(
                observed: observed,
                required: required,
                source: source,
                remediation: Remediation(
                    summary: "Run pod through bundler — a different CocoaPods rewrites Podfile.lock.",
                    command: "bundle install && bundle exec pod install"
                )
            )
        }
        return .pass(observed: observed, required: required, source: source)
    }
}

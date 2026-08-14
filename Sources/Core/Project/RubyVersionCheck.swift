import Foundation

/// `ruby.version` — the Ruby on PATH against `.ruby-version`. Only a project that
/// pinned Ruby gets this Check; a pin is team convention, so breaking it warns
/// rather than errors — the same line `node.version` draws.
public struct RubyVersionCheck: Check {
    public let id = "ruby.version"
    public let category = "Ruby"
    public let title = "Ruby matches the version .ruby-version pins"

    private static let source = CheckSource(tier: 1, origin: ".ruby-version")

    private let pin: String
    private let runner: any ProcessRunner

    public init(pin: String, runner: any ProcessRunner) {
        self.pin = pin
        self.runner = runner
    }

    public func run() async throws -> CheckOutcome {
        let required = "Ruby \(pin) (.ruby-version)"

        // `.ruby-version` is what makes this Check exist, so the requirement is settled
        // whenever it runs: a Ruby that cannot say what it is cannot build the
        // project's gems, which is the state of one that is not installed at all
        // (ADR-0004). An `error` carries no reason, so the tool's own words ride in
        // `observed`.
        let unusable: String
        let remediation: Remediation
        switch try await probeVersion(of: "ruby", using: runner) {
        case .reported(let installed):
            return try await judge(installed: installed, required: required)
        case .notOnPath:
            unusable = "ruby is not on PATH"
            remediation = Remediation(
                summary: "Install the pinned Ruby, then re-run mobile doctor.",
                command: try await VersionManagerCommand.detect(for: .ruby, version: pin, runner: runner),
                url: "https://www.ruby-lang.org/"
            )
        case .unreadable(let complaint):
            unusable = complaint
            remediation = muteToolRemediation("ruby")
        }
        return .error(observed: unusable, required: required, source: Self.source, remediation: remediation)
    }

    private func judge(installed: SemanticVersion, required: String) async throws -> CheckOutcome {
        let observed = "Ruby \(installed)"

        guard let expected = VersionPin(pin) else {
            return .unknown(
                reason: "`.ruby-version` pins `\(pin)`, which mobile cannot resolve to a version",
                observed: observed, required: required, source: Self.source
            )
        }
        guard expected.matches(installed) else {
            return .warning(
                observed: observed,
                required: required,
                source: Self.source,
                remediation: Remediation(
                    summary: "Switch to the pinned Ruby version — the project's gems are built against it.",
                    command: try await VersionManagerCommand.detect(for: .ruby, version: pin, runner: runner)
                )
            )
        }
        return .pass(observed: observed, required: required, source: Self.source)
    }
}

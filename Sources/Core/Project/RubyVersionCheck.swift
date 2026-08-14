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

        let installed: SemanticVersion
        switch try await probeVersion(of: "ruby", using: runner) {
        case .reported(let version):
            installed = version
        case .notOnPath:
            return .error(
                observed: "ruby is not on PATH",
                required: required,
                source: Self.source,
                remediation: Remediation(
                    summary: "Install the pinned Ruby, then re-run mobile doctor.",
                    command: try await VersionManagerCommand.detect(
                        for: .ruby, version: pin, runner: runner
                    ),
                    url: "https://www.ruby-lang.org/"
                )
            )
        case .unreadable(let reason):
            return .unknown(reason: reason, required: required, source: Self.source)
        }
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
                    command: try await VersionManagerCommand.detect(
                        for: .ruby, version: pin, runner: runner
                    )
                )
            )
        }
        return .pass(observed: observed, required: required, source: Self.source)
    }
}

import Foundation

/// `package-manager.version` — the `packageManager` field against what is really
/// installed. A mismatch is the common way a lockfile gets rewritten.
public struct PackageManagerVersionCheck: Check {
    public let id = "package-manager.version"
    public let category = "Package manager"
    public let title = "Package manager matches the packageManager field"

    /// doctor runs `<name> --version`, and the name comes out of a file in the
    /// repo, so it is checked against the managers corepack knows rather than
    /// executed as written.
    private static let known: Set<String> = ["npm", "yarn", "pnpm", "bun"]

    private let requirement: PackageManagerRequirement
    private let anchor: ProjectAnchor
    private let context: ConfigContext
    private let runner: any ProcessRunner

    /// The declaration can come from the workspace root rather than the anchor, so
    /// the origin travels with the requirement instead of being fixed here.
    private var source: CheckSource { CheckSource(tier: 1, origin: requirement.origin) }

    public init(
        requirement: PackageManagerRequirement,
        anchor: ProjectAnchor,
        context: ConfigContext,
        runner: any ProcessRunner
    ) {
        self.requirement = requirement
        self.anchor = anchor
        self.context = context
        self.runner = runner
    }

    public func run() async throws -> CheckOutcome {
        let required = "\(requirement.name) \(requirement.version)"

        guard Self.known.contains(requirement.name) else {
            return .unknown(
                reason: "`packageManager` names `\(requirement.name)`, which mobile does not know how to measure",
                required: required, source: source
            )
        }
        guard let declared = SemanticVersion(requirement.version) else {
            return .unknown(
                reason: "could not read the declared version `\(requirement.version)`",
                required: required, source: source
            )
        }

        // `packageManager` is the declaration, so the requirement is settled the moment
        // this Check exists: a manager that runs and cannot report its version cannot
        // install the dependencies either — the state of one that is not there at all
        // (ADR-0004). An `error` carries no reason, so the tool's own words ride in
        // `observed`.
        let unusable: String
        let advice: Remediation
        switch try await probeVersion(of: requirement.name, using: runner) {
        case .reported(let installed):
            return judge(installed: installed, declared: declared, required: required)
        case .notOnPath:
            unusable = "\(requirement.name) is not on PATH"
            advice = remediation
        case .unreadable(let complaint):
            unusable = complaint
            advice = await muteToolRemediation(
                requirement.name, anchor: anchor, context: context, using: runner
            )
        }
        return .error(observed: unusable, required: required, source: source, remediation: advice)
    }

    private func judge(
        installed: SemanticVersion, declared: SemanticVersion, required: String
    ) -> CheckOutcome {
        let observed = "\(requirement.name) \(installed)"
        guard installed == declared else {
            return .warning(
                observed: observed,
                required: required,
                source: source,
                remediation: Remediation(
                    summary: "Run the declared package manager — a different one rewrites the lockfile.",
                    command: "corepack use \(requirement.name)@\(requirement.version)"
                )
            )
        }
        return .pass(observed: observed, required: required, source: source)
    }

    /// corepack is how the managers it ships with get onto a machine, and pasting
    /// `corepack enable` for one it does not carry is the same mistake #27 fixed
    /// elsewhere — a command that cannot do what the line says it does.
    private var remediation: Remediation {
        guard requirement.name != "bun" else {
            return Remediation(
                summary: "Install bun, then re-run mobile doctor.",
                url: "https://bun.sh/"
            )
        }
        return Remediation(
            summary: "Enable corepack so the declared package manager is the one that runs.",
            command: "corepack enable"
        )
    }
}

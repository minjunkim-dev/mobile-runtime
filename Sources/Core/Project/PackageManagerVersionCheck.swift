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
    private static let source = CheckSource(tier: 1, origin: "package.json packageManager")

    private let requirement: PackageManagerRequirement
    private let runner: any ProcessRunner

    public init(requirement: PackageManagerRequirement, runner: any ProcessRunner) {
        self.requirement = requirement
        self.runner = runner
    }

    public func run() async throws -> CheckOutcome {
        let required = "\(requirement.name) \(requirement.version)"

        guard Self.known.contains(requirement.name) else {
            return .unknown(
                reason: "`packageManager` names `\(requirement.name)`, which mobile does not know how to measure",
                required: required, source: Self.source
            )
        }
        guard let declared = SemanticVersion(requirement.version) else {
            return .unknown(
                reason: "could not read the declared version `\(requirement.version)`",
                required: required, source: Self.source
            )
        }

        let installed: SemanticVersion
        switch try await probeVersion(of: requirement.name, using: runner) {
        case .reported(let version):
            installed = version
        case .notOnPath:
            return .error(
                observed: "\(requirement.name) is not on PATH",
                required: required,
                source: Self.source,
                remediation: Remediation(
                    summary: "Enable corepack so the declared package manager is the one that runs.",
                    command: "corepack enable"
                )
            )
        case .unreadable(let reason):
            return .unknown(reason: reason, required: required, source: Self.source)
        }

        guard installed == declared else {
            return .warning(
                observed: "\(requirement.name) \(installed)",
                required: required,
                source: Self.source,
                remediation: Remediation(
                    summary: "Run the declared package manager — a different one rewrites the lockfile.",
                    command: "corepack use \(requirement.name)@\(requirement.version)"
                )
            )
        }
        return .pass(observed: "\(requirement.name) \(installed)", required: required, source: Self.source)
    }
}

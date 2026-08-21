import Foundation

/// `package-manager.version` — the `packageManager` field against what is really
/// installed. A mismatch is the common way a lockfile gets rewritten.
public struct PackageManagerVersionCheck: Check {
    public let id = "package-manager.version"
    public let category = "Package manager"
    public let title = "Package manager matches the packageManager field"

    /// The manager name comes out of a file in the repo, so it is checked against
    /// the supported set before `ProjectAnchor` turns it into a direct or Corepack
    /// command.
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
        let versionCommand = anchor.packageManagerProcess(
            ["--version"], name: requirement.name,
            workingDirectory: anchor.directory, timeout: .seconds(15)
        )
        let unusable: String
        let advice: Remediation
        switch try await probeVersion(versionCommand, using: runner) {
        case .reported(let installed):
            return judge(installed: installed, declared: declared, required: required)
        case .notOnPath:
            unusable = "\(versionCommand.executable) is not on PATH"
            advice = missingExecutableRemediation(corepack: versionCommand.executable == "corepack")
        case .unreadable(let complaint):
            unusable = complaint
            if versionCommand.executable == "corepack" {
                advice = corepackInstallRemediation
            } else {
                advice = await muteToolRemediation(
                    requirement.name, anchor: anchor, context: context, using: runner
                )
            }
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
                remediation: versionMismatchRemediation
            )
        }
        return .pass(observed: observed, required: required, source: source)
    }

    private var usesCorepack: Bool {
        requirement.name == "yarn" || requirement.name == "pnpm"
    }

    private var corepackInstallRemediation: Remediation {
        let directory = anchor.workspaceRoot?.directory ?? anchor.directory
        return Remediation(
            summary: "Prepare the declared package manager, then re-run mobile doctor. mobile keeps Corepack offline.",
            command: "cd \(shellArgument(directory.path)) && corepack install"
        )
    }

    private var versionMismatchRemediation: Remediation {
        if usesCorepack { return corepackInstallRemediation }
        if requirement.name == "bun" {
            return Remediation(
                summary: "Use bun \(requirement.version), then re-run mobile doctor.",
                url: "https://bun.sh/"
            )
        }
        return Remediation(
            summary: "Use \(requirement.name) \(requirement.version), then re-run mobile doctor."
        )
    }

    private func missingExecutableRemediation(corepack: Bool) -> Remediation {
        if corepack {
            return Remediation(
                summary: "Install Corepack, then prepare the package manager declared by this project.",
                url: "https://github.com/nodejs/corepack#installation"
            )
        }
        return versionMismatchRemediation
    }
}

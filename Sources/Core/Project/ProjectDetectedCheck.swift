import Foundation

/// `project.detected` — which React Native project this is, and whether the two
/// things every later check reads (`ios/`, `node_modules`) are there.
public struct ProjectDetectedCheck: Check {
    public let id = "project.detected"
    public let category = "Project"
    public let title = "React Native project detected"

    private static let source = CheckSource(tier: 1, origin: "package.json")
    private static let required = "a React Native project with an ios/ directory and installed dependencies"

    private let anchor: ProjectAnchor

    public init(anchor: ProjectAnchor) {
        self.anchor = anchor
    }

    public func run() async throws -> CheckOutcome {
        // Whatever the evidence chain settled on, so this line and the Tier 2 checks
        // cannot describe the same project with two different versions. The declared
        // range is the last resort: it is the only thing left when nothing answered.
        let version = anchor.reactNativeVersion?.value ?? anchor.declaredReactNativeVersion
        let dependencies = anchor.hasNodeModules ? "" : ", no node_modules"

        // A managed project generates `ios/` on demand. Its absence says the native
        // checks have nothing to read — it does not say the project is broken.
        guard anchor.hasIOSDirectory else {
            let uninstalled = anchor.hasNodeModules ? "" : "; node_modules is missing too"
            return .unknown(
                reason: "no `ios/` directory — a managed project generates it on demand, "
                    + "so the native checks have nothing to read\(uninstalled)",
                observed: "React Native \(version), no ios/\(dependencies)",
                required: Self.required,
                source: Self.source
            )
        }
        guard anchor.hasNodeModules else {
            return .warning(
                observed: "React Native \(version), node_modules missing",
                required: Self.required,
                source: Self.source,
                remediation: Remediation(
                    summary: "Install the project's dependencies — doctor never installs them for you."
                        + installEvidence,
                    command: anchor.installCommand
                )
            )
        }
        return .pass(
            observed: "React Native \(version) at \(anchor.directory.lastPathComponent)/",
            required: Self.required,
            source: Self.source
        )
    }

    /// Why this command and not another one. The manager and the directory both come
    /// from the lockfile, and a command a human is asked to paste — `npm install` in a
    /// yarn workspace breaks it — has to carry the evidence that chose it (ADR-0003).
    private var installEvidence: String {
        guard let root = anchor.workspaceRoot else { return "" }
        let place = root.directory == anchor.directory ? "" : " at the workspace root"
        return " `\(root.lockfile)`\(place) is what picks it."
    }
}

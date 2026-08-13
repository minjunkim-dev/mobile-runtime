import Foundation

/// `node.version` — is Node installed, and does it match what the project asked
/// for? A pin is team convention (`warning`); `engines` is a declared contract
/// (`error`). Keeping those two apart is the point of this Check.
public struct NodeVersionCheck: Check {
    public let id = "node.version"
    public let category = "Node"
    public let title = "Node version matches what the project requires"

    private let anchor: ProjectAnchor
    private let runner: any ProcessRunner

    public init(anchor: ProjectAnchor, runner: any ProcessRunner) {
        self.anchor = anchor
        self.runner = runner
    }

    public func run() async throws -> CheckOutcome {
        let installed: SemanticVersion
        switch try await probeVersion(of: "node", using: runner) {
        case .reported(let version):
            installed = version
        case .notOnPath:
            return .error(
                observed: "node is not on PATH",
                required: requirement,
                source: source,
                remediation: Remediation(
                    summary: "Install Node, then re-run mobile doctor.",
                    url: "https://nodejs.org/"
                )
            )
        case .unreadable(let reason):
            return .unknown(reason: reason, required: requirement, source: source)
        }
        let observed = "Node \(installed)"

        if let engines = anchor.nodeEngines {
            let source = CheckSource(tier: 1, origin: "package.json engines")
            guard let range = VersionRange(engines) else {
                // Say that the pin went unjudged too, rather than letting the second
                // requirement disappear behind the first one's failure.
                let pin = anchor.nodePin.map { ", so the `\($0.file)` pin was not checked either" } ?? ""
                return .unknown(
                    reason: "could not read `engines.node` (\(engines))\(pin)",
                    observed: observed, required: engines, source: source
                )
            }
            guard range.contains(installed) else {
                return .error(
                    observed: observed,
                    required: "\(engines) (package.json engines)",
                    source: source,
                    remediation: Remediation(
                        summary: "Switch to a Node version that satisfies `engines.node` — "
                            + "the project declares it as a contract, so the build is entitled to refuse.",
                        url: "https://nodejs.org/"
                    )
                )
            }
        }

        if let pin = anchor.nodePin {
            let source = CheckSource(tier: 1, origin: pin.file)
            let required = "\(pin.value) (\(pin.file))"
            guard let expected = VersionPin(pin.value) else {
                return .unknown(
                    reason: "`\(pin.file)` pins `\(pin.value)`, which mobile cannot resolve to a version",
                    observed: observed, required: required, source: source
                )
            }
            guard expected.matches(installed) else {
                return .warning(
                    observed: observed,
                    required: required,
                    source: source,
                    remediation: Remediation(
                        summary: "Switch to the pinned Node version — the team runs on it.",
                        command: "nvm use"
                    )
                )
            }
        }

        return .pass(observed: observed, required: requirement, source: source)
    }

    /// Everything the project declared about Node, for the lines that are not about
    /// one specific declaration. A project that declared nothing still gets this
    /// Check: "is Node installed at all" is a verdict on its own.
    private var requirement: String {
        let declarations = [
            anchor.nodeEngines.map { "\($0) (package.json engines)" },
            anchor.nodePin.map { "\($0.value) (\($0.file))" },
        ].compactMap { $0 }
        return declarations.isEmpty ? "no Node version declared" : declarations.joined(separator: ", ")
    }

    private var source: CheckSource {
        CheckSource(
            tier: 1,
            origin: anchor.nodeEngines != nil ? "package.json engines" : (anchor.nodePin?.file ?? "package.json")
        )
    }
}

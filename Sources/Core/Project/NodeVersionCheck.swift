import Foundation

/// `node.version` — is Node installed, and does it match what the project asked
/// for? A pin is team convention (`warning`); `engines` is a declared contract
/// (`error`). Keeping those two apart is the point of this Check.
public struct NodeVersionCheck: Check {
    public let id = "node.version"
    public let category = "Node"
    public let title = "Node version matches what the project requires"

    private let anchor: ProjectAnchor
    private let context: ConfigContext
    private let runner: any ProcessRunner

    public init(anchor: ProjectAnchor, context: ConfigContext, runner: any ProcessRunner) {
        self.anchor = anchor
        self.context = context
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
        case .unreadable(let complaint):
            // Node is the one tool judged even when nothing was declared — "is it
            // installed" stands on its own — so this is the only Check where the
            // requirement has to be looked up rather than assumed. Declared: a mute
            // Node is as unusable as an absent one, and that is an error. Undeclared:
            // there is nothing it could be failing, so the question stays open
            // (ADR-0004).
            guard anchor.nodePin != nil || !anchor.nodeEngines.isEmpty else {
                return .unknown(
                    reason: "\(complaint), and this project declares no Node version — "
                        + "mobile cannot tell whether the one here would do",
                    observed: complaint, required: requirement, source: source
                )
            }
            return .error(
                observed: complaint,
                required: requirement,
                source: source,
                remediation: await muteToolRemediation(
                    "node", anchor: anchor, context: context, using: runner
                )
            )
        }
        let observed = "Node \(installed)"

        // Every declaration binds, so the requirement is whichever ones the installed
        // Node breaks — that is the stricter side without having to order two ranges
        // against each other (ADR-0003). Each is judged on its own: one range mobile
        // cannot parse must not take the others' verdicts down with it, which is the
        // monorepo silence #26 was filed for, one level in.
        var violated: [NodeEngines] = []
        var unreadable: [NodeEngines] = []
        for engines in anchor.nodeEngines {
            guard let range = VersionRange(engines.range) else {
                unreadable.append(engines)
                continue
            }
            if !range.contains(installed) { violated.append(engines) }
        }

        // A broken contract outranks an unreadable one: it is a judgement, not a gap.
        if !violated.isEmpty {
            return .error(
                observed: observed,
                required: violated.map(\.described).joined(separator: ", "),
                source: source(of: violated),
                remediation: Remediation(
                    summary: "Switch to a Node version that satisfies `engines.node` — "
                        + "the project declares it as a contract, so the build is entitled to refuse.",
                    url: "https://nodejs.org/"
                )
            )
        }
        if !unreadable.isEmpty {
            // Say that the pin went unjudged too, rather than letting the second
            // requirement disappear behind the first one's failure.
            let pin = anchor.nodePin.map { ", so the `\($0.file)` pin was not checked either" } ?? ""
            let ranges = unreadable
                .map { "`engines.node` (\($0.range)) in \($0.origin)" }
                .joined(separator: " and ")
            return .unknown(
                reason: "could not read \(ranges)\(pin)",
                observed: observed,
                required: unreadable.map(\.described).joined(separator: ", "),
                source: source(of: unreadable)
            )
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
                        command: try await VersionManagerCommand.detect(
                            for: .node, version: pin.value, runner: runner
                        )
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
        let declarations = anchor.nodeEngines.map(\.described)
            + [anchor.nodePin.map { "\($0.value) (\($0.file))" }].compactMap { $0 }
        return declarations.isEmpty ? "no Node version declared" : declarations.joined(separator: ", ")
    }

    /// Every declaration that produced the verdict, not just the nearest one: with a
    /// workspace root in play two `package.json` files answer, and naming one of them
    /// would misreport which was read (ADR-0003).
    private func source(of engines: [NodeEngines]) -> CheckSource {
        CheckSource(tier: 1, origin: engines.map(\.origin).joined(separator: ", "))
    }

    private var source: CheckSource {
        anchor.nodeEngines.isEmpty
            ? CheckSource(tier: 1, origin: anchor.nodePin?.file ?? "package.json")
            : source(of: anchor.nodeEngines)
    }
}

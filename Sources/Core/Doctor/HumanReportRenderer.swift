import Foundation

/// flutter-doctor-shaped output: one line per category, remediation indented
/// underneath. Grouping is by subject, never by tier — tiers are an internal idea.
public struct HumanReportRenderer: Sendable {
    private let useColor: Bool
    private let verbose: Bool

    public init(useColor: Bool, verbose: Bool = false) {
        self.useColor = useColor
        self.verbose = verbose
    }

    public func render(_ report: DoctorReport) -> String {
        var lines: [String] = []

        for category in orderedCategories(of: report.checks) {
            let group = DoctorReport(checks: report.checks.filter { $0.category == category })
            let checks = group.checks
            let status = group.status
            // The reason for an unknown belongs on its own indented line, not here.
            let headline = group.worstCheck?.outcome.headline

            lines.append(
                "[\(paint(symbol(status), status))] \(category)"
                    + (headline.map { " — \($0)" } ?? "")
            )

            for check in checks {
                lines.append(contentsOf: detail(for: check))
            }
        }

        if report.status == .pass && !report.checks.isEmpty {
            lines.append("")
            lines.append(paint("No issues found.", .pass))
        }

        return lines.joined(separator: "\n")
    }

    private func detail(for check: CheckResult) -> [String] {
        var lines: [String] = []

        if verbose {
            lines.append("    · \(check.id) [\(check.status.rawValue)] \(check.title)")
            if let observed = check.outcome.observed { lines.append("      observed: \(observed)") }
            if let required = check.outcome.required { lines.append("      required: \(required)") }
            let tier = check.outcome.source.tier.map { " (tier \($0))" } ?? ""
            lines.append("      source:   \(check.outcome.source.origin)\(tier)")
            // Detail must never say less than the summary does: without this, an
            // `unknown` loses the one thing it has to say the moment `-v` is passed.
            if let reason = check.outcome.reason { lines.append("      reason:   \(reason)") }
        }

        if let remediation = check.outcome.remediation {
            lines.append("    → \(remediation.summary)")
            if let command = remediation.command { lines.append("      \(paint(command, .warning))") }
            if let url = remediation.url { lines.append("      \(url)") }
        } else if check.status == .unknown, let reason = check.outcome.reason, !verbose {
            lines.append("    ? \(reason)")
        }

        return lines
    }

    private func orderedCategories(of checks: [CheckResult]) -> [String] {
        var seen: Set<String> = []
        return checks.map(\.category).filter { seen.insert($0).inserted }
    }

    private func symbol(_ status: CheckStatus) -> String {
        switch status {
        case .pass: "✓"
        case .warning: "!"
        case .error: "✗"
        case .unknown: "?"
        }
    }

    private func paint(_ text: String, _ status: CheckStatus) -> String {
        guard useColor else { return text }
        let code = switch status {
        case .pass: "32"
        case .warning: "33"
        case .error: "31"
        case .unknown: "90"
        }
        return "\u{1B}[\(code)m\(text)\u{1B}[0m"
    }
}

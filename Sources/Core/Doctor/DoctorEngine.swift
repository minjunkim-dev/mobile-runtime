import Foundation

public struct DoctorReport: Sendable {
    public let checks: [CheckResult]
    /// Infrastructure failures (spawn, timeout). These make it a tool failure, not
    /// a domain failure — the difference between exit 2 and exit 1.
    public let toolFailures: [String]

    public init(checks: [CheckResult], toolFailures: [String] = []) {
        self.checks = checks
        self.toolFailures = toolFailures
    }

    public var status: CheckStatus { CheckStatus.aggregate(checks.map(\.status)) }
    public var hasToolFailure: Bool { !toolFailures.isEmpty }

    /// The check whose status decides the aggregate — what the human sees first.
    ///
    /// Ties go to the most project-specific one. Folding a category to its worst check
    /// answers nothing when they all pass, and letting order decide put "Xcode is
    /// installed" where the verdict that took a lockfile and a `.xcode-version` to
    /// reach should have been: a host fact is the least interesting thing a passing
    /// category can say. Equal severity and equal tier keep the order they were
    /// registered in.
    public var worstCheck: CheckResult? {
        checks.max {
            ($0.status.severity, $0.outcome.source.tier ?? 0)
                < ($1.status.severity, $1.outcome.source.tier ?? 0)
        }
    }

    /// 0 = no errors (warnings and unknowns still pass), 1 = domain failure,
    /// 2 = tool failure. 64 (usage) is the CLI parser's, not ours.
    public var exitCode: Int32 {
        if hasToolFailure { return 2 }
        return status == .error ? 1 : 0
    }
}

/// Runs Checks. No fail-fast, no cache: every run measures the machine again, and
/// one failing Check never hides the rest.
public struct DoctorEngine: Sendable {
    private let checks: [any Check]

    public init(checks: [any Check]) {
        self.checks = checks
    }

    public var checkIDs: [String] { checks.map(\.id) }

    /// - Parameter only: run just these ids (plus their dependencies). `up`'s
    ///   validate stage reuses the engine this way. `nil` runs everything.
    public func run(only ids: Set<String>? = nil) async -> DoctorReport {
        let selected = select(ids)
        var results: [String: CheckResult] = [:]
        var toolFailures: [String] = []
        var pending = selected

        while !pending.isEmpty {
            let ready = pending.filter { check in
                check.dependsOn.allSatisfy { results[$0] != nil }
            }
            guard !ready.isEmpty else {
                // Dependency cycle, or a dependency outside the selection.
                for check in pending {
                    results[check.id] = CheckResult(
                        id: check.id, category: check.category, title: check.title,
                        outcome: .unknown(reason: "dependencies could not be resolved")
                    )
                }
                break
            }

            let round = await withTaskGroup(of: (CheckResult, String?).self) { group in
                for check in ready {
                    let blocker = check.dependsOn.first { results[$0]?.status != .pass }
                    group.addTask { await Self.execute(check, blockedBy: blocker) }
                }
                var collected: [(CheckResult, String?)] = []
                for await outcome in group { collected.append(outcome) }
                return collected
            }

            for (result, failure) in round {
                results[result.id] = result
                if let failure { toolFailures.append(failure) }
            }
            pending.removeAll { results[$0.id] != nil }
        }

        return DoctorReport(
            checks: selected.compactMap { results[$0.id] },
            toolFailures: toolFailures
        )
    }

    /// Returns the result plus a tool-failure description when the Check hit
    /// infrastructure trouble rather than a verdict.
    private static func execute(_ check: any Check, blockedBy blocker: String?) async -> (CheckResult, String?) {
        func result(_ outcome: CheckOutcome) -> CheckResult {
            CheckResult(id: check.id, category: check.category, title: check.title, outcome: outcome)
        }

        if let blocker {
            return (result(.unknown(reason: "depends on `\(blocker)`, which did not pass")), nil)
        }
        do {
            return (result(try await check.run()), nil)
        } catch let error as DomainError {
            // Keep the interpreted sentence in front of the raw tool output — the
            // interpretation is the part a human can act on.
            let observed = [error.summary, error.observed].compactMap { $0 }.joined(separator: " — ")
            return (result(.error(observed: observed, remediation: error.remediation)), nil)
        } catch {
            let description = "\(check.id): \(error)"
            return (result(.unknown(reason: "check could not run — \(error)")), description)
        }
    }

    private func select(_ ids: Set<String>?) -> [any Check] {
        guard let ids else { return checks }
        var wanted = ids
        // Pull in dependencies so a subset caller still gets a meaningful verdict.
        var changed = true
        while changed {
            changed = false
            for check in checks where wanted.contains(check.id) {
                for dependency in check.dependsOn where !wanted.contains(dependency) {
                    wanted.insert(dependency)
                    changed = true
                }
            }
        }
        return checks.filter { wanted.contains($0.id) }
    }
}

import Foundation

/// What asking a tool for its version can tell you. Every version Check needs the
/// same three-way answer; what to *do* about each one differs per tool, so the
/// probe carries no remediation of its own.
enum ToolVersion {
    case reported(SemanticVersion)
    /// The executable is not installed — a verdict about the machine, not a
    /// failure of doctor.
    case notOnPath
    /// It ran and said something else. The string is a ready-to-use `reason`,
    /// including the tool's own first few lines of complaint.
    case unreadable(String)
}

/// - Throws: `ProcessError` for real infrastructure trouble (a timeout). A missing
///   executable is deliberately *not* thrown — it is an answer.
func probeVersion(of executable: String, using runner: any ProcessRunner) async throws -> ToolVersion {
    let result: ProcessResult
    do {
        result = try await runner.run(ProcessCommand(executable, ["--version"], timeout: .seconds(15)))
    } catch let error as ProcessError {
        guard case .spawnFailed = error else { throw error }
        return .notOnPath
    }

    // Not every tool answers with the bare number — `ruby --version` says
    // "ruby 3.2.2 (2023-03-30 …)" — so the first word that reads as a version wins
    // rather than the whole line.
    guard result.terminationStatus.isSuccess,
        let version = result.standardOutput.split(whereSeparator: \.isWhitespace)
            .lazy.compactMap({ SemanticVersion(String($0)) }).first
    else {
        // The tool's own words, so an `unknown` says why it could not tell.
        let complaint = result.standardError
            .split(whereSeparator: \.isNewline)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .prefix(3)
            .map(String.init)
            .joined(separator: " | ")
        let detail = complaint.isEmpty ? "" : " — \(complaint)"
        return .unreadable("`\(executable) --version` did not report a version\(detail)")
    }
    return .reported(version)
}

/// What to say when a tool ran and reported no version. It is on PATH — it answered —
/// so every "install it" command is advice for a different fault: the thing to fix is
/// whatever provides it, and only the tool's own words (carried in `observed`) know
/// which that is. No command beats a wrong one, the rule #27 settled.
func muteToolRemediation(_ executable: String) -> Remediation {
    Remediation(
        summary: "`\(executable)` is on PATH but reports no version, so it cannot be used. "
            + "Fix whatever provides it — the line above is what it said — then re-run mobile doctor."
    )
}

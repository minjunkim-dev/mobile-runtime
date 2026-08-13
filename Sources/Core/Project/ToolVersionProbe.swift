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
    /// including the tool's own first line of complaint.
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

    guard result.terminationStatus.isSuccess, let version = SemanticVersion(result.standardOutput) else {
        // The tool's own words, so an `unknown` says why it could not tell.
        let complaint = result.standardError.split(separator: "\n").first
            .map { " — \($0.trimmingCharacters(in: .whitespaces))" } ?? ""
        return .unreadable("`\(executable) --version` did not report a version\(complaint)")
    }
    return .reported(version)
}

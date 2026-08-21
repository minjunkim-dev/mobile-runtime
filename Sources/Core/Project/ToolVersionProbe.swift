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
    /// including the tool's own complaint.
    case unreadable(String)
}

/// - Throws: `ProcessError` for real infrastructure trouble (a timeout). A missing
///   executable is deliberately *not* thrown — it is an answer.
func probeVersion(of executable: String, using runner: any ProcessRunner) async throws -> ToolVersion {
    try await probeVersion(
        ProcessCommand(executable, ["--version"], timeout: .seconds(15)), using: runner
    )
}

func probeVersion(_ command: ProcessCommand, using runner: any ProcessRunner) async throws -> ToolVersion {
    let result: ProcessResult
    do {
        result = try await runner.run(command)
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
        let complaint = result.combinedOutput
        let detail = complaint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "" : " — \(complaint)"
        return .unreadable("`\(command.description)` did not report a version\(detail)")
    }
    return .reported(version)
}

/// What to say when a tool ran and reported no version. It is on PATH — it answered —
/// so every "install it" command is advice for a different fault: the thing to fix is
/// whatever provides it, and only the tool's own words (carried in `observed`) know
/// which that is. No command beats a wrong one, the rule #27 settled.
func muteToolRemediation(
    _ executable: String,
    anchor: ProjectAnchor,
    context: ConfigContext,
    using runner: any ProcessRunner,
    fileManager: FileManager = .default
) async -> Remediation {
    let generic = Remediation(
        summary: "`\(executable)` is on PATH but reports no version, so it cannot be used. "
            + "Fix whatever provides it — the diagnostic above is what it said — then re-run mobile doctor."
    )
    guard
        let result = try? await runner.run(
            ProcessCommand("which", [executable], timeout: .seconds(15))
        ),
        result.terminationStatus.isSuccess,
        let path = result.standardOutput.split(whereSeparator: \.isNewline).first,
        let owner = shimOwner(of: String(path))
    else { return generic }

    guard owner == .mise else {
        return Remediation(
            summary: "`\(executable)` is a shim provided by \(owner.rawValue), and it reports no version. "
                + "Fix \(owner.rawValue) — the diagnostic above is what it said — then re-run mobile doctor."
        )
    }
    let lookup = await trackedMiseConfig(for: anchor, using: runner, fileManager: fileManager)
    guard case .found(let config) = lookup else {
        return Remediation(
            summary: "`\(executable)` is a shim provided by mise, and mise refused it. "
                + "Ask mise to diagnose its setup — the diagnostic above is what mise said.",
            command: "mise doctor"
        )
    }
    return Remediation(
        summary: "`\(executable)` is a shim provided by mise, and mise refused it. "
            + "This repo commits a mise config, so trust it first — the diagnostic above is what mise said.",
        command: "mise trust \(shellArgument(context.display(config.root)))"
    )
}

private enum ShimOwner: String {
    case mise, asdf, rbenv, rvm
}

private func shimOwner(of path: String) -> ShimOwner? {
    let components = URL(fileURLWithPath: path).pathComponents.map { $0.lowercased() }
    let dots = CharacterSet(charactersIn: ".")
    func hasShims(_ owner: ShimOwner) -> Bool {
        components.indices.dropLast().contains { index in
            components[index].trimmingCharacters(in: dots) == owner.rawValue
                && components[index + 1] == "shims"
        }
    }

    for owner in [ShimOwner.mise, .asdf, .rbenv] where hasShims(owner) {
        return owner
    }
    return components.contains(".rvm") ? .rvm : nil
}

func shellArgument(_ value: String) -> String {
    let safe = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._/"
    )
    guard value.unicodeScalars.allSatisfy({ safe.contains($0) }) else {
        return "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
    return value
}

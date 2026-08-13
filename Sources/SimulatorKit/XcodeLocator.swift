import Core
import Foundation

public struct XcodeInstallation: Sendable, Equatable {
    public enum Origin: String, Sendable {
        case developerDirEnvironment = "DEVELOPER_DIR"
        case xcodeSelect = "xcode-select"
    }

    public let version: String
    public let build: String
    public let developerDirectory: String
    public let origin: Origin

    public var summary: String {
        "Xcode \(version) (\(build)) at \(developerDirectory) via \(origin.rawValue)"
    }
}

/// Owns the `DEVELOPER_DIR` policy: everything that shells out to Xcode tooling
/// pins the developer directory this resolves, so simctl and xcodebuild can never
/// disagree about which Xcode they are talking to.
public actor XcodeLocator {
    private let runner: any ProcessRunner
    private let developerDirOverride: String?
    private var cached: XcodeInstallation?
    private var cachedFailure: DomainError?

    public init(runner: any ProcessRunner, developerDirOverride: String? = ProcessInfo.processInfo.environment["DEVELOPER_DIR"]) {
        self.runner = runner
        // An empty DEVELOPER_DIR is the same as unset.
        self.developerDirOverride = developerDirOverride.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The environment every Xcode-bound subprocess should carry.
    public func pinnedEnvironment() async -> [String: String] {
        guard let installation = try? await locate() else { return [:] }
        return ["DEVELOPER_DIR": installation.developerDirectory]
    }

    /// - Throws: `DomainError` when Xcode is missing or the developer directory is
    ///   unusable; `ProcessError` when the probe itself could not run.
    public func locate() async throws -> XcodeInstallation {
        if let cached { return cached }
        if let cachedFailure { throw cachedFailure }

        do {
            let installation = try await resolve()
            cached = installation
            return installation
        } catch let error as DomainError {
            cachedFailure = error
            throw error
        }
    }

    private func resolve() async throws -> XcodeInstallation {
        let (developerDirectory, origin) = try await developerDirectory()
        let version = try await runner.run(
            ProcessCommand(
                "xcodebuild", ["-version"],
                environment: ["DEVELOPER_DIR": developerDirectory],
                timeout: .seconds(30)
            )
        )

        guard version.terminationStatus.isSuccess else {
            throw Self.interpret(stderr: version.standardError, developerDirectory: developerDirectory)
        }
        guard let parsed = Self.parseVersion(version.standardOutput) else {
            throw DomainError(
                summary: "Could not read the Xcode version.",
                observed: version.standardOutput.trimmed,
                remediation: Remediation(
                    summary: "Check that `xcodebuild -version` prints a version, then re-run mobile doctor.",
                    command: "xcodebuild -version"
                )
            )
        }

        return XcodeInstallation(
            version: parsed.version,
            build: parsed.build,
            developerDirectory: developerDirectory,
            origin: origin
        )
    }

    private func developerDirectory() async throws -> (String, XcodeInstallation.Origin) {
        if let developerDirOverride {
            return (developerDirOverride, .developerDirEnvironment)
        }
        let selected = try await runner.run(ProcessCommand("xcode-select", ["-p"], timeout: .seconds(15)))
        let path = selected.standardOutput.trimmed
        guard selected.terminationStatus.isSuccess, !path.isEmpty else {
            throw DomainError(
                summary: "No active developer directory — Xcode is not installed or not selected.",
                observed: selected.standardError.firstLine ?? "xcode-select -p failed",
                remediation: Remediation(
                    summary: "Install Xcode from the App Store, then point xcode-select at it.",
                    command: "sudo xcode-select -s /Applications/Xcode.app/Contents/Developer",
                    url: "https://developer.apple.com/xcode/"
                )
            )
        }
        return (path, .xcodeSelect)
    }

    /// Turns the exit code + stderr of a failed `xcodebuild -version` into a
    /// domain failure that already knows how to be fixed.
    private static func interpret(stderr: String, developerDirectory: String) -> DomainError {
        let observed = stderr.firstLine ?? "xcodebuild -version failed"
        let selectRemediation = Remediation(
            summary: "Point xcode-select (or DEVELOPER_DIR) at a full Xcode install.",
            command: "sudo xcode-select -s /Applications/Xcode.app/Contents/Developer",
            url: "https://developer.apple.com/xcode/"
        )

        if stderr.contains("command line tools instance") {
            return DomainError(
                summary: "The active developer directory is Command Line Tools, not a full Xcode.",
                observed: observed,
                remediation: selectRemediation
            )
        }
        if stderr.contains("unable to get active developer directory") || stderr.contains("unable to exec Xcode") {
            return DomainError(
                summary: "The developer directory `\(developerDirectory)` does not contain a usable Xcode.",
                observed: observed,
                remediation: selectRemediation
            )
        }
        return DomainError(
            summary: "Xcode did not report a version.",
            observed: observed,
            remediation: selectRemediation
        )
    }

    static func parseVersion(_ output: String) -> (version: String, build: String)? {
        var version: String?
        var build: String?
        for line in output.split(separator: "\n") {
            if line.hasPrefix("Xcode ") {
                version = String(line.dropFirst("Xcode ".count)).trimmed
            } else if line.hasPrefix("Build version ") {
                build = String(line.dropFirst("Build version ".count)).trimmed
            }
        }
        guard let version, let build else { return nil }
        return (version, build)
    }
}

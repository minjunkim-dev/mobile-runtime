import AndroidKit
import Core
import Foundation

/// Existing JDK reuse requires properties and its real home executable. This
/// identity never grants permission to download that vendor's distribution.
struct ToolJavaObservation: Sendable {
    let identity: String
    let executable: URL
    let properties: AndroidJavaObservation

    static func observe(executable: String = "java", directory: URL, runner: any ProcessRunner) async throws -> Self? {
        guard let reported = try await read(executable: executable, directory: directory, runner: runner) else { return nil }
        if executable.hasPrefix("/"), URL(fileURLWithPath: executable).resolvingSymlinksInPath() == reported.executable.resolvingSymlinksInPath() { return reported }
        try Task.checkCancellation()
        guard let actual = try await read(executable: reported.executable.path, directory: directory, runner: runner),
              actual.identity == reported.identity,
              actual.executable.resolvingSymlinksInPath() == reported.executable.resolvingSymlinksInPath() else { return nil }
        return actual
    }

    private static func read(executable: String, directory: URL, runner: any ProcessRunner) async throws -> Self? {
        guard case .success(let java) = try await AndroidDoctorContext.observeJava(executable: executable, directory: directory, runner: runner),
              let declared = java.propertiesVersion, let runtime = java.runtimeVersion,
              let vendor = java.vendor, let home = java.home, let architecture = java.architecture,
              ["aarch64", "arm64"].contains(architecture), home.hasPrefix("/"), !home.contains(":"),
              !home.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        let pattern = #"^([0-9]+\.[0-9]+\.[0-9]+(?:\.[0-9]+)?)\+([0-9]+)(?:-LTS)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: runtime, range: NSRange(runtime.startIndex..., in: runtime)),
              let numericRange = Range(match.range(at: 1), in: runtime), let buildRange = Range(match.range(at: 2), in: runtime) else { return nil }
        let numeric = String(runtime[numericRange])
        let exact = numeric + "+" + runtime[buildRange]
        guard declared == numeric || declared == exact else { return nil }
        let lower = vendor.lowercased()
        let name: String
        if lower.contains("adoptium") || lower.contains("temurin") { name = "temurin" }
        else if lower.contains("azul") || lower.contains("zulu") { name = "zulu" }
        else { name = lower.split(whereSeparator: { !$0.isASCII || !$0.isLetter && !$0.isNumber }).joined(separator: "-") }
        let path = URL(fileURLWithPath: home).appendingPathComponent("bin/java")
        guard !name.isEmpty, FileManager.default.isExecutableFile(atPath: path.path) else { return nil }
        return Self(identity: name + "-" + exact, executable: path, properties: java)
    }

    static func numeric(_ identity: String) -> SemanticVersion? {
        guard let regex = try? NSRegularExpression(pattern: #"(?:^|[-])([0-9]+\.[0-9]+\.[0-9]+)(?:\.[0-9]+)?\+[0-9]+$"#),
              let match = regex.firstMatch(in: identity, range: NSRange(identity.startIndex..., in: identity)),
              let range = Range(match.range(at: 1), in: identity) else { return nil }
        return SemanticVersion(String(identity[range]))
    }
}

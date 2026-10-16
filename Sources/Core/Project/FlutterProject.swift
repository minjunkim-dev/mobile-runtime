import Foundation
import Yams

/// Tier 1 Flutter declarations. Pub itself resolves workspace membership and globs.
public struct FlutterProject: Sendable {
    public let directory: URL
    public let dartRequirement: String
    public let flutterRequirement: String?
    public let pinnedVersion: String?
    public let pinSources: [URL]
    public let usesWorkspace: Bool
    public let entrypoint: URL?

    public init(directory: URL, entrypoint: String? = nil) throws {
        let root = directory.standardizedFileURL.resolvingSymlinksInPath()
        let document = try Self.manifest(root)
        guard let dependencies = document["dependencies"] as? [String: Any],
              let flutter = dependencies["flutter"] as? [String: Any], flutter["sdk"] as? String == "flutter",
              let environment = document["environment"] as? [String: Any],
              let dart = environment["sdk"] as? String, Self.validRange(dart) else {
            throw Self.failure("pubspec.yaml must declare Flutter and a valid Dart SDK constraint")
        }
        let requirement = environment["flutter"] as? String
        guard environment["flutter"] == nil || requirement != nil,
              requirement.map(Self.validRange) ?? true else {
            throw Self.failure("The Flutter SDK constraint cannot be resolved")
        }
        var declarations: [VersionDeclaration] = []
        var managers: Set<String> = []
        var ancestor = root
        while true {
            let local = try Self.versionDeclarations(ancestor, skipping: managers)
            declarations += local
            managers.formUnion(local.map(\.manager))
            if FileManager.default.fileExists(atPath: ancestor.appendingPathComponent(".git").path)
                || ancestor.path == "/" { break }
            ancestor.deleteLastPathComponent()
        }
        let pins = declarations.map(\.version)
        guard pins.allSatisfy({ SemanticVersion($0)?.description == $0 }), Set(pins).count <= 1 else {
            throw Self.failure("Flutter declarations need the same exact stable version; aliases are not installation identities")
        }
        let target = root.appendingPathComponent(entrypoint ?? "lib/main.dart").standardizedFileURL.resolvingSymlinksInPath()
        guard target.path.hasPrefix(root.path + "/"), target.pathExtension == "dart" else {
            throw Self.failure("Choose a Dart entrypoint inside the selected Flutter app")
        }
        guard document["resolution"] == nil || document["resolution"] is NSNull
                || document["resolution"] as? String == "workspace" else {
            throw Self.failure("Resolve the unsupported Dart package resolution manually")
        }
        self.directory = root
        dartRequirement = dart
        flutterRequirement = requirement
        pinnedVersion = pins.first
        pinSources = declarations.map(\.source)
        usesWorkspace = document["resolution"] as? String == "workspace"
        self.entrypoint = (try? target.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true ? target : nil
    }

    private struct VersionDeclaration {
        let manager: String
        let version: String
        let source: URL
    }

    /// A nearer declaration replaces the same manager's ancestor declaration.
    /// Different managers must agree. The repository boundary prevents global pin leakage.
    private static func versionDeclarations(_ root: URL, skipping: Set<String>) throws -> [VersionDeclaration] {
        var values: [VersionDeclaration] = []
        func append(_ version: String, manager: String, file: String) {
            values.append(VersionDeclaration(manager: manager, version: version, source: root.appendingPathComponent(file)))
        }
        if !skipping.contains("fvm"), let data = try Self.optionalData(root.appendingPathComponent(".fvmrc")) {
            guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pin = value["flutter"] as? String else { throw Self.failure("Inspect the Flutter version in .fvmrc") }
            append(pin, manager: "fvm", file: ".fvmrc")
        }
        if !skipping.contains("flutter-version"), let data = try Self.optionalData(root.appendingPathComponent(".flutter-version")) {
            append(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines), manager: "flutter-version", file: ".flutter-version")
        }
        if !skipping.contains("asdf"), let data = try Self.optionalData(root.appendingPathComponent(".tool-versions")) {
            let declarations = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).map {
                $0.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0].split(whereSeparator: \.isWhitespace).map(String.init)
            }.filter { $0.first == "flutter" }
            guard declarations.count <= 1, declarations.allSatisfy({ $0.count == 2 }) else {
                throw Self.failure("Flutter in .tool-versions needs one exact version")
            }
            for declaration in declarations { append(declaration[1], manager: "asdf", file: ".tool-versions") }
        }
        for name in ["mise.toml", ".mise.toml"] {
            if skipping.contains("mise") { break }
            guard let data = try Self.optionalData(root.appendingPathComponent(name)) else { continue }
            var tools = false
            var unsupportedTools = false
            var declared = false
            for raw in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("#") { continue }
                if line.contains("tools"), line.contains("flutter"), line.contains("="), !tools {
                    throw Self.failure("Resolve the Flutter mise declaration to one exact version")
                }
                if line.hasPrefix("[") {
                    let header = line.components(separatedBy: "#")[0].trimmingCharacters(in: .whitespaces)
                    guard !(header.hasPrefix("[tools.") && header.contains("flutter")) else { throw Self.failure("Resolve the Flutter mise declaration to one exact version") }
                    tools = header == "[tools]"
                    unsupportedTools = header.contains("tools") && !tools
                    continue
                }
                if unsupportedTools && line.contains("flutter") {
                    throw Self.failure("Resolve the Flutter mise declaration to one exact version")
                }
                guard tools else { continue }
                let key = line.components(separatedBy: "=")[0].trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                guard key == "flutter" || key.hasPrefix("flutter.") || key.hasSuffix(":flutter") else { continue }
                let pattern = #"^(?:flutter|"flutter"|'flutter')\s*=\s*["']([0-9]+\.[0-9]+\.[0-9]+)["']\s*(?:#.*)?$"#
                guard !declared, let expression = try? NSRegularExpression(pattern: pattern),
                      let match = expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                      let range = Range(match.range(at: 1), in: line) else {
                    throw Self.failure("Resolve the Flutter mise declaration to one exact version")
                }
                declared = true
                append(String(line[range]), manager: "mise", file: name)
            }
        }
        return values
    }

    public func accepts(flutter: String, dart: String) -> Bool {
        guard let sdk = SemanticVersion(dart), let framework = SemanticVersion(flutter),
              Self.matches(dartRequirement, sdk), flutterRequirement.map({ Self.matches($0, framework) }) ?? true else { return false }
        return pinnedVersion == nil || pinnedVersion == flutter
    }

    /// `dart pub workspace list --json` is read-only and uses the SDK's exact workspace rules.
    public func workspace(from data: Data) throws -> FlutterWorkspace {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let packages = object["packages"] as? [[String: Any]], !packages.isEmpty else {
            throw Self.failure("Dart did not return an unambiguous dependency workspace")
        }
        let paths = try packages.map { package -> URL in
            guard let path = package["path"] as? String, path.hasPrefix("/") else {
                throw Self.failure("Dart workspace package identity is missing")
            }
            return URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        }
        let root = paths[0]
        guard paths.contains(where: { $0.path == directory.path }), Set(paths.map(\.path)).count == paths.count,
              paths.allSatisfy({ $0.path == root.path || $0.path.hasPrefix(root.path + "/") }),
              usesWorkspace || root.path == directory.path else { throw Self.failure("Dart workspace does not contain the selected app") }
        var requirements: [String] = []
        var flutterRequirements: [String] = []
        var migration: [String] = []
        for path in paths {
            let document = try Self.manifest(path)
            guard let environment = document["environment"] as? [String: Any],
                  let sdk = environment["sdk"] as? String, Self.validRange(sdk) else {
                throw Self.failure("Every workspace package needs a valid Dart SDK declaration")
            }
            requirements.append(sdk)
            if let requirement = environment["flutter"] {
                guard let value = requirement as? String, Self.validRange(value) else {
                    throw Self.failure("Resolve every workspace Flutter SDK constraint manually")
                }
                flutterRequirements.append(value)
            }
            var ancestor = path
            while ancestor.path != root.path {
                for name in ["pubspec.lock", ".dart_tool/package_config.json"] {
                    let file = ancestor.appendingPathComponent(name)
                    if FileManager.default.fileExists(atPath: file.path) { migration.append(file.path) }
                }
                ancestor.deleteLastPathComponent()
            }
        }
        return FlutterWorkspace(directory: root, packages: paths, dartRequirements: requirements, flutterRequirements: flutterRequirements,
            migrationFiles: Array(Set(migration)).sorted())
    }

    private static func manifest(_ directory: URL) throws -> [String: Any] {
        guard let data = try optionalData(directory.appendingPathComponent("pubspec.yaml")),
              var value = try Yams.load(yaml: String(decoding: data, as: UTF8.self)) as? [String: Any] else {
            throw failure("Read a valid pubspec.yaml before preparing Flutter")
        }
        if let data = try optionalData(directory.appendingPathComponent("pubspec_overrides.yaml")) {
            guard let overrides = try Yams.load(yaml: String(decoding: data, as: UTF8.self)) as? [String: Any],
                  overrides.keys.allSatisfy({ ["resolution", "workspace", "dependency_overrides"].contains($0) }) else {
                throw failure("Inspect unsupported pubspec_overrides.yaml declarations manually")
            }
            for (key, override) in overrides { value[key] = override }
        }
        return value
    }

    private static func optionalData(_ path: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        return try Data(contentsOf: path)
    }
    private static func validRange(_ value: String) -> Bool {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text == "any" { return true }
        // Dart constraints do not inherit npm's x-ranges, tilde, or partial versions.
        let atom = #"(?:\^|>=|<=|>|<)?\s*[0-9]+\.[0-9]+\.[0-9]+"#
        return text.range(of: "^(?:" + atom + ")(?:\\s+(?:" + atom + "))*$", options: .regularExpression) != nil
            && VersionRange(text) != nil
    }
    private static func matches(_ value: String, _ version: SemanticVersion) -> Bool {
        value == "any" || VersionRange(value)?.contains(version) == true
    }
    private static func failure(_ summary: String) -> DomainError {
        DomainError(summary: summary, remediation: Remediation(summary: "Preserve declarations and lockfiles. Resolve the listed input manually, then inspect again."))
    }
}

public struct FlutterWorkspace: Sendable {
    public let directory: URL
    public let packages: [URL]
    public let dartRequirements: [String]
    public let flutterRequirements: [String]
    public let migrationFiles: [String]

    public func accepts(flutter: String, dart: String) -> Bool {
        guard let sdk = SemanticVersion(dart), let framework = SemanticVersion(flutter) else { return false }
        return dartRequirements.allSatisfy { $0 == "any" || VersionRange($0)?.contains(sdk) == true }
            && flutterRequirements.allSatisfy { $0 == "any" || VersionRange($0)?.contains(framework) == true }
    }
}

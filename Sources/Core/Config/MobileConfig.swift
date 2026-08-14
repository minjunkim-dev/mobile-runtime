import Foundation
import Yams

/// Tier 3: the handful of things a project cannot infer, declared by hand next to
/// the anchor. Four fields in v0, and the schema's shape is the boundary's
/// documentation — the top level is genuinely-Tier-3 only, and anything mobile can
/// infer is sayable only inside `overrides:`.
///
/// There is no `schemaVersion` field: a file this small does not get a migration
/// story before it needs one.
public struct MobileConfig: Sendable, Equatable {
    /// `ios.device` — a simulator name, never a UDID. mobile.yml is committed and a
    /// UDID belongs to one machine.
    public let device: String?
    /// `ios.scheme` — which scheme to build. Absent is normal; it only becomes a
    /// problem when the project has more than one scheme to choose from.
    public let scheme: String?
    /// `overrides.xcode` — Tier 2 only. Tier 1 has no override: editing the
    /// declaration file is the correct recovery, and the Remediation says so.
    public let xcode: MinimumVersion?
    /// `overrides.iosRuntime` — Tier 2 only.
    public let iosRuntime: MinimumVersion?

    public init(
        device: String? = nil,
        scheme: String? = nil,
        xcode: MinimumVersion? = nil,
        iosRuntime: MinimumVersion? = nil
    ) {
        self.device = device
        self.scheme = scheme
        self.xcode = xcode
        self.iosRuntime = iosRuntime
    }

    /// The whole v0 schema, written once. Every other place that has to name a
    /// field — the parser, the reports, the override lookup — reads it from here,
    /// so adding a field is this list plus one property above.
    public enum Key {
        public static let device = "ios.device"
        public static let scheme = "ios.scheme"
        public static let xcode = "overrides.xcode"
        public static let iosRuntime = "overrides.iosRuntime"

        public static let all = [device, scheme, xcode, iosRuntime]

        /// `["ios": ["device", "scheme"], …]` — the shape the parser walks.
        static let sections: [String: Set<String>] = all.reduce(into: [:]) { sections, path in
            let parts = path.split(separator: ".", maxSplits: 1)
            sections[String(parts[0]), default: []].insert(String(parts[1]))
        }
    }

    /// What the file actually declares, as `path: value`, for reports.
    public var declarations: [String] {
        [
            (Key.device, device),
            (Key.scheme, scheme),
            (Key.xcode, xcode?.text),
            (Key.iosRuntime, iosRuntime?.text),
        ]
        .compactMap { path, value in value.map { "\(path): \($0)" } }
    }

    public static let fileName = "mobile.yml"
    /// The one misspelling worth naming. Silently ignoring it is the worst failure
    /// available: the file exists, reads correctly, and does nothing.
    public static let misspelledFileName = "mobile.yaml"
}

/// The outcome of reading a mobile.yml. A file that does not parse never degrades
/// into `parsed` with fewer fields — running with an override quietly void is the
/// scenario the whole file exists to prevent.
public enum MobileConfigParse: Sendable, Equatable {
    /// `unknownKeys` are dotted paths, sorted. They are a warning, not a failure:
    /// the rest of the file still applies.
    case parsed(MobileConfig, unknownKeys: [String])
    /// A message that already names where the file broke.
    case invalid(String)
}

extension MobileConfig {
    static func parse(_ text: String) -> MobileConfigParse {
        let root: Any?
        do {
            root = try Yams.load(yaml: text)
        } catch {
            return .invalid(Self.describe(error))
        }
        // An empty file is a legitimate empty configuration, not a broken one.
        guard let root, !(root is NSNull) else { return .parsed(MobileConfig(), unknownKeys: []) }
        guard let mapping = root as? [String: Any] else {
            return .invalid("\(fileName) must be a block of keys, and this one is not")
        }

        var values: [String: String] = [:]
        var unknownKeys: [String] = []

        for (section, contents) in mapping {
            guard let allowed = Key.sections[section] else {
                unknownKeys.append(section)
                continue
            }
            if contents is NSNull { continue }  // `ios:` with nothing under it
            guard let fields = contents as? [String: Any] else {
                return .invalid("`\(section)` must be a block of keys, not a single value")
            }
            for (field, raw) in fields {
                guard allowed.contains(field) else {
                    unknownKeys.append("\(section).\(field)")
                    continue
                }
                if raw is NSNull { continue }
                guard let value = Self.scalar(raw) else {
                    return .invalid("`\(section).\(field)` must be a single value")
                }
                values["\(section).\(field)"] = value
            }
        }

        // An override that is not a version cannot be applied, and applying nothing
        // silently is what this file exists to prevent.
        var overrides: [String: MinimumVersion] = [:]
        for path in [Key.xcode, Key.iosRuntime] {
            guard let text = values[path] else { continue }
            guard let version = MinimumVersion(text) else {
                return .invalid("`\(path): \(text)` is not a version")
            }
            overrides[path] = version
        }

        return .parsed(
            MobileConfig(
                device: values[Key.device],
                scheme: values[Key.scheme],
                xcode: overrides[Key.xcode],
                iosRuntime: overrides[Key.iosRuntime]
            ),
            // Dictionary order is not stable, and this text ends up in a report.
            unknownKeys: unknownKeys.sorted()
        )
    }

    /// YAML types a version or a name can legitimately arrive as. `xcode: 26` is a
    /// number to the parser and a version to a human.
    private static func scalar(_ value: Any) -> String? {
        switch value {
        case let text as String: text
        case let number as Int: "\(number)"
        case let number as Double: "\(number)"
        default: nil
        }
    }

    /// libYAML already knows the line and column; the multi-line snippet it renders
    /// underneath does not fit on a Check's one line.
    private static func describe(_ error: any Error) -> String {
        guard let yaml = error as? YamlError else { return "\(error)" }
        switch yaml {
        case .parser(_, let problem, let mark, _),
            .scanner(_, let problem, let mark, _),
            .composer(_, let problem, let mark, _):
            return "line \(mark.line), column \(mark.column): \(problem)"
        default:
            return yaml.description.split(separator: "\n").first.map(String.init) ?? "\(yaml)"
        }
    }
}

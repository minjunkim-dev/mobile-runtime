import Foundation

/// `config.syntax` — does mobile.yml parse, and does it say only things mobile
/// understands? A declaration gets no special treatment: a file that cannot be
/// read is an `error`, because the alternative is running with an override quietly
/// void, and a key mobile ignores is a `warning`, because the silent version of
/// that is a user who never learns why their setting does nothing.
public struct ConfigSyntaxCheck: Check {
    public let id = "config.syntax"
    public let category = "mobile.yml"
    public let title = "mobile.yml parses and declares only keys mobile understands"

    private static let source = CheckSource(tier: 3, origin: MobileConfig.fileName)
    private static let schema = MobileConfig.Key.all.joined(separator: ", ")

    private let context: ConfigContext

    public init(context: ConfigContext) {
        self.context = context
    }

    public func run() async throws -> CheckOutcome {
        let required = "valid YAML declaring only \(Self.schema)"

        if case .invalid(let message) = context.parse {
            return .error(
                observed: message,
                required: required,
                source: Self.source,
                remediation: Remediation(
                    summary: "Fix the YAML in \(path(context.file)) — mobile does not fall back to "
                        + "inference while a file it cannot read might be overriding one."
                )
            )
        }

        // Both can be true at once, and the file is small enough that a human wants
        // to hear about all of it in one line.
        var complaints: [(observed: String, remediation: Remediation)] = []
        if case .parsed(_, let unknownKeys) = context.parse, !unknownKeys.isEmpty {
            complaints.append(
                (
                    "unknown \(unknownKeys.count == 1 ? "key" : "keys"): \(unknownKeys.joined(separator: ", "))",
                    Remediation(
                        summary: "Correct or remove them in \(path(context.file)) — mobile.yml declares "
                            + "exactly \(MobileConfig.Key.all.count) fields: \(Self.schema)."
                    )
                )
            )
        }
        if let misspelled = context.misspelledFile {
            complaints.append(
                (
                    "\(MobileConfig.misspelledFileName) found, and mobile only reads "
                        + "\(MobileConfig.fileName)",
                    Remediation(
                        summary: "Rename it — a file mobile never reads is the worst kind of silence.",
                        command: "mv \(misspelled.path) "
                            + "\(misspelled.deletingLastPathComponent().appendingPathComponent(MobileConfig.fileName).path)"
                    )
                )
            )
        }

        if let first = complaints.first {
            return .warning(
                observed: complaints.map(\.observed).joined(separator: "; "),
                required: required,
                source: Self.source,
                remediation: first.remediation
            )
        }

        let declarations = context.configuration?.declarations ?? []
        return .pass(
            observed: declarations.isEmpty
                ? "\(MobileConfig.fileName) declares nothing"
                : "\(MobileConfig.fileName) declares \(declarations.joined(separator: ", "))",
            required: required,
            source: Self.source
        )
    }

    private func path(_ url: URL?) -> String {
        url?.path ?? MobileConfig.fileName
    }
}

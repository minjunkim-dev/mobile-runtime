import Foundation

/// What every `--json` document shares: one schema version across all commands,
/// and one encoder. A consumer reads the envelope the same way whichever command
/// wrote it, so the envelope cannot be a per-command decision.
public enum JSONOutput {
    public static let schemaVersion = 1

    public static func encode(_ document: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        // sortedKeys so the same machine state always produces byte-identical output.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(document), as: UTF8.self)
    }
}

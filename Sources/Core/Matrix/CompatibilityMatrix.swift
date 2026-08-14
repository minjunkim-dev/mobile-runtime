import Foundation

/// Tier 2: the requirements no app repo declares, derived from the framework
/// version instead. Bundled into the binary as JSON — offline by construction, and
/// "same mobile version ⇒ same verdict" reproducible. Nothing is fetched at run time.
///
/// Adding a React Native release is a one-row data change; the rows carry a
/// per-platform object so an Android row can join later without moving the iOS
/// fields.
public struct CompatibilityMatrix: Sendable, Decodable {
    /// What this code knows how to read. A bundled file that says anything else is
    /// a build mistake, not a runtime condition to work around.
    public static let supportedSchemaVersion = 1

    public struct IOSRequirements: Sendable, Decodable, Equatable {
        /// Minimum Xcode. Declared nowhere in the repo — this is why Tier 2 exists.
        public let xcode: MinimumVersion
        /// Minimum iOS runtime, i.e. the framework's deployment floor.
        public let runtime: MinimumVersion

        public init(xcode: MinimumVersion, runtime: MinimumVersion) {
            self.xcode = xcode
            self.runtime = runtime
        }
    }

    public struct Row: Sendable, Decodable {
        /// A framework version written to the precision the row applies to: `0.81`
        /// covers every 0.81.x.
        public let version: String
        /// nil once a row exists only for another platform.
        public let ios: IOSRequirements?
    }

    public struct Framework: Sendable, Decodable {
        /// The npm package name, matching the anchor's dependency.
        public let framework: String
        public let rows: [Row]
    }

    public let schemaVersion: Int
    public let frameworks: [Framework]

    public enum LoadError: Error, CustomStringConvertible {
        case resourceMissing
        case unsupportedSchema(found: Int)

        public var description: String {
            switch self {
            case .resourceMissing: "the compatibility matrix is missing from the mobile binary"
            case .unsupportedSchema(let found):
                "the bundled compatibility matrix is schema \(found), "
                    + "but this mobile expects \(CompatibilityMatrix.supportedSchemaVersion)"
            }
        }
    }

    /// The matrix shipped inside this binary.
    public static func bundled() throws -> CompatibilityMatrix {
        guard let url = Bundle.module.url(forResource: "matrix", withExtension: "json") else {
            throw LoadError.resourceMissing
        }
        let matrix = try JSONDecoder().decode(CompatibilityMatrix.self, from: Data(contentsOf: url))
        guard matrix.schemaVersion == supportedSchemaVersion else {
            throw LoadError.unsupportedSchema(found: matrix.schemaVersion)
        }
        return matrix
    }

    /// The row covering `version`, matched by prefix so a patch release lands on
    /// its minor's row. Identifying which row describes a framework version is a
    /// different question from whether a tool version clears a requirement —
    /// requirements go through `MinimumVersion`.
    public func row(framework: String, version: SemanticVersion) -> Row? {
        rows(framework).first { VersionPin($0.version)?.matches(version) == true }
    }

    /// For the "no row for your version" reason — the range a human should read as
    /// "update mobile, or use `mobile.yml`". Computed rather than read off the ends
    /// of the file, so a row appended out of order cannot print a wrong range.
    public func coverage(framework: String) -> String? {
        let versions = rows(framework).compactMap { SemanticVersion($0.version) }
        guard let lowest = versions.min(), let highest = versions.max() else { return nil }
        return "\(lowest.major).\(lowest.minor)–\(highest.major).\(highest.minor)"
    }

    private func rows(_ framework: String) -> [Row] {
        frameworks.first { $0.framework == framework }?.rows ?? []
    }
}

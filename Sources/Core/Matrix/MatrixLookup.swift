import Foundation

/// What the matrix can say about this project right now. Every way of failing to
/// answer collapses into `unavailable` with a ready-to-use `reason`: a Tier 2
/// Check that cannot measure the framework version must say `unknown`, never
/// `pass`. A groundless pass is the miss that costs doctor its credibility.
public enum MatrixLookup: Sendable, Equatable {
    case requirements(CompatibilityMatrix.IOSRequirements, origin: String)
    case unavailable(reason: String)

    public static let reactNative = "react-native"

    /// Where a verdict built on this lookup came from. Tier 2 either way — an
    /// `unknown` is still the matrix's answer.
    public var source: CheckSource {
        switch self {
        case .requirements(_, let origin): CheckSource(tier: 2, origin: origin)
        case .unavailable: CheckSource(tier: 2, origin: "compatibility matrix")
        }
    }

    /// - Parameter load: defaults to the bundled matrix. A load failure is a mobile
    ///   bug rather than a machine fault, and its own words go into the reason.
    public static func resolve(
        anchor: ProjectAnchor,
        loading load: () throws -> CompatibilityMatrix = CompatibilityMatrix.bundled
    ) -> MatrixLookup {
        let matrix: CompatibilityMatrix
        do {
            matrix = try load()
        } catch {
            return .unavailable(reason: "the bundled compatibility matrix could not be read — \(error)")
        }
        // The declared range in package.json is not a measurement: `^0.81.0` says
        // nothing about which minor is installed, and the matrix rows differ by minor.
        guard let installed = anchor.installedReactNativeVersion else {
            return .unavailable(
                reason: "node_modules is absent, so the installed React Native version could not be "
                    + "measured — run `\(anchor.installCommand)` first, then re-run mobile doctor"
            )
        }
        guard let version = SemanticVersion(installed) else {
            return .unavailable(
                reason: "`node_modules/react-native` reports version `\(installed)`, "
                    + "which mobile cannot resolve to a version"
            )
        }
        guard let row = matrix.row(framework: reactNative, version: version) else {
            let coverage = matrix.coverage(framework: reactNative).map { " (it covers \($0))" } ?? ""
            return .unavailable(
                reason: "the compatibility matrix has no row for react-native \(installed)\(coverage)"
            )
        }
        guard let ios = row.ios else {
            return .unavailable(
                reason: "the compatibility matrix row for react-native \(row.version) states no iOS requirements"
            )
        }
        return .requirements(ios, origin: "compatibility matrix (react-native \(row.version))")
    }
}

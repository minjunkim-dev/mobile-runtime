import Foundation

/// One requirement a Tier 2 Check compares against, and where it came from.
public enum RequirementLookup: Sendable, Equatable {
    case requirement(MinimumVersion, source: CheckSource)
    /// Every way of failing to answer collapses here with a ready-to-use `reason`:
    /// a Check that cannot measure must say `unknown`, never `pass`. A groundless
    /// pass is the miss that costs doctor its credibility.
    case unavailable(reason: String, source: CheckSource)

    public var source: CheckSource {
        switch self {
        case .requirement(_, let source), .unavailable(_, let source): source
        }
    }
}

/// What the matrix — corrected by any `mobile.yml` override — can say about this
/// project right now. Resolved per field, because an override names one Tier 2
/// value and leaves the other alone.
public struct MatrixLookup: Sendable, Equatable {
    public let xcode: RequirementLookup
    public let runtime: RequirementLookup

    public init(xcode: RequirementLookup, runtime: RequirementLookup) {
        self.xcode = xcode
        self.runtime = runtime
    }

    public static let reactNative = "react-native"

    /// - Parameter config: `mobile.yml`, when the project has one. Its overrides win
    ///   over the matrix — a stale matrix must never be what stops the work — and
    ///   the conflict is written into the source rather than hidden.
    /// - Parameter load: defaults to the bundled matrix. A load failure is a mobile
    ///   bug rather than a machine fault, and its own words go into the reason.
    public static func resolve(
        anchor: ProjectAnchor,
        config: MobileConfig? = nil,
        loading load: () throws -> CompatibilityMatrix = CompatibilityMatrix.bundled
    ) -> MatrixLookup {
        let answer = self.answer(anchor: anchor, loading: load)
        return MatrixLookup(
            xcode: requirement(
                override: config?.xcode, field: MobileConfig.Key.xcode,
                matrix: answer, value: \.xcode
            ),
            runtime: requirement(
                override: config?.iosRuntime, field: MobileConfig.Key.iosRuntime,
                matrix: answer, value: \.runtime
            )
        )
    }

    /// The matrix's own answer, before mobile.yml gets a say.
    private enum Answer {
        case requirements(CompatibilityMatrix.IOSRequirements, origin: String)
        case unavailable(reason: String)
    }

    private static let matrixOrigin = "compatibility matrix"

    private static func requirement(
        override: MinimumVersion?,
        field: String,
        matrix: Answer,
        value: KeyPath<CompatibilityMatrix.IOSRequirements, MinimumVersion>
    ) -> RequirementLookup {
        guard let override else {
            switch matrix {
            case .requirements(let requirements, let origin):
                return .requirement(requirements[keyPath: value], source: CheckSource(tier: 2, origin: origin))
            case .unavailable(let reason):
                return .unavailable(reason: reason, source: CheckSource(tier: 2, origin: matrixOrigin))
            }
        }

        // The declaration wins. Tier 3, because the requirement is now the user's —
        // and the disagreement it settles is stated, not swallowed.
        var origin = "\(MobileConfig.fileName) \(field)"
        if case .requirements(let requirements, let matrixOrigin) = matrix,
            !requirements[keyPath: value].agrees(with: override) {
            origin += " — the \(matrixOrigin) says \(requirements[keyPath: value])"
        }
        return .requirement(override, source: CheckSource(tier: 3, origin: origin))
    }

    private static func answer(
        anchor: ProjectAnchor,
        loading load: () throws -> CompatibilityMatrix
    ) -> Answer {
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
        return .requirements(ios, origin: "\(matrixOrigin) (react-native \(row.version))")
    }
}

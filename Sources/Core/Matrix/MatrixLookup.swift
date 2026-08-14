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

/// What the matrix — composed with what the repo declared, corrected by any
/// `mobile.yml` override — can say about this project right now. Resolved per field,
/// because an override names one Tier 2 value and leaves the other alone.
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
                declared: anchor.declaredXcodeVersion.map {
                    (value: $0, file: ProjectAnchor.xcodeVersionFile)
                },
                matrix: answer, value: \.xcode
            ),
            runtime: requirement(
                override: config?.iosRuntime, field: MobileConfig.Key.iosRuntime,
                declared: nil, matrix: answer, value: \.runtime
            )
        )
    }

    /// The matrix's own answer, before mobile.yml gets a say.
    private enum Answer {
        case requirements(CompatibilityMatrix.IOSRequirements, origin: String)
        case unavailable(reason: String)
    }

    private static let matrixOrigin = "compatibility matrix"

    /// - Parameter declared: what the repo wrote down for this field, when a Tier 1
    ///   file carries it. `mobile.yml` outranks it: an override exists to stop the
    ///   tool from blocking the work, so composing it with a repo file would take
    ///   that escape hatch back.
    private static func requirement(
        override: MinimumVersion?,
        field: String,
        declared: (value: String, file: String)?,
        matrix: Answer,
        value: KeyPath<CompatibilityMatrix.IOSRequirements, MinimumVersion>
    ) -> RequirementLookup {
        guard let override else {
            if let declared { return composed(declared, matrix: matrix, value: value) }
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

    /// `max(matrix floor, project declaration)` — ADR-0003. The matrix carries the
    /// framework's floor and the repo carries the toolchain it actually builds on, so
    /// neither replaces the other: the stricter one becomes the requirement and the
    /// loser is named in the source, because `-v` is the audit log of the verdict.
    ///
    /// A tie goes to the repo — Tier 1 is the stronger evidence, and it stays the
    /// answer when the matrix has none at all. That is the miss this closes: a
    /// pristine clone used to end at `unknown` with the answer sitting in a file.
    ///
    /// The declaration is read as a floor (`MinimumVersion`), not as the prefix pin
    /// ADR-0003 names: `max` and "the winner" need one ordered scale, and `VersionPin`
    /// has no order. The visible difference is a host newer than the declaration —
    /// `.xcode-version` 26.3 against Xcode 27 passes here, where a prefix pin would
    /// fail it. Both readings catch the miss #25 reports; this one is the weaker
    /// claim, which is the side to be wrong on.
    private static func composed(
        _ declared: (value: String, file: String),
        matrix: Answer,
        value: KeyPath<CompatibilityMatrix.IOSRequirements, MinimumVersion>
    ) -> RequirementLookup {
        let declaration = MinimumVersion(declared.value)
        let unreadable = "\(declared.file) declares \(declared.value), "
            + "which mobile cannot resolve to a version"

        switch matrix {
        case .requirements(let requirements, let origin):
            let floor = requirements[keyPath: value]
            guard let declaration else {
                return .requirement(floor, source: CheckSource(tier: 2, origin: "\(origin) — \(unreadable)"))
            }
            guard !floor.exceeds(declaration) else {
                return .requirement(
                    floor,
                    source: CheckSource(tier: 2, origin: "\(origin) — \(declared.file) declares \(declaration)")
                )
            }
            return .requirement(
                declaration,
                source: CheckSource(tier: 1, origin: "\(declared.file) — the \(origin) says \(floor)")
            )
        case .unavailable(let reason):
            guard let declaration else {
                return .unavailable(
                    reason: "\(reason); \(unreadable)", source: CheckSource(tier: 2, origin: matrixOrigin)
                )
            }
            // The matrix lost by silence rather than by a lower floor, and a verdict
            // standing on one leg says which leg is missing.
            return .requirement(
                declaration,
                source: CheckSource(tier: 1, origin: "\(declared.file) — the \(matrixOrigin) could not answer")
            )
        }
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
        // Every link of the evidence chain came up empty: nothing installed, no
        // lockfile that resolves react-native, and a declared range — which is not a
        // measurement, since `^0.81.0` says nothing about which minor is installed and
        // the matrix rows differ by minor.
        guard let resolved = anchor.reactNativeVersion else {
            return .unavailable(
                reason: "the React Native version could not be resolved — nothing is installed at "
                    + "`node_modules/react-native`, no lockfile mobile reads resolves it, and "
                    + "`\(anchor.declaredReactNativeVersion)` is not a single version. Run "
                    + "`\(anchor.installCommand)` first, then re-run mobile doctor"
            )
        }
        guard let version = SemanticVersion(resolved.value) else {
            return .unavailable(
                reason: "react-native \(resolved.described) is not something mobile can resolve to a version"
            )
        }
        guard let row = matrix.row(framework: reactNative, version: version) else {
            let coverage = matrix.coverage(framework: reactNative).map { " (it covers \($0))" } ?? ""
            return .unavailable(
                reason: "the compatibility matrix has no row for react-native "
                    + "\(resolved.described)\(coverage)"
            )
        }
        guard let ios = row.ios else {
            return .unavailable(
                reason: "the compatibility matrix row for react-native \(row.version) states no iOS requirements"
            )
        }
        // The version carries its evidence, because a Tier 2 verdict now stands on a
        // chain and `-v` is where that chain is auditable (ADR-0003). The row is not
        // named separately — it is this version's minor, so it would only repeat it.
        return .requirements(ios, origin: "\(matrixOrigin) (react-native \(resolved.described))")
    }
}

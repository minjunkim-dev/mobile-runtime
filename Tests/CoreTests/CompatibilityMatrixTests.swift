import Foundation
import TestSupport
import Testing

@testable import Core

@Suite("compatibility matrix")
struct CompatibilityMatrixTests {
    /// The resource is bundled, not fetched, so "does it load and does this code
    /// understand its schema" is the one thing that can silently break in a build.
    @Test("the bundled matrix loads at the schema this code expects")
    func bundledResourceLoads() throws {
        let matrix = try CompatibilityMatrix.bundled()

        #expect(matrix.schemaVersion == CompatibilityMatrix.supportedSchemaVersion)
        #expect(matrix.coverage(framework: "react-native") == "0.73–0.87")
    }

    @Test("every react-native row carries iOS requirements")
    func rowsAreComplete() throws {
        let matrix = try CompatibilityMatrix.bundled()
        let rows = try #require(matrix.frameworks.first { $0.framework == "react-native" }?.rows)

        #expect(rows.count == 15)
        for row in rows {
            #expect(row.ios != nil, "react-native \(row.version) has no iOS requirements")
        }
    }

    @Test("a patch release lands on its minor's row")
    func prefixMatching() throws {
        let matrix = try CompatibilityMatrix.bundled()

        let row = try #require(matrix.row(framework: "react-native", version: SemanticVersion("0.81.4")!))
        #expect(row.version == "0.81")
        #expect(row.ios?.xcode.text == "16.1")
        #expect(row.ios?.runtime.text == "15.1")

        #expect(matrix.row(framework: "react-native", version: SemanticVersion("0.72.0")!) == nil)
        #expect(matrix.row(framework: "expo", version: SemanticVersion("0.81.4")!) == nil)
    }

    @Test("the inflection points from the research data are the ones shipped")
    func inflectionPoints() throws {
        let matrix = try CompatibilityMatrix.bundled()

        func ios(_ version: String) throws -> CompatibilityMatrix.IOSRequirements {
            try #require(matrix.row(framework: "react-native", version: SemanticVersion(version)!)?.ios)
        }

        #expect(try ios("0.75.0").xcode.text == "15.1")
        #expect(try ios("0.75.0").runtime.text == "13.4")
        // 0.76 raised the deployment floor, 0.81 the Xcode floor, 0.87 again.
        #expect(try ios("0.76.0").runtime.text == "15.1")
        #expect(try ios("0.81.0").xcode.text == "16.1")
        #expect(try ios("0.87.0").xcode.text == "26.0")
    }
}

@Suite("MinimumVersion")
struct MinimumVersionTests {
    @Test("a requirement is a floor written at the source's precision")
    func floorSemantics() throws {
        let twentySix = try #require(MinimumVersion("26"))
        #expect(twentySix.isSatisfied(by: SemanticVersion("26.6")!))
        #expect(twentySix.isSatisfied(by: SemanticVersion("26.0")!))
        #expect(twentySix.isSatisfied(by: SemanticVersion("16.1")!) == false)

        let sixteenOne = try #require(MinimumVersion("16.1"))
        #expect(sixteenOne.isSatisfied(by: SemanticVersion("16.1")!))
        #expect(sixteenOne.isSatisfied(by: SemanticVersion("26.0")!))
        #expect(sixteenOne.isSatisfied(by: SemanticVersion("16.0.9")!) == false)
    }

    @Test("nonsense is rejected rather than guessed at")
    func rejectsNonsense() {
        #expect(MinimumVersion("latest") == nil)
        #expect(MinimumVersion("") == nil)
    }

    @Test("the written text is kept for the `required` line")
    func keepsText() throws {
        #expect(try #require(MinimumVersion("26")).description == "26")
    }
}

@Suite("matrix lookup")
struct MatrixLookupTests {
    private func anchor(_ repo: FixtureRepo, installed: String?) throws -> ProjectAnchor {
        try repo.write("package.json", #"{"dependencies": {"react-native": "^0.81.0"}}"#)
        if let installed {
            try repo.write("node_modules/react-native/package.json", #"{"version": "\#(installed)"}"#)
        }
        return try #require(ProjectAnchor.detect(from: repo.root))
    }

    /// Both Tier 2 Checks answer `unknown` from the same reason, so a scenario that
    /// is about the matrix failing only has to read one field.
    private func reason(_ lookup: RequirementLookup) -> String {
        guard case .unavailable(let reason, let source) = lookup else {
            Issue.record("expected unavailable, got \(lookup)")
            return ""
        }
        #expect(source.tier == 2)
        return reason
    }

    private func requirement(_ lookup: RequirementLookup) -> (MinimumVersion, CheckSource)? {
        guard case .requirement(let version, let source) = lookup else {
            Issue.record("expected a requirement, got \(lookup)")
            return nil
        }
        return (version, source)
    }

    @Test("resolves against the installed version, not the declared range")
    func resolvesFromInstalled() throws {
        let repo = try FixtureRepo()
        let lookup = MatrixLookup.resolve(
            anchor: try anchor(repo, installed: "0.87.2"))

        let (xcode, source) = try #require(requirement(lookup.xcode))
        // The declared `^0.81.0` would have answered 16.1 — the installed 0.87 is what counts.
        #expect(xcode.text == "26.0")
        #expect(source.origin == "compatibility matrix (react-native 0.87)")
        #expect(source.tier == 2)
    }

    @Test("without node_modules there is no measurement — and the install command says so")
    func dependenciesMissing() throws {
        let repo = try FixtureRepo()
        try repo.write(
            "package.json",
            #"{"dependencies": {"react-native": "0.81.0"}, "packageManager": "yarn@3.6.4"}"#
        )
        let anchor = try #require(ProjectAnchor.detect(from: repo.root))

        let lookup = MatrixLookup.resolve(anchor: anchor)

        #expect(reason(lookup.xcode).contains("node_modules is absent"))
        #expect(reason(lookup.runtime).contains("yarn install"))
    }

    @Test("a React Native version outside the matrix is unavailable, not a pass")
    func outsideCoverage() throws {
        let repo = try FixtureRepo()
        let lookup = MatrixLookup.resolve(
            anchor: try anchor(repo, installed: "0.99.0"))

        #expect(reason(lookup.xcode).contains("no row for react-native 0.99.0"))
        #expect(reason(lookup.xcode).contains("0.73–0.87"))
    }

    @Test("an unreadable installed version is unavailable")
    func unreadableVersion() throws {
        let repo = try FixtureRepo()
        let lookup = MatrixLookup.resolve(
            anchor: try anchor(repo, installed: "nightly"))

        #expect(reason(lookup.xcode).contains("nightly"))
    }

    @Test("a matrix that would not load never becomes a pass, and says why")
    func matrixMissing() throws {
        let repo = try FixtureRepo()
        let lookup = MatrixLookup.resolve(anchor: try anchor(repo, installed: "0.81.4")) {
            throw CompatibilityMatrix.LoadError.unsupportedSchema(found: 2)
        }

        // The loader's own words, not a generic "could not be read".
        #expect(reason(lookup.xcode).contains("schema 2"))
    }
}

/// Tier 3 correcting Tier 2: a stale matrix must never be the thing that stops the
/// work, and the correction must never be invisible.
@Suite("mobile.yml overrides")
struct MatrixOverrideTests {
    private func lookup(
        installed: String? = "0.81.4",
        _ config: MobileConfig
    ) throws -> MatrixLookup {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies": {"react-native": "^0.81.0"}}"#)
        if let installed {
            try repo.write("node_modules/react-native/package.json", #"{"version": "\#(installed)"}"#)
        }
        return MatrixLookup.resolve(
            anchor: try #require(ProjectAnchor.detect(from: repo.root)), config: config
        )
    }

    @Test("the declared version wins, and the disagreement is stated in the source")
    func overrideWins() throws {
        let lookup = try lookup(MobileConfig(xcode: MinimumVersion("26")))

        guard case .requirement(let xcode, let source) = lookup.xcode else {
            Issue.record("expected a requirement, got \(lookup.xcode)")
            return
        }
        #expect(xcode.text == "26")
        #expect(source.tier == 3)
        #expect(source.origin.contains("mobile.yml overrides.xcode"))
        // The matrix's own answer for 0.81, not swallowed.
        #expect(source.origin.contains("16.1"))
    }

    /// Agreement is not a conflict, and "26" is not a different floor from "26.0".
    @Test("an override that agrees with the matrix reports no disagreement")
    func overrideAgrees() throws {
        let lookup = try lookup(MobileConfig(xcode: MinimumVersion("16.1.0")))

        guard case .requirement(_, let source) = lookup.xcode else {
            Issue.record("expected a requirement, got \(lookup.xcode)")
            return
        }
        #expect(source.origin == "mobile.yml overrides.xcode")
    }

    /// Story 17: the tool being wrong must not be what stops the work — and that
    /// includes the tool being unable to answer at all.
    @Test("an override answers even when the matrix cannot")
    func overrideWithoutMatrix() throws {
        let lookup = try lookup(installed: nil, MobileConfig(iosRuntime: MinimumVersion("18.0")))

        guard case .requirement(let runtime, let source) = lookup.runtime else {
            Issue.record("expected a requirement, got \(lookup.runtime)")
            return
        }
        #expect(runtime.text == "18.0")
        #expect(source.origin == "mobile.yml overrides.iosRuntime")
        // The field nobody declared still has nothing to stand on.
        #expect(lookup.xcode == .unavailable(
            reason: "node_modules is absent, so the installed React Native version could not be "
                + "measured — run `npm install` first, then re-run mobile doctor",
            source: CheckSource(tier: 2, origin: "compatibility matrix")
        ))
    }

    @Test("overriding one requirement leaves the other on the matrix")
    func overrideIsPerField() throws {
        let lookup = try lookup(MobileConfig(xcode: MinimumVersion("26")))

        guard case .requirement(let runtime, let source) = lookup.runtime else {
            Issue.record("expected a requirement, got \(lookup.runtime)")
            return
        }
        #expect(runtime.text == "15.1")
        #expect(source.tier == 2)
    }
}

/// Tier 1 composing with Tier 2: the matrix carries the framework's floor, the repo's
/// `.xcode-version` carries the one this project actually builds on. The requirement
/// is `max` of the two, and the loser is still named — see ADR-0003.
@Suite(".xcode-version declaration")
struct XcodeDeclarationTests {
    private func lookup(
        installed: String? = "0.81.4",
        declares: String?,
        config: MobileConfig? = nil
    ) throws -> MatrixLookup {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies": {"react-native": "^0.81.0"}}"#)
        if let installed {
            try repo.write("node_modules/react-native/package.json", #"{"version": "\#(installed)"}"#)
        }
        if let declares {
            try repo.write(".xcode-version", "\(declares)\n")
        }
        return MatrixLookup.resolve(
            anchor: try #require(ProjectAnchor.detect(from: repo.root)), config: config
        )
    }

    private func requirement(_ lookup: RequirementLookup) -> (MinimumVersion, CheckSource)? {
        guard case .requirement(let version, let source) = lookup else {
            Issue.record("expected a requirement, got \(lookup)")
            return nil
        }
        return (version, source)
    }

    /// The miss #25 reports: the matrix floor for RN 0.81 is Xcode 16.1, the repo says
    /// 26.3, and a host with 16.1 must not be told it is fine.
    @Test("the declaration wins when it asks for more than the matrix floor")
    func declarationWins() throws {
        let (xcode, source) = try #require(requirement(try lookup(declares: "26.3").xcode))

        #expect(xcode.text == "26.3")
        #expect(source.tier == 1)
        #expect(source.origin == ".xcode-version — the compatibility matrix (react-native 0.81) says 16.1")
    }

    @Test("the matrix floor wins when it is the stricter one, and the declaration is still named")
    func matrixWins() throws {
        let (xcode, source) = try #require(requirement(try lookup(installed: "0.87.2", declares: "16.2").xcode))

        #expect(xcode.text == "26.0")
        #expect(source.tier == 2)
        #expect(source.origin == "compatibility matrix (react-native 0.87) — .xcode-version declares 16.2")
    }

    /// The pristine-clone case: no node_modules, so the matrix cannot answer — but the
    /// repo already wrote the answer down. `unknown` is no longer the end of it.
    @Test("the declaration answers even when the matrix cannot")
    func declarationWithoutMatrix() throws {
        let lookup = try lookup(installed: nil, declares: "26.3")

        let (xcode, source) = try #require(requirement(lookup.xcode))
        #expect(xcode.text == "26.3")
        #expect(source.tier == 1)
        // The matrix lost by silence, and the source says so rather than implying
        // there was only ever one ground.
        #expect(source.origin == ".xcode-version — the compatibility matrix could not answer")
        // The runtime axis declares nothing here, so it stays unmeasured.
        #expect(lookup.runtime.isUnavailable)
    }

    /// `mobile.yml` is the user correcting the tool, so it settles the requirement on
    /// its own — composing it with a file in the repo would take that escape hatch back.
    @Test("mobile.yml still outranks the file")
    func overrideOutranksDeclaration() throws {
        let (xcode, source) = try #require(
            requirement(try lookup(declares: "26.3", config: MobileConfig(xcode: MinimumVersion("16.1"))).xcode)
        )

        #expect(xcode.text == "16.1")
        #expect(source.tier == 3)
        #expect(source.origin == "mobile.yml overrides.xcode")
    }

    @Test("a declaration mobile cannot read falls back to the matrix and says so")
    func unreadableDeclaration() throws {
        let (xcode, source) = try #require(requirement(try lookup(declares: "latest").xcode))

        #expect(xcode.text == "16.1")
        #expect(source.tier == 2)
        #expect(source.origin.contains(".xcode-version declares latest, which mobile cannot resolve"))
    }

    @Test("an unreadable declaration with no matrix answer is unknown, not a pass")
    func unreadableDeclarationWithoutMatrix() throws {
        let lookup = try lookup(installed: nil, declares: "latest")

        guard case .unavailable(let reason, _) = lookup.xcode else {
            Issue.record("expected unavailable, got \(lookup.xcode)")
            return
        }
        #expect(reason.contains("node_modules is absent"))
        #expect(reason.contains(".xcode-version declares latest"))
    }
}

extension RequirementLookup {
    fileprivate var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }
}

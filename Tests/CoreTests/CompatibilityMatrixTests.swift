import Foundation
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

    @Test("resolves against the installed version, not the declared range")
    func resolvesFromInstalled() throws {
        let repo = try FixtureRepo()
        let lookup = MatrixLookup.resolve(
            anchor: try anchor(repo, installed: "0.87.2"))

        guard case .requirements(let requirements, let origin) = lookup else {
            Issue.record("expected requirements, got \(lookup)")
            return
        }
        // The declared `^0.81.0` would have answered 16.1 — the installed 0.87 is what counts.
        #expect(requirements.xcode.text == "26.0")
        #expect(origin == "compatibility matrix (react-native 0.87)")
        #expect(lookup.source.tier == 2)
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

        guard case .unavailable(let reason) = lookup else {
            Issue.record("expected unavailable, got \(lookup)")
            return
        }
        #expect(reason.contains("node_modules is absent"))
        #expect(reason.contains("yarn install"))
    }

    @Test("a React Native version outside the matrix is unavailable, not a pass")
    func outsideCoverage() throws {
        let repo = try FixtureRepo()
        let lookup = MatrixLookup.resolve(
            anchor: try anchor(repo, installed: "0.99.0"))

        guard case .unavailable(let reason) = lookup else {
            Issue.record("expected unavailable, got \(lookup)")
            return
        }
        #expect(reason.contains("no row for react-native 0.99.0"))
        #expect(reason.contains("0.73–0.87"))
    }

    @Test("an unreadable installed version is unavailable")
    func unreadableVersion() throws {
        let repo = try FixtureRepo()
        let lookup = MatrixLookup.resolve(
            anchor: try anchor(repo, installed: "nightly"))

        guard case .unavailable(let reason) = lookup else {
            Issue.record("expected unavailable, got \(lookup)")
            return
        }
        #expect(reason.contains("nightly"))
    }

    @Test("a matrix that would not load never becomes a pass, and says why")
    func matrixMissing() throws {
        let repo = try FixtureRepo()
        let lookup = MatrixLookup.resolve(anchor: try anchor(repo, installed: "0.81.4")) {
            throw CompatibilityMatrix.LoadError.unsupportedSchema(found: 2)
        }

        guard case .unavailable(let reason) = lookup else {
            Issue.record("expected unavailable, got \(lookup)")
            return
        }
        // The loader's own words, not a generic "could not be read".
        #expect(reason.contains("schema 2"))
    }

}

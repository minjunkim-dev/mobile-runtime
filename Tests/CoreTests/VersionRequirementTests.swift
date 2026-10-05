import Testing

@testable import Core

/// The comparator is pure arithmetic shared by every version verdict in the tool,
/// so it gets a table rather than being re-derived through each Check.
@Suite("version requirements")
struct VersionRequirementTests {
    @Test("parses the shapes tools actually print")
    func parsing() {
        #expect(SemanticVersion("v20.11.1") == SemanticVersion("20.11.1"))
        #expect(SemanticVersion("3.6.4+sha224.abc") == SemanticVersion("3.6.4"))
        #expect(SemanticVersion("18") == SemanticVersion("18.0.0"))
        #expect(SemanticVersion("not a version") == nil)
    }

    @Test("orders versions numerically, not lexically")
    func ordering() throws {
        let nine = try #require(SemanticVersion("9.1.0"))
        let ten = try #require(SemanticVersion("10.0.0"))

        #expect(nine < ten)
        #expect(try #require(SemanticVersion("20.11.1")) > #require(SemanticVersion("20.2.0")))
    }

    @Test(
        "satisfies the range shapes that appear in engines.node",
        arguments: [
            (">=18", "20.11.1", true),
            (">=22", "20.11.1", false),
            (">=18 <21", "20.11.1", true),
            (">=18 <21", "21.0.0", false),
            ("^20.9.0", "20.11.1", true),
            ("^18", "20.11.1", false),
            ("~20.11.0", "20.11.1", true),
            ("~20.10.0", "20.11.1", false),
            ("18 || 20", "20.11.1", true),
            ("18 || 19", "20.11.1", false),
            ("*", "20.11.1", true),
            (">= 18.0.0", "20.11.1", true),
        ]
    )
    func rangeSatisfaction(range: String, version: String, expected: Bool) throws {
        let requirement = try #require(VersionRange(range))
        #expect(requirement.contains(try #require(SemanticVersion(version))) == expected)
    }

    @Test("an unreadable range is nil, so the caller can answer `unknown` instead of guessing")
    func unreadableRange() {
        #expect(VersionRange("18 - 20") == nil)
        #expect(VersionRange("lts/hydrogen") == nil)
        #expect(VersionRange("") == nil)
    }

    @Test("a pin matches by prefix — `20` covers every 20.x")
    func pinPrefixMatching() throws {
        let node = try #require(SemanticVersion("20.11.1"))

        #expect(VersionPin("20")?.matches(node) == true)
        #expect(VersionPin("20.11")?.matches(node) == true)
        #expect(VersionPin("v20.11.1")?.matches(node) == true)
        #expect(VersionPin("20.10")?.matches(node) == false)
        #expect(VersionPin("18")?.matches(node) == false)
        // An alias is not a version; the caller turns this into `unknown`.
        #expect(VersionPin("lts/hydrogen") == nil)
    }
}

import Foundation
import TestSupport
import Testing

@testable import Core

/// What the gem files ask of CocoaPods, which is what decides the grade when `pod`
/// cannot be measured (ADR-0004). The version ask and the existence ask are separate
/// questions, and reading only the lock made the Check disappear on a repo that had
/// not committed one.
@Suite("cocoapods requirement")
struct CocoaPodsRequirementTests {
    private func requirement(gemfile: String? = nil, lock: String? = nil) throws
        -> CocoaPodsRequirement?
    {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies": {"react-native": "0.76.5"}}"#)
        if let gemfile { try repo.write("Gemfile", gemfile) }
        if let lock { try repo.write("Gemfile.lock", lock) }
        return ProjectAnchor.detect(from: repo.root)?.cocoapods
    }

    private func lock(_ specs: String) -> String { "GEM\n  specs:\n\(specs)\n" }

    /// A project managing no gems never asked, and a verdict invented for it is noise.
    @Test("no gem files means no requirement at all")
    func noGemFiles() throws {
        #expect(try requirement() == nil)
    }

    @Test("a locked version is the strongest ask, even when the Gemfile also names the gem")
    func lockWins() throws {
        let requirement = try #require(try requirement(
            gemfile: "gem 'cocoapods'\n",
            lock: lock("    cocoapods (1.15.2)")
        ))

        #expect(requirement.level == .version("1.15.2"))
        #expect(requirement.file == "Gemfile.lock")
    }

    /// joplin: the Gemfile asks, no lock is committed. Existence is settled; the
    /// version is not.
    @Test("a Gemfile alone settles that CocoaPods must be installed")
    func gemfileAlone() throws {
        let requirement = try #require(try requirement(gemfile: "gem 'cocoapods'\n"))

        #expect(requirement.level == .installed)
        #expect(requirement.file == "Gemfile")
    }

    /// Real Gemfiles space and qualify the line however they like, and the gem name is
    /// compared whole so a different gem that starts the same way does not count.
    @Test("the gem line is read by its words, not by an exact spelling")
    func gemLineShapes() throws {
        #expect(try requirement(gemfile: "gem  \"cocoapods\", \"~> 1.15\"\n")?.level == .installed)
        #expect(try requirement(gemfile: "  gem 'cocoapods', '>= 1.13'\n")?.level == .installed)
        #expect(try requirement(gemfile: "gem 'cocoapods-core'\n")?.level == .unconfirmed)
    }

    /// The lock exists and pins other gems: the project manages gems but has not asked
    /// for CocoaPods, so a missing `pod` is not its fault.
    @Test("gem files that never name cocoapods confirm no requirement")
    func unconfirmed() throws {
        let requirement = try #require(try requirement(lock: lock("    fastlane (2.219.0)")))

        #expect(requirement.level == .unconfirmed)
        #expect(requirement.file == "Gemfile.lock")
    }

    /// `DEPENDENCIES` repeats the gem with the range the Gemfile asked for; only the
    /// four-space `specs:` entry is the resolved version.
    @Test("the locked version comes from specs, not from DEPENDENCIES")
    func specsSection() throws {
        let requirement = try #require(try requirement(
            lock: """
                GEM
                  specs:
                    cocoapods (1.15.2)
                    cocoapods-core (1.15.2)

                DEPENDENCIES
                  cocoapods (>= 1.13, != 1.15.0)
                """
        ))

        #expect(requirement.level == .version("1.15.2"))
    }
}

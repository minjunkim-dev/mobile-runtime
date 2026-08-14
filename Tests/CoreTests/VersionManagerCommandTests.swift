import Foundation
import TestSupport
import Testing

@testable import Core

/// A remediation command that is not installed is not a remediation. The dogfooding
/// host runs mise, and doctor told it to run `nvm use` and `rbenv install` — both
/// `command not found`. So the command comes from what this host actually has.
@Suite("version manager commands")
struct VersionManagerCommandTests {
    private func onPath(_ managers: String...) -> FakeProcessRunner {
        FakeProcessRunner(
            responses: Dictionary(
                uniqueKeysWithValues: managers.map { ("\($0) --version", .ok("1.0.0\n")) }
            )
        )
    }

    @Test("mise wins when it is there, and the command names the version")
    func misePreferred() async throws {
        let command = try await VersionManagerCommand.detect(
            for: .node, version: "24.15.0", runner: onPath("mise", "fnm", "asdf"), environment: [:]
        )

        #expect(command == "mise use node@24.15.0")
    }

    /// nvm is a shell function, not an executable, so PATH cannot answer for it —
    /// `NVM_DIR` is how a host says it has nvm.
    @Test("nvm is detected by its environment, not by PATH")
    func nvmFromEnvironment() async throws {
        let command = try await VersionManagerCommand.detect(
            for: .node, version: "24.15.0", runner: onPath("fnm"),
            environment: ["NVM_DIR": "/Users/someone/.nvm"]
        )

        #expect(command == "nvm use")
    }

    @Test("the search falls through to whatever this host does have")
    func fallsThrough() async throws {
        let command = try await VersionManagerCommand.detect(
            for: .node, version: "24.15.0", runner: onPath("asdf"), environment: [:]
        )

        #expect(command == "asdf install nodejs 24.15.0")
    }

    /// Ruby has its own managers, and nvm is not one of them.
    @Test("Ruby is asked of Ruby's managers")
    func rubyManagers() async throws {
        #expect(
            try await VersionManagerCommand.detect(
                for: .ruby, version: "3.2.2", runner: onPath("rbenv"),
                environment: ["NVM_DIR": "/Users/someone/.nvm"]
            ) == "rbenv install 3.2.2"
        )
        #expect(
            try await VersionManagerCommand.detect(
                for: .ruby, version: "3.2.2", runner: onPath("mise"), environment: [:]
            ) == "mise use ruby@3.2.2"
        )
    }

    /// No command beats a command that cannot run: Remediation allows a summary on
    /// its own, and a wrong paste costs more than a missing one.
    @Test("a host with no version manager gets no command")
    func noManager() async throws {
        #expect(
            try await VersionManagerCommand.detect(
                for: .node, version: "24.15.0", runner: onPath(), environment: [:]
            ) == nil
        )
    }
}

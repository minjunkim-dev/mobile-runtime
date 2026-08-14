import Foundation
import TestSupport
import Testing

@testable import Core

private let packageJSON = #"{"dependencies": {"react-native": "0.81.0"}}"#

/// A React Native app with a yarn lockfile beside it — the single-repo shape, where
/// the workspace root and the anchor are the same directory.
private func app() throws -> FixtureRepo {
    let repo = try FixtureRepo()
    try repo.write("package.json", packageJSON)
    try repo.write("yarn.lock", "")
    return repo
}

private func anchor(_ repo: FixtureRepo, at relativePath: String? = nil) throws -> ProjectAnchor {
    let directory = relativePath.map { repo.url($0) } ?? repo.root
    return try #require(ProjectAnchor.detect(from: directory))
}

@discardableResult
private func run(
    _ anchor: ProjectAnchor,
    _ runner: FakeProcessRunner,
    context: inout UpContext
) async throws -> StageOutcome {
    try await DependenciesStage(anchor: anchor, runner: runner).run(&context)
}

@Suite("dependencies stage")
struct DependenciesStageTests {
    /// The clone-and-go case: nothing installed, so the lockfile's manager installs it.
    @Test("no node_modules is installed with the manager the lockfile named")
    func installsNode() async throws {
        let repo = try app()
        let runner = FakeProcessRunner(responses: ["yarn install": .ok("")])
        var context = UpContext()

        let outcome = try await run(try anchor(repo), runner, context: &context)

        #expect(outcome.status == .pass)
        let install = try #require(runner.log.first(matching: "yarn install"))
        #expect(install.workingDirectory?.path == repo.root.path)
        // A cold install is minutes of network, and the default 30s would kill it.
        #expect(install.timeout == nil)
    }

    /// No comparison against the lockfile: it costs tens of seconds on every run, and
    /// a mismatch is something the build says out loud anyway.
    @Test("node_modules that exists is skipped without a staleness comparison")
    func skipsNode() async throws {
        let repo = try app()
        try repo.directory("node_modules")
        let runner = FakeProcessRunner()
        var context = UpContext()

        let outcome = try await run(try anchor(repo), runner, context: &context)

        #expect(outcome.status == .skipped)
        #expect(runner.log.all.isEmpty)
    }

    /// Installing from a sub-package is how a workspace gets broken, so the lockfile's
    /// directory — not the anchor's — is where the install runs.
    @Test("in a monorepo the install runs at the workspace root")
    func monorepoRunsAtRoot() async throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"private": true}"#)
        try repo.write("pnpm-lock.yaml", "")
        try repo.write("packages/app/package.json", packageJSON)
        let runner = FakeProcessRunner(responses: ["pnpm install": .ok("")])
        var context = UpContext()

        try await run(try anchor(repo, at: "packages/app"), runner, context: &context)

        let install = try #require(runner.log.first(matching: "pnpm install"))
        #expect(install.workingDirectory?.path == repo.root.path)
    }

    /// The other half of the same rule, and the one that costs minutes when it is
    /// wrong: a hoisted workspace installs into the root and leaves the member with
    /// no `node_modules` of its own. Asking the member would reinstall the whole
    /// monorepo on every `up`.
    @Test("a monorepo whose root is installed is skipped, member directory or not")
    func monorepoSkipsOnRoot() async throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"private": true}"#)
        try repo.write("pnpm-lock.yaml", "")
        try repo.directory("node_modules")
        try repo.write("packages/app/package.json", packageJSON)
        let runner = FakeProcessRunner()
        var context = UpContext()

        let outcome = try await run(try anchor(repo, at: "packages/app"), runner, context: &context)

        #expect(outcome.status == .skipped)
        #expect(runner.log.all.isEmpty)
    }

    @Test("no Pods directory means pod install runs in ios/")
    func installsPods() async throws {
        let repo = try app()
        try repo.directory("node_modules")
        try repo.write("ios/Podfile", "platform :ios, '15.1'\n")
        try repo.write("ios/Podfile.lock", "PODS:\n")
        let runner = FakeProcessRunner(responses: ["pod install": .ok("")])
        var context = UpContext()

        let outcome = try await run(try anchor(repo), runner, context: &context)

        #expect(outcome.status == .pass)
        let install = try #require(runner.log.first(matching: "pod install"))
        #expect(install.workingDirectory?.path == repo.url("ios").path)
    }

    /// CocoaPods' own rule, byte for byte: the manifest it wrote next to `Pods/` has
    /// to be the lock it was built from.
    @Test("a manifest that matches the lock skips pod install")
    func skipsPods() async throws {
        let repo = try app()
        try repo.directory("node_modules")
        try repo.write("ios/Podfile", "platform :ios, '15.1'\n")
        try repo.write("ios/Podfile.lock", "PODS:\n  - React (0.81.0)\n")
        try repo.write("ios/Pods/Manifest.lock", "PODS:\n  - React (0.81.0)\n")
        let runner = FakeProcessRunner()
        var context = UpContext()

        let outcome = try await run(try anchor(repo), runner, context: &context)

        #expect(outcome.status == .skipped)
        #expect(runner.log.all.isEmpty)
    }

    @Test("a manifest that disagrees with the lock reinstalls the Pods")
    func staleManifest() async throws {
        let repo = try app()
        try repo.directory("node_modules")
        try repo.write("ios/Podfile", "platform :ios, '15.1'\n")
        try repo.write("ios/Podfile.lock", "PODS:\n  - React (0.81.0)\n")
        try repo.write("ios/Pods/Manifest.lock", "PODS:\n  - React (0.80.0)\n")
        let runner = FakeProcessRunner(responses: ["pod install": .ok("")])
        var context = UpContext()

        #expect(try await run(try anchor(repo), runner, context: &context).status == .pass)
        #expect(runner.log.first(matching: "pod install") != nil)
    }

    /// A project that does not use CocoaPods is not punished for it.
    @Test("no Podfile means CocoaPods is never touched")
    func noPodfile() async throws {
        let repo = try app()
        try repo.directory("node_modules")
        try repo.directory("ios")
        let runner = FakeProcessRunner()
        var context = UpContext()

        #expect(try await run(try anchor(repo), runner, context: &context).status == .skipped)
        #expect(runner.log.all.isEmpty)
    }

    /// Both halves in one run, which is exactly what a fresh clone looks like.
    @Test("a fresh clone installs node_modules and Pods in that order")
    func installsBoth() async throws {
        let repo = try app()
        try repo.write("ios/Podfile", "platform :ios, '15.1'\n")
        let runner = FakeProcessRunner(responses: [
            "yarn install": .ok(""),
            "pod install": .ok(""),
        ])
        var context = UpContext()

        #expect(try await run(try anchor(repo), runner, context: &context).status == .pass)
        #expect(runner.log.all.map(\.description) == ["yarn install", "pod install"])
    }

    /// exit 1, not exit 2: a project whose dependencies will not install is the
    /// project's problem, and it comes with the line to run by hand.
    @Test("an install that fails is a domain failure with the command to repeat")
    func installFailure() async throws {
        let repo = try app()
        let runner = FakeProcessRunner(responses: [
            "yarn install": .failed(1, "error An unexpected error occurred: ENOTFOUND registry.yarnpkg.com\n")
        ])
        var context = UpContext()

        let error = await #expect(throws: DomainError.self) {
            try await run(try anchor(repo), runner, context: &context)
        }

        #expect(error?.summary.contains("node_modules") == true)
        #expect(error?.observed?.contains("ENOTFOUND") == true)
        #expect(error?.remediation.command == "yarn install")
    }

    /// The other exit code: a runner that could not start the install at all is the
    /// machine's problem, and it must not be dressed up as the project's.
    @Test("an install that could not be started stays an infrastructure failure")
    func toolFailure() async throws {
        let repo = try app()
        let runner = FakeProcessRunner(failures: [
            "yarn install": ProcessError.timedOut(command: "yarn install", timeout: .seconds(30))
        ])
        var context = UpContext()

        await #expect(throws: ProcessError.self) {
            try await run(try anchor(repo), runner, context: &context)
        }
    }
}

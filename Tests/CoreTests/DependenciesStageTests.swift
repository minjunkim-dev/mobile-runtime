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

private func temporaryLogs() throws -> RunLogs {
    let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent("mobile-dependencies-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    return RunLogs(project: URL(fileURLWithPath: "/a/MyApp"), temporaryDirectory: temporary)
}

@discardableResult
private func run(
    _ anchor: ProjectAnchor,
    _ runner: FakeProcessRunner,
    context: inout UpContext,
    logs: RunLogs? = nil
) async throws -> StageOutcome {
    try await DependenciesStage(anchor: anchor, runner: runner, logs: logs).run(&context)
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

    /// The repo that made this a ticket: rainbow declares `bundle exec pod install`,
    /// and bundler refuses to run anything at all while a gem in the lock is missing
    /// — so on a fresh clone the pod install never starts (#59).
    @Test("gems the project declared are installed before the Pods that need them")
    func installsGemsBeforePods() async throws {
        let repo = try app()
        try repo.directory("node_modules")
        try repo.write("Gemfile", "gem 'cocoapods', '1.16.1'\n")
        try repo.write("ios/Podfile", "platform :ios, '15.1'\n")
        let runner = FakeProcessRunner(responses: [
            "bundle check": .failed(1, "The following gems are missing"),
            "bundle install": .ok(""),
            "bundle exec pod install": .ok(""),
        ])
        var context = UpContext()

        let outcome = try await run(try anchor(repo), runner, context: &context)

        #expect(outcome.status == .pass)
        #expect(outcome.detail == "installed gems and Pods")
        let sent = runner.log.all.map(\.description)
        let gems = try #require(sent.firstIndex(of: "bundle install"))
        let pods = try #require(sent.firstIndex(of: "bundle exec pod install"))
        #expect(gems < pods)
        #expect(runner.log.first(matching: "bundle install")?.workingDirectory?.path == repo.root.path)
    }

    /// `bundle check` is bundler's own question about bundler's own files. When it
    /// says the gems are there, a `bundle install` would be tens of seconds spent to
    /// be told the same thing.
    @Test("gems already installed are not reinstalled")
    func skipsInstalledGems() async throws {
        let repo = try app()
        try repo.directory("node_modules")
        try repo.write("Gemfile", "gem 'cocoapods', '1.16.1'\n")
        try repo.write("ios/Podfile", "platform :ios, '15.1'\n")
        let runner = FakeProcessRunner(responses: [
            "bundle check": .ok("The Gemfile's dependencies are satisfied"),
            "bundle exec pod install": .ok(""),
        ])
        var context = UpContext()

        let outcome = try await run(try anchor(repo), runner, context: &context)

        #expect(outcome.detail == "installed Pods")
        #expect(runner.log.all.map(\.description).contains("bundle install") == false)
    }

    /// A project that declared no gems is never asked about them.
    @Test("no Gemfile means bundler is never called")
    func noGemfile() async throws {
        let repo = try app()
        try repo.directory("node_modules")
        try repo.write("ios/Podfile", "platform :ios, '15.1'\n")
        let runner = FakeProcessRunner(responses: ["pod install": .ok("")])
        var context = UpContext()

        _ = try await run(try anchor(repo), runner, context: &context)

        #expect(runner.log.all.map(\.description).contains { $0.hasPrefix("bundle") } == false)
    }

    @Test("a Gemfile without CocoaPods keeps the valid bare pod path")
    func unconfirmedGemfileUsesBarePod() async throws {
        let repo = try app()
        try repo.directory("node_modules")
        try repo.write("Gemfile", "gem 'fastlane'\n")
        try repo.write("ios/Podfile", "platform :ios, '15.1'\n")
        let runner = FakeProcessRunner(responses: ["pod install": .ok("")])
        var context = UpContext()

        _ = try await run(try anchor(repo), runner, context: &context)

        #expect(runner.log.first(matching: "pod install") != nil)
        #expect(runner.log.all.map(\.description).contains { $0.hasPrefix("bundle") } == false)
    }

    /// The failure that started the ticket handed over a command that reproduced it.
    /// This one hands over the command that fixes it.
    @Test("a failed gem install stops the run with a line that actually installs them")
    func failedGemInstall() async throws {
        let repo = try app()
        try repo.directory("node_modules")
        try repo.write("Gemfile", "gem 'cocoapods', '1.16.1'\n")
        try repo.write("ios/Podfile", "platform :ios, '15.1'\n")
        let cause = "/bundler/definition.rb:599:in `materialize': "
            + "Could not find fastlane-2.232.1 in locally installed gems (Bundler::GemNotFound)"
        let backtrace = (1...13)
            .map { "from /bundler/setup.rb:\($0):in `setup'" }
            .joined(separator: "\n")
        let runner = FakeProcessRunner(responses: [
            "bundle check": .failed(1, "missing"),
            "bundle install": .failed(17, cause + "\n" + backtrace + "\n"),
        ])
        var context = UpContext()

        let error = await #expect(throws: DomainError.self) {
            try await run(try anchor(repo), runner, context: &context)
        }

        #expect(error?.summary == "installing gems failed")
        #expect(error?.observed == cause)
        #expect(error?.remediation.command == "cd \(repo.root.path) && bundle install")
        #expect(runner.log.all.map(\.description).contains("bundle exec pod install") == false)
    }

    /// A `bundle` that cannot run at all is not this stage's news: the pod install is
    /// about to run and says what it needs in its own words.
    @Test("a bundler that cannot be run leaves the pod install to speak")
    func bundlerMissing() async throws {
        let repo = try app()
        try repo.directory("node_modules")
        try repo.write("Gemfile", "gem 'cocoapods', '1.16.1'\n")
        try repo.write("ios/Podfile", "platform :ios, '15.1'\n")
        var runner = FakeProcessRunner(responses: ["bundle exec pod install": .ok("")])
        runner.failures["bundle check"] = ProcessError.spawnFailed(
            command: "bundle check", underlying: FixtureMiss(command: "bundle")
        )
        var context = UpContext()

        let outcome = try await run(try anchor(repo), runner, context: &context)

        #expect(outcome.detail == "installed Pods")
        #expect(runner.log.all.map(\.description).contains("bundle install") == false)
    }

    /// The repo that made this a ticket: mattermost-mobile's bare `pod install` dies
    /// on the New Architecture flag its own script sets, so a bare one here means the
    /// Pods never install at all (#48).
    @Test("a project that declares its pod install has that run instead of the bare one")
    func installsPodsWithTheDeclaredScript() async throws {
        let repo = try FixtureRepo()
        try repo.write(
            "package.json",
            #"""
            {
              "dependencies": {"react-native": "0.81.0"},
              "scripts": {"pod-install": "cd ios && RCT_NEW_ARCH_ENABLED=1 pod install"}
            }
            """#
        )
        try repo.write("yarn.lock", "")
        try repo.directory("node_modules")
        try repo.write("ios/Podfile", "platform :ios, '15.1'\n")
        let runner = FakeProcessRunner(responses: ["yarn run pod-install": .ok("")])
        var context = UpContext()

        let outcome = try await run(try anchor(repo), runner, context: &context)

        #expect(outcome.status == .pass)
        let install = try #require(runner.log.first(matching: "yarn run pod-install"))
        // The script does its own `cd ios`; the manager runs where the manifest is.
        #expect(install.workingDirectory?.path == repo.root.path)
        #expect(runner.log.first(matching: "pod install") == nil)
    }

    /// The command a failure hands a human has to be the one that works. The old line
    /// (`cd ios && pod install`) hit the same wall `up` did, so following the screen
    /// led nowhere.
    @Test("a failed declared pod install hands back the declared command")
    func declaredPodInstallFailureRepeatsTheScript() async throws {
        let repo = try FixtureRepo()
        try repo.write(
            "package.json",
            #"""
            {
              "dependencies": {"react-native": "0.81.0"},
              "scripts": {"install-pods": "bundle exec pod install --repo-update"}
            }
            """#
        )
        try repo.write("yarn.lock", "")
        try repo.directory("node_modules")
        try repo.write("ios/Podfile", "platform :ios, '15.1'\n")
        let runner = FakeProcessRunner(responses: [
            "yarn run install-pods": .failed(1, "[!] Invalid `Podfile` file\n")
        ])
        var context = UpContext()

        let error = await #expect(throws: DomainError.self) {
            try await run(try anchor(repo), runner, context: &context)
        }

        #expect(error?.remediation.command == "cd \(repo.root.path) && yarn run install-pods")
        // And what chose it: `yarn run install-pods` says less about itself than the
        // `pod install` it replaced, so the declaration comes with it (ADR-0003).
        #expect(error?.remediation.summary.contains("scripts.install-pods") == true)
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
        let cause = "➤ YN0000: Error: Couldn't find package"
        let status = (1...13).map { "➤ YN0000: Completed step \($0)" }.joined(separator: "\n")
        let runner = FakeProcessRunner(responses: [
            "yarn install": .failed(1, cause + "\n" + status + "\n")
        ])
        var context = UpContext()

        let error = await #expect(throws: DomainError.self) {
            try await run(try anchor(repo), runner, context: &context)
        }

        #expect(error?.summary.contains("node_modules") == true)
        #expect(error?.observed == cause)
        #expect(error?.remediation.command == "yarn install")
    }

    @Test("partial node_modules from a failed install is retried on the next run")
    func retriesAfterPartialNodeInstall() async throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"private": true}"#)
        try repo.write("yarn.lock", "")
        try repo.write("packages/one/package.json", packageJSON)
        try repo.write("packages/two/package.json", packageJSON)
        let first = try anchor(repo, at: "packages/one")
        let sibling = try anchor(repo, at: "packages/two")
        let failed = FakeProcessRunner(responses: [
            "yarn install": .failed(2, "preinstall failed")
        ])
        var context = UpContext()

        await #expect(throws: DomainError.self) {
            try await run(first, failed, context: &context)
        }
        try repo.directory("node_modules")

        let retry = FakeProcessRunner(responses: ["yarn install": .ok("")])
        let outcome = try await run(sibling, retry, context: &context)

        #expect(outcome.status == .pass)
        #expect(retry.log.first(matching: "yarn install") != nil)

        let settled = FakeProcessRunner()
        #expect(try await run(first, settled, context: &context).status == .skipped)
    }

    @Test("an npm failure shows its error rather than later warnings")
    func observedPrefersNPMError() async throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", packageJSON)
        try repo.write("package-lock.json", "")
        let cause = "npm error code ENOTFOUND"
        let warnings = (1...13).map { "npm warn deprecated thing@\($0)" }.joined(separator: "\n")
        let runner = FakeProcessRunner(responses: [
            "npm install": .failed(1, cause + "\n" + warnings + "\n")
        ])
        var context = UpContext()

        let error = await #expect(throws: DomainError.self) {
            try await run(try anchor(repo), runner, context: &context)
        }

        #expect(error?.observed == cause)
    }

    /// The ten lines that fit are not the fix — the file is. Both measured failures
    /// put the reason above a page of the installer's own noise: npm's `[failed]` line
    /// under twenty deprecation warnings, and pod's under mise installing a node (#49).
    @Test("a failed install names the log file its whole output was streamed to")
    func failureNamesLog() async throws {
        let repo = try app()
        let warnings = (1...20).map { "npm warn deprecated thing@\($0)" }.joined(separator: "\n")
        let runner = FakeProcessRunner(responses: [
            "yarn install": FakeProcessRunner.Response(
                status: .exited(1),
                standardOutput: "'pod' binary 1.16.1 [failed]\n" + warnings + "\n"
            )
        ])
        let logs = try temporaryLogs()
        var context = UpContext()

        let error = await #expect(throws: DomainError.self) {
            try await run(try anchor(repo), runner, context: &context, logs: logs)
        }

        let file = logs.url("node_modules-install.log")
        #expect(error?.remediation.summary.contains(file.path) == true)
        #expect(try #require(runner.log.first(matching: "yarn install")).output == .streamed(to: file))
        // Still the last ten — and they are still the warnings, which is exactly why
        // the path above them has to be there.
        let observed = try #require(error?.observed)
        #expect(observed.split(separator: "\n").count == 10)
        #expect(observed.contains("[failed]") == false)
    }

    /// The log is named after what is being installed, not after the installer, so a
    /// run that does both leaves two files rather than the second overwriting the
    /// first. A declared pod install makes that the only naming that works: both
    /// halves of this stage then run through the same `yarn`.
    @Test("a failed pod install names the Pods log, not the node one")
    func podFailureNamesItsOwnLog() async throws {
        let repo = try FixtureRepo()
        try repo.write(
            "package.json",
            #"""
            {
              "dependencies": {"react-native": "0.81.0"},
              "scripts": {"pod-install": "cd ios && pod install"}
            }
            """#
        )
        try repo.write("yarn.lock", "")
        try repo.directory("node_modules")
        try repo.write("ios/Podfile", "platform :ios, '15.1'\n")
        let runner = FakeProcessRunner(responses: [
            "yarn run pod-install": .failed(
                1, "[!] CocoaPods could not find compatible versions for pod \"React\"\n"
            )
        ])
        let logs = try temporaryLogs()
        var context = UpContext()

        let error = await #expect(throws: DomainError.self) {
            try await run(try anchor(repo), runner, context: &context, logs: logs)
        }

        #expect(error?.remediation.summary.contains(logs.url("Pods-install.log").path) == true)
        #expect(error?.remediation.summary.contains("node_modules-install.log") == false)
        #expect(error?.observed?.contains("could not find compatible versions") == true)
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

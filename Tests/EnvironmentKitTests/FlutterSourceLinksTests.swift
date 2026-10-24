import Core
import Darwin
@testable import EnvironmentKit
import Foundation
import TestSupport
import Testing

@Suite("explicit Flutter source file links")
struct FlutterSourceLinksTests {
    @Test("cancelling an in-flight post-failure Git observation starts no snapshot or receipt", arguments: [false, true])
    func cancelledFailureObservation(_ returnsCompletedResult: Bool) async throws {
        let repo = try FixtureRepo()
        try repo.write("assets/notes.md", "preserved notes\n")
        try FileManager.default.createSymbolicLink(atPath: repo.url("NOTES.md").path, withDestinationPath: "assets/notes.md")
        try await git(repo, ["init", "-q"])
        try await git(repo, ["add", "--", "NOTES.md"])
        let runner = WaitingTrackingRunner(base: system, returnsCompletedResult: returnsCompletedResult)
        let snapshot = try await FlutterSourceLinks.capture(root: repo.root,
            sources: [repo.url("NOTES.md").path, repo.url("assets/notes.md").path], links: [repo.url("NOTES.md").path],
            forbidden: [], runner: runner)
        let trace = FailureObservationTrace()
        let task = Task {
            await FlutterSourceLinks.observeFailure(ProcessError.timedOut(command: "fixture", timeout: .seconds(1)), links: snapshot,
                check: { trace.checked() }, record: { _, _ in trace.recorded() })
        }
        let deadline = ContinuousClock.now + .seconds(5)
        while !runner.waiting && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        task.cancel()
        await task.value
        #expect(runner.waiting)
        #expect(!trace.didCheck)
        #expect(!trace.didRecord)
    }

    @Test("dependency lock and workspace config aliases remain outside source exceptions",
          arguments: ["package-lock.json", "npm-shrinkwrap.json", "pnpm-lock.yaml", "pnpm-workspace.yaml", "bun.lockb"], [false, true])
    func dependencyMetadata(_ name: String, _ pointsToMetadata: Bool) async throws {
        let repo = try FixtureRepo()
        let link = repo.url(pointsToMetadata ? "NOTES.md" : name)
        let target = repo.url(pointsToMetadata ? name : "notes.md")
        try repo.write(target.lastPathComponent, "preserved input\n")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: target.lastPathComponent)
        try await git(repo, ["init", "-q"])
        try await git(repo, ["add", "--", link.lastPathComponent])
        await #expect(throws: DomainError.self) {
            try await FlutterSourceLinks.capture(root: repo.root, sources: [link.path, target.path], links: [link.path],
                forbidden: [], runner: system)
        }
        #expect(try String(contentsOf: target, encoding: .utf8) == "preserved input\n")
    }

    @Test("Git tracking stays bound to the workspace despite inherited index or repository redirects",
          arguments: ["index", "repository"])
    func redirectedGitTracking(_ mode: String) async throws {
        let repo = try FixtureRepo(), other = try FixtureRepo()
        for fixture in [repo, other] {
            try fixture.write("assets/notes.md", "preserved notes\n")
            try FileManager.default.createSymbolicLink(atPath: fixture.url("NOTES.md").path, withDestinationPath: "assets/notes.md")
            try await git(fixture, ["init", "-q"])
        }
        try await git(other, ["add", "--", "NOTES.md"])
        var environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        if mode == "index" { environment["GIT_INDEX_FILE"] = other.url(".git/index").path }
        else {
            environment["GIT_DIR"] = other.url(".git").path
            environment["GIT_WORK_TREE"] = repo.root.path
        }
        let redirected = SystemProcessRunner(environment: environment)
        let capture = {
            try await FlutterSourceLinks.capture(root: repo.root,
                sources: [repo.url("NOTES.md").path, repo.url("assets/notes.md").path], links: [repo.url("NOTES.md").path],
                forbidden: [], runner: redirected)
        }
        await #expect(throws: DomainError.self) { try await capture() }
        try await git(repo, ["add", "--", "NOTES.md"])
        let snapshot = try await capture()
        try await snapshot.checkTracking()
        try await git(repo, ["update-index", "--force-remove", "--", "NOTES.md"])
        await #expect(throws: DomainError.self) { try await snapshot.checkTracking() }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: repo.url("NOTES.md").path) == "assets/notes.md")
        #expect(try String(contentsOf: repo.url("assets/notes.md"), encoding: .utf8) == "preserved notes\n")
    }

    @Test("Git tracking ignores inherited configuration and never runs the repository fsmonitor hook",
          arguments: ["system", "global", "environment", "fsmonitor"])
    func isolatedGitConfiguration(_ mode: String) async throws {
        let repo = try FixtureRepo()
        try repo.write("assets/notes.md", "preserved notes\n")
        try FileManager.default.createSymbolicLink(atPath: repo.url("NOTES.md").path, withDestinationPath: "assets/notes.md")
        try await git(repo, ["init", "-q"])
        try await git(repo, ["add", "--", "NOTES.md"])
        let hook = try repo.write("fsmonitor", "#!/bin/sh\nprintf invoked > \"$0.called\"\nexit 1\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: hook.path)
        try await git(repo, ["config", "core.fsmonitor", hook.path])
        let malformed = try repo.write("invalid.config", "[broken\n")
        var environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        if mode == "system" { environment["GIT_CONFIG_SYSTEM"] = malformed.path }
        if mode == "global" { environment["GIT_CONFIG_GLOBAL"] = malformed.path }
        if mode == "environment" {
            environment["GIT_CONFIG_COUNT"] = "1"
            environment["GIT_CONFIG_KEY_0"] = "core.bare"
            environment["GIT_CONFIG_VALUE_0"] = "invalid"
        }
        let snapshot = try await FlutterSourceLinks.capture(root: repo.root,
            sources: [repo.url("NOTES.md").path, repo.url("assets/notes.md").path], links: [repo.url("NOTES.md").path],
            forbidden: [], runner: SystemProcessRunner(environment: environment))
        try await snapshot.checkTracking()
        #expect(!FileManager.default.fileExists(atPath: hook.path + ".called"))
    }

    @Test("raw target components must resolve through ordinary source directories", arguments: [
        "missing/../assets/notes.md", "assets/notes.md/../notes.md", "assets/notes.md/",
        "build/jump/../../assets/notes.md", ".git/jump/../../assets/notes.md"
    ])
    func rawTargetComponents(_ target: String) async throws {
        let repo = try FixtureRepo(), outside = try FixtureRepo()
        try repo.write("assets/notes.md", "preserved notes\n")
        try await git(repo, ["init", "-q"])
        try FileManager.default.createDirectory(at: repo.url("build"), withIntermediateDirectories: true)
        for directory in ["build", ".git"] {
            try FileManager.default.createSymbolicLink(at: repo.url(directory + "/jump"), withDestinationURL: outside.root)
        }
        try FileManager.default.createSymbolicLink(atPath: repo.url("NOTES.md").path, withDestinationPath: target)
        try await git(repo, ["add", "--", "NOTES.md"])
        await #expect(throws: DomainError.self) {
            try await FlutterSourceLinks.capture(root: repo.root,
                sources: [repo.url("NOTES.md").path, repo.url("assets/notes.md").path], links: [repo.url("NOTES.md").path],
                forbidden: [], runner: system)
        }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: repo.url("NOTES.md").path) == target)
    }

    @Test("leading parent traversal works and cancelled intermediate directories remain protected")
    func traversedParent() async throws {
        let repo = try FixtureRepo()
        try repo.write("assets/notes.md", "preserved notes\n")
        try FileManager.default.createDirectory(at: repo.url("docs"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repo.url("transit"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: repo.url("docs/NOTES.md").path,
            withDestinationPath: "../transit/../assets/notes.md")
        try await git(repo, ["init", "-q"])
        try await git(repo, ["add", "--", "docs/NOTES.md"])
        let snapshot = try await FlutterSourceLinks.capture(root: repo.root,
            sources: [repo.url("docs/NOTES.md").path, repo.url("assets/notes.md").path], links: [repo.url("docs/NOTES.md").path],
            forbidden: [], runner: system)
        try snapshot.check()
        #expect(try String(contentsOf: repo.url("docs/NOTES.md"), encoding: .utf8) == "preserved notes\n")
        let moved = try await system.run(ProcessCommand("/usr/bin/sandbox-exec",
            ["-p", "(version 1)(allow default)" + snapshot.protection(), "/bin/mv", repo.url("transit").path, repo.url("moved").path]))
        #expect(!moved.terminationStatus.isSuccess)
        // Preserve the external mutation, including the RED case where the child already moved it.
        if FileManager.default.fileExists(atPath: repo.url("transit").path) {
            try FileManager.default.moveItem(at: repo.url("transit"), to: repo.url("moved"))
        }
        try FileManager.default.createDirectory(at: repo.url("transit"), withIntermediateDirectories: true)
        #expect(throws: DomainError.self) { try snapshot.check() }
        #expect(FileManager.default.fileExists(atPath: repo.url("moved").path))
    }

    @Test("only tracked internal ordinary source file leaves are eligible", arguments: [
        "valid", "source-build-name", "untracked", "regular-index", "absolute", "outside", "dangling", "directory", "chain", "cycle",
        "parent-alias", "lock-link", "lock-target", "metadata-link", "metadata-target", "native-metadata", "tool-metadata", "project-metadata", "entrypoint", "cache", "sdk", "executable", "hardlink"
    ])
    func eligibility(_ mode: String) async throws {
        let repo = try FixtureRepo(), outside = try FixtureRepo()
        var relative = "NOTES.md", target = "assets/notes.md"
        if mode == "source-build-name" { target = "lib/build/notes.md" }
        if mode == "lock-link" { relative = "pubspec.lock" }
        if mode == "metadata-link" { relative = ".flutter-plugins-dependencies" }
        if mode == "lock-target" { target = "pubspec.lock" }
        if mode == "metadata-target" { target = "pubspec.yaml" }
        if mode == "native-metadata" { target = "android/build.gradle" }
        if mode == "tool-metadata" { target = "mise.toml" }
        if mode == "project-metadata" { target = "mobile.yml" }
        if mode == "entrypoint" { target = "lib/main.dart" }
        if mode == "cache" { target = ".dart_tool/notes.md" }
        if mode == "sdk" { target = "sdk/notes.md" }
        try repo.write(target, "preserved notes\n")
        var link = target
        if mode == "absolute" { link = repo.url(target).path }
        if mode == "outside" { link = try outside.write("private-notes.md", "outside bytes").path }
        if mode == "dangling" { link = "missing.md" }
        if mode == "cycle" { link = relative }
        if mode == "directory" { link = "assets" }
        if mode == "chain" {
            link = "assets/alias.md"
            try FileManager.default.createSymbolicLink(atPath: repo.url(link).path, withDestinationPath: "notes.md")
        }
        let path = repo.url(relative)
        if mode == "regular-index" {
            try repo.write(relative, "regular Git entry")
            try await git(repo, ["init", "-q"])
            try await git(repo, ["add", "--", relative])
            try FileManager.default.removeItem(at: path)
        }
        try FileManager.default.createSymbolicLink(atPath: path.path, withDestinationPath: link)
        if mode != "regular-index" {
            try await git(repo, ["init", "-q"])
            if mode != "untracked" { try await git(repo, ["add", "--", relative]) }
        }
        if mode == "parent-alias" {
            try outside.write("notes.md", "outside bytes")
            try FileManager.default.moveItem(at: repo.url("assets"), to: repo.url("saved-assets"))
            try FileManager.default.createSymbolicLink(at: repo.url("assets"), withDestinationURL: outside.root)
        }
        if mode == "executable" { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: repo.url(target).path) }
        if mode == "hardlink" { #expect(linkat(AT_FDCWD, repo.url(target).path, AT_FDCWD, repo.url("other.md").path, 0) == 0) }
        let sources: Set<String> = [path.path, repo.url(target).path, repo.url(link).path]
        let capture = {
            try await FlutterSourceLinks.capture(root: repo.root, sources: sources, links: [path.path],
                forbidden: [repo.url("sdk"), repo.url("lib/main.dart")], runner: system)
        }
        if mode == "valid" || mode == "source-build-name" {
            let snapshot = try await capture()
            try snapshot.check()
            try await snapshot.checkTracking()
        } else {
            await #expect(throws: DomainError.self) { try await capture() }
        }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: path.path) == link)
    }

    @Test("link, target, parent and index changes fail without restoration", arguments: [
        "link", "link-identity", "target", "target-identity", "parent", "mode", "hardlink", "index"
    ])
    func changedInputs(_ mode: String) async throws {
        let repo = try FixtureRepo()
        try repo.write("assets/notes.md", "preserved notes\n")
        try FileManager.default.createSymbolicLink(atPath: repo.url("NOTES.md").path, withDestinationPath: "assets/notes.md")
        try await git(repo, ["init", "-q"])
        try await git(repo, ["add", "--", "NOTES.md"])
        let snapshot = try await FlutterSourceLinks.capture(root: repo.root,
            sources: [repo.url("NOTES.md").path, repo.url("assets/notes.md").path], links: [repo.url("NOTES.md").path],
            forbidden: [], runner: system)
        switch mode {
        case "link", "link-identity":
            try FileManager.default.removeItem(at: repo.url("NOTES.md"))
            try FileManager.default.createSymbolicLink(atPath: repo.url("NOTES.md").path,
                withDestinationPath: mode == "link" ? "missing" : "assets/notes.md")
        case "target": try repo.write("assets/notes.md", "external change")
        case "target-identity":
            try FileManager.default.removeItem(at: repo.url("assets/notes.md"))
            try repo.write("assets/notes.md", "preserved notes\n")
        case "parent":
            try FileManager.default.moveItem(at: repo.url("assets"), to: repo.url("old-assets"))
            try repo.write("assets/notes.md", "preserved notes\n")
        case "mode": try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: repo.url("assets/notes.md").path)
        case "hardlink": #expect(linkat(AT_FDCWD, repo.url("assets/notes.md").path, AT_FDCWD, repo.url("other.md").path, 0) == 0)
        default: try await git(repo, ["update-index", "--force-remove", "--", "NOTES.md"])
        }
        if mode == "index" {
            try snapshot.check()
            await #expect(throws: DomainError.self) { try await snapshot.checkTracking() }
        } else { #expect(throws: DomainError.self) { try snapshot.check() } }
        if mode == "target" { #expect(try String(contentsOf: repo.url("assets/notes.md"), encoding: .utf8) == "external change") }
    }

    @Test("the real native child policy permits reads and output but refuses alias, target and parent mutation")
    func sandbox() async throws {
        let repo = try FixtureRepo()
        try repo.write("assets/notes.md", "preserved notes\n")
        try FileManager.default.createSymbolicLink(atPath: repo.url("NOTES.md").path, withDestinationPath: "assets/notes.md")
        try await git(repo, ["init", "-q"])
        try await git(repo, ["add", "--", "NOTES.md"])
        let snapshot = try await FlutterSourceLinks.capture(root: repo.root,
            sources: [repo.url("NOTES.md").path, repo.url("assets/notes.md").path], links: [repo.url("NOTES.md").path],
            forbidden: [], runner: system)
        let policy = "(version 1)(allow default)" + snapshot.protection()
        for script in ["printf changed > \"$1/NOTES.md\"", "printf changed > \"$1/assets/notes.md\"",
                       "/bin/rm \"$1/NOTES.md\"", "/bin/mv \"$1/assets\" \"$1/moved\"",
                       "/bin/ln \"$1/assets/notes.md\" \"$1/hardlink.md\""] {
            let result = try await system.run(ProcessCommand("/usr/bin/sandbox-exec",
                ["-p", policy, "/bin/sh", "-c", script, "fixture", repo.root.path]))
            #expect(!result.terminationStatus.isSuccess, Comment(rawValue: result.combinedOutput))
            try snapshot.check()
        }
        let allowed = try await system.run(ProcessCommand("/usr/bin/sandbox-exec", ["-p", policy, "/bin/sh", "-c",
            "/bin/cat \"$1/NOTES.md\" > \"$1/generated.txt\"", "fixture", repo.root.path]))
        #expect(allowed.terminationStatus.isSuccess)
        #expect(try String(contentsOf: repo.url("generated.txt"), encoding: .utf8) == "preserved notes\n")
    }

    private var system: SystemProcessRunner { SystemProcessRunner(environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]) }
    private func git(_ repo: FixtureRepo, _ arguments: [String]) async throws {
        let result = try await system.run(ProcessCommand("/usr/bin/git", ["-C", repo.root.path] + arguments))
        try #require(result.terminationStatus.isSuccess, Comment(rawValue: result.combinedOutput))
    }
}

private final class FailureObservationTrace: @unchecked Sendable {
    private let lock = NSLock()
    private var check = false
    private var record = false
    var didCheck: Bool { lock.withLock { check } }
    var didRecord: Bool { lock.withLock { record } }
    func checked() { lock.withLock { check = true } }
    func recorded() { lock.withLock { record = true } }
}

private final class WaitingTrackingRunner: ProcessRunner, @unchecked Sendable {
    let base: any ProcessRunner
    let returnsCompletedResult: Bool
    private let lock = NSLock()
    private var count = 0
    private var initial: ProcessResult?
    var waiting: Bool { lock.withLock { count > 1 } }
    init(base: any ProcessRunner, returnsCompletedResult: Bool) { self.base = base; self.returnsCompletedResult = returnsCompletedResult }
    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        let current = lock.withLock { count += 1; return count }
        if current > 1 {
            do { try await Task.sleep(for: .seconds(30)) }
            catch {
                if returnsCompletedResult, let result = lock.withLock({ initial }) { return result }
                throw error
            }
        }
        let result = try await base.run(command, onLine: onLine)
        lock.withLock { initial = result }
        return result
    }
    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
        throw CancellationError()
    }
}

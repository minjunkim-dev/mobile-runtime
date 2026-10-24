import Core
import Darwin
@testable import EnvironmentKit
import Foundation
import TestSupport
import Testing

@Suite("explicit Flutter source file links")
struct FlutterSourceLinksTests {
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

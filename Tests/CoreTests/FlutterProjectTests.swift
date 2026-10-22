import Core
import Foundation
import TestSupport
import Testing

@Suite("Flutter declarations and dependency workspace")
struct FlutterProjectTests {
    @Test("SDK constraints and an exact FVM pin constrain the same existing SDK")
    func sdkConstraints() throws {
        let repo = try project()
        try repo.write(".fvmrc", #"{"flutter":"3.41.9"}"#)
        let value = try FlutterProject(directory: repo.root)
        #expect(value.accepts(flutter: "3.41.9", dart: "3.11.5"))
        #expect(!value.accepts(flutter: "3.47.2", dart: "3.13.3"))
        #expect(!value.accepts(flutter: "3.41.9", dart: "3.2.0"))
        #expect(value.entrypoint?.lastPathComponent == "main.dart")
    }

    @Test("conflicting exact declarations and mutable aliases stop preparation")
    func conflictingPins() throws {
        let repo = try project()
        try repo.write(".fvmrc", #"{"flutter":"3.41.9"}"#)
        try repo.write(".tool-versions", "flutter 3.47.2\n")
        #expect(throws: (any Error).self) { try FlutterProject(directory: repo.root) }
        try repo.write(".tool-versions", "flutter stable\n")
        #expect(throws: (any Error).self) { try FlutterProject(directory: repo.root) }
    }

    @Test("a dangling declaration link cannot become an absent Flutter declaration", arguments: [
        ".fvmrc", ".flutter-version", ".tool-versions", "mise.toml", ".mise.toml", "pubspec_overrides.yaml",
    ])
    func danglingDeclaration(_ filename: String) throws {
        let repo = try project()
        let file = repo.url(filename)
        let target = repo.url("missing-flutter-declaration")
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(throws: (any Error).self) { try FlutterProject(directory: repo.root) }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: file.path) == target.path)
    }

    @Test("a Dart resolver preserves app and workspace roots and reports files Pub would delete")
    func workspaceIdentity() throws {
        let repo = try project("apps/client", workspace: true)
        try repo.write("pubspec.yaml", "name: root\nenvironment:\n  sdk: ^3.11.0\nworkspace:\n  - apps/*\n")
        try repo.write("apps/client/pubspec.lock", "must not be deleted")
        let value = try FlutterProject(directory: repo.url("apps/client"))
        let json = try JSONSerialization.data(withJSONObject: ["packages": [
            ["name": "root", "path": repo.root.path], ["name": "example", "path": repo.url("apps/client").path]
        ]])
        let workspace = try value.workspace(from: json)
        #expect(workspace.directory.path == repo.root.resolvingSymlinksInPath().path)
        #expect(workspace.packages.count == 2)
        #expect(workspace.migrationFiles == [repo.url("apps/client/pubspec.lock").resolvingSymlinksInPath().path])
        #expect(try String(contentsOf: repo.url("apps/client/pubspec.lock"), encoding: .utf8) == "must not be deleted")
    }

    @Test("a resolver cannot include unrelated packages outside the approved workspace")
    func outsideWorkspace() throws {
        let repo = try project("apps/client", workspace: true)
        let other = try project()
        let value = try FlutterProject(directory: repo.url("apps/client"))
        let json = try JSONSerialization.data(withJSONObject: ["packages": [
            ["path": repo.root.path], ["path": repo.url("apps/client").path], ["path": other.root.path]
        ]])
        #expect(throws: (any Error).self) { try value.workspace(from: json) }
    }

    @Test("SDK-free teardown confirms the same source workspace boundary and nested membership")
    func teardownWorkspace() throws {
        let repo = try project("apps/group/client", workspace: true)
        try repo.write("pubspec.yaml", "name: root\nworkspace:\n  - apps/*\n")
        try repo.write("apps/group/pubspec.yaml", "name: group\nresolution: workspace\nworkspace:\n  - client\n")
        let value = try FlutterProject(directory: repo.url("apps/group/client"))
        #expect(try FolderIdentity(directory: value.workspaceDirectoryForTeardown()) == FolderIdentity(directory: repo.root))
        try repo.write("pubspec_overrides.yaml", "workspace:\n  - other\n")
        #expect(throws: DomainError.self) { try value.workspaceDirectoryForTeardown() }
        try repo.write("pubspec_overrides.yaml", "workspace:\n  - apps/group\n")
        #expect(try FolderIdentity(directory: value.workspaceDirectoryForTeardown()) == FolderIdentity(directory: repo.root))
    }

    @Test("teardown refuses unconfirmed workspace roots and unsupported or escaped membership", arguments: [
        "missing", "unlisted", "parent", "absolute", "complex", "nested-git", "malformed",
    ])
    func teardownUnknownWorkspace(_ kind: String) throws {
        let repo = try project("apps/client", workspace: true)
        let pattern: String
        switch kind {
        case "parent": pattern = "../apps/client"
        case "absolute": pattern = repo.url("apps/client").path
        case "complex": pattern = "apps/{client,other}"
        case "unlisted": pattern = "apps/other"
        default: pattern = "apps/*"
        }
        if kind != "missing" { try repo.write("pubspec.yaml", "name: root\nworkspace:\n  - '\(pattern)'\n") }
        if kind == "malformed" { try repo.write("pubspec.yaml", "workspace: [\n") }
        if kind == "nested-git" { try repo.directory("apps/.git") }
        let value = try FlutterProject(directory: repo.url("apps/client"))
        #expect(throws: DomainError.self) { try value.workspaceDirectoryForTeardown() }
    }

    @Test("teardown honors a standalone effective resolution without requiring SDK inputs")
    func teardownStandaloneOverride() throws {
        let repo = try project(workspace: true)
        try repo.write("pubspec_overrides.yaml", "resolution:\n")
        let value = try FlutterProject(directory: repo.root)
        #expect(try FolderIdentity(directory: value.workspaceDirectoryForTeardown()) == FolderIdentity(directory: repo.root))
    }

    @Test("an entrypoint cannot escape the selected app through a path or symlink")
    func entrypointScope() throws {
        let repo = try project()
        let other = try project()
        #expect(throws: (any Error).self) { try FlutterProject(directory: repo.root, entrypoint: "../main.dart") }
        try FileManager.default.createSymbolicLink(at: repo.url("lib/external.dart"), withDestinationURL: other.url("lib/main.dart"))
        #expect(throws: (any Error).self) { try FlutterProject(directory: repo.root, entrypoint: "lib/external.dart") }
    }

    @Test("an explicit pubspec resolution override is honored without modifying declarations")
    func resolutionOverride() throws {
        let repo = try project(workspace: true)
        try repo.write("pubspec_overrides.yaml", "resolution:\n")
        #expect(try FlutterProject(directory: repo.root).usesWorkspace == false)
    }

    @Test("a quoted mise Flutter key remains an exact project declaration")
    func quotedMisePin() throws {
        let repo = try project()
        try repo.write("mise.toml", "[tools] # project tools\n\"flutter\" = \"3.47.2\"\n")
        #expect(try FlutterProject(directory: repo.root).pinnedVersion == "3.47.2")
    }

    @Test("a member inherits an ancestor manager pin and its nearer declaration takes precedence")
    func inheritedManagerPin() throws {
        let repo = try project("apps/client", workspace: true)
        try repo.write("mise.toml", "[tools]\nflutter = '3.41.9'\n")
        let app = repo.url("apps/client")
        #expect(try FlutterProject(directory: app).pinnedVersion == "3.41.9")
        #expect(try FlutterProject(directory: app).accepts(flutter: "3.47.2", dart: "3.11.5") == false)
        try repo.write("apps/client/.mise.toml", "[tools]\nflutter = '3.47.2'\n")
        #expect(try FlutterProject(directory: app).pinnedVersion == "3.47.2")
    }

    @Test("an unsupported quoted ancestor tools table requires manual resolution")
    func unsupportedAncestorTOML() throws {
        let repo = try project("apps/client")
        try repo.write("mise.toml", "['tools']\nflutter = ['3.41.9', '3.47.2']\n")
        #expect(throws: (any Error).self) { try FlutterProject(directory: repo.url("apps/client")) }
    }

    @Test("an entrypoint directory and npm-only SDK ranges are not Dart inputs")
    func invalidDartInputs() throws {
        let repo = try project()
        try FileManager.default.removeItem(at: repo.url("lib/main.dart"))
        try repo.directory("lib/main.dart")
        #expect(try FlutterProject(directory: repo.root).entrypoint == nil)
        try repo.write("pubspec.yaml", "name: example\nenvironment:\n  sdk: '3.x'\ndependencies:\n  flutter:\n    sdk: flutter\n")
        #expect(throws: (any Error).self) { try FlutterProject(directory: repo.root) }
    }

    private func project(_ path: String = "", workspace: Bool = false) throws -> FixtureRepo {
        let repo = try FixtureRepo()
        let prefix = path.isEmpty ? "" : path + "/"
        try repo.write(prefix + "pubspec.yaml", """
        name: example
        environment:
          sdk: '>=3.6.0 <4.0.0'
          flutter: '>=3.24.0'
        dependencies:
          flutter:
            sdk: flutter
        \(workspace ? "resolution: workspace" : "")
        """)
        try repo.write(prefix + "lib/main.dart", "void main() {}\n")
        return repo
    }
}

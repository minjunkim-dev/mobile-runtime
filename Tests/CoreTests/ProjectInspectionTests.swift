import Core
import Foundation
import TestSupport
import Testing

@Suite("project inspection selection")
struct ProjectInspectionTests {
    @Test("symlink aliases share identity while separate worktrees remain distinct")
    func realFolderIdentity() throws {
        let repo = try FixtureRepo()
        let one = try repo.directory("one")
        let two = try repo.directory("two")
        try FileManager.default.createSymbolicLink(at: repo.url("alias"), withDestinationURL: one)
        #expect(try FolderIdentity(directory: one) == FolderIdentity(directory: repo.url("alias")))
        #expect(try FolderIdentity(directory: one) != FolderIdentity(directory: two))
    }

    @Test("invalid app and unavailable platform block selection; a single host selects itself")
    func invalidSelection() throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies":{"react-native":"0.76.5"}}"#)
        try repo.directory("ios")
        let selected = try ProjectInspectionInput(directory: repo.root, environment: [:]).selection()
        #expect(selected.selected?.id == ".")
        #expect(selected.platform == .ios)
        let badApp = try ProjectInspectionInput(directory: repo.root, environment: [:], app: "missing").selection()
        #expect(badApp.error != nil)
        #expect(badApp.selected == nil)
        let badPlatform = try ProjectInspectionInput(directory: repo.root, environment: [:], platform: .android).selection()
        #expect(badPlatform.error != nil)
    }

    @Test("workspace candidates require an app and platform without changing files")
    func workspaceSelection() throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"workspaces":["packages/*"]}"#)
        for app in ["one", "two"] {
            try repo.write("packages/\(app)/package.json", #"{"dependencies":{"react-native":"0.76.5"}}"#)
            try repo.directory("packages/\(app)/ios")
            try repo.directory("packages/\(app)/android")
        }
        let selection = try ProjectInspectionInput(directory: repo.root, environment: [:]).selection()
        #expect(selection.candidates.map(\.id) == ["packages/one", "packages/two"])
        #expect(selection.requiredInput == ["--app"])
        let chosen = try ProjectInspectionInput(directory: repo.root, environment: [:], app: "packages/two").selection()
        #expect(chosen.requiredInput == ["--platform"])
        let ready = try ProjectInspectionInput(directory: repo.root, environment: [:], app: "packages/two", platform: .android).selection()
        #expect(ready.selected?.id == "packages/two")
        #expect(ready.requiredInput.isEmpty)
        #expect(ready.platform == .android)
        #expect(!FileManager.default.fileExists(atPath: repo.url("mobile.yml").path))
    }
}

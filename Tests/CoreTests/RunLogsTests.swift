import Foundation
import TestSupport
import Testing

@testable import Core

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("mobile-runlogs-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func realLogs(_ temporary: URL) throws -> RunLogs {
    let project = temporary.appendingPathComponent("source/MyApp")
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    return RunLogs(project: project, temporaryDirectory: temporary)
}

private func collidingProjects(_ temporary: URL) throws -> (URL, URL) {
    try RunLogs.collidingProjects(temporary: temporary)
}

@Suite("run logs")
struct RunLogsTests {
    @Test("distinct real inputs with a colliding legacy log namespace get separate DerivedData without writes")
    func derivedDataLegacyCollision() throws {
        let temporary = try temporaryDirectory()
        let (first, second) = try collidingProjects(temporary)
        let one = RunLogs(project: first, temporaryDirectory: temporary)
        let two = RunLogs(project: second, temporaryDirectory: temporary)
        try #require(one.directory == two.directory)
        #expect(try FolderIdentity(directory: first) != FolderIdentity(directory: second))

        #expect(try one.derivedDataDirectory != two.derivedDataDirectory)

        #expect(!FileManager.default.fileExists(atPath: one.directory.path))
    }

    @Test("DerivedData needs a current real input directory while legacy paths remain available", arguments: ["missing", "file", "removed"])
    func derivedDataRequiresInput(_ mode: String) throws {
        let temporary = try temporaryDirectory()
        let project = temporary.appendingPathComponent("source/MyApp")
        if mode == "file" {
            try FileManager.default.createDirectory(at: project.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("preserve".utf8).write(to: project)
        } else if mode == "removed" {
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        }
        let logs = RunLogs(project: project, temporaryDirectory: temporary)
        if mode == "removed" { try FileManager.default.removeItem(at: project) }

        #expect(throws: (any Error).self) { try logs.derivedDataDirectory }

        #expect(logs.write("legacy log", to: "build.log") == nil)
        if mode == "file" { #expect(try String(contentsOf: project, encoding: .utf8) == "preserve") }
    }

    @Test("DerivedData stays outside inputs, separates checkouts, and merges a project alias without writes")
    func derivedDataIdentity() throws {
        let temporary = try temporaryDirectory()
        let first = temporary.appendingPathComponent("sources/a/MyApp")
        let second = temporary.appendingPathComponent("sources/b/MyApp")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        let alias = temporary.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: first)
        let one = RunLogs(project: first, temporaryDirectory: temporary)
        let two = RunLogs(project: second, temporaryDirectory: temporary)

        let output = try one.derivedDataDirectory

        #expect(output != (try two.derivedDataDirectory))
        #expect(output == (try RunLogs(project: alias, temporaryDirectory: temporary).derivedDataDirectory))
        #expect(output.path.hasPrefix(temporary.resolvingSymlinksInPath().path + "/mobile/"))
        #expect(!output.path.hasPrefix(first.path + "/"))
        #expect(!FileManager.default.fileExists(atPath: one.directory.path))
    }

    @Test("a DerivedData parent or output link cannot redirect Xcode, including dangling links",
        arguments: ["mobile", "input", "folder", "output"], [false, true])
    func derivedDataSymlink(component: String, dangling: Bool) throws {
        let temporary = try temporaryDirectory()
        let project = temporary.appendingPathComponent("source/MyApp")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let logs = RunLogs(project: project, temporaryDirectory: temporary)
        let output = try logs.derivedDataDirectory
        let target = temporary.appendingPathComponent("preserved")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let marker = target.appendingPathComponent("keep")
        try Data("untouched".utf8).write(to: marker)
        let link = component == "mobile" ? logs.directory.deletingLastPathComponent()
            : component == "input" ? logs.directory : component == "folder" ? output.deletingLastPathComponent() : output
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        let destination = dangling ? target.appendingPathComponent("missing") : target
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: destination)

        #expect(throws: (any Error).self) { try logs.derivedDataDirectory }

        #expect(try String(contentsOf: marker, encoding: .utf8) == "untouched")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == destination.path)
    }

    @Test("a regular file in the Xcode output path is preserved", arguments: ["mobile", "input", "folder", "output"])
    func derivedDataFile(component: String) throws {
        let temporary = try temporaryDirectory()
        let project = temporary.appendingPathComponent("source/MyApp")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let logs = RunLogs(project: project, temporaryDirectory: temporary)
        let output = try logs.derivedDataDirectory
        let file = component == "mobile" ? logs.directory.deletingLastPathComponent()
            : component == "input" ? logs.directory : component == "folder" ? output.deletingLastPathComponent() : output
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("preserve".utf8).write(to: file)

        #expect(throws: (any Error).self) { try logs.derivedDataDirectory }

        #expect(try String(contentsOf: file, encoding: .utf8) == "preserve")
    }

    @Test("an alias shares the selected port and an unreadable record is preserved")
    func portAliasAndPermissions() throws {
        let temporary = try temporaryDirectory()
        let logs = try realLogs(temporary)
        let project = temporary.appendingPathComponent("source/MyApp")
        let alias = temporary.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: project)
        let other = RunLogs(project: alias, temporaryDirectory: temporary)
        try logs.recordMetroPort(8097)
        #expect(try other.metroPort() == 8097)
        let file = try logs.url("metro-port-ios")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }
        #expect(throws: (any Error).self) { try other.metroPort() }
        #expect(throws: (any Error).self) { try other.recordMetroPort(8098) }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        #expect(try String(contentsOf: file, encoding: .utf8) == "8097\n")
    }

    @Test("colliding legacy roots keep distinct installed app records")
    func installRecordCollision() throws {
        let temporary = try temporaryDirectory()
        let (first, second) = try collidingProjects(temporary)
        let one = RunLogs(project: first, temporaryDirectory: temporary)
        let two = RunLogs(project: second, temporaryDirectory: temporary)
        let firstRecord = InstallRecord(udid: "A", bundleId: "first.app")
        let secondRecord = InstallRecord(udid: "B", bundleId: "second.app")
        #expect(firstRecord.write(to: one) != nil)
        #expect(secondRecord.write(to: two) != nil)
        #expect(try InstallRecord.read(from: one) == firstRecord)
        #expect(try InstallRecord.read(from: two) == secondRecord)
    }

    @Test("new logs and state writes remain separate when legacy paths collide",
        arguments: ["build.log", "metro.log", "install.json", "android-active-run.json", "android-lifecycle.lock"])
    func logIdentityCollision(_ name: String) throws {
        let temporary = try temporaryDirectory()
        let (first, second) = try collidingProjects(temporary)
        let one = RunLogs(project: first, temporaryDirectory: temporary)
        let two = RunLogs(project: second, temporaryDirectory: temporary)
        try #require(one.directory == two.directory)

        let firstFile = try #require(one.write("first-owned", to: name))
        let secondFile = try #require(two.write("second-owned", to: name))

        #expect(firstFile != secondFile)
        #expect(try String(contentsOf: firstFile, encoding: .utf8) == "first-owned")
        #expect(try String(contentsOf: secondFile, encoding: .utf8) == "second-owned")
        #expect(!FileManager.default.fileExists(atPath: one.directory.appendingPathComponent(name).path))
    }

    @Test("colliding legacy log paths do not share a new selected-port record", arguments: [ProjectPlatform.ios, .android])
    func metroPortLegacyCollision(_ platform: ProjectPlatform) throws {
        let temporary = try temporaryDirectory()
        let (first, second) = try collidingProjects(temporary)
        let one = RunLogs(project: first, temporaryDirectory: temporary)
        let two = RunLogs(project: second, temporaryDirectory: temporary)
        try #require(one.directory == two.directory)

        try one.recordMetroPort(8097, platform: platform)
        try two.recordMetroPort(8098, platform: platform)

        #expect(try one.metroPort(platform: platform) == 8097)
        #expect(try two.metroPort(platform: platform) == 8098)
    }

    @Test("an earlier development port record has no confirmed owner and cannot become a new endpoint",
        arguments: ["8081\n", "8097\n", "unreadable", ""])
    func legacyPortUnknownOwner(_ bytes: String) throws {
        let temporary = try temporaryDirectory()
        let project = temporary.appendingPathComponent("source/MyApp")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let logs = RunLogs(project: project, temporaryDirectory: temporary)
        let legacy = logs.directory.appendingPathComponent("metro-port-ios")
        try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(bytes.utf8).write(to: legacy)

        #expect(throws: (any Error).self) { try logs.metroPort() }
        #expect(throws: (any Error).self) { try logs.recordMetroPort(8098) }

        #expect(try String(contentsOf: legacy, encoding: .utf8) == bytes)
        #expect(!FileManager.default.fileExists(atPath: (try logs.derivedDataDirectory).deletingLastPathComponent().path))
    }

    @Test("only an absent Metro port record uses the legacy endpoint")
    func metroPortRecord() throws {
        let logs = try realLogs(temporaryDirectory())
        #expect(try logs.metroPort() == nil)
        try logs.recordMetroPort(8097)
        #expect(try logs.metroPort() == 8097)
        for invalid in ["", "unreadable", "0", "65536"] {
            try Data(invalid.utf8).write(to: try logs.url("metro-port-ios"))
            #expect(throws: (any Error).self) { try logs.metroPort() }
            #expect(throws: (any Error).self) { try logs.recordMetroPort(8098) }
            #expect(try String(contentsOf: try logs.url("metro-port-ios"), encoding: .utf8) == invalid)
        }
    }

    @Test("a symlink port record is preserved and cannot redirect a write or teardown")
    func metroPortSymlink() throws {
        let temporary = try temporaryDirectory()
        let logs = try realLogs(temporary)
        try FileManager.default.createDirectory(at: (try logs.url("metro-port-ios")).deletingLastPathComponent(), withIntermediateDirectories: true)
        let other = temporary.appendingPathComponent("other")
        try Data("8097\n".utf8).write(to: other)
        try FileManager.default.createSymbolicLink(at: try logs.url("metro-port-ios"), withDestinationURL: other)
        #expect(throws: (any Error).self) { try logs.metroPort() }
        #expect(throws: (any Error).self) { try logs.recordMetroPort(8098) }
        #expect(try String(contentsOf: other, encoding: .utf8) == "8097\n")
    }

    @Test("one project preserves each platform's endpoint without retargeting the other's down")
    func separatePlatformPorts() throws {
        let logs = try realLogs(temporaryDirectory())
        try logs.recordMetroPort(8097, platform: .ios)
        #expect(try logs.metroPort(platform: .android) == nil)
        try logs.recordMetroPort(8098, platform: .android)
        #expect(try logs.metroPort(platform: .ios) == 8097)
        #expect(try logs.metroPort(platform: .android) == 8098)
        try Data("unconfirmed".utf8).write(to: try logs.url("metro-port-android"))
        #expect(throws: (any Error).self) { try logs.metroPort(platform: .android) }
        #expect(try logs.metroPort(platform: .ios) == 8097)
    }
    /// The repo is somebody else's house. A tool that writes its logs there is a tool
    /// that asks for a `.gitignore` entry in return for being run once.
    @Test("logs live under the system temporary directory, not in the project")
    func outsideTheProject() throws {
        let temporary = try temporaryDirectory()
        let project = URL(fileURLWithPath: "/Users/someone/work/MyApp")

        let logs = RunLogs(project: project, temporaryDirectory: temporary)

        #expect(logs.directory.path.hasPrefix(temporary.path + "/"))
        #expect(!logs.directory.path.contains("/work/MyApp"))
    }

    /// Two checkouts of the same app — a worktree, a second clone — would otherwise
    /// overwrite each other's logs, and the one you read would be the other run's.
    @Test("two projects with the same name get different directories")
    func perProject() throws {
        let temporary = try temporaryDirectory()

        let one = RunLogs(project: URL(fileURLWithPath: "/a/MyApp"), temporaryDirectory: temporary)
        let two = RunLogs(project: URL(fileURLWithPath: "/b/MyApp"), temporaryDirectory: temporary)

        #expect(one.directory != two.directory)
        // The name is still in there: a directory listing should be readable by a human
        // who is looking for their own project.
        #expect(one.directory.lastPathComponent.hasPrefix("MyApp-"))
    }

    /// The same project always gets the same directory, so the path printed by a
    /// failure an hour ago still points at a file that is there.
    @Test("the same project gets the same directory every time")
    func stable() throws {
        let temporary = try temporaryDirectory()
        let project = URL(fileURLWithPath: "/a/MyApp")

        #expect(
            RunLogs(project: project, temporaryDirectory: temporary).directory
                == RunLogs(project: project, temporaryDirectory: temporary).directory
        )
    }

    @Test("writing creates the directory and returns the file it wrote")
    func writes() throws {
        let temporary = try temporaryDirectory()
        let logs = try realLogs(temporary)

        let file = try #require(logs.write("the whole build log\n", to: "build.log"))

        #expect(file == (try logs.url("build.log")))
        #expect(try String(contentsOf: file, encoding: .utf8) == "the whole build log\n")
    }

    /// A log that could not be saved must not replace the failure being reported —
    /// the caller gets nil and says what it was going to say anyway.
    @Test("a directory that cannot be created yields no file, not an error")
    func unwritable() throws {
        let blocked = try temporaryDirectory().appendingPathComponent("file")
        try Data("not a directory".utf8).write(to: blocked)
        let logs = RunLogs(project: URL(fileURLWithPath: "/a/MyApp"), temporaryDirectory: blocked)

        #expect(logs.write("log", to: "build.log") == nil)
    }
}

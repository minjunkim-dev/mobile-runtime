import Foundation
import Testing

@testable import Core

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("mobile-runlogs-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("run logs")
struct RunLogsTests {
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
        arguments: ["mobile", "input", "output"], [false, true])
    func derivedDataSymlink(component: String, dangling: Bool) throws {
        let temporary = try temporaryDirectory()
        let logs = RunLogs(project: URL(fileURLWithPath: "/a/MyApp"), temporaryDirectory: temporary)
        let target = temporary.appendingPathComponent("preserved")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let marker = target.appendingPathComponent("keep")
        try Data("untouched".utf8).write(to: marker)
        let link = component == "mobile" ? logs.directory.deletingLastPathComponent()
            : component == "input" ? logs.directory : logs.url("DerivedData")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        let destination = dangling ? target.appendingPathComponent("missing") : target
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: destination)

        #expect(throws: (any Error).self) { try logs.derivedDataDirectory }

        #expect(try String(contentsOf: marker, encoding: .utf8) == "untouched")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == destination.path)
    }

    @Test("a regular file in the Xcode output path is preserved", arguments: ["mobile", "input", "output"])
    func derivedDataFile(component: String) throws {
        let temporary = try temporaryDirectory()
        let logs = RunLogs(project: URL(fileURLWithPath: "/a/MyApp"), temporaryDirectory: temporary)
        let file = component == "mobile" ? logs.directory.deletingLastPathComponent()
            : component == "input" ? logs.directory : logs.url("DerivedData")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("preserve".utf8).write(to: file)

        #expect(throws: (any Error).self) { try logs.derivedDataDirectory }

        #expect(try String(contentsOf: file, encoding: .utf8) == "preserve")
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
        let logs = RunLogs(project: URL(fileURLWithPath: "/a/MyApp"), temporaryDirectory: temporary)

        let file = try #require(logs.write("the whole build log\n", to: "build.log"))

        #expect(file == logs.directory.appendingPathComponent("build.log"))
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

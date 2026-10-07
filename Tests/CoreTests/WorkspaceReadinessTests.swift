import Foundation
import TestSupport
import Testing
@testable import Core

@Suite("Workspace preparation")
struct WorkspaceReadinessTests {
    @Test("readiness checks do not create an absent cache directory")
    func absentCache() async throws {
        let repo = try FixtureRepo()
        let cache = repo.url("missing/cache")
        let result = try await WorkspaceAccessCheck(paths: [repo.root, cache]).run()
        #expect(result.status == .pass)
        #expect(!FileManager.default.fileExists(atPath: cache.path))
    }

    @Test("an unobserved package cache is unknown rather than a guessed pass or permission error")
    func unobservedCache() async throws {
        let repo = try FixtureRepo()
        let result = try await WorkspaceAccessCheck(paths: [repo.root], unresolvedCache: "npm cache could not be read").run()
        #expect(result.status == .unknown)
        #expect(result.reason?.contains("npm cache") == true)
    }

    @Test("an inaccessible location reports its path and permission guidance")
    func deniedPath() async throws {
        let repo = try FixtureRepo()
        let path = repo.url("locked")
        try repo.directory("locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path) }
        // Root intentionally bypasses these mode bits; the CI non-root user verifies denial.
        guard !FileManager.default.isWritableFile(atPath: path.path) else { return }
        let result = try await WorkspaceAccessCheck(paths: [path]).run()
        #expect(result.status == .error)
        #expect(result.observed?.contains(path.path) == true)
        #expect(result.remediation?.summary.contains("Files & Folders") == true)
        #expect(result.remediation?.command == nil)
    }

    @Test("a file cannot substitute for a working directory")
    func filePath() async throws {
        let repo = try FixtureRepo()
        try repo.write("file", "data")
        #expect(try await WorkspaceAccessCheck(paths: [repo.url("file")]).run().status == .error)
    }

    @Test("storage recommendation is a warning, never a fabricated build requirement")
    func storage() {
        #expect(WorkspaceStorageCheck.outcome(availableBytes: 1024).status == .warning)
        #expect(WorkspaceStorageCheck.outcome(availableBytes: 10 * 1024 * 1024 * 1024).status == .pass)
    }
}

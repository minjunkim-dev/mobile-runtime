import Foundation

/// A real repo laid out in a temp directory. The file system is never mocked —
/// a throwaway directory is cheaper than a fake and tells the truth about
/// symlinks, missing files and nesting.
public final class FixtureRepo {
    public let root: URL

    public init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mobile-fixture-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        // A git root of its own, so an upward search can never wander out of the
        // fixture and into whatever happens to live above the temp directory.
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git"), withIntermediateDirectories: true
        )
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    public func url(_ relativePath: String) -> URL {
        root.appendingPathComponent(relativePath)
    }

    /// Creates the intermediate directories, so `write("packages/app/package.json", …)`
    /// is all a scenario needs to say.
    @discardableResult
    public func write(_ relativePath: String, _ contents: String) throws -> URL {
        let file = url(relativePath)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: file)
        return file
    }

    @discardableResult
    public func directory(_ relativePath: String) throws -> URL {
        let directory = url(relativePath)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

import Core
import Foundation

extension RunLogs {
    /// A log directory this test owns, under a temporary root of its own so two
    /// tests naming the same project never read each other's files.
    public static func temporary(
        project: URL = URL(fileURLWithPath: "/a/MyApp")
    ) throws -> RunLogs {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mobile-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return RunLogs(project: project, temporaryDirectory: root)
    }
}

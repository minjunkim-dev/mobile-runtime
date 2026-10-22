import Core
import Foundation

extension RunLogs {
    /// A log directory this test owns, under a temporary root of its own so two
    /// tests naming the same project never read each other's files.
    public static func temporary(
        project: URL? = nil
    ) throws -> RunLogs {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mobile-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let input = project ?? root.appendingPathComponent("source/MyApp")
        if project == nil { try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true) }
        return RunLogs(project: input, temporaryDirectory: root)
    }
    /// Find two real owned inputs that collide in the legacy log digest.
    public static func collidingProjects(temporary: URL) throws -> (URL, URL) {
        let parent = temporary.appendingPathComponent("sources").resolvingSymlinksInPath()
        var prefix: UInt32 = 2_166_136_261
        for byte in (parent.path + "/").utf8 { prefix = (prefix ^ UInt32(byte)) &* 16_777_619 }
        var seen: [UInt32: String] = [:]
        var collision: (String, String)?
        // Find names within this test's owned temporary root; never create the
        // review-only paths or the thousands of candidate directories.
        for index in 0..<1_000_000 {
            let name = String(UInt64(index) &* 0x9e3779b97f4a7c15, radix: 16)
            var digest = prefix
            for byte in (name + "/MyApp").utf8 { digest = (digest ^ UInt32(byte)) &* 16_777_619 }
            if let other = seen.updateValue(name, forKey: digest) { collision = (other, name); break }
        }
        guard let names = collision else { throw CocoaError(.fileReadUnknown) }
        let first = parent.appendingPathComponent(names.0).appendingPathComponent("MyApp")
        let second = parent.appendingPathComponent(names.1).appendingPathComponent("MyApp")
        for input in [first, second] { try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true) }
        return (first, second)
    }
}

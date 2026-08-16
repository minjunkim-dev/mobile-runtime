import Foundation

/// What `up` installed, and where. Written by `install` — the first moment the udid
/// and the bundle id are both settled — and read by `down`, which has no other way
/// to know which app on which simulator is this project's: a simulator cannot be
/// asked, and recomputing the bundle id needs a scheme, the one thing 3 of 3
/// dogfooding repos did not declare (ADR-0007).
///
/// A record, not a cache. When it is missing `down` skips the app and says so; it
/// never fills the gap by recomputing.
public struct InstallRecord: Codable, Sendable, Equatable {
    public let udid: String
    public let bundleId: String

    public init(udid: String, bundleId: String) {
        self.udid = udid
        self.bundleId = bundleId
    }

    /// Next to the run logs, in the same per-project temp directory: one place for
    /// what a run leaves behind, and nothing written into the user's repo.
    public static let fileName = "install.json"

    public static func read(from logs: RunLogs) -> InstallRecord? {
        guard let data = try? Data(contentsOf: logs.url(fileName)) else { return nil }
        return try? JSONDecoder().decode(InstallRecord.self, from: data)
    }

    /// Best effort, like every other thing written under the log directory: a record
    /// that could not be saved must not become the failure of the run that installed
    /// the app. The cost of losing it is one `down` that skips the app.
    ///
    /// - Returns: the file written, or nil when it could not be.
    @discardableResult
    public func write(to logs: RunLogs) -> URL? {
        guard let json = try? JSONOutput.encode(self) else { return nil }
        return logs.write(json, to: Self.fileName)
    }
}

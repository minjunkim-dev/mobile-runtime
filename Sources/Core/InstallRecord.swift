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

    public static func read(from logs: RunLogs, leases: ResourceLeases = .user,
                            ownerProject: String? = nil) throws -> InstallRecord? {
        if let current = try readRecord(at: logs.url(fileName)) { return current }
        let legacy = logs.directory.appendingPathComponent(fileName)
        guard let previous = try readRecord(at: legacy) else { return nil }
        guard try leases.ownsClaim(device: .device(.ios, previous.udid),
            project: ownerProject ?? logs.project.standardizedFileURL.resolvingSymlinksInPath().path,
            appID: previous.bundleId) else {
            throw DomainError(summary: "The legacy install record has no confirmed project owner.",
                remediation: Remediation(summary: "Inspect the existing run's record and device claim. Existing apps and records were preserved."))
        }
        return previous
    }

    private static func readRecord(at file: URL) throws -> InstallRecord? {
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: file.path) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.uint64Value <= 1_048_576 else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        return try JSONDecoder().decode(InstallRecord.self, from: Data(contentsOf: file))
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

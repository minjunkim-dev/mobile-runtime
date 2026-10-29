import Foundation

/// Display provenance only; never grants permission to stop or delete a device.
public enum DeviceOrigin: String, Codable, Sendable {
    case runstir, external, unknown

    public var displayName: String {
        switch self {
        case .runstir: "Runstir가 만듦"
        case .external: "외부 기기"
        case .unknown: "출처 불명"
        }
    }
}

/// One user namespace shared with CLI/GUI leases, independent of project and TMPDIR.
public struct DeviceOriginStore: Sendable {
    public let leases: ResourceLeases
    public var file: URL { leases.directory.appendingPathComponent("device-origins.json") }
    public static var user: Self { Self(leases: .user) }
    public init(leases: ResourceLeases) {
        self.leases = ResourceLeases(directory: leases.directory.standardizedFileURL.resolvingSymlinksInPath())
    }

    private struct Record: Codable, Equatable {
        let platform: ProjectPlatform
        let id: String
        let directory: String?
        let created: Date?
    }
    private struct Document: Codable {
        var version = 1
        var records: [Record] = []
    }

    public func origin(platform: ProjectPlatform, id: String, directory: URL? = nil) -> DeviceOrigin {
        do {
            let records = try read().records.filter { $0.platform == platform && $0.id == id }
            guard !records.isEmpty else { return .external }
            let current = try identity(platform: platform, id: id, directory: directory)
            return records.contains(current) ? .runstir : .unknown
        } catch { return .unknown }
    }

    public var warning: String? {
        do { _ = try read(); return nil }
        catch { return "The virtual-device origin record cannot be read. Device origins are unknown. Preserve the record and inspect its permissions and contents manually; Runstir did not repair or overwrite it." }
    }

    public func record(platform: ProjectPlatform, id: String, directory: URL? = nil) throws {
        try Task.checkCancellation()
        let current = try identity(platform: platform, id: id, directory: directory)
        let lease = try leases.acquire([.destination(file)], owner: LeaseOwner(
            operationId: UUID().uuidString, command: "record-device-origin", project: file.path))
        defer { lease.release() }
        var document = try read()
        if document.records.contains(current) { return }
        document.records.append(current)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)
        guard data.count <= 4_000_000 else { throw failure() }
        try Task.checkCancellation()
        try data.write(to: file, options: .atomic)
    }

    private func read() throws -> Document {
        let manager = FileManager.default
        // lstat-like attributes also distinguish a dangling link from an absent file.
        let attributes: [FileAttributeKey: Any]
        do { attributes = try manager.attributesOfItem(atPath: file.path) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return Document() }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.intValue <= 4_000_000,
              file.deletingLastPathComponent().resolvingSymlinksInPath().path == file.deletingLastPathComponent().standardizedFileURL.path else {
            throw failure()
        }
        let data = try Data(contentsOf: file)
        guard data.count <= 4_000_000 else { throw failure() }
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.version == 1, document.records.allSatisfy({ record in
            !record.id.isEmpty && (record.platform == .ios
                ? UUID(uuidString: record.id) != nil && record.directory == nil && record.created == nil
                : record.directory?.hasPrefix("/") == true && record.created != nil)
        }) else { throw failure() }
        return document
    }

    private func identity(platform: ProjectPlatform, id: String, directory: URL?) throws -> Record {
        if platform == .ios {
            guard UUID(uuidString: id) != nil else { throw failure() }
            return Record(platform: platform, id: id, directory: nil, created: nil)
        }
        guard !id.isEmpty, let directory else { throw failure() }
        let canonical = directory.standardizedFileURL.resolvingSymlinksInPath()
        let values = try canonical.resourceValues(forKeys: [.isDirectoryKey, .creationDateKey])
        guard values.isDirectory == true, let created = values.creationDate else { throw failure() }
        return Record(platform: platform, id: id, directory: canonical.path, created: created)
    }

    private func failure() -> DomainError {
        DomainError(summary: "The virtual-device origin record or device identity is unavailable.",
            remediation: Remediation(summary: "Preserve the created device and the existing origin record. Inspect the record and device identity manually. Runstir did not delete the device or repair the record."))
    }
}

public struct DeviceOriginCheck: Check {
    public let id = "host.device-origins"
    public let category = "Host"
    public let title = "Virtual-device origins"
    public init() {}
    public func run() async throws -> CheckOutcome {
        if let warning = DeviceOriginStore.user.warning {
            return .warning(observed: warning, remediation: Remediation(summary: warning))
        }
        return .pass(observed: "The virtual-device origin record is readable or has not been created.")
    }
}

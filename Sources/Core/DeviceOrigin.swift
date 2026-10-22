import Foundation

/// Who made a virtual execution device (ADR-0045). Display only: device selection, `down`
/// and deletion never read it. Physical devices have none.
public enum DeviceOrigin: String, Codable, Sendable {
    case runstirCreated = "runstir-created"
    case external
    case unknown

    public var label: String {
        switch self {
        case .runstirCreated: "Runstir-created"
        case .external: "external device"
        case .unknown: "origin unknown"
        }
    }
}

/// The per-user record of virtual devices that approved setup created and confirmed.
/// Shared by every project and worktree; never backfilled, repaired or pruned.
public struct DeviceOriginRecord: Sendable {
    public struct Device: Codable, Sendable, Equatable {
        public let platform: ProjectPlatform
        /// The Simulator UDID or the AVD name.
        public let id: String
        /// AVD only: the resolved AVD folder and that folder's birth time.
        public let folder: String?
        public let folderCreated: String?

        public static func simulator(_ udid: String) -> Device {
            Device(platform: .ios, id: udid, folder: nil, folderCreated: nil)
        }

        /// nil when the folder's birth time cannot be read.
        public static func avd(name: String, folder: URL) -> Device? {
            #if canImport(Darwin)
            let path = folder.resolvingSymlinksInPath().standardizedFileURL.path
            var info = stat()
            guard stat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { return nil }
            let birth = info.st_birthtimespec
            return Device(platform: .android, id: name, folder: path,
                          folderCreated: "\(birth.tv_sec).\(String(format: "%09ld", birth.tv_nsec))")
            #else
            return nil  // No birth time to compare, so the origin stays unknown.
            #endif
        }
    }

    private struct Document: Codable {
        var schemaVersion = 1
        var devices: [Device]
    }

    public let file: URL

    public init(environment: [String: String]) {
        let home = environment["HOME"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser
        file = home.appendingPathComponent("Library/Application Support/dev.runstir/device-origins.json")
    }

    /// Recorded devices; empty when nothing was recorded, nil when the file cannot be read.
    public func devices() -> [Device]? {
        try? read()?.devices ?? []
    }

    public func origin(platform: ProjectPlatform, id: String, folder: String?) -> DeviceOrigin {
        Self.origin(platform: platform, id: id, folder: folder, recorded: devices())
    }

    public static func origin(platform: ProjectPlatform, id: String, folder: String?, recorded: [Device]?) -> DeviceOrigin {
        guard let recorded else { return .unknown }
        let matches = recorded.filter { $0.platform == platform && $0.id == id }
        guard !matches.isEmpty else { return .external }
        guard platform == .android else { return .runstirCreated }
        guard let current = folder.flatMap({ Device.avd(name: id, folder: URL(fileURLWithPath: $0)) }) else { return .unknown }
        return matches.contains(current) ? .runstirCreated : .unknown
    }

    /// Reads the record once for a whole list of virtual devices.
    public func annotate(_ devices: [RuntimeDeviceCandidate], platform: ProjectPlatform) -> [RuntimeDeviceCandidate] {
        let recorded = self.devices()
        return devices.map { device in
            var device = device
            device.origin = Self.origin(platform: platform, id: platform == .ios ? device.id : device.name,
                                        folder: device.avdFolder, recorded: recorded)
            return device
        }
    }

    public func annotate(_ devices: [AppFileDevice], platform: ProjectPlatform) -> [AppFileDevice] {
        let recorded = self.devices()
        return devices.map { device in
            var device = device
            device.origin = Self.origin(platform: platform, id: platform == .ios ? device.id : device.name,
                                        folder: device.avdFolder, recorded: recorded)
            return device
        }
    }

    /// Adds one confirmed creation. An unreadable file is reported, never replaced.
    public func record(_ device: Device) throws {
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let lock = open(directory.appendingPathComponent("device-origins.lock").path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard lock >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(lock) }
        guard flock(lock, LOCK_EX) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var document = try read() ?? Document(devices: [])
        guard !document.devices.contains(device) else { return }
        document.devices.append(device)
        try Data(JSONOutput.encode(document).utf8).write(to: file, options: .atomic)
    }

    private func read() throws -> Document? {
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: file.path) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.uint64Value <= 1_048_576 else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: file))
        guard document.schemaVersion == 1 else { throw CocoaError(.fileReadCorruptFile) }
        return document
    }
}

/// An unreadable record turns every virtual device's origin unknown. Doctor says so; nothing repairs it.
public struct DeviceOriginRecordCheck: Check {
    public let id = "host.device-origin-record"
    public let category = "Workspace"
    public let title = "The virtual device origin record is readable"
    public let dependsOn: [String] = []
    let record: DeviceOriginRecord

    public init(record: DeviceOriginRecord) { self.record = record }

    public func run() async throws -> CheckOutcome {
        guard record.devices() != nil else {
            return .warning(observed: "\(record.file.path) exists but could not be read; virtual devices show origin unknown",
                remediation: Remediation(summary: "Inspect or move that file yourself. Runstir does not repair or overwrite it; devices and selection are unaffected."))
        }
        return .pass(observed: FileManager.default.fileExists(atPath: record.file.path) ? record.file.path : "no virtual device created by setup is recorded")
    }
}

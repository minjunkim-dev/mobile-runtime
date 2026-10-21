import Foundation

/// One name per real resource. CLI, GUI and separate processes derive the same key,
/// so they collide on the same lock.
public struct ResourceKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    private init(_ rawValue: String) { self.rawValue = rawValue }

    /// The real folder: symlinks and path aliases share one key.
    public static func folder(_ identity: FolderIdentity) -> Self {
        Self("folder:\(identity.volume):\(identity.file)")
    }

    public static func appFile(_ identity: AppFileIdentity) -> Self {
        // Stable if a user replaces the bytes at the same path while a task is active.
        Self("app-file:\(identity.path)")
    }

    public static func appFileObject(_ identity: AppFileIdentity) -> Self {
        Self("app-file-object:\(identity.volume):\(identity.file)")
    }

    /// The canonical path stays the same before and after installation creates it.
    public static func destination(_ url: URL) -> Self {
        Self("destination:\(url.resolvingSymlinksInPath().standardizedFileURL.path)")
    }

    public static func device(_ platform: ProjectPlatform, _ id: String) -> Self {
        Self("device:\(platform.rawValue):\(id)")
    }

    public static func app(_ platform: ProjectPlatform, device: String, appID: String) -> Self {
        Self("app:\(platform.rawValue):\(device):\(appID)")
    }

    public static func port(_ port: Int) -> Self { Self("port:\(port)") }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public var description: String { rawValue }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct LeaseOwner: Codable, Sendable, Equatable {
    public let operationId: String
    public let command: String
    public let project: String
    /// Shown to people only. Liveness comes from the kernel lock or a fresh observation,
    /// never from a pid that the system can reuse.
    public let pid: Int32

    public init(operationId: String, command: String, project: String,
                pid: Int32 = ProcessInfo.processInfo.processIdentifier) {
        self.operationId = operationId
        self.command = command
        self.project = project
        self.pid = pid
    }
}

public struct ResourceConflict: Error, Codable, Sendable, Equatable {
    public let key: ResourceKey
    /// nil when the owner cannot be confirmed. The resource is preserved either way.
    public let owner: LeaseOwner?
    public let reason: String

    public init(key: ResourceKey, owner: LeaseOwner?, reason: String) {
        self.key = key
        self.owner = owner
        self.reason = reason
    }

    public var domainError: DomainError {
        DomainError(
            summary: "\(key) is in use: \(reason)",
            remediation: Remediation(summary: "Select another resource or explicitly stop the owning operation, then check again. Nothing was switched, stopped, queued or removed.")
        )
    }
}

/// Nonblocking process leases in one fixed per-user directory. The kernel drops a lock
/// when its process ends, so a dead owner never blocks and a live one always does.
public struct ResourceLeases: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    /// Independent of TMPDIR, so every client of one user meets the same locks.
    public static var user: ResourceLeases {
        ResourceLeases(directory: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/dev.runstir/leases"))
    }

    /// Takes every key or none: a conflict releases only the keys this call took.
    public func acquire(_ keys: [ResourceKey], owner: LeaseOwner) throws -> ResourceLease {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lease = ResourceLease()
        // One global order, so two operations never each hold half of the other's keys.
        for key in Set(keys).sorted() {
            try lease.take(key, file: file(key, "lock"), owner: owner)
        }
        return lease
    }

    func file(_ key: ResourceKey, _ suffix: String) -> URL {
        // FNV-1a: stable across processes. A collision only adds a false conflict.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in key.rawValue.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        let hex = String(hash, radix: 16)
        return directory.appendingPathComponent(String(repeating: "0", count: 16 - hex.count) + hex + "." + suffix)
    }
}

public final class ResourceLease: @unchecked Sendable {
    private let lock = NSLock()
    private var descriptors: [Int32] = []

    fileprivate init() {}

    deinit { release() }

    fileprivate func take(_ key: ResourceKey, file: URL, owner: LeaseOwner) throws {
        // Close-on-exec: a detached Metro or emulator must not inherit the lock.
        let descriptor = open(file.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(descriptor)
            guard code == EWOULDBLOCK else { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
            let holder = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(LeaseOwner.self, from: $0) }
            throw ResourceConflict(key: key, owner: holder, reason: holder.map {
                "held by \($0.command) operation \($0.operationId) for \($0.project) (pid \($0.pid))"
            } ?? "a running process holds it and its owner record is missing or unreadable")
        }
        lock.withLock { descriptors.append(descriptor) }
        // A record already here belongs to a process the kernel released: replace it.
        let record = try JSONEncoder().encode(owner)
        let written = record.withUnsafeBytes { ftruncate(descriptor, 0) == 0 ? pwrite(descriptor, $0.baseAddress, $0.count, 0) : -1 }
        guard written == record.count else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    /// Idempotent. Releases only this operation's keys.
    public func release() {
        lock.withLock {
            for descriptor in descriptors.reversed() {
                _ = ftruncate(descriptor, 0)
                _ = flock(descriptor, LOCK_UN)
                close(descriptor)
            }
            descriptors = []
        }
    }
}

/// What a finished run leaves on a device. The lease ends with the command; the app
/// and its device stay in use until someone observes otherwise.
public struct ResourceClaim: Codable, Sendable, Equatable {
    public let device: ResourceKey
    public let platform: ProjectPlatform
    /// The handle an observer addresses: a Simulator udid or an adb serial.
    public let handle: String
    public let appID: String
    public let owner: LeaseOwner

    public init(device: ResourceKey, platform: ProjectPlatform, handle: String, appID: String, owner: LeaseOwner) {
        self.device = device
        self.platform = platform
        self.handle = handle
        self.appID = appID
        self.owner = owner
    }

    public var app: ResourceKey { .app(platform, device: handle, appID: appID) }
}

public enum ClaimObservation: Sendable, Equatable {
    case running(String)
    case stopped
    case unknown(String)
}

extension ResourceLeases {
    /// A legacy install record may name a device but cannot prove its folder owner.
    /// Read the existing reservation book without creating or changing a claim.
    public func ownsClaim(device: ResourceKey, project: String, appID: String) throws -> Bool {
        let location = file(device, "claim")
        do {
            let root = try FileManager.default.attributesOfItem(atPath: directory.path)
            let attributes = try FileManager.default.attributesOfItem(atPath: location.path)
            guard root[.type] as? FileAttributeType == .typeDirectory,
                  attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = attributes[.size] as? NSNumber, size.uint64Value <= 1_048_576 else {
                throw ResourceConflict(key: device, owner: nil, reason: "the previous app claim is redirected or unreadable")
            }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile { return false }
        guard let saved = try reservation(device: device), let claim = saved.claim else { return false }
        return saved.owner.project == project && claim.device == device && claim.appID == appID
    }

    /// Call while holding `device`, before changes. A failed final record leaves this
    /// owner's unconfirmed reservation in place so another project cannot take over.
    public func reserve(device: ResourceKey, owner: LeaseOwner) throws {
        try write(DeviceReservation(owner: owner, claim: nil), device: device)
    }

    public func record(_ claim: ResourceClaim) throws {
        try write(DeviceReservation(owner: claim.owner, claim: claim), device: claim.device)
    }

    private func write(_ reservation: DeviceReservation, device: ResourceKey) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(reservation).write(to: file(device, "claim"), options: .atomic)
    }

    /// Call under the device lease only after its owning runtime has been verified stopped.
    public func releaseAfterTeardown(device: ResourceKey, project: String) throws {
        guard let reservation = try reservation(device: device) else { return }
        guard reservation.owner.project == project else {
            throw ResourceConflict(key: device, owner: reservation.owner,
                reason: "the device claim belongs to another project and was preserved")
        }
        try FileManager.default.removeItem(at: file(device, "claim"))
    }

    private func reservation(device: ResourceKey) throws -> DeviceReservation? {
        let file = file(device, "claim")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let unreadable = ResourceConflict(key: device, owner: nil,
            reason: "a previous run's claim on this device is unreadable or inconsistent: \(file.path)")
        guard let data = try? Data(contentsOf: file) else { throw unreadable }
        let reservation: DeviceReservation
        // Existing installations wrote ResourceClaim directly rather than a reservation.
        if let claim = try? JSONDecoder().decode(ResourceClaim.self, from: data) {
            reservation = DeviceReservation(owner: claim.owner, claim: claim)
        } else if let saved = try? JSONDecoder().decode(DeviceReservation.self, from: data) {
            reservation = saved
        } else {
            throw unreadable
        }
        if let claim = reservation.claim {
            guard claim.device == device, claim.owner == reservation.owner else { throw unreadable }
        }
        return reservation
    }

    /// Call while holding `device`. Another project's claim is observed again; only an
    /// observed stop removes it. A running or unobservable app blocks the device.
    public func check(device: ResourceKey, project: String,
                      observe: (ResourceClaim) async throws -> ClaimObservation) async throws {
        let file = file(device, "claim")
        guard let reservation = try reservation(device: device) else { return }
        guard reservation.owner.project != project else { return }
        guard let claim = reservation.claim else {
            let owner = reservation.owner
            throw ResourceConflict(key: device, owner: owner,
                reason: "the result of \(owner.command) operation \(owner.operationId) for \(owner.project) is unconfirmed; its device reservation stays at \(file.path)")
        }
        let leftBehind = "\(claim.appID) from \(claim.owner.project) (\(claim.owner.command) operation \(claim.owner.operationId))"
        switch try await observe(claim) {
        case .stopped:
            try? FileManager.default.removeItem(at: file)
        case .running(let detail):
            throw ResourceConflict(key: claim.app, owner: claim.owner, reason: "\(leftBehind) is still running on this device after its run finished: \(detail)")
        case .unknown(let detail):
            throw ResourceConflict(key: claim.app, owner: claim.owner, reason: "\(leftBehind) may still be running; it could not be observed: \(detail). The claim stays at \(file.path)")
        }
    }
}

private struct DeviceReservation: Codable {
    let owner: LeaseOwner
    let claim: ResourceClaim?
}

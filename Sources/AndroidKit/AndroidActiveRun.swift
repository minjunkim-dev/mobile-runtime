import Core
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

struct AndroidActiveRun: Codable, Sendable, Equatable {
    struct Target: Codable, Sendable, Equatable {
        let module: String
        let variant: String
        let applicationId: String
        let launcherActivity: String
        let avdSelector: String?
        var framework: ProjectFramework? = nil
        var entrypoint: String? = nil
        var serverSocket: String? = nil
    }

    struct Device: Codable, Sendable, Equatable {
        var avd: String
        var launcherPID: Int32?
        var serial: String?
        var api: Int?
        var abi: String?
        var state: AndroidDevice.State
    }

    struct Metro: Codable, Sendable, Equatable {
        var state: MetroProcess.State
        var startPID: Int32?
        var listenerPID: Int32?
        var logPath: String?
    }

    struct Reverse: Codable, Sendable, Equatable {
        let serial: String
        var state: AndroidReverse.State
    }

    struct App: Codable, Sendable, Equatable {
        let serial: String
        let applicationId: String
        var launched: Bool
        var pid: Int32?
    }

    struct Forward: Codable, Sendable, Equatable {
        enum State: String, Codable, Sendable { case pending, created }
        var state: State
        let serial: String
        let avd: String
        let applicationId: String
        let module: String
        let variant: String
        let entrypoint: String
        let appPID: Int32
        let hostPort: Int
        let devicePort: Int
        let launchMarker: String
        let operationID: String
        let serverSocket: String
    }

    let schemaVersion: Int
    let project: String
    let target: Target
    var device: Device?
    var metro: Metro?
    var reverse: Reverse?
    var app: App?
    var forward: Forward?

    init(project: URL, product: AndroidBuiltProduct, avdSelector: String? = nil,
         flutterEntrypoint: URL? = nil, flutterServerSocket: String? = nil) {
        schemaVersion = flutterEntrypoint == nil ? 1 : 2
        self.project = project.resolvingSymlinksInPath().path
        target = Target(
            module: product.module,
            variant: product.variant,
            applicationId: product.applicationId,
            launcherActivity: product.launcherActivity,
            avdSelector: avdSelector,
            framework: flutterEntrypoint == nil ? nil : .flutter,
            entrypoint: flutterEntrypoint?.resolvingSymlinksInPath().path,
            serverSocket: flutterServerSocket
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, project, target, device, metro, reverse, app, forward
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == 1 || schemaVersion == 2,
              schemaVersion != 1 || !values.contains(.forward) else {
            throw AndroidStateError("unsupported Android active-run schema or forward state")
        }
        project = try values.decode(String.self, forKey: .project)
        target = try values.decode(Target.self, forKey: .target)
        device = try values.decodeIfPresent(Device.self, forKey: .device)
        metro = try values.decodeIfPresent(Metro.self, forKey: .metro)
        reverse = try values.decodeIfPresent(Reverse.self, forKey: .reverse)
        app = try values.decodeIfPresent(App.self, forKey: .app)
        forward = try values.decodeIfPresent(Forward.self, forKey: .forward)
        try validate()
    }

    func validate() throws {
        guard schemaVersion == 1 || schemaVersion == 2 else {
            throw AndroidStateError("unsupported Android active-run schema")
        }
        if schemaVersion == 1 {
            guard target.framework == nil, target.entrypoint == nil, target.serverSocket == nil, forward == nil else {
                throw AndroidStateError("legacy Android state contains Flutter ownership")
            }
            return
        }
        guard target.framework == .flutter, let entrypoint = target.entrypoint,
              project.hasPrefix("/"), !target.module.isEmpty, !target.variant.isEmpty,
              !target.applicationId.isEmpty, !target.launcherActivity.isEmpty,
              entrypoint.hasPrefix(project + "/"), entrypoint.hasSuffix(".dart"),
              URL(fileURLWithPath: entrypoint).standardizedFileURL.path == entrypoint,
              let serverSocket = target.serverSocket, metro == nil, reverse == nil else {
            throw AndroidStateError("incoherent Flutter Android target")
        }
        _ = try AndroidADBEndpoint(socket: serverSocket)
        if let device {
            guard !device.avd.isEmpty, target.avdSelector == nil || target.avdSelector == device.avd,
                  device.serial == nil || device.serial?.isEmpty == false,
                  device.launcherPID == nil || (device.launcherPID ?? 0) > 0 else {
                throw AndroidStateError("incoherent Flutter device ownership")
            }
        }
        if let app {
            guard let device, device.serial == app.serial, !app.serial.isEmpty,
                  app.applicationId == target.applicationId,
                  app.pid == nil || (app.launched && (app.pid ?? 0) > 0) else {
                throw AndroidStateError("incoherent Flutter app ownership")
            }
        }
        guard let forward else { return }
        guard let device, let app, app.launched, app.pid == forward.appPID,
              !forward.serial.isEmpty, !forward.avd.isEmpty,
              forward.appPID > 0, forward.serial == device.serial, forward.serial == app.serial,
              forward.avd == device.avd, forward.applicationId == target.applicationId,
              forward.applicationId == app.applicationId, forward.module == target.module,
              forward.variant == target.variant, forward.entrypoint == entrypoint,
              forward.serverSocket == serverSocket,
              (1...65535).contains(forward.hostPort), (1...65535).contains(forward.devicePort),
              UUID(uuidString: forward.operationID) != nil,
              AndroidFlutterService.epoch(forward.launchMarker) != nil else {
            throw AndroidStateError("incoherent Flutter forward ownership")
        }
        _ = try AndroidADBEndpoint(socket: forward.serverSocket)
    }

    var isEmpty: Bool {
        device == nil && metro == nil && reverse == nil && app == nil && forward == nil
    }

    func matches(
        project: URL, product: AndroidBuiltProduct, avdSelector: String? = nil,
        flutterEntrypoint: URL? = nil, flutterServerSocket: String? = nil
    ) -> Bool {
        self.project == project.resolvingSymlinksInPath().path
            && target == Target(
                module: product.module,
                variant: product.variant,
                applicationId: product.applicationId,
                launcherActivity: product.launcherActivity,
                avdSelector: avdSelector,
                framework: flutterEntrypoint == nil ? nil : .flutter,
                entrypoint: flutterEntrypoint?.resolvingSymlinksInPath().path,
                serverSocket: flutterServerSocket
            )
    }
}

struct AndroidActiveRunStore: Sendable {
    static let fileName = "android-active-run.json"
    static let lockName = "android-lifecycle.lock"

    let project: URL
    let logs: RunLogs
    private let operation: WorkflowKind

    init(project: URL, logs: RunLogs? = nil, operation: WorkflowKind = .up) {
        self.project = project.resolvingSymlinksInPath()
        self.logs = logs ?? RunLogs(project: project)
        self.operation = operation
    }

    var file: URL {
        get throws {
            let current = try logs.url(Self.fileName)
            do {
                _ = try FileManager.default.attributesOfItem(atPath: current.path)
                return current
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {}
            let legacy = logs.directory.appendingPathComponent(Self.fileName)
            guard try readRecord(at: legacy) != nil else { return current }
            guard operation == .down else {
                throw AndroidStateError("an existing legacy Android run must finish mobile down --platform android before a new run")
            }
            // A base-main record has a canonical project. Only its original down
            // cleanup may update it, under its original lifecycle lock.
            return legacy
        }
    }

    var lockFile: URL {
        get throws {
            let record = try file
            let lock = record.deletingLastPathComponent().appendingPathComponent(Self.lockName)
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: lock.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular else {
                    throw AndroidStateError("the Android lifecycle lock is redirected or is not a regular file")
                }
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile { return lock }
            return lock
        }
    }

    func read() throws -> AndroidActiveRun? { try readRecord(at: file) }

    private func readRecord(at location: URL) throws -> AndroidActiveRun? {
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: location.path) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.uint64Value <= 1_048_576 else {
            throw AndroidStateError("the Android active-run record is redirected or unreadable")
        }
        do {
            let run = try JSONDecoder().decode(AndroidActiveRun.self, from: Data(contentsOf: location))
            guard run.project == project.path else {
                throw AndroidStateError("the Android active-run record does not belong to this project")
            }
            return run
        } catch let error as AndroidStateError { throw error }
        catch { throw AndroidStateError("the Android active-run record is unreadable: \(error)") }
    }

    func write(_ run: AndroidActiveRun) throws {
        guard run.project == project.path else {
            throw AndroidStateError("refusing to write an Android active run for another project")
        }
        try run.validate()
        let location = try file
        _ = try readRecord(at: location)
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(run).write(to: location, options: .atomic)
    }

    func removeIfEmpty(_ run: AndroidActiveRun) throws {
        try run.validate()
        if run.isEmpty {
            let location = try file
            if try readRecord(at: location) != nil { try FileManager.default.removeItem(at: location) }
        } else {
            try write(run)
        }
    }

    func acquire(operation: String) throws -> AndroidLifecycleLease {
        try AndroidLifecycleLease(file: lockFile, operation: operation)
    }
}

struct AndroidStateError: Error, CustomStringConvertible, Sendable {
    let description: String
    init(_ description: String) { self.description = description }
}

final class AndroidLifecycleLease: @unchecked Sendable {
    private var descriptor: Int32

    init(file: URL, operation: String) throws {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let descriptor = open(file.path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw AndroidStateError("could not open the Android lifecycle lock for \(operation)")
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw DomainError(
                summary: "another Android lifecycle command is already running",
                remediation: Remediation(
                    summary: "Wait for the current mobile up/down command to finish, then retry."
                )
            )
        }
        self.descriptor = descriptor
    }

    deinit {
        if descriptor >= 0 {
            _ = flock(descriptor, LOCK_UN)
            close(descriptor)
            descriptor = -1
        }
    }
}

public struct AndroidRuntimeTimeouts: Sendable {
    public var boot: Duration
    public var install: Duration
    public var launch: Duration
    public var metroBind: Duration
    public var cleanupGrace: Duration
    public var poll: Duration

    public init(
        boot: Duration = .seconds(300),
        install: Duration = .seconds(120),
        launch: Duration = .seconds(30),
        metroBind: Duration = MetroLaunch.defaultBindWait,
        cleanupGrace: Duration = .seconds(2),
        poll: Duration = .milliseconds(250)
    ) {
        self.boot = boot
        self.install = install
        self.launch = launch
        self.metroBind = metroBind
        self.cleanupGrace = cleanupGrace
        self.poll = poll
    }
}

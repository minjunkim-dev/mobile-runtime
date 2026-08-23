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

    let schemaVersion: Int
    let project: String
    let target: Target
    var device: Device?
    var metro: Metro?
    var reverse: Reverse?
    var app: App?

    init(project: URL, product: AndroidBuiltProduct, avdSelector: String? = nil) {
        schemaVersion = 1
        self.project = project.resolvingSymlinksInPath().path
        target = Target(
            module: product.module,
            variant: product.variant,
            applicationId: product.applicationId,
            launcherActivity: product.launcherActivity,
            avdSelector: avdSelector
        )
    }

    var isEmpty: Bool {
        device == nil && metro == nil && reverse == nil && app == nil
    }

    func matches(
        project: URL, product: AndroidBuiltProduct, avdSelector: String? = nil
    ) -> Bool {
        self.project == project.resolvingSymlinksInPath().path
            && target == Target(
                module: product.module,
                variant: product.variant,
                applicationId: product.applicationId,
                launcherActivity: product.launcherActivity,
                avdSelector: avdSelector
            )
    }
}

struct AndroidActiveRunStore: Sendable {
    static let fileName = "android-active-run.json"
    static let lockName = "android-lifecycle.lock"

    let project: URL
    let logs: RunLogs

    init(project: URL, logs: RunLogs? = nil) {
        self.project = project.resolvingSymlinksInPath()
        self.logs = logs ?? RunLogs(project: project)
    }

    var file: URL { logs.url(Self.fileName) }
    var lockFile: URL { logs.url(Self.lockName) }

    func read() throws -> AndroidActiveRun? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        do {
            let run = try JSONDecoder().decode(AndroidActiveRun.self, from: Data(contentsOf: file))
            guard run.schemaVersion == 1, run.project == project.path else {
                throw AndroidStateError("the Android active-run record does not belong to this project")
            }
            return run
        } catch let error as AndroidStateError {
            throw error
        } catch {
            throw AndroidStateError("the Android active-run record is unreadable: \(error)")
        }
    }

    func write(_ run: AndroidActiveRun) throws {
        guard run.project == project.path else {
            throw AndroidStateError("refusing to write an Android active run for another project")
        }
        try FileManager.default.createDirectory(
            at: logs.directory, withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(run).write(to: file, options: .atomic)
    }

    func removeIfEmpty(_ run: AndroidActiveRun) throws {
        if run.isEmpty {
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
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
        let descriptor = open(file.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
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
        metroBind: Duration = .seconds(10),
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

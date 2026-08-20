import Foundation

/// How a Stage ended. Deliberately not `CheckStatus`: a Check hands down a verdict
/// on the machine, a Stage reports what it did to it. `skipped` is the honest word
/// for work that was already done — nothing to warn about, nothing to install.
public enum StageStatus: String, Sendable, Codable {
    case pass
    case skipped
    case failed
}

/// What a Stage says when it is done. Failure is thrown, never returned — a Stage
/// that failed has no result to hand forward, and the pipeline stops there.
public struct StageOutcome: Sendable, Equatable {
    public let status: StageStatus
    /// The one thing worth reading on the progress line — which device, which
    /// scheme, why it was skipped. nil when the status already says everything.
    public let detail: String?

    public static func pass(_ detail: String? = nil) -> StageOutcome {
        StageOutcome(status: .pass, detail: detail)
    }

    public static func skipped(_ detail: String? = nil) -> StageOutcome {
        StageOutcome(status: .skipped, detail: detail)
    }
}

/// A finished Stage, with the time it took. `id` is a stable contract — scripts and
/// JSON consumers hold on to it, so renaming one is a breaking change.
public struct StageResult: Sendable, Equatable {
    public let id: String
    public let status: StageStatus
    public let duration: Duration
    public let detail: String?

    public init(id: String, status: StageStatus, duration: Duration, detail: String? = nil) {
        self.id = id
        self.status = status
        self.duration = duration
        self.detail = detail
    }

    public var durationMs: Int { Int((duration.seconds * 1000).rounded()) }
}

/// The simulator `device` settled on. Lives here rather than in SimulatorKit because
/// the context and the JSON envelope are Core's, and Core knows nothing about simctl
/// — a name, a udid and a runtime is all the later stages and a script need.
public struct SelectedDevice: Sendable, Equatable, Encodable {
    public let name: String
    public let udid: String
    /// As the runtime writes it — `26.5`, not `26.5.0`.
    public let runtime: String

    public init(name: String, udid: String, runtime: String) {
        self.name = name
        self.udid = udid
        self.runtime = runtime
    }
}

/// What `build` produced, read out of `xcodebuild -showBuildSettings` rather than
/// out of the build log — log formats move between Xcode versions, and install must
/// pick up the exact bundle this run made.
public struct BuiltProduct: Sendable, Equatable, Encodable {
    /// The `.app` itself, in whatever derived data directory Xcode chose.
    public let path: String
    public let bundleIdentifier: String

    public init(path: String, bundleIdentifier: String) {
        self.path = path
        self.bundleIdentifier = bundleIdentifier
    }
}

/// The Metro bundler this run left behind. `pid` and `logPath` are absent on a reuse
/// on purpose: that process belongs to whoever started it, and a CI job has to be
/// able to clean up only what it started itself.
public struct MetroProcess: Sendable, Equatable, Encodable {
    public enum State: String, Sendable, Equatable, Encodable {
        case reused
        case spawned
    }

    /// The process `up` started: the project's start script. **Not** the bundler —
    /// that is its grandchild, and a `SIGTERM` here does not reach it. #61 measured
    /// the chain: killing this pid left 8081 held by a process two links down.
    public let pid: Int32?
    /// Who holds 8081, asked of the port once the bundler had bound it. This is the
    /// pid a human or a CI job would kill, and the one `mobile down` finds for
    /// itself. nil when the port had not answered in time — a fact about the run,
    /// not a failure of it, so nothing stops for it.
    public let listenerPid: Int32?
    public let state: State
    /// Where the detached child's two streams went — the only place its output is.
    public let logPath: String?

    public init(
        state: State, pid: Int32? = nil, listenerPid: Int32? = nil, logPath: String? = nil
    ) {
        self.state = state
        self.pid = pid
        self.listenerPid = listenerPid
        self.logPath = logPath
    }
}

/// What the Stages hand each other. Explicit and passed through the pipeline, so a
/// Stage can only read what an earlier one actually put here — no global state, and
/// no Stage reaching sideways into another's internals.
public struct UpContext: Sendable {
    /// `validate`'s report, kept past the stage that produced it: a failure renders
    /// through doctor's renderer, and warnings still have to be shown.
    public var validation: DoctorReport?

    /// Set by `device`, read by everything that has to name a simulator afterwards —
    /// build, install and launch all address the same udid.
    public var device: SelectedDevice?

    /// Set by `metro`. `launch` reads its ownership and log path to wait for the
    /// bundle signal, and the reader and `--json` report the same process.
    public var metro: MetroProcess?

    /// Set by `build`, consumed by `install` and `launch`.
    public var product: BuiltProduct?

    /// Where `build` streamed xcodebuild's whole output. Kept on a success too — the
    /// warnings a build that worked still printed are in there, and a failure names
    /// the same path in its remediation.
    public var buildLog: String?

    /// Set by `launch` — the app's pid inside the simulator. Read by nothing else in
    /// the pipeline: it is there so whatever runs after `up` can address the process
    /// without going looking for it.
    public var appPid: Int32?

    public init() {}
}

/// One step of `up`. Unlike a Check, a Stage exists for its side effect, its place
/// in the order is part of the contract, and it consumes what the Stage before it
/// produced. The two never merge into one type.
public protocol Stage: Sendable {
    /// Stable contract. Never rename.
    var id: String { get }

    func run(_ context: inout UpContext) async throws -> StageOutcome
}

extension Duration {
    var seconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) * 1e-18
    }
}

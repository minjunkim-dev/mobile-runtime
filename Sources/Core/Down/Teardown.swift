import Foundation

/// What `down` did about one thing it aims at. Three words rather than a Stage's
/// three: `down` does not build anything, it stops things — and "stopped nothing
/// because there was nothing" is the ordinary outcome, not a warning.
public enum TeardownStatus: String, Sendable, Codable {
    case stopped
    /// Nothing of this project's was there. The ordinary quiet outcome.
    case skipped
    /// Something is there and it is not this project's to stop — another project's
    /// Metro, or a port that cannot say whose it is. Nothing was done and nothing is
    /// wrong with the run, but "nothing to stop" would be the wrong thing to read.
    case blocked
    case failed
    /// The job could not be run, so nothing was observed about the thing it aimed
    /// at. Doctor's word for the same state, for the same reason: covering a
    /// judgement that could not be made with `skipped` is how a run reports an empty
    /// machine it never looked at.
    case unknown
}

/// One item of `down`'s report. `id` is `metro` or `app` — the same words `up`'s
/// stages use, because they point at the same things.
public struct TeardownItem: Sendable, Equatable {
    public let id: String
    public let status: TeardownStatus
    /// What was stopped, or why nothing was. A `down` whose every line said only
    /// `skipped` would leave the reader to guess between "not mine" and "not there".
    public let detail: String?
    /// What to do about a thing this run did not stop — carried by `failed` and by
    /// `blocked` alike. A blocked port has a next step too, and it is the one the
    /// verdict already wrote: the process holding 8081, by name.
    public let remediation: Remediation?

    public init(
        id: String, status: TeardownStatus, detail: String? = nil, remediation: Remediation? = nil
    ) {
        self.id = id
        self.status = status
        self.detail = detail
        self.remediation = remediation
    }

    public static func stopped(_ id: String, _ detail: String? = nil) -> TeardownItem {
        TeardownItem(id: id, status: .stopped, detail: detail)
    }

    public static func skipped(_ id: String, _ detail: String? = nil) -> TeardownItem {
        TeardownItem(id: id, status: .skipped, detail: detail)
    }

    public static func unknown(_ id: String, _ detail: String? = nil) -> TeardownItem {
        TeardownItem(id: id, status: .unknown, detail: detail)
    }

    /// The whole verdict, not its headline: which project the port is serving and
    /// the line that names the process are exactly what a blocked run is for.
    public static func blocked(_ id: String, _ error: DomainError) -> TeardownItem {
        TeardownItem(
            id: id, status: .blocked, detail: error.message, remediation: error.remediation
        )
    }

    public static func failed(_ id: String, _ error: DomainError) -> TeardownItem {
        TeardownItem(
            id: id, status: .failed, detail: error.message, remediation: error.remediation
        )
    }
}

/// What a run of `down` produced. Modelled on `DoctorReport`, not on `UpReport`:
/// every job is attempted and one failure hides none of the others.
public struct TeardownReport: Sendable {
    public let items: [TeardownItem]
    /// Jobs that could not be run at all — the tool or the machine, not the project.
    public let toolFailures: [String]
    /// A failure of the run itself rather than of one of its jobs — standing outside
    /// a project is the whole of it. Carried the way `up` carries one, so that no
    /// item has to be invented to hold it: `metro` and `app` are the only item ids.
    public let failure: DomainError?

    public init(
        items: [TeardownItem], toolFailures: [String] = [], failure: DomainError? = nil
    ) {
        self.items = items
        self.toolFailures = toolFailures
        self.failure = failure
    }

    /// Doctor's vocabulary again, so a consumer does not learn a second one — and a
    /// run that could not ask must not answer `pass`: that is the envelope saying
    /// the machine is clean while the exit code says the tool broke.
    public var status: CheckStatus {
        if failure != nil || items.contains(where: { $0.status == .failed }) { return .error }
        if !toolFailures.isEmpty || items.contains(where: { $0.status == .unknown }) {
            return .unknown
        }
        return .pass
    }

    /// Nothing of this project's was there to stop. A fact about the machine, not a
    /// verdict about it — hence exit 0 and a sentence, rather than a warning. A
    /// blocked item is not this: something was there, and it was somebody else's.
    public var stoppedNothing: Bool {
        items.allSatisfy { $0.status == .skipped }
    }

    /// The same split doctor and up make: 1 is the project's problem, 2 is ours.
    public var exitCode: Int32 {
        if !toolFailures.isEmpty { return 2 }
        return status == .error ? 1 : 0
    }
}

/// Runs `down`'s jobs and collects what they said. Not a pipeline: the jobs are
/// independent, so a Metro that would not die is no reason to leave the app running
/// (ADR-0007). The `Stage` protocol stays `up`'s.
public struct Teardown: Sendable {
    /// A job is its id and the work: the id is needed before the work runs, to name
    /// the item a job that threw could not name itself.
    public typealias Job = (id: String, run: @Sendable () async throws -> TeardownItem)

    private let jobs: [Job]

    public init(jobs: [Job]) {
        self.jobs = jobs
    }

    public func run() async -> TeardownReport {
        var items: [TeardownItem] = []
        var toolFailures: [String] = []

        for job in jobs {
            do {
                items.append(try await job.run())
            } catch {
                // A job that could not run says nothing about the thing it aimed at.
                // Not `failed` — that word is for "it is still there" — and above all
                // not `skipped`, which would make a run that never looked report an
                // empty machine. It lands on the exit code as the tool's problem.
                items.append(.unknown(job.id, "could not run"))
                toolFailures.append("\(job.id): \(error)")
            }
        }

        return TeardownReport(items: items, toolFailures: toolFailures)
    }
}

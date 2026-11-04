import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// A process told apart from a later one that reuses its pid: the start time is part of
/// who it is, so a signal meant for this process never reaches a stranger.
struct ProcessIdentity: Hashable, Sendable, CustomStringConvertible {
    let pid: Int32
    /// Microseconds since the epoch.
    let started: UInt64

    var description: String { "\(pid)@\(started)" }
}

/// A live process and the pid of its parent.
struct ProcessEntry: Sendable {
    let identity: ProcessIdentity
    let parent: Int32
}

/// The two questions asked of the process table and the one action taken on it. A seam so a
/// pid reuse, which no test can force on a real host, is still exercised.
struct ProcessTable: Sendable {
    /// The live process with this pid; nil when it is gone or already a zombie.
    var entry: @Sendable (Int32) -> ProcessEntry?
    /// Pids whose parent is `pid` right now.
    var children: @Sendable (Int32) -> [Int32]
    var signal: @Sendable (Int32, Int32) -> Void

    #if canImport(Darwin)
    static let system = ProcessTable(
        entry: { pid in
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
                  info.pbi_status != UInt32(SZOMB) else { return nil }
            return ProcessEntry(
                identity: ProcessIdentity(pid: pid, started: info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec),
                parent: Int32(bitPattern: info.pbi_ppid)
            )
        },
        children: { pid in
            var buffer = [pid_t](repeating: 0, count: 512)
            let count = proc_listchildpids(pid, &buffer, Int32(buffer.count * MemoryLayout<pid_t>.size))
            return Array(buffer.prefix(max(0, Int(count))))
        },
        signal: { pid, number in _ = kill(pid, number) }
    )
    #else
    // shortcut: no process table off Darwin, so a command's descendants outside its group stay
    // unreached there; the product ships on macOS only and Linux builds Core for the compile gate.
    static let system = ProcessTable(entry: { _ in nil }, children: { _ in [] }, signal: { _, _ in })
    #endif
}

/// What a command started, whatever process group or session each piece chose. A command's
/// group is killed on cancellation or timeout, but a tool that leaves the group (Xcode's
/// SWBBuildService runs every task in a group of its own) is not reached by that, and once its
/// parent dies it is adopted by launchd, so its lineage is gone. The lineage therefore has to
/// be read before the kill: `capture` freezes and records the tree, `settle` kills what it
/// recorded and waits for it to be gone.
///
/// Only descendants found through the parent chain of the command's own process, checked
/// against their start time. Never a sweep by path or name: that would reach a user's own
/// Xcode working in the same folder.
final class OwnedDescendants: @unchecked Sendable {
    /// Enough for a tool tree to settle (a fork racing the freeze shows up next pass) and short
    /// enough that a runaway fork loop cannot hold the cancellation.
    private static let capturePasses = 8
    /// SIGKILL is delivered in milliseconds on a healthy host. This is the margin for a loaded
    /// one, and still short enough that quitting does not look hung. Whatever outlives it is
    /// reported rather than waited for.
    static let settleLimit: Duration = .seconds(3)

    private let table: ProcessTable
    private let lock = NSLock()
    private var root: ProcessIdentity?
    private var owned: Set<ProcessIdentity> = []

    init(table: ProcessTable = .system) {
        self.table = table
    }

    /// Called once the command's own process exists. Its identity anchors every later lookup.
    func adopt(rootPID: Int32) {
        let identity = table.entry(rootPID)?.identity
        lock.withLock { root = identity }
    }

    /// Before the group is killed. A frozen process cannot fork, so the loop ends with every
    /// descendant held in place instead of racing a tool that is still starting its next one.
    func capture() {
        guard let root = lock.withLock({ root }) else { return }
        send(SIGSTOP, to: root)
        var frozen: Set<ProcessIdentity> = [root]
        for _ in 0..<Self.capturePasses {
            let found = descendants(of: root).subtracting(frozen)
            if found.isEmpty { break }
            for identity in found { send(SIGSTOP, to: identity) }
            frozen.formUnion(found)
        }
        // The command's own process is in the set so a group kill that did not land cannot
        // leave it stopped for good. Once reaped its pid no longer matches and it is skipped.
        lock.withLock { owned.formUnion(frozen) }
    }

    /// After the group is gone: kills everything captured that is still the same process and
    /// returns what outlived `limit`.
    func settle(limit: Duration = OwnedDescendants.settleLimit) async -> [ProcessIdentity] {
        var remaining = lock.withLock { owned }
        let deadline = ContinuousClock.now + limit
        while true {
            remaining = remaining.filter { table.entry($0.pid)?.identity == $0 }
            guard !remaining.isEmpty, ContinuousClock.now < deadline else { return remaining.sorted { $0.pid < $1.pid } }
            for identity in remaining { send(SIGKILL, to: identity) }
            // Not the caller's task: cancellation is why we are here, and a cancelled sleep
            // returns at once, which would turn this wait into a spin.
            await Task { try? await Task.sleep(for: .milliseconds(20)) }.value
        }
    }

    private func descendants(of root: ProcessIdentity) -> Set<ProcessIdentity> {
        guard let start = table.entry(root.pid), start.identity == root else { return [] }
        var found: Set<ProcessIdentity> = []
        var pending = [start.identity]
        while let parent = pending.popLast() {
            for pid in table.children(parent.pid) {
                // A child is younger than its parent and names it, or the pid was reused.
                guard let child = table.entry(pid), child.parent == parent.pid,
                      child.identity.started >= parent.started, found.insert(child.identity).inserted else { continue }
                pending.append(child.identity)
            }
        }
        return found
    }

    /// A signal checked against the identity just before it is sent. Between that check and
    /// the kill a pid can still be reused, which no platform interface here can close.
    private func send(_ number: Int32, to identity: ProcessIdentity) {
        guard table.entry(identity.pid)?.identity == identity else { return }
        table.signal(identity.pid, number)
    }
}

import Foundation
import Testing

@testable import Core

// A pid reuse cannot be forced on a real host, so the process table is a fake here.
@Suite("OwnedDescendants against a fake process table")
struct OwnedDescendantsTests {
    final class FakeTable: @unchecked Sendable {
        private let lock = NSLock()
        private var live: [Int32: ProcessEntry] = [:]
        private var sent: [(pid: Int32, signal: Int32)] = []
        /// Pids a SIGKILL does not remove, like a process stuck in an uninterruptible wait.
        var unkillable: Set<Int32> = []
        /// Runs after a SIGSTOP lands, outside the table's lock, to interleave with a capture in progress.
        var onStop: (@Sendable (Int32) -> Void)?

        func start(_ pid: Int32, at started: UInt64, parent: Int32) {
            lock.withLock { live[pid] = ProcessEntry(identity: ProcessIdentity(pid: pid, started: started), parent: parent) }
        }

        func exit(_ pid: Int32) { lock.withLock { _ = live.removeValue(forKey: pid) } }

        func signals(_ number: Int32) -> [Int32] { lock.withLock { sent.filter { $0.signal == number }.map(\.pid) } }

        var table: ProcessTable {
            ProcessTable(
                entry: { pid in self.lock.withLock { self.live[pid] } },
                children: { pid in self.lock.withLock { self.live.values.filter { $0.parent == pid }.map(\.identity.pid) } },
                signal: { pid, number in
                    self.lock.withLock {
                        self.sent.append((pid, number))
                        if number == SIGKILL, !self.unkillable.contains(pid) { self.live.removeValue(forKey: pid) }
                    }
                    if number == SIGSTOP { self.onStop?(pid) }
                }
            )
        }
    }

    @Test("a captured descendant that left the group is killed after the command is gone")
    func killsCapturedDescendant() async {
        let fake = FakeTable()
        fake.start(100, at: 10, parent: 1)
        fake.start(101, at: 20, parent: 100)
        let owned = OwnedDescendants(table: fake.table)
        owned.adopt(rootPID: 100)

        owned.capture()
        // Never the root: swift-subprocess traps when the process it waits on reports a stop.
        #expect(fake.signals(SIGSTOP) == [101])
        fake.exit(100) // the group kill reaches only the root

        #expect(await owned.settle(limit: .milliseconds(200)).isEmpty)
        #expect(fake.signals(SIGKILL) == [101])
    }

    @Test("a captured descendant that outlives the limit is reported instead of waited for")
    func reportsSurvivor() async {
        let fake = FakeTable()
        fake.start(100, at: 10, parent: 1)
        fake.start(101, at: 20, parent: 100)
        fake.unkillable = [101]
        let owned = OwnedDescendants(table: fake.table)
        owned.adopt(rootPID: 100)

        owned.capture()
        fake.exit(100)

        #expect(await owned.settle(limit: .milliseconds(100)) == [ProcessIdentity(pid: 101, started: 20)])
    }

    @Test("a command that exits while its tree is being frozen still has that tree settled")
    func settleWaitsForCaptureInProgress() async {
        final class Pending: @unchecked Sendable { var settle: Task<[ProcessIdentity], Never>? }
        let fake = FakeTable()
        fake.start(100, at: 10, parent: 1)
        fake.start(101, at: 20, parent: 100)
        let owned = OwnedDescendants(table: fake.table)
        owned.adopt(rootPID: 100)
        let pending = Pending()
        fake.onStop = { _ in
            // The command finishes on its own, so the runner settles while the freeze is still running.
            fake.exit(100)
            pending.settle = Task { await owned.settle(limit: .milliseconds(200)) }
            Thread.sleep(forTimeInterval: 0.05)
        }

        owned.capture()

        #expect(await pending.settle?.value == [])
        #expect(fake.signals(SIGKILL) == [101])
    }

    @Test("a pid reused by another process after capture is never signalled")
    func sparesReusedPID() async {
        let fake = FakeTable()
        fake.start(100, at: 10, parent: 1)
        fake.start(101, at: 20, parent: 100)
        let owned = OwnedDescendants(table: fake.table)
        owned.adopt(rootPID: 100)

        owned.capture()
        fake.exit(100)
        fake.exit(101)
        fake.start(101, at: 99, parent: 1) // a stranger now holds the captured pid

        #expect(await owned.settle(limit: .milliseconds(200)).isEmpty)
        #expect(fake.signals(SIGKILL).isEmpty)
    }

    @Test("a child older than its parent is a reused pid and is not captured")
    func skipsChildOlderThanParent() {
        let fake = FakeTable()
        fake.start(100, at: 10, parent: 1)
        fake.start(101, at: 5, parent: 100)
        let owned = OwnedDescendants(table: fake.table)
        owned.adopt(rootPID: 100)

        owned.capture()
        #expect(fake.signals(SIGSTOP).isEmpty)
    }
}

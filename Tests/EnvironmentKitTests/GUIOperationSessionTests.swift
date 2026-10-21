import EnvironmentKit
import Foundation
import Testing

@Suite("GUI operation cancellation completion boundary")
@MainActor
struct GUIOperationSessionTests {
    @Test("cancel does not close a task until its cleanup returns")
    func waitsForCleanup() async {
        let session = GUIOperationSession()
        let gate = SessionGate()
        var closeRequested = false
        #expect(session.start { await gate.wait() })
        await gate.entered()
        session.cancel { closeRequested = true }
        #expect(session.cancelling)
        #expect(session.task != nil)
        #expect(!closeRequested)
        #expect(!session.start {})
        await gate.release()
        await session.cancelAndWait()
        #expect(closeRequested)
        #expect(session.task == nil)
        #expect(!session.cancelling)
    }

    @Test("canceling one window preserves an independent active window")
    func independentWindows() async {
        let first = GUIOperationSession()
        let second = GUIOperationSession()
        let firstGate = SessionGate()
        let secondGate = SessionGate()
        first.start { await firstGate.wait() }
        second.start { await secondGate.wait() }
        await firstGate.entered()
        await secondGate.entered()
        first.cancel()
        await firstGate.release()
        await first.cancelAndWait()
        #expect(first.task == nil)
        #expect(second.task != nil)
        #expect(!second.cancelling)
        await secondGate.release()
        await second.cancelAndWait()
    }

    @Test("termination prevents new work and waits for every cancellation")
    func terminationBarrier() async {
        let first = GUIOperationSession()
        let second = GUIOperationSession()
        let gate = SessionGate()
        first.start { await gate.wait() }
        await gate.entered()
        [first, second].forEach { $0.stopAcceptingNewOperations() }
        #expect(!second.start {})
        var replied = false
        let shutdown = Task { @MainActor in
            await first.cancelAndWait()
            await second.cancelAndWait()
            replied = true
        }
        // The gate has not completed. Cancellation cannot fabricate cleanup completion.
        #expect(!replied)
        await gate.release()
        await shutdown.value
        #expect(replied)
        #expect(first.task == nil)
        #expect(second.task == nil)
    }
}

private actor SessionGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var didEnter = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            didEnter = true
            entryWaiters.forEach { $0.resume() }
            entryWaiters = []
        }
    }

    func entered() async {
        if didEnter { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

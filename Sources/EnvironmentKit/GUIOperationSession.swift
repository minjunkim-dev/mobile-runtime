import Foundation
import Observation

/// A window owns one task. Cancellation finishes only after its existing cleanup returns.
@MainActor @Observable
public final class GUIOperationSession {
    public private(set) var task: Task<Void, Never>?
    public private(set) var cancelling = false
    public private(set) var acceptsNewOperations = true
    @ObservationIgnored private var generation: UUID?
    @ObservationIgnored private var completions: [@MainActor () -> Void] = []

    public init() {}

    @discardableResult
    public func start(_ operation: @escaping @MainActor @Sendable () async -> Void) -> Bool {
        guard task == nil, acceptsNewOperations else { return false }
        let id = UUID()
        generation = id
        task = Task {
            await operation()
            guard generation == id else { return }
            task = nil
            generation = nil
            cancelling = false
            let callbacks = completions
            completions = []
            callbacks.forEach { $0() }
        }
        return true
    }

    public func cancel(after completion: (@MainActor () -> Void)? = nil) {
        guard let task else { completion?(); return }
        if let completion { completions.append(completion) }
        cancelling = true
        task.cancel()
    }

    public func stopAcceptingNewOperations() { acceptsNewOperations = false }

    public func cancelAndWait() async {
        await withCheckedContinuation { continuation in
            cancel { continuation.resume() }
        }
    }
}

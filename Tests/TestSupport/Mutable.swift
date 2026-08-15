import Foundation

/// A box for what a test has to watch from inside a `@Sendable` closure — whether a
/// check ran, what a writer was handed. Shared so the test targets keep one copy.
///
/// Locked, because the closures that write to it are not all on one task: `build`
/// prints its elapsed line from a ticker and its notable lines from the run itself,
/// and a test that counted both would otherwise be racing rather than asserting.
public final class Mutable<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    public var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }

    /// Read-modify-write in one step. `value.append(_:)` through the property above is
    /// a get and a set with a gap in between, and two tasks appending across that gap
    /// lose one of the two.
    public func mutate(_ change: (inout Value) -> Void) {
        lock.withLock { change(&stored) }
    }

    public init(_ value: Value) {
        self.stored = value
    }
}

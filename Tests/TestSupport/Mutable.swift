/// A box for what a test has to watch from inside a `@Sendable` closure — whether a
/// check ran, what a writer was handed. Shared so the test targets keep one copy.
public final class Mutable<Value: Sendable>: @unchecked Sendable {
    public var value: Value

    public init(_ value: Value) {
        self.value = value
    }
}

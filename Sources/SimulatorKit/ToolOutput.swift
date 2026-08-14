import Core
import Foundation

/// A tool could not be asked, or a Stage found the pipeline in a state it cannot
/// work from. Not a `DomainError`: nothing about the project is wrong, so it must
/// not land on the project's exit code.
struct ToolUnavailable: Error, CustomStringConvertible {
    let description: String
}

extension UpContext {
    /// What a Stage after `build` cannot work without. Reaching one of those without
    /// a device or a product is the pipeline run out of order — mobile's own bug, not
    /// the project's, so it must not land on the project's exit code.
    func built(for stage: String) throws -> (device: SelectedDevice, product: BuiltProduct) {
        guard let device, let product else {
            throw ToolUnavailable(
                description: "\(stage) ran before there was a device and a build — "
                    + "`device` and `build` come first"
            )
        }
        return (device, product)
    }
}

/// Reading raw tool output: the shapes every simctl/xcodebuild interpretation in
/// this target needs.
extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    var firstLine: String? {
        split(separator: "\n").first.map { String($0).trimmed }
    }
}

extension Array {
    /// The single element, or nil. "There is exactly one" is the shape half this
    /// target's decisions turn on — one workspace, one project, one `.app` — and
    /// `count == 1 ? self[0] : nil` written out each time reads like an index bug
    /// waiting to happen.
    var only: Element? { count == 1 ? self[0] : nil }
}

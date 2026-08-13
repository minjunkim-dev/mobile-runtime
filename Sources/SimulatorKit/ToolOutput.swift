import Foundation

/// Reading raw tool output: the two shapes every simctl/xcodebuild interpretation
/// in this target needs.
extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    var firstLine: String? {
        split(separator: "\n").first.map { String($0).trimmed }
    }
}

import Foundation

/// A version as tools actually print it. Prerelease and build metadata are parsed
/// off and dropped — no verdict in doctor turns on them.
public struct SemanticVersion: Sendable, Equatable, Comparable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int = 0, patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Accepts `v20.11.1`, `3.6.4+sha224.…`, `1.0.0-rc.1` and partials like `18`.
    public init?(_ text: String) {
        guard let components = VersionComponents(text), let first = components.values.first else { return nil }
        self.init(
            major: first,
            minor: components.values.count > 1 ? components.values[1] : 0,
            patch: components.values.count > 2 ? components.values[2] : 0
        )
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

/// A pin from `.nvmrc` and friends. Matching is by prefix: `20` covers every 20.x.
public struct VersionPin: Sendable, Equatable {
    private let components: [Int]

    public init?(_ text: String) {
        guard let parsed = VersionComponents(text) else { return nil }
        components = parsed.values
    }

    public func matches(_ version: SemanticVersion) -> Bool {
        zip(components, [version.major, version.minor, version.patch]).allSatisfy(==)
    }
}

/// A Tier 2 requirement value, written at whatever precision the source used:
/// `"26"` reads as 26.0, `"16.1"` as 16.1, and anything from there up satisfies it.
/// Matrix rows and `mobile.yml` overrides share this one comparator — there is no
/// second way to state a tool version requirement.
///
/// A floor, not a prefix match: every value the matrix carries is a minimum, and a
/// prefix match would fail Xcode 26 against a `16.1` requirement. Written to a
/// major only, `"26"` therefore also accepts 27 — an override saying "26 works
/// here" is a statement about the floor, not a ceiling.
public struct MinimumVersion: Sendable, Equatable, Decodable, CustomStringConvertible {
    /// As written in the source, so `required:` can quote it back verbatim.
    public let text: String
    private let floor: SemanticVersion

    public init?(_ text: String) {
        guard let components = VersionComponents(text) else { return nil }
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.floor = components.lowerBound
    }

    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = MinimumVersion(text) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "`\(text)` is not a version")
            )
        }
        self = parsed
    }

    public func isSatisfied(by version: SemanticVersion) -> Bool { version >= floor }

    /// Two requirements agree when they demand the same thing: `"26"` and `"26.0"`
    /// are not a disagreement worth reporting.
    public func agrees(with other: MinimumVersion) -> Bool { floor == other.floor }

    /// The stricter of two requirements, for composing a matrix floor with what the
    /// project declared. Precision is not strictness: `"26"` does not exceed `"26.0"`.
    public func exceeds(_ other: MinimumVersion) -> Bool { floor > other.floor }

    public var description: String { text }
}

/// The subset of npm range syntax that appears in `engines`: comparators, `^`, `~`,
/// x-ranges, whitespace as AND and `||` as OR. Anything else fails to parse on
/// purpose — the caller answers `unknown` rather than guessing a pass.
public struct VersionRange: Sendable {
    private let alternatives: [[Comparator]]

    public init?(_ text: String) {
        var alternatives: [[Comparator]] = []
        for clause in text.components(separatedBy: "||") {
            guard let comparators = Self.parse(clause) else { return nil }
            alternatives.append(comparators)
        }
        guard !alternatives.isEmpty else { return nil }
        self.alternatives = alternatives
    }

    public func contains(_ version: SemanticVersion) -> Bool {
        alternatives.contains { $0.allSatisfy { $0.satisfied(by: version) } }
    }

    private static func parse(_ clause: String) -> [Comparator]? {
        // `>= 18` is one token wearing a space: an operator on its own joins the
        // version that follows it.
        var tokens: [String] = []
        var pendingOperator = ""
        for piece in clause.split(whereSeparator: \.isWhitespace).map(String.init) {
            if piece.allSatisfy(Comparator.isOperatorCharacter) {
                pendingOperator += piece
                continue
            }
            tokens.append(pendingOperator + piece)
            pendingOperator = ""
        }
        guard pendingOperator.isEmpty, !tokens.isEmpty else { return nil }

        var comparators: [Comparator] = []
        for token in tokens {
            guard let parsed = Comparator.parse(token) else { return nil }
            comparators.append(contentsOf: parsed)
        }
        return comparators
    }
}

struct Comparator: Sendable {
    enum Relation: Sendable {
        case atLeast, greaterThan, atMost, lessThan, exactly
    }

    let relation: Relation
    let version: SemanticVersion

    static func isOperatorCharacter(_ character: Character) -> Bool {
        "><=^~".contains(character)
    }

    func satisfied(by candidate: SemanticVersion) -> Bool {
        switch relation {
        case .atLeast: candidate >= version
        case .greaterThan: candidate > version
        case .atMost: candidate <= version
        case .lessThan: candidate < version
        case .exactly: candidate == version
        }
    }

    /// One token expands to zero comparators (a wildcard), one, or the two bounds
    /// of a `^`/`~`/x-range.
    static func parse(_ token: String) -> [Comparator]? {
        if token == "*" || token.lowercased() == "x" { return [] }

        let symbol = String(token.prefix(while: isOperatorCharacter))
        let rest = String(token.dropFirst(symbol.count))
        guard let components = VersionComponents(rest) else { return nil }
        let lower = components.lowerBound

        switch symbol {
        case ">=": return [Comparator(relation: .atLeast, version: lower)]
        case ">": return [Comparator(relation: .greaterThan, version: lower)]
        case "<=": return [Comparator(relation: .atMost, version: lower)]
        case "<": return [Comparator(relation: .lessThan, version: lower)]
        case "^": return bounded(lower, components.caretUpperBound)
        case "~": return bounded(lower, components.tildeUpperBound)
        case "", "=":
            // A bare `18` means 18.x; a full `18.2.1` means exactly that.
            guard let upper = components.xRangeUpperBound else {
                return [Comparator(relation: .exactly, version: lower)]
            }
            return bounded(lower, upper)
        default: return nil
        }
    }

    private static func bounded(_ lower: SemanticVersion, _ upper: SemanticVersion) -> [Comparator] {
        [
            Comparator(relation: .atLeast, version: lower),
            Comparator(relation: .lessThan, version: upper),
        ]
    }
}

/// The 1–3 numbers a version string actually carries. How many there are decides
/// what `^`, `~` and an x-range mean, so the count is kept rather than padded away.
struct VersionComponents {
    let values: [Int]

    init?(_ text: String) {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("v") || value.hasPrefix("V") { value.removeFirst() }
        value = String(value.prefix { $0 != "+" && $0 != "-" })
        guard !value.isEmpty else { return nil }

        var values: [Int] = []
        for part in value.split(separator: ".", omittingEmptySubsequences: false) {
            // `18.x` says "precision ends here", so the rest is dropped.
            if part == "x" || part == "X" || part == "*" { break }
            guard let number = Int(part), number >= 0 else { return nil }
            values.append(number)
        }
        guard (1...3).contains(values.count) else { return nil }
        self.values = values
    }

    var lowerBound: SemanticVersion {
        SemanticVersion(
            major: values[0],
            minor: values.count > 1 ? values[1] : 0,
            patch: values.count > 2 ? values[2] : 0
        )
    }

    /// `^` allows changes that leave the left-most non-zero component alone.
    var caretUpperBound: SemanticVersion {
        if values[0] != 0 { return SemanticVersion(major: values[0] + 1) }
        if values.count == 1 { return SemanticVersion(major: 1) }
        if values[1] != 0 { return SemanticVersion(major: 0, minor: values[1] + 1) }
        if values.count == 2 { return SemanticVersion(major: 0, minor: 1) }
        return SemanticVersion(major: 0, minor: 0, patch: values[2] + 1)
    }

    /// `~` allows patch moves once a minor is named, minor moves otherwise.
    var tildeUpperBound: SemanticVersion {
        values.count == 1
            ? SemanticVersion(major: values[0] + 1)
            : SemanticVersion(major: values[0], minor: values[1] + 1)
    }

    /// nil when the version is fully specified — then it is an equality, not a range.
    var xRangeUpperBound: SemanticVersion? {
        switch values.count {
        case 1: SemanticVersion(major: values[0] + 1)
        case 2: SemanticVersion(major: values[0], minor: values[1] + 1)
        default: nil
        }
    }
}

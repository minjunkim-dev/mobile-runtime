import Foundation

/// What the project's gem files ask of CocoaPods, and which file asked. The two
/// questions are separate (ADR-0004): `Gemfile.lock` settles *which version*, and a
/// `Gemfile` naming the gem already settles *whether it must be installed*. Reading
/// only the lock made the Check vanish on a repo that had not committed one — the
/// silence `unknown` exists to prevent.
///
/// The requirement is what picks the grade when `pod` cannot be measured. The reason
/// a measurement failed does not: an unusable tool the project needs is an error
/// whether it is absent or merely mute.
public struct CocoaPodsRequirement: Sendable, Equatable {
    public enum Level: Sendable, Equatable {
        /// `Gemfile.lock` pins a version: both being installed and being that version.
        case version(String)
        /// A gem file declares the gem but nothing pins it — installed is the whole ask.
        case installed
        /// Gem files exist, none of them names CocoaPods. Nothing is required, so a
        /// `pod` that cannot answer is `unknown` rather than a fault.
        case unconfirmed
    }

    public let level: Level
    /// The file the requirement was read from, as a verdict has to name it.
    public let file: String

    public init(level: Level, file: String) {
        self.level = level
        self.file = file
    }

    static let lockFile = "Gemfile.lock"
    static let gemfile = "Gemfile"

    /// nil when the project manages no gems at all — then there is no CocoaPods Check,
    /// which is absence rather than a verdict.
    static func resolve(anchorDirectory: String, fileManager: FileManager) -> CocoaPodsRequirement? {
        func contents(_ file: String) -> String? {
            fileManager.contents(atPath: anchorDirectory.appending("/\(file)")).map {
                String(decoding: $0, as: UTF8.self)
            }
        }

        let lock = contents(lockFile)
        let gemfileText = contents(gemfile)
        guard lock != nil || gemfileText != nil else { return nil }

        // The lock is the stronger ask: it settles the version as well as the
        // existence, and a Gemfile that also names the gem adds nothing to that.
        if let locked = lock.flatMap(lockedVersion) {
            return CocoaPodsRequirement(level: .version(locked), file: lockFile)
        }
        if gemfileText.map(declaresCocoaPods) == true {
            return CocoaPodsRequirement(level: .installed, file: gemfile)
        }
        return CocoaPodsRequirement(level: .unconfirmed, file: lock != nil ? lockFile : gemfile)
    }

    private static let lockedPrefix = "    cocoapods ("

    /// Reads the version out of the `specs:` section, not the `DEPENDENCIES` one:
    /// both name cocoapods, and the four-space indent is what tells the locked
    /// version apart from the range the Gemfile asked for. `cocoapods-core` fails the
    /// prefix, as it should.
    private static func lockedVersion(in lock: String) -> String? {
        lock.split(separator: "\n")
            .first { $0.hasPrefix(lockedPrefix) && $0.hasSuffix(")") }
            .map { String($0.dropFirst(lockedPrefix.count).dropLast()) }
    }

    /// `gem 'cocoapods'`, in either quote style, however it is spaced and whatever
    /// version range follows. The name is compared whole, so `gem 'cocoapods-core'` —
    /// a different gem — does not count.
    private static func declaresCocoaPods(in gemfile: String) -> Bool {
        gemfile.split(separator: "\n").contains { line in
            let words = line.split(whereSeparator: \.isWhitespace)
            guard words.count > 1, words[0] == "gem" else { return false }
            return words[1].trimmingCharacters(in: CharacterSet(charactersIn: "'\",")) == "cocoapods"
        }
    }
}

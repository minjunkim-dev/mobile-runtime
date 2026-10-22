import Core
import CryptoKit
import Foundation

/// Snapshot the chosen bytes, not their producer's trustworthiness. No contained code runs.
enum AppFileSnapshot {
    static func read(_ url: URL) throws -> (identity: AppFileIdentity, digest: String) {
        let identity = try AppFileIdentity(url: url)
        let root = URL(fileURLWithPath: identity.path)
        let attributes = try FileManager.default.attributesOfItem(atPath: root.path)
        let kind = attributes[.type] as? FileAttributeType
        guard root.pathExtension == "app" && kind == .typeDirectory
                || root.pathExtension == "apk" && kind == .typeRegular else {
            throw failure("Choose an iOS Simulator or Development/Ad Hoc device .app directory or one Android .apk file. IPA, AAB, split bundles and archives are excluded here.")
        }
        var hash = SHA256()
        var members = [root]
        if kind == .typeDirectory {
            var readError: (any Error)?
            guard let enumerator = FileManager.default.enumerator(at: root,
                includingPropertiesForKeys: [.isSymbolicLinkKey], errorHandler: { _, error in readError = error; return false }) else {
                throw failure("The .app directory cannot be read completely.")
            }
            for case let member as URL in enumerator {
                guard members.count < 200_000 else { throw failure("The .app exceeds the inspection member limit.") }
                // Foundation can enumerate /private/var while the root uses /var. Resolve
                // only the parent: the final member must remain a link when it is a link.
                let canonicalMember = member.deletingLastPathComponent().resolvingSymlinksInPath()
                    .appendingPathComponent(member.lastPathComponent, isDirectory: false)
                guard canonicalMember.path.hasPrefix(root.path + "/") else {
                    throw failure("The .app member is outside its inspected root.")
                }
                members.append(canonicalMember)
            }
            if let readError { throw readError }
        }
        for member in members.sorted(by: { $0.path < $1.path }) {
            try Task.checkCancellation()
            let relative = member == root ? "." : String(member.path.dropFirst(root.path.count + 1))
            let values = try FileManager.default.attributesOfItem(atPath: member.path)
            let mode = (values[.posixPermissions] as? NSNumber)?.stringValue ?? "unknown"
            switch values[.type] as? FileAttributeType {
            case .typeDirectory:
                hash.update(data: Data("directory\u{0}\(relative)\u{0}\(mode)\u{0}".utf8))
            case .typeSymbolicLink:
                let target = member.resolvingSymlinksInPath()
                guard target.path.hasPrefix(root.path + "/"), FileManager.default.fileExists(atPath: target.path) else {
                    throw failure("The .app contains an escaping or dangling symbolic link: \(relative)")
                }
                let destination = try FileManager.default.destinationOfSymbolicLink(atPath: member.path)
                // Absolute links would still address the original after staging the input.
                guard !destination.hasPrefix("/") else { throw failure("The .app contains an absolute symbolic link: \(relative)") }
                hash.update(data: Data("link\u{0}\(relative)\u{0}\(destination)\u{0}".utf8))
            case .typeRegular:
                if kind == .typeDirectory {
                    hash.update(data: Data("file\u{0}\(relative)\u{0}\(mode)\u{0}\((values[.size] as? NSNumber)?.stringValue ?? "unknown")\u{0}".utf8))
                }
                let input = try FileHandle(forReadingFrom: member)
                defer { try? input.close() }
                while let block = try input.read(upToCount: 65_536), !block.isEmpty {
                    try Task.checkCancellation()
                    hash.update(data: block)
                }
            default:
                throw failure("The app input contains an unsupported special file: \(relative)")
            }
        }
        guard try AppFileIdentity(url: root) == identity else { throw failure("The app file changed during inspection. Inspect it again.") }
        return (identity, hash.finalize().map { String(format: "%02x", $0) }.joined())
    }

    static func digest(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return SHA256.hash(data: try encoder.encode(value)).map { String(format: "%02x", $0) }.joined()
    }

    static func failure(_ summary: String) -> DomainError {
        DomainError(summary: summary, remediation: Remediation(summary: "Choose a supported app file, inspect its current state and approve the current plan again. The original file and existing app data are preserved."))
    }
}

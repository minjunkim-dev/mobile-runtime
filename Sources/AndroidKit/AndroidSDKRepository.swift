import Core
import CryptoKit
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// A single official schema-3 observation. Selection never falls back to an older schema.
public struct AndroidSDKRepository: Sendable {
    public static let url = URL(string: "https://dl.google.com/android/repository/repository2-3.xml")!
    public static var command: ProcessCommand {
        ProcessCommand("curl", ["--fail", "--silent", "--show-error", "--proto", "=https", "--max-time", "30", url.absoluteString], timeout: .seconds(40))
    }
    public let sha256: String
    private let packages: [AndroidSDKRepositoryPackage]

    public init(data: Data) throws {
        guard data.count <= 4 * 1024 * 1024,
              let text = String(data: data, encoding: .utf8),
              !text.localizedCaseInsensitiveContains("<!DOCTYPE"),
              !text.localizedCaseInsensitiveContains("<!ENTITY") else { throw Self.invalid("Unsafe or oversized repository metadata") }
        let delegate = SDKRepositoryXML()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), let root = delegate.root,
              root.attributes["xmlns:sdk"] == "http://schemas.android.com/sdk/android/repo/repository2/03" else {
            throw Self.invalid("The official schema-3 repository could not be parsed")
        }
        sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let licenses = root.children.filter { $0.localName == "license" }
        var values: [AndroidSDKRepositoryPackage] = []
        for node in root.children where node.localName == "remotePackage" {
            guard node.child("channelRef")?.attributes["ref"] == "channel-0",
                  node.attributes["obsolete"] != "true",
                  let path = node.attributes["path"], Self.safePackagePath(path),
                  let revisionNode = node.child("revision"), revisionNode.child("preview") == nil,
                  let major = revisionNode.child("major")?.value, Int(major) != nil,
                  let licenseID = node.child("uses-license")?.attributes["ref"],
                  licenseID.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil,
                  licenses.filter({ $0.attributes["id"] == licenseID }).count == 1,
                  let license = licenses.first(where: { $0.attributes["id"] == licenseID }) else { continue }
            let parts = [major, revisionNode.child("minor")?.value, revisionNode.child("micro")?.value].compactMap { $0 }
            guard parts.allSatisfy({ Int($0) != nil }) else { continue }
            let revision = parts.joined(separator: ".")
            let archives = node.child("archives")?.children.filter {
                ($0.child("host-os") == nil || $0.child("host-os")?.value == "macosx")
                    && ($0.child("host-arch") == nil || ["aarch64", "arm64"].contains($0.child("host-arch")?.value ?? ""))
                    && ($0.child("host-bits") == nil || $0.child("host-bits")?.value == "64")
            } ?? []
            guard archives.count == 1, let complete = archives[0].child("complete"),
                  let size = complete.child("size").flatMap({ Int64($0.value) }), size > 0,
                  let checksum = complete.child("checksum"), checksum.attributes["type"] == "sha1",
                  checksum.value.range(of: #"^[0-9a-f]{40}$"#, options: .regularExpression) != nil,
                  let filename = complete.child("url")?.value,
                  filename.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*\.zip$"#, options: .regularExpression) != nil else { continue }
            // Schema 3 distinguishes base platforms from extension platforms with different paths.
            if path.hasPrefix("platforms;") {
                guard let details = node.child("type-details"), let api = details.child("api-level")?.value else { continue }
                let base = details.child("base-extension")?.value == "true"
                let expected = base || details.child("extension-level") == nil
                    ? "platforms;android-\(api)"
                    : "platforms;android-\(api)-ext\(details.child("extension-level")!.value)"
                guard path == expected else { continue }
            }
            let local = SDKRepositoryNode(name: "localPackage", attributes: ["path": path], children:
                node.children.filter { ["type-details", "revision", "display-name", "uses-license"].contains($0.localName) })
            let document = SDKRepositoryNode(name: "common:repository", attributes: root.attributes, children: [license, local]).xml
            values.append(AndroidSDKRepositoryPackage(packagePath: path, revision: revision,
                archiveURL: Self.url.deletingLastPathComponent().appendingPathComponent(filename),
                size: size, sha1: checksum.value, licenseID: licenseID,
                licenseSHA1: Insecure.SHA1.hash(data: Data(AndroidSDKLicenses.normalizedText(license.text).utf8)).map { String(format: "%02x", $0) }.joined(),
                localMetadata: Data(document.utf8)))
        }
        packages = values
    }

    public func package(_ path: String) throws -> AndroidSDKRepositoryPackage {
        let matching = packages.filter { $0.packagePath == path }
        guard matching.count == 1 else { throw Self.invalid("No single stable macOS arm64 archive identifies \(path)") }
        return matching[0]
    }

    private static func safePackagePath(_ path: String) -> Bool {
        path.split(separator: ";", omittingEmptySubsequences: false).allSatisfy {
            $0.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil && $0 != ".."
        }
    }

    private static func invalid(_ message: String) -> DomainError {
        DomainError(summary: message, remediation: Remediation(summary: "Inspect the official repository metadata and re-plan. No package was installed."))
    }
}

public struct AndroidSDKRepositoryPackage: Sendable {
    public let packagePath: String
    public let revision: String
    public let archiveURL: URL
    public let size: Int64
    public let sha1: String
    public let licenseID: String
    public let licenseSHA1: String
    public let localMetadata: Data

    public func licenseAccepted(in sdk: URL) -> Bool {
        let record = sdk.appendingPathComponent("licenses").appendingPathComponent(licenseID)
        guard let text = try? String(contentsOf: record, encoding: .utf8) else { return false }
        return text.split(whereSeparator: \.isNewline).contains(Substring(licenseSHA1))
    }
}

private final class SDKRepositoryNode {
    let name: String
    let attributes: [String: String]
    var children: [SDKRepositoryNode]
    var text = ""
    init(name: String, attributes: [String: String], children: [SDKRepositoryNode] = []) {
        self.name = name; self.attributes = attributes; self.children = children
    }
    var localName: String { name.split(separator: ":").last.map(String.init) ?? name }
    var value: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    func child(_ name: String) -> SDKRepositoryNode? { children.first { $0.localName == name } }
    var xml: String {
        let attributes = attributes.sorted { $0.key < $1.key }.map { " \($0.key)=\"\(Self.escape($0.value))\"" }.joined()
        return "<\(name)\(attributes)>\(Self.escape(text))\(children.map(\.xml).joined())</\(name)>"
    }
    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}

private final class SDKRepositoryXML: NSObject, XMLParserDelegate {
    var root: SDKRepositoryNode?
    private var stack: [SDKRepositoryNode] = []
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        let node = SDKRepositoryNode(name: name, attributes: attributes)
        if let parent = stack.last { parent.children.append(node) } else { root = node }
        stack.append(node)
    }
    func parser(_ parser: XMLParser, foundCharacters text: String) { stack.last?.text += text }
    func parser(_ parser: XMLParser, foundCDATA data: Data) { stack.last?.text += String(decoding: data, as: UTF8.self) }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) { _ = stack.popLast() }
}

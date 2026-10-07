import Core
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Mirrors Android repository License.checkAccepted: exact text SHA-1 in licenses/<id>.
/// No sdkmanager invocation, network request, license acceptance, or SDK modification.
enum AndroidSDKLicenses {
    static func check(packages: [URL], sdk: URL, command: String?) -> CheckOutcome? {
        var unresolved: [String] = []
        var unaccepted: [String] = []
        for package in packages {
            let metadata = package.appendingPathComponent("package.xml")
            guard let data = try? Data(contentsOf: metadata), data.count <= 2 * 1024 * 1024,
                !String(decoding: data, as: UTF8.self).contains("<!DOCTYPE")
            else { unresolved.append(metadata.path); continue }
            let document = SDKLicenseDocument()
            let parser = XMLParser(data: data)
            parser.shouldResolveExternalEntities = false
            parser.delegate = document
            guard parser.parse(), document.hasPackage, !document.invalid else { unresolved.append(metadata.path); continue }
            for reference in document.references {
                guard reference.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil,
                    let text = document.licenses[reference]
                else { unresolved.append(metadata.path); continue }
                #if canImport(CryptoKit)
                let hash = Insecure.SHA1.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
                let record = sdk.appendingPathComponent("licenses").appendingPathComponent(reference)
                do {
                    let accepted = try String(contentsOf: record, encoding: .utf8)
                    if !accepted.split(whereSeparator: \.isNewline).contains(Substring(hash)) {
                        unaccepted.append(record.path)
                    }
                } catch {
                    if (error as NSError).domain == NSCocoaErrorDomain,
                        (error as NSError).code == NSFileReadNoSuchFileError {
                        unaccepted.append(record.path)
                    } else {
                        unresolved.append(record.path)
                    }
                }
                #else
                unresolved.append("license hash verification unavailable on this host")
                #endif
            }
        }
        if !unaccepted.isEmpty {
            return .error(
                observed: "SDK root \(sdk.path); license acceptance missing: \(Set(unaccepted).sorted().joined(separator: ", "))",
                required: "accepted licenses for the selected SDK packages",
                source: CheckSource(tier: 1, origin: "selected package.xml + SDK licenses records"),
                remediation: Remediation(
                    summary: "Review and accept the selected SDK's licenses in Android Studio or run the shown SDK Manager command. mobile never accepts licenses for you.",
                    command: command,
                    url: "https://developer.android.com/tools/sdkmanager#accept-licenses"
                )
            )
        }
        if !unresolved.isEmpty {
            return .unknown(
                reason: "SDK license metadata or records could not be verified: \(Set(unresolved).sorted().joined(separator: ", ")). Restore read access to these files and review licenses in Android Studio, then run mobile doctor again.",
                source: CheckSource(tier: 1, origin: "selected package.xml + SDK licenses records")
            )
        }
        return nil
    }
}

private final class SDKLicenseDocument: NSObject, XMLParserDelegate {
    var licenses: [String: String] = [:]
    var references: [String] = []
    var hasPackage = false
    var invalid = false
    private var licenseID: String?
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        let local = name.split(separator: ":").last.map(String.init) ?? name
        if local == "localPackage" { hasPackage = true }
        if local == "uses-license" {
            if let reference = attributes["ref"], !reference.isEmpty { references.append(reference) }
            else { invalid = true }
        }
        if local == "license" {
            licenseID = attributes["id"]
            text = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if licenseID != nil { text += string }
    }

    func parser(_ parser: XMLParser, foundCDATA data: Data) {
        if licenseID != nil { text += String(decoding: data, as: UTF8.self) }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name.split(separator: ":").last == "license", let id = licenseID {
            if licenses[id] != nil { invalid = true }
            licenses[id] = text
            licenseID = nil
        }
    }
}

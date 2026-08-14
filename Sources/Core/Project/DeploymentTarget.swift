import Foundation

/// The lowest iOS the project was built to run on, and the file that said so.
/// ADR-0003's second evidence chain: `ios/Podfile.properties.json` → the Podfile's
/// own `platform :ios` literal → nothing.
///
/// The matrix carries what a React Native version needs; only the repo knows what
/// this app targets, and it is routinely higher. Without this a project asking for
/// iOS 16.4 passes on a host with 15.x runtimes and then fails to install — the
/// miss #23 reports.
///
/// `project.pbxproj` is deliberately not read: its `IPHONEOS_DEPLOYMENT_TARGET`
/// differs per target (joplin 15.6/18.6, rainbow 15.1/17.5), so knowing which value
/// is the app's needs a scheme — and ADR-0004 lets that choice stay unresolved.
/// An ambiguous source must not be what raises a grade.
public struct DeploymentTarget: Sendable, Equatable {
    public let value: String
    /// Anchor-relative, because that is how a verdict has to name it.
    public let file: String

    public init(value: String, file: String) {
        self.value = value
        self.file = file
    }

    private static let propertiesFile = "ios/Podfile.properties.json"
    private static let podfile = "ios/Podfile"
    /// The key the Podfile itself reads before it reaches its own literal.
    private static let propertiesKey = "deploymentTarget"

    static func resolve(anchorDirectory: String, fileManager: FileManager) -> DeploymentTarget? {
        func contents(_ file: String) -> Data? {
            fileManager.contents(atPath: anchorDirectory.appending("/\(file)"))
        }

        let platform: (key: String?, literal: String?) =
            contents(podfile).map { platformLine(in: String(decoding: $0, as: UTF8.self)) } ?? (nil, nil)

        // The properties file existing is not the same as the target being in it —
        // joplin ships one that only sets `newArchEnabled`, and its target lives in
        // the Podfile literal below.
        if let data = contents(propertiesFile),
            let properties = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let declared = properties[platform.key ?? propertiesKey]
        {
            // JSON has numbers, and a hand-edited file uses them. Anything else — an
            // object, an array — is not a version and falls through to the literal.
            switch declared {
            case let text as String: return DeploymentTarget(value: text, file: propertiesFile)
            case let number as NSNumber: return DeploymentTarget(value: "\(number)", file: propertiesFile)
            default: break
            }
        }
        guard let literal = platform.literal else { return nil }
        return DeploymentTarget(value: literal, file: podfile)
    }

    /// What the `platform :ios` line says: the properties key it consults, if any, and
    /// its own version literal. Real Podfiles write it three ways —
    /// `platform :ios, '15.1'`, `platform :ios, podfile_properties['…'] || '16.4'`, and
    /// `platform :ios, min_ios_version_supported`. The third has neither, and yields
    /// nothing rather than a guess: CocoaPods resolves that one, and mobile runs no Ruby.
    ///
    /// The key is read from the line rather than fixed, because the Podfile is what
    /// decides it — mattermost-mobile reads `deploymentTarget`, an Expo-generated one
    /// reads `ios.deploymentTarget`, and looking up the wrong key silently lands on the
    /// fallback literal, which is always the lower of the two.
    private static func platformLine(in podfile: String) -> (key: String?, literal: String?) {
        guard
            let line = podfile.split(separator: "\n").first(where: {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("platform :ios")
            })
        else { return (nil, nil) }

        // Quoted runs are the only things that matter, and an unquoted `#` ends the
        // line — a version inside a trailing comment is not a declaration, and
        // believing it would raise the requirement on no evidence.
        var quoted: [String] = []
        var current = ""
        var insideQuotes = false
        for character in line {
            if character == "'" || character == "\"" {
                if insideQuotes { quoted.append(current) }
                current = ""
                insideQuotes.toggle()
            } else if !insideQuotes && character == "#" {
                break
            } else if insideQuotes {
                current.append(character)
            }
        }
        return (
            key: quoted.first { SemanticVersion($0) == nil },
            literal: quoted.last { SemanticVersion($0) != nil }
        )
    }
}

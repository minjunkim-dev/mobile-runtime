import Core
import Foundation

/// Shape of `xcrun simctl list runtimes -j` — the fields two Checks read, not the
/// whole document.
struct SimctlRuntimeList: Decodable {
    struct Runtime: Decodable {
        struct SupportedDeviceType: Decodable {
            let identifier: String
        }

        let identifier: String
        let name: String
        let version: String
        let buildversion: String?
        let supportedArchitectures: [String]?
        let supportedDeviceTypes: [SupportedDeviceType]?
        /// A runtime is a system-wide cryptex image, so this flips to false on its
        /// own after a macOS update. Filtering on it is not optional.
        let isAvailable: Bool

        private enum CodingKeys: String, CodingKey {
            case identifier, name, version, buildversion, supportedArchitectures, supportedDeviceTypes, isAvailable
        }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            identifier = try values.decode(String.self, forKey: .identifier)
            name = try values.decode(String.self, forKey: .name)
            version = try values.decode(String.self, forKey: .version)
            buildversion = try values.decodeIfPresent(String.self, forKey: .buildversion)
            supportedArchitectures = try values.decodeIfPresent([String].self, forKey: .supportedArchitectures)
            isAvailable = try values.decode(Bool.self, forKey: .isAvailable)
            // Unknown creation compatibility must not hide an available runtime
            // or an existing device from the read-only checks and reuse path.
            supportedDeviceTypes = try? values.decode([SupportedDeviceType].self, forKey: .supportedDeviceTypes)
        }

        /// The identifier is the discriminator rather than the `platform` field:
        /// it is the one key every simctl vintage prints.
        var isIOS: Bool { identifier.contains("SimRuntime.iOS") }
    }

    let runtimes: [Runtime]

    /// One command line, so a Check that changes it cannot drift from the one the
    /// other Check pinned `DEVELOPER_DIR` on.
    static func command(environment: [String: String]) -> ProcessCommand {
        ProcessCommand(
            "xcrun", ["simctl", "list", "runtimes", "-j"],
            environment: environment,
            timeout: .seconds(60)
        )
    }

    /// - Returns: nil when simctl answered with something that is not a runtime list.
    static func decode(_ standardOutput: String) -> SimctlRuntimeList? {
        try? JSONDecoder().decode(SimctlRuntimeList.self, from: Data(standardOutput.utf8))
    }
}

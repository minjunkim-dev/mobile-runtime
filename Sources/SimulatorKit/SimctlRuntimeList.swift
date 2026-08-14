import Core
import Foundation

/// Shape of `xcrun simctl list runtimes -j` — the fields two Checks read, not the
/// whole document.
struct SimctlRuntimeList: Decodable {
    struct Runtime: Decodable {
        let identifier: String
        let name: String
        let version: String
        /// A runtime is a system-wide cryptex image, so this flips to false on its
        /// own after a macOS update. Filtering on it is not optional.
        let isAvailable: Bool

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

import Core
import Foundation

/// Shape of `xcrun simctl list devices -j` — the fields `config.values` reads.
/// Devices are keyed by runtime, which is what makes "the same name on two
/// runtimes" a question that has to be answered rather than assumed away.
struct SimctlDeviceList: Decodable {
    struct Device: Decodable {
        let name: String
        /// False for a device whose runtime the system unmounted. It is still
        /// listed, and it still cannot be booted.
        let isAvailable: Bool
    }

    /// Runtime identifier → the devices on it.
    let devices: [String: [Device]]

    /// A device the project could actually name, paired with the runtime it sits on.
    struct Simulator {
        let name: String
        /// For ordering — `"9.0"` sorts above `"26.5"` as text.
        let runtime: SemanticVersion
        /// As the runtime writes it, so a report says `iOS 18.2` and not `18.2.0`.
        let runtimeText: String
        let isAvailable: Bool
    }

    static func command(environment: [String: String]) -> ProcessCommand {
        ProcessCommand(
            "xcrun", ["simctl", "list", "devices", "-j"],
            environment: environment,
            timeout: .seconds(60)
        )
    }

    /// - Returns: nil when simctl answered with something that is not a device list.
    static func decode(_ standardOutput: String) -> SimctlDeviceList? {
        try? JSONDecoder().decode(SimctlDeviceList.self, from: Data(standardOutput.utf8))
    }

    /// iOS devices only, flattened. Android will not arrive through simctl.
    var simulators: [Simulator] {
        devices.flatMap { identifier, devices -> [Simulator] in
            guard let text = Self.iOSVersionText(of: identifier), let runtime = SemanticVersion(text) else {
                return []
            }
            return devices.map {
                Simulator(name: $0.name, runtime: runtime, runtimeText: text, isAvailable: $0.isAvailable)
            }
        }
    }

    /// `…SimRuntime.iOS-18-2` → `"18.2"`. The identifier is the discriminator rather
    /// than a `platform` field: it is the one key every simctl vintage prints.
    private static func iOSVersionText(of runtimeIdentifier: String) -> String? {
        guard let marker = runtimeIdentifier.range(of: "SimRuntime.iOS-") else { return nil }
        return runtimeIdentifier[marker.upperBound...].replacingOccurrences(of: "-", with: ".")
    }
}

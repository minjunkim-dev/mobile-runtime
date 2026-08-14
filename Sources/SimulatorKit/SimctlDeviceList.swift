import Core
import Foundation

/// Shape of `xcrun simctl list devices -j` — the fields `config.values` reads.
/// Devices are keyed by runtime, which is what makes "the same name on two
/// runtimes" a question that has to be answered rather than assumed away.
struct SimctlDeviceList: Decodable {
    struct Device: Decodable {
        let name: String
        /// The only handle that survives a rename, and what every later simctl call
        /// addresses the device by.
        let udid: String
        /// `Booted`, `Shutdown`, `Creating`. Compared case-insensitively — the word is
        /// simctl's, not a contract.
        let state: String
        /// False for a device whose runtime the system unmounted. It is still
        /// listed, and it still cannot be booted.
        let isAvailable: Bool
    }

    /// Runtime identifier → the devices on it.
    let devices: [String: [Device]]

    /// A device the project could actually name, paired with the runtime it sits on.
    struct Simulator {
        let name: String
        let udid: String
        /// For ordering — `"9.0"` sorts above `"26.5"` as text.
        let runtime: SemanticVersion
        /// As the runtime writes it, so a report says `iOS 18.2` and not `18.2.0`.
        let runtimeText: String
        /// `com.apple.CoreSimulator.SimRuntime.iOS-26-5` — what `simctl create` wants.
        let runtimeIdentifier: String
        let isAvailable: Bool
        let isBooted: Bool
    }

    /// The runtime a `simctl create` line should name. simctl lists a runtime even
    /// when it holds no devices, which is what makes that command possible on a
    /// machine with none.
    ///
    /// - Parameter clearing: the project's floor. The newest runtime that clears it
    ///   wins; if none does, the newest one does — telling someone to create a device
    ///   they cannot boot at all is worse than one `simulator.runtime` already grades.
    func newestRuntime(clearing lookup: MatrixLookup?) -> (identifier: String, version: SemanticVersion)? {
        let runtimes = devices.keys
            .compactMap { identifier -> (identifier: String, version: SemanticVersion)? in
                guard let text = Self.iOSVersionText(of: identifier), let version = SemanticVersion(text) else {
                    return nil
                }
                return (identifier, version)
            }
        if case .requirement(let minimum, _) = lookup?.runtime {
            let compatible = runtimes.filter { minimum.isSatisfied(by: $0.version) }
            if !compatible.isEmpty { return compatible.max { $0.version < $1.version } }
        }
        return runtimes.max { $0.version < $1.version }
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
                Simulator(
                    name: $0.name,
                    udid: $0.udid,
                    runtime: runtime,
                    runtimeText: text,
                    runtimeIdentifier: identifier,
                    isAvailable: $0.isAvailable,
                    isBooted: $0.state.caseInsensitiveCompare("Booted") == .orderedSame
                )
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

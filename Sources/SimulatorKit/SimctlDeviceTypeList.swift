import Core
import Foundation

/// Shape of `xcrun simctl list devicetypes -j`. Read on one path only: when the
/// machine has no simulator at all and the error has to name a real device type for
/// the `simctl create` line it hands over.
struct SimctlDeviceTypeList: Decodable {
    struct DeviceType: Decodable {
        let name: String
        /// `com.apple.CoreSimulator.SimDeviceType.iPhone-17`.
        let identifier: String
        /// `iPhone`, `iPad`, `Apple Watch`. Absent on older Xcodes.
        let productFamily: String?
        let minRuntimeVersionString: String?
        let maxRuntimeVersionString: String?
    }

    let devicetypes: [DeviceType]

    static func command(environment: [String: String]) -> ProcessCommand {
        ProcessCommand(
            "xcrun", ["simctl", "list", "devicetypes", "-j"],
            environment: environment,
            timeout: .seconds(60)
        )
    }

    static func decode(_ standardOutput: String) -> SimctlDeviceTypeList? {
        try? JSONDecoder().decode(SimctlDeviceTypeList.self, from: Data(standardOutput.utf8))
    }

    /// The newest iPhone this Xcode can create on `runtime`. The version bounds are
    /// what keeps the suggested command from being one simctl refuses.
    func newestPhone(runningOn runtime: SemanticVersion) -> DeviceType? {
        devicetypes
            .filter { type in
                guard type.productFamily == nil || type.productFamily == "iPhone" else { return false }
                guard SimulatorNaming.isPhone(type.name) else { return false }
                if let floor = type.minRuntimeVersionString.flatMap(SemanticVersion.init), runtime < floor {
                    return false
                }
                if let ceiling = type.maxRuntimeVersionString.flatMap(SemanticVersion.init), ceiling < runtime {
                    return false
                }
                return true
            }
            .max { SimulatorNaming.isNewer($1.name, than: $0.name) }
    }
}

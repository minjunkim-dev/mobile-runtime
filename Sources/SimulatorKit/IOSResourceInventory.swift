import Core
import Foundation

public struct IOSResourceInventory: Sendable {
    public struct Runtime: Sendable {
        public let identifier: String
        public let name: String
        public let version: String
        public let build: String?
        public let architectures: [String]?
        public let available: Bool
    }

    public struct Device: Sendable, Equatable {
        public let identifier: String
        public let name: String
        public let runtimeIdentifier: String
        public let deviceTypeIdentifier: String?
        public let state: String
        public let available: Bool
    }

    public let runtimes: [Runtime]
    public let devices: [Device]
    private let list: SimctlDeviceList
    private let types: SimctlDeviceTypeList

    public static func load(runner: any ProcessRunner, environment: [String: String], deviceSet: URL) async throws -> Self {
        let runtimeResult = try await runner.run(SimctlRuntimeList.command(environment: environment))
        let deviceResult = try await runner.run(deviceCommand(deviceSet, environment: environment))
        let typeResult = try await runner.run(SimctlDeviceTypeList.command(environment: environment))
        guard runtimeResult.terminationStatus.isSuccess, deviceResult.terminationStatus.isSuccess,
              typeResult.terminationStatus.isSuccess,
              let runtimeList = SimctlRuntimeList.decode(runtimeResult.standardOutput),
              let deviceList = SimctlDeviceList.decode(deviceResult.standardOutput),
              let typeList = SimctlDeviceTypeList.decode(typeResult.standardOutput) else {
            throw DomainError(summary: "Could not observe iOS runtime, Simulator and device type identities",
                remediation: Remediation(summary: "Inspect the selected Xcode and CoreSimulator state, then re-plan. No resource was created."))
        }
        return Self(runtimes: runtimeList.runtimes.filter(\.isIOS).map {
            Runtime(identifier: $0.identifier, name: $0.name, version: $0.version, build: $0.buildversion,
                architectures: $0.supportedArchitectures, available: $0.isAvailable)
        }, devices: deviceList.devices.flatMap { runtime, devices in
            devices.map { Device(identifier: $0.udid, name: $0.name, runtimeIdentifier: runtime,
                deviceTypeIdentifier: $0.deviceTypeIdentifier, state: $0.state, available: $0.isAvailable) }
        }.sorted { $0.identifier < $1.identifier }, list: deviceList, types: typeList)
    }

    public static func deviceCommand(_ deviceSet: URL, environment: [String: String]) -> ProcessCommand {
        ProcessCommand("xcrun", ["simctl", "--set", deviceSet.path, "list", "devices", "-j"],
            environment: environment, timeout: .seconds(60))
    }

    public func compatibleRuntimes(minimum: MinimumVersion, architecture: String) -> [Runtime] {
        runtimes.filter {
            $0.available && $0.build?.range(of: #"^[0-9]+[A-Z][0-9]+$"#, options: .regularExpression) != nil
                && $0.architectures?.contains(architecture) == true
                && SemanticVersion($0.version).map { minimum.isSatisfied(by: $0) } == true
        }.sorted {
            guard let first = SemanticVersion($0.version), let second = SemanticVersion($1.version) else { return $0.identifier < $1.identifier }
            return first == second ? $0.identifier < $1.identifier : first > second
        }
    }

    /// Keep the existing name/booted/newest-iPhone selection order after strict compatibility filtering.
    public func existing(minimum: MinimumVersion, architecture: String, declared: String?) -> Device? {
        let runtimeIDs = Set(compatibleRuntimes(minimum: minimum, architecture: architecture).map(\.identifier))
        let candidates = list.simulators.filter { runtimeIDs.contains($0.runtimeIdentifier) && $0.isAvailable }
        guard case .success(let selected) = SimulatorSelector(simulators: candidates, lookup: nil).resolve(declared: declared) else { return nil }
        return devices.first { $0.identifier == selected.udid && $0.deviceTypeIdentifier != nil
            && ["Shutdown", "Booted"].contains($0.state) }
    }

    public func creation(runtimeID: String, version: String, build: String, architecture: String,
                         declared: String?, xcode: XcodeInstallation, deviceSet: URL) throws -> IOSSimulatorRequest {
        guard let versionNumber = SemanticVersion(version) else { throw failure("The runtime version is not an exact OS version") }
        let type: SimctlDeviceTypeList.DeviceType
        if let declared {
            let matches = types.devicetypes.filter { $0.name == declared }
            guard matches.count == 1, let only = matches.first else {
                throw failure("The declared Simulator is absent. Its name does not identify one device type; select or create it manually, then re-plan.")
            }
            type = only
        } else {
            guard let selected = types.newestPhone(runningOn: versionNumber) else {
                throw failure("The selected Xcode has no compatible iPhone device type for this exact runtime")
            }
            type = selected
        }
        guard type.minRuntimeVersionString.flatMap(SemanticVersion.init).map({ versionNumber >= $0 }) == true,
              type.maxRuntimeVersionString.flatMap(SemanticVersion.init).map({ versionNumber <= $0 }) == true else {
            throw failure("The device type's OS bounds are unknown or incompatible with the runtime")
        }
        let name = declared ?? "\(type.name) - Runstir - iOS \(version)"
        guard !devices.contains(where: { $0.name == name }) else {
            throw failure("A Simulator already uses the planned name. Preserve it and inspect its identity and state before creating another device.")
        }
        return IOSSimulatorRequest(name: name, deviceTypeIdentifier: type.identifier, runtimeIdentifier: runtimeID,
            runtimeVersion: version, runtimeBuild: build, architecture: architecture,
            developerDirectory: xcode.developerDirectory, xcodeVersion: xcode.version, xcodeBuild: xcode.build, deviceSet: deviceSet)
    }

    public func resource(_ device: Device, architecture: String, origin: IOSPreparationResource.Origin) -> IOSPreparationResource {
        let runtime = runtimes.first { $0.identifier == device.runtimeIdentifier }
        return IOSPreparationResource(kind: .simulator, identifier: device.identifier, name: device.name,
            runtimeIdentifier: device.runtimeIdentifier, runtimeBuild: runtime?.build, version: runtime?.version,
            architecture: architecture, deviceTypeIdentifier: device.deviceTypeIdentifier,
            state: device.state, isAvailable: device.available, origin: origin)
    }

    public func resource(_ runtime: Runtime, architecture: String, origin: IOSPreparationResource.Origin) -> IOSPreparationResource {
        IOSPreparationResource(kind: .runtime, identifier: runtime.identifier, name: runtime.name,
            runtimeIdentifier: runtime.identifier, runtimeBuild: runtime.build, version: runtime.version,
            architecture: runtime.architectures?.contains(architecture) == true ? architecture : nil,
            state: runtime.available ? "available" : "unavailable",
            isAvailable: runtime.available, origin: origin)
    }

    private func failure(_ message: String) -> DomainError {
        DomainError(summary: message, remediation: Remediation(summary: "Preserve existing resources. Resolve the selection or manual action, then inspect and approve a new plan."))
    }
}

import Core
import Foundation

public struct IOSWorkflowCandidates: Sendable {
    public let devices: [RuntimeDeviceCandidate]
    public let declaredDeviceID: String?
    public let schemes: [String]
    public let configurations: [String]

    public static func load(anchor: ProjectAnchor, config: ConfigContext, lookup: MatrixLookup?,
                            runner: any ProcessRunner, locator: XcodeLocator,
                            includeDevices: Bool) async throws -> Self {
        let environment = await locator.pinnedEnvironment()
        var devices: [RuntimeDeviceCandidate] = []
        var declaredID: String?
        if includeDevices {
            let result = try await runner.run(SimctlDeviceList.command(environment: environment))
            guard result.terminationStatus.isSuccess, let list = SimctlDeviceList.decode(result.standardOutput) else {
                throw ToolUnavailable(description: "Could not list iOS Simulator identities. Check Xcode and run mobile doctor.")
            }
            let available = list.simulators.filter { simulator in
                guard simulator.isAvailable else { return false }
                if case .requirement(let minimum, _) = lookup?.runtime { return minimum.isSatisfied(by: simulator.runtime) }
                return true
            }
            devices = available.map { RuntimeDeviceCandidate(id: $0.udid, name: $0.name, detail: "iOS \($0.runtimeText)") }
                .sorted { $0.id < $1.id }
            if let name = config.configuration?.device,
                case .success(let selected) = SimulatorSelector(simulators: available, lookup: lookup).named(name) {
                declaredID = selected.udid
            }
        }
        guard let target = XcodeBuildTarget.locate(inIOSDirectoryOf: anchor) else {
            throw DomainError(summary: "no Xcode project to build in ios/",
                              remediation: Remediation(summary: "Prepare the React Native iOS project before build or up."))
        }
        let targetToList = XcodeSchemeList.target(inIOSDirectoryOf: anchor, buildTarget: target)
        let result = try await runner.run(XcodeSchemeList.command(target: targetToList, environment: environment))
        guard result.terminationStatus.isSuccess, let listing = XcodeSchemeList.decode(result.standardOutput),
            !listing.schemes.isEmpty else {
            throw ToolUnavailable(description: "Could not list Xcode schemes. Check Xcode and run mobile doctor.")
        }
        return Self(devices: devices, declaredDeviceID: declaredID,
                    schemes: listing.schemes.sorted(), configurations: listing.configurations.sorted())
    }
}

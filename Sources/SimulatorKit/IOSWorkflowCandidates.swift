import Core
import Foundation

public struct IOSWorkflowCandidates: Sendable {
    public let devices: [RuntimeDeviceCandidate]
    public let declaredDeviceID: String?
    public let schemes: [String]
    public let configurations: [String]

    public static func load(anchor: ProjectAnchor, config: ConfigContext, lookup: MatrixLookup?,
                            runner: any ProcessRunner, locator: XcodeLocator,
                            includeDevices: Bool, configuration: String? = nil) async throws -> Self {
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
        var configurations = listing.configurations
        // Workspace lists omit configurations. Expose the effective value so callers reject Xcode's fallback.
        if configurations.isEmpty, let scheme = config.configuration?.scheme ?? (listing.schemes.count == 1 ? listing.schemes.first : nil),
           listing.schemes.contains(scheme) {
            let requested = configuration ?? "Debug"
            let arguments = ["-showBuildSettings", "-json"] + targetToList.arguments
                + ["-scheme", scheme, "-configuration", requested, "-destination", "generic/platform=iOS Simulator"]
            let settings = try await runner.run(ProcessCommand("xcodebuild", arguments, environment: environment, timeout: .seconds(120)))
            if settings.terminationStatus.isSuccess,
               let entries = (try? JSONSerialization.jsonObject(with: Data(settings.standardOutput.utf8))) as? [[String: Any]],
               !entries.isEmpty,
               let effective = (entries.first?["buildSettings"] as? [String: String])?["CONFIGURATION"],
               !effective.isEmpty,
               entries.allSatisfy({ ($0["buildSettings"] as? [String: String])?["CONFIGURATION"] == effective }) {
                configurations = [effective]
            }
        }
        return Self(devices: devices, declaredDeviceID: declaredID,
                    schemes: listing.schemes.sorted(), configurations: configurations.sorted())
    }
}

import Core
import Foundation

public struct IOSWorkflowCandidates: Sendable {
    public let devices: [RuntimeDeviceCandidate]
    public let declaredDeviceID: String?
    public let schemes: [String]
    public let configurations: [String]
    public let deploymentTarget: String?

    public static func load(anchor: ProjectAnchor, config: ConfigContext, lookup: MatrixLookup?,
                            runner: any ProcessRunner, locator: XcodeLocator,
                            includeDevices: Bool, configuration: String? = nil) async throws -> Self {
        let environment = await locator.pinnedEnvironment()
        var devices: [RuntimeDeviceCandidate] = []
        var declaredID: String?
        var availableSimulators: [SimctlDeviceList.Simulator] = []
        if includeDevices {
            let result = try await runner.run(SimctlDeviceList.command(environment: environment))
            guard result.terminationStatus.isSuccess, let list = SimctlDeviceList.decode(result.standardOutput) else {
                throw ToolUnavailable(description: "Could not list iOS Simulator identities. Check Xcode and run mobile doctor.")
            }
            availableSimulators = list.simulators.filter { simulator in
                guard simulator.isAvailable else { return false }
                if case .requirement(let minimum, _) = lookup?.runtime { return minimum.isSatisfied(by: simulator.runtime) }
                return true
            }
        }
        guard let target = XcodeBuildTarget.locate(inIOSDirectoryOf: anchor) else {
            throw DomainError(summary: "no selected Xcode project or workspace to build",
                              remediation: Remediation(summary: "Select an existing iOS project or workspace before build or up."))
        }
        let targetToList = XcodeSchemeList.target(inIOSDirectoryOf: anchor, buildTarget: target)
        let result = try await runner.run(XcodeSchemeList.command(target: targetToList, environment: environment))
        if anchor.framework == .nativeIOS, !result.terminationStatus.isSuccess {
            throw DomainError(summary: "Xcode could not inspect the selected native iOS container.",
                observed: result.combinedOutput.lastLines(10),
                remediation: Remediation(summary: "Prepare this project's locked dependencies and shared app scheme in Xcode, then retry. Automatic dependency resolution remains disabled."))
        }
        guard result.terminationStatus.isSuccess, let listing = XcodeSchemeList.decode(result.standardOutput) else {
            throw ToolUnavailable(description: "Could not list Xcode schemes. Check Xcode and run mobile doctor.")
        }
        let schemes = listing.schemes(in: targetToList, anchor: anchor)
        guard !schemes.isEmpty else {
            guard anchor.framework == .nativeIOS else {
                throw ToolUnavailable(description: "Could not list Xcode schemes. Check Xcode and run mobile doctor.")
            }
            throw DomainError(summary: "No shared Xcode scheme is available in the selected container.",
                              remediation: Remediation(summary: "Share the app scheme in Xcode and commit the .xcscheme file, then retry."))
        }
        var configurations = listing.configurations
        var deploymentTarget: String?
        // Workspace lists omit configurations. Expose the effective value so callers reject Xcode's fallback.
        if (configurations.isEmpty || anchor.framework == .nativeIOS),
           let scheme = config.configuration?.scheme ?? (schemes.count == 1 ? schemes.first : nil),
           schemes.contains(scheme) {
            let requested = configuration ?? "Debug"
            let arguments = ["-showBuildSettings", "-json"] + targetToList.arguments
                + ["-scheme", scheme, "-configuration", requested, "-destination", "generic/platform=iOS Simulator"]
            let settings = try await runner.run(ProcessCommand("xcodebuild", arguments, environment: environment, timeout: .seconds(120)))
            if anchor.framework == .nativeIOS {
                guard settings.terminationStatus.isSuccess,
                    let resolved = XcodeBuildSettings.decode(settings.standardOutput)?.applicationSettings(scheme: scheme, nativeTarget: targetToList),
                    let effective = resolved["CONFIGURATION"],
                    let minimum = resolved["IPHONEOS_DEPLOYMENT_TARGET"], MinimumVersion(minimum) != nil,
                    resolved["PLATFORM_NAME"] == "iphonesimulator"
                else {
                    throw DomainError(summary: "Could not resolve the native iOS app target, Simulator platform and deployment target.",
                        observed: settings.terminationStatus.isSuccess ? nil : settings.combinedOutput.lastLines(10),
                        remediation: Remediation(summary: "Prepare this shared app scheme in Xcode. Resolve dependencies and any required signing there, then retry. Runstir never provisions signing or changes the project."))
                }
                // A declared configuration is not proof that Xcode used it.
                // Keep the effective value so the caller rejects fallback to Release.
                if effective != requested { configurations = [effective] }
                else if configurations.isEmpty { configurations = [effective] }
                deploymentTarget = minimum
                if let floor = MinimumVersion(minimum) {
                    availableSimulators = availableSimulators.filter { floor.isSatisfied(by: $0.runtime) }
                }
            } else if settings.terminationStatus.isSuccess,
               let entries = (try? JSONSerialization.jsonObject(with: Data(settings.standardOutput.utf8))) as? [[String: Any]],
               !entries.isEmpty,
               let effective = (entries.first?["buildSettings"] as? [String: String])?["CONFIGURATION"],
               !effective.isEmpty,
               entries.allSatisfy({ ($0["buildSettings"] as? [String: String])?["CONFIGURATION"] == effective }) {
                configurations = [effective]
            }
        }
        devices = availableSimulators.map { RuntimeDeviceCandidate(id: $0.udid, name: $0.name, detail: "iOS \($0.runtimeText)") }
            .sorted { $0.id < $1.id }
        if let name = config.configuration?.device,
            case .success(let selected) = SimulatorSelector(simulators: availableSimulators, lookup: lookup).named(name) {
            declaredID = selected.udid
        }
        return Self(devices: devices, declaredDeviceID: declaredID,
                    schemes: schemes.sorted(), configurations: configurations.sorted(), deploymentTarget: deploymentTarget)
    }
}

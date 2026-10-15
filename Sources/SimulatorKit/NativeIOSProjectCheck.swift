import Core
import Foundation

/// Native iOS preparation is measured, never installed or rewritten by a build.
public struct NativeIOSProjectCheck: Check {
    public let id = "project.native-ios"
    public let category = "Project"
    public let title = "The shared native iOS app scheme is ready for Simulator"
    public var dependsOn: [String] {
        ["xcode.installed", "xcode.ready", "project.execution-environment"]
            + (config.file != nil || config.misspelledFile != nil ? ["config.syntax"] : [])
    }

    private let anchor: ProjectAnchor
    private let config: ConfigContext
    private let lookup: MatrixLookup?
    private let runner: any ProcessRunner
    private let locator: XcodeLocator
    private let configuration: String

    public init(anchor: ProjectAnchor, config: ConfigContext, lookup: MatrixLookup?,
                runner: any ProcessRunner, locator: XcodeLocator, configuration: String = "Debug") {
        self.anchor = anchor
        self.config = config
        self.lookup = lookup
        self.runner = runner
        self.locator = locator
        self.configuration = configuration
    }

    public func run() async throws -> CheckOutcome {
        let source = CheckSource(tier: 1, origin: anchor.iosContainer ?? "native iOS project")
        let podfile = anchor.iosDirectory.appendingPathComponent("Podfile")
        if FileManager.default.fileExists(atPath: podfile.path) {
            let lock = try? Data(contentsOf: anchor.iosDirectory.appendingPathComponent("Podfile.lock"))
            let installed = try? Data(contentsOf: anchor.iosDirectory.appendingPathComponent("Pods/Manifest.lock"))
            guard let lock, lock == installed, anchor.iosContainer?.hasSuffix(".xcworkspace") == true else {
                return .error(observed: "CocoaPods preparation is missing, differs from Podfile.lock, or the selected container is not a workspace",
                    required: "the prepared CocoaPods workspace with matching installed dependencies", source: source,
                    remediation: Remediation(summary: "Prepare dependencies with the project's documented CocoaPods command, then select its workspace. Runstir does not install native iOS dependencies during build or up.",
                        command: anchor.podInstallCommand))
            }
        }
        let candidates = try await IOSWorkflowCandidates.load(anchor: anchor, config: config, lookup: lookup,
            runner: runner, locator: locator, includeDevices: false, configuration: configuration)
        guard let target = candidates.deploymentTarget, let minimum = MinimumVersion(target) else {
            return .unknown(reason: "Choose a shared app scheme before its Simulator deployment target can be measured.", source: source)
        }
        guard candidates.configurations.contains(configuration) else {
            return .unknown(reason: "The selected scheme did not resolve \(configuration). Choose an existing configuration explicitly for build or up.", source: source)
        }
        let runtime = MatrixLookup(xcode: lookup?.xcode ?? .unavailable(reason: "not measured", source: source),
            runtime: .requirement(minimum, source: source))
        return try await SimulatorRuntimeCheck(lookup: runtime, runner: runner, locator: locator).run()
    }
}

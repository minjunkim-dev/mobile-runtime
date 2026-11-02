import Core
import Foundation

/// `simulator.runtime` — is an iOS runtime new enough for this project installed,
/// and is it actually usable? Runtimes are system-wide cryptex images, not part of
/// the Xcode bundle, so one that worked yesterday can come back `isAvailable:
/// false` after a macOS update. An installed-but-unavailable runtime is the
/// failure this Check exists for; counting it as present would be the miss.
public struct SimulatorRuntimeCheck: Check {
    public let id = "simulator.runtime"
    public let category = "iOS Simulator"
    public let title = "An iOS runtime this project can run on is installed and available"
    public let dependsOn: [String]

    /// The recovery routine for a runtime the system unmounted from under Xcode.
    private static let remount = Remediation(
        summary: "Re-mount the runtime images macOS unmounted — shut the simulators down, "
            + "drop the devices whose runtime vanished, then re-scan.",
        command: "xcrun simctl shutdown all; xcrun simctl delete unavailable; "
            + "xcrun simctl runtime scan-and-mount"
    )

    private let requirement: @Sendable () async throws -> RequirementLookup
    private let runner: any ProcessRunner
    private let locator: XcodeLocator

    public init(lookup: MatrixLookup, runner: any ProcessRunner, locator: XcodeLocator) {
        self.init(requirement: lookup.runtime, runner: runner, locator: locator)
    }

    init(requirement: RequirementLookup, runner: any ProcessRunner, locator: XcodeLocator) {
        self.dependsOn = ["simulator.daemon"]
        self.requirement = { requirement }
        self.runner = runner
        self.locator = locator
    }

    /// Grades the deployment target the selected native scheme measures. A scheme
    /// Xcode cannot resolve is `project.native-ios`'s error; here it stays unknown.
    /// - Parameter project: the measuring Check, whose prerequisites gate the measurement here too.
    public init(measurement: NativeIOSSchemeMeasurement, project: NativeIOSProjectCheck,
                runner: any ProcessRunner, locator: XcodeLocator) {
        self.dependsOn = Array(Set(["simulator.daemon"] + project.dependsOn)).sorted()
        self.requirement = {
            do { return try await measurement.runtime() } catch is DomainError {
                return .unavailable(reason: "The selected scheme's deployment target could not be measured. Resolve project.native-ios first.",
                    source: measurement.source)
            }
        }
        self.runner = runner
        self.locator = locator
    }

    public func run() async throws -> CheckOutcome {
        let requirement = try await requirement()
        let minimum: MinimumVersion
        switch requirement {
        case .requirement(let version, _): minimum = version
        case .unavailable(let reason, let source): return .unknown(reason: reason, source: source)
        }
        let source = requirement.source
        let required = "an iOS \(minimum) or newer simulator runtime, available"

        let result = try await runner.run(
            SimctlRuntimeList.command(environment: await locator.pinnedEnvironment())
        )
        // simulator.daemon passed, so simctl was answering moments ago. Anything
        // else here is a machine that moved under us, not a verdict about the project.
        guard result.terminationStatus.isSuccess, let list = SimctlRuntimeList.decode(result.standardOutput) else {
            return .unknown(
                reason: "simctl stopped listing runtimes — "
                    + (result.standardError.firstLine ?? "its output was not a runtime list"),
                required: required, source: source
            )
        }

        // Paired with the parsed version so "newest" is a version comparison and not
        // a string one — `"9.0"` sorts above `"26.5"` as text.
        let matching = list.runtimes.compactMap { runtime -> (runtime: SimctlRuntimeList.Runtime, version: SemanticVersion)? in
            guard runtime.isIOS, let version = SemanticVersion(runtime.version),
                minimum.isSatisfied(by: version)
            else { return nil }
            return (runtime, version)
        }
        if let usable = matching.filter(\.runtime.isAvailable).max(by: { $0.version < $1.version })?.runtime {
            return .pass(
                observed: "\(usable.name) installed and available",
                required: required,
                source: source
            )
        }
        // Installed but unusable is a different problem — and a different fix —
        // from never installed.
        guard matching.isEmpty else {
            return .error(
                observed: matching.map(\.runtime.name).joined(separator: ", ") + " installed but unavailable",
                required: required,
                source: source,
                remediation: Self.remount
            )
        }
        let present = list.runtimes.filter(\.isIOS).map(\.name)
        return .error(
            observed: present.isEmpty
                ? "no iOS runtime installed"
                : "installed iOS runtimes: \(present.joined(separator: ", "))",
            required: required,
            source: source,
            remediation: Remediation(
                summary: "Install an iOS \(minimum) or newer simulator runtime.",
                command: "xcodebuild -downloadPlatform iOS",
                url: "https://developer.apple.com/documentation/xcode/installing-additional-simulator-runtimes"
            )
        )
    }
}

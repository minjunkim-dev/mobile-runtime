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
    public let dependsOn = ["simulator.daemon"]

    /// The recovery routine for a runtime the system unmounted from under Xcode.
    private static let remount = Remediation(
        summary: "Re-mount the runtime images macOS unmounted — shut the simulators down, "
            + "drop the devices whose runtime vanished, then re-scan.",
        command: "xcrun simctl shutdown all; xcrun simctl delete unavailable; "
            + "xcrun simctl runtime scan-and-mount"
    )

    private let lookup: MatrixLookup
    private let runner: any ProcessRunner
    private let locator: XcodeLocator

    public init(lookup: MatrixLookup, runner: any ProcessRunner, locator: XcodeLocator) {
        self.lookup = lookup
        self.runner = runner
        self.locator = locator
    }

    public func run() async throws -> CheckOutcome {
        let requirements: CompatibilityMatrix.IOSRequirements
        switch lookup {
        case .requirements(let resolved, _): requirements = resolved
        case .unavailable(let reason): return .unknown(reason: reason, source: lookup.source)
        }
        let required = "an iOS \(requirements.runtime) or newer simulator runtime, available"

        let result = try await runner.run(
            SimctlRuntimeList.command(environment: await locator.pinnedEnvironment())
        )
        // simulator.daemon passed, so simctl was answering moments ago. Anything
        // else here is a machine that moved under us, not a verdict about the project.
        guard result.terminationStatus.isSuccess, let list = SimctlRuntimeList.decode(result.standardOutput) else {
            return .unknown(
                reason: "simctl stopped listing runtimes — "
                    + (result.standardError.firstLine ?? "its output was not a runtime list"),
                required: required, source: lookup.source
            )
        }

        // Paired with the parsed version so "newest" is a version comparison and not
        // a string one — `"9.0"` sorts above `"26.5"` as text.
        let matching = list.runtimes.compactMap { runtime -> (runtime: SimctlRuntimeList.Runtime, version: SemanticVersion)? in
            guard runtime.isIOS, let version = SemanticVersion(runtime.version),
                requirements.runtime.isSatisfied(by: version)
            else { return nil }
            return (runtime, version)
        }
        if let usable = matching.filter(\.runtime.isAvailable).max(by: { $0.version < $1.version })?.runtime {
            return .pass(
                observed: "\(usable.name) installed and available",
                required: required,
                source: lookup.source
            )
        }
        // Installed but unusable is a different problem — and a different fix —
        // from never installed.
        guard matching.isEmpty else {
            return .error(
                observed: matching.map(\.runtime.name).joined(separator: ", ") + " installed but unavailable",
                required: required,
                source: lookup.source,
                remediation: Self.remount
            )
        }
        let present = list.runtimes.filter(\.isIOS).map(\.name)
        return .error(
            observed: present.isEmpty
                ? "no iOS runtime installed"
                : "installed iOS runtimes: \(present.joined(separator: ", "))",
            required: required,
            source: lookup.source,
            remediation: Remediation(
                summary: "Install an iOS \(requirements.runtime) or newer simulator runtime.",
                command: "xcodebuild -downloadPlatform iOS",
                url: "https://developer.apple.com/documentation/xcode/installing-additional-simulator-runtimes"
            )
        )
    }
}

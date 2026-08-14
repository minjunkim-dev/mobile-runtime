import Core
import Foundation

/// `config.values` — a declaration gets no special treatment. A device or scheme
/// named in mobile.yml is measured against the machine and the project like every
/// other requirement, and the one question the file exists to answer — "which
/// scheme, out of these several?" — is asked here even when there is no file.
public struct ConfigValuesCheck: Check {
    public let id = "config.values"
    public let category = "mobile.yml"
    public let title = "mobile.yml names a simulator and a scheme that exist"

    private let context: ConfigContext
    /// Used only to prefer a runtime the project can actually run on when one
    /// device name exists on several. nil outside a project.
    private let lookup: MatrixLookup?
    private let runner: any ProcessRunner
    private let locator: XcodeLocator

    public init(
        context: ConfigContext,
        lookup: MatrixLookup?,
        runner: any ProcessRunner,
        locator: XcodeLocator
    ) {
        self.context = context
        self.lookup = lookup
        self.runner = runner
        self.locator = locator
    }

    /// There is something to say when a file exists, when one sits where mobile
    /// never reads it, or when the project has schemes to choose between.
    public static func applies(to context: ConfigContext) -> Bool {
        context.file != nil || context.strayFile != nil || context.anchor?.hasIOSDirectory == true
    }

    /// What one half of the file's values amounts to.
    private enum Judgement {
        /// Fine, with a phrase for the pass line.
        case ok(String)
        /// A verdict worth stopping on — the first problem is the one to fix.
        case verdict(CheckOutcome)
        /// Nothing declared and nothing measurable: no line, no noise.
        case silent
    }

    private var source: CheckSource {
        CheckSource(tier: 3, origin: context.file == nil ? "no \(MobileConfig.fileName)" : MobileConfig.fileName)
    }

    public func run() async throws -> CheckOutcome {
        // Validating the values of a file that did not parse is meaningless, and
        // half-parsing it would be worse.
        if case .invalid = context.parse {
            return .unknown(
                reason: "\(MobileConfig.fileName) did not parse, so its values were not checked — "
                    + "see `config.syntax`",
                source: source
            )
        }
        var judgements = [try await judgeDevice(), try await judgeScheme()]
        // Last, so a wrong value in the file mobile *does* read outranks a file it
        // never reads — but never dropped, because a stray is invisible otherwise.
        if let stray = context.strayFile { judgements.append(.verdict(strayOutcome(stray))) }

        for judgement in judgements {
            if case .verdict(let outcome) = judgement { return outcome }
        }
        let notes = judgements.compactMap { judgement -> String? in
            if case .ok(let note) = judgement { return note }
            return nil
        }
        return .pass(
            observed: notes.isEmpty ? "nothing declared to check" : notes.joined(separator: ", "),
            source: source
        )
    }

    /// A file in a place mobile never reads is the silent failure this Check is
    /// here to break: it looks configured, and nothing it says has any effect.
    private func strayOutcome(_ stray: URL) -> CheckOutcome {
        let destination = context.anchorDirectory
        return .warning(
            observed: "\(stray.path) is not next to a React Native project, so mobile never reads it",
            required: "\(MobileConfig.fileName) beside the package.json that depends on react-native",
            source: source,
            remediation: Remediation(
                summary: destination.map {
                    "Move it to \($0.appendingPathComponent(MobileConfig.fileName).path) — "
                        + "mobile reads mobile.yml beside the project's package.json and nowhere else."
                }
                    ?? "mobile found no React Native project here. Move the file beside the "
                        + "package.json that depends on react-native, or delete it."
            )
        )
    }

    private func judgeDevice() async throws -> Judgement {
        guard let declared = context.configuration?.device else { return .silent }

        // A UDID would work on this machine and nowhere else — and mobile.yml is
        // committed with the repo.
        guard !Self.isUDID(declared) else {
            return .verdict(
                .error(
                    observed: "ios.device: \(declared) is a UDID",
                    required: "a simulator name",
                    source: source,
                    remediation: Remediation(
                        summary: "Name the simulator instead — a UDID belongs to one machine, and "
                            + "mobile.yml is committed with the repo.",
                        command: "xcrun simctl list devices available"
                    )
                )
            )
        }

        // `iPhone 16 Pro (26.0)` picks the runtime too, and the runtime is inferred.
        guard !Self.namesARuntime(declared) else {
            return .verdict(
                .error(
                    observed: "ios.device: \(declared) names a runtime as well as a device",
                    required: "a simulator name",
                    source: source,
                    remediation: Remediation(
                        summary: "Name the simulator only — which runtime it boots on is inferred, "
                            + "and mobile takes the newest one this project can run on.",
                        command: "xcrun simctl list devices available"
                    )
                )
            )
        }

        let result = try await runner.run(
            SimctlDeviceList.command(environment: await locator.pinnedEnvironment())
        )
        guard result.terminationStatus.isSuccess, let list = SimctlDeviceList.decode(result.standardOutput) else {
            return .verdict(
                .unknown(
                    reason: "simctl did not list the simulators — "
                        + (result.standardError.firstLine ?? "its output was not a device list"),
                    source: source
                )
            )
        }

        let named = list.simulators.filter { $0.name == declared }
        let available = named.filter(\.isAvailable)
        guard let resolved = Self.preferred(available, lookup: lookup) else {
            return .verdict(
                named.isEmpty
                    ? .error(
                        observed: "no simulator named \(declared)",
                        required: "a simulator installed on this machine",
                        source: source,
                        remediation: Remediation(
                            summary: "Set ios.device to one of the simulators on this machine: "
                                + Self.summarise(list.simulators.filter(\.isAvailable).map(\.name)),
                            command: "xcrun simctl list devices available"
                        )
                    )
                    : .error(
                        observed: "\(declared) exists only on runtimes macOS has made unavailable",
                        required: "a simulator installed on this machine",
                        source: source,
                        remediation: Remediation(
                            summary: "Re-mount the runtime images macOS unmounted, then re-run mobile doctor.",
                            command: "xcrun simctl shutdown all; xcrun simctl delete unavailable; "
                                + "xcrun simctl runtime scan-and-mount"
                        )
                    )
            )
        }
        return .ok("device \(declared) on iOS \(resolved.runtimeText)")
    }

    private func judgeScheme() async throws -> Judgement {
        let declared = context.configuration?.scheme
        guard let anchor = context.anchor, anchor.hasIOSDirectory,
            let project = XcodeSchemeList.project(inIOSDirectoryOf: anchor)
        else {
            guard let declared else { return .silent }
            return .verdict(
                .unknown(
                    reason: "ios.scheme declares \(declared), and there is no single "
                        + "ios/*.xcodeproj to check it against",
                    source: source
                )
            )
        }

        let list = XcodeSchemeList.command(project: project, environment: await locator.pinnedEnvironment())
        let result = try await runner.run(list)
        guard result.terminationStatus.isSuccess,
            let schemes = XcodeSchemeList.decode(result.standardOutput)?.project.schemes, !schemes.isEmpty
        else {
            return .verdict(
                .unknown(
                    reason: "`\(list.description)` listed no schemes — "
                        + (result.standardError.firstLine ?? "its output was not a scheme list"),
                    source: source
                )
            )
        }

        guard let declared else {
            // The point of the whole file: one scheme needs no declaration, and
            // several cannot be guessed between.
            guard schemes.count > 1 else {
                return .ok("no scheme declared — \(schemes[0]) is the only one")
            }
            // A warning, not an error: doctor answers "can this machine build the
            // project", and an unpicked scheme is a choice nobody has made yet rather
            // than a broken machine. App extensions make several schemes the norm —
            // all three dogfooding repos have them — so exit 1 would fail CI on
            // healthy repos. `up` cannot proceed on it, and that grade belongs to the
            // stage that has to pick one (ADR-0004).
            return .verdict(
                .warning(
                    observed: "\(schemes.count) schemes — \(schemes.joined(separator: ", ")) — "
                        + "and nothing declares which one to build",
                    required: "ios.scheme, because this project has more than one scheme",
                    source: source,
                    remediation: Remediation(
                        summary: "Declare the scheme in "
                            + "\(anchor.directory.appendingPathComponent(MobileConfig.fileName).path): "
                            + "`ios:` on one line, `  scheme: \(schemes[0])` on the next.",
                        command: "xcodebuild -list -project \(project.path)"
                    )
                )
            )
        }
        guard schemes.contains(declared) else {
            return .verdict(
                .error(
                    observed: "no scheme named \(declared) — this project has "
                        + schemes.joined(separator: ", "),
                    required: "a scheme this project defines",
                    source: source,
                    remediation: Remediation(
                        summary: "Set ios.scheme to one of them.",
                        command: "xcodebuild -list -project \(project.path)"
                    )
                )
            )
        }
        return .ok("scheme \(declared)")
    }

    /// The newest simulator the project can run on. Where one name exists on
    /// several runtimes the matrix breaks the tie; without it, newest wins.
    private static func preferred(
        _ simulators: [SimctlDeviceList.Simulator],
        lookup: MatrixLookup?
    ) -> SimctlDeviceList.Simulator? {
        var candidates = simulators
        if case .requirement(let minimum, _) = lookup?.runtime {
            let compatible = simulators.filter { minimum.isSatisfied(by: $0.runtime) }
            // Falling back to an incompatible runtime is not this Check's error to
            // raise — `simulator.runtime` already says the machine has none.
            if !compatible.isEmpty { candidates = compatible }
        }
        return candidates.max { $0.runtime < $1.runtime }
    }

    private static func summarise(_ names: [String], limit: Int = 8) -> String {
        let unique = Set(names).sorted()
        guard unique.count > limit else { return unique.joined(separator: ", ") }
        return unique.prefix(limit).joined(separator: ", ") + " and \(unique.count - limit) more"
    }

    /// `iPhone 16 Pro (26.0)`, `iPhone 16 Pro (iOS 26.0)`, `name,OS=26.0`. Apple's
    /// own names carry parentheses — `iPad Pro (12.9-inch)` — so only a trailing
    /// group that reads as an iOS version counts.
    private static func namesARuntime(_ value: String) -> Bool {
        if value.contains("OS=") { return true }
        guard value.hasSuffix(")"), let opening = value.lastIndex(of: "(") else { return false }
        var group = value[value.index(after: opening)..<value.index(before: value.endIndex)]
            .trimmingCharacters(in: .whitespaces)
        if group.hasPrefix("iOS") { group = String(group.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
        return group.allSatisfy { $0.isNumber || $0 == "." } && SemanticVersion(group) != nil
    }

    /// `8-4-4-4-12` hex, the shape simctl prints.
    private static func isUDID(_ value: String) -> Bool {
        value.split(separator: "-", omittingEmptySubsequences: false).map(\.count) == [8, 4, 4, 4, 12]
            && value.allSatisfy { $0.isHexDigit || $0 == "-" }
    }
}

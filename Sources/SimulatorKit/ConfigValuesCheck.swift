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
    private static let undecidedSchemeRequirement =
        "ios.scheme, because this project has more than one scheme"

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

    static func isUndecidedScheme(_ result: CheckResult) -> Bool {
        result.id == "config.values"
            && result.outcome.required == undecidedSchemeRequirement
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
            observed: "\(context.display(stray)) is not next to a React Native project, "
                + "so mobile never reads it",
            required: "\(MobileConfig.fileName) beside the package.json that depends on react-native",
            source: source,
            remediation: Remediation(
                summary: destination.map {
                    "Move it to \(context.display($0.appendingPathComponent(MobileConfig.fileName))) — "
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

        // The same selector `up`'s device stage runs. Judging a declaration with one
        // rule and booting with another is how doctor comes to bless a device that up
        // then refuses.
        let selector = SimulatorSelector(simulators: list.simulators, lookup: lookup)
        switch selector.named(declared) {
        case .success(let resolved):
            return .ok("device \(declared) on iOS \(resolved.runtimeText)")
        case .failure(let miss):
            return .verdict(
                .error(
                    observed: miss.observed,
                    required: "a simulator installed on this machine",
                    source: source,
                    remediation: miss.remediation(availableNames: selector.availableNames)
                )
            )
        }
    }

    private func judgeScheme() async throws -> Judgement {
        let declared = context.configuration?.scheme
        guard let anchor = context.anchor, anchor.hasIOSDirectory,
            let buildTarget = XcodeBuildTarget.locate(inIOSDirectoryOf: anchor)
        else {
            guard let declared else { return .silent }
            return .verdict(
                .unknown(
                    reason: "ios.scheme declares \(declared), and there is no single root "
                        + "ios/*.xcworkspace or ios/*.xcodeproj to check it against",
                    source: source
                )
            )
        }

        let target = XcodeSchemeList.target(inIOSDirectoryOf: anchor, buildTarget: buildTarget)
        let list = XcodeSchemeList.command(target: target, environment: await locator.pinnedEnvironment())
        let result = try await runner.run(list)
        guard result.terminationStatus.isSuccess,
            let schemes = XcodeSchemeList.decode(result.standardOutput)?.schemes, !schemes.isEmpty
        else {
            return .verdict(
                .unknown(
                    reason: "`\(list.description)` listed no schemes — "
                        + (result.standardError.firstLine ?? "its output was not a scheme list"),
                    source: source
                )
            )
        }

        // The same selector `up`'s build stage runs, so a scheme doctor approves is
        // the scheme that gets built.
        switch SchemeSelector(schemes: schemes).resolve(declared: declared) {
        case .success(let resolved):
            return .ok(
                declared == nil
                    ? "no scheme declared — \(resolved) is the only one"
                    : "scheme \(resolved)"
            )
        case .failure(let miss):
            let remediation = miss.remediation(
                configFile: context.display(
                    anchor.directory.appendingPathComponent(MobileConfig.fileName)
                ),
                target: context.display(target.url),
                kind: target.kind
            )
            switch miss {
            case .noSchemeNamed:
                return .verdict(
                    .error(
                        observed: miss.observed,
                        required: "a scheme this project defines",
                        source: source,
                        remediation: remediation
                    )
                )
            case .undecided:
                // A warning, not an error: doctor answers "can this machine build the
                // project", and an unpicked scheme is a choice nobody has made yet
                // rather than a broken machine. App extensions make several schemes
                // the norm — all three dogfooding repos have them — so exit 1 would
                // fail CI on healthy repos. `up` cannot proceed on it, and that grade
                // belongs to the stage that has to pick one (ADR-0004).
                return .verdict(
                    .warning(
                        observed: miss.observed,
                        required: Self.undecidedSchemeRequirement,
                        source: source,
                        remediation: remediation
                    )
                )
            }
        }
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

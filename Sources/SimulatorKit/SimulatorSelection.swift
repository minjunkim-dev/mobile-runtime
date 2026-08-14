import Core

/// Which simulator a run uses, decided in one place. `config.values` asks whether the
/// declared name resolves and `device` asks which one to boot, and they are the same
/// question asked twice — a second copy of this would let doctor call a device usable
/// and then watch up boot a different one.
struct SimulatorSelector {
    /// Why nothing was chosen. The wording belongs to the caller: doctor grades a
    /// declaration, `up` stops a pipeline, and the same fact reads differently.
    enum Miss: Error, Equatable {
        case noSimulatorNamed(String)
        /// The name exists, on runtimes macOS has unmounted.
        case unavailableRuntimesOnly(String)
        /// Nothing to pick from unasked. An iPad-only machine lands here too, which is
        /// why the wording says iPhone rather than claiming the machine is empty.
        case noPhoneInstalled

        /// What was looked for and not found. Both callers report this verbatim, so
        /// doctor and up cannot describe the same machine differently.
        var observed: String {
            switch self {
            case .noSimulatorNamed(let name): "no simulator named \(name)"
            case .unavailableRuntimesOnly(let name):
                "\(name) exists only on runtimes macOS has made unavailable"
            case .noPhoneInstalled: "no iPhone simulator on this machine to boot"
            }
        }

        /// - Parameter create: a measured `simctl create` line, or nil when the device
        ///   type could not be read — no command beats a wrong one.
        func remediation(availableNames: [String], create: String? = nil) -> Remediation {
            switch self {
            case .noSimulatorNamed:
                Remediation(
                    summary: "Set ios.device to one of the simulators on this machine: "
                        + Self.summarise(availableNames),
                    command: "xcrun simctl list devices available"
                )
            case .unavailableRuntimesOnly:
                Remediation(
                    summary: "Re-mount the runtime images macOS unmounted, then re-run mobile doctor.",
                    command: "xcrun simctl shutdown all; xcrun simctl delete unavailable; "
                        + "xcrun simctl runtime scan-and-mount"
                )
            case .noPhoneInstalled:
                Remediation(
                    summary: create == nil
                        ? "Create one with `xcrun simctl create` — mobile does not create simulators for "
                            + "you. `xcrun simctl list devicetypes` and `xcrun simctl list runtimes` name "
                            + "the two things it needs."
                        : "Create one, then re-run — mobile does not create simulators for you.",
                    command: create
                )
            }
        }

        private static func summarise(_ names: [String], limit: Int = 8) -> String {
            let unique = Set(names).sorted()
            guard unique.count > limit else { return unique.joined(separator: ", ") }
            return unique.prefix(limit).joined(separator: ", ") + " and \(unique.count - limit) more"
        }
    }

    private let simulators: [SimctlDeviceList.Simulator]
    /// Only used to prefer a runtime the project can actually run on when one name
    /// exists on several. nil outside a project.
    private let lookup: MatrixLookup?

    init(simulators: [SimctlDeviceList.Simulator], lookup: MatrixLookup?) {
        self.simulators = simulators
        self.lookup = lookup
    }

    /// The names worth suggesting when a declaration missed.
    var availableNames: [String] {
        simulators.filter(\.isAvailable).map(\.name)
    }

    /// A declared name, resolved to one device. The newest runtime the project can run
    /// on wins when the name exists on several.
    func named(_ declared: String) -> Result<SimctlDeviceList.Simulator, Miss> {
        let named = simulators.filter { $0.name == declared }
        guard let resolved = Self.preferred(named.filter(\.isAvailable), lookup: lookup) else {
            return .failure(named.isEmpty ? .noSimulatorNamed(declared) : .unavailableRuntimesOnly(declared))
        }
        return .success(resolved)
    }

    /// `up`'s order: what mobile.yml declared, then whatever is already running, then
    /// the newest iPhone this machine has. A booted simulator outranks a better one
    /// that is not: booting takes seconds nobody asked to spend.
    func resolve(declared: String?) -> Result<SimctlDeviceList.Simulator, Miss> {
        if let declared { return named(declared) }
        if let booted = Self.preferred(simulators.filter { $0.isAvailable && $0.isBooted }, lookup: lookup) {
            return .success(booted)
        }
        let phones = simulators.filter { $0.isAvailable && SimulatorNaming.isPhone($0.name) }
        guard let automatic = Self.preferred(phones, lookup: lookup) else {
            return .failure(.noPhoneInstalled)
        }
        return .success(automatic)
    }

    /// Newest runtime first, then the newest model on it. Where the matrix names a
    /// floor, runtimes below it are dropped — unless that leaves nothing, because
    /// "this machine has no new enough runtime" is `simulator.runtime`'s verdict to
    /// give, and saying it twice is two errors for one problem.
    private static func preferred(
        _ simulators: [SimctlDeviceList.Simulator],
        lookup: MatrixLookup?
    ) -> SimctlDeviceList.Simulator? {
        var candidates = simulators
        if case .requirement(let minimum, _) = lookup?.runtime {
            let compatible = simulators.filter { minimum.isSatisfied(by: $0.runtime) }
            if !compatible.isEmpty { candidates = compatible }
        }
        return candidates.max { first, second in
            first.runtime == second.runtime
                ? SimulatorNaming.isNewer(second.name, than: first.name)
                : first.runtime < second.runtime
        }
    }

}

/// Ordering for simulator and device-type names. Apple's names are marketing, not a
/// version scheme, so this ranks the two things that are actually legible in them:
/// the generation number, and how plain the model is.
enum SimulatorNaming {
    /// Higher is newer. `iPhone 17` outranks `iPhone 16 Pro Max`, and among one
    /// generation the plainest name wins — `iPhone 17` over `iPhone 17 Pro` and
    /// `iPhone 17e`. Any stable rule would do; this one picks the device most people
    /// would have picked by hand.
    static func rank(of name: String) -> (generation: Int, plainness: Int) {
        (generation(of: name) ?? -1, -name.count)
    }

    static func isNewer(_ name: String, than other: String) -> Bool {
        rank(of: name) > rank(of: other)
    }

    /// An iPad boots and builds, but "the newest iPhone" is what a React Native
    /// developer means by "a simulator", and a device chosen for you should not be a
    /// surprise. Devices and device types are judged by the one rule. A declared name
    /// is never filtered this way.
    static func isPhone(_ name: String) -> Bool { name.hasPrefix("iPhone") }

    /// The first number in the name: `iPhone 16 Pro` is 16, `iPhone 17e` is 17, and
    /// `iPhone Air` has none.
    private static func generation(of name: String) -> Int? {
        for word in name.split(separator: " ") {
            let digits = word.prefix { $0.isNumber }
            if !digits.isEmpty { return Int(digits) }
        }
        return nil
    }
}

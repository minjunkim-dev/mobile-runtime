import Core

/// The iOS Checks doctor runs, in report order. Assembling them lives next to the
/// Checks themselves — the way `ProjectAnchor.checks(runner:)` owns the project
/// ones — so adding an iOS Check is never a CLI edit.
///
/// - Parameter lookup: nil outside a project. The two Tier 2 Checks then do not
///   exist, the way a project that pinned no Ruby gets no Ruby line: a Check with
///   nothing to compare against is absent, not permanently `unknown`. What the
///   machine alone can answer — `xcode.installed`, `simulator.daemon` — still runs.
public func iOSChecks(
    lookup: MatrixLookup?,
    runner: any ProcessRunner,
    locator: XcodeLocator
) -> [any Check] {
    var checks: [any Check] = [XcodeInstalledCheck(locator: locator)]
    if let lookup { checks.append(XcodeVersionCheck(lookup: lookup, locator: locator)) }
    checks.append(SimulatorDaemonCheck(runner: runner, locator: locator))
    if let lookup { checks.append(SimulatorRuntimeCheck(lookup: lookup, runner: runner, locator: locator)) }
    return checks
}

/// The mobile.yml Checks. `config.syntax` comes from Core — parsing a config file
/// is not iOS knowledge — while `config.values` lives here, because a device is a
/// simulator and a scheme is Xcode's. Both are absent when there is nothing to
/// say: zero-config means zero noise.
public func configChecks(
    context: ConfigContext,
    lookup: MatrixLookup?,
    runner: any ProcessRunner,
    locator: XcodeLocator
) -> [any Check] {
    var checks = context.checks()
    if ConfigValuesCheck.applies(to: context) {
        checks.append(
            ConfigValuesCheck(context: context, lookup: lookup, runner: runner, locator: locator)
        )
    }
    return checks
}

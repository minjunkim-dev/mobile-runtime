import Core

/// The Stages `up` runs on iOS, in pipeline order. Assembling them lives next to
/// the Stages themselves — the way `iOSChecks` owns doctor's list — so adding a
/// Stage is never a CLI edit.
/// - Parameter note: where a Stage that is still working writes its elapsed line.
///   Only `build` takes long enough to need one.
/// - Parameter settle: how long `launch` waits for the app to draw. A parameter so a
///   test does not spend three seconds per run on it.
public func iOSUpStages(
    anchor: ProjectAnchor,
    doctor: DoctorEngine,
    config: ConfigContext,
    lookup: MatrixLookup?,
    runner: any ProcessRunner,
    locator: XcodeLocator,
    settle: Duration = LaunchStage.defaultSettle,
    note: @escaping @Sendable (String) -> Void
) -> [any Stage] {
    // One log directory per run of the pipeline, so the stage that streams into it
    // and the stage that writes the install record next to it cannot disagree.
    let logs = RunLogs(project: anchor.directory)
    return [
        ValidateStage(engine: doctor, checkIDs: IOSUpValidation.checkIDs),
        DependenciesStage(anchor: anchor, runner: runner),
        DeviceStage(
            declared: config.configuration?.device, lookup: lookup, runner: runner, locator: locator
        ),
        // Before build on purpose: Metro warms up while xcodebuild spends its minutes.
        MetroStage(anchor: anchor, runner: runner, logs: logs),
        BuildStage(config: config, runner: runner, locator: locator, note: note),
        InstallStage(runner: runner, locator: locator, logs: logs),
        LaunchStage(runner: runner, locator: locator, settle: settle),
    ]
}

/// Which of doctor's Checks gate an iOS build, named one by one.
///
/// "Everything doctor registered" would have been shorter and wrong: the day a
/// host or Android Check joins doctor, it would start gating `mobile up` on a
/// simulator without anyone deciding that. A Check enters this list by being
/// written into it.
public enum IOSUpValidation {
    public static let checkIDs: Set<String> = [
        // Host and matrix — can this machine build for iOS at all.
        "xcode.installed",
        "xcode.version",
        "simulator.daemon",
        "simulator.runtime",
        // mobile.yml — the declarations device and build stages will read.
        "config.syntax",
        "config.values",
        // The project and the toolchain its own declarations pin.
        "project.detected",
        "node.version",
        "package-manager.version",
        "cocoapods.version",
        "ruby.version",
    ]
}

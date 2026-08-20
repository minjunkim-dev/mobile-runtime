import Core

/// The Stages `up` runs on iOS, in pipeline order. Assembling them lives next to
/// the Stages themselves — the way `iOSChecks` owns doctor's list — so adding a
/// Stage is never a CLI edit.
/// - Parameter note: where a Stage that is still working writes its elapsed line.
///   Only `build` takes long enough to need one.
/// - Parameter readinessWait: the upper bound for observing Metro after launch.
public func iOSUpStages(
    anchor: ProjectAnchor,
    doctor: DoctorEngine,
    config: ConfigContext,
    lookup: MatrixLookup?,
    runner: any ProcessRunner,
    locator: XcodeLocator,
    readinessWait: Duration = LaunchStage.defaultReadinessWait,
    note: @escaping @Sendable (String) -> Void
) -> [any Stage] {
    [
        ValidateStage(
            engine: doctor,
            checkIDs: IOSUpValidation.checkIDs,
            promoteToError: IOSUpValidation.promotesToError
        ),
        DependenciesStage(anchor: anchor, runner: runner),
        DeviceStage(
            declared: config.configuration?.device, lookup: lookup, runner: runner, locator: locator
        ),
        // Before build on purpose: Metro warms up while xcodebuild spends its minutes.
        MetroStage(anchor: anchor, runner: runner),
        BuildStage(config: config, runner: runner, locator: locator, note: note),
        InstallStage(runner: runner, locator: locator, logs: RunLogs(project: anchor.directory)),
        LaunchStage(
            project: anchor.directory, runner: runner, locator: locator, readinessWait: readinessWait
        ),
    ]
}

/// Which of doctor's Checks gate an iOS build, named one by one.
///
/// "Everything doctor registered" would have been shorter and wrong: the day a
/// host or Android Check joins doctor, it would start gating `mobile up` on a
/// simulator without anyone deciding that. A Check enters this list by being
/// written into it.
public enum IOSUpValidation {
    static func promotesToError(_ result: CheckResult) -> Bool {
        ConfigValuesCheck.isUndecidedScheme(result)
    }

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

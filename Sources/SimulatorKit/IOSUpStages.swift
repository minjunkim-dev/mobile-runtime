import Core

public enum IOSWorkflow: Sendable {
    case build
    case up
}

/// The Stages an iOS workflow runs, in pipeline order. Assembling both workflows
/// here keeps `build` a strict subset of `up` instead of letting two CLI lists drift.
/// - Parameter note: where a Stage that is still working writes its elapsed line.
///   Only `build` takes long enough to need one.
/// - Parameter readinessWait: the upper bound for observing Metro after launch.
public func iOSStages(
    workflow: IOSWorkflow,
    anchor: ProjectAnchor,
    doctor: DoctorEngine,
    config: ConfigContext,
    lookup: MatrixLookup?,
    hostRunner: any ProcessRunner,
    projectRunner: any ProcessRunner,
    locator: XcodeLocator,
    readinessWait: Duration = LaunchStage.defaultReadinessWait,
    note: @escaping @Sendable (String) -> Void
) -> [any Stage] {
    var stages: [any Stage] = [
        ValidateStage(
            engine: doctor,
            checkIDs: IOSWorkflowValidation.checkIDs,
            promoteToError: IOSWorkflowValidation.promotesToError
        ),
        DependenciesStage(anchor: anchor, runner: projectRunner),
        DeviceStage(
            declared: config.configuration?.device,
            lookup: lookup,
            runner: hostRunner,
            locator: locator
        ),
    ]
    if case .up = workflow {
        // Before build on purpose: Metro warms up while xcodebuild spends its minutes.
        stages.append(MetroStage(anchor: anchor, runner: projectRunner))
    }
    stages.append(BuildStage(config: config, runner: projectRunner, locator: locator, note: note))
    if case .up = workflow {
        stages.append(InstallStage(
            runner: hostRunner, locator: locator, logs: RunLogs(project: anchor.directory)
        ))
        stages.append(LaunchStage(
            project: anchor.directory,
            runner: hostRunner,
            metroRunner: projectRunner,
            locator: locator,
            readinessWait: readinessWait
        ))
    }
    return stages
}

/// Which of doctor's Checks gate an iOS build, named one by one.
///
/// "Everything doctor registered" would have been shorter and wrong: the day a
/// host or Android Check joins doctor, it would start gating `mobile up` on a
/// simulator without anyone deciding that. A Check enters this list by being
/// written into it.
public enum IOSWorkflowValidation {
    static func promotesToError(_ result: CheckResult) -> Bool {
        ConfigValuesCheck.isUndecidedScheme(result)
    }

    public static let checkIDs: Set<String> = [
        // Host and matrix — can this machine build for iOS at all.
        "xcode.installed",
        "xcode.ready",
        "host.workspace-access",
        "host.storage",
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

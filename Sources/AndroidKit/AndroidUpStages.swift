import Core
import Foundation

struct AndroidRuntimeStage: Stage {
    let id: String
    let operation: @Sendable (inout UpContext) async throws -> StageOutcome

    func run(_ context: inout UpContext) async throws -> StageOutcome {
        try await operation(&context)
    }
}

actor AndroidRuntime {
    private struct RunningEmulator: Sendable, Equatable {
        let serial: String
        let avd: String
        let adbState: String
    }

    private let anchor: ProjectAnchor
    private let config: ConfigContext
    private let hostRunner: any ProcessRunner
    private let projectRunner: any ProcessRunner
    private let logs: RunLogs
    private let store: AndroidActiveRunStore
    private let timeouts: AndroidRuntimeTimeouts
    private let doctorContext: AndroidDoctorContext
    private var activeRun: AndroidActiveRun?

    init(
        anchor: ProjectAnchor,
        config: ConfigContext,
        hostRunner: any ProcessRunner,
        projectRunner: any ProcessRunner,
        environment: AndroidEnvironment,
        logs: RunLogs,
        timeouts: AndroidRuntimeTimeouts
    ) {
        self.anchor = anchor
        self.config = config
        self.hostRunner = hostRunner
        self.projectRunner = projectRunner
        self.logs = logs
        self.store = AndroidActiveRunStore(project: anchor.directory, logs: logs)
        self.timeouts = timeouts
        self.doctorContext = AndroidDoctorContext(
            anchor: anchor,
            config: config,
            hostRunner: hostRunner,
            projectRunner: projectRunner,
            environment: environment
        )
    }

    func device(for product: AndroidBuiltProduct) async throws -> AndroidDevice {
        try prepare(product)
        if let existing = try run().device {
            if let requested = config.configuration?.androidAVD, requested != existing.avd {
                throw DomainError(summary: "selected AVD differs from the Android active run",
                                  remediation: retryDown)
            }
            guard let serial = existing.serial, let api = existing.api, let abi = existing.abi else {
                throw DomainError(
                    summary: "the Android active run has an incomplete Emulator identity",
                    remediation: retryDown
                )
            }
            let ready = try await awaitReady(
                avd: existing.avd,
                expectedSerial: serial,
                product: product,
                deadline: ContinuousClock.now + timeouts.boot
            )
            guard ready.api == api, ready.abi == abi else {
                throw DomainError(
                    summary: "the active-run Emulator identity changed",
                    observed: "recorded API \(api) ABI \(abi), now API \(ready.api) ABI \(ready.abi)",
                    remediation: retryDown
                )
            }
            return AndroidDevice(
                avd: existing.avd,
                serial: serial,
                api: api,
                abi: abi,
                state: existing.state
            )
        }

        let sdk = try sdkRoot()
        let installed = try await installedAVDs(sdk: sdk, product: product)
        let running = try await runningEmulators(sdk: sdk)
        let selected = try selectAVD(installed: installed, running: running)

        if let emulator = selected.running {
            var value = try run()
            value.device = AndroidActiveRun.Device(
                avd: selected.avd.name,
                launcherPID: nil,
                serial: emulator.serial,
                api: nil,
                abi: nil,
                state: .reused
            )
            try save(value)
        } else {
            let command = doctorContext.toolCommand(
                "emulator", ["-avd", selected.avd.name], sdk: sdk
            )
            let log = logs.url("android-emulator.log")
            let pid = try await hostRunner.spawnDetached(command, logFile: log)
            var value = try run()
            value.device = AndroidActiveRun.Device(
                avd: selected.avd.name,
                launcherPID: pid,
                serial: nil,
                api: nil,
                abi: nil,
                state: .started
            )
            do {
                try save(value)
            } catch {
                _ = try? await hostRunner.run(
                    ProcessCommand("kill", ["-TERM", "\(pid)"], timeout: .seconds(10))
                )
                throw error
            }
        }

        let current = try requireDevice(run().device)
        let ready = try await awaitReady(
            avd: current.avd,
            expectedSerial: current.serial,
            product: product,
            deadline: ContinuousClock.now + timeouts.boot
        )
        var value = try run()
        value.device?.serial = ready.serial
        value.device?.api = ready.api
        value.device?.abi = ready.abi
        try save(value)
        let state = try requireDevice(value.device).state
        return AndroidDevice(
            avd: current.avd,
            serial: ready.serial,
            api: ready.api,
            abi: ready.abi,
            state: state
        )
    }

    func install(_ product: AndroidBuiltProduct, on device: AndroidDevice) async throws {
        var value = try run()
        if let existing = value.app,
            existing.serial != device.serial || existing.applicationId != product.applicationId
        {
            throw DomainError(
                summary: "the Android active run belongs to another installed app target",
                remediation: retryDown
            )
        }

        let sdk = try sdkRoot()
        let command = adb(
            ["-s", device.serial, "install", "-r", product.apkPath],
            sdk: sdk,
            timeout: timeouts.install
        )
        let result = try await hostRunner.run(command)
        guard result.terminationStatus.isSuccess else {
            throw DomainError(
                summary: "installing the Android APK failed",
                observed: result.combinedOutput.lastLines(10),
                remediation: Remediation(
                    summary: "Fix the reported adb install error and retry; mobile does not uninstall or clear app data.",
                    command: command.description
                )
            )
        }

        value = try run()
        value.app = AndroidActiveRun.App(
            serial: device.serial,
            applicationId: product.applicationId,
            launched: value.app?.launched ?? false,
            pid: value.app?.pid
        )
        try save(value)

        let path = try await hostRunner.run(adb(
            ["-s", device.serial, "shell", "pm", "path", product.applicationId], sdk: sdk
        ))
        guard path.terminationStatus.isSuccess,
            path.standardOutput.split(separator: "\n").contains(where: { $0.hasPrefix("package:") })
        else {
            throw DomainError(
                summary: "adb could not verify the installed Android package",
                observed: path.combinedOutput.lastLines(8),
                remediation: retryDown
            )
        }
        try await requireResolvedLauncher(product, serial: device.serial, sdk: sdk)
    }

    func metro(afterReinstall: Bool = false) async throws -> MetroProcess {
        var value = try run()
        if let existing = value.metro {
            switch existing.state {
            case .reused:
                let verdict = try await MetroVerdict.ask(anchor: anchor.directory, runner: projectRunner)
                if case .mine = verdict {
                    return MetroProcess(state: .reused)
                }
                if case .empty = verdict {
                    value.metro = nil
                    try save(value)
                } else if let blocker = verdict.blocker {
                    throw blocker
                }
            case .spawned:
                guard let listener = existing.listenerPID,
                    try await currentListener() == listener,
                    try await MetroVerdict.ask(anchor: anchor.directory, runner: projectRunner) == .mine
                else {
                    throw DomainError(
                        summary: "the active-run Metro identity can no longer be confirmed",
                        remediation: retryDown
                    )
                }
                return MetroProcess(
                    state: .spawned,
                    pid: existing.startPID,
                    listenerPid: listener,
                    logPath: existing.logPath
                )
            }
        }

        let verdict = try await MetroVerdict.ask(anchor: anchor.directory, runner: projectRunner)
        if let blocker = verdict.blocker { throw blocker }
        if case .mine = verdict {
            value = try run()
            value.metro = AndroidActiveRun.Metro(
                state: .reused, startPID: nil, listenerPID: nil, logPath: nil
            )
            try save(value)
            return MetroProcess(state: .reused)
        }

        let log = logs.url("metro.log")
        if afterReinstall { await MetroStage.dropWatchmanWatch(of: anchor.directory, runner: projectRunner) }
        let command = anchor.startProcess
        let startPID = try await projectRunner.spawnDetached(command, logFile: log)
        value = try run()
        value.metro = AndroidActiveRun.Metro(
            state: .spawned,
            startPID: startPID,
            listenerPID: nil,
            logPath: log.path
        )
        do {
            try save(value)
        } catch {
            _ = try? await projectRunner.run(
                ProcessCommand("kill", ["-TERM", "\(startPID)"], timeout: .seconds(10))
            )
            throw error
        }

        let deadline = ContinuousClock.now + timeouts.metroBind
        while true {
            if let listener = try await currentListener() {
                let observed = try await MetroVerdict.ask(
                    anchor: anchor.directory, runner: projectRunner
                )
                if case .mine = observed {
                    value = try run()
                    value.metro?.listenerPID = listener
                    try save(value)
                    return MetroProcess(
                        state: .spawned,
                        pid: startPID,
                        listenerPid: listener,
                        logPath: log.path
                    )
                }
                if let blocker = observed.blocker { throw blocker }
            }
            guard try await processIsRunning(startPID) else {
                throw DomainError(
                    summary: "Metro exited before listening on \(MetroVerdict.port)",
                    remediation: Remediation(
                        summary: "Inspect the Metro log at \(log.path).",
                        command: command.description
                    )
                )
            }
            guard ContinuousClock.now < deadline else {
                throw DomainError(
                    summary: "Metro did not listen on \(MetroVerdict.port) within \(timeouts.metroBind)",
                    remediation: Remediation(
                        summary: "Inspect the Metro log at \(log.path).",
                        command: command.description
                    )
                )
            }
            try await pause()
        }
    }

    func reverse(on device: AndroidDevice) async throws -> AndroidReverse {
        let sdk = try sdkRoot()
        var value = try run()
        if let existing = value.reverse, existing.serial != device.serial {
            throw DomainError(
                summary: "the Android active run has an adb reverse for another Emulator",
                remediation: retryDown
            )
        }

        let mappings = try await reverseMappings(serial: device.serial, sdk: sdk)
        let source = "tcp:\(MetroVerdict.port)"
        if let target = mappings[source], target != source {
            throw DomainError(
                summary: "adb reverse \(source) already points to \(target)",
                remediation: Remediation(
                    summary: "Preserve the existing mapping and choose how it should be reconciled."
                )
            )
        }
        if mappings[source] == source {
            let state = value.reverse?.state ?? .reused
            value.reverse = AndroidActiveRun.Reverse(serial: device.serial, state: state)
            try save(value)
            return AndroidReverse(state: state)
        }

        let create = adb(
            ["-s", device.serial, "reverse", source, source], sdk: sdk
        )
        let created = try await hostRunner.run(create)
        guard created.terminationStatus.isSuccess else {
            throw DomainError(
                summary: "creating adb reverse for Metro failed",
                observed: created.combinedOutput.lastLines(8),
                remediation: Remediation(
                    summary: "Fix the reported adb reverse error; mobile will not overwrite another mapping.",
                    command: create.description
                )
            )
        }
        value = try run()
        value.reverse = AndroidActiveRun.Reverse(serial: device.serial, state: .created)
        do {
            try save(value)
        } catch {
            if let mappings = try? await reverseMappings(serial: device.serial, sdk: sdk),
                mappings[source] == source
            {
                _ = try? await hostRunner.run(adb(
                    ["-s", device.serial, "reverse", "--remove", source], sdk: sdk
                ))
            }
            throw error
        }
        guard try await reverseMappings(serial: device.serial, sdk: sdk)[source] == source else {
            throw DomainError(
                summary: "adb reverse did not retain the Metro mapping",
                remediation: retryDown
            )
        }
        return AndroidReverse(state: .created)
    }

    func launch(_ product: AndroidBuiltProduct, on device: AndroidDevice) async throws -> Int32 {
        let sdk = try sdkRoot()
        guard let app = try run().app,
            app.serial == device.serial,
            app.applicationId == product.applicationId
        else {
            throw AndroidStateError("the installed Android app record is missing")
        }
        let forceStop = adb(
            ["-s", device.serial, "shell", "am", "force-stop", product.applicationId],
            sdk: sdk
        )
        let stopped = try await hostRunner.run(forceStop)
        guard stopped.terminationStatus.isSuccess else {
            throw DomainError(
                summary: "the existing Android app process could not be stopped before launch",
                observed: stopped.combinedOutput.lastLines(8),
                remediation: retryDown
            )
        }

        let component = "\(product.applicationId)/\(product.launcherActivity)"
        let deadline = ContinuousClock.now + timeouts.launch
        let start = adb(
            ["-s", device.serial, "shell", "am", "start", "-W", "-n", component],
            sdk: sdk,
            timeout: timeouts.launch
        )
        let started = try await hostRunner.run(start)
        guard started.terminationStatus.isSuccess else {
            throw DomainError(
                summary: "launching the Android app failed",
                observed: started.combinedOutput.lastLines(10),
                remediation: Remediation(
                    summary: "Fix the reported Activity Manager error and retry.",
                    command: start.description
                )
            )
        }
        var value = try run()
        value.app?.launched = true
        value.app?.pid = nil
        do {
            try save(value)
        } catch {
            _ = try? await hostRunner.run(forceStop)
            throw error
        }
        try await requireResolvedLauncher(product, serial: device.serial, sdk: sdk)

        while true {
            if let pid = try await launchedPID(
                product: product, serial: device.serial, sdk: sdk
            ) {
                value = try run()
                value.app?.pid = pid
                try save(value)
                return pid
            }
            guard ContinuousClock.now < deadline else {
                throw DomainError(
                    summary: "the Android app did not become launch-ready within \(timeouts.launch)",
                    remediation: retryDown
                )
            }
            try await pause()
        }
    }

    private func launchedPID(
        product: AndroidBuiltProduct, serial: String, sdk: URL
    ) async throws -> Int32? {
        let pidResult = try await hostRunner.run(adb(
            ["-s", serial, "shell", "pidof", product.applicationId], sdk: sdk
        ))
        guard pidResult.terminationStatus.isSuccess,
            let pid = pidResult.standardOutput.split(whereSeparator: \.isWhitespace)
                .compactMap({ Int32($0) }).first
        else { return nil }
        let activities = try await hostRunner.run(adb(
            ["-s", serial, "shell", "dumpsys", "activity", "activities"], sdk: sdk
        ))
        guard activities.terminationStatus.isSuccess,
            activities.standardOutput.contains(product.applicationId),
            activities.standardOutput.contains(product.launcherActivity)
        else { return nil }
        let source = "tcp:\(MetroVerdict.port)"
        guard try await reverseMappings(serial: serial, sdk: sdk)[source] == source,
            try await MetroVerdict.ask(anchor: anchor.directory, runner: projectRunner) == .mine
        else { return nil }
        return pid
    }

    private func reverseMappings(serial: String, sdk: URL) async throws -> [String: String] {
        let result = try await hostRunner.run(adb(
            ["-s", serial, "reverse", "--list"], sdk: sdk
        ))
        guard result.terminationStatus.isSuccess else {
            throw AndroidStateError("adb reverse --list could not be observed")
        }
        return result.standardOutput.split(separator: "\n").reduce(into: [:]) { mappings, line in
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 2 else { return }
            mappings[fields[fields.count - 2]] = fields[fields.count - 1]
        }
    }

    private func currentListener() async throws -> Int32? {
        let result = try await projectRunner.run(
            ProcessCommand(
                "lsof", MetroVerdict.listenerArguments + ["-t"], timeout: .seconds(10)
            )
        )
        return result.standardOutput.split(separator: "\n")
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }.first
    }

    private func processIsRunning(_ pid: Int32) async throws -> Bool {
        try await projectRunner.run(
            ProcessCommand("kill", ["-0", "\(pid)"], timeout: .seconds(10))
        ).terminationStatus.isSuccess
    }

    private func prepare(_ product: AndroidBuiltProduct) throws {
        if activeRun != nil { return }
        if let existing = try store.read() {
            guard existing.matches(
                project: anchor.directory,
                product: product,
                avdSelector: config.configuration?.androidAVD
            ) else {
                throw DomainError(
                    summary: "another Android target already has an active run for this project",
                    remediation: retryDown
                )
            }
            activeRun = existing
        } else {
            activeRun = AndroidActiveRun(
                project: anchor.directory,
                product: product,
                avdSelector: config.configuration?.androidAVD
            )
        }
    }

    private func run() throws -> AndroidActiveRun {
        guard let activeRun else {
            throw AndroidStateError("the Android active run has not been prepared")
        }
        return activeRun
    }

    private func save(_ run: AndroidActiveRun) throws {
        try store.write(run)
        activeRun = run
    }

    private func sdkRoot() throws -> URL {
        switch doctorContext.sdkRoot() {
        case .resolved(let sdk, _): return sdk
        case .conflict(let reason), .missing(let reason):
            throw DomainError(
                summary: reason,
                remediation: Remediation(
                    summary: "Make android/local.properties sdk.dir and ANDROID_HOME name one installed SDK."
                )
            )
        }
    }

    private func installedAVDs(
        sdk: URL, product: AndroidBuiltProduct
    ) async throws -> [AndroidAVD] {
        guard let minSDK = Int(product.minSdk) else {
            throw DomainError(
                summary: "the built APK has an unreadable minSdk",
                remediation: Remediation(
                    summary: "Fix the evaluated variant minSdk and rebuild the APK."
                )
            )
        }
        let listed = try await hostRunner.run(
            doctorContext.toolCommand("emulator", ["-list-avds"], sdk: sdk)
        )
        guard listed.terminationStatus.isSuccess else {
            throw AndroidStateError("emulator -list-avds could not be observed")
        }
        let names = listed.standardOutput.split(separator: "\n").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        let avds = doctorContext.avds(names: names, sdk: sdk)
        let compatible = avds.filter { avd in
            guard let api = avd.apiLevel, api >= minSDK,
                let abi = avd.abi,
                avd.config != nil,
                avd.systemImagePresent
            else { return false }
            return product.abis.contains(abi)
        }
        guard !compatible.isEmpty else {
            let observed = avds.isEmpty
                ? "no existing AVDs"
                : avds.map {
                    "\($0.name) API \($0.apiLevel.map(String.init) ?? "unknown") "
                        + "ABI \($0.abi ?? "unknown")"
                }.sorted().joined(separator: ", ")
            throw DomainError(
                summary: "no existing AVD is compatible with the built APK",
                observed: observed,
                remediation: Remediation(
                    summary: "Select an existing AVD with API >= \(minSDK) and one of "
                        + "\(product.abis.joined(separator: ", ")); mobile will not provision it."
                )
            )
        }
        return compatible
    }

    private func selectAVD(
        installed: [AndroidAVD], running: [RunningEmulator]
    ) throws -> (avd: AndroidAVD, running: RunningEmulator?) {
        let declared = config.configuration?.androidAVD
        let candidates = declared.map { name in installed.filter { $0.name == name } } ?? installed
        guard !candidates.isEmpty else {
            throw DomainError(
                summary: declared.map { "android.avd names \($0), but it is not compatible" }
                    ?? "no existing AVD is compatible with the built APK",
                remediation: Remediation(
                    summary: "Select or create a compatible AVD explicitly; mobile will not provision one."
                )
            )
        }
        let runningCandidates = running.filter { emulator in
            candidates.contains { $0.name == emulator.avd }
        }
        if runningCandidates.count == 1, let emulator = runningCandidates.first,
            let avd = candidates.first(where: { $0.name == emulator.avd })
        {
            return (avd, emulator)
        }
        if runningCandidates.count > 1 {
            throw selectorError("running", runningCandidates.map(\.avd))
        }
        guard candidates.count == 1, let avd = candidates.first else {
            throw selectorError("installed", candidates.map(\.name))
        }
        return (avd, nil)
    }

    private func selectorError(_ kind: String, _ names: [String]) -> DomainError {
        DomainError(
            summary: "multiple compatible \(kind) AVDs: \(names.sorted().joined(separator: ", "))",
            remediation: Remediation(summary: "Set android.avd to one compatible AVD in mobile.yml.")
        )
    }

    private func runningEmulators(sdk: URL) async throws -> [RunningEmulator] {
        let devices = try await hostRunner.run(adb(["devices"], sdk: sdk))
        guard devices.terminationStatus.isSuccess else {
            throw AndroidStateError("adb devices could not be observed")
        }
        var result: [RunningEmulator] = []
        for line in devices.standardOutput.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2, fields[0].hasPrefix("emulator-") else { continue }
            let serial = String(fields[0])
            let identity = try await hostRunner.run(adb(
                ["-s", serial, "emu", "avd", "name"], sdk: sdk
            ))
            guard identity.terminationStatus.isSuccess,
                let avd = androidAVDName(from: identity.standardOutput),
                !avd.isEmpty
            else {
                throw AndroidStateError("running emulator \(serial) has no readable AVD identity")
            }
            result.append(RunningEmulator(serial: serial, avd: avd, adbState: String(fields[1])))
        }
        return result
    }

    private func awaitReady(
        avd: String,
        expectedSerial: String?,
        product: AndroidBuiltProduct,
        deadline: ContinuousClock.Instant
    ) async throws -> (serial: String, api: Int, abi: String) {
        let sdk = try sdkRoot()
        while true {
            let running = try await runningEmulators(sdk: sdk).filter { $0.avd == avd }
            if running.count == 1, let emulator = running.first,
                expectedSerial == nil || expectedSerial == emulator.serial,
                emulator.adbState == "device",
                let ready = try await readyIdentity(serial: emulator.serial, sdk: sdk, product: product)
            {
                return (emulator.serial, ready.api, ready.abi)
            }
            guard ContinuousClock.now < deadline else {
                throw DomainError(
                    summary: "Android Emulator \(avd) did not become ready within \(timeouts.boot)",
                    remediation: Remediation(
                        summary: "Inspect the selected existing AVD; mobile will not replace or recreate it."
                    )
                )
            }
            try await pause()
        }
    }

    private func readyIdentity(
        serial: String, sdk: URL, product: AndroidBuiltProduct
    ) async throws -> (api: Int, abi: String)? {
        let booted = try await hostRunner.run(adb(
            ["-s", serial, "shell", "getprop", "sys.boot_completed"], sdk: sdk
        ))
        guard booted.terminationStatus.isSuccess,
            booted.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
        else { return nil }
        let apiResult = try await hostRunner.run(adb(
            ["-s", serial, "shell", "getprop", "ro.build.version.sdk"], sdk: sdk
        ))
        let abiResult = try await hostRunner.run(adb(
            ["-s", serial, "shell", "getprop", "ro.product.cpu.abilist"], sdk: sdk
        ))
        let packages = try await hostRunner.run(adb(
            ["-s", serial, "shell", "pm", "path", "android"], sdk: sdk
        ))
        guard apiResult.terminationStatus.isSuccess,
            abiResult.terminationStatus.isSuccess,
            packages.terminationStatus.isSuccess,
            packages.standardOutput.contains("package:"),
            let api = Int(apiResult.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)),
            let minSDK = Int(product.minSdk), api >= minSDK
        else { return nil }
        let abis = abiResult.standardOutput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ",").map(String.init)
        guard let abi = abis.first(where: product.abis.contains) else { return nil }
        return (api, abi)
    }

    private func requireResolvedLauncher(
        _ product: AndroidBuiltProduct, serial: String, sdk: URL
    ) async throws {
        let resolved = try await hostRunner.run(adb(
            [
                "-s", serial, "shell", "cmd", "package", "resolve-activity", "--brief",
                "-a", "android.intent.action.MAIN",
                "-c", "android.intent.category.LAUNCHER",
                product.applicationId,
            ],
            sdk: sdk
        ))
        guard resolved.terminationStatus.isSuccess,
            normalizedActivity(resolved.standardOutput, applicationId: product.applicationId)
                == product.launcherActivity
        else {
            throw DomainError(
                summary: "the installed package launcher does not match the built APK",
                observed: resolved.combinedOutput.lastLines(8),
                remediation: retryDown
            )
        }
    }

    private func normalizedActivity(_ output: String, applicationId: String) -> String? {
        guard let component = output.split(separator: "\n").last.map(String.init),
            let slash = component.firstIndex(of: "/")
        else { return nil }
        let activity = String(component[component.index(after: slash)...])
        if activity.hasPrefix(".") { return applicationId + activity }
        return activity.contains(".") ? activity : applicationId + "." + activity
    }

    private func adb(
        _ arguments: [String], sdk: URL, timeout: Duration = .seconds(15)
    ) -> ProcessCommand {
        doctorContext.toolCommand("adb", arguments, sdk: sdk, timeout: timeout)
    }

    private func pause() async throws {
        if timeouts.poll > .zero { try await Task.sleep(for: timeouts.poll) }
    }

    private func requireDevice(_ value: AndroidActiveRun.Device?) throws -> AndroidActiveRun.Device {
        guard let value else { throw AndroidStateError("the Android Emulator record disappeared") }
        return value
    }

    private var retryDown: Remediation {
        Remediation(
            summary: "Preserve the recorded resources and retry ownership cleanup.",
            command: "mobile down --platform android"
        )
    }
}

public func androidUpStages(
    anchor: ProjectAnchor,
    doctor: DoctorEngine,
    config: ConfigContext,
    hostRunner: any ProcessRunner,
    projectRunner: any ProcessRunner,
    environment: AndroidEnvironment = AndroidEnvironment(),
    logs: RunLogs? = nil,
    timeouts: AndroidRuntimeTimeouts = AndroidRuntimeTimeouts(),
    note: @escaping @Sendable (String) -> Void
) -> [any Stage] {
    let logs = logs ?? RunLogs(project: anchor.directory)
    let runtime = AndroidRuntime(
        anchor: anchor,
        config: config,
        hostRunner: hostRunner,
        projectRunner: projectRunner,
        environment: environment,
        logs: logs,
        timeouts: timeouts
    )
    return androidBuildStages(
        anchor: anchor,
        doctor: doctor,
        config: config,
        hostRunner: hostRunner,
        projectRunner: projectRunner,
        environment: environment,
        validationCheckIDs: AndroidUpValidation.checkIDs,
        note: note
    ) + [
        AndroidRuntimeStage(id: "android.device") { context in
            guard var product = context.androidProduct else {
                throw AndroidStateError("android.device requires android.build output")
            }
            let device = try await runtime.device(for: product)
            product.device = device
            context.androidProduct = product
            return device.state == .started
                ? .pass("started \(device.avd) — \(device.serial)")
                : .skipped("reused \(device.avd) — \(device.serial)")
        },
        AndroidRuntimeStage(id: "android.install") { context in
            guard let product = context.androidProduct, let device = product.device else {
                throw AndroidStateError("android.install requires a selected Emulator")
            }
            try await runtime.install(product, on: device)
            return .pass(product.applicationId)
        },
        AndroidRuntimeStage(id: "metro") { context in
            let metro = try await runtime.metro(afterReinstall: context.nodeModulesReinstalled)
            context.metro = metro
            return metro.state == .spawned
                ? .pass("started on \(MetroVerdict.port) — pid \(metro.listenerPid ?? 0)")
                : .skipped("already running on \(MetroVerdict.port)")
        },
        AndroidRuntimeStage(id: "android.reverse") { context in
            guard var product = context.androidProduct, let device = product.device else {
                throw AndroidStateError("android.reverse requires a selected Emulator")
            }
            let reverse = try await runtime.reverse(on: device)
            product.reverse = reverse
            context.androidProduct = product
            return reverse.state == .created
                ? .pass("tcp:\(MetroVerdict.port)")
                : .skipped("tcp:\(MetroVerdict.port) already mapped")
        },
        AndroidRuntimeStage(id: "android.launch") { context in
            guard var product = context.androidProduct, let device = product.device else {
                throw AndroidStateError("android.launch requires a selected Emulator")
            }
            let pid = try await runtime.launch(product, on: device)
            product.appPid = pid
            context.androidProduct = product
            return .pass("\(product.applicationId) — pid \(pid)")
        },
    ]
}

public func runAndroidUp(
    anchor: ProjectAnchor,
    doctor: DoctorEngine,
    config: ConfigContext,
    hostRunner: any ProcessRunner,
    projectRunner: any ProcessRunner,
    environment: AndroidEnvironment = AndroidEnvironment(),
    logs: RunLogs? = nil,
    timeouts: AndroidRuntimeTimeouts = AndroidRuntimeTimeouts(),
    note: @escaping @Sendable (String) -> Void,
    onStageFinished: (@Sendable (StageResult) -> Void)? = nil,
    onStageStarted: (@Sendable (String) -> Void)? = nil
) async -> UpReport {
    let logs = logs ?? RunLogs(project: anchor.directory)
    let store = AndroidActiveRunStore(project: anchor.directory, logs: logs)
    do {
        let lease = try store.acquire(operation: "up")
        defer { withExtendedLifetime(lease) {} }
        if let requested = config.configuration?.androidAVD,
            let active = try store.read(), let device = active.device, device.avd != requested {
            throw DomainError(summary: "selected AVD differs from the Android active run",
                              remediation: Remediation(summary: "Run mobile down --platform android for this project before selecting another AVD."))
        }
        let stages = androidUpStages(
            anchor: anchor,
            doctor: doctor,
            config: config,
            hostRunner: hostRunner,
            projectRunner: projectRunner,
            environment: environment,
            logs: logs,
            timeouts: timeouts,
            note: note
        )
        let report = await UpPipeline(stages: stages).run(
            onStageFinished: onStageFinished, onStageStarted: onStageStarted
        )
        guard report.failure != nil, report.context.androidProduct != nil else { return report }

        let cleanup = await Task.detached { await AndroidCleanup(
            anchor: anchor,
            config: config,
            runner: hostRunner,
            projectRunner: projectRunner,
            environment: environment,
            logs: logs,
            timeouts: timeouts
        ).run() }.value
        var context = report.context
        var product = context.androidProduct
        product?.rollback = cleanup.report.items
        context.androidProduct = product
        context.androidRollbackExitCode = cleanup.report.exitCode
        context.androidRequiresTeardown = cleanup.hasRemainingRecord
        return UpReport(stages: report.stages, context: context, failure: report.failure)
    } catch let error as DomainError {
        return UpReport(stages: [], failure: .domain(error))
    } catch {
        return UpReport(stages: [], failure: .tool("android.lifecycle: \(error)"))
    }
}

import Core
import Foundation

struct AndroidCleanup: Sendable {
    private enum DeviceVerification {
        case absent
        case verified
        case blocked(TeardownItem)
    }

    struct Result: Sendable {
        let report: TeardownReport
        let hasRemainingRecord: Bool
    }

    private let anchor: ProjectAnchor
    private let runner: any ProcessRunner
    private let projectRunner: any ProcessRunner
    private let timeouts: AndroidRuntimeTimeouts
    private let store: AndroidActiveRunStore
    private let doctorContext: AndroidDoctorContext

    init(
        anchor: ProjectAnchor,
        config: ConfigContext,
        runner: any ProcessRunner,
        projectRunner: any ProcessRunner,
        environment: AndroidEnvironment,
        logs: RunLogs,
        timeouts: AndroidRuntimeTimeouts
    ) {
        self.anchor = anchor
        self.runner = runner
        self.projectRunner = projectRunner
        self.timeouts = timeouts
        self.store = AndroidActiveRunStore(project: anchor.directory, logs: logs, operation: .down)
        self.doctorContext = AndroidDoctorContext(
            anchor: anchor,
            config: config,
            hostRunner: runner,
            projectRunner: projectRunner,
            environment: environment
        )
    }

    func run() async -> Result {
        let ids = ["android.app", "android.adb.reverse", "metro", "android.emulator"]
        let original: AndroidActiveRun?
        do {
            if anchor.framework == .reactNative { _ = try store.logs.metroPort(platform: .android) }
            original = try store.read()
        } catch {
            let message = "android.active-run: \(error)"
            return Result(
                report: TeardownReport(
                    items: ids.map { .unknown($0, "active-run record could not be read") },
                    toolFailures: [message],
                    blockedIsFailure: true
                ),
                hasRemainingRecord: true
            )
        }
        guard var active = original else {
            return Result(
                report: TeardownReport(
                    items: ids.map { .skipped($0, "no Android active run recorded") },
                    blockedIsFailure: true
                ),
                hasRemainingRecord: false
            )
        }

        var items: [TeardownItem] = []
        var toolFailures: [String] = []
        var failure: DomainError?
        for id in ids {
            do {
                try Task.checkCancellation()
                let item: TeardownItem
                switch id {
                case "android.app": item = try await cleanApp(active.app, device: active.device)
                case "android.adb.reverse":
                    item = try await cleanReverse(active.reverse, device: active.device)
                case "metro": item = try await cleanMetro(active.metro)
                default: item = try await cleanEmulator(active.device)
                }
                if item.status == .stopped || item.status == .skipped {
                    switch id {
                    case "android.app": active.app = nil
                    case "android.adb.reverse": active.reverse = nil
                    case "metro": active.metro = nil
                    default: active.device = nil
                    }
                    try store.removeIfEmpty(active)
                }
                items.append(item)
            } catch is CancellationError {
                let pending = ids.dropFirst(items.count).map { TeardownItem.unknown($0, "cancelled before cleanup completed") }
                return Result(report: TeardownReport(items: items + pending, toolFailures: toolFailures,
                                                      failure: failure, blockedIsFailure: true, cancelled: true),
                              hasRemainingRecord: true)
            } catch let error as DomainError {
                items.append(TeardownItem(id: id, status: .unknown, detail: error.message,
                                          remediation: error.remediation))
                failure = failure ?? error
            } catch {
                items.append(.unknown(id, "could not verify or update ownership state"))
                toolFailures.append("\(id): \(error)")
            }
        }
        return Result(
            report: TeardownReport(
                items: items,
                toolFailures: toolFailures,
                failure: failure,
                blockedIsFailure: true
            ),
            hasRemainingRecord: (try? store.file).map { FileManager.default.fileExists(atPath: $0.path) } ?? true
        )
    }

    private func cleanApp(
        _ app: AndroidActiveRun.App?, device: AndroidActiveRun.Device?
    ) async throws -> TeardownItem {
        guard let app else { return .skipped("android.app", "not recorded") }
        guard app.launched else {
            return .skipped("android.app", "installed package was not launched")
        }
        let sdk = try doctorContext.requiredSDKRoot()
        switch try await verifyDevice(
            device, serial: app.serial, sdk: sdk, resource: "Android app"
        ) {
        case .absent:
            return .skipped("android.app", "recorded Emulator is no longer running")
        case .blocked(let item): return item
        case .verified: break
        }
        let installed = try await runner.run(adb(
            ["-s", app.serial, "shell", "pm", "path", app.applicationId], sdk: sdk
        ))
        guard installed.terminationStatus.isSuccess,
            installed.standardOutput.contains("package:")
        else {
            return .skipped("android.app", "package is no longer installed")
        }
        let command = adb(
            ["-s", app.serial, "shell", "am", "force-stop", app.applicationId], sdk: sdk
        )
        let stopped = try await runner.run(command)
        guard stopped.terminationStatus.isSuccess else {
            return .failed(
                "android.app",
                cleanupFailure(
                    "the owned Android app did not stop",
                    observed: stopped.combinedOutput.lastLines(8)
                )
            )
        }
        let after = try await runner.run(adb(
            ["-s", app.serial, "shell", "pidof", app.applicationId], sdk: sdk
        ))
        guard !after.terminationStatus.isSuccess
            || after.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .failed(
                "android.app",
                cleanupFailure(
                    "the owned Android app is still running after force-stop",
                    observed: after.standardOutput.lastLines(4)
                )
            )
        }
        return .stopped("android.app", app.applicationId)
    }

    private func cleanReverse(
        _ reverse: AndroidActiveRun.Reverse?, device: AndroidActiveRun.Device?
    ) async throws -> TeardownItem {
        guard let reverse else { return .skipped("android.adb.reverse", "not recorded") }
        guard reverse.state == .created else {
            return .skipped("android.adb.reverse", "pre-existing mapping preserved")
        }
        let sdk = try doctorContext.requiredSDKRoot()
        switch try await verifyDevice(
            device, serial: reverse.serial, sdk: sdk, resource: "adb reverse"
        ) {
        case .absent:
            return .skipped("android.adb.reverse", "recorded Emulator is no longer running")
        case .blocked(let item): return item
        case .verified: break
        }
        let source = "tcp:\(try store.logs.metroPort(platform: .android) ?? MetroVerdict.port)"
        let mappings = try await doctorContext.reverseMappings(serial: reverse.serial, sdk: sdk, runner: runner)
        guard let current = mappings[source] else {
            return .skipped("android.adb.reverse", "mapping already absent")
        }
        guard current == source else {
            return .blocked(
                "android.adb.reverse",
                identityMismatch(
                    "the owned adb reverse mapping was replaced",
                    observed: "\(source) now points to \(current)"
                )
            )
        }
        let command = adb(
            ["-s", reverse.serial, "reverse", "--remove", source], sdk: sdk
        )
        let removed = try await runner.run(command)
        guard removed.terminationStatus.isSuccess else {
            return .failed(
                "android.adb.reverse",
                cleanupFailure(
                    "the owned adb reverse mapping could not be removed",
                    observed: removed.combinedOutput.lastLines(8)
                )
            )
        }
        guard try await doctorContext.reverseMappings(serial: reverse.serial, sdk: sdk, runner: runner)[source] == nil else {
            return .failed(
                "android.adb.reverse",
                cleanupFailure(
                    "the owned adb reverse mapping is still present",
                    observed: source
                )
            )
        }
        return .stopped("android.adb.reverse", source)
    }

    private func cleanMetro(_ metro: AndroidActiveRun.Metro?) async throws -> TeardownItem {
        guard let metro else { return .skipped("metro", "not recorded") }
        guard metro.state == .spawned else {
            return .skipped("metro", "pre-existing Metro preserved")
        }

        let startRunning = if let pid = metro.startPID {
            try await processIsRunning(pid)
        } else {
            false
        }
        let port = try store.logs.metroPort(platform: .android) ?? MetroVerdict.port
        let listener = try await MetroLaunch.listeners(runner: projectRunner, port: port).first
        if !startRunning && listener == nil {
            return .skipped("metro", "owned Metro already stopped")
        }
        var listenerToStop = metro.listenerPID
        if let recorded = metro.listenerPID {
            guard listener == recorded else {
                return .blocked(
                    "metro",
                    identityMismatch(
                        "the owned Metro listener PID changed",
                        observed: "recorded \(recorded), current \(listener.map(String.init) ?? "none")"
                    )
                )
            }
            guard try await MetroVerdict.ask(
                anchor: anchor.directory, runner: projectRunner, port: port
            ) == .mine else {
                return .blocked(
                    "metro",
                    identityMismatch(
                        "the listener no longer identifies as this project's Metro",
                        observed: "pid \(recorded)"
                    )
                )
            }
        } else if let listener {
            guard startRunning,
                try await MetroVerdict.ask(
                    anchor: anchor.directory, runner: projectRunner, port: port
                ) == .mine
            else {
                return .blocked(
                    "metro",
                    identityMismatch(
                        "an unrecorded listener appeared during Metro startup",
                        observed: "pid \(listener)"
                    )
                )
            }
            listenerToStop = listener
        }
        if let pid = metro.startPID, startRunning {
            guard try await processCWD(pid) == anchor.directory.resolvingSymlinksInPath().path else {
                return .blocked(
                    "metro",
                    identityMismatch(
                        "the recorded Metro start PID no longer belongs to this project",
                        observed: "pid \(pid)"
                    )
                )
            }
        }

        for pid in Set([listenerToStop, metro.startPID].compactMap({ $0 })) {
            _ = try await projectRunner.run(
                ProcessCommand("kill", ["-TERM", "\(pid)"], timeout: .seconds(10))
            )
        }
        try await pause()
        let listenerAfter = try await MetroLaunch.listeners(runner: projectRunner, port: port).first
        let startAfter = if let pid = metro.startPID {
            try await processIsRunning(pid)
        } else {
            false
        }
        guard listenerAfter == nil, !startAfter else {
            return .failed(
                "metro",
                cleanupFailure(
                    "the owned Metro is still running after SIGTERM",
                    observed: "listener \(listenerAfter.map(String.init) ?? "none")"
                )
            )
        }
        return .stopped("metro", metro.listenerPID.map { "pid \($0)" } ?? "start process")
    }

    private func cleanEmulator(_ device: AndroidActiveRun.Device?) async throws -> TeardownItem {
        guard let device else { return .skipped("android.emulator", "not recorded") }
        guard device.state == .started else {
            return .skipped("android.emulator", "pre-existing Emulator preserved")
        }
        guard let pid = device.launcherPID, pid > 0, device.serial?.isEmpty == false else {
            return .unknown("android.emulator", "owned Emulator absence requires its recorded serial and launcher PID")
        }
        let sdk = try doctorContext.requiredSDKRoot()
        if let serial = device.serial {
            if try await emulatorSerials(sdk: sdk).contains(serial) {
                let current = try await emulatorAVDName(serial: serial, sdk: sdk)
                guard current == device.avd else {
                    return .blocked(
                        "android.emulator",
                        identityMismatch(
                            "the owned Emulator serial now names another AVD",
                            observed: "recorded \(device.avd), current \(current)"
                        )
                    )
                }
                let command = adb(["-s", serial, "emu", "kill"], sdk: sdk)
                let stopped = try await runner.run(command)
                guard stopped.terminationStatus.isSuccess else {
                    return .failed(
                        "android.emulator",
                        cleanupFailure(
                            "the owned Emulator could not be stopped",
                            observed: stopped.combinedOutput.lastLines(8)
                        )
                    )
                }
                for _ in 0..<5 {
                    try await pause()
                    if try await emulatorSerials(sdk: sdk).contains(serial) == false {
                        return .stopped("android.emulator", "\(device.avd) — \(serial)")
                    }
                }
                return .failed(
                    "android.emulator",
                    cleanupFailure(
                        "the owned Emulator is still running",
                        observed: serial
                    )
                )
            }
        }

        guard let running = try await ownedLauncherPresence(pid) else {
            return .unknown("android.emulator", "owned Emulator launcher presence could not be confirmed")
        }
        if !running {
            return TeardownItem(id: "android.emulator", status: .skipped,
                detail: "owned Emulator already stopped", ownedRuntimeStopped: true)
        }
        let commandLine = try await processCommand(pid)
        guard commandLine.contains("emulator"), commandLine.contains("-avd \(device.avd)") else {
            return .blocked(
                "android.emulator",
                identityMismatch(
                    "the recorded Emulator launcher PID was reused",
                    observed: "pid \(pid): \(commandLine)"
                )
            )
        }
        let stopped = try await runner.run(
            ProcessCommand("kill", ["-TERM", "\(pid)"], timeout: .seconds(10))
        )
        guard stopped.terminationStatus.isSuccess else {
            return .failed("android.emulator", cleanupFailure(
                "the owned Emulator launcher could not be stopped", observed: stopped.combinedOutput.lastLines(8)))
        }
        try await pause()
        guard let runningAfter = try await ownedLauncherPresence(pid) else {
            return .unknown("android.emulator", "owned Emulator launcher presence after SIGTERM could not be confirmed")
        }
        guard !runningAfter else {
            return .failed(
                "android.emulator",
                cleanupFailure(
                    "the owned Emulator launcher is still running after SIGTERM",
                    observed: "pid \(pid)"
                )
            )
        }
        return .stopped("android.emulator", "\(device.avd) — launcher pid \(pid)")
    }

    private func ownedLauncherPresence(_ pid: Int32) async throws -> Bool? {
        let result = try await runner.run(
            ProcessCommand("ps", ["-p", "\(pid)", "-o", "pid="], timeout: .seconds(10))
        )
        guard result.standardError.isEmpty else { return nil }
        let pids = result.standardOutput.split(whereSeparator: \.isWhitespace).map(String.init)
        if case .exited(1) = result.terminationStatus, pids.isEmpty { return false }
        return result.terminationStatus.isSuccess && pids == [String(pid)] ? true : nil
    }

    private func adb(
        _ arguments: [String], sdk: URL, timeout: Duration = .seconds(15)
    ) -> ProcessCommand {
        doctorContext.toolCommand("adb", arguments, sdk: sdk, timeout: timeout)
    }

    private func processIsRunning(_ pid: Int32) async throws -> Bool {
        try await runner.run(
            ProcessCommand("kill", ["-0", "\(pid)"], timeout: .seconds(10))
        ).terminationStatus.isSuccess
    }

    private func processCWD(_ pid: Int32) async throws -> String? {
        let result = try await runner.run(
            ProcessCommand(
                "lsof", ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"],
                timeout: .seconds(10)
            )
        )
        guard result.terminationStatus.isSuccess else { return nil }
        return result.standardOutput.split(separator: "\n")
            .first(where: { $0.hasPrefix("n") })
            .map { URL(fileURLWithPath: String($0.dropFirst())).resolvingSymlinksInPath().path }
    }

    private func processCommand(_ pid: Int32) async throws -> String {
        let result = try await runner.run(
            ProcessCommand("ps", ["-p", "\(pid)", "-o", "command="], timeout: .seconds(10))
        )
        guard result.terminationStatus.isSuccess else {
            throw AndroidStateError("the Emulator launcher command could not be observed")
        }
        return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func emulatorSerials(sdk: URL) async throws -> Set<String> {
        let result = try await runner.run(adb(["devices"], sdk: sdk))
        guard result.terminationStatus.isSuccess else {
            throw AndroidStateError("adb devices could not be observed")
        }
        return Set(result.standardOutput.split(separator: "\n").compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace)
            return fields.first?.hasPrefix("emulator-") == true ? String(fields[0]) : nil
        })
    }

    private func emulatorAVDName(serial: String, sdk: URL) async throws -> String {
        let result = try await runner.run(adb(
            ["-s", serial, "emu", "avd", "name"], sdk: sdk
        ))
        guard result.terminationStatus.isSuccess,
            let name = androidAVDName(from: result.standardOutput),
            !name.isEmpty
        else {
            throw AndroidStateError("the recorded Emulator AVD identity could not be observed")
        }
        return name
    }

    private func verifyDevice(
        _ device: AndroidActiveRun.Device?,
        serial: String,
        sdk: URL,
        resource: String
    ) async throws -> DeviceVerification {
        guard let device, device.serial == serial else {
            return .blocked(.blocked(
                resource == "Android app" ? "android.app" : "android.adb.reverse",
                identityMismatch(
                    "the \(resource) has no matching Emulator ownership record",
                    observed: serial
                )
            ))
        }
        guard try await emulatorSerials(sdk: sdk).contains(serial) else { return .absent }
        let current = try await emulatorAVDName(serial: serial, sdk: sdk)
        guard current == device.avd else {
            return .blocked(.blocked(
                resource == "Android app" ? "android.app" : "android.adb.reverse",
                identityMismatch(
                    "the \(resource) serial now names another AVD",
                    observed: "recorded \(device.avd), current \(current)"
                )
            ))
        }
        return .verified
    }

    private func pause() async throws {
        if timeouts.cleanupGrace > .zero {
            try await Task.sleep(for: timeouts.cleanupGrace)
        }
    }

    private func identityMismatch(_ summary: String, observed: String) -> DomainError {
        DomainError(
            summary: summary,
            observed: observed,
            remediation: Remediation(
                summary: "Inspect the recorded identity without replacing or deleting it."
            )
        )
    }

    private func cleanupFailure(_ summary: String, observed: String) -> DomainError {
        DomainError(
            summary: summary,
            observed: observed,
            remediation: Remediation(
                summary: "The owned resource was asked to stop and remains recorded for a retry.",
                command: "mobile down --platform android"
            )
        )
    }
}

/// Read while holding the project lease, before acquiring the device lease.
public func androidTeardownDeviceKey(anchor: ProjectAnchor, logs: RunLogs? = nil) throws -> ResourceKey? {
    try AndroidActiveRunStore(project: anchor.directory, logs: logs, operation: .down).read()?.device
        .map { .device(.android, "avd:\($0.avd)") }
}

public func androidTeardown(
    anchor: ProjectAnchor,
    config: ConfigContext,
    runner: any ProcessRunner,
    projectRunner: any ProcessRunner,
    environment: AndroidEnvironment = AndroidEnvironment(),
    logs: RunLogs? = nil,
    timeouts: AndroidRuntimeTimeouts = AndroidRuntimeTimeouts()
) async -> TeardownReport {
    let logs = logs ?? RunLogs(project: anchor.directory)
    let store = AndroidActiveRunStore(project: anchor.directory, logs: logs, operation: .down)
    do {
        let lease = try store.acquire(operation: "down")
        defer { withExtendedLifetime(lease) {} }
        return await AndroidCleanup(
            anchor: anchor,
            config: config,
            runner: runner,
            projectRunner: projectRunner,
            environment: environment,
            logs: logs,
            timeouts: timeouts
        ).run().report
    } catch let error as DomainError {
        return TeardownReport(
            items: [], failure: error, blockedIsFailure: true
        )
    } catch {
        return TeardownReport(
            items: [], toolFailures: ["android.lifecycle: \(error)"], blockedIsFailure: true
        )
    }
}

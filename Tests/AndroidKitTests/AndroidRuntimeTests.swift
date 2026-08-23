import Core
import Foundation
import TestSupport
import Testing

@testable import AndroidKit

private final class ScriptedProcessState: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String: [FakeProcessRunner.Response]]
    private var commands: [ProcessCommand] = []

    init(_ responses: [String: [FakeProcessRunner.Response]]) {
        self.responses = responses
    }

    func answer(_ command: ProcessCommand) throws -> FakeProcessRunner.Response {
        try lock.withLock {
            commands.append(command)
            guard var queue = responses[command.description], let answer = queue.first else {
                throw FixtureMiss(command: command.description)
            }
            if queue.count > 1 {
                queue.removeFirst()
                responses[command.description] = queue
            }
            return answer
        }
    }

    func record(_ command: ProcessCommand) {
        lock.withLock { commands.append(command) }
    }

    var all: [ProcessCommand] { lock.withLock { commands } }
}

private struct ScriptedProcessRunner: ProcessRunner {
    let state: ScriptedProcessState
    var spawnedPID: Int32 = 7001

    func run(
        _ command: ProcessCommand,
        onLine: (@Sendable (String) -> Void)?
    ) async throws -> ProcessResult {
        let answer = try state.answer(command)
        if case .streamed = command.output {
            for line in answer.standardOutput.split(separator: "\n") { onLine?(String(line)) }
            return ProcessResult(
                terminationStatus: answer.status, standardOutput: "", standardError: ""
            )
        }
        return ProcessResult(
            terminationStatus: answer.status,
            standardOutput: answer.standardOutput,
            standardError: answer.standardError
        )
    }

    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
        state.record(command)
        return spawnedPID
    }
}

private struct RuntimeScenario {
    let repo: FixtureRepo
    let anchor: ProjectAnchor
    let config: ConfigContext
    let environment: AndroidEnvironment
    let logs: RunLogs
    let product: AndroidBuiltProduct
}

private func runtimeScenario() throws -> RuntimeScenario {
    let repo = try FixtureRepo()
    try repo.write("package.json", #"{"dependencies":{"react-native":"0.83.1"}}"#)
    try repo.directory("android")
    let sdk = try repo.directory("sdk")
    try repo.write("android/local.properties", "sdk.dir=\(sdk.path)\n")
    try repo.directory("sdk/system-images/android-35/google_apis/arm64-v8a")
    let avdHome = try repo.directory("avds")
    try repo.write(
        "avds/Pixel.avd/config.ini",
        "image.sysdir.1=system-images/android-35/google_apis/arm64-v8a/\n"
            + "abi.type=arm64-v8a\ntarget=android-35\n"
    )
    let anchor = try #require(ProjectAnchor.detect(from: repo.root))
    return RuntimeScenario(
        repo: repo,
        anchor: anchor,
        config: ConfigContext.detect(anchor: anchor, workingDirectory: repo.root),
        environment: AndroidEnvironment(values: [
            "ANDROID_HOME": sdk.path,
            "ANDROID_AVD_HOME": avdHome.path,
            "PATH": "/usr/bin:/bin",
        ]),
        logs: try .temporary(project: repo.root),
        product: AndroidBuiltProduct(
            apkPath: repo.url("app-debug.apk").path,
            module: ":app",
            variant: "debug",
            assembleTask: ":app:assembleDebug",
            applicationId: "dev.mobile.fixture",
            minSdk: "24",
            targetSdk: "35",
            abis: ["arm64-v8a"],
            launcherActivity: "dev.mobile.fixture.MainActivity"
        )
    )
}

private func command(_ executable: String, _ arguments: [String]) -> String {
    ([executable] + arguments).joined(separator: " ")
}

private let serial = "emulator-5554"
private let reverseSource = "tcp:8081"

@Suite("Android owned runtime")
struct AndroidRuntimeTests {
    @Test("lifecycle lock rejects a concurrent command and releases with its lease")
    func lifecycleLock() throws {
        let scenario = try runtimeScenario()
        let store = AndroidActiveRunStore(project: scenario.repo.root, logs: scenario.logs)
        var lease: AndroidLifecycleLease? = try store.acquire(operation: "up")

        let error = #expect(throws: DomainError.self) {
            _ = try store.acquire(operation: "down")
        }
        #expect(error?.summary.contains("already running") == true)
        lease = nil
        lease = try store.acquire(operation: "down")
        #expect(lease != nil)
    }

    @Test("up stage order keeps build as the side-effect-free prefix")
    func stageOrder() throws {
        let scenario = try runtimeScenario()
        let runner = ScriptedProcessRunner(state: ScriptedProcessState([:]))
        let stages = androidUpStages(
            anchor: scenario.anchor,
            doctor: DoctorEngine(checks: []),
            config: scenario.config,
            hostRunner: runner,
            projectRunner: runner,
            environment: scenario.environment,
            logs: scenario.logs,
            timeouts: AndroidRuntimeTimeouts(poll: .zero),
            note: { _ in }
        )

        #expect(stages.map(\.id) == [
            "validate", "dependencies", "android.build", "android.device",
            "android.install", "metro", "android.reverse", "android.launch",
        ])
        #expect(AndroidUpValidation.checkIDs.contains("android.avd"))
    }

    @Test("reuses one compatible Emulator and records install, Metro, reverse and launch ownership")
    func runsAndroidRuntimeStages() async throws {
        let scenario = try runtimeScenario()
        let responses: [String: [FakeProcessRunner.Response]] = [
            command("emulator", ["-list-avds"]): [.ok("Pixel\n")],
            command("adb", ["devices"]): [.ok("List of devices attached\n\(serial) device\n")],
            command("adb", ["-s", serial, "emu", "avd", "name"]): [.ok("Pixel\n")],
            command("adb", ["-s", serial, "shell", "getprop", "sys.boot_completed"]): [.ok("1\n")],
            command("adb", ["-s", serial, "shell", "getprop", "ro.build.version.sdk"]): [.ok("35\n")],
            command("adb", ["-s", serial, "shell", "getprop", "ro.product.cpu.abilist"]): [.ok("arm64-v8a\n")],
            command("adb", ["-s", serial, "shell", "pm", "path", "android"]): [.ok("package:/system/framework/framework-res.apk\n")],
            command("adb", ["-s", serial, "install", "-r", scenario.product.apkPath]): [.ok("Success\n")],
            command("adb", ["-s", serial, "shell", "pm", "path", scenario.product.applicationId]): [.ok("package:/data/app/base.apk\n")],
            command(
                "adb",
                [
                    "-s", serial, "shell", "cmd", "package", "resolve-activity", "--brief",
                    "-a", "android.intent.action.MAIN",
                    "-c", "android.intent.category.LAUNCHER",
                    scenario.product.applicationId,
                ]
            ): [.ok("dev.mobile.fixture/.MainActivity\n")],
            MetroStatus.command: [.ok(MetroStatus.running(projectRoot: scenario.repo.root))],
            command("adb", ["-s", serial, "reverse", "--list"]): [
                .ok(""),
                .ok("\(serial) \(reverseSource) \(reverseSource)\n"),
                .ok("\(serial) \(reverseSource) \(reverseSource)\n"),
            ],
            command("adb", ["-s", serial, "reverse", reverseSource, reverseSource]): [.ok("")],
            command("adb", ["-s", serial, "shell", "am", "force-stop", scenario.product.applicationId]): [.ok("")],
            command(
                "adb",
                [
                    "-s", serial, "shell", "am", "start", "-W", "-n",
                    "dev.mobile.fixture/dev.mobile.fixture.MainActivity",
                ]
            ): [.ok("Status: ok\n")],
            command("adb", ["-s", serial, "shell", "pidof", scenario.product.applicationId]): [.ok("8123\n")],
            command("adb", ["-s", serial, "shell", "dumpsys", "activity", "activities"]): [.ok("mResumedActivity dev.mobile.fixture/dev.mobile.fixture.MainActivity\n")],
        ]
        let state = ScriptedProcessState(responses)
        let runner = ScriptedProcessRunner(state: state)
        let runtime = AndroidRuntime(
            anchor: scenario.anchor,
            config: scenario.config,
            hostRunner: runner,
            projectRunner: runner,
            environment: scenario.environment,
            logs: scenario.logs,
            timeouts: AndroidRuntimeTimeouts(poll: .zero)
        )

        let device = try await runtime.device(for: scenario.product)
        try await runtime.install(scenario.product, on: device)
        let metro = try await runtime.metro()
        let reverse = try await runtime.reverse(on: device)
        let pid = try await runtime.launch(scenario.product, on: device)

        #expect(device.state == .reused)
        #expect(device.avd == "Pixel")
        #expect(metro.state == .reused)
        #expect(reverse.state == .created)
        #expect(pid == 8123)
        let saved = try AndroidActiveRunStore(
            project: scenario.repo.root, logs: scenario.logs
        ).read()
        let record = try #require(saved)
        #expect(record.device?.state == .reused)
        #expect(record.metro?.state == .reused)
        #expect(record.reverse?.state == .created)
        #expect(record.app?.launched == true)
        #expect(record.app?.pid == 8123)
        #expect(state.all.contains { ["avdmanager", "sdkmanager"].contains($0.executable) } == false)
    }

    @Test("down stops owned app and reverse but preserves reused Metro and Emulator")
    func cleanupPreservesReusedResources() async throws {
        let scenario = try runtimeScenario()
        let store = AndroidActiveRunStore(project: scenario.repo.root, logs: scenario.logs)
        var record = AndroidActiveRun(project: scenario.repo.root, product: scenario.product)
        record.device = .init(
            avd: "Pixel", launcherPID: nil, serial: serial, api: 35, abi: "arm64-v8a", state: .reused
        )
        record.metro = .init(state: .reused, startPID: nil, listenerPID: nil, logPath: nil)
        record.reverse = .init(serial: serial, state: .created)
        record.app = .init(
            serial: serial, applicationId: scenario.product.applicationId, launched: true, pid: 8123
        )
        try store.write(record)
        let responses: [String: [FakeProcessRunner.Response]] = [
            command("adb", ["devices"]): [.ok("List of devices attached\n\(serial) device\n")],
            command("adb", ["-s", serial, "emu", "avd", "name"]): [.ok("Pixel\n")],
            command("adb", ["-s", serial, "shell", "pm", "path", scenario.product.applicationId]): [.ok("package:/data/app/base.apk\n")],
            command("adb", ["-s", serial, "shell", "am", "force-stop", scenario.product.applicationId]): [.ok("")],
            command("adb", ["-s", serial, "shell", "pidof", scenario.product.applicationId]): [.failed(1, "")],
            command("adb", ["-s", serial, "reverse", "--list"]): [
                .ok("\(serial) \(reverseSource) \(reverseSource)\n"),
                .ok(""),
            ],
            command("adb", ["-s", serial, "reverse", "--remove", reverseSource]): [.ok("")],
        ]
        let state = ScriptedProcessState(responses)
        let runner = ScriptedProcessRunner(state: state)

        let cleanup = await AndroidCleanup(
            anchor: scenario.anchor,
            config: scenario.config,
            runner: runner,
            projectRunner: runner,
            environment: scenario.environment,
            logs: scenario.logs,
            timeouts: AndroidRuntimeTimeouts(cleanupGrace: .zero)
        ).run()

        #expect(cleanup.report.items.map(\.id) == [
            "android.app", "android.adb.reverse", "metro", "android.emulator",
        ])
        #expect(cleanup.report.items.map(\.status) == [.stopped, .stopped, .skipped, .skipped])
        #expect(cleanup.report.exitCode == 0)
        #expect(cleanup.hasRemainingRecord == false)
        #expect(state.all.contains { $0.arguments.contains("uninstall") } == false)
        #expect(state.all.contains { $0.arguments.contains("clear") } == false)
        #expect(state.all.contains { $0.arguments == ["-s", serial, "emu", "kill"] } == false)
    }

    @Test("down with no active run infers nothing and exits zero")
    func cleanupWithoutRecord() async throws {
        let scenario = try runtimeScenario()
        let state = ScriptedProcessState([:])
        let runner = ScriptedProcessRunner(state: state)

        let cleanup = await AndroidCleanup(
            anchor: scenario.anchor,
            config: scenario.config,
            runner: runner,
            projectRunner: runner,
            environment: scenario.environment,
            logs: scenario.logs,
            timeouts: AndroidRuntimeTimeouts(cleanupGrace: .zero)
        ).run()

        #expect(cleanup.report.items.allSatisfy { $0.status == .skipped })
        #expect(cleanup.report.exitCode == 0)
        #expect(cleanup.hasRemainingRecord == false)
        #expect(state.all.isEmpty)
    }

    @Test("down stops an Emulator started by the active run")
    func cleanupStopsOwnedEmulator() async throws {
        let scenario = try runtimeScenario()
        let store = AndroidActiveRunStore(project: scenario.repo.root, logs: scenario.logs)
        var record = AndroidActiveRun(project: scenario.repo.root, product: scenario.product)
        record.device = .init(
            avd: "Pixel", launcherPID: 7001, serial: serial, api: 35,
            abi: "arm64-v8a", state: .started
        )
        try store.write(record)
        let responses: [String: [FakeProcessRunner.Response]] = [
            command("adb", ["devices"]): [
                .ok("List of devices attached\n\(serial) device\n"),
                .ok("List of devices attached\n"),
            ],
            command("adb", ["-s", serial, "emu", "avd", "name"]): [.ok("Pixel\n")],
            command("adb", ["-s", serial, "emu", "kill"]): [.ok("OK\n")],
        ]
        let runner = ScriptedProcessRunner(state: ScriptedProcessState(responses))

        let cleanup = await AndroidCleanup(
            anchor: scenario.anchor,
            config: scenario.config,
            runner: runner,
            projectRunner: runner,
            environment: scenario.environment,
            logs: scenario.logs,
            timeouts: AndroidRuntimeTimeouts(cleanupGrace: .zero)
        ).run()

        #expect(cleanup.report.items.last?.status == .stopped)
        #expect(cleanup.report.items.last?.detail?.contains("Pixel") == true)
        #expect(cleanup.hasRemainingRecord == false)
    }

    @Test("a replaced reverse mapping is blocked, retained and exits one")
    func replacedReverseIsBlocked() async throws {
        let scenario = try runtimeScenario()
        let store = AndroidActiveRunStore(project: scenario.repo.root, logs: scenario.logs)
        var record = AndroidActiveRun(project: scenario.repo.root, product: scenario.product)
        record.device = .init(
            avd: "Pixel", launcherPID: nil, serial: serial, api: 35,
            abi: "arm64-v8a", state: .reused
        )
        record.reverse = .init(serial: serial, state: .created)
        try store.write(record)
        let runner = ScriptedProcessRunner(state: ScriptedProcessState([
            command("adb", ["devices"]): [.ok("List of devices attached\n\(serial) device\n")],
            command("adb", ["-s", serial, "emu", "avd", "name"]): [.ok("Pixel\n")],
            command("adb", ["-s", serial, "reverse", "--list"]): [
                .ok("\(serial) \(reverseSource) tcp:9000\n")
            ]
        ]))

        let cleanup = await AndroidCleanup(
            anchor: scenario.anchor,
            config: scenario.config,
            runner: runner,
            projectRunner: runner,
            environment: scenario.environment,
            logs: scenario.logs,
            timeouts: AndroidRuntimeTimeouts(cleanupGrace: .zero)
        ).run()

        #expect(cleanup.report.items[1].status == .blocked)
        #expect(cleanup.report.exitCode == 1)
        #expect(cleanup.hasRemainingRecord)
        #expect(try store.read()?.reverse?.state == .created)
    }

    @Test("an unreadable active-run record is preserved and exits two")
    func corruptedRecordIsUnknown() async throws {
        let scenario = try runtimeScenario()
        let store = AndroidActiveRunStore(project: scenario.repo.root, logs: scenario.logs)
        try FileManager.default.createDirectory(
            at: scenario.logs.directory, withIntermediateDirectories: true
        )
        try Data("not json".utf8).write(to: store.file)
        let runner = ScriptedProcessRunner(state: ScriptedProcessState([:]))

        let cleanup = await AndroidCleanup(
            anchor: scenario.anchor,
            config: scenario.config,
            runner: runner,
            projectRunner: runner,
            environment: scenario.environment,
            logs: scenario.logs,
            timeouts: AndroidRuntimeTimeouts(cleanupGrace: .zero)
        ).run()

        #expect(cleanup.report.items.allSatisfy { $0.status == .unknown })
        #expect(cleanup.report.exitCode == 2)
        #expect(cleanup.hasRemainingRecord)
        #expect(FileManager.default.fileExists(atPath: store.file.path))
    }
}

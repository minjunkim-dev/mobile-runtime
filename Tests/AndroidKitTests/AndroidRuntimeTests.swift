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

private func runtimeScenario(native: Bool = false, abis: [String] = ["arm64-v8a"]) throws -> RuntimeScenario {
    let repo = try FixtureRepo()
    if native {
        try repo.write("settings.gradle.kts", "include(\":app\")")
        try repo.write("gradlew", "wrapper")
    } else {
        try repo.write("package.json", #"{"dependencies":{"react-native":"0.83.1"}}"#)
        try repo.directory("android")
    }
    let sdk = try repo.directory("sdk")
    try repo.write(native ? "local.properties" : "android/local.properties", "sdk.dir=\(sdk.path)\n")
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
            abis: abis,
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
    @Test("colliding legacy parents keep independent Android records and lifecycle locks")
    func collidingAndroidState() throws {
        let scenario = try runtimeScenario()
        let temporary = try scenario.repo.directory("collision")
        let (first, second) = try RunLogs.collidingProjects(temporary: temporary)
        let oneLogs = RunLogs(project: first, temporaryDirectory: temporary)
        let twoLogs = RunLogs(project: second, temporaryDirectory: temporary)
        try #require(oneLogs.directory == twoLogs.directory)
        let one = AndroidActiveRunStore(project: first, logs: oneLogs)
        let two = AndroidActiveRunStore(project: second, logs: twoLogs)
        var a = AndroidActiveRun(project: first, product: scenario.product)
        var b = AndroidActiveRun(project: second, product: scenario.product)
        a.metro = .init(state: .spawned, startPID: 7001, listenerPID: 7002, logPath: "first.log")
        b.metro = .init(state: .spawned, startPID: 8001, listenerPID: 8002, logPath: "second.log")
        try one.write(a)
        try two.write(b)
        let firstLock = try one.acquire(operation: "up")
        let secondLock = try two.acquire(operation: "up")
        #expect(try one.file != two.file)
        #expect(try one.lockFile != two.lockFile)
        #expect(try one.read() == a)
        #expect(try two.read() == b)
        #expect(!FileManager.default.fileExists(atPath: oneLogs.directory.appendingPathComponent(AndroidActiveRunStore.fileName).path))
        withExtendedLifetime((firstLock, secondLock)) {}
    }

    @Test("a base-main owned Android Metro uses its original down path and preserves legacy logs")
    func legacyAndroidMetroDown() async throws {
        let scenario = try runtimeScenario()
        let legacy = scenario.logs.directory.appendingPathComponent(AndroidActiveRunStore.fileName)
        let legacyLock = scenario.logs.directory.appendingPathComponent(AndroidActiveRunStore.lockName)
        let legacyLog = scenario.logs.directory.appendingPathComponent("metro.log")
        try FileManager.default.createDirectory(at: scenario.logs.directory, withIntermediateDirectories: true)
        try Data("preserved log".utf8).write(to: legacyLog)
        try Data("preserved lock".utf8).write(to: legacyLock)
        var record = AndroidActiveRun(project: scenario.repo.root, product: scenario.product)
        record.metro = .init(state: .spawned, startPID: 7002, listenerPID: 7002, logPath: legacyLog.path)
        let bytes = try JSONEncoder().encode(record)
        try bytes.write(to: legacy)
        let rejected = FakeProcessRunner()
        let up = await runAndroidUp(anchor: scenario.anchor, doctor: DoctorEngine(checks: []),
            config: scenario.config, hostRunner: rejected, projectRunner: rejected,
            environment: scenario.environment, logs: scenario.logs, note: { _ in })
        #expect(up.exitCode != 0)
        #expect(rejected.log.all.isEmpty)
        #expect(try Data(contentsOf: legacy) == bytes)
        let state = ScriptedProcessState([
            "kill -0 7002": [.ok(""), .failed(1, "")],
            command("lsof", MetroVerdict.listenerArguments + ["-t"]): [.ok("7002\n"), .failed(1, "")],
            MetroStatus.command: [.ok(MetroStatus.running(projectRoot: scenario.repo.root))],
            "lsof -a -p 7002 -d cwd -Fn": [.ok("p7002\nn\(scenario.repo.root.path)\n")],
            "kill -TERM 7002": [.ok("")],
        ])
        let runner = ScriptedProcessRunner(state: state)

        let report = await androidTeardown(anchor: scenario.anchor, config: scenario.config,
            runner: runner, projectRunner: runner, environment: scenario.environment,
            logs: scenario.logs, timeouts: AndroidRuntimeTimeouts(cleanupGrace: .zero))

        #expect(report.exitCode == 0)
        #expect(report.items.first { $0.id == "metro" }?.status == .stopped)
        #expect(state.all.filter { $0.executable == "kill" && $0.arguments.first == "-TERM" }.map(\.description) == ["kill -TERM 7002"])
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(try String(contentsOf: legacyLog, encoding: .utf8) == "preserved log")
        #expect(try String(contentsOf: legacyLock, encoding: .utf8) == "preserved lock")
        #expect(!FileManager.default.fileExists(atPath: (try scenario.logs.url(AndroidActiveRunStore.fileName)).path))
        #expect(try scenario.logs.metroPort(platform: .android) == nil)
    }

    @Test("unknown legacy Android ownership blocks before commands and preserves every record",
        arguments: ["foreign", "malformed", "symlink", "permission"])
    func legacyAndroidUnknown(_ mode: String) async throws {
        let scenario = try runtimeScenario()
        let legacy = scenario.logs.directory.appendingPathComponent(AndroidActiveRunStore.fileName)
        try FileManager.default.createDirectory(at: scenario.logs.directory, withIntermediateDirectories: true)
        let project = mode == "foreign" ? URL(fileURLWithPath: "/another/project") : scenario.repo.root
        let bytes = mode == "malformed" ? Data("not JSON".utf8)
            : try JSONEncoder().encode(AndroidActiveRun(project: project, product: scenario.product))
        let target = mode == "symlink" ? scenario.repo.url("preserved-record") : legacy
        try bytes.write(to: target)
        if mode == "symlink" { try FileManager.default.createSymbolicLink(at: legacy, withDestinationURL: target) }
        if mode == "permission" { try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: legacy.path) }
        defer { if mode == "permission" { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: legacy.path) } }
        let runner = FakeProcessRunner()

        let report = await androidTeardown(anchor: scenario.anchor, config: scenario.config,
            runner: runner, projectRunner: runner, environment: scenario.environment, logs: scenario.logs)

        #expect(report.exitCode != 0)
        #expect(runner.log.all.isEmpty)
        if mode == "permission" { try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: legacy.path) }
        #expect(try Data(contentsOf: target) == bytes)
        #expect(!FileManager.default.fileExists(atPath: (try scenario.logs.url(AndroidActiveRunStore.fileName)).path))
    }

    @Test("teardown derives the same AVD lease key and preserves unknown records")
    func teardownDeviceKey() throws {
        let scenario = try runtimeScenario()
        let store = AndroidActiveRunStore(project: scenario.repo.root, logs: scenario.logs)
        #expect(try androidTeardownDeviceKey(anchor: scenario.anchor, logs: scenario.logs) == nil)
        var active = AndroidActiveRun(project: scenario.repo.root, product: scenario.product)
        active.device = .init(avd: "Pixel", launcherPID: nil, serial: serial, api: 35, abi: "arm64-v8a", state: .reused)
        try store.write(active)
        #expect(try androidTeardownDeviceKey(anchor: scenario.anchor, logs: scenario.logs) == .device(.android, "avd:Pixel"))
        try Data("unreadable active run".utf8).write(to: try store.file)
        #expect(throws: AndroidStateError.self) {
            try androidTeardownDeviceKey(anchor: scenario.anchor, logs: scenario.logs)
        }
        #expect(try String(contentsOf: try store.file, encoding: .utf8) == "unreadable active run")
    }

    @Test("another requested AVD preserves the existing active run before any subprocess")
    func requestedAVDDoesNotRollbackExistingRun() async throws {
        let scenario = try runtimeScenario()
        let store = AndroidActiveRunStore(project: scenario.repo.root, logs: scenario.logs)
        var active = AndroidActiveRun(project: scenario.repo.root, product: scenario.product)
        active.device = .init(avd: "Pixel", launcherPID: 7001, serial: serial, api: 35, abi: "arm64-v8a", state: .started)
        try store.write(active)
        let runner = FakeProcessRunner()
        let report = await runAndroidUp(anchor: scenario.anchor, doctor: DoctorEngine(checks: []),
            config: scenario.config.selecting(avd: "AnotherPixel"), hostRunner: runner, projectRunner: runner,
            environment: scenario.environment, logs: scenario.logs, note: { _ in })
        #expect(report.exitCode == 1)
        #expect(report.stages.isEmpty)
        #expect(try store.read()?.device?.avd == "Pixel")
        #expect(try store.read()?.device?.launcherPID == 7001)
        #expect(runner.log.all.isEmpty)
    }
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

    @Test("records selected Metro endpoint and ownership for reused and newly started bundlers", arguments: [8081, 8097], [false, true])
    func runsAndroidRuntimeStages(port: Int, startMetro: Bool) async throws {
        let scenario = try runtimeScenario()
        let reverseSource = "tcp:\(port)"
        var responses: [String: [FakeProcessRunner.Response]] = [
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
            "curl -s -i -m 2 http://localhost:\(port)/status": [.ok(MetroStatus.running(projectRoot: scenario.repo.root))],
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
        if startMetro {
            responses["curl -s -i -m 2 http://localhost:\(port)/status"] = [
                .failed(7, ""), .ok(MetroStatus.running(projectRoot: scenario.repo.root)),
            ]
            for (command, response) in MetroStatus.startupResponses(
                projectRoot: scenario.repo.root, startPID: 7001, listenerPID: 7003, port: port
            ) { responses[command] = [response] }
        }
        let state = ScriptedProcessState(responses)
        let runner = ScriptedProcessRunner(state: state)
        let runtime = AndroidRuntime(
            anchor: scenario.anchor,
            config: scenario.config,
            hostRunner: runner,
            projectRunner: runner,
            environment: scenario.environment,
            logs: scenario.logs,
            timeouts: AndroidRuntimeTimeouts(poll: .zero),
            port: port
        )

        let device = try await runtime.device(for: scenario.product)
        try await runtime.install(scenario.product, on: device)
        let metro = try await runtime.metro()
        let reverse = try await runtime.reverse(on: device)
        let pid = try await runtime.launch(scenario.product, on: device)

        #expect(device.state == .reused)
        #expect(device.avd == "Pixel")
        #expect(metro.state == (startMetro ? .spawned : .reused))
        #expect(metro.port == port)
        #expect(try scenario.logs.metroPort(platform: .android) == port)
        #expect(reverse.state == .created)
        #expect(pid == 8123)
        let saved = try AndroidActiveRunStore(
            project: scenario.repo.root, logs: scenario.logs
        ).read()
        let record = try #require(saved)
        #expect(record.device?.state == .reused)
        #expect(record.metro?.state == (startMetro ? .spawned : .reused))
        if startMetro {
            #expect(record.metro?.startPID == 7001)
            #expect(record.metro?.listenerPID == 7003)
            #expect(!state.all.contains { $0.description == "lsof -nP -iTCP:\(port) -sTCP:LISTEN -t" })
        }
        #expect(record.reverse?.state == .created)
        #expect(record.app?.launched == true)
        #expect(record.app?.pid == 8123)
        #expect(state.all.contains { ["avdmanager", "sdkmanager"].contains($0.executable) } == false)
    }

    @Test("changing a recorded Android endpoint preserves its active run before any subprocess")
    func changedPortPreservesActiveRun() async throws {
        let scenario = try runtimeScenario()
        let store = AndroidActiveRunStore(project: scenario.repo.root, logs: scenario.logs)
        var active = AndroidActiveRun(project: scenario.repo.root, product: scenario.product)
        active.metro = .init(state: .reused, startPID: nil, listenerPID: nil, logPath: nil)
        try store.write(active)
        try scenario.logs.recordMetroPort(8097, platform: .android)
        let runner = FakeProcessRunner()
        let report = await runAndroidUp(anchor: scenario.anchor, doctor: DoctorEngine(checks: []),
            config: scenario.config, hostRunner: runner, projectRunner: runner,
            environment: scenario.environment, logs: scenario.logs, metroPort: 8098, note: { _ in })
        #expect(report.exitCode == 1)
        #expect(report.stages.isEmpty)
        #expect(runner.log.all.isEmpty)
        #expect(try store.read() == active)
        #expect(try scenario.logs.metroPort(platform: .android) == 8097)
    }

    @Test("native Android universal APK uses the owned lifecycle without Metro or reverse")
    func nativeRuntimeStages() async throws {
        let scenario = try runtimeScenario(native: true, abis: [])
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
        let stages = androidUpStages(anchor: scenario.anchor, doctor: DoctorEngine(checks: []),
            config: scenario.config, hostRunner: runner, projectRunner: runner,
            environment: scenario.environment, logs: scenario.logs,
            timeouts: AndroidRuntimeTimeouts(poll: .zero), note: { _ in })
        var context = UpContext()
        context.androidProduct = scenario.product
        for stage in stages.drop(while: { $0.id != "android.device" }) {
            _ = try await stage.run(&context)
        }
        let device = try #require(context.androidProduct?.device)
        let pid = context.androidProduct?.appPid
        #expect(device.state == .reused)
        #expect(device.avd == "Pixel")
        #expect(pid == 8123)
        #expect(context.metro == nil)
        #expect(!state.all.contains { $0.arguments.contains("reverse") || ["node", "npm", "lsof"].contains($0.executable) })
        let saved = try AndroidActiveRunStore(
            project: scenario.repo.root, logs: scenario.logs
        ).read()
        let record = try #require(saved)
        #expect(record.device?.state == .reused)
        #expect(record.metro == nil)
        #expect(record.reverse == nil)
        #expect(record.app?.launched == true)
        #expect(record.app?.pid == 8123)
        #expect(state.all.contains { ["avdmanager", "sdkmanager"].contains($0.executable) } == false)
    }

    @Test("ADB CRLF does not become part of the Emulator AVD identity")
    func trimsAVDIdentity() {
        #expect(androidAVDName(from: "Pixel\r\nOK\r\n") == "Pixel")
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
                .ok("List of devices attached\n\(serial) device\n"),
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
            at: (try store.file).deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("not json".utf8).write(to: try store.file)
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
        #expect(FileManager.default.fileExists(atPath: try store.file.path))
    }

    @Test("SDK root failures keep unobserved ownership unknown and exit one", arguments: [true, false])
    func sdkRootFailurePreservesOwnership(conflicting: Bool) async throws {
        let scenario = try runtimeScenario()
        try scenario.repo.write("android/local.properties", conflicting ? "sdk.dir=/different-sdk\n" : "")
        let environment = conflicting ? scenario.environment : AndroidEnvironment(values: [:])
        let store = AndroidActiveRunStore(project: scenario.repo.root, logs: scenario.logs)
        var record = AndroidActiveRun(project: scenario.repo.root, product: scenario.product)
        record.device = .init(avd: "Pixel", launcherPID: 7001, serial: serial, api: 35,
                              abi: "arm64-v8a", state: .started)
        record.reverse = .init(serial: serial, state: .created)
        record.app = .init(serial: serial, applicationId: scenario.product.applicationId,
                           launched: true, pid: 8123)
        try store.write(record)
        let runner = FakeProcessRunner()

        let report = await androidTeardown(anchor: scenario.anchor, config: scenario.config,
            runner: runner, projectRunner: runner, environment: environment, logs: scenario.logs)

        #expect(report.exitCode == 1)
        #expect(report.status == .error)
        #expect(report.toolFailures.isEmpty)
        let failure = try #require(report.failure)
        #expect(failure.remediation.summary == "Make android/local.properties sdk.dir and ANDROID_HOME name one installed SDK.")
        let checks = androidChecks(anchor: scenario.anchor, config: scenario.config,
            hostRunner: runner, projectRunner: runner, environment: environment).filter { $0.id == "android.sdk" }
        let up = await runAndroidUp(anchor: scenario.anchor, doctor: DoctorEngine(checks: checks),
            config: scenario.config, hostRunner: runner, projectRunner: runner,
            environment: environment, logs: scenario.logs, note: { _ in })
        #expect(up.exitCode == report.exitCode)
        #expect(up.stages.last?.id == "validate")
        #expect(up.failure?.remediation == failure.remediation)
        #expect(report.items.map(\.status) == [.unknown, .unknown, .skipped, .unknown])
        for item in report.items where item.status == .unknown {
            #expect(item.detail == failure.message)
            #expect(item.remediation == failure.remediation)
        }
        let document = DownJSONDocument(report: report, toolVersion: "test", platform: "android")
        #expect(document.error?.message == failure.message)
        #expect(document.error?.remediation == failure.remediation)
        #expect(document.items.map(\.status) == report.items.map(\.status))
        #expect(try store.read() == record)
        #expect(runner.log.all.isEmpty)
        #expect(runner.log.spawned.isEmpty)
    }

    @Test("cleanup process failures still exit two alongside SDK domain failures", arguments: [true, false])
    func cleanupToolFailureKeepsExitTwo(missingSDK: Bool) async throws {
        let scenario = try runtimeScenario()
        if missingSDK { try scenario.repo.write("android/local.properties", "") }
        let store = AndroidActiveRunStore(project: scenario.repo.root, logs: scenario.logs)
        var record = AndroidActiveRun(project: scenario.repo.root, product: scenario.product)
        record.device = .init(avd: "Pixel", launcherPID: 7001, serial: serial, api: 35,
                              abi: "arm64-v8a", state: .started)
        record.metro = .init(state: .spawned, startPID: 7002, listenerPID: nil, logPath: nil)
        try store.write(record)
        let failure = ProcessError.spawnFailed(command: "fixture probe", underlying: FixtureMiss(command: "fixture probe"))
        let runner = FakeProcessRunner(failures: ["adb devices": failure, "kill -0 7002": failure])
        let report = await androidTeardown(anchor: scenario.anchor, config: scenario.config,
            runner: runner, projectRunner: runner,
            environment: missingSDK ? AndroidEnvironment(values: [:]) : scenario.environment, logs: scenario.logs)

        #expect(report.exitCode == 2)
        #expect(!report.toolFailures.isEmpty)
        let document = DownJSONDocument(report: report, toolVersion: "test", platform: "android")
        #expect(document.error?.message.contains("fixture probe") == true)
        #expect(report.items.map(\.status) == [.skipped, .skipped, .unknown, .unknown])
        #expect(try store.read() == record)
        #expect(runner.log.all.allSatisfy { $0.description == "adb devices" || $0.description == "kill -0 7002" })
    }

    @Test("SDK root failure still cleans an independently verified owned Metro")
    func sdkRootFailureKeepsBestEffortCleanup() async throws {
        let scenario = try runtimeScenario()
        try scenario.repo.write("android/local.properties", "")
        let store = AndroidActiveRunStore(project: scenario.repo.root, logs: scenario.logs)
        var record = AndroidActiveRun(project: scenario.repo.root, product: scenario.product)
        record.device = .init(avd: "Pixel", launcherPID: 7001, serial: serial, api: 35,
                              abi: "arm64-v8a", state: .started)
        record.app = .init(serial: serial, applicationId: scenario.product.applicationId,
                           launched: true, pid: 8123)
        record.metro = .init(state: .spawned, startPID: 7002, listenerPID: 7002, logPath: nil)
        try store.write(record)
        let state = ScriptedProcessState([
            "kill -0 7002": [.ok(""), .failed(1, "")],
            command("lsof", MetroVerdict.listenerArguments + ["-t"]): [.ok("7002\n"), .failed(1, "")],
            MetroStatus.command: [.ok(MetroStatus.running(projectRoot: scenario.repo.root))],
            "lsof -a -p 7002 -d cwd -Fn": [.ok("p7002\nn\(scenario.repo.root.path)\n")],
            "kill -TERM 7002": [.ok("")],
        ])
        let runner = ScriptedProcessRunner(state: state)
        let report = await androidTeardown(anchor: scenario.anchor, config: scenario.config,
            runner: runner, projectRunner: runner, environment: AndroidEnvironment(values: [:]),
            logs: scenario.logs, timeouts: AndroidRuntimeTimeouts(cleanupGrace: .zero))

        #expect(report.exitCode == 1)
        #expect(report.toolFailures.isEmpty)
        #expect(report.items.map(\.status) == [.unknown, .skipped, .stopped, .unknown])
        record.metro = nil
        #expect(try store.read() == record)
        #expect(state.all.contains { $0.description == "kill -TERM 7002" })
        #expect(!state.all.contains { $0.executable == "adb" })
    }
}

@Suite("Android live app observation")
struct AndroidAppObservationTests {
    @Test("a recycled serial preserves the recorded AVD claim before pidof")
    func recycledSerial() async throws {
        let scenario = try runtimeScenario()
        let device = ResourceKey.device(.android, "avd:Pixel")
        let owner = LeaseOwner(operationId: "first-up", command: "up", project: "/work/first")
        let leases = ResourceLeases(directory: scenario.repo.url("leases"))
        try leases.record(ResourceClaim(device: device, platform: .android, handle: serial,
            appID: "dev.other", owner: owner))
        let pidof = command("adb", ["-s", serial, "shell", "pidof", "dev.other"])
        let runner = FakeProcessRunner(responses: [
            command("adb", ["-s", serial, "emu", "avd", "name"]): .ok("Other\nOK\n"),
            pidof: .failed(1, ""),
        ])
        let conflict = try await #require(throws: ResourceConflict.self) {
            try await leases.check(device: device, project: "/work/second") { claim in
                try await androidAppObservation(serial: claim.handle, applicationId: claim.appID, expectedDevice: claim.device,
                    anchor: scenario.anchor, config: scenario.config, runner: runner, environment: scenario.environment)
            }
        }
        #expect(conflict.owner == owner)
        #expect(!runner.log.all.contains { $0.description == pidof })
        try await #require(throws: ResourceConflict.self) {
            try await leases.check(device: device, project: "/work/second") { _ in .unknown("still reserved") }
        }
    }

    @Test("pidof separates a running app, a stopped app, and a disconnected or unobservable device")
    func observation() async throws {
        let scenario = try runtimeScenario()
        let identity = command("adb", ["-s", serial, "emu", "avd", "name"])
        let pidof = command("adb", ["-s", serial, "shell", "pidof", "dev.other"])
        func observe(_ response: FakeProcessRunner.Response) async -> ClaimObservation {
            try! await androidAppObservation(serial: serial, applicationId: "dev.other", expectedDevice: .device(.android, "avd:Pixel"), anchor: scenario.anchor,
                config: scenario.config, runner: FakeProcessRunner(responses: [identity: .ok("Pixel\nOK\n"), pidof: response]), environment: scenario.environment)
        }
        #expect(await observe(.ok("4242\n")) == .running("dev.other pid 4242 on \(serial)"))
        #expect(await observe(.failed(1, "")) == .stopped)
        #expect(await observe(.failed(1, "adb: device '\(serial)' not found")) == .unknown("adb: device '\(serial)' not found"))
        #expect(await observe(.failed(1, "error: device offline")) == .unknown("error: device offline"))
    }

    @Test("an unreadable AVD identity remains unknown without probing the app", arguments: [true, false])
    func unreadableIdentity(commandFailed: Bool) async throws {
        let scenario = try runtimeScenario()
        let identity = command("adb", ["-s", serial, "emu", "avd", "name"])
        let runner = FakeProcessRunner(responses: [identity: commandFailed ? .failed(1, "device offline") : .ok("")])
        let observation = try await androidAppObservation(serial: serial, applicationId: "dev.other",
            expectedDevice: .device(.android, "avd:Pixel"), anchor: scenario.anchor, config: scenario.config,
            runner: runner, environment: scenario.environment)
        guard case .unknown = observation else { Issue.record("An unverified AVD must remain unknown"); return }
        #expect(runner.log.all.map(\.description) == [identity])
    }

    @Test("cancellation from AVD or app observation is preserved", arguments: [true, false])
    func cancellation(duringIdentity: Bool) async throws {
        let scenario = try runtimeScenario()
        let identity = command("adb", ["-s", serial, "emu", "avd", "name"])
        let pidof = command("adb", ["-s", serial, "shell", "pidof", "dev.other"])
        var runner = FakeProcessRunner(responses: [identity: .ok("Pixel\nOK\n")])
        runner.failures[duringIdentity ? identity : pidof] = CancellationError()
        try await #require(throws: CancellationError.self) {
            try await androidAppObservation(serial: serial, applicationId: "dev.other",
                expectedDevice: .device(.android, "avd:Pixel"), anchor: scenario.anchor, config: scenario.config,
                runner: runner, environment: scenario.environment)
        }
    }
}

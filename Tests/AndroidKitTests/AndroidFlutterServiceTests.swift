import Core
import Foundation
import TestSupport
import Testing

@testable import AndroidKit

private let flutterPID: Int32 = 4102
private let flutterSerial = "emulator-5554"
private let flutterMarker = "1792400000.123456"
private let flutterAnnouncement = "1792400001.123456 4102 4102 I flutter : The Dart VM service is listening on http://127.0.0.1:38881/private-token=/\n"

private struct FlutterProductStage: Stage {
    let id = "fixture.build.output"
    let product: AndroidBuiltProduct
    func run(_ context: inout UpContext) async throws -> StageOutcome {
        context.androidProduct = product
        return .pass("fixture APK")
    }
}

private struct FlutterRuntimeFixture {
    let repo: FixtureRepo
    let anchor: ProjectAnchor
    let config: ConfigContext
    let environment: AndroidEnvironment
    let logs: RunLogs
    let product: AndroidBuiltProduct
    let entrypoint: URL
    var store: AndroidActiveRunStore { AndroidActiveRunStore(project: repo.root, logs: logs) }

    init() throws {
        repo = try FixtureRepo()
        try repo.write("pubspec.yaml", "name: fixture\ndependencies:\n  flutter:\n    sdk: flutter\n")
        try repo.write("lib/main.dart", "void main() {}")
        let sdk = try repo.directory("sdk")
        try repo.write("android/local.properties", "sdk.dir=\(sdk.path)\n")
        anchor = try #require(ProjectAnchor.detect(from: repo.root))
        #expect(anchor.framework == .flutter)
        config = ConfigContext.detect(anchor: anchor, workingDirectory: repo.root)
        environment = AndroidEnvironment(values: ["ANDROID_HOME": sdk.path, "PATH": "/usr/bin:/bin"])
        logs = try .temporary(project: repo.root)
        entrypoint = repo.url("lib/main.dart")
        product = AndroidBuiltProduct(apkPath: repo.url("app.apk").path, module: ":app", variant: "debug",
            assembleTask: ":app:assembleDebug", applicationId: "dev.flutter.fixture", minSdk: "24",
            targetSdk: "35", abis: ["arm64-v8a"], launcherActivity: "dev.flutter.fixture.MainActivity")
    }

    func active() -> AndroidActiveRun {
        var run = AndroidActiveRun(project: repo.root, product: product,
            flutterEntrypoint: entrypoint, flutterServerSocket: "tcp:5037")
        run.device = .init(avd: "Pixel", launcherPID: nil, serial: flutterSerial,
            api: 35, abi: "arm64-v8a", state: .reused)
        run.app = .init(serial: flutterSerial, applicationId: product.applicationId, launched: true, pid: flutterPID)
        return run
    }

    func service(_ runner: any ProcessRunner, launch: Duration = .seconds(2)) throws -> AndroidFlutterService {
        let context = AndroidDoctorContext(anchor: anchor, config: config,
            hostRunner: runner, projectRunner: runner, environment: environment)
        return AndroidFlutterService(context: context, runner: runner, sdk: try context.requiredSDKRoot(),
            endpoint: try AndroidADBEndpoint(environment: environment),
            timeouts: AndroidRuntimeTimeouts(launch: launch, poll: .milliseconds(5)))
    }
}

/// The fake models the externally visible forward table and partial outcomes.
/// It never executes an SDK command and rejects any unplanned command.
private final class FlutterADB: ProcessRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [ProcessCommand] = []
    var table = ""
    var log = flutterAnnouncement
    var pid: Int32? = flutterPID
    var avd = "Pixel"
    var createFailure = false
    var cancelAfterCreate = false
    var pendingCheck: (@Sendable () throws -> Void)?
    var afterCreate: (@Sendable () throws -> Void)?
    var replacementAfterRemove = false
    var malformedList = false
    var cancelOnConfirmation = false
    var markerOutput = "\(flutterMarker) 900 900 I system : marker\n"
    var logcatFailure = false
    var logcatDelay: Duration?
    var packagePathFailure = false
    var postStopPIDFailure = false

    var commands: [ProcessCommand] { lock.withLock { recorded } }

    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        if command.arguments.contains("logcat"), !command.arguments.contains("-t"), let logcatDelay {
            try await Task.sleep(for: logcatDelay)
        }
        return try lock.withLock {
            recorded.append(command)
            guard command.executable == "adb", Array(command.arguments.prefix(2)) == ["-L", "tcp:5037"] else {
                throw FixtureMiss(command: command.description)
            }
            let args = Array(command.arguments.dropFirst(2))
            var output = ""
            var status: TerminationStatus = .exited(0)
            var standardError = ""
            switch args {
            case ["devices"]: output = "List of devices attached\n\(flutterSerial)\tdevice\n"
            case ["-s", flutterSerial, "emu", "avd", "name"]: output = avd + "\nOK\n"
            case ["-s", flutterSerial, "shell", "pidof", "dev.flutter.fixture"]:
                output = pid.map { "\($0)\n" } ?? ""
                if pid == nil { status = .exited(1) }
                if pid == nil && postStopPIDFailure { standardError = "error: device offline" }
            case ["forward", "--list"]:
                if cancelOnConfirmation && !table.isEmpty { throw CancellationError() }
                output = malformedList ? "unknown fields\n" : table
            case ["-s", flutterSerial, "forward", "--no-rebind", "tcp:8097", "tcp:38881"]:
                try pendingCheck?()
                if createFailure || !table.isEmpty { status = .exited(1) }
                else {
                    table = "\(flutterSerial) tcp:8097 tcp:38881\n"
                    try afterCreate?()
                    if cancelAfterCreate { throw CancellationError() }
                }
            case ["-s", flutterSerial, "forward", "--remove", "tcp:8097"]:
                table = replacementAfterRemove ? "emulator-5556 tcp:8097 tcp:40000\n" : ""
            case ["-s", flutterSerial, "shell", "pm", "path", "dev.flutter.fixture"]:
                output = packagePathFailure ? "" : "package:/data/app/base.apk\n"
                if packagePathFailure {
                    status = .exited(1)
                    standardError = "error: device offline"
                }
            case ["-s", flutterSerial, "shell", "pm", "path", "android"]: output = "package:/system/framework/framework-res.apk\n"
            case ["-s", flutterSerial, "shell", "getprop", "sys.boot_completed"]: output = "1\n"
            case ["-s", flutterSerial, "shell", "getprop", "ro.build.version.sdk"]: output = "35\n"
            case ["-s", flutterSerial, "shell", "getprop", "ro.product.cpu.abilist"]: output = "arm64-v8a\n"
            case ["-s", flutterSerial, "shell", "am", "force-stop", "dev.flutter.fixture"]: pid = nil
            case ["-s", flutterSerial, "shell", "am", "start", "-W", "-n", "dev.flutter.fixture/dev.flutter.fixture.MainActivity"]:
                pid = flutterPID
                output = "Status: ok\n"
            case ["-s", flutterSerial, "shell", "cmd", "package", "resolve-activity", "--brief", "-a", "android.intent.action.MAIN", "-c", "android.intent.category.LAUNCHER", "dev.flutter.fixture"]:
                output = "dev.flutter.fixture/dev.flutter.fixture.MainActivity\n"
            case ["-s", flutterSerial, "shell", "dumpsys", "activity", "activities"]:
                output = "dev.flutter.fixture/dev.flutter.fixture.MainActivity\n"
            default:
                if args.contains("logcat") {
                    output = args.contains("-t") ? markerOutput : log
                    if logcatFailure { status = .exited(1) }
                } else { throw FixtureMiss(command: command.description) }
            }
            return ProcessResult(terminationStatus: status, standardOutput: output, standardError: standardError)
        }
    }

    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
        throw FixtureMiss(command: command.description)
    }
}

@Suite("Flutter Android service ownership")
struct AndroidFlutterServiceTests {
    @Test("selected PID/time creates a pending record before no-rebind and a sanitized result")
    func connectAndDown() async throws {
        let fixture = try FlutterRuntimeFixture()
        let initial = fixture.active()
        try fixture.store.write(initial)
        let runner = FlutterADB()
        let store = fixture.store
        runner.pendingCheck = {
            let saved = try store.read()
            let pending = try #require(saved?.forward)
            #expect(pending.state == .pending)
            #expect(pending.hostPort == 8097)
        }
        let service = try fixture.service(runner)
        #expect(try await service.marker(serial: flutterSerial) == flutterMarker)
        let (created, result) = try await service.connect(initial, marker: flutterMarker, hostPort: 8097, store: fixture.store)
        #expect(created.forward?.state == .created)
        #expect(try fixture.store.read() == created)
        #expect(result == AndroidFlutterConnection(hostPort: 8097, devicePort: 38881))
        var product = fixture.product
        product.flutterConnection = result
        let publicJSON = String(decoding: try JSONEncoder().encode(product), as: UTF8.self)
        let privateRecord = try String(contentsOf: fixture.store.file, encoding: .utf8)
        #expect(!publicJSON.contains("private-token"))
        #expect(!privateRecord.contains("private-token"))
        let report = await androidTeardown(anchor: fixture.anchor, config: fixture.config,
            runner: runner, projectRunner: runner, environment: fixture.environment, logs: fixture.logs)
        #expect(report.exitCode == 0)
        #expect(report.items.first?.id == "android.adb.forward")
        #expect(runner.table.isEmpty)
        #expect(try fixture.store.read() == nil)
        #expect(!runner.commands.contains { $0.arguments.contains("reverse") || $0.arguments.contains("kill-server") })
        #expect(runner.commands.allSatisfy { if case .collected = $0.output { true } else { false } })
    }

    @Test("foreign global mapping is preserved before create")
    func foreignMapping() async throws {
        let fixture = try FlutterRuntimeFixture()
        let initial = fixture.active()
        try fixture.store.write(initial)
        let runner = FlutterADB()
        runner.table = "emulator-5556 tcp:8097 tcp:38881\n"
        await #expect(throws: DomainError.self) {
            _ = try await fixture.service(runner).connect(initial, marker: flutterMarker, hostPort: 8097, store: fixture.store)
        }
        #expect(try fixture.store.read() == initial)
        #expect(!runner.commands.contains { $0.arguments.contains("--no-rebind") || $0.arguments.contains("--remove") })
    }

    @Test("uncertain creation retains pending/app/device and never removes by port", arguments: [false, true])
    func uncertainCreate(cancel: Bool) async throws {
        let fixture = try FlutterRuntimeFixture()
        let initial = fixture.active()
        try fixture.store.write(initial)
        let runner = FlutterADB()
        runner.cancelAfterCreate = cancel
        if !cancel {
            runner.pendingCheck = { runner.table = "emulator-5556 tcp:8097 tcp:40000\n" }
        }
        if cancel {
            await #expect(throws: CancellationError.self) {
                _ = try await fixture.service(runner).connect(initial, marker: flutterMarker, hostPort: 8097, store: fixture.store)
            }
        } else {
            await #expect(throws: AndroidStateError.self) {
                _ = try await fixture.service(runner).connect(initial, marker: flutterMarker, hostPort: 8097, store: fixture.store)
            }
        }
        let saved = try fixture.store.read()
        let pending = try #require(saved)
        #expect(pending.forward?.state == .pending)
        let report = await androidTeardown(anchor: fixture.anchor, config: fixture.config,
            runner: runner, projectRunner: runner, environment: fixture.environment, logs: fixture.logs)
        #expect(report.exitCode != 0)
        #expect(try fixture.store.read() == pending)
        #expect(!runner.commands.contains { $0.arguments.contains("--remove") || $0.arguments.contains("force-stop") || $0.arguments.contains("kill") })
    }

    @Test("replaced mapping or app preserves full ownership", arguments: ["mapping", "pid", "avd", "list", "endpoint"])
    func changedIdentity(kind: String) async throws {
        let fixture = try FlutterRuntimeFixture()
        let initial = fixture.active()
        try fixture.store.write(initial)
        let runner = FlutterADB()
        let (created, _) = try await fixture.service(runner).connect(initial, marker: flutterMarker, hostPort: 8097, store: fixture.store)
        switch kind {
        case "mapping": runner.table = "emulator-5556 tcp:8097 tcp:38881\n"
        case "pid": runner.pid = 9999
        case "avd": runner.avd = "Different"
        case "list": runner.malformedList = true
        default: break
        }
        let before = runner.commands.count
        var values = fixture.environment.values
        if kind == "endpoint" { values["ADB_SERVER_SOCKET"] = "tcp:localhost:5038" }
        let report = await androidTeardown(anchor: fixture.anchor, config: fixture.config,
            runner: runner, projectRunner: runner, environment: AndroidEnvironment(values: values), logs: fixture.logs)
        #expect(report.exitCode != 0)
        #expect(try fixture.store.read() == created)
        #expect(!runner.commands.dropFirst(before).contains { $0.arguments.contains("--remove") || $0.arguments.contains("force-stop") })
        if kind == "endpoint" { #expect(runner.commands.count == before) }
    }

    @Test("a mapping recreated after removal is retained without a second delete")
    func replacementAfterRemove() async throws {
        let fixture = try FlutterRuntimeFixture()
        let initial = fixture.active()
        try fixture.store.write(initial)
        let runner = FlutterADB()
        let (created, _) = try await fixture.service(runner).connect(initial, marker: flutterMarker, hostPort: 8097, store: fixture.store)
        runner.replacementAfterRemove = true
        let report = await androidTeardown(anchor: fixture.anchor, config: fixture.config,
            runner: runner, projectRunner: runner, environment: fixture.environment, logs: fixture.logs)
        #expect(report.exitCode != 0)
        #expect(try fixture.store.read() == created)
        #expect(runner.commands.filter { $0.arguments.contains("--remove") }.count == 1)
        #expect(!runner.commands.contains { $0.arguments.contains("force-stop") })
    }

    @Test("old or foreign PID announcements cannot create a forward", arguments: [
        "1792399999.123456 4102 4102 I flutter : The Dart VM service is listening on http://127.0.0.1:38881/private-token=/\n",
        "1792400001.123456 9999 9999 I flutter : The Dart VM service is listening on http://127.0.0.1:38881/private-token=/\n",
        "1792400001.123456 4102 4102 I flutter : The Dart VM service is listening on http://remote.example:38881/private-token=/\n",
        flutterAnnouncement + "1792400002.123456 4102 4102 I flutter : The Dart VM service is listening on http://127.0.0.1:40000/other=/\n",
    ])
    func rejectUnlinkedAnnouncement(log: String) async throws {
        let fixture = try FlutterRuntimeFixture()
        let initial = fixture.active()
        try fixture.store.write(initial)
        let runner = FlutterADB()
        runner.log = log
        await #expect(throws: AndroidStateError.self) {
            _ = try await fixture.service(runner, launch: .milliseconds(100)).connect(initial, marker: flutterMarker, hostPort: 8097, store: fixture.store)
        }
        #expect(!runner.commands.contains { $0.arguments.contains("--no-rebind") })
        #expect(try fixture.store.read() == initial)
    }

    @Test("schema validation rejects forward on legacy records and incoherent Flutter state")
    func schemaBoundaries() throws {
        let fixture = try FlutterRuntimeFixture()
        let legacy = AndroidActiveRun(project: fixture.repo.root, product: fixture.product)
        let bytes = try JSONEncoder().encode(legacy)
        var object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        object["forward"] = NSNull()
        #expect(throws: AndroidStateError.self) {
            _ = try JSONDecoder().decode(AndroidActiveRun.self, from: JSONSerialization.data(withJSONObject: object))
        }
        #expect(try JSONDecoder().decode(AndroidActiveRun.self, from: bytes) == legacy)
        var malformed = fixture.active()
        malformed.metro = .init(state: .reused)
        #expect(throws: AndroidStateError.self) { try fixture.store.write(malformed) }
        #expect(try fixture.store.read() == nil)
        #expect(throws: AndroidStateError.self) { _ = try AndroidADBEndpoint(socket: "localfilesystem:/tmp/adb") }
        #expect(throws: AndroidStateError.self) { _ = try AndroidADBEndpoint(socket: "tcp:remote.example:5037") }
    }

    @Test("confirmed child success is committed before cancellation of the next observation")
    func cancellationAfterSuccess() async throws {
        let fixture = try FlutterRuntimeFixture()
        let initial = fixture.active()
        try fixture.store.write(initial)
        let runner = FlutterADB()
        runner.cancelOnConfirmation = true
        await #expect(throws: CancellationError.self) {
            _ = try await fixture.service(runner).connect(initial, marker: flutterMarker, hostPort: 8097, store: fixture.store)
        }
        #expect(try fixture.store.read()?.forward?.state == .created)
        #expect(runner.table == "\(flutterSerial) tcp:8097 tcp:38881\n")
        #expect(!runner.commands.contains { $0.arguments.contains("--remove") })
    }

    @Test("record commit failure cleans only the confirmed mapping and preserves foreign state")
    func commitFailure() async throws {
        let fixture = try FlutterRuntimeFixture()
        let initial = fixture.active()
        try fixture.store.write(initial)
        let runner = FlutterADB()
        let file = fixture.store.file
        let backup = fixture.repo.url("pending.json")
        let foreign = fixture.repo.url("foreign.txt")
        try Data("foreign state".utf8).write(to: foreign)
        runner.afterCreate = {
            try FileManager.default.moveItem(at: file, to: backup)
            try FileManager.default.createSymbolicLink(at: file, withDestinationURL: foreign)
        }
        await #expect(throws: AndroidStateError.self) {
            _ = try await fixture.service(runner).connect(initial, marker: flutterMarker, hostPort: 8097, store: fixture.store)
        }
        #expect(runner.table.isEmpty)
        #expect(runner.commands.filter { $0.arguments.contains("--remove") }.count == 1)
        #expect(try String(contentsOf: foreign, encoding: .utf8) == "foreign state")
        #expect(try JSONDecoder().decode(AndroidActiveRun.self, from: Data(contentsOf: backup)).forward?.state == .pending)
        #expect(throws: AndroidStateError.self) { _ = try fixture.store.read() }
    }

    @Test("down exports the recorded general port key and another up cannot overwrite the run")
    func recordedKeysAndRepeatUp() async throws {
        let fixture = try FlutterRuntimeFixture()
        let initial = fixture.active()
        try fixture.store.write(initial)
        let runner = FlutterADB()
        let (created, _) = try await fixture.service(runner).connect(initial, marker: flutterMarker, hostPort: 8097, store: fixture.store)
        #expect(try androidTeardownResourceKeys(anchor: fixture.anchor, logs: fixture.logs)
            == [.device(.android, "avd:Pixel"), .port(8097)])
        let before = runner.commands.count
        let report = await runAndroidUp(anchor: fixture.anchor, doctor: DoctorEngine(checks: []),
            config: fixture.config, hostRunner: runner, projectRunner: runner,
            environment: fixture.environment, logs: fixture.logs, port: 8098,
            flutterEntrypoint: fixture.entrypoint, note: { _ in })
        #expect(report.exitCode == 1)
        #expect(report.stages.isEmpty)
        #expect(runner.commands.count == before)
        #expect(try fixture.store.read() == created)
    }

    @Test("local endpoint environment precedence is pinned without server-management commands")
    func endpointSelection() throws {
        #expect(try AndroidADBEndpoint(environment: AndroidEnvironment(values: [:])).socket == "tcp:5037")
        let selected = try AndroidADBEndpoint(environment: AndroidEnvironment(values: [
            "ADB_SERVER_SOCKET": "tcp:localhost:5040", "ANDROID_ADB_SERVER_ADDRESS": "foreign", "ANDROID_ADB_SERVER_PORT": "bad",
        ]))
        #expect(selected.arguments(["devices"]) == ["-L", "tcp:localhost:5040", "devices"])
        #expect(try AndroidADBEndpoint(environment: AndroidEnvironment(values: ["ANDROID_ADB_SERVER_PORT": "5041"])).socket == "tcp:5041")
        #expect(throws: AndroidStateError.self) {
            _ = try AndroidADBEndpoint(environment: AndroidEnvironment(values: ["ADB_SERVER_SOCKET": ""]))
        }
    }

    @Test("Flutter service follows launch without changing the existing build prefix")
    func flutterStageOrder() throws {
        let fixture = try FlutterRuntimeFixture()
        let runner = FakeProcessRunner()
        let stages = androidUpStages(anchor: fixture.anchor, doctor: DoctorEngine(checks: []), config: fixture.config,
            hostRunner: runner, projectRunner: runner, environment: fixture.environment, logs: fixture.logs,
            port: 8097, flutterEntrypoint: fixture.entrypoint, note: { _ in })
        #expect(stages.map(\.id) == ["validate", "android.build", "android.device", "android.install", "android.launch", "android.flutter.service"])
        #expect(runner.log.all.isEmpty)
    }

    @Test("malformed forward identities are rejected without replacing the last coherent record", arguments: [
        "hostPort", "devicePort", "serial", "avd", "applicationId", "entrypoint", "appPID", "operationID", "serverSocket", "launchMarker",
    ])
    func malformedForward(field: String) async throws {
        let fixture = try FlutterRuntimeFixture()
        let initial = fixture.active()
        try fixture.store.write(initial)
        let runner = FlutterADB()
        let (created, _) = try await fixture.service(runner).connect(initial, marker: flutterMarker, hostPort: 8097, store: fixture.store)
        let bytes = try JSONEncoder().encode(created)
        var object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var forward = try #require(object["forward"] as? [String: Any])
        switch field {
        case "hostPort": forward[field] = 0
        case "devicePort": forward[field] = 65536
        case "appPID": forward[field] = 9999
        case "serverSocket": forward[field] = "tcp:5038"
        default: forward[field] = ""
        }
        object["forward"] = forward
        #expect(throws: AndroidStateError.self) {
            _ = try JSONDecoder().decode(AndroidActiveRun.self, from: JSONSerialization.data(withJSONObject: object))
        }
        #expect(try fixture.store.read() == created)
    }

    @Test("missing markers and unsupported logcat remain unknown without a public secret", arguments: [false, true])
    func unavailableLogcat(failed: Bool) async throws {
        let fixture = try FlutterRuntimeFixture()
        let runner = FlutterADB()
        runner.markerOutput = "private-token but no reliable timestamp"
        runner.logcatFailure = failed
        do {
            _ = try await fixture.service(runner).marker(serial: flutterSerial)
            Issue.record("an unavailable time marker must not be accepted")
        } catch {
            #expect(!String(describing: error).contains("private-token"))
        }
        #expect(runner.commands.count == 1)
        #expect(try fixture.store.read() == nil)
    }

    @Test("Flutter cannot clean a legacy framework record or stop a substituted app identity")
    func frameworkAndAppBoundaries() async throws {
        let fixture = try FlutterRuntimeFixture()
        let legacy = AndroidActiveRun(project: fixture.repo.root, product: fixture.product)
        try fixture.store.write(legacy)
        let runner = FlutterADB()
        let report = await androidTeardown(anchor: fixture.anchor, config: fixture.config,
            runner: runner, projectRunner: runner, environment: fixture.environment, logs: fixture.logs)
        #expect(report.exitCode != 0)
        #expect(try fixture.store.read() == legacy)
        #expect(runner.commands.isEmpty)
        var changed = fixture.active()
        changed.app = .init(serial: flutterSerial, applicationId: "another.app", launched: true, pid: flutterPID)
        #expect(throws: AndroidStateError.self) { try fixture.store.write(changed) }
        #expect(try fixture.store.read() == legacy)
    }

    @Test("shared runtime stages bind the prelaunch marker and preserve cancellation 130", arguments: [false, true])
    func runtimeStages(cancel: Bool) async throws {
        let fixture = try FlutterRuntimeFixture()
        try fixture.store.write(fixture.active())
        let runner = FlutterADB()
        runner.cancelAfterCreate = cancel
        let stages = androidUpStages(anchor: fixture.anchor, doctor: DoctorEngine(checks: []), config: fixture.config,
            hostRunner: runner, projectRunner: runner, environment: fixture.environment, logs: fixture.logs,
            timeouts: AndroidRuntimeTimeouts(poll: .zero), port: 8097,
            flutterEntrypoint: fixture.entrypoint, note: { _ in })
        let runtime = stages.filter { ["android.device", "android.launch", "android.flutter.service"].contains($0.id) }
        let report = await UpPipeline(stages: [FlutterProductStage(product: fixture.product)] + runtime).run()
        #expect(report.exitCode == (cancel ? 130 : 0))
        #expect(report.context.androidProduct?.appPid == flutterPID)
        #expect(report.context.androidProduct?.flutterConnection?.hostPort == (cancel ? nil : 8097))
        let markerIndex = try #require(runner.commands.firstIndex { $0.arguments.contains("-t") })
        let launchIndex = try #require(runner.commands.firstIndex { $0.arguments.contains("start") })
        #expect(markerIndex < launchIndex)
        #expect(try fixture.store.read()?.forward?.state == (cancel ? .pending : .created))
        #expect(!report.stages.contains { $0.detail?.contains("private-token") == true })
        #expect(!runner.commands.contains { $0.arguments.contains("reverse") || $0.arguments.contains("start-server") || $0.arguments.contains("kill-server") })
    }

    @Test("runtime rejects symbolic, escaped and nonregular Flutter entrypoints before device commands", arguments: ["leaf", "parent", "outside", "missing", "directory"])
    func invalidRuntimeEntrypoint(_ kind: String) async throws {
        let fixture = try FlutterRuntimeFixture()
        let outside = try FixtureRepo()
        try outside.write("main.dart", "preserved outside source")
        let entrypoint: URL
        switch kind {
        case "leaf":
            entrypoint = fixture.repo.url("lib/alias.dart")
            try FileManager.default.createSymbolicLink(at: entrypoint, withDestinationURL: fixture.entrypoint)
        case "parent":
            let alias = fixture.repo.url("linked-lib")
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.entrypoint.deletingLastPathComponent())
            entrypoint = alias.appendingPathComponent("main.dart")
        case "outside": entrypoint = outside.url("main.dart")
        case "directory": entrypoint = try fixture.repo.directory("lib/not-a-file.dart")
        default: entrypoint = fixture.repo.url("lib/missing.dart")
        }
        let runner = FlutterADB()
        let stages = androidUpStages(anchor: fixture.anchor, doctor: DoctorEngine(checks: []), config: fixture.config,
            hostRunner: runner, projectRunner: runner, environment: fixture.environment, logs: fixture.logs,
            port: 8097, flutterEntrypoint: entrypoint, note: { _ in })
        let report = await UpPipeline(stages: [FlutterProductStage(product: fixture.product)]
            + stages.filter { $0.id == "android.device" }).run()
        #expect(report.exitCode == 2)
        #expect(runner.commands.isEmpty)
        #expect(try fixture.store.read() == nil)
        #expect(try String(contentsOf: outside.url("main.dart"), encoding: .utf8) == "preserved outside source")
        withExtendedLifetime(outside) {}
    }

    @Test("unreadable and substituted records remain unchanged", arguments: ["malformed", "symlink", "unreadable", "oversized"])
    func unreadableState(kind: String) throws {
        let fixture = try FlutterRuntimeFixture()
        let active = fixture.active()
        try fixture.store.write(active)
        let file = fixture.store.file
        let foreign = fixture.repo.url("untouched.txt")
        try Data("untouched".utf8).write(to: foreign)
        switch kind {
        case "malformed": try Data("not JSON".utf8).write(to: file)
        case "symlink":
            try FileManager.default.removeItem(at: file)
            try FileManager.default.createSymbolicLink(at: file, withDestinationURL: foreign)
        case "unreadable": try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        default: try Data(repeating: 32, count: 1_048_577).write(to: file)
        }
        defer {
            if kind == "unreadable" { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }
        }
        #expect(throws: AndroidStateError.self) { _ = try fixture.store.read() }
        #expect(throws: AndroidStateError.self) { try fixture.store.write(active) }
        #expect(try String(contentsOf: foreign, encoding: .utf8) == "untouched")
        if kind == "malformed" { #expect(try String(contentsOf: file, encoding: .utf8) == "not JSON") }
        if kind == "oversized" { #expect(try Data(contentsOf: file).count == 1_048_577) }
    }

    @Test("a late valid URI cannot exceed the shared discovery deadline")
    func exhaustedDiscoveryBudget() async throws {
        let fixture = try FlutterRuntimeFixture()
        let initial = fixture.active()
        try fixture.store.write(initial)
        let runner = FlutterADB()
        runner.logcatDelay = .milliseconds(1100)
        await #expect(throws: AndroidStateError.self) {
            _ = try await fixture.service(runner, launch: .seconds(1)).connect(initial,
                marker: flutterMarker, hostPort: 8097, store: fixture.store)
        }
        #expect(try fixture.store.read() == initial)
        #expect(!runner.commands.contains { $0.arguments.contains("--no-rebind") })
        let observations = runner.commands.filter { $0.arguments.contains("logcat") }
        #expect(observations.count == 1)
        let observation = try #require(observations.first)
        let childTimeout = try #require(observation.timeout)
        #expect(childTimeout <= .seconds(1))
        #expect(runner.commands.allSatisfy { ($0.timeout ?? .seconds(99)) <= .seconds(1) })
    }

    @Test("Flutter pm-path transport failure preserves app and device ownership")
    func packagePathTransportFailure() async throws {
        let fixture = try FlutterRuntimeFixture()
        let initial = fixture.active()
        try fixture.store.write(initial)
        let runner = FlutterADB()
        runner.packagePathFailure = true
        let report = await androidTeardown(anchor: fixture.anchor, config: fixture.config,
            runner: runner, projectRunner: runner, environment: fixture.environment, logs: fixture.logs)
        #expect(report.exitCode != 0)
        #expect(report.items.contains { $0.id == "android.app" && $0.status == .unknown })
        #expect(try fixture.store.read() == initial)
        #expect(!runner.commands.contains { $0.arguments.contains("force-stop") || $0.arguments.contains("kill") })
    }

    @Test("Flutter post-stop pidof transport failure does not prove app absence")
    func postStopTransportFailure() async throws {
        let fixture = try FlutterRuntimeFixture()
        let initial = fixture.active()
        try fixture.store.write(initial)
        let runner = FlutterADB()
        runner.postStopPIDFailure = true
        let report = await androidTeardown(anchor: fixture.anchor, config: fixture.config,
            runner: runner, projectRunner: runner, environment: fixture.environment, logs: fixture.logs)
        #expect(report.exitCode != 0)
        #expect(report.items.contains { $0.id == "android.app" && $0.status == .unknown })
        #expect(try fixture.store.read() == initial)
        #expect(runner.commands.filter { $0.arguments.contains("force-stop") }.count == 1)
        #expect(!runner.commands.contains { $0.arguments.contains("kill") })
    }

    @Test("app-only unconfirmed or replacement PID preserves ownership with a nonzero result", arguments: [false, true])
    func appOnlyUncertainPID(replaced: Bool) async throws {
        let fixture = try FlutterRuntimeFixture()
        var initial = fixture.active()
        if !replaced { initial.app?.pid = nil }
        try fixture.store.write(initial)
        let runner = FlutterADB()
        if replaced { runner.pid = 9999 }
        let report = await androidTeardown(anchor: fixture.anchor, config: fixture.config,
            runner: runner, projectRunner: runner, environment: fixture.environment, logs: fixture.logs)
        #expect(report.exitCode != 0)
        #expect(try fixture.store.read() == initial)
        #expect(!runner.commands.contains { $0.arguments.contains("force-stop") || $0.arguments.contains("kill") })
    }
}

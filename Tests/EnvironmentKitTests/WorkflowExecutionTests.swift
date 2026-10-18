import Core
import EnvironmentKit
import Foundation
import TestSupport
import Testing

@Suite("shared CLI and GUI RN workflows")
struct WorkflowExecutionTests {
    @Test("an unmet exact tool declaration blocks build and up before dependency or build changes", arguments: [WorkflowKind.build, .up])
    func unmetToolDeclaration(_ kind: WorkflowKind) async throws {
        let repo = try iosProject()
        try repo.write(".tool-versions", "nodejs 24.14.0\n")
        let runner = kind == .build ? iosRunner(repo) : iosUpRunner(repo)
        let result = await WorkflowExecution.run(kind, input: WorkflowInput(project: ProjectInspectionInput(
            directory: repo.root, environment: [:])), runner: runner, leases: temporaryLeases())
        #expect(result.exitCode == 1)
        #expect(result.up?.context.validation?.checks.contains { $0.id == "tools.node" && $0.status == .error } == true)
        #expect(!runner.log.all.contains { $0.arguments.contains("install") || $0.arguments.contains("build") || $0.executable == "curl" })
    }
    @Test("dual-platform app needs selection before any subprocess or mutation")
    func missingPlatform() async throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies":{"react-native":"0.76.5"}}"#)
        try repo.directory("ios")
        try repo.directory("android")
        let runner = FakeProcessRunner()
        let result = await WorkflowExecution.run(.up, input: WorkflowInput(project: ProjectInspectionInput(
            directory: repo.root, environment: [:])), runner: runner)
        #expect(result.exitCode == 1)
        #expect(result.operation.state == "needs-selection")
        #expect(result.operation.requiredInput == ["--platform"])
        #expect(result.operation.selection?.selected?.id == ".")
        #expect(runner.log.all.isEmpty)
    }

    @Test("one iOS app builds a generic Simulator artifact without boot, install or launch")
    func genericBuild() async throws {
        let repo = try iosProject()
        let runner = iosRunner(repo)
        let events = EventLog()
        let result = await WorkflowExecution.run(.build, input: WorkflowInput(project: ProjectInspectionInput(
            directory: repo.root, environment: [:])), runner: runner, onEvent: { events.append($0) })
        #expect(result.exitCode == 0, Comment(rawValue: result.up?.failure?.message ?? ""))
        #expect(result.operation.state == "succeeded")
        #expect(result.operation.scheme == "MyApp")
        #expect(result.operation.device == nil)
        #expect(result.up?.stages.map(\.id) == ["validate", "dependencies", "build"])
        #expect(!runner.log.all.contains { $0.arguments.contains("bootstatus") || ($0.executable == "xcrun" && ($0.arguments.contains("install") || $0.arguments.contains("launch"))) })
        #expect(runner.log.spawned.isEmpty)
        #expect(events.all.map(\.sequence) == Array(1...events.all.count))
        #expect(Set(events.all.map(\.operationId)) == [result.operation.id])
        let data = Data(try result.encoded(toolVersion: "test").utf8)
        let document = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(document["command"] as? String == "build")
        #expect(document["schemaVersion"] as? Int == 1)
        #expect(document["result"] != nil)
        #expect(document["stages"] != nil)
        #expect(document["operation"] != nil)
    }

    @Test("an explicit RN build destination does not boot or take an app runtime lease")
    func selectedBuild() async throws {
        let repo = try iosProject()
        var runner = iosUpRunner(repo)
        runner.responses["xcrun simctl list devices -j"] = .ok(#"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"name":"iPhone A","udid":"A","state":"Shutdown","isAvailable":true}]}}"#)
        let leases = temporaryLeases()
        let device = try leases.acquire([.device(.ios, "A")], owner: LeaseOwner(
            operationId: "other-app", command: "up", project: "/other-app"))
        defer { device.release() }
        let result = await WorkflowExecution.run(.build, input: WorkflowInput(project: ProjectInspectionInput(
            directory: repo.root, environment: [:], platform: .ios), device: "A"), runner: runner, leases: leases)
        #expect(result.exitCode == 0, Comment(rawValue: result.up?.failure?.message ?? ""))
        #expect(result.operation.device == "A")
        let build = try #require(runner.log.all.first { $0.arguments.last == "build" })
        #expect(build.arguments.contains("platform=iOS Simulator,id=A"))
        #expect(!build.arguments.contains("ONLY_ACTIVE_ARCH=YES"))
        #expect(!runner.log.all.contains { $0.executable == "xcrun" && ($0.arguments.contains("bootstatus") || $0.arguments.contains("boot") || $0.arguments.contains("install") || $0.arguments.contains("launch")) })
        #expect(runner.log.spawned.isEmpty)
    }

    @Test("several Simulator identities need an explicit device before dependencies")
    func missingDevice() async throws {
        let repo = try iosProject()
        var runner = iosRunner(repo)
        runner.responses["xcrun simctl list devices -j"] = .ok(#"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"name":"iPhone A","udid":"A","state":"Booted","isAvailable":true},{"name":"iPhone B","udid":"B","state":"Shutdown","isAvailable":true}]}}"#)
        let result = await WorkflowExecution.run(.up, input: WorkflowInput(project: ProjectInspectionInput(
            directory: repo.root, environment: [:], platform: .ios)), runner: runner)
        #expect(result.exitCode == 1)
        #expect(result.operation.state == "needs-selection")
        #expect(result.operation.requiredInput == ["--device"])
        #expect(result.operation.devices.map(\.id) == ["A", "B"])
        #expect(!runner.log.all.contains { $0.description == "yarn install --frozen-lockfile" })
        #expect(runner.log.spawned.isEmpty)
    }

    @Test("workspace-only apps confirm Debug from effective Xcode settings")
    func workspaceOnlyBuild() async throws {
        let repo = try iosProject(workspaceOnly: true)
        let runner = iosRunner(repo, workspaceOnly: true)
        let result = await WorkflowExecution.run(.build, input: WorkflowInput(project: ProjectInspectionInput(
            directory: repo.root, environment: [:])), runner: runner)
        #expect(result.exitCode == 0)
        #expect(result.operation.configuration == "Debug")
        #expect(result.up?.stages.map(\.id) == ["validate", "dependencies", "build"])
    }

    @Test("a workspace cannot accept an invalid configuration that Xcode silently resolves to Release")
    func workspaceInvalidConfiguration() async throws {
        let repo = try iosProject(workspaceOnly: true)
        var runner = iosRunner(repo, workspaceOnly: true)
        let command = "xcodebuild -showBuildSettings -json -workspace \(repo.url("ios/MyApp.xcworkspace").path) -scheme MyApp -configuration Missing -destination generic/platform=iOS Simulator -derivedDataPath \(RunLogs(project: repo.root).url("DerivedData").resolvingSymlinksInPath().path)"
        runner.responses[command] = .ok(#"[{"target":"MyApp","buildSettings":{"CONFIGURATION":"Release"}}]"#)
        let result = await WorkflowExecution.run(.build, input: WorkflowInput(project: ProjectInspectionInput(
            directory: repo.root, environment: [:]), configuration: "Missing"), runner: runner)
        #expect(result.exitCode == 1)
        #expect(result.operation.configurations == ["Release"])
        #expect(!runner.log.all.contains { $0.description == "yarn install --frozen-lockfile" })
    }

    @Test("invalid scheme and cross-platform selectors stop before dependency changes")
    func invalidSelectors() async throws {
        let repo = try iosProject()
        let runner = iosRunner(repo)
        let result = await WorkflowExecution.run(.build, input: WorkflowInput(project: ProjectInspectionInput(
            directory: repo.root, environment: [:], platform: .ios), scheme: "Wrong"), runner: runner)
        #expect(result.exitCode == 1)
        #expect(!runner.log.all.contains { $0.description == "yarn install --frozen-lockfile" })
        let unused = FakeProcessRunner()
        let wrongPlatform = await WorkflowExecution.run(.build, input: WorkflowInput(project: ProjectInspectionInput(
            directory: repo.root, environment: [:]), module: ":app"), runner: unused)
        #expect(wrongPlatform.exitCode == 1)
        #expect(unused.log.all.isEmpty)
    }

    @Test("a project without Debug requires configuration before dependency changes")
    func missingDebugConfiguration() async throws {
        let repo = try iosProject()
        var runner = iosRunner(repo)
        runner.responses["xcodebuild -list -json -project \(repo.url("ios/MyApp.xcodeproj").path)"] = .ok(#"{"project":{"schemes":["MyApp"],"configurations":["Release","Development"]}}"#)
        let result = await WorkflowExecution.run(.build, input: WorkflowInput(project: ProjectInspectionInput(
            directory: repo.root, environment: [:])), runner: runner)
        #expect(result.exitCode == 1)
        #expect(result.operation.state == "needs-selection")
        #expect(result.operation.requiredInput == ["--configuration"])
        #expect(result.operation.configuration == nil)
        #expect(!runner.log.all.contains { $0.description == "yarn install --frozen-lockfile" })
    }

    @Test("cancelled operation produces exit 130 and one correlated final event")
    func cancellation() async throws {
        let repo = try iosProject()
        let runner = FakeProcessRunner()
        let events = EventLog()
        let task = Task {
            await WorkflowExecution.run(.up, input: WorkflowInput(project: ProjectInspectionInput(
                directory: repo.root, environment: [:])), runner: runner, onEvent: { events.append($0) })
        }
        task.cancel()
        let result = await task.value
        #expect(result.exitCode == 130)
        #expect(result.operation.state == "cancelled")
        #expect(events.all.last?.kind == "cancelled")
        #expect(events.all.last?.operationId == result.operation.id)
        #expect(runner.log.spawned.isEmpty)
    }

    @Test("infrastructure failure keeps exit 2 and command-specific public fields")
    func infrastructureFailure() async throws {
        let repo = try iosProject()
        let result = await WorkflowExecution.run(.build, input: WorkflowInput(project: ProjectInspectionInput(
            directory: repo.root, environment: [:])), runner: FakeProcessRunner())
        #expect(result.exitCode == 2)
        #expect(result.operation.state == "failed")
        #expect(result.up?.failure != nil)
        #expect(result.up?.stages.isEmpty == true)
    }

    @Test("a folder held by another client stops build before changes and names the owner")
    func folderConflict() async throws {
        let repo = try iosProject()
        let runner = iosRunner(repo)
        let leases = temporaryLeases()
        let gui = LeaseOwner(operationId: "gui-1", command: "up", project: repo.root.path)
        let held = try leases.acquire([.folder(try FolderIdentity(directory: repo.root))], owner: gui)
        let result = await WorkflowExecution.run(.build, input: WorkflowInput(project: ProjectInspectionInput(
            directory: repo.root, environment: [:])), runner: runner, leases: leases)
        #expect(result.exitCode == 1)
        #expect(result.operation.state == "failed")
        #expect(result.operation.conflict?.owner == gui)
        #expect(result.up?.failure?.message.contains("held by up operation gui-1") == true)
        #expect(!runner.log.all.contains { $0.description == "yarn install --frozen-lockfile" })
        held.release()
        let retry = await WorkflowExecution.run(.build, input: WorkflowInput(project: ProjectInspectionInput(
            directory: repo.root, environment: [:])), runner: iosRunner(repo), leases: leases)
        #expect(retry.exitCode == 0)
        _ = try leases.acquire([.folder(try FolderIdentity(directory: repo.root))], owner: gui)
    }

    @Test("an app another project left running blocks up on that device; no automatic switch")
    func liveAppConflict() async throws {
        let repo = try iosProject()
        var runner = iosRunner(repo)
        runner.responses["xcrun simctl list devices -j"] = .ok(#"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"name":"iPhone A","udid":"A","state":"Booted","isAvailable":true},{"name":"iPhone B","udid":"B","state":"Shutdown","isAvailable":true}]}}"#)
        runner.responses["xcrun simctl spawn A launchctl list"] = .ok("PID\tStatus\tLabel\n4242\t0\tUIKitApplication:com.other.App[a1b2][rb-legacy]\n")
        let leases = temporaryLeases()
        let other = LeaseOwner(operationId: "cli-1", command: "up", project: "/work/other")
        try leases.record(ResourceClaim(device: .device(.ios, "A"), platform: .ios, handle: "A", appID: "com.other.App", owner: other))
        let result = await WorkflowExecution.run(.up, input: WorkflowInput(project: ProjectInspectionInput(
            directory: repo.root, environment: [:], platform: .ios), device: "A"), runner: runner, leases: leases)
        #expect(result.exitCode == 1)
        #expect(result.operation.device == "A")
        #expect(result.operation.conflict?.owner == other)
        #expect(result.operation.conflict?.reason.contains("still running") == true)
        #expect(!runner.log.all.contains { $0.description == "yarn install --frozen-lockfile" })
        #expect(runner.log.spawned.isEmpty)
        // The failed up released its own keys; the other project's claim is preserved.
        _ = try leases.acquire([.device(.ios, "A"), .port(8081)], owner: other)
        await #expect(throws: ResourceConflict.self) {
            try await leases.check(device: .device(.ios, "A"), project: repo.root.path) { _ in .running("") }
        }
    }

    @Test("a finished up leaves a device claim that another project's up observes again")
    func upLeavesClaim() async throws {
        let repo = try iosProject()
        var runner = iosRunner(repo)
        let destination = "-project \(repo.url("ios/MyApp.xcodeproj").path) -scheme MyApp -configuration Debug -destination platform=iOS Simulator,id=A -derivedDataPath \(RunLogs(project: repo.root).url("DerivedData").resolvingSymlinksInPath().path)"
        runner.responses["xcrun simctl list devices -j"] = .ok(#"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"name":"iPhone A","udid":"A","state":"Booted","isAvailable":true}]}}"#)
        runner.responses[MetroStatus.command] = .ok(MetroStatus.running(projectRoot: repo.root))
        runner.responses["xcodebuild \(destination) build"] = .ok("** BUILD SUCCEEDED **")
        runner.responses["xcodebuild -showBuildSettings -json \(destination)"] = .ok(#"[{"target":"MyApp","buildSettings":{"CONFIGURATION":"Debug","BUILT_PRODUCTS_DIR":"/test/build","FULL_PRODUCT_NAME":"MyApp.app","PRODUCT_BUNDLE_IDENTIFIER":"com.test.MyApp"}}]"#)
        runner.responses["xcrun simctl install A /test/build/MyApp.app"] = .ok("")
        runner.responses["xcrun simctl terminate A com.test.MyApp"] = .ok("")
        runner.responses["xcrun simctl launch A com.test.MyApp"] = .ok("com.test.MyApp: 3538")
        let leases = temporaryLeases()
        let result = await WorkflowExecution.run(.up, input: WorkflowInput(project: ProjectInspectionInput(
            directory: repo.root, environment: [:], platform: .ios), device: "A"), runner: runner, leases: leases)
        #expect(result.exitCode == 0, Comment(rawValue: result.up?.failure?.message ?? ""))
        // The lease ended with the command; the app it launched still holds the device.
        let other = LeaseOwner(operationId: "other-up", command: "up", project: "/work/other")
        let lease = try leases.acquire([.device(.ios, "A"), .port(8081)], owner: other)
        let conflict = try await #require(throws: ResourceConflict.self) {
            try await leases.check(device: .device(.ios, "A"), project: other.project) { claim in
                #expect(claim.handle == "A")
                return .running("pid 3538")
            }
        }
        #expect(conflict.key == .app(.ios, device: "A", appID: "com.test.MyApp"))
        #expect(conflict.owner?.operationId == result.operation.id)
        lease.release()
    }

    @Test("down respects another operation's device and port leases before teardown", arguments: [ResourceKey.device(.ios, "A"), .port(8081)])
    func downResourceConflict(key: ResourceKey) async throws {
        let repo = try iosProject()
        let logs = RunLogs(project: repo.root)
        defer { try? FileManager.default.removeItem(at: logs.directory) }
        #expect(InstallRecord(udid: "A", bundleId: "com.test.MyApp").write(to: logs) != nil)
        let leases = temporaryLeases()
        let other = LeaseOwner(operationId: "other-up", command: "up", project: "/work/other")
        let held = try leases.acquire([key], owner: other)
        defer { held.release() }
        let runner = iosRunner(repo)
        let result = await WorkflowExecution.run(.down, input: WorkflowInput(project: ProjectInspectionInput(
            directory: repo.root, environment: [:], platform: .ios)), runner: runner, leases: leases)
        #expect(result.exitCode == 1)
        #expect(result.operation.conflict?.owner == other)
        #expect(!runner.log.all.contains { $0.arguments.contains("terminate") || $0.executable == "kill" })
        #expect(result.down?.items.isEmpty == true)
    }

    @Test("stale down preserves another project's running or unobservable app", arguments: [true, false])
    func downClaimConflict(running: Bool) async throws {
        let repo = try iosProject()
        let logs = RunLogs(project: repo.root)
        defer { try? FileManager.default.removeItem(at: logs.directory) }
        #expect(InstallRecord(udid: "A", bundleId: "com.test.MyApp").write(to: logs) != nil)
        let leases = temporaryLeases()
        let other = LeaseOwner(operationId: "finished-up", command: "up", project: "/work/other")
        try leases.record(ResourceClaim(device: .device(.ios, "A"), platform: .ios,
            handle: "A", appID: "com.test.MyApp", owner: other))
        var runner = iosRunner(repo)
        runner.responses["xcrun simctl spawn A launchctl list"] = running
            ? .ok("PID\tStatus\tLabel\n4242\t0\tUIKitApplication:com.test.MyApp[a1b2][rb-legacy]\n")
            : .failed(1, "Simulator observation failed")
        let result = await WorkflowExecution.run(.down, input: WorkflowInput(project: ProjectInspectionInput(
            directory: repo.root, environment: [:], platform: .ios)), runner: runner, leases: leases)
        #expect(result.exitCode == 1)
        #expect(result.operation.conflict?.owner == other)
        #expect(!runner.log.all.contains { $0.arguments.contains("terminate") || $0.executable == "kill" })
        #expect(result.down?.items.isEmpty == true)
    }

    @Test("an up failure before install leaves a durable unknown device reservation")
    func failedUpKeepsReservation() async throws {
        let repo = try iosProject()
        var runner = iosUpRunner(repo)
        let build = runner.responses.keys.first { $0.hasPrefix("xcodebuild ") && $0.hasSuffix(" build") && $0.contains("id=A") }!
        runner.responses[build] = .failed(65, "compile failed")
        let leases = temporaryLeases()
        let result = await WorkflowExecution.run(.up, input: WorkflowInput(project: ProjectInspectionInput(
            directory: repo.root, environment: [:], platform: .ios), device: "A"), runner: runner, leases: leases)
        #expect(result.exitCode == 1)
        #expect(result.operation.completed.contains("dependencies"))
        #expect(!runner.log.all.contains { $0.executable == "xcrun" && $0.arguments.contains("install") })
        let conflict = try await #require(throws: ResourceConflict.self) {
            try await leases.check(device: .device(.ios, "A"), project: "/work/other") { _ in
                Issue.record("An unfinished reservation must not be observed as a completed app claim")
                return .stopped
            }
        }
        #expect(conflict.owner?.operationId == result.operation.id)
    }

    @Test("a final claim write failure preserves stages, app evidence and cancellation", arguments: [0, 1, 130])
    func claimWriteFailure(launchExit: Int) async throws {
        let repo = try iosProject()
        var runner = iosUpRunner(repo)
        let launch = "xcrun simctl launch A com.test.MyApp"
        if launchExit == 130 { runner.failures[launch] = CancellationError() }
        else if launchExit != 0 { runner.responses[launch] = .failed(1, "launch failed") }
        let leases = temporaryLeases()
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: leases.directory.path) }
        let result = await WorkflowExecution.run(.up, input: WorkflowInput(project: ProjectInspectionInput(
            directory: repo.root, environment: [:], platform: .ios), device: "A"), runner: runner, leases: leases) { event in
                if event.stageId == "launch", event.state != "running" {
                    do { try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: leases.directory.path) }
                    catch { Issue.record("Could not inject claim write failure: \(error)") }
                }
            }
        #expect(result.exitCode == (launchExit == 130 ? 130 : 2))
        #expect(result.up?.context.product?.bundleIdentifier == "com.test.MyApp")
        #expect(result.up?.context.device?.udid == "A")
        #expect(result.operation.completed.contains("build"))
        #expect(result.operation.completed.contains("install"))
        #expect(result.operation.remaining.contains { $0.contains("Could not record the app claim") })
        let conflict = try await #require(throws: ResourceConflict.self) {
            try await leases.check(device: .device(.ios, "A"), project: "/work/other") { _ in
                Issue.record("A failed final write must leave an unknown reservation")
                return .stopped
            }
        }
        #expect(conflict.owner?.operationId == result.operation.id)
    }

    private func temporaryLeases() -> ResourceLeases {
        ResourceLeases(directory: FileManager.default.temporaryDirectory.appendingPathComponent("runstir-leases-\(UUID().uuidString)"))
    }

    private func iosProject(workspaceOnly: Bool = false) throws -> FixtureRepo {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies":{"react-native":"0.81.0"}}"#)
        try repo.write("yarn.lock", "")
        try repo.directory("node_modules")
        try repo.directory(workspaceOnly ? "ios/MyApp.xcworkspace" : "ios/MyApp.xcodeproj")
        let node = try repo.write(".mobile/tool-fixtures/node", "fixture node")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: node.path)
        return repo
    }

    private func iosRunner(_ repo: FixtureRepo, workspaceOnly: Bool = false) -> FakeProcessRunner {
        let target = workspaceOnly ? "-workspace \(repo.url("ios/MyApp.xcworkspace").path)" : "-project \(repo.url("ios/MyApp.xcodeproj").path)"
        let destination = "\(target) -scheme MyApp -configuration Debug -destination generic/platform=iOS Simulator -derivedDataPath \(RunLogs(project: repo.root).url("DerivedData").resolvingSymlinksInPath().path)"
        return FakeProcessRunner(responses: [
            "xcode-select -p": .ok("/test/Xcode"),
            "xcodebuild -version": .ok("Xcode 27.0\nBuild version 18A100"),
            "xcodebuild -checkFirstLaunchStatus": .ok(""),
            "xcrun simctl list runtimes -j": .ok(#"{"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-0","name":"iOS 27.0","version":"27.0","isAvailable":true}]}"#),
            "node --version": .ok("v22.14.0"),
            "/usr/bin/which node": .ok(repo.url(".mobile/tool-fixtures/node").path),
            "\(repo.url(".mobile/tool-fixtures/node").path) --version": .ok("v22.14.0"),
            "yarn --version": .ok("1.22.22"),
            "yarn install --frozen-lockfile": .ok(""),
            "xcodebuild -list -json \(target)": .ok(workspaceOnly ? #"{"workspace":{"schemes":["MyApp"]}}"# : #"{"project":{"schemes":["MyApp"],"configurations":["Debug","Release"]}}"#),
            "xcodebuild \(destination) build": .ok("** BUILD SUCCEEDED **"),
            "xcodebuild -showBuildSettings -json \(destination)": .ok(#"[{"target":"MyApp","buildSettings":{"CONFIGURATION":"Debug","BUILT_PRODUCTS_DIR":"/test/build","FULL_PRODUCT_NAME":"MyApp.app","PRODUCT_BUNDLE_IDENTIFIER":"com.test.MyApp"}}]"#),
        ])
    }

    private func iosUpRunner(_ repo: FixtureRepo) -> FakeProcessRunner {
        var runner = iosRunner(repo)
        let destination = "-project \(repo.url("ios/MyApp.xcodeproj").path) -scheme MyApp -configuration Debug -destination platform=iOS Simulator,id=A -derivedDataPath \(RunLogs(project: repo.root).url("DerivedData").resolvingSymlinksInPath().path)"
        runner.responses["xcrun simctl list devices -j"] = .ok(#"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"name":"iPhone A","udid":"A","state":"Booted","isAvailable":true}]}}"#)
        runner.responses[MetroStatus.command] = .ok(MetroStatus.running(projectRoot: repo.root))
        runner.responses["xcodebuild \(destination) build"] = .ok("** BUILD SUCCEEDED **")
        runner.responses["xcodebuild -showBuildSettings -json \(destination)"] = .ok(#"[{"target":"MyApp","buildSettings":{"CONFIGURATION":"Debug","BUILT_PRODUCTS_DIR":"/test/build","FULL_PRODUCT_NAME":"MyApp.app","PRODUCT_BUNDLE_IDENTIFIER":"com.test.MyApp"}}]"#)
        runner.responses["xcrun simctl install A /test/build/MyApp.app"] = .ok("")
        runner.responses["xcrun simctl terminate A com.test.MyApp"] = .ok("")
        runner.responses["xcrun simctl launch A com.test.MyApp"] = .ok("com.test.MyApp: 3538")
        return runner
    }
}

private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [WorkflowEvent] = []
    func append(_ event: WorkflowEvent) { lock.withLock { events.append(event) } }
    var all: [WorkflowEvent] { lock.withLock { events } }
}

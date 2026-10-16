import Core
@testable import EnvironmentKit
import Foundation
import SimulatorKit
import TestSupport
import Testing

@Suite("iOS resource preparation")
struct IOSPreparationTests {
    @Test("shared setup plans a missing Simulator without creating it before approval")
    func missingSimulatorPlan() async throws {
        let fixture = try IOSPreparationFixture()
        let runner = fixture.runner()
        let result = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: runner)
        #expect(result.exitCode == 0)
        let plan = try #require(result.plan)
        #expect(plan.steps.contains { $0.id == "ios.simulator.create" && $0.kind == "install" })
        #expect(!runner.log.all.contains { $0.arguments.contains("create") || $0.arguments.contains("-downloadPlatform") || $0.arguments.contains("-importPlatform") })
        #expect(try String(contentsOf: fixture.repo.url("package.json"), encoding: .utf8) == fixture.package)
    }

    @Test("approved creation records the actual UDID and state and retries reuse it")
    func approvedCreation() async throws {
        let fixture = try IOSPreparationFixture()
        let runner = IOSPreparationRunner(fixture)
        let plan = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: runner)
        let id = try #require(plan.plan?.id)
        let unapproved = await PreparationExecution.run(input: fixture.input, runner: runner)
        #expect(unapproved.operation.state == "needs-approval")
        #expect(runner.creations == 0)
        let done = await PreparationExecution.run(input: fixture.input, approvedPlanID: id, trustRepository: true,
            runner: runner, leases: fixture.leases)
        #expect(done.operation.completed.contains("ios.simulator.create"), Comment(rawValue: done.operation.error ?? ""))
        let created = try #require(done.operation.resources.first { $0.kind == .simulator })
        #expect(created.identifier == "B38C3447-963B-42CB-959F-F5234F5A1092")
        #expect(created.state == "Shutdown" && created.origin == .created)
        let document = try #require(try JSONSerialization.jsonObject(with: Data(done.encoded(toolVersion: "fixture").utf8)) as? [String: Any])
        let operation = try #require(document["operation"] as? [String: Any])
        let resources = try #require(operation["resources"] as? [[String: Any]])
        #expect(resources.contains { $0["identifier"] as? String == created.identifier })
        #expect(runner.creations == 1)
        let retry = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: runner)
        #expect(try #require(retry.plan).steps.contains { $0.id == "ios.simulator.create" } == false)
        #expect(retry.plan?.resources?.contains { $0.identifier == created.identifier && $0.origin == .reused } == true)
        #expect(!runner.log.contains { ["boot", "delete", "erase", "shutdown"].contains(where: $0.arguments.contains) })
        try fixture.assertPreserved()
    }

    @Test("a pinned missing runtime is installed before creating the approved Simulator")
    func runtimeAndSimulator() async throws {
        let fixture = try IOSPreparationFixture()
        let runner = IOSPreparationRunner(fixture, runtime: false)
        let plan = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: runner)
        let steps = try #require(plan.plan?.steps)
        #expect(steps.contains { $0.id == "ios.runtime.install" && $0.installation?.artifact == nil })
        #expect(steps.contains { $0.id == "ios.simulator.create" })
        #expect(runner.installations == 0 && runner.creations == 0)
        let done = await PreparationExecution.run(input: fixture.input, approvedPlanID: try #require(plan.plan?.id),
            trustRepository: true, runner: runner, leases: fixture.leases)
        #expect(done.operation.completed.contains("ios.runtime.install"), Comment(rawValue: done.operation.error ?? ""))
        #expect(done.operation.completed.contains("ios.simulator.create"))
        #expect(done.operation.resources.contains { $0.kind == .runtime && $0.runtimeBuild == "24A434" && $0.origin == .installed })
        #expect(done.operation.resources.contains { $0.kind == .simulator && $0.state == "Shutdown" && $0.origin == .created })
        #expect(runner.installations == 1 && runner.creations == 1)
        let mutations = runner.log.filter { $0.arguments.contains("-downloadPlatform") || $0.arguments.contains("create") }
        #expect(mutations.first?.arguments == ["-downloadPlatform", "iOS", "-buildVersion", "27.0", "-architectureVariant", "arm64"])
        #expect(mutations.allSatisfy { $0.environment["DEVELOPER_DIR"] == "/test/Xcode" })
        try fixture.assertPreserved()
    }

    @Test("a newly observed Simulator action requires a new approval after runtime completion")
    func remainingCreationApproval() async throws {
        let fixture = try IOSPreparationFixture()
        let runner = IOSPreparationRunner(fixture, runtime: false, deviceTypeAfterRuntime: true)
        let planned = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: runner)
        let original = try #require(planned.plan)
        #expect(original.steps.contains { $0.id == "ios.runtime.install" })
        #expect(!original.steps.contains { $0.id == "ios.simulator.create" })
        let partial = await PreparationExecution.run(input: fixture.input, approvedPlanID: original.id,
            trustRepository: true, runner: runner, leases: fixture.leases)
        #expect(partial.operation.state == "partial")
        #expect(partial.operation.completed.contains("ios.runtime.install"))
        #expect(partial.operation.resources.contains { $0.kind == .runtime && $0.origin == .installed })
        let remaining = try #require(partial.plan)
        #expect(remaining.id != original.id)
        #expect(remaining.steps.contains { $0.id == "ios.simulator.create" })
        #expect(remaining.platforms.first { $0.platform == .ios }?.state == "needs-approval")
        #expect(runner.installations == 1 && runner.creations == 0)
        let stale = await PreparationExecution.run(input: fixture.input, approvedPlanID: original.id,
            trustRepository: true, runner: runner, leases: fixture.leases)
        #expect(stale.operation.state == "needs-approval")
        #expect(runner.installations == 1 && runner.creations == 0)
        let completed = await PreparationExecution.run(input: fixture.input, approvedPlanID: remaining.id,
            trustRepository: true, runner: runner, leases: fixture.leases)
        #expect(completed.operation.completed.contains("ios.simulator.create"))
        #expect(runner.installations == 1 && runner.creations == 1)
        try fixture.assertPreserved()
    }

    @Test("creation failure and cancellation preserve observed completion or block unknown retries",
          arguments: [IOSPreparationRunner.Fault.failBefore, .failAfter, .cancelBefore, .cancelAfter])
    private func creationRecovery(fault: IOSPreparationRunner.Fault) async throws {
        let fixture = try IOSPreparationFixture()
        let runner = IOSPreparationRunner(fixture, fault: fault)
        let plan = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: runner)
        let result = await PreparationExecution.run(input: fixture.input, approvedPlanID: try #require(plan.plan?.id),
            trustRepository: true, runner: runner, leases: fixture.leases)
        #expect(result.exitCode == (fault.cancelled ? 130 : 1))
        let observed = try #require(result.operation.resources.first { $0.kind == .simulator })
        #expect((observed.identifier != nil) == fault.after)
        #expect(observed.state == (fault.after ? "Shutdown" : "unknown"))
        #expect(observed.origin == .unknown)
        #expect(runner.creations == 1)
        let retry = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: runner)
        #expect(retry.plan?.steps.contains { $0.id == "ios.simulator.create" } == false)
        if !fault.after {
            #expect(retry.plan?.steps.contains { $0.observed?.contains("unresolved system state") == true } == true)
        }
        #expect(!runner.log.contains { ["delete", "erase", "shutdown", "boot"].contains(where: $0.arguments.contains) })
        try fixture.assertPreserved()
    }

    @Test("runtime failure and cancellation retain completed installation and never repeat unknown mutations",
          arguments: [IOSPreparationRunner.Fault.failBefore, .failAfter, .cancelBefore, .cancelAfter])
    private func runtimeRecovery(fault: IOSPreparationRunner.Fault) async throws {
        let fixture = try IOSPreparationFixture()
        let runner = IOSPreparationRunner(fixture, runtime: false, fault: fault)
        let plan = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: runner)
        let result = await PreparationExecution.run(input: fixture.input, approvedPlanID: try #require(plan.plan?.id),
            trustRepository: true, runner: runner, leases: fixture.leases)
        #expect(result.exitCode == (fault.cancelled ? 130 : 1))
        let observed = try #require(result.operation.resources.first { $0.kind == .runtime })
        #expect((observed.identifier != nil) == fault.after)
        #expect(observed.origin == .unknown)
        #expect(runner.installations == 1 && runner.creations == 0)
        let retry = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: runner)
        #expect(retry.plan?.steps.contains { $0.id == "ios.runtime.install" } == false)
        #expect(retry.plan?.steps.contains { $0.id == "ios.simulator.create" } == fault.after)
        let stale = await PreparationExecution.run(input: fixture.input, approvedPlanID: try #require(plan.plan?.id),
            trustRepository: true, runner: runner, leases: fixture.leases)
        #expect(stale.operation.state == "needs-approval")
        #expect(runner.installations == 1 && runner.creations == 0)
        try fixture.assertPreserved()
    }

    @Test("an occupied runtime resource lease prevents creation without changing the plan")
    func resourceConflict() async throws {
        let fixture = try IOSPreparationFixture()
        let runner = IOSPreparationRunner(fixture)
        let plan = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: runner)
        let held = try fixture.leases.acquire([.destination(URL(fileURLWithPath: "/Library/Developer/CoreSimulator"))],
            owner: LeaseOwner(operationId: "other", command: "setup", project: "/other"))
        defer { held.release() }
        let result = await PreparationExecution.run(input: fixture.input, approvedPlanID: try #require(plan.plan?.id),
            trustRepository: true, runner: runner, leases: fixture.leases)
        #expect(result.operation.conflict != nil)
        #expect(runner.creations == 0)
    }

    @Test("runtime installation acquires existing device and device-set leases", arguments: [true, false])
    func runtimeResourceConflict(_ deviceLease: Bool) async throws {
        let fixture = try IOSPreparationFixture()
        let identifier = "E00349BB-E8F0-4E8A-B5DD-BF3DDE20FBC0"
        let runner = IOSPreparationRunner(fixture, runtime: false, existingDeviceID: identifier)
        let plan = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: runner)
        #expect(plan.plan?.steps.contains { $0.id == "ios.runtime.install" } == true)
        let key: ResourceKey = deviceLease ? .device(.ios, identifier) : .destination(fixture.deviceSet)
        let held = try fixture.leases.acquire([key],
            owner: LeaseOwner(operationId: "other", command: "up", project: "/other"))
        defer { held.release() }
        let result = await PreparationExecution.run(input: fixture.input, approvedPlanID: try #require(plan.plan?.id),
            trustRepository: true, runner: runner, leases: fixture.leases)
        #expect(result.operation.conflict != nil)
        #expect(runner.installations == 0 && runner.creations == 0)
        try fixture.assertPreserved()
    }

    @Test("plans encoded before iOS resource observations remain decodable")
    func legacyPlanDecoding() async throws {
        let fixture = try IOSPreparationFixture()
        let plan = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: fixture.runner())
        let encoded = try JSONEncoder().encode(try #require(plan.plan))
        var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "resources")
        let decoded = try JSONDecoder().decode(PreparationPlan.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.resources == nil)
        #expect(decoded.id == plan.plan?.id)
    }

    @Test("a changed official runtime pin rejects stale approval before mutation")
    func staleCatalog() async throws {
        let fixture = try IOSPreparationFixture()
        let runner = IOSPreparationRunner(fixture, runtime: false)
        let plan = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: runner)
        runner.changeCatalogBuild()
        let result = await PreparationExecution.run(input: fixture.input, approvedPlanID: try #require(plan.plan?.id),
            trustRepository: true, runner: runner, leases: fixture.leases)
        #expect(result.operation.state == "needs-approval")
        #expect(runner.installations == 0 && runner.creations == 0)
    }
}

@Suite("iOS preparation provider actions")
struct IOSPreparationProviderTests {
    @Test("the provider plans and creates a Simulator without booting or changing existing source")
    func creation() async throws {
        let fixture = try IOSPreparationFixture()
        let runner = IOSPreparationRunner(fixture)
        let plan = try await inspect(fixture, runner)
        let action = try #require(plan.actions["ios.simulator.create"])
        #expect(runner.creations == 0)
        let lease = try fixture.leases.acquire(action.metadata.resourceKeys,
            owner: LeaseOwner(operationId: "fixture", command: "setup", project: fixture.repo.root.path))
        defer { lease.release() }
        let result = try await action.run(runner: runner) { _ in }
        #expect(result.resources.first?.identifier == "B38C3447-963B-42CB-959F-F5234F5A1092")
        #expect(result.resources.first?.state == "Shutdown")
        #expect(result.resources.first?.origin == .created)
        let retry = try await inspect(fixture, runner)
        #expect(retry.actions.isEmpty)
        #expect(retry.resources.contains { $0.kind == .simulator && $0.origin == .reused })
        #expect(!runner.log.contains { ["boot", "delete", "erase", "shutdown"].contains(where: $0.arguments.contains) })
        try fixture.assertPreserved()
    }

    @Test("the runtime action installs the fixed OS and keeps the following creation identity stable")
    func runtimeThenCreate() async throws {
        let fixture = try IOSPreparationFixture()
        let runner = IOSPreparationRunner(fixture, runtime: false)
        let plan = try await inspect(fixture, runner)
        let runtime = try #require(plan.actions["ios.runtime.install"])
        let creation = try #require(plan.actions["ios.simulator.create"])
        let result = try await runtime.run(runner: runner) { _ in }
        #expect(result.resources.first?.runtimeBuild == "24A434")
        #expect(result.resources.first?.origin == .installed)
        let remaining = try await inspect(fixture, runner)
        #expect(remaining.actions["ios.runtime.install"] == nil)
        #expect(remaining.actions["ios.simulator.create"]?.metadata == creation.metadata)
        let created = try await creation.run(runner: runner) { _ in }
        #expect(created.resources.first?.origin == .created)
        #expect(runner.installations == 1 && runner.creations == 1)
        try fixture.assertPreserved()
    }

    @Test("failed or cancelled creation reports actual or unknown resources and prevents blind retry",
          arguments: [IOSPreparationRunner.Fault.failBefore, .failAfter, .cancelBefore, .cancelAfter])
    private func creationRecovery(fault: IOSPreparationRunner.Fault) async throws {
        let fixture = try IOSPreparationFixture()
        let runner = IOSPreparationRunner(fixture, fault: fault)
        let plan = try await inspect(fixture, runner)
        let action = try #require(plan.actions["ios.simulator.create"])
        do {
            _ = try await action.run(runner: runner) { _ in }
            Issue.record("expected controlled failure or cancellation")
        } catch let error as InstallationActionFailure {
            #expect((error.underlying is CancellationError) == fault.cancelled)
            #expect((error.result.resources.first?.identifier != nil) == fault.after)
            #expect(error.result.resources.first?.state == (fault.after ? "Shutdown" : "unknown"))
        }
        let retry = try await inspect(fixture, runner)
        #expect(retry.actions.isEmpty)
        #expect(runner.creations == 1)
        try fixture.assertPreserved()
    }

    @Test("failed or cancelled runtime installation keeps completed resources and blocks unknown retry",
          arguments: [IOSPreparationRunner.Fault.failBefore, .failAfter, .cancelBefore, .cancelAfter])
    private func runtimeRecovery(fault: IOSPreparationRunner.Fault) async throws {
        let fixture = try IOSPreparationFixture()
        let runner = IOSPreparationRunner(fixture, runtime: false, fault: fault)
        let plan = try await inspect(fixture, runner)
        let action = try #require(plan.actions["ios.runtime.install"])
        do {
            _ = try await action.run(runner: runner) { _ in }
            Issue.record("expected controlled failure or cancellation")
        } catch let error as InstallationActionFailure {
            #expect((error.underlying is CancellationError) == fault.cancelled)
            #expect(error.result.resources.first?.origin == .unknown)
            #expect((error.result.resources.first?.identifier != nil) == fault.after)
            if !fault.after { #expect(error.result.resources.first?.runtimeBuild == nil) }
        }
        let retry = try await inspect(fixture, runner)
        #expect(retry.actions["ios.runtime.install"] == nil)
        #expect((retry.actions["ios.simulator.create"] != nil) == fault.after)
        #expect(runner.creations == 0)
        try fixture.assertPreserved()
    }

    private func inspect(_ fixture: IOSPreparationFixture, _ runner: IOSPreparationRunner) async throws -> IOSPreparation {
        let selected = try #require(try fixture.input.selection().selected)
        let anchor = try #require(ProjectAnchor.detect(candidate: selected))
        let context = await WorkflowContext.make(input: fixture.input, platform: .ios, anchor: anchor, runner: runner)
        return try await IOSPreparation.inspect(context: context, input: fixture.input)
    }
}

private final class IOSPreparationFixture {
    let repo: FixtureRepo
    let home: FixtureRepo
    let package = #"{"dependencies":{"react-native":"0.81.0"}}"#
    var input: ProjectInspectionInput {
        ProjectInspectionInput(directory: repo.root, environment: ["HOME": home.root.path])
    }
    var deviceSet: URL { home.url("Library/Developer/CoreSimulator/Devices") }
    var leases: ResourceLeases { ResourceLeases(directory: home.url("leases")) }

    init() throws {
        repo = try FixtureRepo()
        home = try FixtureRepo()
        try repo.write("package.json", package)
        try repo.write("yarn.lock", "")
        try repo.directory("ios/MyApp.xcodeproj")
    }

    func runner() -> FakeProcessRunner {
        FakeProcessRunner(responses: [
            "xcode-select -p": .ok("/test/Xcode"),
            "xcodebuild -version": .ok("Xcode 27.0\nBuild version 18A100"),
            "xcodebuild -checkFirstLaunchStatus": .ok(""),
            "xcrun simctl list runtimes -j": .ok(#"{"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-0","name":"iOS 27.0","version":"27.0","buildversion":"24A434","supportedArchitectures":["arm64"],"isAvailable":true}]}"#),
            "xcrun simctl list devices -j": .ok(#"{"devices":{}}"#),
            "xcrun simctl --set \(deviceSet.path) list devices -j": .ok(#"{"devices":{}}"#),
            "xcrun simctl list devicetypes -j": .ok(#"{"devicetypes":[{"identifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-17","name":"iPhone 17","productFamily":"iPhone","minRuntimeVersionString":"26.0.0","maxRuntimeVersionString":"65535.255.255"}]}"#),
            "node --version": .ok("v22.14.0"),
            "/usr/bin/which node": .ok("/test/bin/node"),
            "/usr/bin/which yarn": .ok("/test/bin/yarn"),
            "yarn --version": .ok("1.22.22"),
            "yarn install --frozen-lockfile": .ok(""),
            "pgrep -x xcodebuild": .failed(1, ""),
            "pgrep -x Simulator": .failed(1, ""),
            "xcodebuild -list -json -project \(repo.url("ios/MyApp.xcodeproj").path)": .ok(#"{"project":{"schemes":["MyApp"]}}"#),
        ])
    }

    func assertPreserved() throws {
        #expect(try String(contentsOf: repo.url("package.json"), encoding: .utf8) == package)
        #expect(try String(contentsOf: repo.url("yarn.lock"), encoding: .utf8) == "")
        #expect(!FileManager.default.fileExists(atPath: repo.url("mobile.yml").path))
    }
}

private final class IOSPreparationRunner: ProcessRunner, @unchecked Sendable {
    enum Fault: Sendable { case failBefore, failAfter, cancelBefore, cancelAfter
        var after: Bool { self == .failAfter || self == .cancelAfter }
        var cancelled: Bool { self == .cancelBefore || self == .cancelAfter }
    }
    let fixture: IOSPreparationFixture
    let base: FakeProcessRunner
    private let lock = NSLock()
    private var runtime: Bool
    private var device = false
    private var catalogBuild = "24A434"
    private var installed = 0
    private var created = 0
    let fault: Fault?
    let existingDeviceID: String?
    let deviceTypeAfterRuntime: Bool
    var installations: Int { lock.withLock { installed } }
    var creations: Int { lock.withLock { created } }
    var log: [ProcessCommand] { base.log.all }

    init(_ fixture: IOSPreparationFixture, runtime: Bool = true, fault: Fault? = nil,
         existingDeviceID: String? = nil, deviceTypeAfterRuntime: Bool = false) {
        self.fixture = fixture; self.base = fixture.runner(); self.runtime = runtime; self.fault = fault
        self.existingDeviceID = existingDeviceID
        self.deviceTypeAfterRuntime = deviceTypeAfterRuntime
    }

    func changeCatalogBuild() { lock.withLock { catalogBuild = "24A999" } }

    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        var answer = base
        if command.arguments == ["simctl", "list", "runtimes", "-j"] {
            let present = lock.withLock { runtime }
            answer.responses[command.description] = .ok(present
                ? #"{"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-0","name":"iOS 27.0","version":"27.0","buildversion":"24A434","supportedArchitectures":["arm64"],"isAvailable":true}]}"#
                : #"{"runtimes":[]}"#)
        } else if command.arguments == ["simctl", "--set", fixture.deviceSet.path, "list", "devices", "-j"] {
            let present = lock.withLock { device }
            var devices: [String: [[String: Any]]] = [:]
            if present {
                devices["com.apple.CoreSimulator.SimRuntime.iOS-27-0"] = [["udid": "B38C3447-963B-42CB-959F-F5234F5A1092",
                    "name": "iPhone 17 - Runstir - iOS 27.0", "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
                    "isAvailable": true, "state": "Shutdown"]]
            }
            if let existingDeviceID {
                devices["com.apple.CoreSimulator.SimRuntime.iOS-26-0"] = [["udid": existingDeviceID, "name": "Existing unavailable Simulator",
                    "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17", "isAvailable": false, "state": "Shutdown"]]
            }
            answer.responses[command.description] = .ok(String(decoding: try JSONSerialization.data(withJSONObject: ["devices": devices]), as: UTF8.self))
        } else if command.arguments == ["simctl", "list", "devicetypes", "-j"], deviceTypeAfterRuntime, !lock.withLock({ runtime }) {
            answer.responses[command.description] = .ok(#"{"devicetypes":[]}"#)
        } else if command.description == IOSRuntimeCatalog.command.description {
            let build = lock.withLock { catalogBuild }
            let catalog: [String: Any] = ["downloadables": [["platform": "com.apple.platform.iphoneos", "downloadMethod": "mobileAsset",
                "contentType": "cryptexDiskImage", "dictionaryVersion": 2, "name": "iOS 27.0 Simulator Runtime",
                "identifier": "fixture-asset", "simulatorVersion": ["version": "27.0", "buildUpdate": build],
                "architectures": ["arm64"], "fileSize": Int64(12)]]]
            let data = try PropertyListSerialization.data(fromPropertyList: catalog, format: .xml, options: 0)
            answer.responses[command.description] = .ok(String(decoding: data, as: UTF8.self))
        } else if command.arguments.contains("-downloadPlatform") || command.arguments.contains("create") {
            let installation = command.arguments.contains("-downloadPlatform")
            lock.withLock {
                if installation { installed += 1 } else { created += 1 }
                if fault == nil || fault?.after == true {
                    if installation { runtime = true } else { device = true }
                }
            }
            if fault?.cancelled == true { answer.failures[command.description] = CancellationError() }
            else if fault != nil { answer.responses[command.description] = .failed(1, "controlled fixture failure") }
            else { answer.responses[command.description] = .ok(installation ? "" : "B38C3447-963B-42CB-959F-F5234F5A1092\n") }
        }
        return try await answer.run(command, onLine: onLine)
    }

    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
        try await base.spawnDetached(command, logFile: logFile)
    }
}

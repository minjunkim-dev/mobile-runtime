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

    @Test("runtime installation reuses an existing Simulator that becomes available")
    func recoveredExistingSimulator() async throws {
        let fixture = try IOSPreparationFixture()
        let runner = IOSPreparationRunner(fixture, runtime: false,
            existingDeviceID: "E00349BB-E8F0-4E8A-B5DD-BF3DDE20FBC0", existingDeviceChange: .available)
        let planned = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: runner)
        let plan = try #require(planned.plan)
        #expect(plan.steps.contains { $0.id == "ios.runtime.install" })
        #expect(plan.steps.contains { $0.id == "ios.simulator.create" })
        let result = await PreparationExecution.run(input: fixture.input, approvedPlanID: plan.id,
            trustRepository: true, runner: runner, leases: fixture.leases)
        #expect(result.exitCode == 1 && result.operation.error == nil, Comment(rawValue: result.operation.error ?? ""))
        #expect(result.operation.state == "partial") // This RN fixture retains unrelated manual preparation.
        #expect(result.operation.completed.contains("ios.runtime.install"))
        #expect(!result.operation.completed.contains("ios.simulator.create"))
        #expect(!result.operation.remaining.contains("ios.runtime.install"))
        #expect(!result.operation.remaining.contains("ios.simulator.create"))
        #expect(result.operation.resources.contains { $0.identifier == "E00349BB-E8F0-4E8A-B5DD-BF3DDE20FBC0"
            && $0.name == "iPhone 17" && $0.origin == .reused && $0.state == "Shutdown" && $0.isAvailable == true })
        #expect(runner.installations == 1 && runner.creations == 0)
        let document = try #require(try JSONSerialization.jsonObject(with: Data(result.encoded(toolVersion: "fixture").utf8)) as? [String: Any])
        let operation = try #require(document["operation"] as? [String: Any])
        let resources = try #require(operation["resources"] as? [[String: Any]])
        #expect(resources.contains { $0["identifier"] as? String == "E00349BB-E8F0-4E8A-B5DD-BF3DDE20FBC0"
            && $0["origin"] as? String == "reused" })
        #expect(!resources.contains { $0["origin"] as? String == "created" })
        #expect(try fixture.journalSnapshot().isEmpty)
        let retry = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: runner)
        #expect(retry.plan?.steps.contains { $0.kind == "install" } == false)
        #expect(retry.plan?.resources?.contains { $0.identifier == "E00349BB-E8F0-4E8A-B5DD-BF3DDE20FBC0"
            && $0.origin == .reused } == true)
        try fixture.assertPreserved()
    }

    @Test("runtime recovery does not approve changed source conditions")
    func recoveredSimulatorChangedApproval() async throws {
        let fixture = try IOSPreparationFixture()
        let runner = IOSPreparationRunner(fixture, runtime: false,
            existingDeviceID: "E00349BB-E8F0-4E8A-B5DD-BF3DDE20FBC0", existingDeviceChange: .approval)
        let planned = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: runner)
        let result = await PreparationExecution.run(input: fixture.input, approvedPlanID: try #require(planned.plan?.id),
            trustRepository: true, runner: runner, leases: fixture.leases)
        #expect(result.exitCode == 1 && result.operation.state == "failed")
        #expect(!result.operation.changedFiles.isEmpty)
        #expect(runner.installations == 1 && runner.creations == 0)
        #expect(try String(contentsOf: fixture.repo.url("mobile.yml"), encoding: .utf8) == "ios:\n  device: Different device\n")
    }

    @Test("recovery rechecks existing devices before skipping or starting creation", arguments: [
        IOSPreparationRunner.ExistingDeviceChange.name, .type, .state
    ])
    fileprivate func recoveredSimulatorChangedAfterInstall(change: IOSPreparationRunner.ExistingDeviceChange) async throws {
        let fixture = try IOSPreparationFixture()
        let runner = IOSPreparationRunner(fixture, runtime: false,
            existingDeviceID: "E00349BB-E8F0-4E8A-B5DD-BF3DDE20FBC0", existingDeviceChange: change,
            lateExistingDeviceChange: true)
        let planned = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: runner)
        let result = await PreparationExecution.run(input: fixture.input, approvedPlanID: try #require(planned.plan?.id),
            trustRepository: true, runner: runner, leases: fixture.leases)
        #expect(result.exitCode == 1 && result.operation.state == "failed")
        #expect(result.operation.completed.contains("ios.runtime.install"))
        #expect(runner.installations == 1 && runner.creations == 0)
        try fixture.assertPreserved()
    }

    @Test("recovered-device reuse rejects source changes before skipping creation", arguments: ["App.swift", "App.js"])
    func recoveredSimulatorChangedSource(file: String) async throws {
        let fixture = try IOSPreparationFixture()
        try fixture.repo.write(file, "original source")
        let runner = IOSPreparationRunner(fixture, runtime: false,
            existingDeviceID: "E00349BB-E8F0-4E8A-B5DD-BF3DDE20FBC0", existingDeviceChange: .available,
            lateSourceChange: file)
        let planned = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: runner)
        let result = await PreparationExecution.run(input: fixture.input, approvedPlanID: try #require(planned.plan?.id),
            trustRepository: true, runner: runner, leases: fixture.leases)
        #expect(result.exitCode == 1 && result.operation.state == "failed")
        #expect(result.operation.changedFiles.count == 1)
        let changedSource = URL(fileURLWithPath: try #require(result.operation.changedFiles.first))
        #expect(changedSource.lastPathComponent == file)
        #expect(try FolderIdentity(directory: changedSource.deletingLastPathComponent()) == FolderIdentity(directory: fixture.repo.root))
        #expect(result.operation.completed == ["ios.runtime.install"])
        #expect(result.operation.resources.contains { $0.kind == .runtime && $0.runtimeBuild == "24A434"
            && $0.origin == .installed && $0.isAvailable == true })
        #expect(runner.installations == 1 && runner.creations == 0)
        #expect(!runner.log.contains { $0.executable == "yarn" && $0.arguments == ["install", "--frozen-lockfile"] })
        #expect(try String(contentsOf: fixture.repo.url(file), encoding: .utf8) == "externally changed source")
        #expect(try fixture.journalSnapshot().isEmpty)
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
        let journal = try fixture.journalSnapshot()
        #expect(journal.count == 1)
        let retry = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: runner)
        #expect(retry.plan != nil)
        #expect(retry.exitCode == 0 && retry.operation.state == "needs-approval")
        #expect(retry.operation.error == nil && retry.operation.completed.isEmpty)
        #expect(retry.operation.nextAction == "Review this plan. Approve only its exact plan-id; repository trust is separate.")
        if !fault.after {
            let blocked = try #require(retry.plan?.steps.first { $0.id == "ios.resources" })
            try fixture.assertManualRecovery(blocked)
            #expect(retry.operation.manual.contains { $0.id == "ios.resources" && $0.kind == "provider" })
            #expect(retry.operation.resources.isEmpty)
        }
        #expect(retry.plan?.steps.contains { $0.id == "ios.runtime.install" } == false)
        #expect(retry.plan?.steps.contains { $0.id == "ios.simulator.create" } == fault.after)
        let stale = await PreparationExecution.run(input: fixture.input, approvedPlanID: try #require(plan.plan?.id),
            trustRepository: true, runner: runner, leases: fixture.leases)
        #expect(stale.operation.state == "needs-approval")
        #expect(runner.installations == 1 && runner.creations == 0)
        #expect(try fixture.journalSnapshot() == journal)
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

    @Test("the runtime provider accepts only availability recovery of preserved devices")
    func existingDeviceAvailability() async throws {
        let fixture = try IOSPreparationFixture()
        let runner = IOSPreparationRunner(fixture, runtime: false,
            existingDeviceID: "E00349BB-E8F0-4E8A-B5DD-BF3DDE20FBC0", existingDeviceChange: .available)
        let planned = try await inspect(fixture, runner)
        let action = try #require(planned.actions["ios.runtime.install"])
        let installed = try await action.run(runner: runner) { _ in }
        #expect(installed.resources.contains { $0.kind == .runtime && $0.origin == .installed })
        let remaining = try await inspect(fixture, runner)
        #expect(remaining.actions.isEmpty)
        #expect(remaining.resources.contains { $0.identifier == "E00349BB-E8F0-4E8A-B5DD-BF3DDE20FBC0"
            && $0.name == "iPhone 17" && $0.origin == .reused && $0.state == "Shutdown" && $0.isAvailable == true })
        #expect(runner.installations == 1 && runner.creations == 0)
        #expect(try fixture.journalSnapshot().isEmpty)
        try fixture.assertPreserved()
    }

    @Test("runtime installation rejects changes beyond target-runtime availability recovery", arguments: [
        IOSPreparationRunner.ExistingDeviceChange.identifier, .name, .type, .runtime, .state, .removed, .unavailable, .unrelatedAvailable
    ])
    fileprivate func changedExistingDevice(change: IOSPreparationRunner.ExistingDeviceChange) async throws {
        let fixture = try IOSPreparationFixture()
        let runner = IOSPreparationRunner(fixture, runtime: false,
            existingDeviceID: "E00349BB-E8F0-4E8A-B5DD-BF3DDE20FBC0", existingDeviceChange: change)
        let planned = try await inspect(fixture, runner)
        let action = try #require(planned.actions["ios.runtime.install"])
        await #expect(throws: InstallationActionFailure.self) { try await action.run(runner: runner) { _ in } }
        #expect(runner.installations == 1 && runner.creations == 0)
        #expect(try fixture.journalSnapshot().count == 1)
        try fixture.assertPreserved()
    }

    @Test("a headless Simulator outside the selected device set blocks global runtime installation")
    func headlessSimulatorBusy() async throws {
        let fixture = try IOSPreparationFixture()
        let runner = IOSPreparationRunner(fixture, runtime: false)
        let plan = try await inspect(fixture, runner)
        let action = try #require(plan.actions["ios.runtime.install"])
        await #expect(throws: DomainError.self) {
            try await action.run(runner: HeadlessSimulatorRunner(base: runner)) { _ in }
        }
        #expect(runner.installations == 0 && runner.creations == 0)
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
        let journal = try fixture.journalSnapshot()
        #expect(journal.count == 1)
        let retry = try await inspect(fixture, runner)
        if !fault.after {
            let blocked = try #require(retry.checks.first { $0.id == "ios.resources" })
            try fixture.assertManualRecovery(blocked)
            #expect(retry.actions.isEmpty && retry.resources.isEmpty)
        }
        #expect(retry.actions["ios.runtime.install"] == nil)
        #expect((retry.actions["ios.simulator.create"] != nil) == fault.after)
        #expect(runner.creations == 0)
        #expect(try fixture.journalSnapshot() == journal)
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
            "pgrep -x launchd_sim": .failed(1, ""),
            "xcodebuild -list -json -project \(repo.url("ios/MyApp.xcodeproj").path)": .ok(#"{"project":{"schemes":["MyApp"]}}"#),
        ])
    }

    func journalSnapshot() throws -> [String: Data] {
        let directory = home.url("Library/Caches/dev.runstir/ios-preparation")
        return try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("attempt-") && $0.pathExtension == "json" }
            .map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
    }

    func assertManualRecovery(_ step: PreparationStep) throws {
        #expect(step.id == "ios.resources" && step.kind == "provider")
        #expect(step.command == nil && step.installation == nil)
        let message = try #require(step.remediation?.summary)
        #expect(step.observed == message)
        #expect(message.contains("iOS 27.0 build 24A434 arm64"))
        #expect(message.contains("Complete its manual installation in the selected Xcode's Components before inspecting again."))
        #expect(message.contains("Preserve the recovery journal and existing resources"))
    }

    func assertPreserved() throws {
        #expect(try String(contentsOf: repo.url("package.json"), encoding: .utf8) == package)
        #expect(try String(contentsOf: repo.url("yarn.lock"), encoding: .utf8) == "")
        #expect(!FileManager.default.fileExists(atPath: repo.url("mobile.yml").path))
    }
}

private final class IOSPreparationRunner: ProcessRunner, @unchecked Sendable {
    enum ExistingDeviceChange: Sendable { case available, identifier, name, type, runtime, state, removed, unavailable, unrelatedAvailable, approval }
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
    private var deviceReadsAfterInstall = 0
    let fault: Fault?
    let existingDeviceID: String?
    let existingDeviceChange: ExistingDeviceChange?
    let lateExistingDeviceChange: Bool
    let lateSourceChange: String?
    let deviceTypeAfterRuntime: Bool
    var installations: Int { lock.withLock { installed } }
    var creations: Int { lock.withLock { created } }
    var log: [ProcessCommand] { base.log.all }

    init(_ fixture: IOSPreparationFixture, runtime: Bool = true, fault: Fault? = nil,
         existingDeviceID: String? = nil, deviceTypeAfterRuntime: Bool = false, existingDeviceChange: ExistingDeviceChange? = nil,
         lateExistingDeviceChange: Bool = false, lateSourceChange: String? = nil) {
        self.fixture = fixture; self.base = fixture.runner(); self.runtime = runtime; self.fault = fault
        self.existingDeviceID = existingDeviceID
        self.existingDeviceChange = existingDeviceChange
        self.lateExistingDeviceChange = lateExistingDeviceChange
        self.lateSourceChange = lateSourceChange
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
            let installed = lock.withLock { runtime }
            let changed = lock.withLock {
                if installed { deviceReadsAfterInstall += 1 }
                return installed && (!lateExistingDeviceChange || deviceReadsAfterInstall > 1)
            }
            if let lateSourceChange, lock.withLock({ deviceReadsAfterInstall == 2 }) {
                try fixture.repo.write(lateSourceChange, "externally changed source")
            }
            var devices: [String: [[String: Any]]] = [:]
            if present {
                devices["com.apple.CoreSimulator.SimRuntime.iOS-27-0"] = [["udid": "B38C3447-963B-42CB-959F-F5234F5A1092",
                    "name": "iPhone 17 - Runstir - iOS 27.0", "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
                    "isAvailable": true, "state": "Shutdown"]]
            }
            if let existingDeviceID {
                var runtimeID = existingDeviceChange == nil || existingDeviceChange == .unavailable || existingDeviceChange == .unrelatedAvailable
                    ? "com.apple.CoreSimulator.SimRuntime.iOS-26-0" : "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
                var existing: [String: Any] = ["udid": existingDeviceID,
                    "name": existingDeviceChange == nil ? "Existing unavailable Simulator" : "iPhone 17",
                    "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
                    "isAvailable": existingDeviceChange == .unavailable ? !changed : existingDeviceChange != nil && installed,
                    "state": "Shutdown"]
                if changed {
                    switch existingDeviceChange {
                    case .identifier: existing["udid"] = "3B638FA1-5C11-416A-88B8-756633B5B7D5"
                    case .name: existing["name"] = "Renamed iPhone 17"
                    case .type: existing["deviceTypeIdentifier"] = "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
                    case .runtime: runtimeID = "com.apple.CoreSimulator.SimRuntime.iOS-26-0"
                    case .state: existing["state"] = "Booted"
                    default: break
                    }
                }
                if existingDeviceChange != .removed || !changed { devices[runtimeID, default: []].append(existing) }
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
            if installation && existingDeviceChange == .approval {
                try fixture.repo.write("mobile.yml", "ios:\n  device: Different device\n")
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

private struct HeadlessSimulatorRunner: ProcessRunner {
    let base: IOSPreparationRunner

    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        if command.executable == "pgrep", command.arguments == ["-x", "launchd_sim"] {
            return ProcessResult(terminationStatus: .exited(0), standardOutput: "12345\n", standardError: "")
        }
        return try await base.run(command, onLine: onLine)
    }

    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
        try await base.spawnDetached(command, logFile: logFile)
    }
}

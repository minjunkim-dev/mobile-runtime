import Core
import CryptoKit
import Darwin
import Foundation
import SimulatorKit

/// The shared setup executor owns approval and leases. This provider owns only iOS preparation.
struct IOSPreparation {
    var checks: [PreparationStep] = []
    var installed: [String: Bool] = [:]
    var actions: [String: InstallationAction] = [:]
    var resources: [IOSPreparationResource] = []
    private static let runtimeRoot = URL(fileURLWithPath: "/Library/Developer/CoreSimulator")
    private static let candidateOS = "27.0"

    static func inspect(context: WorkflowContext, input: ProjectInspectionInput) async throws -> Self {
        var plan = Self()
        do {
            let xcode = try await context.locator.locate()
            guard let version = SemanticVersion(xcode.version), let floor = SemanticVersion("27.0"), version >= floor else {
                throw failure("Install a supported Xcode 27.0 or newer manually, then inspect again")
            }
            let ready = try await XcodeReadyCheck(runner: context.runner, locator: context.locator).run()
            guard ready.status == .pass else {
                plan.checks = [blocker("xcode", ready.remediation?.summary ?? ready.reason ?? "Finish selected Xcode setup and recheck", kind: "license")]
                return plan
            }
            guard let minimum = try await minimumOS(context) else {
                throw failure("The selected app's iOS deployment requirement is unknown. Select its shared scheme and resolve its declared dependencies manually, then re-plan.")
            }
            let deviceSet = devicesDirectory(input)
            let environment = ["DEVELOPER_DIR": xcode.developerDirectory]
            let inventory = try await IOSResourceInventory.load(runner: context.runner, environment: environment, deviceSet: deviceSet)
            if try unresolvedAttempt(in: recoveryDirectory(deviceSet), inventory: inventory) {
                throw failure("An earlier iOS preparation has an unresolved system state. Check the selected Xcode's Components and Simulator state, then inspect again. Do not start another installation or creation while that state is unknown.")
            }
            let compatible = inventory.compatibleRuntimes(minimum: minimum, architecture: "arm64")
            if let device = inventory.existing(minimum: minimum, architecture: "arm64", declared: context.config.configuration?.device),
               let runtime = compatible.first(where: { $0.identifier == device.runtimeIdentifier }) {
                plan.resources = [inventory.resource(runtime, architecture: "arm64", origin: .reused),
                                  inventory.resource(device, architecture: "arm64", origin: .reused)]
                plan.checks = [reuse("runtime", runtime.identifier, "iOS \(runtime.version) build \(runtime.build ?? "unknown") arm64"),
                               reuse("simulator", device.identifier, "\(device.name): \(device.state)")]
                return plan
            }
            let runtimeIDs = Set(compatible.map(\.identifier))
            guard !inventory.devices.contains(where: {
                runtimeIDs.contains($0.runtimeIdentifier) && ($0.deviceTypeIdentifier == nil || !["Shutdown", "Booted"].contains($0.state))
            }) else {
                throw failure("An existing Simulator has an unresolved device type or state. Inspect it before planning another device.")
            }
            let runtimeID: String
            let runtimeVersion: String
            let runtimeBuild: String
            if let runtime = compatible.first, let build = runtime.build {
                runtimeID = runtime.identifier; runtimeVersion = runtime.version; runtimeBuild = build
                plan.resources = [inventory.resource(runtime, architecture: "arm64", origin: .reused)]
                plan.checks.append(reuse("runtime", runtime.identifier, "iOS \(runtime.version) build \(build) arm64"))
            } else {
                guard let candidate = SemanticVersion(candidateOS), minimum.isSatisfied(by: candidate) else {
                    throw failure("The fixed iOS \(candidateOS) runtime candidate does not satisfy this app. No newer, older or beta runtime will be substituted.")
                }
                guard !inventory.runtimes.contains(where: { $0.version == candidateOS }) else {
                    throw failure("The required runtime exists but its availability, build or architecture is not confirmed. Preserve it and repair the selected Xcode manually, then re-plan.")
                }
                guard inventory.devices.allSatisfy({ $0.state == "Shutdown" }) else {
                    throw failure("Runtime installation requires every existing Simulator to be Shutdown. Finish the owning iOS work and inspect again; setup does not stop it.")
                }
                let catalog = try await IOSRuntimeCatalog.load(runner: context.runner)
                let pin = try catalog.pin(version: candidateOS, architecture: "arm64", xcode: xcode,
                    existingDeviceIDs: inventory.devices.map(\.identifier), deviceSet: deviceSet)
                runtimeID = pin.identifier; runtimeVersion = pin.version; runtimeBuild = pin.build
                let metadata = InstallationMetadata(package: "ios.runtime", revision: pin.build,
                    destination: runtimeRoot, resourceRoot: runtimeRoot, managed: .iosRuntime(pin),
                    repositoryURL: pin.catalogURL, repositorySHA256: pin.catalogSHA256, requiredFile: "")
                try metadata.validate()
                plan.checks.append(PreparationStep(id: "ios.runtime.install", platform: .ios, kind: "install", target: runtimeRoot.path,
                    observed: "absent; existing Simulators are Shutdown", required: metadata.inspectionLine + "; recovery state: \(recoveryDirectory(deviceSet).path)",
                    source: CheckSource(tier: 1, origin: "Apple runtime catalog; SHA-256 \(pin.catalogSHA256)"), command: nil,
                    remediation: Remediation(summary: "The selected Xcode downloads and verifies this Apple-managed runtime. Payload checksum is not exposed. Xcode/account/license/administrator actions remain manual. Existing resources are preserved.")))
                plan.checks[plan.checks.count - 1].installation = metadata
                plan.actions["ios.runtime.install"] = InstallationAction(metadata: metadata, returning: { runner, beforeCommit in
                    try await install(pin, runner: runner, beforeCommit: beforeCommit)
                })
            }
            let request = try inventory.creation(runtimeID: runtimeID, version: runtimeVersion, build: runtimeBuild,
                architecture: "arm64", declared: context.config.configuration?.device, xcode: xcode, deviceSet: deviceSet)
            let metadata = InstallationMetadata(package: "ios.simulator", revision: runtimeBuild,
                destination: deviceSet, resourceRoot: deviceSet, managed: .iosSimulator(request), requiredFile: "")
            try metadata.validate()
            var step = PreparationStep(id: "ios.simulator.create", platform: .ios, kind: "install", target: deviceSet.path,
                observed: "no compatible selected Simulator", required: metadata.inspectionLine + "; recovery state: \(recoveryDirectory(deviceSet).path)",
                source: CheckSource(tier: 1, origin: "Selected Xcode device types and runtime identities"), command: nil,
                remediation: Remediation(summary: "Create this exact device without booting it. Existing names and devices are never replaced."))
            step.installation = metadata
            plan.checks.append(step)
            plan.actions[step.id] = InstallationAction(metadata: metadata, returning: { runner, beforeCommit in
                try await create(request, runner: runner, beforeCommit: beforeCommit)
            })
        } catch is CancellationError { throw CancellationError() }
        catch let error as DomainError { plan.checks.append(blocker("resources", error.message)) }
        return plan
    }

    private static func minimumOS(_ context: WorkflowContext) async throws -> MinimumVersion? {
        let configured: MinimumVersion?
        if case .requirement(let minimum, _) = context.lookup?.runtime { configured = minimum }
        else { configured = nil }
        guard let anchor = context.anchor, anchor.framework == .nativeIOS else { return configured }
        let candidates = try await IOSWorkflowCandidates.load(anchor: anchor, config: context.config, lookup: context.lookup,
            runner: context.projectRunner, locator: context.locator, includeDevices: false)
        guard let declared = candidates.deploymentTarget.flatMap(MinimumVersion.init) else { return nil }
        return configured.map { declared.exceeds($0) ? declared : $0 } ?? declared
    }

    private static func devicesDirectory(_ input: ProjectInspectionInput) -> URL {
        let home = input.environment["HOME"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Developer/CoreSimulator/Devices").standardizedFileURL
    }

    private static func recoveryDirectory(_ deviceSet: URL) -> URL {
        var home = deviceSet
        for _ in 0..<4 { home.deleteLastPathComponent() }
        return home.appendingPathComponent("Library/Caches/dev.runstir/ios-preparation")
    }

    private static func reuse(_ id: String, _ target: String, _ observed: String) -> PreparationStep {
        PreparationStep(id: "ios.\(id)", platform: .ios, kind: "reuse", target: target, observed: observed,
            required: "Compatible existing iOS resource", source: CheckSource(origin: "Selected Xcode and simctl"), command: nil, remediation: nil)
    }

    private static func blocker(_ id: String, _ message: String, kind: String = "provider") -> PreparationStep {
        PreparationStep(id: "ios.\(id)", platform: .ios, kind: kind, target: "Selected Xcode and CoreSimulator",
            observed: message, required: "Known compatible runtime and Simulator identities", source: CheckSource(origin: "iOS preparation"),
            command: nil, remediation: Remediation(summary: message,
                url: "https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components"))
    }

    private static func failure(_ message: String) -> DomainError {
        DomainError(summary: message, remediation: Remediation(summary: "Preserve existing and completed resources. Finish the listed manual Xcode/account/license/permission action, then inspect and approve the remaining plan."))
    }

    private static func checkXcode(directory: String, version: String, build: String, runner: any ProcessRunner) async throws {
        let locator = XcodeLocator(runner: runner, developerDirOverride: directory)
        let current = try await locator.locate()
        guard current.version == version, current.build == build,
              try await XcodeReadyCheck(runner: runner, locator: locator).run().status == .pass else {
            throw failure("The selected Xcode identity or its initial setup changed. No new iOS resource mutation started.")
        }
    }

    private static func install(_ pin: IOSRuntimePin, runner: any ProcessRunner,
                                beforeCommit: @Sendable ([URL]) async throws -> Void) async throws -> InstallationActionResult {
        try await beforeCommit([])
        try await checkXcode(directory: pin.developerDirectory, version: pin.xcodeVersion, build: pin.xcodeBuild, runner: runner)
        let environment = ["DEVELOPER_DIR": pin.developerDirectory]
        let before = try await IOSResourceInventory.load(runner: runner, environment: environment, deviceSet: pin.deviceSet)
        guard before.devices.map(\.identifier).sorted() == pin.existingDeviceIDs,
              before.devices.allSatisfy({ $0.state == "Shutdown" }),
              !before.runtimes.contains(where: { $0.identifier == pin.identifier }) else {
            throw failure("Runtime or existing Simulator conditions changed before installation")
        }
        // Headless Simulators can belong to device sets outside the selected HOME.
        for process in ["xcodebuild", "Simulator", "launchd_sim"] {
            let result = try await runner.run(ProcessCommand("pgrep", ["-x", process], timeout: .seconds(10)))
            guard result.terminationStatus == .exited(1), result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw failure("Another \(process) operation may be active. Finish it and inspect again. Setup will not stop it.")
            }
        }
        let catalog = try await IOSRuntimeCatalog.load(runner: runner)
        let xcode = try await XcodeLocator(runner: runner, developerDirOverride: pin.developerDirectory).locate()
        guard try catalog.pin(version: pin.version, architecture: pin.architecture, xcode: xcode,
            existingDeviceIDs: before.devices.map(\.identifier), deviceSet: pin.deviceSet) == pin else {
            throw failure("The official runtime pin changed before installation")
        }
        let journal = try Attempt.write(.iosRuntime(pin), deviceSet: pin.deviceSet)
        var resources: [IOSPreparationResource] = []
        do {
            try Task.checkCancellation()
            let result = try await runner.run(ProcessCommand("xcodebuild", ["-downloadPlatform", "iOS", "-buildVersion", pin.version,
                "-architectureVariant", pin.architecture], environment: environment, timeout: nil))
            let after = try await observe(runner: runner, environment: environment, deviceSet: pin.deviceSet)
            if let runtime = after.runtimes.first(where: { $0.identifier == pin.identifier }) {
                resources = [after.resource(runtime, architecture: pin.architecture,
                    origin: result.terminationStatus.isSuccess && exactRuntime(pin, in: after) != nil ? .installed : .unknown)]
            }
            guard result.terminationStatus.isSuccess, exactRuntime(pin, in: after) != nil else {
                throw failure("The selected Xcode did not confirm installation of the approved OS build and architecture. Check Components, account access, license and permissions manually.")
            }
            guard preservesDevices(before.devices, after: after.devices, installedRuntimeID: pin.identifier) else {
                throw failure("An existing Simulator observation changed during runtime installation. Its cause is unknown. Inspect it manually; no resource was restored or removed.")
            }
            try Task.checkCancellation()
            journal.removeIfOwned()
            return InstallationActionResult(resources: resources)
        } catch {
            if resources.isEmpty {
                let after = try? await observe(runner: runner, environment: environment, deviceSet: pin.deviceSet)
                if let after, let runtime = exactRuntime(pin, in: after) {
                    resources = [after.resource(runtime, architecture: pin.architecture, origin: .unknown)]
                } else {
                    resources = [IOSPreparationResource(kind: .runtime, identifier: nil, runtimeIdentifier: pin.identifier,
                        runtimeBuild: nil, version: nil, architecture: nil,
                        state: "unknown", isAvailable: nil, origin: .unknown)]
                }
            }
            throw InstallationActionFailure(underlying: error, result: InstallationActionResult(resources: resources))
        }
    }

    private static func create(_ request: IOSSimulatorRequest, runner: any ProcessRunner,
                               beforeCommit: @Sendable ([URL]) async throws -> Void) async throws -> InstallationActionResult {
        try await beforeCommit([])
        try await checkXcode(directory: request.developerDirectory, version: request.xcodeVersion, build: request.xcodeBuild, runner: runner)
        let environment = ["DEVELOPER_DIR": request.developerDirectory]
        let before = try await IOSResourceInventory.load(runner: runner, environment: environment, deviceSet: request.deviceSet)
        guard let runtime = before.runtimes.first(where: { $0.identifier == request.runtimeIdentifier }),
              runtime.available, runtime.build == request.runtimeBuild, runtime.version == request.runtimeVersion,
              runtime.architectures?.contains(request.architecture) == true else { throw failure("The approved runtime is not available with its exact build and architecture") }
        let xcode = try await XcodeLocator(runner: runner, developerDirOverride: request.developerDirectory).locate()
        guard try before.creation(runtimeID: request.runtimeIdentifier, version: request.runtimeVersion,
            build: request.runtimeBuild, architecture: request.architecture, declared: request.name.contains(" - Runstir - iOS ") ? nil : request.name,
            xcode: xcode, deviceSet: request.deviceSet) == request else { throw failure("Simulator creation conditions changed") }
        let journal = try Attempt.write(.iosSimulator(request), deviceSet: request.deviceSet)
        var resources: [IOSPreparationResource] = []
        do {
            try Task.checkCancellation()
            let result = try await runner.run(ProcessCommand("xcrun", ["simctl", "--set", request.deviceSet.path,
                "create", request.name, request.deviceTypeIdentifier, request.runtimeIdentifier], environment: environment, timeout: .seconds(120)))
            let identifier = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            let after = try await observe(runner: runner, environment: environment, deviceSet: request.deviceSet)
            if let device = matchingDevice(request, in: after), device.identifier == identifier, UUID(uuidString: identifier) != nil {
                resources = [after.resource(device, architecture: request.architecture,
                    origin: result.terminationStatus.isSuccess ? .created : .unknown)]
            }
            guard result.terminationStatus.isSuccess, resources.first?.state == "Shutdown", resources.first?.isAvailable == true else {
                throw failure("Simulator creation did not confirm the returned identity and actual Shutdown state. Existing devices and any completed creation were preserved.")
            }
            try Task.checkCancellation()
            journal.removeIfOwned()
            return InstallationActionResult(resources: resources)
        } catch {
            if resources.isEmpty {
                let after = try? await observe(runner: runner, environment: environment, deviceSet: request.deviceSet)
                if let after, let device = matchingDevice(request, in: after) {
                    resources = [after.resource(device, architecture: request.architecture, origin: .unknown)]
                } else {
                    resources = [IOSPreparationResource(kind: .simulator, identifier: nil, name: request.name,
                        runtimeIdentifier: request.runtimeIdentifier, runtimeBuild: request.runtimeBuild, version: request.runtimeVersion,
                        architecture: request.architecture, deviceTypeIdentifier: request.deviceTypeIdentifier,
                        state: "unknown", isAvailable: nil, origin: .unknown)]
                }
            }
            throw InstallationActionFailure(underlying: error, result: InstallationActionResult(resources: resources))
        }
    }

    /// Cancellation stops mutations. A separate bounded read observes what the OS actually completed.
    private static func observe(runner: any ProcessRunner, environment: [String: String], deviceSet: URL) async throws -> IOSResourceInventory {
        try await Task.detached { try await IOSResourceInventory.load(runner: runner, environment: environment, deviceSet: deviceSet) }.value
    }

    private static func exactRuntime(_ pin: IOSRuntimePin, in inventory: IOSResourceInventory) -> IOSResourceInventory.Runtime? {
        inventory.runtimes.first { $0.identifier == pin.identifier && $0.version == pin.version && $0.build == pin.build
            && $0.architectures?.contains(pin.architecture) == true && $0.available }
    }

    static func preservesDevices(_ before: [IOSResourceInventory.Device], after: [IOSResourceInventory.Device], installedRuntimeID: String) -> Bool {
        before.map(\.identifier).sorted() == after.map(\.identifier).sorted() && before.allSatisfy { device in
            guard let observed = after.first(where: { $0.identifier == device.identifier }) else { return false }
            return observed.name == device.name && observed.deviceTypeIdentifier == device.deviceTypeIdentifier
                && observed.runtimeIdentifier == device.runtimeIdentifier && observed.state == device.state
                && (observed.available == device.available
                    || (!device.available && observed.available && device.runtimeIdentifier == installedRuntimeID))
        }
    }

    private static func matchingDevice(_ request: IOSSimulatorRequest, in inventory: IOSResourceInventory) -> IOSResourceInventory.Device? {
        let matches = inventory.devices.filter { $0.name == request.name && $0.runtimeIdentifier == request.runtimeIdentifier
            && $0.deviceTypeIdentifier == request.deviceTypeIdentifier }
        return matches.count == 1 ? matches.first : nil
    }

    private static func unresolvedAttempt(in directory: URL, inventory: IOSResourceInventory) throws -> Bool {
        guard FileManager.default.fileExists(atPath: directory.path) else { return false }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        for file in files where file.lastPathComponent.hasPrefix("attempt-") && file.pathExtension == "json" {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 65_537) <= 65_536,
                  let attempt = try? JSONDecoder().decode(Attempt.Record.self, from: Data(contentsOf: file)) else { return true }
            switch attempt.identity {
            case .iosRuntime(let pin):
                if exactRuntime(pin, in: inventory) == nil {
                    throw failure("An earlier iOS preparation has an unresolved system state for iOS \(pin.version) build \(pin.build) \(pin.architecture). Check the selected Xcode's Components and Simulator state first. Complete its manual installation in the selected Xcode's Components before inspecting again. Preserve the recovery journal and existing resources while installation or system state remains unconfirmed. Do not start another installation or creation while that state is unknown.")
                }
            case .iosSimulator(let request):
                guard let device = matchingDevice(request, in: inventory), device.available,
                      ["Shutdown", "Booted"].contains(device.state) else { return true }
            }
        }
        return false
    }

    private struct Attempt {
        struct Record: Codable { let id: UUID; let identity: ManagedInstallation }
        let file: URL
        let bytes: Data

        static func write(_ identity: ManagedInstallation, deviceSet: URL) throws -> Self {
            let directory = recoveryDirectory(deviceSet)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let bytes = try encoder.encode(Record(id: UUID(), identity: identity))
            let identityBytes = try encoder.encode(identity)
            let digest = SHA256.hash(data: identityBytes).map { String(format: "%02x", $0) }.joined()
            let file = directory.appendingPathComponent("attempt-\(digest).json")
            let temporary = directory.appendingPathComponent(".stage-\(UUID().uuidString)")
            try bytes.write(to: temporary, options: .withoutOverwriting)
            defer { try? FileManager.default.removeItem(at: temporary) }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            let handle = try FileHandle(forWritingTo: temporary)
            try handle.synchronize(); try handle.close()
            guard link(temporary.path, file.path) == 0 else { throw failure("A prior iOS preparation attempt must be inspected before retrying") }
            return Self(file: file, bytes: bytes)
        }

        func removeIfOwned() {
            if (try? Data(contentsOf: file)) == bytes { try? FileManager.default.removeItem(at: file) }
        }
    }
}

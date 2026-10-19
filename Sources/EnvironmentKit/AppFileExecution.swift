import AndroidKit
import Core
import Foundation
import SimulatorKit

public struct AppFileInput: Sendable {
    public let file: URL
    public let environment: [String: String]
    public let device: String?

    public init(file: URL, environment: [String: String], device: String? = nil) {
        self.file = file
        self.environment = environment
        self.device = device
    }
}

public struct AppFileResult: Sendable {
    public let operation: AppFileOperation
    public let exitCode: Int32

    public func encoded(toolVersion: String) throws -> String {
        struct Document: Encodable {
            let schemaVersion: Int
            let toolVersion: String
            let command: String
            let status: String
            let operation: AppFileOperation
        }
        return try JSONOutput.encode(Document(schemaVersion: JSONOutput.schemaVersion,
            toolVersion: toolVersion, command: operation.command, status: operation.state, operation: operation))
    }
}

/// Human CLI output only. Structured output and approval inputs retain original values.
public enum AppFileHumanOutput {
    public static func lines(_ result: AppFileResult) -> (output: [String], errors: [String]) {
        let operation = result.operation
        var output = ["\(operation.command): \(operation.state)"]
        var errors: [String] = []
        if let artifact = operation.artifact {
            output += ["file: \(artifact.file.path)",
                "origin: \(artifact.origin) — producer trust and safety are unverified",
                "\(artifact.contentIdentityAlgorithm): \(artifact.contentIdentity)",
                "\(artifact.metadata.platform.rawValue): \(artifact.metadata.appID), version \(artifact.metadata.version ?? "unknown"), build \(artifact.metadata.build)",
                "architecture: \(artifact.metadata.architectures.joined(separator: ", ")); minimum OS: \(artifact.metadata.minimumOS)",
                artifact.metadata.signatureCondition]
            if let signer = artifact.metadata.signingIdentity { output.append("signer SHA-256: \(signer)") }
        }
        for device in operation.devices {
            output.append("device: \(device.id) — \(device.name), OS \(device.os), \(device.architectures.joined(separator: ", ")), \(device.ready ? "ready" : "manual preparation required")")
        }
        if let plan = operation.plan {
            output += ["plan-id: \(plan.id)",
                "target: \(plan.device.id); installed: \(plan.installed.state), version \(plan.installed.version ?? "unknown"), build \(plan.installed.build ?? "unknown")",
                "approval: \(plan.approval)"]
            errors += plan.warnings
        }
        output += ["installation: \(operation.installation); launch request: \(operation.launch); running: \(operation.running); first screen: \(operation.firstScreen)",
            "external server: \(operation.externalServer)"]
        if let error = operation.error { errors.append(error) }
        if let next = operation.nextAction { output.append(next) }
        return (output.map(escape), errors.map(escape))
    }

    public static func progress(_ event: WorkflowEvent) -> String {
        escape("\(event.stageId ?? event.kind): \(event.state)\(event.detail.map { " — \($0)" } ?? "")")
    }

    private static func escape(_ value: String) -> String {
        value.unicodeScalars.map { scalar in
            CharacterSet.controlCharacters.contains(scalar)
                ? String(format: "\\u{%04X}", scalar.value) : String(scalar)
        }.joined()
    }
}

/// CLI and GUI share file inspection, exact approval, leases and observed results.
public enum AppFileExecution {
    public static func run(input: AppFileInput, inspectOnly: Bool = false, planOnly: Bool = false,
                           approvedPlanID: String? = nil, runner suppliedRunner: (any ProcessRunner)? = nil,
                           leases: ResourceLeases = .user,
                           onEvent: @escaping @Sendable (WorkflowEvent) -> Void = { _ in }) async -> AppFileResult {
        var operation = AppFileOperation(id: UUID().uuidString, command: inspectOnly ? "app inspect" : "app run")
        let events = WorkflowEvents(id: operation.id, callback: onEvent)
        events.send("started", state: operation.state)
        let runner = suppliedRunner ?? SystemProcessRunner(environment: input.environment)
        var provider: AppFileProvider?
        var selected: AppFileDevice?
        var installationRequested = false
        var stageDirectory: URL?
        defer {
            if let stageDirectory { try? FileManager.default.removeItem(at: stageDirectory) }
        }
        do {
            try Task.checkCancellation()
            let first = try AppFileSnapshot.read(input.file)
            let file = URL(fileURLWithPath: first.identity.path)
            let tools = try AppFileProvider(file: file, runner: runner, environment: input.environment)
            provider = tools
            let artifact = try await inspect(file: file, first: first, provider: tools)
            operation.artifact = artifact
            operation.completed.append("inspect")
            events.send("stage", stage: "inspect", state: "succeeded", detail: "\(artifact.metadata.appID), \(artifact.contentIdentityAlgorithm) \(artifact.contentIdentity)")
            operation.devices = try await tools.devices()
            guard let deviceID = input.device else {
                operation.state = inspectOnly ? "succeeded" : "needs-selection"
                if !inspectOnly { operation.requiredInput = ["--device"] }
                operation.nextAction = "Select a listed, prepared and booted virtual device. No installation was requested."
                return finish(operation, code: inspectOnly ? 0 : 1, events: events)
            }
            guard let device = operation.devices.first(where: { $0.id == deviceID }) else {
                throw AppFileSnapshot.failure("The selected device is absent or disconnected. Select a current candidate; Runstir will not switch targets.")
            }
            selected = device
            try compatible(artifact.metadata, device: device)
            let installed = try await tools.installed(appID: artifact.metadata.appID, device: device)
            operation.installed = installed
            let plan = try makePlan(artifact: artifact, device: device, installed: installed)
            operation.plan = plan
            if inspectOnly || planOnly {
                operation.state = "planned"
                operation.nextAction = "Review the file, target, replacement and warnings. Approve exactly: \(plan.approval)"
                return finish(operation, code: 0, events: events)
            }
            guard approvedPlanID == plan.approval else {
                operation.state = "needs-approval"
                operation.requiredInput = ["--approve"]
                operation.nextAction = "Inspect and approve the current plan: \(plan.approval). An older or unorderable build requires its DOWNGRADE risk acknowledgement."
                return finish(operation, code: 1, events: events)
            }

            let owner = LeaseOwner(operationId: operation.id, command: "app run \(artifact.file.path)",
                project: ResourceKey.appFile(artifact.file).rawValue + ":app:" + artifact.metadata.appID)
            let deviceKey = ResourceKey.device(artifact.metadata.platform, device.id)
            let lease = try leases.acquire([.appFile(artifact.file), .appFileObject(artifact.file), deviceKey,
                .app(artifact.metadata.platform, device: device.handle, appID: artifact.metadata.appID)], owner: owner)
            defer { lease.release() }
            try await leases.check(device: deviceKey, project: owner.project) { claim in
                try await tools.observe(claim)
            }
            try Task.checkCancellation()

            // Install only the approved bytes. A later source change cannot redirect
            // the platform installer to an unapproved file or an external bundle link.
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("dev.runstir-app-file-\(operation.id)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700])
            stageDirectory = directory
            let staged = directory.appendingPathComponent(file.lastPathComponent)
            events.send("stage", stage: "snapshot", state: "running",
                detail: "Copying only the approved input into this operation's private stage. Cancellation waits for the filesystem copy to return; installation has not started.")
            try FileManager.default.copyItem(at: file, to: staged)
            let stagedSnapshot = try AppFileSnapshot.read(staged)
            guard stagedSnapshot.digest == artifact.contentIdentity,
                  try await tools.metadata(staged) == artifact.metadata else {
                throw AppFileSnapshot.failure("The copied app bytes or metadata differ from the approved file.")
            }
            let current = try await inspect(file: file, first: AppFileSnapshot.read(file), provider: tools)
            let currentDevices = try await tools.devices()
            guard let currentDevice = currentDevices.first(where: { $0.id == deviceID }) else {
                throw AppFileSnapshot.failure("The approved device disconnected before installation.")
            }
            try compatible(current.metadata, device: currentDevice)
            let currentInstalled = try await tools.installed(appID: current.metadata.appID, device: currentDevice)
            let currentPlan = try makePlan(artifact: current, device: currentDevice, installed: currentInstalled)
            operation.artifact = current
            operation.devices = currentDevices
            operation.installed = currentInstalled
            operation.plan = currentPlan
            guard currentPlan.id == plan.id else {
                operation.state = "needs-approval"
                operation.nextAction = "The file, device or installed app changed. Review the new plan and approve it again."
                return finish(operation, code: 1, events: events)
            }
            selected = currentDevice
            // Check the shared ownership boundary again immediately before mutation.
            try await leases.check(device: deviceKey, project: owner.project) { claim in
                try await tools.observe(claim)
            }
            try Task.checkCancellation()
            try leases.reserve(device: deviceKey, owner: owner)
            installationRequested = true
            operation.installation = "requested"
            events.send("stage", stage: "install", state: "running")
            try await tools.install(file: staged, device: currentDevice)
            let observed = try await tools.installed(appID: artifact.metadata.appID, device: currentDevice)
            operation.installed = observed
            guard observed.state == "installed", observed.build == artifact.metadata.build else {
                throw AppFileSnapshot.failure("The installer returned, but the selected app and build were not observed as installed. No launch was requested.")
            }
            operation.installation = "installed"
            operation.completed.append("install")
            events.send("stage", stage: "install", state: "succeeded", detail: "The selected app build is observed as installed; existing data was not cleared.")
            let claim = ResourceClaim(device: deviceKey, platform: artifact.metadata.platform,
                handle: currentDevice.handle, appID: artifact.metadata.appID, owner: owner)
            try leases.record(claim)
            try Task.checkCancellation()
            operation.launch = "requested"
            events.send("stage", stage: "launch", state: "running")
            try await tools.launch(metadata: artifact.metadata, device: currentDevice)
            operation.launch = "accepted"
            operation.completed.append("launch")
            switch try await tools.observe(claim) {
            case .running(let detail): operation.running = "running: " + detail
            case .stopped: operation.running = "stopped"
            case .unknown(let detail): operation.running = "unknown: " + detail
            }
            operation.state = operation.running.hasPrefix("running:") ? "succeeded" : "partially-completed"
            operation.nextAction = "Installation and launch request are separate from first-screen and functional evidence. Check the app screen and any external server conditions. Runstir did not create a server connection."
            return finish(operation, code: operation.state == "succeeded" ? 0 : 1, events: events)
        } catch {
            let cancelled = error is CancellationError || Task.isCancelled
            let conflict = error as? ResourceConflict
            operation.conflict = conflict
            let domain = (error as? DomainError) ?? conflict?.domainError
            operation.error = domain?.message ?? String(describing: error)
            operation.nextAction = domain?.remediation.summary
                ?? "Inspect the current file and selected device before retrying. Completed installation and existing data remain."
            if installationRequested {
                if operation.installation != "installed" { operation.installation = "unconfirmed" }
                if let provider, let selected, let artifact = operation.artifact {
                    do { operation.installed = try await provider.installed(appID: artifact.metadata.appID, device: selected) }
                    catch { operation.installed = AppFileInstalledState(state: "unknown", detail: "Re-observation failed: \(error)") }
                }
            }
            operation.state = cancelled ? "cancelled" : "failed"
            return finish(operation, code: cancelled ? 130 : domain != nil ? 1 : 2, events: events)
        }
    }

    private static func inspect(file: URL, first: (identity: AppFileIdentity, digest: String),
                                provider: AppFileProvider) async throws -> AppFileArtifact {
        let metadata = try await provider.metadata(file)
        let after = try AppFileSnapshot.read(file)
        guard first.identity == after.identity, first.digest == after.digest else {
            throw AppFileSnapshot.failure("The file changed while its metadata was inspected.")
        }
        return AppFileArtifact(file: first.identity, contentIdentity: first.digest, metadata: metadata)
    }

    private static func compatible(_ metadata: AppFileMetadata, device: AppFileDevice) throws {
        guard device.ready else {
            throw AppFileSnapshot.failure("The selected virtual device is not ready. Boot and prepare that device manually, then inspect again. No environment preparation was started.")
        }
        guard metadata.architectures.contains("any") || !Set(metadata.architectures).isDisjoint(with: device.architectures),
              let minimum = SemanticVersion(metadata.minimumOS), let os = SemanticVersion(device.os), minimum <= os else {
            throw AppFileSnapshot.failure("The app architecture or minimum OS is incompatible with the selected device.")
        }
    }

    private static func makePlan(artifact: AppFileArtifact, device: AppFileDevice,
                                 installed: AppFileInstalledState) throws -> AppFilePlan {
        guard ["installed", "absent"].contains(installed.state), installed.state != "installed" || installed.build != nil else {
            throw AppFileSnapshot.failure("The current installed app or its build is unknown. Confirm the device state before approval.")
        }
        let replacement = installed.state == "installed"
        let old = installed.build.flatMap(versionComponents)
        let new = versionComponents(artifact.metadata.build)
        let downgrade = old.flatMap { old in new.map { $0.lexicographicallyPrecedes(old) } } ?? false
        let buildOrderUnknown = replacement && (old == nil || new == nil)
        var warnings = ["File identity does not prove the producer is trusted or the app is safe.",
            "Installation, launch request, running state and first-screen evidence are separate observations."]
        if replacement { warnings.append("Replace the same app ID using the platform's data-preserving install. No uninstall, reset or delete-and-retry is allowed.") }
        if downgrade { warnings.append("OLDER BUILD: the new build is older than the installed build. The platform may refuse it. Data preservation and automatic rollback are not guaranteed.") }
        else if buildOrderUnknown { warnings.append("UNKNOWN BUILD ORDER: the build labels cannot be ordered. The new build may be older. Separate DOWNGRADE risk acknowledgement is required; installation and data preservation are not guaranteed.") }
        struct Identity: Encodable {
            let artifact: AppFileArtifact
            let device: AppFileDevice
            let installed: AppFileInstalledState
            let downgrade: Bool
            let buildOrderUnknown: Bool
            let warnings: [String]
        }
        let id = try AppFileSnapshot.digest(Identity(artifact: artifact, device: device, installed: installed,
            downgrade: downgrade, buildOrderUnknown: buildOrderUnknown, warnings: warnings))
        return AppFilePlan(id: id, artifact: artifact, device: device, installed: installed,
            replacement: replacement, downgrade: downgrade, buildOrderUnknown: buildOrderUnknown, warnings: warnings)
    }

    private static func versionComponents(_ value: String) -> [UInt64]? {
        // Same grammar as accepted CFBundleVersion metadata. A release follows
        // its development, alpha, beta and final-candidate builds in that order.
        let suffixStart = value.firstIndex { $0.isLetter }
        let numeric = suffixStart.map { String(value[..<$0]) } ?? value
        let suffix = suffixStart.map { String(value[$0...]) } ?? ""
        let fields = numeric.split(separator: ".", omittingEmptySubsequences: false)
        guard !fields.isEmpty, fields.count <= 4,
              fields.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }) else { return nil }
        let numbers = fields.compactMap { UInt64($0) }
        guard numbers.count == fields.count else { return nil }
        var stage: UInt64 = 4
        var sequence: UInt64 = 0
        if !suffix.isEmpty {
            guard let pair = [("d", UInt64(0)), ("a", 1), ("b", 2), ("fc", 3)].first(where: { suffix.hasPrefix($0.0) }) else { return nil }
            let serial = suffix.dropFirst(pair.0.count)
            guard !serial.isEmpty, serial.utf8.allSatisfy({ (48...57).contains($0) }), let number = UInt64(serial) else { return nil }
            stage = pair.1
            sequence = number
        }
        return numbers + Array(repeating: 0, count: 4 - numbers.count) + [stage, sequence]
    }

    private static func finish(_ operation: AppFileOperation, code: Int32, events: WorkflowEvents) -> AppFileResult {
        events.send(code == 130 ? "cancelled" : "finished", state: operation.state, detail: operation.nextAction)
        return AppFileResult(operation: operation, exitCode: code)
    }
}

private enum AppFileProvider: Sendable {
    case ios(SimulatorAppFile)
    case android(AndroidAppFile)

    init(file: URL, runner: any ProcessRunner, environment: [String: String]) throws {
        if file.pathExtension == "app" { self = .ios(SimulatorAppFile(runner: runner, environment: environment)) }
        else { self = .android(try AndroidAppFile(runner: runner, environment: environment)) }
    }

    func metadata(_ file: URL) async throws -> AppFileMetadata {
        switch self {
        case .ios(let tools): try await tools.metadata(file)
        case .android(let tools): try await tools.metadata(file)
        }
    }

    func devices() async throws -> [AppFileDevice] {
        switch self {
        case .ios(let tools): try await tools.devices()
        case .android(let tools): try await tools.devices()
        }
    }

    func installed(appID: String, device: AppFileDevice) async throws -> AppFileInstalledState {
        switch self {
        case .ios(let tools): try await tools.installed(appID: appID, device: device)
        case .android(let tools): try await tools.installed(appID: appID, device: device)
        }
    }

    func install(file: URL, device: AppFileDevice) async throws {
        switch self {
        case .ios(let tools): try await tools.install(file: file, device: device)
        case .android(let tools): try await tools.install(file: file, device: device)
        }
    }

    func launch(metadata: AppFileMetadata, device: AppFileDevice) async throws {
        switch self {
        case .ios(let tools): try await tools.launch(appID: metadata.appID, device: device)
        case .android(let tools): try await tools.launch(metadata: metadata, device: device)
        }
    }

    func observe(_ claim: ResourceClaim) async throws -> ClaimObservation {
        switch self {
        case .ios(let tools): try await tools.observe(claim)
        case .android(let tools): try await tools.observe(claim)
        }
    }
}

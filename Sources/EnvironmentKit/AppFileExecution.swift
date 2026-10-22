import AndroidKit
import Core
import Foundation
import Logging
import SimulatorKit

public struct AppFileInput: Sendable {
    public let file: URL
    public let environment: [String: String]
    public let device: String?
    public let platform: ProjectPlatform?

    public init(file: URL, environment: [String: String], device: String? = nil, platform: ProjectPlatform? = nil) {
        self.file = file
        self.environment = environment
        self.device = device
        self.platform = platform
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
            if let profile = artifact.metadata.provisioning {
                output.append("profile: \(profile.kind) \(profile.profileUUID), team \(profile.teamID), app ID \(profile.applicationIdentifier), expires \(profile.expiration), \(profile.provisionedDeviceCount) devices")
            }
        }
        for device in operation.devices {
            let state = device.ready ? "ready" : device.boot == "required" ? "shut down; Runstir boots it after approval" : "manual preparation required"
            output.append("device: \(device.id) — \(device.name), OS \(device.os), \(device.architectures.joined(separator: ", ")), \(state)")
            if let pairing = device.pairing {
                output.append("device state: pairing \(pairing), Developer Mode \(device.developerMode ?? "unknown"), connection \(device.connection ?? "unknown")")
            }
            if let source = device.architectureSource {
                output.append("architecture evidence: \(source); runtime: \(device.runtimeIdentifier ?? "unknown"), build \(device.runtimeBuild ?? "unknown"), available \(device.runtimeAvailable.map(String.init) ?? "unknown")")
            }
        }
        for check in operation.prerequisites ?? [] {
            output.append("condition \(check.id): \(check.state) — \(check.observed)")
            if let action = check.action { output.append("  manual step: \(action)") }
        }
        if let boot = operation.deviceBoot {
            output.append("device boot: \(boot.state) \(boot.device)\(boot.handle.map { " on \($0)" } ?? "")\(boot.launcherPID.map { ", launcher pid \($0)" } ?? "") — \(boot.detail)")
            if let log = boot.log { output.append("emulator log: \(log)") }
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

    fileprivate static func escape(_ value: String) -> String {
        value.unicodeScalars.map { scalar in
            (CharacterSet.controlCharacters.contains(scalar) || scalar.value == 0x2028 || scalar.value == 0x2029)
                ? String(format: "\\u{%04X}", scalar.value) : String(scalar)
        }.joined()
    }
}

/// Last text boundary for AppFile's human tool logs; never transforms actual argv.
public struct AppFileLogStream: TextOutputStream, Sendable {
    private let sink: @Sendable (String) -> Void

    public init(sink: @escaping @Sendable (String) -> Void = {
        FileHandle.standardError.write(Data($0.utf8))
    }) {
        self.sink = sink
    }

    public mutating func write(_ string: String) {
        // StreamLogHandler appends exactly one LF after the fully rendered entry.
        // Escape every input-controlled character before that delimiter.
        let terminated = string.utf8.last == 0x0a
        let body = terminated ? String(decoding: string.utf8.dropLast(), as: UTF8.self) : string
        sink(AppFileHumanOutput.escape(body) + (terminated ? "\n" : ""))
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
            let artifact = try await inspect(file: file, first: first, provider: tools, platform: input.platform)
            operation.artifact = artifact
            operation.completed.append("inspect")
            events.send("stage", stage: "inspect", state: "succeeded", detail: "\(artifact.metadata.appID), \(artifact.contentIdentityAlgorithm) \(artifact.contentIdentity)")
            operation.devices = try await tools.devices(selected: input.device)
            guard let deviceID = input.device else {
                operation.state = inspectOnly ? "succeeded" : "needs-selection"
                if !inspectOnly { operation.requiredInput = ["--device"] }
                operation.nextAction = "Select a listed device: a booted virtual device, a shut-down Simulator or installed AVD that Runstir boots after approval, or a connected, trusted iOS device with Developer Mode. No device was booted and no installation was requested."
                return finish(operation, code: inspectOnly ? 0 : 1, events: events)
            }
            guard let device = operation.devices.first(where: { $0.id == deviceID }) else {
                throw AppFileSnapshot.failure("The selected device is absent or disconnected. Select a current candidate; Runstir will not switch targets.")
            }
            selected = device
            operation.prerequisites = prerequisites(artifact.metadata, device: device)
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
            let digestMatches = stagedSnapshot.digest == artifact.contentIdentity
            // An approved IPA is extracted only from the private copy whose bytes were just verified.
            let installInput = digestMatches && staged.pathExtension == "ipa"
                ? try IPAArchive.extract(staged, into: directory.appendingPathComponent("extracted", isDirectory: true)) : staged
            let stagedMetadata: AppFileMetadata? = digestMatches ? try await tools.metadata(installInput) : nil
            guard digestMatches, stagedMetadata == artifact.metadata else {
                Logger(label: "mobile.app-file.snapshot").debug("App file snapshot mismatch", metadata: [
                    "expectedDigest": .string(artifact.contentIdentity), "stagedDigest": .string(stagedSnapshot.digest),
                    "metadataEqual": .string(stagedMetadata.map { "\($0 == artifact.metadata)" } ?? "not-compared")])
                throw AppFileSnapshot.failure("The copied app bytes or metadata differ from the approved file.")
            }
            let current = try await inspect(file: file, first: AppFileSnapshot.read(file), provider: tools, platform: input.platform)
            let currentDevices = try await tools.devices(selected: deviceID)
            guard var currentDevice = currentDevices.first(where: { $0.id == deviceID }) else {
                throw AppFileSnapshot.failure("The approved device disconnected before installation.")
            }
            operation.prerequisites = prerequisites(current.metadata, device: currentDevice)
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
            if currentDevice.boot == "required" {
                // The approved plan named this shut-down device. It is booted under the device lease,
                // like `up`, and left running; no other device is booted, switched or stopped.
                operation.deviceBoot = AppFileDeviceBoot(state: "requested", device: currentDevice.id,
                    detail: "Runstir is booting the approved shut-down device and will leave it running.")
                events.send("stage", stage: "boot", state: "running", detail: "Booting \(currentDevice.name) headlessly. Other devices are not booted or stopped.")
                operation.deviceBoot = try await tools.startBoot(currentDevice, operation: operation.id)
                let live = try await tools.awaitBooted(currentDevice)
                guard live.name == currentDevice.name, live.os == currentDevice.os,
                      live.runtimeIdentifier == currentDevice.runtimeIdentifier, live.runtimeBuild == currentDevice.runtimeBuild else {
                    throw AppFileSnapshot.failure("The booted device's identity differs from the approved plan. Inspect and approve again.")
                }
                try compatible(current.metadata, device: live)
                operation.deviceBoot?.state = "started"
                operation.deviceBoot?.handle = live.handle
                operation.devices = operation.devices.map { $0.id == live.id ? live : $0 }
                operation.completed.append("boot")
                events.send("stage", stage: "boot", state: "succeeded", detail: "\(live.name) is ready on \(live.handle). Runstir started it and leaves it running.")
                currentDevice = live
                selected = live
                let observed = try await tools.installed(appID: current.metadata.appID, device: live)
                operation.installed = observed
                // The approval covered a fresh install. Anything already there needs its own replacement approval.
                guard observed.state == "absent" else {
                    operation.plan = try makePlan(artifact: current, device: live, installed: observed)
                    operation.state = "needs-approval"
                    operation.requiredInput = ["--approve"]
                    operation.nextAction = "Runstir booted \(live.name) and left it running. The app is already installed there; review the replacement plan and approve it."
                    return finish(operation, code: 1, events: events)
                }
            }
            try leases.reserve(device: deviceKey, owner: owner)
            installationRequested = true
            operation.installation = "requested"
            events.send("stage", stage: "install", state: "running")
            try await tools.install(file: installInput, device: currentDevice)
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
            if var boot = operation.deviceBoot, boot.state == "requested" {
                boot.state = "unconfirmed"
                if let provider {
                    events.send("stage", stage: "reobserve", state: "running",
                        detail: "Checking the device Runstir started booting. It is not stopped.")
                    let id = boot.device
                    let observation = Task { try await provider.devices(selected: id) }
                    let live = try? await observation.value.first { $0.id == id }
                    if let live, live.ready { boot.handle = live.handle }
                    boot.detail += " Re-observed: " + (live.map { $0.ready ? "ready on \($0.handle)" : $0.boot == "required" ? "not running" : "running, not ready" }
                        ?? "the device state could not be confirmed") + ". Runstir does not stop it; stop it yourself if it is not needed."
                }
                operation.deviceBoot = boot
            }
            if installationRequested {
                if operation.installation != "installed" { operation.installation = "unconfirmed" }
                if let provider, let selected, let artifact = operation.artifact {
                    // Cancellation stops new steps, not the look at what the interrupted step left.
                    // An unstructured task does not inherit this task's cancellation.
                    events.send("stage", stage: "reobserve", state: "running",
                        detail: "Checking the installed state after the interruption. Nothing is deleted or launched.")
                    let observation = Task { try await provider.installed(appID: artifact.metadata.appID, device: selected) }
                    do { operation.installed = try await observation.value }
                    catch { operation.installed = AppFileInstalledState(state: "unknown", detail: "Re-observation failed: \(error)") }
                }
            }
            operation.state = cancelled ? "cancelled" : "failed"
            return finish(operation, code: cancelled ? 130 : domain != nil ? 1 : 2, events: events)
        }
    }

    private static func inspect(file: URL, first: (identity: AppFileIdentity, digest: String),
                                provider: AppFileProvider, platform: ProjectPlatform?) async throws -> AppFileArtifact {
        let metadata = try await provider.metadata(file)
        let after = try AppFileSnapshot.read(file)
        guard first.identity == after.identity, first.digest == after.digest else {
            throw AppFileSnapshot.failure("The file changed while its metadata was inspected.")
        }
        if let platform, metadata.platform != platform {
            throw AppFileSnapshot.failure("The selected platform \(platform.rawValue) does not match the inspected file's platform \(metadata.platform.rawValue). Select a matching file or platform, then inspect again.")
        }
        return AppFileArtifact(file: first.identity, contentIdentity: first.digest, metadata: metadata)
    }

    static func compatible(_ metadata: AppFileMetadata, device: AppFileDevice,
                           host: ToolPreparationHost = .current, now: Date = Date()) throws {
        if let checks = prerequisites(metadata, device: device, now: now) {
            let open = checks.filter { $0.state != "satisfied" }
            guard open.isEmpty else {
                throw DomainError(summary: "Physical iOS installation conditions are not met: "
                    + open.map { "\($0.id) \($0.state) (\($0.observed))" }.joined(separator: "; "),
                    remediation: Remediation(summary: open.compactMap(\.action).joined(separator: " ")
                        + " Then inspect again with the same file and device. Runstir did not register a device, re-sign the app or collect an account."))
            }
            return
        }
        guard device.ready || device.boot == "required" else {
            throw AppFileSnapshot.failure("The selected virtual device is not ready and Runstir cannot boot it. Runstir boots only a shut-down Simulator on an installed runtime or an installed AVD with its system image that no Emulator runs. Prepare it manually, then inspect again. No runtime, image or device was created or downloaded.")
        }
        if metadata.platform == .ios {
            guard host.architecture == "arm64", device.runtimeAvailable == true,
                  let identifier = device.runtimeIdentifier, !identifier.isEmpty,
                  let build = device.runtimeBuild, !build.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let source = device.architectureSource, !source.isEmpty, !device.architectures.isEmpty else {
                throw AppFileSnapshot.failure("Native arm64 Simulator compatibility is unknown. Confirm the selected runtime's identity, build and architecture capabilities on native macOS arm64, then inspect again.")
            }
            guard metadata.architectures.contains("arm64"), device.architectures.contains("arm64") else {
                throw AppFileSnapshot.failure("Native arm64 Simulator compatibility is unknown for this app and runtime. x86-only or Rosetta-dependent execution is not confirmed.")
            }
        }
        guard metadata.architectures.contains("any") || !Set(metadata.architectures).isDisjoint(with: device.architectures),
              let minimum = SemanticVersion(metadata.minimumOS), let os = SemanticVersion(device.os), minimum <= os else {
            throw AppFileSnapshot.failure("The app architecture or minimum OS is incompatible with the selected device.")
        }
    }

    /// Physical iOS conditions Runstir can observe; nil for virtual devices and Android.
    /// The install itself stays the platform's final acceptance.
    static func prerequisites(_ metadata: AppFileMetadata, device: AppFileDevice,
                              now: Date = Date()) -> [AppFilePrerequisite]? {
        guard let profile = metadata.provisioning else { return nil }
        let reexport = "Sign and export the app again yourself in Xcode or your build system. Runstir does not re-sign."
        let prefix = profile.applicationIdentifier.prefix { $0 != "." }
        let pattern = profile.applicationIdentifier.drop { $0 != "." }.dropFirst()
        let appIDMatches = profile.applicationIdentifierPrefixes.contains(String(prefix)) && (pattern == "*" || pattern == metadata.appID
            || pattern.hasSuffix(".*") && metadata.appID.hasPrefix(pattern.dropLast()))
        let expiration = ISO8601DateFormatter().date(from: profile.expiration)
        let listed = profile.provisionedDevices.contains { $0.caseInsensitiveCompare(device.id) == .orderedSame }
        let minimum = SemanticVersion(metadata.minimumOS)
        let os = SemanticVersion(device.os)
        return [
            AppFilePrerequisite(id: "signature",
                satisfied: profile.signatureVerified && profile.signingTeamID == profile.teamID && profile.signingCertificateInProfile,
                observed: "codesign strict verification \(profile.signatureVerified ? "passed" : "failed"); signing team \(profile.signingTeamID ?? "unknown"), profile team \(profile.teamID); signing certificate \(profile.signingCertificateInProfile ? "is" : "is not") in the profile",
                action: "Sign with a certificate that this \(profile.kind) profile lists, from the same team. " + reexport),
            AppFilePrerequisite(id: "profile-app-id", satisfied: appIDMatches,
                observed: "profile application identifier \(profile.applicationIdentifier); app ID \(metadata.appID)",
                action: "Use a profile whose App ID matches \(metadata.appID). " + reexport),
            AppFilePrerequisite(id: "profile-expiration", satisfied: expiration.map { $0 > now },
                observed: "\(profile.kind) profile \(profile.profileUUID) expires \(profile.expiration)",
                action: "Use a current, unexpired profile. " + reexport),
            AppFilePrerequisite(id: "profile-device", satisfied: listed,
                observed: "UDID \(device.id) is \(listed ? "" : "not ")among the profile's \(profile.provisionedDeviceCount) devices",
                action: "Register this UDID in your Apple Developer account yourself and regenerate the profile. Registering the device does not change an existing app file. " + reexport),
            AppFilePrerequisite(id: "os", satisfied: minimum.flatMap { minimum in os.map { minimum <= $0 } },
                observed: "app minimum iOS \(metadata.minimumOS); device iOS \(device.os)",
                action: "Update the device's iOS, or use a build whose minimum iOS this device meets."),
            AppFilePrerequisite(id: "architecture",
                satisfied: device.architectures.isEmpty ? nil : !Set(metadata.architectures).isDisjoint(with: device.architectures),
                observed: "app \(metadata.architectures.joined(separator: ", ")); device \(device.architectures.isEmpty ? "unknown" : device.architectures.joined(separator: ", "))",
                action: "Use a build with an architecture this device supports."),
            AppFilePrerequisite(id: "trust", satisfied: device.pairing.map { $0 == "paired" },
                observed: "pairing \(device.pairing ?? "unknown")",
                action: "Connect and unlock the device, then tap Trust This Computer, or pair it in Xcode's Devices and Simulators window."),
            AppFilePrerequisite(id: "developer-mode", satisfied: device.developerMode.map { $0 == "enabled" },
                observed: "Developer Mode \(device.developerMode ?? "unknown")",
                action: "On the device, turn on Settings > Privacy & Security > Developer Mode and restart when asked. A device whose iOS has no Developer Mode setting is not supported by this devicectl path."),
            AppFilePrerequisite(id: "connection", satisfied: device.connection.map { $0 == "connected" },
                observed: "connection \(device.connection ?? "unknown")",
                action: "Connect the device by USB or the same network and unlock it."),
        ]
    }

    private static func makePlan(artifact: AppFileArtifact, device: AppFileDevice,
                                 installed: AppFileInstalledState) throws -> AppFilePlan {
        let unobserved = device.boot == "required" && installed.state == "unobserved"
        guard unobserved || ["installed", "absent"].contains(installed.state), installed.state != "installed" || installed.build != nil else {
            throw AppFileSnapshot.failure("The current installed app or its build is unknown. Confirm the device state before approval.")
        }
        let replacement = installed.state == "installed"
        let old = installed.build.flatMap(versionComponents)
        let new = versionComponents(artifact.metadata.build)
        let downgrade = old.flatMap { old in new.map { $0.lexicographicallyPrecedes(old) } } ?? false
        let buildOrderUnknown = replacement && (old == nil || new == nil)
        var warnings = ["File identity does not prove the producer is trusted or the app is safe.",
            "Installation, launch request, running state and first-screen evidence are separate observations."]
        if unobserved { warnings.append("BOOT: Runstir boots \(device.name) (\(device.id)) after approval and leaves it running. The installed app is observed after boot; an existing or unknown installation requires a new approval.") }
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
    case iosDevice(IOSDeviceAppFile)
    case android(AndroidAppFile)

    init(file: URL, runner: any ProcessRunner, environment: [String: String]) throws {
        if file.pathExtension == "ipa" {
            self = .iosDevice(IOSDeviceAppFile(runner: runner, environment: environment))
        } else if file.pathExtension == "app" {
            self = IOSDeviceAppFile.declaresDevice(file)
                ? .iosDevice(IOSDeviceAppFile(runner: runner, environment: environment))
                : .ios(SimulatorAppFile(runner: runner, environment: environment))
        } else { self = .android(try AndroidAppFile(runner: runner, environment: environment)) }
    }

    func metadata(_ file: URL) async throws -> AppFileMetadata {
        if file.pathExtension == "ipa" {
            // Inspection reads the app from a private extraction it removes; installation re-extracts its verified copy.
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("dev.runstir-ipa-inspect-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            return try await metadata(IPAArchive.extract(file, into: directory))
        }
        return switch self {
        case .ios(let tools): try await tools.metadata(file)
        case .iosDevice(let tools): try await tools.metadata(file)
        case .android(let tools): try await tools.metadata(file)
        }
    }

    func devices(selected: String?) async throws -> [AppFileDevice] {
        switch self {
        case .ios(let tools): try await tools.devices()
        case .iosDevice(let tools): try await tools.devices(selected: selected)
        case .android(let tools): try await tools.devices()
        }
    }

    func installed(appID: String, device: AppFileDevice) async throws -> AppFileInstalledState {
        // A shut-down device cannot answer until Runstir boots it after approval.
        if device.boot == "required" {
            return AppFileInstalledState(state: "unobserved", detail: "The device is shut down. Runstir observes the installed app after booting it.")
        }
        return switch self {
        case .ios(let tools): try await tools.installed(appID: appID, device: device)
        case .iosDevice(let tools): try await tools.installed(appID: appID, device: device)
        case .android(let tools): try await tools.installed(appID: appID, device: device)
        }
    }

    func startBoot(_ device: AppFileDevice, operation: String) async throws -> AppFileDeviceBoot {
        switch self {
        case .ios(let tools): try await tools.startBoot(device)
        case .iosDevice: throw AppFileSnapshot.failure("Runstir does not boot physical devices.")
        case .android(let tools): try await tools.startBoot(device, operation: operation)
        }
    }

    func awaitBooted(_ device: AppFileDevice) async throws -> AppFileDevice {
        switch self {
        case .ios(let tools): try await tools.awaitBooted(device)
        case .iosDevice: throw AppFileSnapshot.failure("Runstir does not boot physical devices.")
        case .android(let tools): try await tools.awaitBooted(device)
        }
    }

    func install(file: URL, device: AppFileDevice) async throws {
        switch self {
        case .ios(let tools): try await tools.install(file: file, device: device)
        case .iosDevice(let tools): try await tools.install(file: file, device: device)
        case .android(let tools): try await tools.install(file: file, device: device)
        }
    }

    func launch(metadata: AppFileMetadata, device: AppFileDevice) async throws {
        switch self {
        case .ios(let tools): try await tools.launch(appID: metadata.appID, device: device)
        case .iosDevice(let tools): try await tools.launch(appID: metadata.appID, device: device)
        case .android(let tools): try await tools.launch(metadata: metadata, device: device)
        }
    }

    func observe(_ claim: ResourceClaim) async throws -> ClaimObservation {
        switch self {
        case .ios(let tools): try await tools.observe(claim)
        case .iosDevice(let tools): try await tools.observe(claim)
        case .android(let tools): try await tools.observe(claim)
        }
    }
}

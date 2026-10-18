import AndroidKit
import Core
import Darwin
import Foundation

/// Android resource behavior; approval, leases and completion remain in PreparationExecution.
struct AndroidEmulatorPreparation {
    var checks: [PreparationStep] = []
    var installed: [String: Bool] = [:]
    var actions: [String: InstallationAction] = [:]
    var resources: [AndroidPreparationResource] = []

    static func inspect(context: AndroidDoctorContext, runner: any ProcessRunner) async throws -> Self {
        var plan = Self()
        do {
            let state = try await AndroidEmulatorEnvironment.inspect(context: context)
            let selected: AndroidPreparationResource?
            if let declared = state.declaredAVD {
                selected = state.compatible.first { $0.name == declared }
                if selected == nil, state.names.contains(declared) {
                    throw failure("The declared existing AVD is incompatible or unreadable. Preserve it; setup will not replace it.")
                }
            } else {
                let running = state.compatible.filter { state.running.contains($0.name) }
                let candidates = running.isEmpty ? state.compatible : running
                guard candidates.count <= 1 else { throw failure("Multiple compatible AVDs exist. Select android.avd in mobile.yml; no device was created.") }
                selected = candidates.first
            }
            if selected == nil {
                guard state.minSDK <= 35, state.abis.isEmpty || state.abis.contains("arm64-v8a") else {
                    throw failure("The fixed API 35 arm64 image candidate does not satisfy this project's minSdk/ABI. Prepare a compatible exact image explicitly; setup will not force API 35.")
                }
            }
            let requirements = state.sdkRequirements(includeImage: selected == nil, includeManager: selected == nil)
            let sdk = try await AndroidSDKPreparation.inspect(requirements, runner: runner)
            plan.checks += sdk.checks; plan.installed = sdk.installed; plan.actions = sdk.actions
            if let selected {
                plan.resources = [selected]
                plan.checks.append(PreparationStep(id: "android.emulator.ready", platform: .android, kind: "reuse", target: selected.directory.path,
                    observed: "\(selected.name); image revision \(selected.imageRevision ?? "unknown"); metadata SHA-256 \(selected.metadataSHA256 ?? "unknown")",
                    required: "existing compatible AVD; minSdk \(state.minSDK); ABI \(state.abis.joined(separator: ","))",
                    source: state.source, command: nil, remediation: nil))
                return plan
            }
            guard sdk.checks.allSatisfy({ $0.kind == "reuse" }),
                  let manager = state.avdManager, let managerRevision = state.avdManagerRevision else {
                plan.checks.append(blocker("Inspect the completed tools and image again. A new plan will pin the observed device profile and AVD creation identity."))
                return plan
            }
            let imagePackage = "system-images;android-35;google_apis;arm64-v8a"
            let image = state.sdkRoot.appendingPathComponent(imagePackage.replacingOccurrences(of: ";", with: "/"))
            let metadata = try await runner.run(AndroidSDKRepositorySource.googleAPIs.command)
            guard metadata.terminationStatus.isSuccess else { throw failure("Official system-image dependency metadata is unavailable.") }
            let repository = try AndroidSDKRepository(data: Data(metadata.standardOutput.utf8), source: .googleAPIs)
            let package = try repository.package(imagePackage)
            guard let required = package.minimumEmulatorRevision.flatMap({ SemanticVersion($0) }),
                  let observed = AndroidEmulatorEnvironment.revision(in: state.sdkRoot.appendingPathComponent("emulator")).flatMap({ SemanticVersion($0) }),
                  observed >= required else {
                throw failure("The existing Emulator does not satisfy image dependency \(package.minimumEmulatorRevision ?? "unknown"). Preserve its installation and prepare a compatible Emulator manually.")
            }
            guard let revision = AndroidEmulatorEnvironment.revision(in: image),
                  let digest = AndroidEmulatorEnvironment.imageDigest(in: image) else { throw failure("The existing system image identity is unknown.") }
            let profile = try await AndroidEmulatorEnvironment.profile("pixel_7", runner: runner, manager: manager,
                environment: ["ANDROID_HOME": state.sdkRoot.path, "ANDROID_SDK_ROOT": state.sdkRoot.path])
            let request = AndroidAVDRequest(name: state.declaredAVD ?? "Runstir_API_35_google_apis_arm64", sdkRoot: state.sdkRoot,
                avdHome: state.avdHome, imagePackage: imagePackage, imageRevision: revision, imageMetadataSHA256: digest,
                deviceProfile: "pixel_7", profileSHA256: AndroidEmulatorEnvironment.digest(Data(profile.utf8)),
                avdManager: manager, avdManagerRevision: managerRevision,
                emulatorRevision: AndroidEmulatorEnvironment.revision(in: state.sdkRoot.appendingPathComponent("emulator")) ?? "unknown",
                repositorySHA256: repository.sha256)
            let installation = installation(request)
            try installation.validate()
            try AndroidEmulatorEnvironment.validateImage(request)
            plan.installed[request.directory.path] = AndroidEmulatorEnvironment.exists(request.directory)
            plan.installed[request.pointer.path] = AndroidEmulatorEnvironment.exists(request.pointer)
            plan.resources = AndroidEmulatorEnvironment.observe(request, origin: .unknown).map { [$0] } ?? []
            try absent(request)
            var step = PreparationStep(id: "android.virtual-device.create", platform: .android, kind: "install", target: request.directory.path,
                observed: "absent", required: installation.inspectionLine,
                source: CheckSource(tier: 1, origin: "\(state.source.origin); \(repository.source.url); dependency metadata SHA-256 \(repository.sha256); Emulator >= \(package.minimumEmulatorRevision ?? "unknown")"),
                command: nil, remediation: Remediation(summary: "Create only this exact AVD. Existing AVDs, images and caches are preserved. Creation does not boot an Emulator or run an app."))
            step.installation = installation
            plan.checks.append(step)
            plan.actions[step.id] = InstallationAction(metadata: installation, returning: { runner, beforeCommit in
                try await create(request, runner: runner, beforeCommit: beforeCommit)
            })
        } catch is CancellationError { throw CancellationError() }
        catch let error as DomainError { plan.checks.append(blocker(error.message)) }
        return plan
    }

    static func create(_ request: AndroidAVDRequest, runner: any ProcessRunner,
                       beforeCommit: @Sendable ([URL]) async throws -> Void) async throws -> InstallationActionResult {
        do {
            try installation(request).validate()
            try absent(request)
            try AndroidEmulatorEnvironment.validateImage(request)
            let profile = try await AndroidEmulatorEnvironment.profile(request.deviceProfile, runner: runner,
                manager: request.avdManager, environment: ["ANDROID_HOME": request.sdkRoot.path, "ANDROID_SDK_ROOT": request.sdkRoot.path])
            guard AndroidEmulatorEnvironment.digest(Data(profile.utf8)) == request.profileSHA256 else { throw failure("The approved device profile changed.") }
            try Task.checkCancellation()
            try await beforeCommit([])
            try absent(request)
            let manager = FileManager.default
            try manager.createDirectory(at: request.avdHome, withIntermediateDirectories: true)
            let scratch = request.avdHome.appendingPathComponent(".runstir-avd-\(UUID().uuidString)")
            try manager.createDirectory(at: scratch, withIntermediateDirectories: false)
            defer { try? manager.removeItem(at: scratch) }
            let home = scratch.appendingPathComponent("avds")
            let user = scratch.appendingPathComponent("user")
            try manager.createDirectory(at: home, withIntermediateDirectories: false)
            try manager.createDirectory(at: user, withIntermediateDirectories: false)
            let staged = AndroidAVDRequest(name: request.name, sdkRoot: request.sdkRoot, avdHome: home,
                imagePackage: request.imagePackage, imageRevision: request.imageRevision, imageMetadataSHA256: request.imageMetadataSHA256,
                deviceProfile: request.deviceProfile, profileSHA256: request.profileSHA256,
                avdManager: request.avdManager, avdManagerRevision: request.avdManagerRevision,
                emulatorRevision: request.emulatorRevision, repositorySHA256: request.repositorySHA256)
            try await beforeCommit([scratch])
            let result = try await runner.run(ProcessCommand(request.avdManager.path,
                ["create", "avd", "--name", request.name, "--package", request.imagePackage, "--abi", "arm64-v8a",
                 "--device", request.deviceProfile, "--path", staged.directory.path],
                environment: ["ANDROID_HOME": request.sdkRoot.path, "ANDROID_SDK_ROOT": request.sdkRoot.path,
                    "ANDROID_AVD_HOME": home.path, "ANDROID_USER_HOME": user.path, "ANDROID_EMULATOR_HOME": user.path], timeout: .seconds(180)))
            guard result.terminationStatus.isSuccess,
                  AndroidEmulatorEnvironment.observe(staged, origin: .created)?.state == "available" else {
                throw failure("AVD creation failed or returned a different identity. Existing resources were preserved.")
            }
            try validateStaged(staged)
            try Data("avd.ini.encoding=UTF-8\npath=\(request.directory.path)\ntarget=android-35\n".utf8).write(to: staged.pointer)
            try Task.checkCancellation()
            try await beforeCommit([scratch])
            try AndroidEmulatorEnvironment.validateImage(request)
            try absent(request)
            // Finish both exclusive renames without an asynchronous cancellation point.
            guard renamex_np(staged.directory.path, request.directory.path, UInt32(RENAME_EXCL)) == 0 else {
                throw failure("The AVD directory appeared or could not be committed. Existing content was preserved.")
            }
            guard renamex_np(staged.pointer.path, request.pointer.path, UInt32(RENAME_EXCL)) == 0 else {
                throw failure("AVD data was created but registration could not be committed. Preserve it and inspect the remaining manual recovery.")
            }
            guard let resource = AndroidEmulatorEnvironment.observe(request, origin: .created), resource.state == "available" else {
                throw failure("Created AVD identity could not be verified. Preserve it and inspect manually.")
            }
            return InstallationActionResult(androidResources: [resource])
        } catch {
            let resources = AndroidEmulatorEnvironment.observe(request, origin: .unknown).map { [$0] } ?? []
            throw InstallationActionFailure(underlying: error, result: InstallationActionResult(androidResources: resources))
        }
    }

    private static func installation(_ request: AndroidAVDRequest) -> InstallationMetadata {
        InstallationMetadata(package: "android.avd", revision: request.imageRevision, destination: request.directory,
            resourceRoot: request.avdHome, managed: .androidAVD(request), requiredFile: "config.ini")
    }
    private static func validateStaged(_ request: AndroidAVDRequest) throws {
        let pointer = try request.pointer.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        let directory = try request.directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard pointer.isRegularFile == true, pointer.isSymbolicLink != true,
              directory.isDirectory == true, directory.isSymbolicLink != true,
              let files = FileManager.default.enumerator(at: request.directory,
                includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey]) else {
            throw failure("The staged AVD could not be inspected safely.")
        }
        for case let file as URL in files {
            let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey])
            guard values.isSymbolicLink != true, values.isRegularFile == true || values.isDirectory == true else {
                throw failure("The staged AVD contains an unsafe file type.")
            }
        }
    }
    private static func absent(_ request: AndroidAVDRequest) throws {
        guard request.avdHome.resolvingSymlinksInPath().standardizedFileURL.path == request.avdHome.path,
              request.sdkRoot.resolvingSymlinksInPath().standardizedFileURL.path == request.sdkRoot.path else {
            throw failure("An approved Android resource root now resolves to another path. Preserve it and re-plan.")
        }
        guard !AndroidEmulatorEnvironment.exists(request.directory), !AndroidEmulatorEnvironment.exists(request.pointer) else {
            throw failure("An AVD name or destination already exists, including incomplete content or links. Preserve it and inspect manually.")
        }
        var parent = request.avdHome
        while !AndroidEmulatorEnvironment.exists(parent), parent.path != "/" { parent.deleteLastPathComponent() }
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &directory), directory.boolValue,
              FileManager.default.isWritableFile(atPath: parent.path), FileManager.default.isExecutableFile(atPath: parent.path) else {
            throw failure("AVD creation needs separate manual destination permission.")
        }
    }
    private static func blocker(_ message: String) -> PreparationStep {
        PreparationStep(id: "android.emulator.preparation", platform: .android, kind: "provider", target: "Android Emulator",
            observed: message, required: "Exact compatible image and AVD identity", source: CheckSource(origin: "Android Emulator preparation"),
            command: nil, remediation: Remediation(summary: message))
    }
    private static func failure(_ message: String) -> DomainError { InstallationExecution.failure(message) }
}

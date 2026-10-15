import AndroidKit
import Core
import Foundation

struct AndroidSDKPreparation {
    var checks: [PreparationStep] = []
    var steps: [PreparationStep] { checks.filter { $0.kind != "reuse" } }
    var installed: [String: Bool] = [:]
    var actions: [String: InstallationAction] = [:]

    static func inspect(_ requirements: AndroidSDKRequirements, runner: any ProcessRunner) async throws -> Self {
        var plan = Self()
        guard let sdk = requirements.sdkRoot else {
            plan.checks = [blocker("root", requirements.blockers.joined(separator: "; "))]
            return plan
        }
        if !requirements.blockers.isEmpty {
            plan.checks.append(blocker("requirements", requirements.blockers.joined(separator: "; ")))
            return plan
        }
        var repository: AndroidSDKRepository?
        var repositoryFailure: String?
        let missing = requirements.packages.filter { !$0.observation(in: sdk).present }
        if !missing.isEmpty {
            do {
                let result = try await runner.run(AndroidSDKRepository.command)
                guard result.terminationStatus.isSuccess else { throw InstallationExecution.failure("Official Android SDK metadata download failed") }
                repository = try AndroidSDKRepository(data: Data(result.standardOutput.utf8))
            } catch is CancellationError { throw CancellationError() }
            catch { repositoryFailure = "Official archive identity is unavailable. Recheck the official metadata before approving installation." }
        }
        for requirement in requirements.packages {
            try Task.checkCancellation()
            let path = requirement.packagePath
            let destination = sdk.appendingPathComponent(path.replacingOccurrences(of: ";", with: "/"))
            let observed = requirement.observation(in: sdk)
            plan.installed[destination.path] = observed.present
            let id = "android.sdk.package.\(path)"
            if observed.present {
                let kind = observed.ready ? "reuse" : observed.licenseStatus == .error ? "license" : "provider"
                plan.checks.append(PreparationStep(id: id, platform: .android, kind: kind, target: destination.path,
                    observed: observed.revision.map { "installed revision \($0)" } ?? "existing destination, revision unknown",
                    required: "\(path); existing packages are never replaced", source: requirement.source, command: nil,
                    remediation: observed.ready ? nil : Remediation(summary: observed.reason ?? "Inspect the existing SDK package and license metadata, then re-plan.")))
                continue
            }
            guard let repository else {
                plan.checks.append(blocker(path, repositoryFailure ?? "Official repository metadata is unavailable", target: destination.path))
                continue
            }
            do {
                let package = try repository.package(path)
                let metadata = InstallationMetadata(package: path, revision: package.revision, destination: destination, resourceRoot: sdk,
                    artifact: InstallationArtifact(url: package.archiveURL, checksumAlgorithm: "sha1", checksum: package.sha1, size: package.size),
                    repositoryURL: AndroidSDKRepository.url, repositorySHA256: repository.sha256,
                    licenseID: package.licenseID, licenseSHA1: package.licenseSHA1,
                    requiredFile: requirement.requiredFile, executable: requirement.executable)
                let licensed = package.licenseAccepted(in: sdk)
                var kind = licensed ? "install" : "license"
                var summary = licensed ? "Install only this pinned archive into the absent destination. Existing packages and caches are preserved."
                    : "Review \(package.licenseID) (SHA-1 \(package.licenseSHA1)) in Android Studio or SDK Manager. Setup approval does not accept licenses. Accept manually and re-plan."
                if licensed {
                    do { try InstallationExecution.validateDestination(metadata) }
                    catch { kind = "permission"; summary = "Verify destination write access separately. Setup never requests administrator privileges. Inspect and re-plan." }
                }
                var step = PreparationStep(id: id, platform: .android, kind: kind, target: destination.path,
                    observed: "absent", required: "\(path), revision \(package.revision), \(package.size) bytes, SHA-1 \(package.sha1)",
                    source: CheckSource(tier: 1, origin: "\(AndroidSDKRepository.url.absoluteString); metadata SHA-256 \(repository.sha256); \(requirement.source.origin)"),
                    command: nil, remediation: Remediation(summary: summary, url: "https://developer.android.com/tools/sdkmanager#accept-licenses"))
                step.installation = metadata
                plan.checks.append(step)
                plan.actions[id] = InstallationAction(metadata: metadata) { runner, beforeCommit in
                    try await InstallationExecution.installSDKZip(metadata, localMetadata: package.localMetadata,
                                                                 runner: runner, beforeCommit: beforeCommit)
                }
            } catch {
                plan.checks.append(blocker(path, "No unambiguous official revision/archive identifies \(path). Nothing will use latest or an older metadata schema.", target: destination.path))
            }
        }
        return plan
    }

    private static func blocker(_ id: String, _ reason: String, target: String = "Android SDK") -> PreparationStep {
        PreparationStep(id: "android.sdk.\(id)", platform: .android, kind: "provider", target: target,
            observed: reason, required: "exact evaluated requirements and official compatible archive metadata",
            source: CheckSource(origin: "Android SDK preparation"), command: nil,
            remediation: Remediation(summary: reason))
    }
}

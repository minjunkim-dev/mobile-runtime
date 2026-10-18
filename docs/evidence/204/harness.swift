import Foundation
import Core
import CryptoKit
import AndroidKit
import EnvironmentKit
enum ValidationFailure: Error { case message(String) }

struct BoundedRunner: ProcessRunner {
    let base: SystemProcessRunner
    let runtime: Bool
    let cancelDownload: Bool
    let failPlatform: Bool
    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        let name = URL(fileURLWithPath: command.executable).lastPathComponent
        guard name != "adb", name != "sdkmanager", name != "avdmanager",
              name != "emulator" || (runtime && (command.arguments == ["-list-avds"] || command.arguments == ["-accel-check"])) else {
            throw ValidationFailure.message( "Validation boundary refuses runtime/provisioning command: " + name)
        }
        if failPlatform && name == "curl" && command.arguments.contains(where: { $0.hasSuffix("platform-35_r02.zip") }) {
            throw ValidationFailure.message("Deliberate owned-harness failure before the second package download")
        }
        var selected = command
        if name == "gradlew" { selected.arguments.insert("--offline", at: 0) }
        let result = try await base.run(selected, onLine: onLine)
        if name == "curl", let index = command.arguments.firstIndex(of: "--output"), result.terminationStatus.isSuccess {
            let destination = URL(fileURLWithPath: command.arguments[index + 1])
            let data = try Data(contentsOf: destination, options: .mappedIfSafe)
            let receipt = ["kind": "actual-curl-payload", "size": String(data.count),
                "sha1": Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                "url": command.arguments.last ?? "unknown"]
            FileHandle.standardError.write(try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys]) + Data([10]))
        }
        if cancelDownload && name == "curl" && command.arguments.contains("--output") {
            withUnsafeCurrentTask { $0?.cancel() }
            throw CancellationError()
        }
        return result
    }
    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
        throw ValidationFailure.message( "Validation boundary refuses detached process")
    }
}

@main struct OwnedSDKValidation {
    static func main() async throws {
        // Public, de-identified copy. The executed private source has its own receipt hash.
        guard let prefixPath = ProcessInfo.processInfo.environment["RUNSTIR_VALIDATION_ROOT"],
              let java = ProcessInfo.processInfo.environment["RUNSTIR_VALIDATION_JAVA_HOME"],
              let user = ProcessInfo.processInfo.environment["RUNSTIR_VALIDATION_USER"] else {
            throw ValidationFailure.message("Set the owned validation root, JDK home and validation user inputs")
        }
        let prefix = URL(fileURLWithPath: prefixPath)
        if CommandLine.arguments.contains("--atomic-probe") {
            try Data("owned atomic probe".utf8).write(to: prefix.appendingPathComponent("evidence/atomic-probe.txt"), options: CommandLine.arguments.contains("--regular-probe") ? [] : .atomic)
            return
        }
        let env = ["HOME": prefix.appendingPathComponent("home").path, "USER": user, "LOGNAME": user, "LANG": "en_US.UTF-8",
            "PATH": java + "/bin:/usr/bin:/bin:/usr/sbin:/sbin", "JAVA_HOME": java,
            "JAVA_TOOL_OPTIONS": "-Duser.home=" + prefix.appendingPathComponent("home").path + " -Djava.io.tmpdir=" + prefix.appendingPathComponent("tmp").path + " -Djava.util.prefs.userRoot=" + prefix.appendingPathComponent("home/prefs").path,
            "ANDROID_HOME": prefix.appendingPathComponent("sdk").path, "ANDROID_SDK_ROOT": prefix.appendingPathComponent("sdk").path,
            "ANDROID_USER_HOME": prefix.appendingPathComponent("android-user").path, "ANDROID_EMULATOR_HOME": prefix.appendingPathComponent("android-emulator").path,
            "ANDROID_AVD_HOME": prefix.appendingPathComponent("avd").path, "GRADLE_USER_HOME": prefix.appendingPathComponent("gradle").path,
            "TMPDIR": prefix.appendingPathComponent("tmp").path + "/", "XDG_CACHE_HOME": prefix.appendingPathComponent("home/cache").path]
        let directory = prefix.appendingPathComponent("source")
        let runner = BoundedRunner(base: SystemProcessRunner(environment: env, workingDirectory: directory), runtime: CommandLine.arguments.contains("--runtime-probes"), cancelDownload: CommandLine.arguments.contains("--cancel-download"), failPlatform: CommandLine.arguments.contains("--fail-platform"))
        let input = ProjectInspectionInput(directory: directory, environment: env)
        if CommandLine.arguments.contains("--plan") {
            let approval = CommandLine.arguments.first { $0.hasPrefix("--approved=") }.map { String($0.dropFirst(11)) }
            let leases = ResourceLeases(directory: prefix.appendingPathComponent("leases"))
            let held = CommandLine.arguments.contains("--hold-sdk") ? try leases.acquire([.destination(prefix.appendingPathComponent("sdk"))], owner: LeaseOwner(operationId: "owned204-conflicting-sdk", command: "validation", project: directory.path)) : nil
            defer { held?.release() }
            let result = await PreparationExecution.run(input: input, planOnly: approval == nil, approvedPlanID: approval,
                runner: runner, leases: leases, onEvent: { event in
                    if let data = try? JSONEncoder().encode(event) { FileHandle.standardError.write(data + Data([10])) }
                })
            print(try result.encoded(toolVersion: "owned-harness-204"))
        } else {
            guard let candidate = try input.selection().selected, let anchor = ProjectAnchor.detect(candidate: candidate) else { throw ValidationFailure.message( "No selected native Android candidate") }
            let context = AndroidDoctorContext(anchor: anchor, config: ConfigContext.detect(anchor: anchor, workingDirectory: directory),
                hostRunner: runner, projectRunner: runner, environment: AndroidEnvironment(values: env))
            let requirements = try await context.sdkRequirements()
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(decoding: try encoder.encode(requirements), as: UTF8.self))
            if CommandLine.arguments.contains("--metadata") {
                let output = try await runner.run(AndroidSDKRepository.command)
                guard output.terminationStatus.isSuccess else { throw ValidationFailure.message("Official repository read failed") }
                let repository = try AndroidSDKRepository(data: Data(output.standardOutput.utf8))
                var pins: [[String: String]] = []
                for requirement in requirements.packages {
                    let package = try repository.package(requirement.packagePath)
                    pins.append(["package": package.packagePath, "revision": package.revision,
                        "url": package.archiveURL.absoluteString, "size": String(package.size), "sha1": package.sha1,
                        "licenseAccepted": String(package.licenseAccepted(in: prefix.appendingPathComponent("sdk"))), "repositorySHA256": repository.sha256, "licenseID": package.licenseID, "licenseSHA1": package.licenseSHA1,
                        "destination": prefix.appendingPathComponent("sdk").appendingPathComponent(package.packagePath.replacingOccurrences(of: ";", with: "/")).path])
                }
                try JSONSerialization.data(withJSONObject: pins, options: [.prettyPrinted, .sortedKeys]).write(to: prefix.appendingPathComponent("evidence/exact-payload-plan.json"))
            }
        }
    }
}

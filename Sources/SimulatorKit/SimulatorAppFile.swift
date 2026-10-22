import Core
import Foundation

/// The source-free path uses simctl only. It never enters a project or builds one.
public struct SimulatorAppFile: Sendable {
    private let runner: any ProcessRunner
    private let locator: XcodeLocator

    public init(runner: any ProcessRunner, environment: [String: String]) {
        self.runner = runner
        locator = XcodeLocator(runner: runner, developerDirOverride: environment["DEVELOPER_DIR"])
    }

    public func metadata(_ file: URL) async throws -> AppFileMetadata {
        let bundle = try await IOSAppBundle.read(file, target: .simulator, runner: runner, failure: Self.failure)
        return AppFileMetadata(platform: .ios, appID: bundle.appID, name: bundle.name, version: bundle.version,
            build: bundle.build, architectures: bundle.architectures, minimumOS: bundle.minimumOS,
            signatureCondition: "Simulator input; final platform acceptance is checked by simctl install. No signing or re-signing is performed.")
    }

    public func devices() async throws -> [AppFileDevice] {
        let installation = try await locator.locate()
        let environment = await locator.pinnedEnvironment()
        let result = try await runner.run(SimctlDeviceList.command(environment: environment))
        guard result.terminationStatus.isSuccess, let list = SimctlDeviceList.decode(result.standardOutput) else {
            throw Self.failure("The available Simulator identities could not be read.")
        }
        let inventory = try await runner.run(SimctlRuntimeList.command(environment: environment))
        guard inventory.terminationStatus.isSuccess, let runtimes = SimctlRuntimeList.decode(inventory.standardOutput) else {
            throw Self.failure("The Simulator runtime capability inventory could not be read.")
        }
        let simulators = list.simulators
        guard Set(simulators.map(\.udid)).count == simulators.count else {
            throw Self.failure("A Simulator identity appears on more than one runtime. Its target is unknown.")
        }
        return simulators.sorted(by: { $0.udid < $1.udid }).map { device in
            let matches = runtimes.runtimes.filter { $0.identifier == device.runtimeIdentifier }
            let runtime = matches.count == 1 ? matches.first : nil
            let architectures = runtime.flatMap { runtime -> [String]? in
                guard runtime.isIOS, runtime.isAvailable,
                      SemanticVersion(runtime.version) == device.runtime,
                      let build = runtime.buildversion, !build.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let values = runtime.supportedArchitectures, !values.isEmpty,
                      Set(values).count == values.count,
                      values.allSatisfy({ ["arm64", "x86_64"].contains($0) }) else { return nil }
                return values
            } ?? []
            return AppFileDevice(id: device.udid, handle: device.udid, name: device.name,
                os: device.runtimeText, architectures: architectures,
                ready: device.isAvailable && device.isBooted, toolIdentity: installation.summary,
                runtimeIdentifier: device.runtimeIdentifier, runtimeBuild: runtime?.buildversion,
                runtimeAvailable: runtime?.isAvailable,
                architectureSource: "simctl list runtimes -j supportedArchitectures; runtime capabilities, not measured device CPU")
        }
    }

    public func installed(appID: String, device: AppFileDevice) async throws -> AppFileInstalledState {
        let result = try await command(["listapps", device.handle])
        guard result.terminationStatus.isSuccess,
              let plist = try? PropertyListSerialization.propertyList(from: Data(result.standardOutput.utf8), format: nil),
              let apps = plist as? [String: [String: Any]] else {
            return AppFileInstalledState(state: "unknown", detail: "simctl listapps could not confirm the installed state")
        }
        guard let app = apps[appID] else { return AppFileInstalledState(state: "absent") }
        return AppFileInstalledState(state: "installed", version: app["CFBundleShortVersionString"] as? String,
            build: app["CFBundleVersion"] as? String, location: app["Path"] as? String)
    }

    public func install(file: URL, device: AppFileDevice) async throws {
        let result = try await command(["install", device.handle, file.path], timeout: .seconds(120))
        guard result.terminationStatus.isSuccess else {
            throw Self.failure("simctl refused the app installation: " + result.combinedOutput.lastLines(8))
        }
    }

    public func launch(appID: String, device: AppFileDevice) async throws {
        let result = try await command(["launch", device.handle, appID], timeout: .seconds(60))
        guard result.terminationStatus.isSuccess else {
            throw Self.failure("simctl refused the launch request: " + result.combinedOutput.lastLines(8))
        }
    }

    public func observe(_ claim: ResourceClaim) async throws -> ClaimObservation {
        guard claim.platform == .ios, claim.device == .device(.ios, claim.handle) else {
            return .unknown("the recorded claim does not identify this Simulator platform and device")
        }
        return try await simulatorAppObservation(udid: claim.handle, bundleID: claim.appID, runner: runner, locator: locator)
    }

    private func command(_ arguments: [String], timeout: Duration = .seconds(30)) async throws -> ProcessResult {
        try await runner.run(ProcessCommand("xcrun", ["simctl"] + arguments,
            environment: await locator.pinnedEnvironment(), timeout: timeout))
    }

    private static func failure(_ summary: String) -> DomainError {
        DomainError(summary: summary, remediation: Remediation(summary: "Choose a supported iOS Simulator .app and a prepared, booted Simulator, then inspect again. No app was deleted or re-signed."))
    }
}

/// Info.plist and Mach-O metadata shared by the Simulator and physical-device paths.
/// Platform tools read the executable's load commands; the executable is never run.
struct IOSAppBundle {
    enum Target {
        case simulator, device

        var plistPlatform: String { self == .simulator ? "iPhoneSimulator" : "iPhoneOS" }
        var machOPlatforms: Set<String> { self == .simulator ? ["7", "iossimulator"] : ["2", "ios"] }
        var architectures: Set<String> { self == .simulator ? ["arm64", "x86_64"] : ["arm64", "arm64e"] }
        var label: String { self == .simulator ? "Simulator" : "iOS device" }
    }

    let appID: String
    let name: String?
    let version: String?
    let build: String
    let architectures: [String]
    let minimumOS: String

    /// Only a peek at the declared platform; full validation is `read`.
    static func declaresDevice(_ file: URL) -> Bool {
        let url = file.appendingPathComponent("Info.plist")
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1_048_576,
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return false }
        return (plist["CFBundleSupportedPlatforms"] as? [String])?.contains(Target.device.plistPlatform) == true
    }

    static func read(_ file: URL, target: Target, runner: any ProcessRunner,
                     failure: (String) -> DomainError) async throws -> IOSAppBundle {
        let infoURL = file.appendingPathComponent("Info.plist")
        guard let size = try infoURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1_048_576,
              let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoURL), format: nil) as? [String: Any],
              plist["CFBundlePackageType"] as? String == "APPL",
              let appID = plist["CFBundleIdentifier"] as? String,
              appID.range(of: #"^[A-Za-z0-9][A-Za-z0-9.-]*$"#, options: .regularExpression) != nil,
              let build = plist["CFBundleVersion"] as? String,
              build.range(of: #"^[0-9]+(?:\.[0-9]+){0,3}(?:(?:d|a|b|fc)[0-9]+)?$"#, options: .regularExpression) != nil,
              let executable = plist["CFBundleExecutable"] as? String,
              !executable.isEmpty, executable != ".", executable != "..", !executable.contains("/"),
              let minimum = plist["MinimumOSVersion"] as? String, SemanticVersion(minimum) != nil,
              (plist["CFBundleSupportedPlatforms"] as? [String])?.contains(target.plistPlatform) == true else {
            throw failure("The .app lacks required \(target.label) platform, app ID, build, executable or OS metadata.")
        }
        let binary = file.appendingPathComponent(executable).resolvingSymlinksInPath()
        guard binary.path.hasPrefix(file.path + "/"),
              try binary.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw failure("The app executable must be a regular file inside the .app.")
        }
        // These platform tools read Mach-O metadata. The app executable is never run.
        let arch = try await runner.run(ProcessCommand("/usr/bin/lipo", ["-archs", binary.path]))
        let architectures = arch.standardOutput.split(whereSeparator: \.isWhitespace).map(String.init).sorted()
        guard arch.terminationStatus.isSuccess, !architectures.isEmpty,
              architectures.allSatisfy({ target.architectures.contains($0) }) else {
            throw failure("The app has unknown or unsupported executable architectures.")
        }
        for architecture in architectures {
            let settings = try await runner.run(ProcessCommand("/usr/bin/otool", ["-arch", architecture, "-l", binary.path]))
            var command = ""
            var platforms: [String] = []
            var minimums: [SemanticVersion] = []
            for line in settings.standardOutput.split(whereSeparator: \.isNewline) {
                let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
                if fields.count == 2, fields[0] == "cmd" { command = fields[1] }
                if command == "LC_BUILD_VERSION", fields.count >= 2 {
                    if fields[0] == "platform" { platforms.append(fields[1].lowercased()) }
                    if fields[0] == "minos", let version = SemanticVersion(fields[1]) { minimums.append(version) }
                }
            }
            guard settings.terminationStatus.isSuccess, !platforms.isEmpty,
                  platforms.allSatisfy({ target.machOPlatforms.contains($0) }),
                  !minimums.isEmpty, let declared = SemanticVersion(minimum),
                  minimums.allSatisfy({ $0 <= declared }) else {
                throw failure("The executable's \(target.label) platform or minimum OS is unknown or disagrees with Info.plist.")
            }
        }
        return IOSAppBundle(appID: appID, name: plist["CFBundleDisplayName"] as? String ?? plist["CFBundleName"] as? String,
            version: plist["CFBundleShortVersionString"] as? String, build: build,
            architectures: architectures, minimumOS: minimum)
    }
}

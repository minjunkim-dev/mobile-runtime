import Core
import Foundation
import TestSupport
import Testing

@testable import SimulatorKit

private let developerDirectory = "/Applications/Xcode.app/Contents/Developer"
private let packageJSON = #"{"dependencies": {"react-native": "0.81.0"}}"#

/// Devices as simctl groups them: by runtime, which is what makes "the same name
/// on two runtimes" a real question.
private func deviceList(_ devices: (name: String, runtime: String, available: Bool)...) -> String {
    var byRuntime: [String: [String]] = [:]
    for (index, device) in devices.enumerated() {
        let identifier = "com.apple.CoreSimulator.SimRuntime.iOS-"
            + device.runtime.replacingOccurrences(of: ".", with: "-")
        // udid and state are fields simctl always prints; `config.values` reads
        // neither, and `up`'s device stage cannot work without them.
        let udid = "00000000-0000-0000-0000-\(String(format: "%012d", index))"
        byRuntime[identifier, default: []].append(
            #"{"name": "\#(device.name)", "udid": "\#(udid)", "state": "Shutdown", "#
                + #""isAvailable": \#(device.available)}"#
        )
    }
    let entries = byRuntime.map { #""\#($0)": [\#($1.joined(separator: ","))]"# }
    return #"{"devices": {\#(entries.joined(separator: ","))}}"#
}

private func schemeList(_ schemes: [String], container: String = "project") -> String {
    #"{"\#(container)": {"name": "MyApp", "schemes": [\#(schemes.map { "\"\($0)\"" }.joined(separator: ","))]}}"#
}

/// A React Native project with an Xcode project beside it — the shape every
/// scheme question needs.
private func project(
    _ mobileYML: String?,
    iOSDirectory: Bool = true,
    workspaceOnly: Bool = false
) throws -> FixtureRepo {
    let repo = try FixtureRepo()
    try repo.write("package.json", packageJSON)
    if iOSDirectory {
        if workspaceOnly {
            try repo.directory("ios/MyApp.xcworkspace")
            try repo.directory("ios/App/MyApp.xcodeproj")
        } else {
            try repo.directory("ios/MyApp.xcodeproj")
        }
    }
    if let mobileYML { try repo.write("mobile.yml", mobileYML) }
    return repo
}

private func check(
    _ repo: FixtureRepo,
    from subdirectory: String? = nil,
    devices: String = deviceList(("iPhone 16 Pro", "18.2", true)),
    schemes: [String] = ["MyApp"],
    lookup: MatrixLookup? = nil
) async throws -> (result: CheckResult?, runner: FakeProcessRunner) {
    let runner = FakeProcessRunner(responses: [
        "xcode-select -p": .ok(developerDirectory + "\n"),
        "xcodebuild -version": .ok("Xcode 26.6\nBuild version 17F113\n"),
        "xcrun simctl list devices -j": .ok(devices),
        "xcodebuild -list -json -project \(repo.url("ios/MyApp.xcodeproj").path)": .ok(schemeList(schemes)),
        "xcodebuild -list -json -workspace \(repo.url("ios/MyApp.xcworkspace").path)":
            .ok(schemeList(schemes, container: "workspace")),
    ])
    let workingDirectory = subdirectory.map { repo.url($0) } ?? repo.root
    let context = ConfigContext.detect(
        anchor: ProjectAnchor.detect(from: workingDirectory),
        workingDirectory: workingDirectory
    )
    let report = await DoctorEngine(
        checks: configChecks(
            context: context,
            lookup: lookup,
            runner: runner,
            locator: XcodeLocator(runner: runner, developerDirOverride: nil)
        )
    ).run()
    return (report.checks.first { $0.id == "config.values" }, runner)
}

@Suite("config.values")
struct ConfigValuesCheckTests {
    @Test("passes, naming the runtime it resolved the device on")
    func declarationsExist() async throws {
        let repo = try project("ios:\n  device: iPhone 16 Pro\n  scheme: MyApp\n")

        let check = try #require(try await check(repo).result)

        #expect(check.status == .pass)
        #expect(check.outcome.observed == "device iPhone 16 Pro on iOS 18.2, scheme MyApp")
        #expect(check.outcome.source.tier == 3)
    }

    /// A Tier 3 declaration is measured like everything else — and the recovery is
    /// the list of what is actually there.
    @Test("errors, with what does exist, when the declared device is not installed")
    func deviceMissing() async throws {
        let repo = try project("ios:\n  device: iPhone 15 Ultra\n")

        let check = try #require(
            try await check(
                repo,
                devices: deviceList(("iPhone 16 Pro", "18.2", true), ("iPad Air", "18.2", true))
            ).result
        )

        #expect(check.status == .error)
        #expect(check.outcome.observed == "no simulator named iPhone 15 Ultra")
        #expect(check.outcome.remediation?.summary.contains("iPad Air, iPhone 16 Pro") == true)
        #expect(check.outcome.remediation?.command == "xcrun simctl list devices available")
    }

    @Test("resolves the newest runtime when one device name exists on several")
    func deviceOnSeveralRuntimes() async throws {
        let repo = try project("ios:\n  device: iPhone 16 Pro\n")

        let check = try #require(
            try await check(
                repo,
                devices: deviceList(
                    ("iPhone 16 Pro", "18.2", true),
                    ("iPhone 16 Pro", "26.0", true),
                    ("iPhone 16 Pro", "17.5", true)
                )
            ).result
        )

        #expect(check.outcome.observed == "device iPhone 16 Pro on iOS 26.0, no scheme declared — MyApp is the only one")
    }

    /// Whether any installed runtime is new enough is `simulator.runtime`'s verdict.
    /// Saying it twice would be two errors for one problem.
    @Test("does not re-raise the runtime verdict when the device only exists on an old runtime")
    func deviceOnlyOnOldRuntime() async throws {
        let repo = try project("ios:\n  device: iPhone 16 Pro\n")
        let lookup = MatrixLookup(
            xcode: .requirement(MinimumVersion("16.1")!, source: CheckSource(tier: 2, origin: "matrix")),
            runtime: .requirement(MinimumVersion("15.1")!, source: CheckSource(tier: 2, origin: "matrix"))
        )

        let check = try #require(
            try await check(
                repo,
                devices: deviceList(("iPhone 16 Pro", "14.0", true)),
                lookup: lookup
            ).result
        )

        #expect(check.status == .pass)
        #expect(check.outcome.observed == "device iPhone 16 Pro on iOS 14.0, no scheme declared — MyApp is the only one")
    }

    @Test("errors when the device is unavailable rather than absent")
    func deviceUnavailable() async throws {
        let repo = try project("ios:\n  device: iPhone 16 Pro\n")

        let check = try #require(
            try await check(repo, devices: deviceList(("iPhone 16 Pro", "18.2", false))).result
        )

        #expect(check.status == .error)
        #expect(check.outcome.observed?.contains("unavailable") == true)
        #expect(check.outcome.remediation?.command?.contains("scan-and-mount") == true)
    }

    /// The runtime is inferred, so naming one in the device value is a second
    /// answer to a question the project already answers.
    @Test("errors when ios.device names a runtime as well as a device")
    func deviceNamesARuntime() async throws {
        let repo = try project("ios:\n  device: iPhone 16 Pro (26.0)\n")

        let check = try #require(try await check(repo).result)

        #expect(check.status == .error)
        #expect(check.outcome.observed?.contains("names a runtime as well as a device") == true)
    }

    /// Apple ships simulators whose own names carry parentheses.
    @Test("accepts a simulator whose real name ends in parentheses")
    func parenthesisedDeviceName() async throws {
        let repo = try project("ios:\n  device: iPad Pro (12.9-inch) (6th generation)\n")

        let check = try #require(
            try await check(
                repo,
                devices: deviceList(("iPad Pro (12.9-inch) (6th generation)", "18.2", true))
            ).result
        )

        #expect(check.status == .pass)
    }

    /// mobile.yml is committed with the repo, and a UDID belongs to one machine.
    @Test("errors when ios.device is a UDID")
    func deviceIsUDID() async throws {
        let repo = try project("ios:\n  device: 4A5B6C7D-1234-4321-ABCD-0123456789AB\n")

        let check = try #require(try await check(repo).result)

        #expect(check.status == .error)
        #expect(check.outcome.observed?.contains("is a UDID") == true)
        #expect(check.outcome.required == "a simulator name")
    }

    /// The reason mobile.yml exists at all — but a warning, not an error. doctor
    /// answers "can this machine build the project", and an unpicked scheme is a
    /// choice nobody has made yet, not a broken machine. All three dogfooding repos
    /// ship several schemes because app extensions are normal, and exit 1 in CI is
    /// too strong a word for that (ADR-0004). `up` is where it stops the work.
    @Test("warns when the project has several schemes and nothing declares one")
    func schemeAmbiguous() async throws {
        let repo = try project(nil)

        let check = try #require(
            try await check(repo, schemes: ["MyApp", "MyApp-tvOS"]).result
        )

        #expect(check.status == .warning)
        #expect(check.outcome.observed?.contains("MyApp, MyApp-tvOS") == true)
        #expect(check.outcome.required?.contains("ios.scheme") == true)
        #expect(check.outcome.remediation?.summary.contains("mobile.yml") == true)
        // Paths under the working directory are written relative to it: the reader's
        // home directory is not part of the instruction (#35).
        #expect(check.outcome.remediation?.command == "xcodebuild -list -project ios/MyApp.xcodeproj")
        #expect(check.outcome.remediation?.summary.contains(repo.root.path) == false)
    }

    @Test("a single scheme needs no declaration")
    func schemeUnambiguous() async throws {
        let repo = try project(nil)

        let check = try #require(try await check(repo).result)

        #expect(check.status == .pass)
        #expect(check.outcome.observed == "no scheme declared — MyApp is the only one")
    }

    @Test("a root workspace with only a nested project is checked before build")
    func schemeInWorkspaceOnlyRoot() async throws {
        let repo = try project(nil, workspaceOnly: true)

        let check = try #require(try await check(repo).result)

        #expect(check.status == .pass)
        #expect(check.outcome.observed == "no scheme declared — MyApp is the only one")
    }

    @Test("errors when the declared scheme is not one the project defines")
    func schemeMissing() async throws {
        let repo = try project("ios:\n  scheme: Staging\n")

        let check = try #require(
            try await check(repo, schemes: ["MyApp", "MyApp-tvOS"]).result
        )

        #expect(check.status == .error)
        #expect(check.outcome.observed?.contains("no scheme named Staging") == true)
    }

    /// Validating the values of a file that did not parse is meaningless.
    @Test("does not check values — or ask the machine anything — when the file did not parse")
    func syntaxErrorSkipsValues() async throws {
        let repo = try project("ios:\n\tdevice: iPhone 16 Pro\n")

        let (result, runner) = try await check(repo)
        let check = try #require(result)

        #expect(check.status == .unknown)
        #expect(check.outcome.reason?.contains("config.syntax") == true)
        #expect(runner.log.all.isEmpty)
    }

    @Test("warns about a mobile.yml sitting where mobile never reads one")
    func stray() async throws {
        let repo = try FixtureRepo()
        try repo.write("mobile.yml", "ios:\n  scheme: MyApp\n")

        let (result, runner) = try await check(repo)
        let check = try #require(result)

        #expect(check.status == .warning)
        #expect(check.outcome.observed?.contains("not next to a React Native project") == true)
        #expect(runner.log.all.isEmpty)
    }

    /// A stray must never swallow the verdict on the file mobile actually reads.
    @Test("still checks the anchor's own file when a stray sits below it")
    func strayDoesNotMaskTheRealFile() async throws {
        let repo = try project("ios:\n  device: iPhone 15 Ultra\n")
        try repo.write("ios/mobile.yml", "ios:\n  scheme: MyApp\n")

        let check = try #require(try await check(repo, from: "ios").result)

        #expect(check.status == .error)
        #expect(check.outcome.observed == "no simulator named iPhone 15 Ultra")
    }

    /// zero-config: a project with nothing to declare and nothing to disambiguate
    /// gets no mobile.yml line at all.
    @Test("is absent when there is no mobile.yml and no Xcode project to ask about")
    func nothingToSay() async throws {
        let repo = try project(nil, iOSDirectory: false)

        #expect(try await check(repo).result == nil)
    }
}

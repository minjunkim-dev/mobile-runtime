import Core
import Foundation
import Testing
@testable import AndroidKit

@Suite("Android AVD SDK write protection", .serialized)
struct AndroidAVDSDKProtectionTests {
    @Test("wrapping retains every command field and the original absolute invocation")
    func commandFields() throws {
        let fixture = try SDKProtectionFixture()
        var original = fixture.command(["list", "device", "literal \" $argument"])
        original.environment["CUSTOM_VALUE"] = "unchanged"
        original.timeout = .seconds(7)
        original.output = .streamed(to: fixture.root.appendingPathComponent("output.log"))
        let wrapped = try AndroidEmulatorEnvironment.sdkReadOnlyCommand(original, sdk: fixture.sdk, writableDirectories: fixture.writable)
        #expect(wrapped.executable == "/usr/bin/sandbox-exec")
        #expect(wrapped.arguments.first == "-p")
        #expect(Array(wrapped.arguments.dropFirst(2)) == [original.executable] + original.arguments)
        #expect(wrapped.environment == original.environment)
        #expect(wrapped.workingDirectory == original.workingDirectory)
        #expect(wrapped.timeout == original.timeout)
        #expect(wrapped.output == original.output)
    }

    @Test("ambiguous paths and SDK/write overlaps fail closed", arguments: ["sdk-link", "parent-link", "write-link", "inside-sdk", "contains-sdk", "log-in-sdk", "outside-tool", "relative-tool", "sdk-env", "home-env", "control"])
    func unsafeBoundaries(kind: String) throws {
        let fixture = try SDKProtectionFixture()
        var sdk = fixture.sdk
        var writable = fixture.writable
        var command = fixture.command(["list", "device"])
        switch kind {
        case "sdk-link":
            sdk = fixture.root.appendingPathComponent("sdk-alias")
            try FileManager.default.createSymbolicLink(at: sdk, withDestinationURL: fixture.sdk)
        case "parent-link":
            let alias = fixture.root.appendingPathComponent("parent-alias")
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.root)
            sdk = alias.appendingPathComponent("sdk")
        case "write-link":
            let alias = fixture.root.appendingPathComponent("avd-alias")
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.avd)
            writable = [alias]
        case "inside-sdk": writable = [fixture.sdk.appendingPathComponent("new-avd")]
        case "contains-sdk": writable = [fixture.root]
        case "log-in-sdk": command.output = .streamed(to: fixture.sdk.appendingPathComponent("new.log"))
        case "outside-tool": command.executable = "/bin/sh"
        case "relative-tool": command.executable = "avdmanager"
        case "sdk-env": command.environment["ANDROID_HOME"] = "relative-sdk"
        case "home-env": command.environment["ANDROID_AVD_HOME"] = fixture.sdk.path
        default: sdk = fixture.root.appendingPathComponent("sdk\ninvalid")
        }
        #expect(throws: DomainError.self) {
            try AndroidEmulatorEnvironment.sdkReadOnlyCommand(command, sdk: sdk, writableDirectories: writable)
        }
        #expect(try String(contentsOf: fixture.marker, encoding: .utf8) == "original")
    }

    @Test("the OS denies descendant SDK writes while owned AVD and temp writes succeed", arguments: ["sdk", "sdk \"quoted\"\\name"])
    func operatingSystemDenial(name: String) async throws {
        let fixture = try SDKProtectionFixture(sdkName: name)
        let avdFile = fixture.avd.appendingPathComponent("owned")
        let tempFile = fixture.temporary.appendingPathComponent("owned")
        let command = try AndroidEmulatorEnvironment.sdkReadOnlyCommand(fixture.command([fixture.marker.path, avdFile.path, tempFile.path]),
            sdk: fixture.sdk, writableDirectories: fixture.writable)
        let result = try await SystemProcessRunner().run(command)
        #expect(!result.terminationStatus.isSuccess, Comment(rawValue: result.combinedOutput))
        #expect(try String(contentsOf: fixture.marker, encoding: .utf8) == "original")
        #expect(try String(contentsOf: avdFile, encoding: .utf8) == "owned")
        #expect(try String(contentsOf: tempFile, encoding: .utf8) == "owned")
    }

    @Test("the wrapped child retains the ProcessRunner timeout")
    func timeout() async throws {
        let fixture = try SDKProtectionFixture()
        var original = fixture.command(["sleep"])
        original.timeout = .milliseconds(80)
        let command = try AndroidEmulatorEnvironment.sdkReadOnlyCommand(original, sdk: fixture.sdk, writableDirectories: fixture.writable)
        do {
            _ = try await SystemProcessRunner().run(command)
            Issue.record("The protected child did not time out")
        } catch ProcessError.timedOut(_, let observed) {
            #expect(observed == original.timeout)
        }
    }

    @Test("the wrapped child retains ProcessRunner cancellation")
    func cancellation() async throws {
        let fixture = try SDKProtectionFixture()
        let command = try AndroidEmulatorEnvironment.sdkReadOnlyCommand(fixture.command(["sleep"]), sdk: fixture.sdk, writableDirectories: fixture.writable)
        let task = Task { try await SystemProcessRunner().run(command) }
        let started = fixture.home.appendingPathComponent("sleep.pid")
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: started.path) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(FileManager.default.fileExists(atPath: started.path))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try String(contentsOf: fixture.marker, encoding: .utf8) == "original")
    }
}

private final class SDKProtectionFixture {
    let root: URL
    let sdk: URL
    let avd: URL
    let temporary: URL
    let home: URL
    let manager: URL
    let marker: URL
    var writable: [URL] { [avd, temporary, home] }

    init(sdkName: String = "sdk") throws {
        let temporaryRoot = ProcessInfo.processInfo.environment["TMPDIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
        root = temporaryRoot.appendingPathComponent("runstir-sdk-protection-\(UUID().uuidString)", isDirectory: true)
        sdk = root.appendingPathComponent(sdkName, isDirectory: true)
        avd = root.appendingPathComponent("avd", isDirectory: true)
        temporary = root.appendingPathComponent("tmp", isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        manager = sdk.appendingPathComponent("cmdline-tools/21.0/bin/avdmanager")
        marker = sdk.appendingPathComponent("package.xml")
        for path in [manager.deletingLastPathComponent(), avd, temporary, home] {
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        }
        try Data("original".utf8).write(to: marker)
        let script = """
        #!/bin/sh
        if [ "$1" = sleep ]; then
          /usr/bin/printf '%s' "$$" > "$ANDROID_USER_HOME/sleep.pid"
          exec /bin/sleep 2
        fi
        /bin/sh -c 'printf mutated > "$1"' _ "$1"
        denied=$?
        /usr/bin/printf owned > "$2"
        /usr/bin/printf owned > "$3"
        exit "$denied"
        """
        try Data(script.utf8).write(to: manager)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: manager.path)
    }
    deinit { try? FileManager.default.removeItem(at: root) }
    func command(_ arguments: [String]) -> ProcessCommand {
        ProcessCommand(manager.path, arguments, environment: [
            "HOME": home.path, "CFFIXED_USER_HOME": home.path, "TMPDIR": temporary.path + "/", "PATH": "/usr/bin:/bin",
            "ANDROID_HOME": sdk.path, "ANDROID_SDK_ROOT": sdk.path, "ANDROID_AVD_HOME": avd.path,
            "ANDROID_USER_HOME": home.path, "ANDROID_EMULATOR_HOME": home.path
        ], workingDirectory: root, timeout: .seconds(5))
    }
}

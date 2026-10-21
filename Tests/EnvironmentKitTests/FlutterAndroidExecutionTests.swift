import Core
import Darwin
@testable import EnvironmentKit
import Foundation
import TestSupport
import Testing

@Suite("Flutter Android private execution boundaries", .serialized)
struct FlutterAndroidExecutionTests {
    @Test("factory rejects unverified SDK capability before creating a private execution view")
    func unverifiedFactoryInput() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let (app, preparation) = try await fixture.preparation()
        try #require(preparation.checks.contains { $0.id == "android.flutter.generated" && $0.kind == "reuse" })
        for relative in ["kotlin/tasks/BaseFlutterTask.kt", "kotlin/tasks/BaseFlutterTaskHelper.kt", "kotlin/FlutterPlugin.kt",
                         "kotlin/FlutterAppPluginLoaderPlugin.kt", "scripts/native_plugin_loader.gradle.kts"] {
            try fixture.file("sdk/packages/flutter_tools/gradle/src/main/" + relative, "unverified fixture bytes; never execute\n")
        }
        try fixture.file("sdk/packages/flutter_tools/.dart_tool/package_config.json", #"{"configVersion":2,"packages":[]}"#)
        try fixture.file("workspace/android/gradle/wrapper/gradle-wrapper.properties",
            "distributionUrl=https\\://services.gradle.org/distributions/gradle-8.14-bin.zip\n")
        try fixture.file("workspace/android/gradlew", "fixture wrapper; never execute\n", mode: 0o700)
        let temporary = try fixture.directory("factory-private-views")
        let before = try FlutterAndroidExecution.tree(fixture.root, bindIdentity: true)
        #expect(throws: DomainError.self) {
            try FlutterAndroidExecution.prepare(app: app, preparation: preparation, trackedFiles: [], temporaryDirectory: temporary)
        }
        #expect(try FileManager.default.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil).isEmpty)
        #expect(try FlutterAndroidExecution.tree(fixture.root, bindIdentity: true) == before)
    }

    @Test("private SDK copy preserves source bytes, links and permissions without sharing inodes")
    func copyPreservesSource() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = try fixture.directory("source")
        try fixture.file("source/bin/tool", "selected SDK bytes", mode: 0o755)
        try fixture.file("source/packages/tool.txt", "tool source")
        #expect(symlink("tool", source.appendingPathComponent("bin/alias").path) == 0)
        #expect(symlink("../packages/tool.txt", source.appendingPathComponent("bin/relative").path) == 0)
        let original = try FlutterAndroidExecution.tree(source, bindIdentity: true)
        let copy = fixture.root.appendingPathComponent("copy")
        try FlutterAndroidExecution.copyTree(source, to: copy, snapshot: original)
        #expect(try FlutterAndroidExecution.tree(source, bindIdentity: true) == original)
        #expect(try FlutterAndroidExecution.tree(copy) == original.mapValues(\.unbound))
        for key in ["bin/tool", "packages/tool.txt"] {
            #expect(try FlutterAndroidExecution.entry(source.appendingPathComponent(key), bindIdentity: true).nodeIdentity
                != FlutterAndroidExecution.entry(copy.appendingPathComponent(key), bindIdentity: true).nodeIdentity)
        }
        #expect(throws: DomainError.self) { try FlutterAndroidExecution.copyTree(source, to: copy, snapshot: original) }
        #expect(try String(contentsOf: copy.appendingPathComponent("bin/tool"), encoding: .utf8) == "selected SDK bytes")
    }

    @Test("external links, unresolved links, hardlinks and external Git layouts stop isolation", arguments: [
        "external", "absolute", "dangling", "hardlink", "gitfile",
    ])
    func rejectedTree(_ kind: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = try fixture.directory("source")
        try fixture.file("outside", "preserved")
        switch kind {
        case "external": #expect(symlink("../outside", source.appendingPathComponent("alias").path) == 0)
        case "absolute": #expect(symlink(fixture.root.appendingPathComponent("outside").path, source.appendingPathComponent("alias").path) == 0)
        case "dangling": #expect(symlink("missing", source.appendingPathComponent("alias").path) == 0)
        case "hardlink": #expect(link(fixture.root.appendingPathComponent("outside").path, source.appendingPathComponent("alias").path) == 0)
        default: try fixture.file("source/.git", "gitdir: ../other/.git")
        }
        #expect(throws: (any Error).self) { try FlutterAndroidExecution.tree(source) }
        #expect(try String(contentsOf: fixture.root.appendingPathComponent("outside"), encoding: .utf8) == "preserved")
    }

    @Test("changed SDK input is retained and cannot become a successful copy")
    func changedInput() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = try fixture.directory("source")
        try fixture.file("source/tool", "before")
        let original = try FlutterAndroidExecution.tree(source, bindIdentity: true)
        try Data("changed bytes".utf8).write(to: source.appendingPathComponent("tool"))
        #expect(throws: DomainError.self) {
            try FlutterAndroidExecution.copyTree(source, to: fixture.root.appendingPathComponent("partial"), snapshot: original)
        }
        #expect(try String(contentsOf: source.appendingPathComponent("tool"), encoding: .utf8) == "changed bytes")
        #expect(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("partial").path))
    }

    @Test("input identity changes are distinct from equal bytes")
    func sameBytesReplacement() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.file("source/tool", "same")
        let source = fixture.root.appendingPathComponent("source")
        let before = try FlutterAndroidExecution.tree(source, bindIdentity: true)
        try FileManager.default.moveItem(at: source.appendingPathComponent("tool"), to: fixture.root.appendingPathComponent("old-tool"))
        try fixture.file("source/tool", "same")
        #expect(try FlutterAndroidExecution.tree(source) == before.mapValues(\.unbound))
        #expect(try FlutterAndroidExecution.tree(source, bindIdentity: true) != before)
    }

    @Test("cancellation preserves a partial owned copy and original SDK")
    func cancelledCopy() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.file("source/tool", "original")
        let source = fixture.root.appendingPathComponent("source")
        let before = try FlutterAndroidExecution.tree(source, bindIdentity: true)
        let gate = Gate()
        let task = Task {
            await gate.wait()
            try FlutterAndroidExecution.copyTree(source, to: fixture.root.appendingPathComponent("partial"), snapshot: before)
        }
        task.cancel()
        await gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try FlutterAndroidExecution.tree(source, bindIdentity: true) == before)
        #expect(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("partial").path))
    }

    @Test("canonical templates accept version and root name changes, preserving the original bytes", arguments: [false, true])
    func canonicalSettings(_ kotlin: Bool) throws {
        let original = kotlin ? Self.kotlin : Self.groovy
        for version in ["8.11.1", "8.13.2", "8.14.0-rc-1"] {
            let changed = original.replacingOccurrences(of: "8.12.1", with: version)
                + "\nrootProject.name = \"customer app \(version)\"\n"
            let bytes = Data(changed.utf8)
            try FlutterAndroidExecution.validateSettings(bytes)
            #expect(bytes == Data(changed.utf8))
        }
    }

    @Test("additional relative settings logic is rejected before execution", arguments: [
        "apply from: '../other.gradle'", "includeBuild('../other')", "include(':another')",
        "dependencyResolutionManagement { versionCatalogs { create('libs') } }",
        "file('local.properties').text = 'changed'",
    ])
    func customSettings(_ extra: String) {
        #expect(throws: DomainError.self) {
            try FlutterAndroidExecution.validateSettings(Data((Self.groovy + "\n" + extra).utf8))
        }
    }

    @Test("wrapper selection remains Gradle 8 and rejects ambiguous Java Properties inputs")
    func wrapperSelection() throws {
        for version in ["8.13", "8.14.3"] {
            try FlutterAndroidExecution.validateWrapper("distributionUrl=https\\://services.gradle.org/distributions/gradle-\(version)-all.zip\nnetworkTimeout=10000\n")
        }
        for source in [
            "distributionUrl=https\\://services.gradle.org/distributions/gradle-7.5-all.zip",
            "distributionUrl=https\\://services.gradle.org/distributions/gradle-9.0-all.zip",
            "distributionUrl=https\\://services.gradle.org/distributions/gradle-8.13-all.zip\ndistributionUrl=https\\://services.gradle.org/distributions/gradle-9.0-all.zip",
            "distributionUrl=https\\://services.gradle.org/distributions/gradle-8.13-all.zip\ndistribution\\u0055rl=https\\://services.gradle.org/distributions/gradle-9.0-all.zip",
            "distributionUrl=https\\://services.gradle.org/distributions/\\\ngradle-8.13-all.zip",
        ] {
            #expect(throws: DomainError.self) { try FlutterAndroidExecution.validateWrapper(source) }
        }
    }

    @Test("exclusive private files reject existing files and symlinks without changing targets")
    func exclusiveWrites() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.file("owned", "existing")
        let existing = fixture.root.appendingPathComponent("owned")
        #expect(symlink("owned", fixture.root.appendingPathComponent("alias").path) == 0)
        for path in [existing, fixture.root.appendingPathComponent("alias")] {
            #expect(throws: DomainError.self) { try FlutterAndroidExecution.write(Data("replace".utf8), to: path) }
        }
        #expect(try String(contentsOf: existing, encoding: .utf8) == "existing")
        let created = fixture.root.appendingPathComponent("new")
        try FlutterAndroidExecution.write(Data("private".utf8), to: created)
        #expect(try FlutterAndroidExecution.entry(created).mode == 0o600)
        #expect(try FlutterAndroidExecution.Identity(fixture.root).uid == getuid())
    }

    @Test("four shadow inputs preserve original local property bytes including escapes and duplicate keys")
    func shadowInputs() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let app = try fixture.directory("selected-app")
        let local = "# user-owned\nflutter.sdk=/selected/sdk\nsdk.dir=/existing/android\nsecret\\ key: preserved\\ value\nflutter.sdk=/last/sdk\n"
        try fixture.file("selected-app/android/settings.gradle", Self.groovy)
        try fixture.file("selected-app/android/gradle.properties", "org.gradle.jvmargs=-Xmx4G\n")
        try fixture.file("selected-app/android/local.properties", local)
        try fixture.file("selected-app/.flutter-plugins-dependencies", "{\"version\":\"3.41.9\",\"plugins\":{\"android\":[]}}")
        let before = try FlutterAndroidExecution.tree(app, bindIdentity: true)
        let owned = try FlutterAndroidExecution.makeRoot(in: fixture.root)
        let settings = try FlutterAndroidExecution.makeShadow(app: app, settingsFile: app.appendingPathComponent("android/settings.gradle"), ownedRoot: owned)
        #expect(try FlutterAndroidExecution.tree(app, bindIdentity: true) == before)
        #expect(try Data(contentsOf: settings) == Data(Self.groovy.utf8))
        #expect(try String(contentsOf: settings.deletingLastPathComponent().appendingPathComponent("local.properties"), encoding: .utf8) == local)
        for file in [settings, settings.deletingLastPathComponent().appendingPathComponent("gradle.properties"),
                     settings.deletingLastPathComponent().appendingPathComponent("local.properties"),
                     settings.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".flutter-plugins-dependencies")] {
            #expect(try FlutterAndroidExecution.entry(file).mode == 0o600)
        }
        #expect(throws: DomainError.self) {
            try FlutterAndroidExecution.makeShadow(app: app, settingsFile: app.appendingPathComponent("android/settings.gradle"), ownedRoot: owned)
        }
    }

    @Test("preparation's verified no-plugin absence remains absent in the private settings")
    func noPluginMetadataAbsence() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let (app, preparation) = try await fixture.preparation()
        #expect(preparation.checks.contains { $0.id == "android.flutter.generated" && $0.kind == "reuse" })
        let prepared = try FlutterAndroidExecution.preparedInputs(app: app, preparation: preparation, trackedFiles: [])
        #expect(prepared.metadata == nil)
        let before = try FlutterAndroidExecution.tree(app, bindIdentity: true)
        let owned = try FlutterAndroidExecution.makeRoot(in: fixture.root)
        let settings = try FlutterAndroidExecution.makeShadow(app: app, settingsFile: app.appendingPathComponent("android/settings.gradle"), ownedRoot: owned)
        #expect(!FileManager.default.fileExists(atPath: settings.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".flutter-plugins-dependencies").path))
        #expect(try FlutterAndroidExecution.tree(app, bindIdentity: true) == before)
        try prepared.check()
        try fixture.file("workspace/.flutter-plugins-dependencies", "unexpected new metadata")
        #expect(throws: DomainError.self) { try prepared.check() }
        #expect(try String(contentsOf: app.appendingPathComponent(".flutter-plugins-dependencies"), encoding: .utf8) == "unexpected new metadata")
    }

    @Test("reachable plugin metadata failure is not reclassified as no-plugin absence")
    func missingReachablePlugin() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let (app, preparation) = try await fixture.preparation(reachablePlugin: true)
        #expect(preparation.checks.contains { $0.id == "android.flutter.generated" && $0.kind != "reuse" })
        #expect(throws: DomainError.self) {
            try FlutterAndroidExecution.preparedInputs(app: app, preparation: preparation, trackedFiles: [])
        }
    }

    @Test("deleting reachable-plugin metadata after successful preparation rejects stale reuse")
    func deletedPreparedPluginMetadata() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let (app, preparation) = try await fixture.preparation(reachablePlugin: true, metadataForPlugin: true)
        #expect(preparation.checks.contains { $0.id == "android.flutter.generated" && $0.kind == "reuse" })
        let prepared = try FlutterAndroidExecution.preparedInputs(app: app, preparation: preparation, trackedFiles: [])
        let metadata = app.appendingPathComponent(".flutter-plugins-dependencies")
        #expect(prepared.metadata?.path == metadata.path)
        let unchanged = try FlutterAndroidExecution.tree(fixture.root, excluding: ["workspace/.flutter-plugins-dependencies"], bindIdentity: true)
        try FileManager.default.removeItem(at: metadata)
        #expect(throws: DomainError.self) { try prepared.check() }
        #expect(throws: DomainError.self) {
            try FlutterAndroidExecution.preparedInputs(app: app, preparation: preparation, trackedFiles: [])
        }
        #expect(!FileManager.default.fileExists(atPath: metadata.path))
        #expect(try FlutterAndroidExecution.tree(fixture.root, bindIdentity: true) == unchanged)
    }

    @Test("workspace member uses shared root lock/config and preserves sibling workspace inputs")
    func sharedWorkspaceInputs() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let (app, preparation) = try await fixture.preparation(member: true)
        let workspace = fixture.root.appendingPathComponent("workspace")
        let lockfile = workspace.appendingPathComponent("pubspec.lock")
        let config = workspace.appendingPathComponent(".dart_tool/package_config.json")
        let shared = workspace.appendingPathComponent("packages/shared/lib/shared.dart")
        let prepared = try FlutterAndroidExecution.preparedInputs(app: app, preparation: preparation,
            trackedFiles: [lockfile, shared])
        for file in [lockfile, config, shared] { #expect(prepared.files.keys.contains { $0.path == file.path }) }
        #expect(!FileManager.default.fileExists(atPath: app.appendingPathComponent("pubspec.lock").path))
        #expect(!FileManager.default.fileExists(atPath: app.appendingPathComponent(".dart_tool/package_config.json").path))
        try prepared.check()
        try Data("changed root lock preserved".utf8).write(to: lockfile)
        #expect(throws: DomainError.self) { try prepared.check() }
        #expect(try String(contentsOf: lockfile, encoding: .utf8) == "changed root lock preserved")
    }

    @Test("workspace member's newly introduced stray lock remains a migration failure")
    func strayMemberLock() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let (app, preparation) = try await fixture.preparation(member: true)
        let prepared = try FlutterAndroidExecution.preparedInputs(app: app, preparation: preparation, trackedFiles: [])
        try fixture.file("workspace/apps/client/pubspec.lock", "user lock retained")
        #expect(throws: DomainError.self) { try prepared.check() }
        #expect(throws: DomainError.self) {
            try FlutterAndroidExecution.preparedInputs(app: app, preparation: preparation, trackedFiles: [])
        }
        #expect(try String(contentsOf: app.appendingPathComponent("pubspec.lock"), encoding: .utf8) == "user lock retained")
    }

    @Test("prepared private TMP aliases bind the same physical app while custom aliases are rejected")
    func preparedPathAliases() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let (app, preparation) = try await fixture.preparation()
        let tmpAlias = URL(fileURLWithPath: app.path.replacingOccurrences(of: "/private/tmp/", with: "/tmp/"))
        let prepared = try FlutterAndroidExecution.preparedInputs(app: tmpAlias, preparation: preparation, trackedFiles: [])
        #expect(prepared.entrypoint.path == app.appendingPathComponent("lib/main.dart").path)
        #expect(symlink("workspace", fixture.root.appendingPathComponent("custom-alias").path) == 0)
        let custom = fixture.root.appendingPathComponent("custom-alias")
        #expect(throws: DomainError.self) {
            try FlutterAndroidExecution.preparedInputs(app: custom, preparation: preparation, trackedFiles: [])
        }
        #expect(throws: DomainError.self) { try FlutterAndroidExecution.makeRoot(in: custom) }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: custom.path) == "workspace")
    }

    @Test("a directory URL spelling cannot turn the whole private SDK root into a write exception")
    func wholeRootException() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let view = try fixture.directory("view")
        let samePath = URL(fileURLWithPath: view.path, isDirectory: false)
        #expect(throws: DomainError.self) {
            try FlutterAndroidExecution.parentPolicy(protected: [], privateRoot: view, writable: [samePath])
        }
    }

    @Test("parent policy inventory stays out of command descriptions and timeout diagnostics")
    func privateParentPolicy() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let inventory = "/private-source-inventory/customer-secret.swift"
        try fixture.file("parent.sb", "(version 1)(allow default)(deny file-write* (literal \"\(inventory)\"))")
        let original = ProcessCommand("/selected/android/gradlew", ["help", "--offline"],
            environment: ["JAVA_HOME": "/selected/jdk"], workingDirectory: fixture.root,
            timeout: .seconds(5), output: .streamed(to: fixture.root.appendingPathComponent("output.log")))
        let wrapped = try FlutterAndroidExecution.policyCommand(original, file: fixture.root.appendingPathComponent("parent.sb"))
        #expect(wrapped.executable == "/usr/bin/sandbox-exec")
        #expect(Array(wrapped.arguments.prefix(2)) == ["-f", fixture.root.appendingPathComponent("parent.sb").path])
        #expect(!wrapped.description.contains(inventory))
        #expect(!wrapped.description.contains("deny file-write"))
        let error = ProcessError.timedOut(command: wrapped.description, timeout: .seconds(5))
        #expect(!String(describing: error).contains(inventory))
        #expect(wrapped.environment == original.environment)
        #expect(wrapped.workingDirectory == original.workingDirectory)
        #expect(wrapped.timeout == original.timeout)
        #expect(wrapped.output == original.output)
    }

    @Test("workspace generated parent can be created while member package config remains absent")
    func workspaceGeneratedParent() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let app = try fixture.directory("app")
        let sdk = try fixture.directory("sdk")
        let absentConfig = app.appendingPathComponent(".dart_tool/package_config.json")
        let output = app.appendingPathComponent(".dart_tool/flutter_build")
        let profile = try FlutterAndroidExecution.childPolicy(protected: [absentConfig], sdk: sdk, writable: [output])
        let generated = try await fixture.run(profile: profile,
            script: "/bin/mkdir -p \"$1/app/.dart_tool/flutter_build\" && printf generated > \"$1/app/.dart_tool/flutter_build/artifact\"")
        #expect(generated.terminationStatus.isSuccess)
        let stray = try await fixture.run(profile: profile, script: "printf stray > \"$1/app/.dart_tool/package_config.json\"")
        #expect(!stray.terminationStatus.isSuccess)
        #expect(!FileManager.default.fileExists(atPath: absentConfig.path))
    }

    @Test("child sandbox allows selected output and cache lock while refusing source, artifact and ancestor mutation")
    func childSandbox() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = try fixture.directory("source")
        let sdk = try fixture.directory("view")
        let output = try fixture.directory("output")
        try fixture.file("source/lock", "source lock")
        try fixture.file("view/bin/cache/artifacts/engine", "engine")
        try fixture.file("view/bin/cache/lockfile", "old lock")
        let before = try FlutterAndroidExecution.tree(source, bindIdentity: true)
        let engine = try FlutterAndroidExecution.entry(sdk.appendingPathComponent("bin/cache/artifacts/engine"), bindIdentity: true)
        let profile = try FlutterAndroidExecution.childPolicy(protected: [source], sdk: sdk, writable: [output])
        for script in [
            "printf changed > \"$1/source/lock\"",
            "printf changed > \"$1/view/bin/cache/artifacts/engine\"",
            "/bin/mv \"$1/source\" \"$1/moved\"",
            "/bin/mv \"$1/view/bin\" \"$1/output/stolen\"",
            "/bin/ln \"$1/source/lock\" \"$1/output/hardlink\"",
        ] {
            let result = try await fixture.run(profile: profile, script: script)
            #expect(!result.terminationStatus.isSuccess)
        }
        let accepted = try await fixture.run(profile: profile,
            script: "printf output > \"$1/output/generated\" && printf locked > \"$1/view/bin/cache/lockfile\"")
        #expect(accepted.terminationStatus.isSuccess)
        #expect(try String(contentsOf: output.appendingPathComponent("generated"), encoding: .utf8) == "output")
        #expect(try FlutterAndroidExecution.tree(source, bindIdentity: true) == before)
        #expect(try FlutterAndroidExecution.entry(sdk.appendingPathComponent("bin/cache/artifacts/engine"), bindIdentity: true) == engine)
    }

    @Test("parent sandbox permits shadow Gradle project cache and protects source and adjacent private inputs")
    func parentSandbox() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = try fixture.directory("source")
        let view = try fixture.directory("view")
        let cache = try fixture.directory("view/gradle-cache")
        try fixture.directory("view/app/android")
        try fixture.directory("ordinary-cache")
        try fixture.file("source/file", "source")
        try fixture.file("view/tool", "tool")
        let before = try FlutterAndroidExecution.tree(source, bindIdentity: true)
        let profile = try FlutterAndroidExecution.parentPolicy(protected: [source], privateRoot: view, writable: [cache])
        for script in ["printf bad > \"$1/source/file\"", "printf bad > \"$1/view/tool\"",
                       "printf bad > \"$1/view/app/android/local.properties\"",
                       "/bin/mkdir -p \"$1/view/app/android/.gradle-other/8.14/fileHashes\"",
                       "/bin/mv \"$1\" \"$1-moved\""] {
            #expect(try await !fixture.run(profile: profile, script: script).terminationStatus.isSuccess)
        }
        let accepted = try await fixture.run(profile: profile,
            script: "/bin/mkdir -p \"$1/view/app/android/.gradle/8.14/fileHashes\" && printf project-cache > \"$1/view/app/android/.gradle/8.14/fileHashes/cache.bin\" && printf compiled > \"$1/view/gradle-cache/output\" && printf dependency > \"$1/ordinary-cache/dependency\"")
        #expect(accepted.terminationStatus.isSuccess, Comment(rawValue: accepted.combinedOutput))
        if accepted.terminationStatus.isSuccess {
            #expect(try String(contentsOf: view.appendingPathComponent("app/android/.gradle/8.14/fileHashes/cache.bin"), encoding: .utf8) == "project-cache")
        }
        #expect(try FlutterAndroidExecution.tree(source, bindIdentity: true) == before)
        #expect(try String(contentsOf: view.appendingPathComponent("tool"), encoding: .utf8) == "tool")
    }

    @Test("child network denial is observed against an open owned loopback listener")
    func childNetwork() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let sdk = try fixture.directory("sdk")
        let output = try fixture.directory("output")
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        #expect(descriptor >= 0)
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        #expect(bound == 0)
        #expect(listen(descriptor, 4) == 0)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let queried = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        #expect(queried == 0)
        let port = UInt16(bigEndian: address.sin_port)
        let runner = SystemProcessRunner(environment: ["PATH": "/usr/bin:/bin"], workingDirectory: fixture.root)
        let baseline = try await runner.run(ProcessCommand("/usr/bin/nc", ["-z", "-w", "1", "127.0.0.1", String(port)], timeout: .seconds(3)))
        #expect(baseline.terminationStatus.isSuccess)
        let profile = try FlutterAndroidExecution.childPolicy(protected: [], sdk: sdk, writable: [output])
        let rejected = try await runner.run(ProcessCommand("/usr/bin/sandbox-exec",
            ["-p", profile, "/usr/bin/nc", "-z", "-w", "1", "127.0.0.1", String(port)], timeout: .seconds(3)))
        #expect(!rejected.terminationStatus.isSuccess)
        let after = try await runner.run(ProcessCommand("/usr/bin/nc", ["-z", "-w", "1", "127.0.0.1", String(port)], timeout: .seconds(3)))
        #expect(after.terminationStatus.isSuccess)
        print("FlutterAndroidExecutionTests.childNetwork before=\(baseline.terminationStatus) rejected=\(rejected.terminationStatus) after=\(after.terminationStatus)")
    }

    private static let groovy = #"""
    pluginManagement {
        def flutterSdkPath = {
            def properties = new Properties()
            file("local.properties").withInputStream { properties.load(it) }
            def flutterSdkPath = properties.getProperty("flutter.sdk")
            assert flutterSdkPath != null, "flutter.sdk not set in local.properties"
            return flutterSdkPath
        }()
        includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")
        repositories { google(); mavenCentral(); gradlePluginPortal() }
    }
    plugins {
        id "dev.flutter.flutter-plugin-loader" version "1.0.0"
        id "com.android.application" version "8.12.1" apply false
        id "org.jetbrains.kotlin.android" version "2.2.0" apply false
    }
    include ":app"
    """#.replacingOccurrences(of: ";", with: "")

    private static let kotlin = #"""
    pluginManagement {
        val flutterSdkPath = run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }
        includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")
        repositories { google(); mavenCentral(); gradlePluginPortal() }
    }
    plugins {
        id("dev.flutter.flutter-plugin-loader") version "1.0.0"
        id("com.android.application") version "8.12.1" apply false
        id("org.jetbrains.kotlin.android") version "2.2.0" apply false
    }
    include(":app")
    """#.replacingOccurrences(of: ";", with: "")

    private struct Fixture: Sendable {
        let root: URL
        let identity: FlutterAndroidExecution.Identity
        init() throws {
            root = try FlutterAndroidExecution.makeRoot(in: URL(fileURLWithPath: "/private/tmp", isDirectory: true))
            identity = try FlutterAndroidExecution.Identity(root)
        }
        @discardableResult func directory(_ relative: String) throws -> URL {
            let path = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            return path
        }
        func file(_ relative: String, _ contents: String, mode: mode_t = 0o600) throws {
            let path = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FlutterAndroidExecution.write(Data(contents.utf8), to: path, mode: mode)
        }
        func run(profile: String, script: String) async throws -> ProcessResult {
            try await SystemProcessRunner(environment: ["PATH": "/usr/bin:/bin"], workingDirectory: root).run(
                ProcessCommand("/usr/bin/sandbox-exec", ["-p", profile, "/bin/sh", "-c", script, "fixture", root.path], timeout: .seconds(3)))
        }
        func preparation(member: Bool = false, reachablePlugin: Bool = false, metadataForPlugin: Bool = false) async throws -> (URL, FlutterPreparation) {
            let workspace = try directory("workspace")
            try directory("workspace/.git")
            try directory("home")
            let appRelative = member ? "workspace/apps/client" : "workspace"
            let app = root.appendingPathComponent(appRelative)
            let appName = member ? "client" : "example"
            let sdk = try directory("sdk")
            let version = #"{"frameworkVersion":"3.41.9","channel":"stable","dartSdkVersion":"3.11.5","frameworkRevision":"00b0c91f06209d9e4a41f71b7a512d6eb3b9c694"}"#
            for (relative, contents) in [
                ("bin/cache/flutter.version.json", version), ("bin/cache/dart-sdk/version", "3.11.5\n"),
                ("bin/cache/flutter_tools.snapshot", "fixture snapshot"), ("bin/flutter", "fixture wrapper; never execute"),
                ("packages/flutter/pubspec.yaml", "name: flutter\ndependencies: {}\n"),
                ("bin/cache/artifacts/engine/android-arm64/flutter.jar", "fixture engine marker"),
            ] { try file("sdk/" + relative, contents, mode: relative == "bin/flutter" ? 0o700 : 0o600) }
            try directory("sdk/bin/cache/dart-sdk/bin")
            try FlutterAndroidExecution.write(Data([0xcf, 0xfa, 0xed, 0xfe, 0x0c, 0, 0, 1]),
                to: sdk.appendingPathComponent("bin/cache/dart-sdk/bin/dart"), mode: 0o700)
            let manifest = "environment:\n  sdk: ^3.6.0\ndependencies:\n  flutter:\n    sdk: flutter\n"
            var appManifest = "name: \(appName)\n" + (member ? "resolution: workspace\n" : "") + manifest
            if member { appManifest += "  shared:\n    path: ../../packages/shared\n" }
            if reachablePlugin { appManifest += "  fixture_plugin:\n    path: ../plugin\n" }
            try file(appRelative + "/pubspec.yaml", appManifest)
            if member {
                try file("workspace/pubspec.yaml", "name: example\n" + manifest + "workspace:\n  - apps/client\n  - packages/shared\n")
                try file("workspace/packages/shared/pubspec.yaml", "name: shared\nresolution: workspace\nenvironment:\n  sdk: ^3.6.0\ndependencies: {}\n")
                try file("workspace/packages/shared/lib/shared.dart", "void shared() {}\n")
            }
            try file("workspace/pubspec.lock", "packages: {}\n")
            try file(appRelative + "/lib/main.dart", "void main() {}\n")
            try file(appRelative + "/android/settings.gradle", FlutterAndroidExecutionTests.groovy)
            try file(appRelative + "/android/gradle.properties", "org.gradle.jvmargs=-Xmx2G\n")
            try file(appRelative + "/android/local.properties", "flutter.sdk=\(sdk.path)\n")
            var packages: [(String, URL)] = [("example", workspace)]
            if member { packages += [("client", app), ("shared", root.appendingPathComponent("workspace/packages/shared"))] }
            var configured = packages + [("flutter", sdk.appendingPathComponent("packages/flutter"))]
            if reachablePlugin {
                try file("plugin/pubspec.yaml", "name: fixture_plugin\ndependencies: {}\nflutter:\n  plugin:\n    platforms:\n      android:\n        pluginClass: FixturePlugin\n")
                configured.append(("fixture_plugin", root.appendingPathComponent("plugin")))
                if metadataForPlugin {
                    let metadata = try JSONSerialization.data(withJSONObject: ["version": "3.41.9", "plugins": [
                        "android": [["name": "fixture_plugin", "path": root.appendingPathComponent("plugin").path,
                                     "native_build": true, "shared_darwin_source": false] as [String: Any]],
                        "ios": []
                    ]] as [String: Any])
                    try FlutterAndroidExecution.write(metadata, to: app.appendingPathComponent(".flutter-plugins-dependencies"))
                }
            }
            let config = try JSONSerialization.data(withJSONObject: ["configVersion": 2,
                "packages": configured.map { ["name": $0.0, "rootUri": $0.1.absoluteString] }])
            let graph = try JSONSerialization.data(withJSONObject: ["configVersion": 1, "roots": packages.map { $0.0 },
                "packages": configured.map { pair -> [String: Any] in
                    let name = pair.0
                    var dependencies = ["example", "client"].contains(name) ? ["flutter"] : []
                    if name == "client" { dependencies.append("shared") }
                    if name == appName && reachablePlugin { dependencies.append("fixture_plugin") }
                    return ["name": name, "dependencies": dependencies, "devDependencies": []]
                }])
            try directory("workspace/.dart_tool")
            try FlutterAndroidExecution.write(config, to: workspace.appendingPathComponent(".dart_tool/package_config.json"))
            try FlutterAndroidExecution.write(graph, to: workspace.appendingPathComponent(".dart_tool/package_graph.json"))
            let resolver = try JSONSerialization.data(withJSONObject: ["packages": packages.map { ["path": $0.1.path] }])
            let command = sdk.standardizedFileURL.resolvingSymlinksInPath().appendingPathComponent("bin/cache/dart-sdk/bin/dart").path + " pub --suppress-analytics workspace list --json"
            let runner = FakeProcessRunner(responses: [
                FlutterRelease.command.description: .ok(String(decoding: try FlutterFixture.releaseMetadata(), as: UTF8.self)),
                command: .ok(String(decoding: resolver, as: UTF8.self)),
            ])
            let preparation = try await FlutterPreparation.inspect(directory: app,
                environment: ["HOME": root.appendingPathComponent("home").path, "FLUTTER_ROOT": sdk.path],
                runner: runner, installationRoot: root.appendingPathComponent("managed"))
            return (app, preparation)
        }
        func remove() {
            // The fixture owns this exclusive root; no product SDK is ever read or removed.
            guard (try? FlutterAndroidExecution.Identity(root)) == identity else { return }
            try? FileManager.default.removeItem(at: root)
        }
    }

    private actor Gate {
        var continuation: CheckedContinuation<Void, Never>?
        var released = false
        func wait() async {
            if released { return }
            await withCheckedContinuation { continuation = $0 }
        }
        func release() { released = true; continuation?.resume(); continuation = nil }
    }
}

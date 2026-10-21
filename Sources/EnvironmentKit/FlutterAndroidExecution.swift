import Core
import CryptoKit
import Darwin
import Foundation

/// One invocation's private SDK and settings. This does not prepare missing artifacts.
final class FlutterAndroidExecution: @unchecked Sendable {
    static let revision = "00b0c91f06209d9e4a41f71b7a512d6eb3b9c694"
    let root: URL
    let sdk: URL
    let settings: URL
    let launcher: URL
    let initScript: URL
    private let originalSDK: URL
    private let android: URL
    private let entrypoint: URL
    private let identity: Identity
    private let originalTree: [String: Entry]
    private let immutableView: [String: Entry]
    private let protectedInputs: [URL: Entry]
    private let privateInputs: [URL: Entry]
    private let absentInputs: Set<URL>
    private let parentPolicy: URL
    private let unusedTree: [String: Entry]
    private let lock = NSLock()
    private var used = false

    private static let gradleCache = ["packages/flutter_tools/gradle/.gradle", "packages/flutter_tools/gradle/build"]
    private static let mutableView = gradleCache + ["bin/cache/lockfile"]
    private static let capability = [
        "kotlin/tasks/BaseFlutterTask.kt": "27dd5ea0f0938f3d1cfb54b992601b39cbf25ae8f20bfe2da771d2ebbb630c56",
        "kotlin/tasks/BaseFlutterTaskHelper.kt": "2436cca453b4a1ac7720b3a951f6bce8fc668e966d577d4b256c2d8a96ff43f7",
        "kotlin/FlutterPlugin.kt": "018df660f8ad233e1581015810fbe8421939e0cf7794e1153204be530ac66486",
        "kotlin/FlutterAppPluginLoaderPlugin.kt": "4cc53d34ca996bd9e672163fe51774a92f465aa8906792a4438a0fd9cc740748",
        "scripts/native_plugin_loader.gradle.kts": "e0aac9eefc8581ea6d28e6c1284f0b92e03727aaf0453ac4b8a2b8689a13e686",
    ]

    /// `trackedFiles` comes from the same resolved dependency workspace's trusted source inventory.
    static func prepare(app: URL, preparation: FlutterPreparation, trackedFiles: [URL],
                        temporaryDirectory: URL = FileManager.default.temporaryDirectory) throws -> FlutterAndroidExecution {
        try Task.checkCancellation()
        let app = try preparedPath(app)
        let prepared = try preparedInputs(app: app, preparation: preparation, trackedFiles: trackedFiles)
        let selected = prepared.sdk
        let entrypoint = prepared.entrypoint
        let source = try preparedPath(selected.root)
        let android = try canonical(app.appendingPathComponent("android"))
        guard selected.version == "3.41.9", selected.revision == revision,
              try FlutterSDK.read(source).fingerprint == selected.fingerprint else {
            throw failure("This Flutter SDK has no verified protected Android task launcher. Preserve it and inspect setup.")
        }
        for (relative, hash) in capability {
            guard try entry(source.appendingPathComponent("packages/flutter_tools/gradle/src/main/" + relative)).digest == hash else {
                throw failure("The selected Flutter Gradle task or loader differs from the verified SDK capability.")
            }
        }
        let candidates = ["settings.gradle", "settings.gradle.kts"].map { android.appendingPathComponent($0) }
        let present = candidates.filter { exists($0) }
        guard present.count == 1, let originalSettings = present.first else {
            throw failure("One existing canonical Flutter Android settings file is required.")
        }
        let settingsBytes = try Data(contentsOf: originalSettings)
        try validateSettings(settingsBytes)
        for relative in ["buildSrc", "gradle/libs.versions.toml", "gradle/verification-metadata.xml"] {
            guard !exists(android.appendingPathComponent(relative)) else {
                throw failure("Additional Android settings inputs need a separately verified execution route.")
            }
        }
        guard !exists(app.appendingPathComponent(".flutter-plugins")) else {
            throw failure("Legacy Flutter plugin metadata is outside this protected route.")
        }
        let wrapper = android.appendingPathComponent("gradle/wrapper/gradle-wrapper.properties")
        let wrapperBytes = try String(contentsOf: wrapper, encoding: .utf8)
        try validateWrapper(wrapperBytes)
        guard inside(app, entrypoint), entrypoint.pathExtension == "dart", !inside(source, app), !inside(app, source) else {
            throw failure("The selected Flutter app, entrypoint and SDK must identify separate canonical inputs.")
        }
        let plugins = try prepared.metadata.map { try pluginDirectories(Data(contentsOf: $0)) } ?? [:]
        let required = [originalSettings, wrapper, android.appendingPathComponent("gradle.properties"),
                        android.appendingPathComponent("local.properties")]
        var inputs = prepared.files
        for path in required {
            let path = try canonical(path)
            guard inside(app, path), try entry(path).kind == .file else {
                throw failure("A selected Flutter source input is not a regular file in this app.")
            }
            inputs[path] = try entry(path, bindIdentity: true)
        }
        var absent = prepared.absent
        inputs[source] = try entry(source, bindIdentity: true)
        let before = try tree(source, bindIdentity: true)
        for (relative, hash) in capability {
            guard before["packages/flutter_tools/gradle/src/main/" + relative]?.digest == hash else {
                throw failure("The Flutter Gradle capability changed before its SDK snapshot was identified.")
            }
        }
        let sourcePackages = try canonical(source.appendingPathComponent("packages/flutter_tools/.dart_tool/package_config.json"))
        guard try entry(sourcePackages).kind == .file else {
            throw failure("The selected SDK tools package configuration is missing; it will not be generated.")
        }
        let root = try makeRoot(in: temporaryDirectory)
        // An interrupted preparation retains its exclusive directory for private diagnosis.
        try write(Data("{\"schema\":1,\"state\":\"preparing\",\"sdkRevision\":\"\(revision)\"}\n".utf8), to: root.appendingPathComponent("receipt.json"))
        struct Provenance: Encodable {
            let selectedRoot: String
            let revision: String
            let preparationFingerprint: String
            let inputs: [String: Entry]
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try write(encoder.encode(Provenance(selectedRoot: source.path, revision: selected.revision,
            preparationFingerprint: selected.fingerprint, inputs: before)), to: root.appendingPathComponent("sdk-manifest.json"))
        let copy = root.appendingPathComponent("sdk")
        try copyTree(source, to: copy, snapshot: before, excluding: gradleCache)
        guard try FlutterSDK.read(source).fingerprint == selected.fingerprint,
              try tree(source, bindIdentity: true) == before,
              try tree(copy, excluding: gradleCache) == filtered(before, excluding: gradleCache).mapValues(\.unbound) else {
            throw failure("Flutter SDK inputs changed while making the private execution copy. The partial copy was retained.")
        }
        let settings = try makeShadow(app: app, settingsFile: originalSettings, ownedRoot: root)
        let shadowAndroid = settings.deletingLastPathComponent()
        let shadow = shadowAndroid.deletingLastPathComponent()
        let shadowMetadata = shadow.appendingPathComponent(".flutter-plugins-dependencies")
        if prepared.metadata == nil { absent.insert(shadowMetadata) }
        for child in ["home", "tmp"] { try directory(root.appendingPathComponent(child)) }
        let outputs = [app.appendingPathComponent("build"), app.appendingPathComponent(".dart_tool/flutter_build")]
        for output in outputs {
            _ = try canonical(output, mayBeAbsent: true)
            guard !inputs.keys.contains(where: { inside(output, $0) || inside($0, output) }) else {
                throw failure("A Flutter generated output overlaps a protected source input.")
            }
        }
        let policy = root.appendingPathComponent("child.sb")
        let launcher = root.appendingPathComponent("flutter-child")
        let initScript = root.appendingPathComponent("binding.gradle")
        let childPolicy = try Self.childPolicy(protected: Array(inputs.keys) + Array(absent), sdk: copy,
            writable: outputs + [root.appendingPathComponent("home"), root.appendingPathComponent("tmp")])
        try write(Data(childPolicy.utf8), to: policy)
        let executable = copy.appendingPathComponent("bin/cache/dart-sdk/bin/dart")
        let packages = copy.appendingPathComponent("packages/flutter_tools/.dart_tool/package_config.json")
        let script = """
        #!/bin/sh
        set -eu
        unset FLUTTER_ALREADY_LOCKED DART_VM_OPTIONS FLUTTER_TOOL_ARGS
        export FLUTTER_ROOT=\(shell(copy.path))
        export HOME=\(shell(root.appendingPathComponent("home").path))
        export CFFIXED_USER_HOME="$HOME"
        export TMPDIR=\(shell(root.appendingPathComponent("tmp").path + "/"))
        exec /usr/bin/sandbox-exec -f \(shell(policy.path)) \(shell(executable.path)) --disable-dart-dev \(shell("--packages=" + packages.path)) \(shell(copy.appendingPathComponent("bin/cache/flutter_tools.snapshot").path)) --suppress-analytics "$@"
        """
        try write(Data((script + "\n").utf8), to: launcher, mode: 0o700)
        try write(Data(binding(settings: settings, android: android, app: app, sdk: copy,
                               launcher: launcher, target: entrypoint, plugins: plugins).utf8), to: initScript)
        let parentText = try Self.parentPolicy(protected: Array(inputs.keys) + Array(absent), privateRoot: root,
            writable: gradleCache.map { copy.appendingPathComponent($0) } + [
                shadowAndroid.appendingPathComponent("local.properties"), copy.appendingPathComponent("bin/cache/lockfile"),
                root.appendingPathComponent("home"), root.appendingPathComponent("tmp")])
        let parentPolicy = root.appendingPathComponent("parent.sb")
        try write(Data(parentText.utf8), to: parentPolicy)
        var privateFiles = [copy, settings, shadowAndroid.appendingPathComponent("gradle.properties"),
                            policy, parentPolicy, launcher, initScript]
        if prepared.metadata != nil { privateFiles.append(shadowMetadata) }
        let privateInputs = try Dictionary(uniqueKeysWithValues: privateFiles.map { ($0, try entry($0, bindIdentity: true)) })
        guard try tree(source, bindIdentity: true) == before,
              try inputs.allSatisfy({ try entry($0.key, bindIdentity: true) == $0.value }),
              absent.allSatisfy({ !exists($0) }) else {
            throw failure("Flutter inputs changed before the protected execution became ready.")
        }
        try write(Data("{\"schema\":1,\"state\":\"ready\",\"cleanup\":\"retain-after-use\"}\n".utf8),
                  to: root.appendingPathComponent("ready.json"))
        return FlutterAndroidExecution(root: root, sdk: copy, settings: settings, launcher: launcher,
            initScript: initScript, originalSDK: source, android: android, entrypoint: entrypoint,
            identity: try Identity(root), originalTree: before,
            immutableView: try tree(copy, excluding: mutableView, bindIdentity: true), protectedInputs: inputs,
            privateInputs: privateInputs, absentInputs: absent, parentPolicy: parentPolicy, unusedTree: try tree(root, bindIdentity: true))
    }

    private init(root: URL, sdk: URL, settings: URL, launcher: URL, initScript: URL, originalSDK: URL,
                 android: URL, entrypoint: URL, identity: Identity, originalTree: [String: Entry],
                 immutableView: [String: Entry], protectedInputs: [URL: Entry], privateInputs: [URL: Entry],
                 absentInputs: Set<URL>, parentPolicy: URL,
                 unusedTree: [String: Entry]) {
        self.root = root; self.sdk = sdk; self.settings = settings; self.launcher = launcher
        self.initScript = initScript; self.originalSDK = originalSDK; self.android = android
        self.entrypoint = entrypoint; self.identity = identity; self.originalTree = originalTree
        self.immutableView = immutableView; self.protectedInputs = protectedInputs
        self.privateInputs = privateInputs; self.parentPolicy = parentPolicy
        self.absentInputs = absentInputs
        self.unusedTree = unusedTree
    }

    func runner(base: any ProcessRunner) -> any ProcessRunner { ProtectedRunner(base: base, execution: self) }

    func check() throws {
        guard try Identity(root) == identity, try Self.tree(originalSDK, bindIdentity: true) == originalTree,
              try Self.tree(sdk, excluding: Self.mutableView, bindIdentity: true) == immutableView,
              try protectedInputs.allSatisfy({ try Self.entry($0.key, bindIdentity: true) == $0.value }),
              try privateInputs.allSatisfy({ try Self.entry($0.key, bindIdentity: true) == $0.value }),
              absentInputs.allSatisfy({ !Self.exists($0) }) else {
            throw Self.failure("Protected Flutter inputs or the private execution directory changed. Preserve them and inspect setup again.")
        }
    }

    private func command(_ original: ProcessCommand) throws -> ProcessCommand {
        try check()
        guard original.executable == "./gradlew" else { return original }
        guard let directory = original.workingDirectory, try Self.preparedPath(directory).path == android.path,
              !original.arguments.contains(where: {
                  ["-c", "--settings-file", "-p", "--project-dir", "--configuration-cache"].contains($0)
                    || $0.hasPrefix("--settings-file=") || $0.hasPrefix("--project-dir=")
                    || $0.hasPrefix("-Pflutter.sdk") || $0.hasPrefix("-Ptarget")
              }) else { throw Self.failure("A second settings, project, SDK or Flutter target would bypass the selected execution boundary.") }
        var result = original
        result.executable = android.appendingPathComponent("gradlew").path
        result.arguments = original.arguments
            + ["--no-daemon", "--no-configuration-cache", "-Dorg.gradle.unsafe.isolated-projects=false", "-c", settings.path,
               "-I", initScript.path, "-Pflutter.sdk=\(sdk.path)", "-Ptarget=\(entrypoint.path)"]
        result.environment["FLUTTER_ROOT"] = sdk.path
        return try Self.policyCommand(result, file: parentPolicy)
    }

    /// No ProcessRunner API proves that every Gradle descendant has terminated.
    /// Used views remain private; only a never-executed view can be discarded here.
    func discardUnused() throws {
        try lock.withLock {
            guard !used, try Identity(root) == identity, try Self.tree(root, bindIdentity: true) == unusedTree else {
                throw Self.failure("This execution view has been used or changed. Retain its receipt until child termination is independently established.")
            }
            try FileManager.default.removeItem(at: root)
        }
    }

    private struct ProtectedRunner: ProcessRunner {
        let base: any ProcessRunner
        let execution: FlutterAndroidExecution
        func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
            let protected = try execution.command(command)
            execution.lock.withLock { execution.used = true }
            // The base runner retains timeout, cancellation, streaming and nonzero status semantics.
            let result = try await base.run(protected, onLine: onLine)
            try execution.check()
            return result
        }
        func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
            throw FlutterAndroidExecution.failure("Flutter Android protected Gradle children must finish inside their owning operation.")
        }
    }

    struct PreparedInputs: Sendable {
        let sdk: FlutterSDK
        let entrypoint: URL
        let metadata: URL?
        let files: [URL: Entry]
        let absent: Set<URL>

        func check() throws {
            guard try files.allSatisfy({ try FlutterAndroidExecution.entry($0.key, bindIdentity: true) == $0.value }),
                  absent.allSatisfy({ !FlutterAndroidExecution.exists($0) }) else {
                throw FlutterAndroidExecution.failure("Prepared Flutter workspace inputs or verified absent metadata changed.")
            }
        }
    }

    /// Reuse Pub's resolved workspace and validate current reachable-plugin metadata.
    static func preparedInputs(app: URL, preparation: FlutterPreparation, trackedFiles: [URL]) throws -> PreparedInputs {
        let app = try preparedPath(app)
        guard let sdk = preparation.sdk, let workspace = preparation.workspace, let selectedEntrypoint = preparation.entrypoint,
              workspace.migrationFiles.isEmpty,
              preparation.activeEnvironment["FLUTTER_ROOT"] == sdk.root.path else {
            throw failure("Flutter Android needs the same prepared SDK, selected app and resolved dependency workspace.")
        }
        let workspaceRoot = try preparedPath(workspace.directory)
        let packages = try workspace.packages.map(preparedPath)
        let entrypoint = try preparedPath(selectedEntrypoint)
        guard packages.contains(where: { $0.path == app.path }) else { throw failure("The resolved workspace does not contain the selected Flutter app.") }
        for id in ["flutter.declarations", "flutter.sdk", "dependencies.flutter", "android.flutter.generated"] {
            guard let step = preparation.checks.first(where: { $0.id == id }),
                  step.kind == "reuse" || (id == "dependencies.flutter" && step.kind == "align") else {
                throw failure("Flutter Android preparation has unresolved selected-app inputs.")
            }
        }
        guard !preparation.checks.contains(where: { $0.platform != .ios && !["reuse", "align"].contains($0.kind) }),
              inside(workspaceRoot, app), inside(app, entrypoint), entrypoint.pathExtension == "dart" else {
            throw failure("The selected Flutter app or dependency workspace is no longer prepared.")
        }
        let metadata = app.appendingPathComponent(".flutter-plugins-dependencies")
        let hasMetadata = exists(metadata)
        var required = trackedFiles + [entrypoint, workspaceRoot.appendingPathComponent("pubspec.lock"),
            workspaceRoot.appendingPathComponent(".dart_tool/package_config.json"),
            workspaceRoot.appendingPathComponent(".dart_tool/package_graph.json"),
            app.appendingPathComponent("android/local.properties")]
        if hasMetadata { required.append(metadata) }
        var absent: Set<URL> = hasMetadata ? [] : [metadata]
        for package in packages {
            guard inside(workspaceRoot, package) else { throw failure("A prepared Flutter package escaped its resolved workspace.") }
            required.append(package.appendingPathComponent("pubspec.yaml"))
            let overrides = package.appendingPathComponent("pubspec_overrides.yaml")
            if exists(overrides) { required.append(overrides) } else { absent.insert(overrides) }
            // Keep the existing resolver's stray member/ancestor lock migration boundary.
            var ancestor = package
            while ancestor.path != workspaceRoot.path {
                for relative in ["pubspec.lock", ".dart_tool/package_config.json"] {
                    let stray = ancestor.appendingPathComponent(relative)
                    guard !exists(stray) else { throw failure("A workspace member or ancestor has a stray lock/config. Preserve it and inspect setup.") }
                    absent.insert(stray)
                }
                ancestor.deleteLastPathComponent()
            }
        }
        var files: [URL: Entry] = [:]
        for path in Set(required) {
            let path = try preparedPath(path)
            let value = try entry(path, bindIdentity: true)
            guard inside(workspaceRoot, path), value.kind == .file else {
                throw failure("A protected Flutter input is not a regular file in the resolved dependency workspace.")
            }
            files[path] = value
        }
        for path in absent { _ = try canonical(path, mayBeAbsent: true) }
        let currentProject: FlutterProject
        do {
            currentProject = try FlutterProject(directory: app, entrypoint: String(entrypoint.path.dropFirst(app.path.count + 1)))
        } catch {
            throw failure("The selected Flutter app declarations cannot be confirmed from current inputs.")
        }
        var currentPreparation = preparation
        guard currentPreparation.pluginMetadataIssue(project: currentProject, sdk: sdk, platform: .android) == nil else {
            throw failure("Flutter Android plugin metadata does not match the current resolved package graph and manifests.")
        }
        let prepared = PreparedInputs(sdk: sdk, entrypoint: try canonical(entrypoint), metadata: hasMetadata ? metadata : nil,
                                      files: files, absent: absent)
        try prepared.check()
        return prepared
    }

    static func policyCommand(_ original: ProcessCommand, file: URL) throws -> ProcessCommand {
        _ = try canonical(file)
        guard try entry(file).mode == 0o600 else { throw failure("A Flutter parent policy is not a private immutable input.") }
        var result = original
        result.executable = "/usr/bin/sandbox-exec"
        result.arguments = ["-f", file.path, original.executable] + original.arguments
        return result
    }

    private static func preparedPath(_ path: URL) throws -> URL {
        // Consume the already-selected resolver path; Foundation may shorten /private aliases.
        guard path.isFileURL, path.query == nil, path.fragment == nil, let physical = realpath(path.path, nil) else {
            throw failure("An existing prepared Flutter input cannot be bound to its physical path.")
        }
        defer { free(physical) }
        var expected = path.path
        for alias in ["/tmp", "/var", "/etc"] where expected == alias || expected.hasPrefix(alias + "/") {
            expected = "/private" + expected
            break
        }
        guard String(cString: physical) == expected else {
            throw failure("A prepared Flutter path uses a non-system symbolic alias. Preserve it and inspect the selected physical resource.")
        }
        return try canonical(URL(fileURLWithPath: expected, isDirectory: path.hasDirectoryPath))
    }

    enum Kind: String, Codable, Sendable { case file, directory, link }
    struct Entry: Equatable, Codable, Sendable {
        let kind: Kind
        let mode: UInt16
        let size: Int64
        let digest: String
        let target: String?
        var nodeIdentity: String? = nil
        var unbound: Self { var value = self; value.nodeIdentity = nil; return value }
    }
    struct Identity: Equatable, Sendable {
        let device: Int32
        let inode: UInt64
        let uid: UInt32
        init(_ path: URL) throws {
            var info = stat()
            guard lstat(path.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
                  info.st_uid == getuid(), info.st_mode & 0o777 == 0o700,
                  try canonical(path) == path else { throw failure("The private Flutter execution root no longer has its original identity.") }
            device = info.st_dev; inode = info.st_ino; uid = info.st_uid
        }
    }

    static func makeRoot(in parent: URL) throws -> URL {
        let parent = try preparedPath(parent)
        var pattern = Array(parent.appendingPathComponent("runstir-flutter-android-XXXXXX").path.utf8CString)
        guard let path = mkdtemp(&pattern) else { throw failure("An exclusive private Flutter execution directory could not be created.") }
        let result = URL(fileURLWithPath: String(cString: path), isDirectory: true)
        _ = try Identity(result)
        return result
    }

    static func tree(_ root: URL, excluding: [String] = [], bindIdentity: Bool = false) throws -> [String: Entry] {
        _ = try canonical(root)
        var result: [String: Entry] = [:]
        func visit(_ directory: URL) throws {
            for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).sorted(by: { $0.path < $1.path }) {
                try Task.checkCancellation()
                let relative = String(file.path.dropFirst(root.path.count + 1))
                if excluding.contains(where: { relative == $0 || relative.hasPrefix($0 + "/") }) { continue }
                let value = try entry(file, bindIdentity: bindIdentity)
                if value.kind == .link {
                    guard let target = value.target, !target.hasPrefix("/"),
                          let physical = realpath(file.deletingLastPathComponent().appendingPathComponent(target).path, nil) else {
                        throw failure("The selected SDK contains an external, absolute or unresolved symbolic link.")
                    }
                    defer { free(physical) }
                    guard inside(root, URL(fileURLWithPath: String(cString: physical))) else {
                        throw failure("The selected SDK contains a symbolic link outside its execution copy.")
                    }
                }
                guard relative != ".git" || value.kind == .directory else {
                    throw failure("The selected SDK uses an external Git layout.")
                }
                result[relative] = value
                if value.kind == .directory { try visit(file) }
            }
        }
        try visit(root)
        return result
    }

    static func copyTree(_ source: URL, to destination: URL, snapshot: [String: Entry], excluding: [String] = []) throws {
        try directory(destination)
        let expected = filtered(snapshot, excluding: excluding)
        for (relative, value) in expected.sorted(by: { $0.key < $1.key }) where value.kind == .directory {
            try Task.checkCancellation()
            try directory(destination.appendingPathComponent(relative))
        }
        for (relative, value) in expected.sorted(by: { $0.key < $1.key }) where value.kind == .file {
            try Task.checkCancellation()
            let input = source.appendingPathComponent(relative)
            let output = destination.appendingPathComponent(relative)
            guard try entry(input, bindIdentity: value.nodeIdentity != nil) == value else { throw failure("An SDK file changed before it could be copied.") }
            let descriptor = open(input.path, O_RDONLY | O_NOFOLLOW)
            guard descriptor >= 0 else { throw failure("An SDK file could not be opened without following links.") }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            let destinationFD = open(output.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard destinationFD >= 0 else { throw failure("An SDK copy destination already exists or cannot be created exclusively.") }
            let destinationHandle = FileHandle(fileDescriptor: destinationFD, closeOnDealloc: true)
            var digest = SHA256()
            while let data = try handle.read(upToCount: 4 * 1024 * 1024), !data.isEmpty {
                try Task.checkCancellation()
                digest.update(data: data)
                try destinationHandle.write(contentsOf: data)
            }
            guard fchmod(destinationFD, mode_t(value.mode)) == 0 else { throw failure("Private SDK file permissions could not be retained.") }
            try destinationHandle.close()
            try handle.close()
            guard digest.finalize().map({ String(format: "%02x", $0) }).joined() == value.digest,
                  try entry(input, bindIdentity: value.nodeIdentity != nil) == value else { throw failure("An SDK file changed during its private copy.") }
        }
        for (relative, value) in expected.sorted(by: { $0.key < $1.key }) where value.kind == .link {
            guard let target = value.target, try entry(source.appendingPathComponent(relative), bindIdentity: value.nodeIdentity != nil) == value else {
                throw failure("An SDK symbolic link changed during its private copy.")
            }
            guard symlink(target, destination.appendingPathComponent(relative).path) == 0 else {
                throw failure("An SDK link destination already exists or cannot be created.")
            }
        }
        // Directory permissions are compared as input data, not silently widened.
        for (relative, value) in expected where value.kind == .directory {
            guard chmod(destination.appendingPathComponent(relative).path, mode_t(value.mode)) == 0 else {
                throw failure("Private SDK directory permissions could not be retained.")
            }
        }
    }

    static func makeShadow(app: URL, settingsFile: URL, ownedRoot: URL) throws -> URL {
        _ = try Identity(ownedRoot)
        let app = try preparedPath(app)
        let settingsFile = try preparedPath(settingsFile)
        guard settingsFile.deletingLastPathComponent().path == app.appendingPathComponent("android").path,
              ["settings.gradle", "settings.gradle.kts"].contains(settingsFile.lastPathComponent) else {
            throw failure("Shadow settings do not belong to the selected Flutter Android host.")
        }
        let shadow = ownedRoot.appendingPathComponent("app")
        try directory(shadow)
        let android = shadow.appendingPathComponent("android")
        try directory(android)
        let settings = android.appendingPathComponent(settingsFile.lastPathComponent)
        var files = [
            (settingsFile, settings),
            (app.appendingPathComponent("android/gradle.properties"), android.appendingPathComponent("gradle.properties")),
            (app.appendingPathComponent("android/local.properties"), android.appendingPathComponent("local.properties")),
        ]
        let metadata = app.appendingPathComponent(".flutter-plugins-dependencies")
        if exists(metadata) { files.append((metadata, shadow.appendingPathComponent(".flutter-plugins-dependencies"))) }
        for (source, destination) in files {
            _ = try canonical(source)
            let original = try entry(source, bindIdentity: true)
            guard original.kind == .file else { throw failure("A prepared Flutter settings input is not a regular file.") }
            let bytes = try Data(contentsOf: source)
            guard try entry(source, bindIdentity: true) == original else { throw failure("A Flutter settings input changed during its private copy.") }
            try write(bytes, to: destination)
        }
        return settings
    }

    static func entry(_ path: URL, bindIdentity: Bool = false) throws -> Entry {
        var info = stat()
        guard lstat(path.path, &info) == 0, info.st_mode & 0o7000 == 0 else {
            throw failure("A Flutter input is missing or has unsupported special permissions.")
        }
        let mode = UInt16(info.st_mode & 0o777)
        let identity = bindIdentity ? "\(info.st_dev):\(info.st_ino):\(info.st_uid)" : nil
        switch info.st_mode & S_IFMT {
        case S_IFREG:
            guard info.st_nlink == 1 else { throw failure("A Flutter input shares a hard link and cannot be isolated safely.") }
            let descriptor = open(path.path, O_RDONLY | O_NOFOLLOW)
            guard descriptor >= 0 else { throw failure("A Flutter input cannot be read without following links.") }
            defer { close(descriptor) }
            var opened = stat()
            guard fstat(descriptor, &opened) == 0, opened.st_dev == info.st_dev, opened.st_ino == info.st_ino else {
                throw failure("A Flutter input changed identity while being read.")
            }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
            var digest = SHA256()
            while let data = try handle.read(upToCount: 4 * 1024 * 1024), !data.isEmpty {
                try Task.checkCancellation(); digest.update(data: data)
            }
            var after = stat()
            guard fstat(descriptor, &after) == 0, after.st_size == info.st_size,
                  after.st_mtimespec.tv_sec == info.st_mtimespec.tv_sec,
                  after.st_mtimespec.tv_nsec == info.st_mtimespec.tv_nsec,
                  after.st_ctimespec.tv_sec == info.st_ctimespec.tv_sec,
                  after.st_ctimespec.tv_nsec == info.st_ctimespec.tv_nsec else {
                throw failure("A Flutter input changed while its content was being identified.")
            }
            return Entry(kind: .file, mode: mode, size: info.st_size, digest: digest.finalize().map { String(format: "%02x", $0) }.joined(), target: nil, nodeIdentity: identity)
        case S_IFDIR: return Entry(kind: .directory, mode: mode, size: 0, digest: "", target: nil, nodeIdentity: identity)
        case S_IFLNK:
            let target = try FileManager.default.destinationOfSymbolicLink(atPath: path.path)
            return Entry(kind: .link, mode: mode, size: Int64(target.utf8.count), digest: hex(Data(target.utf8)), target: target, nodeIdentity: identity)
        default: throw failure("A Flutter input is not a regular file, directory or supported internal link.")
        }
    }

    static func childPolicy(protected: [URL], sdk: URL, writable: [URL]) throws -> String {
        let sdk = try canonical(sdk)
        let writable = try writable.map { try canonical($0, mayBeAbsent: true) }
        guard !writable.contains(where: { inside(sdk, $0) || inside($0, sdk) }) else {
            throw failure("A Flutter child output overlaps immutable SDK inputs.")
        }
        var newParents = Set<String>()
        for path in writable {
            var parent = path.deletingLastPathComponent()
            while !exists(parent), parent.path != "/" {
                newParents.insert(parent.path)
                parent.deleteLastPathComponent()
            }
        }
        let permits = writable.map { "(subpath \(seatbelt($0.path)))" }
            + newParents.sorted().map { "(literal \(seatbelt($0)))" }
            + ["(literal \(seatbelt(sdk.appendingPathComponent("bin/cache/lockfile").path)))", "(literal \"/dev/null\")"]
        return "(version 1)(allow default)(deny network*)(deny file-write* (require-not (require-any \(permits.joined()))))"
            + (try protection(protected))
            + ancestorProtection(writable)
    }

    static func parentPolicy(protected: [URL], privateRoot: URL, writable: [URL]) throws -> String {
        let root = try canonical(privateRoot)
        let projectCache = root.appendingPathComponent("app/android/.gradle")
        let exceptions = try (writable + [projectCache]).map { path -> String in
            let path = try canonical(path, mayBeAbsent: true)
            guard inside(root, path), root.path != path.path else { throw failure("A private SDK write exception escapes its exclusive root.") }
            return "(subpath \(seatbelt(path.path)))"
        }
        let rootFilter = "(subpath \(seatbelt(root.path)))"
        let filter = exceptions.isEmpty ? rootFilter
            : "(require-all \(rootFilter) (require-not (require-any \(exceptions.joined()))))"
        return "(version 1)(allow default)" + (try protection(protected))
            + "(deny file-write* \(filter))"
            + ancestorProtection([root])
    }

    private static func protection(_ paths: [URL]) throws -> String {
        let paths = try paths.map { try canonical($0, mayBeAbsent: true) }
        return paths.map { "(deny file-write* (subpath \(seatbelt($0.path))))" }.joined() + ancestorProtection(paths)
    }

    private static func ancestorProtection(_ paths: [URL]) -> String {
        var ancestors = Set<String>()
        for path in paths {
            var current = path.deletingLastPathComponent()
            while current.path != "/" {
                if exists(current) { ancestors.insert(current.path) }
                current.deleteLastPathComponent()
            }
        }
        return ancestors.sorted().map { "(deny file-write* (literal \(seatbelt($0))))" }.joined()
    }

    /// Three stock template shapes; plugin versions and an optional root name remain project inputs.
    static func validateSettings(_ bytes: Data) throws {
        guard let source = String(data: bytes, encoding: .utf8) else { throw failure("Flutter settings are not UTF-8.") }
        let text = source.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        let token = try NSRegularExpression(pattern: #"\"[^\"\\]*\"|'[^'\\]*'|\s+|."#)
        let range = NSRange(text.startIndex..., in: text)
        var normalized = token.matches(in: text, range: range).compactMap { match -> String? in
            let value = (text as NSString).substring(with: match.range)
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
        }.joined()
        normalized = normalized.replacingOccurrences(of: #"(?:rootProject\.name=)(?:\"[A-Za-z0-9 _.-]+\"|'[A-Za-z0-9 _.-]+');?"#,
            with: "", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"(id(?:\(\"(?:com.android.application|org.jetbrains.kotlin.android)\"\)|\"(?:com.android.application|org.jetbrains.kotlin.android)\")version)\"[0-9][A-Za-z0-9.+_-]*\""#,
            with: "$1\"VERSION\"", options: .regularExpression)
        let groovyStart = #"pluginManagement{defflutterSdkPath={defproperties=newProperties()file("local.properties").withInputStream{properties.load(it)}defflutterSdkPath=properties.getProperty("flutter.sdk")assertflutterSdkPath!=null,"flutter.sdk not set in local.properties"returnflutterSdkPath}"#
        let repositories = "repositories{google()mavenCentral()gradlePluginPortal()}"
        let appPlugin = #"id"com.android.application"version"VERSION"applyfalse"#
        let kotlinPlugin = #"id"org.jetbrains.kotlin.android"version"VERSION"applyfalse"#
        let current = groovyStart + #"()includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")"# + repositories + #"}plugins{id"dev.flutter.flutter-plugin-loader"version"1.0.0""# + appPlugin
        let legacy = groovyStart + #"settings.ext.flutterSdkPath=flutterSdkPath()includeBuild("${settings.ext.flutterSdkPath}/packages/flutter_tools/gradle")"# + repositories + #"plugins{id"dev.flutter.flutter-gradle-plugin"version"1.0.0"applyfalse}}plugins{id"dev.flutter.flutter-plugin-loader"version"1.0.0""# + appPlugin
        let kotlin = #"pluginManagement{valflutterSdkPath=run{valproperties=java.util.Properties()file("local.properties").inputStream().use{properties.load(it)}valflutterSdkPath=properties.getProperty("flutter.sdk")require(flutterSdkPath!=null){"flutter.sdk not set in local.properties"}flutterSdkPath}includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")"# + repositories + #"}plugins{id("dev.flutter.flutter-plugin-loader")version"1.0.0"id("com.android.application")version"VERSION"applyfalseid("org.jetbrains.kotlin.android")version"VERSION"applyfalse}include(":app")"#
        guard [current + #"}include":app""#, current + kotlinPlugin + #"}include":app""#,
               legacy + #"}include":app""#, legacy + kotlinPlugin + #"}include":app""#, kotlin].contains(normalized) else {
            throw failure("Custom Flutter settings logic or additional settings inputs have no verified private execution route.")
        }
    }

    static func validateWrapper(_ source: String) throws {
        var values: [String: String] = [:]
        for line in source.split(whereSeparator: \.isNewline) {
            let line = line.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("!") { continue }
            // Escaped keys and continued values have Java Properties semantics outside this stock wrapper route.
            guard let separator = line.firstIndex(of: "="), !line.hasSuffix("\\") else {
                throw failure("Custom Gradle wrapper properties need separate inspection before protected execution.")
            }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            guard key.range(of: #"^[A-Za-z][A-Za-z0-9.]*$"#, options: .regularExpression) != nil,
                  values[key] == nil else { throw failure("Gradle wrapper property keys are escaped or duplicated.") }
            values[key] = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
        }
        guard let url = values["distributionUrl"],
              url.range(of: #"^[^\r\n]*[/]gradle-8\.[0-9]+(?:\.[0-9]+)?-(?:all|bin)\.zip$"#, options: .regularExpression) != nil else {
            throw failure("Protected Flutter Android execution requires the prepared Gradle 8 wrapper; preparation failures are not bypassed.")
        }
    }

    private static func pluginDirectories(_ data: Data) throws -> [String: String] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], json["version"] as? String == "3.41.9",
              let platforms = json["plugins"] as? [String: Any], let plugins = platforms["android"] as? [[String: Any]] else {
            throw failure("Prepared Flutter Android plugin metadata is missing or incompatible.")
        }
        var paths: [String: String] = [:]
        for plugin in plugins where plugin["native_build"] as? Bool != false {
            guard let name = plugin["name"] as? String, name.range(of: #"^[a-zA-Z0-9_]+$"#, options: .regularExpression) != nil,
                  let path = plugin["path"] as? String, paths[name] == nil else {
                throw failure("Flutter plugin descriptors are ambiguous.")
            }
            paths[name] = try canonical(URL(fileURLWithPath: path).appendingPathComponent("android")).path
        }
        return paths
    }

    private static func binding(settings: URL, android: URL, app: URL, sdk: URL, launcher: URL,
                                target: URL, plugins: [String: String]) -> String {
        let descriptors = plugins.sorted { $0.key < $1.key }.map { "\(groovy(":" + $0.key)): \(groovy($0.value))" }.joined(separator: ",")
        return """
        import java.util.Properties
        import org.gradle.api.GradleException
        def selectedSettings = new File(\(groovy(settings.path))).canonicalFile
        if (gradle.startParameter.settingsFile?.canonicalFile != selectedSettings) { return }
        if (!gradle.gradleVersion.startsWith('8.')) { throw new GradleException('Protected Flutter execution requires prepared Gradle 8') }
        if (gradle.startParameter.configurationCacheRequested) { throw new GradleException('Configuration cache bypasses the per-invocation Flutter binding') }
        def originalAndroid = new File(\(groovy(android.path))).canonicalFile
        def executionSDK = new File(\(groovy(sdk.path))).canonicalFile
        def childLauncher = new File(\(groovy(launcher.path))).canonicalFile
        def local = new File(selectedSettings.parentFile, 'local.properties')
        def values = new Properties()
        local.withInputStream { values.load(it) }
        values.setProperty('flutter.sdk', executionSDK.path)
        local.withOutputStream { values.store(it, null) }
        gradle.startParameter.setProjectDir(originalAndroid)
        gradle.beforeSettings { s ->
            s.rootProject.projectDir = originalAndroid
            s.ext.flutterSdkPath = executionSDK.path
        }
        gradle.settingsEvaluated { s ->
            def expected = [':app': new File(originalAndroid, 'app').canonicalPath\(descriptors.isEmpty ? "" : "," + descriptors)]
            def actual = [:]
            def visit
            visit = { descriptor ->
                if (descriptor.path != ':') { actual[descriptor.path] = descriptor.projectDir.canonicalPath }
                descriptor.children.each { visit(it) }
            }
            visit(s.rootProject)
            if (s.rootProject.projectDir.canonicalFile != originalAndroid || actual != expected) {
                throw new GradleException('Flutter Android root, app or native plugin descriptors changed')
            }
        }
        gradle.projectsEvaluated {
            if (gradle.rootProject.projectDir.canonicalFile != originalAndroid) { throw new GradleException('Flutter Android root changed') }
            def bound = 0
            gradle.rootProject.allprojects.each { project ->
                def plugin = project.plugins.findPlugin('dev.flutter.flutter-gradle-plugin')
                if (plugin != null) {
                    def type = plugin.class.classLoader.loadClass('com.flutter.gradle.tasks.BaseFlutterTask')
                    project.tasks.withType(type).each { task ->
                        if (task.flutterRoot?.canonicalFile != executionSDK || task.sourceDir?.canonicalFile != new File(\(groovy(app.path))).canonicalFile || new File(task.targetPath).canonicalFile != new File(\(groovy(target.path))).canonicalFile) {
                            throw new GradleException('Flutter task SDK, source or entrypoint changed')
                        }
                        task.flutterExecutable = childLauncher
                        task.doFirst {
                            if (task.flutterExecutable?.canonicalFile != childLauncher || task.flutterRoot?.canonicalFile != executionSDK) { throw new GradleException('Flutter child launcher changed') }
                        }
                        bound++
                    }
                }
            }
            if (bound == 0) { throw new GradleException('No verified Flutter Android task was bound') }
        }
        """
    }

    static func canonical(_ path: URL, mayBeAbsent: Bool = false) throws -> URL {
        guard path.isFileURL, path.path.hasPrefix("/"), path.query == nil, path.fragment == nil,
              !path.path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }),
              !path.path.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else {
            throw failure("A Flutter protection path is not an unambiguous absolute file path.")
        }
        // Foundation standardization can turn canonical /private/tmp back into its /tmp alias.
        var existing = path
        while mayBeAbsent && !exists(existing) && existing.path != "/" { existing.deleteLastPathComponent() }
        guard let physical = realpath(existing.path, nil) else { throw failure("A Flutter input path cannot be resolved.") }
        defer { free(physical) }
        guard String(cString: physical) == existing.path else { throw failure("A Flutter input or output aliases another path.") }
        return path
    }

    private static func filtered(_ values: [String: Entry], excluding: [String]) -> [String: Entry] {
        values.filter { key, _ in !excluding.contains(where: { key == $0 || key.hasPrefix($0 + "/") }) }
    }
    private static func inside(_ parent: URL, _ child: URL) -> Bool { child.path == parent.path || child.path.hasPrefix(parent.path + "/") }
    private static func exists(_ path: URL) -> Bool { var info = stat(); return lstat(path.path, &info) == 0 }
    private static func directory(_ path: URL) throws {
        guard mkdir(path.path, 0o700) == 0 else { throw failure("A private Flutter directory already exists or cannot be created.") }
    }
    static func write(_ data: Data, to path: URL, mode: mode_t = 0o600) throws {
        let descriptor = open(path.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode)
        guard descriptor >= 0 else { throw failure("A private Flutter file already exists or cannot be created exclusively.") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        try handle.write(contentsOf: data)
        try handle.close()
        guard chmod(path.path, mode) == 0 else { throw failure("Private Flutter file permissions could not be retained.") }
    }
    private static func hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func seatbelt(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
    private static func shell(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    private static func groovy(_ value: String) -> String { "'" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'") + "'" }
    private static func failure(_ summary: String) -> DomainError {
        DomainError(summary: summary, remediation: Remediation(summary:
            "Preserve the selected SDK, source and lockfiles. Inspect the existing setup plan; this execution will not install, download or migrate them."))
    }
}

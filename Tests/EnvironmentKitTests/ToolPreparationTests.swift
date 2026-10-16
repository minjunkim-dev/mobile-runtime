import Core
import CryptoKit
@testable import EnvironmentKit
import Foundation
import TestSupport
import Testing

@Suite("approved Node Ruby JDK preparation")
struct ToolPreparationTests {
    private let host = ToolPreparationHost(architecture: "arm64", macOS: SemanticVersion(major: 27))

    @Test("planning pins the exact archive and does not download it", arguments: [PreparedTool.node, .ruby, .java])
    func planning(_ tool: PreparedTool) async throws {
        let fixture = try await fixture()
        let plan = try await inspect([tool], fixture: fixture)
        let step = try #require(plan.steps.first)
        #expect(step.kind == "install")
        #expect(step.installation?.revision == version(tool))
        #expect(step.installation?.artifact?.checksumAlgorithm == "sha256")
        #expect(step.installation?.artifact?.size == Int64(fixture.runner.payloads[tool]!.count))
        #expect(fixture.runner.downloads == 0)
        #expect(plan.activeTools[tool.rawValue] == nil)
        #expect(step.required?.contains("no shared manager cache writes") == true)
    }

    @Test("successful installation is reused and activates only measured project paths", arguments: [PreparedTool.node, .ruby, .java])
    func installAndRecheck(_ tool: PreparedTool) async throws {
        let fixture = try await fixture()
        let plan = try await inspect([tool], fixture: fixture)
        let action = try #require(plan.actions["tools.\(tool.rawValue)"])
        try await action.run(runner: fixture.runner, beforeCommit: { _ in })
        let after = try await inspect([tool], fixture: fixture)
        #expect(after.steps.isEmpty)
        #expect(after.activeTools[tool.rawValue]?.path.hasPrefix(fixture.repo.url("store/installs").path) == true)
        #expect(after.activeTools[tool.rawValue] == fixture.repo.url("store/installs/\(tool.rawValue)/\(version(tool))/bin/\(tool.rawValue)"))
        #expect(after.checks.first?.observed?.contains("executable SHA256") == true)
        #expect(fixture.runner.downloads == 1)
        #expect(try String(contentsOf: fixture.repo.url("store/existing/keep"), encoding: .utf8) == "original")
    }

    @Test("creating an absent tool store preserves the approved artifact identity", arguments: ["MISE_DATA_DIR", "XDG_DATA_HOME", "HOME"])
    func absentStoreApproval(_ key: String) async throws {
        let fixture = try await fixture()
        let directory = fixture.repo.root
        let runner = fixture.runner
        let environment = [key: fixture.repo.url("absent-parent/absent-store").path]
        let observedHost = host
        let request = ToolPreparationRequirement(tool: .node, version: "22.23.2", source: CheckSource(tier: 1, origin: ".nvmrc"))
        let plan = try await ToolPreparation.inspect(requirements: [request], directory: directory,
            environment: environment, runner: runner, host: observedHost)
        let action = try #require(plan.actions["tools.node"])
        let approved = action.metadata
        #expect(!FileManager.default.fileExists(atPath: approved.resourceRoot.path))
        try await action.run(runner: runner) { _ in
            let current = try await ToolPreparation.inspect(requirements: [request], directory: directory,
                environment: environment, runner: runner, host: observedHost)
            guard current.actions["tools.node"]?.metadata == approved else {
                throw DomainError(summary: "Approved tool identity changed after store creation", remediation: Remediation(summary: "Inspect again"))
            }
        }
        #expect(FileManager.default.isExecutableFile(atPath: approved.destination.appendingPathComponent("bin/node").path))
        #expect(runner.downloads == 1)
    }

    @Test("manager absence proposes one pinned mise and leaves global selections unchanged")
    func missingManager() async throws {
        let fixture = try await fixture(manager: false)
        let plan = try await inspect([.node, .ruby, .java], fixture: fixture)
        let bootstrap = try #require(plan.steps.first { $0.id == "tools.00.mise" })
        #expect(bootstrap.installation?.revision == "2026.10.7")
        #expect(plan.actions.count == 4)
        #expect(fixture.runner.downloads == 0)
        let action = try #require(plan.actions[bootstrap.id])
        try await action.run(runner: fixture.runner, beforeCommit: { _ in })
        let after = try await inspect([.node], fixture: fixture)
        #expect(after.steps.allSatisfy { $0.id != "tools.00.mise" })
        #expect(after.activeTools["mise"] == fixture.repo.url("store/manager/2026.10.7/bin/mise"))
        #expect(FileManager.default.isExecutableFile(atPath: fixture.repo.url("store/manager/2026.10.7/bin/mise").path))
        #expect(try String(contentsOf: fixture.repo.url("global-selection"), encoding: .utf8) == "old")
        #expect(!fixture.runner.commands.contains { $0.arguments.contains("install") || $0.arguments.contains("use") })
    }

    @Test("the project environment is observed separately and prereleases do not satisfy an exact stable request", arguments: [true, false])
    func projectEnvironmentReuse(_ exact: Bool) async throws {
        let fixture = try await fixture()
        let node = try fixture.repo.write("project tool/bin/node", "fixture node")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: node.path)
        let project = FakeProcessRunner(responses: ["/usr/bin/which node": .ok(node.path), "\(node.path) --version": .ok(exact ? "v22.23.2\n" : "v22.23.2-rc.1\n")])
        let request = ToolPreparationRequirement(tool: .node, version: "22.23.2", source: CheckSource(tier: 1, origin: "mise.toml"))
        let plan = try await ToolPreparation.inspect(requirements: [request], directory: fixture.repo.root,
            environment: [:], runner: fixture.runner, currentToolRunner: project, host: host)
        #expect(plan.steps.isEmpty == exact)
        #expect((plan.activeTools["node"] == node) == exact)
        #expect(fixture.runner.commands.isEmpty)
        #expect(project.log.first(matching: "\(node.path) --version") != nil)
    }

    @Test("another manager and a vendor-qualified unsupported JDK are preserved")
    func existingManagerAndVendor() async throws {
        let fixture = try await fixture(manager: false)
        let node = ToolPreparationRequirement(tool: .node, version: "22.23.2", source: CheckSource(tier: 1, origin: ".nvmrc"))
        let plan = try await ToolPreparation.inspect(requirements: [node], directory: fixture.repo.root,
            environment: ["MISE_DATA_DIR": fixture.repo.url("store").path, "NVM_DIR": fixture.repo.url("nvm").path], runner: fixture.runner, host: host)
        #expect(plan.actions.isEmpty)
        #expect(plan.steps.first?.observed?.contains("nvm") == true)
        let java = ToolPreparationRequirement(tool: .java, version: "zulu-17.0.18+8", source: CheckSource(tier: 1, origin: ".java-version"))
        let vendor = try await ToolPreparation.inspect(requirements: [java], directory: fixture.repo.root,
            environment: ["MISE_DATA_DIR": fixture.repo.url("store").path], runner: fixture.runner, host: host)
        #expect(vendor.actions.isEmpty)
        #expect(vendor.steps.first?.required == "zulu-17.0.18+8")
        #expect(fixture.runner.downloads == 0)
    }

    @Test("existing Zulu satisfies vendorless or Zulu JDK 21, but never an explicit Temurin request", arguments: ["21", "zulu-21", "zulu-21.0.11+10", "temurin-21", "temurin-21.0.11+10"])
    func selectedJavaProperties(_ declaration: String) async throws {
        let fixture = try await fixture()
        try fixture.repo.write("package.json", #"{"dependencies":{"react-native":"0.83.10"}}"#)
        try fixture.repo.write(".java-version", declaration + "\n")
        try fixture.repo.write("android/build.gradle", "plugins { id 'com.android.application' version '8.7.3' apply false }")
        try fixture.repo.write("android/gradle/wrapper/gradle-wrapper.properties", "distributionUrl=https\\://services.gradle.org/distributions/gradle-8.10.2-bin.zip")
        let java = try fixture.repo.write("selected jdk/bin/java", "existing JDK")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: java.path)
        let runner = SelectedJavaPropertiesRunner(base: fixture.runner, java: java)
        let anchor = try #require(ProjectAnchor.detect(from: fixture.repo.root))
        let requirements = try await ToolRequirements.resolve(anchor: anchor, platforms: [.android], runner: runner).filter { $0.tool == .java }
        let plan = try await ToolPreparation.inspect(requirements: requirements, directory: fixture.repo.root,
            environment: ["MISE_DATA_DIR": fixture.repo.url("store").path], runner: runner, currentToolRunner: runner, host: host)
        #expect((plan.activeTools["java"] == java) == !declaration.hasPrefix("temurin-"))
        #expect(plan.actions.isEmpty)
        #expect(fixture.runner.downloads == 0)
        #expect(try String(contentsOf: fixture.repo.url(".java-version"), encoding: .utf8) == declaration + "\n")
    }

    @Test("missing JDK runtime vendor architecture version or home is never promoted to exact reuse", arguments: ["java.version", "java.runtime.version", "java.vendor", "java.home", "os.arch"])
    func missingJavaProperty(_ property: String) async throws {
        let fixture = try await fixture()
        let java = try fixture.repo.write("selected jdk/bin/java", "existing JDK")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: java.path)
        let runner = SelectedJavaPropertiesRunner(base: fixture.runner, java: java, omittedProperty: property)
        let request = ToolPreparationRequirement(tool: .java, version: "zulu-21.0.11+10", source: CheckSource(tier: 1, origin: ".java-version"))
        let plan = try await ToolPreparation.inspect(requirements: [request], directory: fixture.repo.root,
            environment: ["MISE_DATA_DIR": fixture.repo.url("store").path], runner: runner, currentToolRunner: runner, host: host)
        #expect(plan.activeTools["java"] == nil)
        #expect(plan.actions.isEmpty)
        #expect(plan.steps.first?.kind == "provider")
    }

    @Test("a shim's reported Java home must match that home's actual properties")
    func verifyReportedJavaHome() async throws {
        let fixture = try await fixture()
        let shim = try fixture.repo.write("selected shim/java", "shim")
        let actual = try fixture.repo.write("other jdk/bin/java", "different JDK")
        for path in [shim, actual] { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path) }
        let runner = SelectedJavaPropertiesRunner(base: fixture.runner, java: shim, reportedHome: actual.deletingLastPathComponent().deletingLastPathComponent())
        #expect(try await ToolJavaObservation.observe(executable: shim.path, directory: fixture.repo.root, runner: runner) == nil)
    }

    @Test("shared setup plans and runs pinned tools even when the project toolchain is missing")
    func sharedMissingToolchain() async throws {
        let fixture = try await fixture(manager: false)
        try fixture.repo.write("package.json", #"{"dependencies":{"react-native":"0.83.10"}}"#)
        try fixture.repo.write(".nvmrc", "22.23.2\n")
        try fixture.repo.directory("ios")
        let runner = MissingProjectToolchainRunner(base: fixture.runner)
        let input = ProjectInspectionInput(directory: fixture.repo.root,
            environment: ["MISE_DATA_DIR": fixture.repo.url("store").path])
        let planned = await PreparationExecution.run(input: input, planOnly: true, runner: runner)
        #expect(planned.operation.state == "needs-approval")
        let plan = try #require(planned.plan)
        #expect(plan.steps.contains { $0.id == "tools.node" && $0.kind == "install" })
        let result = await PreparationExecution.run(input: input, approvedPlanID: plan.id, runner: runner,
            leases: ResourceLeases(directory: fixture.repo.url(".mobile/leases")))
        #expect(result.operation.completed.contains("tools.node"))
        #expect(FileManager.default.isExecutableFile(atPath: fixture.repo.url("store/installs/node/22.23.2/bin/node").path))
        #expect(try String(contentsOf: fixture.repo.url(".nvmrc"), encoding: .utf8) == "22.23.2\n")
    }

    @Test("workflow and doctor observe the prepared child tool offline")
    func sharedOfflineActivation() async throws {
        let fixture = try await fixture()
        try fixture.repo.write("package.json", #"{"dependencies":{"react-native":"0.83.10"}}"#)
        try fixture.repo.write(".nvmrc", "22.23.2\n")
        try fixture.repo.directory("ios")
        let plan = try await inspect([.node], fixture: fixture)
        try await #require(plan.actions["tools.node"]).run(runner: fixture.runner, beforeCommit: { _ in })
        let runner = MissingProjectToolchainRunner(base: fixture.runner)
        let input = ProjectInspectionInput(directory: fixture.repo.root, environment: ["MISE_DATA_DIR": fixture.repo.url("store").path])
        let anchor = try #require(ProjectAnchor.detect(from: fixture.repo.root))
        let before = fixture.runner.commands.count
        let context = await WorkflowContext.make(input: input, platform: .ios, anchor: anchor, runner: runner)
        #expect(try await context.projectRunner.run(ProcessCommand("node", ["--version"])).standardOutput == "v22.23.2")
        _ = try await EnvironmentInspection.run(input: input, runner: runner)
        let commands = Array(fixture.runner.commands.dropFirst(before))
        #expect(commands.contains { $0.executable == fixture.repo.url("store/installs/node/22.23.2/bin/node").path })
        #expect(!commands.contains { $0.executable == "curl" || $0.arguments.contains("install") })
    }

    @Test("doctor reports an unmet exact manager declaration without downloading tools")
    func sharedDoctorMissingDeclaration() async throws {
        let fixture = try await fixture()
        try fixture.repo.write("package.json", #"{"dependencies":{"react-native":"0.83.10"}}"#)
        try fixture.repo.write(".tool-versions", "nodejs 22.23.2\n")
        try fixture.repo.directory("ios")
        let runner = MissingProjectToolchainRunner(base: fixture.runner)
        let result = try await EnvironmentInspection.run(input: ProjectInspectionInput(directory: fixture.repo.root,
            environment: ["MISE_DATA_DIR": fixture.repo.url("store").path], platform: .ios), runner: runner)
        #expect(result.report.checks.contains { $0.id == "tools.node" && $0.status == .error })
        #expect(!fixture.runner.commands.contains { $0.executable == "curl" })
    }

    @Test("workflow observation stays offline and conflicting declarations remain manual")
    func observeOnly() async throws {
        let fixture = try await fixture()
        let node = ToolPreparationRequirement(tool: .node, version: "22.23.2", source: CheckSource(tier: 1, origin: ".nvmrc"))
        let observed = try await ToolPreparation.inspect(requirements: [node], directory: fixture.repo.root,
            environment: ["MISE_DATA_DIR": fixture.repo.url("store").path], runner: fixture.runner, host: host, planInstallations: false)
        #expect(observed.actions.isEmpty)
        #expect(!fixture.runner.commands.contains { $0.executable == "curl" })
        let other = ToolPreparationRequirement(tool: .node, version: "24.21.0", source: CheckSource(tier: 1, origin: "tool declaration"))
        let conflict = try await ToolPreparation.inspect(requirements: [node, other], directory: fixture.repo.root,
            environment: ["MISE_DATA_DIR": fixture.repo.url("store").path], runner: fixture.runner, host: host)
        #expect(conflict.actions.isEmpty)
        #expect(!fixture.runner.commands.contains { $0.executable == "curl" })
    }

    @Test("partial completion, download failure, cancellation and retry keep completed versions")
    func partialAndRetry() async throws {
        let fixture = try await fixture()
        let plan = try await inspect([.node, .ruby, .java], fixture: fixture)
        try await #require(plan.actions["tools.node"]).run(runner: fixture.runner, beforeCommit: { _ in })
        fixture.runner.setFault(.download(.ruby))
        await #expect(throws: DomainError.self) { try await #require(plan.actions["tools.ruby"]).run(runner: fixture.runner, beforeCommit: { _ in }) }
        let failed = try await inspect([.node, .ruby, .java], fixture: fixture)
        #expect(failed.checks.first { $0.id == "tools.node" }?.kind == "reuse")
        #expect(Set(failed.steps.map(\.id)) == ["tools.ruby", "tools.java"])
        fixture.runner.setFault(.cancel(.java))
        await #expect(throws: CancellationError.self) { try await #require(failed.actions["tools.java"]).run(runner: fixture.runner, beforeCommit: { _ in }) }
        #expect(FileManager.default.fileExists(atPath: fixture.repo.url("store/installs/node/22.23.2/bin/node").path))
        fixture.runner.setFault(.none)
        for action in failed.actions.values { try await action.run(runner: fixture.runner, beforeCommit: { _ in }) }
        #expect(try await inspect([.node, .ruby, .java], fixture: fixture).steps.isEmpty)
    }

    @Test("metadata cancellation propagates; incompatible staged OS and external libraries block commit")
    func validationAndMetadataCancel() async throws {
        let fixture = try await fixture()
        fixture.runner.setFault(.metadataCancel)
        await #expect(throws: CancellationError.self) { try await inspect([.node], fixture: fixture) }
        fixture.runner.setFault(.none)
        let plan = try await inspect([.ruby], fixture: fixture)
        let action = try #require(plan.actions["tools.ruby"])
        for fault in [ToolPreparationFixtureRunner.Fault.minimumOS, .externalLibrary, .platformIOS] {
            fixture.runner.setFault(fault)
            await #expect(throws: DomainError.self) { try await action.run(runner: fixture.runner, beforeCommit: { _ in }) }
            #expect(!FileManager.default.fileExists(atPath: action.metadata.destination.path))
        }
    }

    private func version(_ tool: PreparedTool) -> String { switch tool { case .node: "22.23.2"; case .ruby: "3.2.2"; case .java: "temurin-17.0.18+8" } }

    @Test("bundled JVM install name resolves through a contained library rpath", arguments: ["none", "local-precedence", "bare-loader", "bare-executable"])
    func bundledJVMRpath(_ layout: String) async throws {
        let fixture = try await libraryFixture(layout)
        try await ToolInstallationValidation.validate(stage: fixture.repo.url("stage"), executable: "bin/java", version: version(.java), tool: "java", host: host, runner: fixture.runner)
        #expect(fixture.runner.inspectionHits >= 3)
        #expect(fixture.runner.commands.contains { $0.executable == "/usr/bin/env" && $0.arguments.contains("-version") })
    }

    @Test("rpath fallback cannot hide ambiguous missing aliased or external libraries", arguments: [
        "ambiguous", "missing", "plain-file", "wrong-id", "self-link", "outside-link", "external-local", "escaping-local", "external-main", "external-pool",
        "absolute-external", "usr-lookalike", "system-lookalike", "usr-traversal", "system-traversal", "alias-parent-traversal", "nul-rpath", "relative-local", "relative-main", "loader-lookalike", "executable-lookalike",
    ])
    func rejectedLibraryFallback(_ fault: String) async throws {
        let fixture = try await libraryFixture(fault)
        await #expect(throws: DomainError.self) {
            try await ToolInstallationValidation.validate(stage: fixture.repo.url("stage"), executable: "bin/java", version: version(.java), tool: "java", host: host, runner: fixture.runner)
        }
        #expect(fixture.runner.inspectionHits > 0)
        #expect(!fixture.runner.commands.contains { $0.executable == "/usr/bin/env" })
        #expect(try String(contentsOf: fixture.repo.url("store/existing/keep"), encoding: .utf8) == "original")
    }

    private func libraryFixture(_ fault: String = "none") async throws -> (repo: FixtureRepo, runner: ToolPreparationFixtureRunner) {
        let fixture = try await fixture()
        let stage = fixture.repo.url("stage")
        let magic = Data([0xcf, 0xfa, 0xed, 0xfe])
        let binaries = ["bin/java", "lib/libjava.dylib", "lib/server/libjvm.dylib"]
            + (["ambiguous", "local-precedence"].contains(fault) ? ["lib/other/libjvm.dylib"] : [])
            + (fault == "local-precedence" ? ["lib/libjvm.dylib"] : [])
        for relative in binaries {
            let file = try fixture.repo.write("stage/\(relative)", "fixture")
            try (magic + Data(relative.utf8)).write(to: file)
        }
        if fault == "missing" { try FileManager.default.removeItem(at: stage.appendingPathComponent("lib/server/libjvm.dylib")) }
        if fault == "plain-file" { try Data("not Mach-O".utf8).write(to: stage.appendingPathComponent("lib/server/libjvm.dylib")) }
        if ["external-local", "escaping-local", "external-main", "external-pool", "absolute-external"].contains(fault) {
            try fixture.repo.write("outside/libjvm.dylib", "external")
        }
        if fault == "alias-parent-traversal" {
            try fixture.repo.write("outside/subdir/keep", "outside")
            try fixture.repo.write("outside/libjvm.dylib", "external")
            try FileManager.default.createSymbolicLink(atPath: stage.appendingPathComponent("lib/alias").path, withDestinationPath: fixture.repo.url("outside/subdir").path)
        }
        if fault == "self-link" || fault == "outside-link" {
            let target = fault == "self-link" ? "libjvm.dylib" : try fixture.repo.write("outside/libjvm.dylib", "outside").path
            try FileManager.default.createSymbolicLink(atPath: stage.appendingPathComponent("lib/libjvm.dylib").path, withDestinationPath: target)
        }
        for relative in binaries {
            let directory = (relative as NSString).deletingLastPathComponent
            var rpath = relative == "bin/java" ? "@loader_path/../lib" : "@loader_path/."
            if fault == "external-main", relative == "bin/java" { rpath = fixture.repo.url("outside").path }
            if fault == "external-local", relative == "lib/libjava.dylib" { rpath = fixture.repo.url("outside").path }
            if fault == "relative-main", relative == "bin/java" { rpath = "../outside" }
            if fault == "relative-local", relative == "lib/libjava.dylib" { rpath = "../outside" }
            if fault == "loader-lookalike", relative == "lib/libjava.dylib" { rpath = "@loader_pathology" }
            if fault == "executable-lookalike", relative == "bin/java" { rpath = "@executable_pathology" }
            if fault == "escaping-local", relative == "lib/libjava.dylib" { rpath = "@loader_path/../../outside" }
            if fault == "alias-parent-traversal", relative == "lib/libjava.dylib" { rpath = "@loader_path/alias/.." }
            if fault == "nul-rpath", relative == "lib/libjava.dylib" { rpath = "@loader_path/.\0/../../outside" }
            if fault == "external-pool", directory == "lib/server" { rpath = fixture.repo.url("outside").path }
            let installName = relative == "bin/java" ? nil : "@rpath/\((relative as NSString).lastPathComponent)"
            var settings = "cmd LC_BUILD_VERSION\nplatform 1\nminos 14.0\ncmd LC_RPATH\npath \(rpath) (offset 12)\n"
            if fault == "bare-loader", relative == "lib/libjava.dylib" { settings += "cmd LC_RPATH\npath @loader_path (offset 12)\n" }
            if fault == "bare-executable", relative == "bin/java" { settings += "cmd LC_RPATH\npath @executable_path (offset 12)\n" }
            if let installName { settings += "cmd LC_ID_DYLIB\nname \(fault == "wrong-id" && directory == "lib/server" ? "@rpath/wrong.dylib" : installName) (offset 24)\n" }
            var dependency = relative == "lib/libjava.dylib" ? "@rpath/libjvm.dylib" : "/usr/lib/libSystem.B.dylib"
            if relative == "lib/libjava.dylib" {
                switch fault {
                case "absolute-external": dependency = fixture.repo.url("outside/libjvm.dylib").path
                case "usr-lookalike": dependency = "/usr/library/libjvm.dylib"
                case "system-lookalike": dependency = "/System/LibraryEvil/libjvm.dylib"
                case "usr-traversal": dependency = "/usr/lib/../../outside/libjvm.dylib"
                case "system-traversal": dependency = "/System/Library/../../outside/libjvm.dylib"
                default: break
                }
            }
            let libraries = "fixture:\n\t\(dependency) (compatibility version 1.0.0, current version 1.0.0)\n"
            fixture.runner.setInspection(stage.appendingPathComponent(relative).path, settings: settings, libraries: libraries)
        }
        return fixture
    }

    private func inspect(_ tools: [PreparedTool], fixture: (repo: FixtureRepo, runner: ToolPreparationFixtureRunner)) async throws -> ToolPreparation {
        try await ToolPreparation.inspect(requirements: tools.map { ToolPreparationRequirement(tool: $0, version: version($0), source: CheckSource(tier: 1, origin: "fixture declaration")) },
            directory: fixture.repo.root, environment: ["MISE_DATA_DIR": fixture.repo.url("store").path], runner: fixture.runner, host: host)
    }

    private func fixture(manager: Bool = true) async throws -> (repo: FixtureRepo, runner: ToolPreparationFixtureRunner) {
        let repo = try FixtureRepo()
        try repo.write("store/existing/keep", "original")
        try repo.write("global-selection", "old")
        let mise = manager ? try repo.write("bin/mise", "existing manager") : nil
        if let mise { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: mise.path) }
        var payloads: [PreparedTool: Data] = [:]
        for tool in [PreparedTool.node, .ruby, .java] {
            let root = switch tool { case .node: "node-v22.23.2-darwin-arm64"; case .ruby: "ruby-3.2.2"; case .java: "jdk-17.0.18+8" }
            let member = root + (tool == .java ? "/Contents/Home/bin/java" : "/bin/\(tool.rawValue)")
            let file = repo.url("\(tool.rawValue).tar")
            try toolFixtureTAR([(path: member, body: Data("fixture \(tool.rawValue)".utf8), type: 48, link: "")]).write(to: file)
            let result = try await SystemProcessRunner().run(ProcessCommand("gzip", ["-k", file.path], workingDirectory: repo.root))
            #expect(result.terminationStatus.isSuccess)
            payloads[tool] = try Data(contentsOf: file.appendingPathExtension("gz"))
        }
        return (repo, ToolPreparationFixtureRunner(payloads: payloads, mise: mise))
    }
}

private struct MissingProjectToolchainRunner: ProcessRunner {
    let base: ToolPreparationFixtureRunner
    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        do { return try await base.run(command, onLine: onLine) }
        catch is FixtureMiss { return ProcessResult(terminationStatus: .exited(127), standardOutput: "", standardError: "fixture toolchain unavailable") }
    }
    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 { throw FixtureMiss(command: command.description) }
}

private struct SelectedJavaPropertiesRunner: ProcessRunner {
    let base: ToolPreparationFixtureRunner
    let java: URL
    var omittedProperty: String? = nil
    var reportedHome: URL? = nil
    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        if command.executable == "node", command.arguments == ["--version"] {
            return ProcessResult(terminationStatus: .exited(127), standardOutput: "", standardError: "fixture Node absent")
        }
        if command.executable == "/usr/bin/which", command.arguments == ["java"] {
            return ProcessResult(terminationStatus: .exited(0), standardOutput: java.path, standardError: "")
        }
        if ["java", java.path].contains(command.executable), command.arguments.contains("-XshowSettings:properties") {
            let home = reportedHome ?? java.deletingLastPathComponent().deletingLastPathComponent()
            let properties = "java.version = 21.0.11\njava.runtime.version = 21.0.11+10-LTS\njava.vendor = Azul Systems, Inc.\njava.home = \(home.path)\nos.arch = aarch64\n"
            let output = properties.components(separatedBy: .newlines).filter { line in
                omittedProperty.map { !line.hasPrefix($0 + " =") } ?? true
            }.joined(separator: "\n")
            return ProcessResult(terminationStatus: .exited(0), standardOutput: "", standardError: output)
        }
        if let home = reportedHome, command.executable == home.appendingPathComponent("bin/java").path {
            return ProcessResult(terminationStatus: .exited(0), standardOutput: "", standardError: "java.version = 17.0.18\njava.runtime.version = 17.0.18+8\njava.vendor = Eclipse Adoptium\njava.home = \(home.path)\nos.arch = aarch64\n")
        }
        // Deliberately misleading banner. Reuse must rely on the properties above.
        if ["java", java.path].contains(command.executable), command.arguments == ["-version"] {
            return ProcessResult(terminationStatus: .exited(0), standardOutput: "", standardError: "Temurin-17.0.18+8")
        }
        return try await base.run(command, onLine: onLine)
    }
    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 { throw FixtureMiss(command: command.description) }
}

private final class ToolPreparationFixtureRunner: ProcessRunner, @unchecked Sendable {
    enum Fault { case none, download(PreparedTool), cancel(PreparedTool), metadataCancel, minimumOS, externalLibrary, platformIOS }
    let payloads: [PreparedTool: Data]
    let mise: URL?
    private let lock = NSLock()
    private var fault: Fault = .none
    private var calls: [ProcessCommand] = []
    private var inspections: [String: (settings: String, libraries: String)] = [:]
    private var hits = 0
    var inspectionHits: Int { lock.withLock { hits } }
    var commands: [ProcessCommand] { lock.withLock { calls } }
    var downloads: Int { commands.filter { $0.executable == "curl" && $0.arguments.contains("--output") }.count }
    init(payloads: [PreparedTool: Data], mise: URL?) { self.payloads = payloads; self.mise = mise }
    func setFault(_ value: Fault) { lock.withLock { fault = value } }
    func setInspection(_ path: String, settings: String, libraries: String) {
        lock.withLock { inspections[URL(fileURLWithPath: path).resolvingSymlinksInPath().path] = (settings, libraries) }
    }

    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        let fault = lock.withLock { calls.append(command); return self.fault }
        func ok(_ text: String) -> ProcessResult { ProcessResult(terminationStatus: .exited(0), standardOutput: text, standardError: "") }
        if command.executable == "/usr/bin/which" {
            if command.arguments == ["mise"], let mise { return ok(mise.path) }
            return ProcessResult(terminationStatus: .exited(1), standardOutput: "", standardError: "")
        }
        if command.executable == "/bin/sh", command.arguments.contains("runstir-tool-gzip") { return try await SystemProcessRunner().run(command, onLine: onLine) }
        if command.executable == "/usr/bin/lipo" { return ok("arm64\n") }
        if command.executable.hasSuffix("/bin/mise") { return ok("2026.10.7 macos-arm64") }
        if command.executable == "/usr/bin/otool" {
            if let path = command.arguments.last, let inspection = lock.withLock({ () -> (settings: String, libraries: String)? in
                guard let inspection = inspections[URL(fileURLWithPath: path).resolvingSymlinksInPath().path] else { return nil }
                hits += 1
                return inspection
            }) {
                return ok(command.arguments.contains("-l") ? inspection.settings : inspection.libraries)
            }
            let minimum = if case .minimumOS = fault { "99.0" } else { "14.0" }
            let platform = if case .platformIOS = fault { "2" } else { "1" }
            let library = if case .externalLibrary = fault { "/opt/homebrew/lib/unapproved.dylib" } else { "/usr/lib/libSystem.B.dylib" }
            if command.arguments.contains("-l") { return ok("cmd LC_BUILD_VERSION\nplatform \(platform)\nminos \(minimum)\n") }
            return ok("fixture:\n\t\(library) (compatibility version 1.0.0, current version 1.0.0)\n")
        }
        if command.executable == "/usr/bin/env" || command.executable.contains("/installs/") {
            let text = command.description
            if text.contains("bin/java"), command.arguments.contains("-XshowSettings:properties") {
                let home = URL(fileURLWithPath: command.executable).deletingLastPathComponent().deletingLastPathComponent().path
                return ok("java.version = 17.0.18\njava.runtime.version = 17.0.18+8\njava.vendor = Eclipse Adoptium\njava.home = \(home)\nos.arch = aarch64\n")
            }
            if text.contains("--disable-gems") { return ok("3.2.2") }
            if text.contains("bin/ruby") { return ok("ruby 3.2.2p53") }
            if text.contains("bin/java") { return ok("openjdk version 17.0.18\nTemurin-17.0.18+8") }
            if text.contains("bin/mise") { return ok("2026.10.7 macos-arm64") }
            return ok("v22.23.2")
        }
        if command.executable == "curl" {
            if case .metadataCancel = fault, !command.arguments.contains("--output") { throw CancellationError() }
            let url = command.arguments.last!
            let tool: PreparedTool? = url.contains("ruby") ? .ruby : url.contains("temurin") || url.contains("OpenJDK") ? .java : url.contains("nodejs") ? .node : nil
            let data = tool.flatMap { payloads[$0] } ?? Data("fixture mise".utf8)
            if let index = command.arguments.firstIndex(of: "--output") {
                if case .cancel(let selected) = fault, selected == tool { throw CancellationError() }
                if case .download(let selected) = fault, selected == tool { return ProcessResult(terminationStatus: .exited(22), standardOutput: "", standardError: "controlled failure") }
                try data.write(to: URL(fileURLWithPath: command.arguments[index + 1]))
                return ok("")
            }
            let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            if command.arguments.contains("--head") { return ok("HTTP/2 200\r\nContent-Length: \(data.count)\r\nDate: changing metadata\r\n") }
            if url.contains("SHASUMS256") { return ok(sha + "  node-v22.23.2-darwin-arm64.tar.gz\n") }
            let repo = tool == .ruby ? "jdx/ruby" : tool == .java ? "adoptium/temurin17-binaries" : "jdx/mise"
            let tag = tool == .ruby ? "3.2.2" : tool == .java ? "jdk-17.0.18+8" : "v2026.10.7"
            let name = tool == .ruby ? "ruby-3.2.2.macos.tar.gz" : tool == .java ? "OpenJDK17U-jdk_aarch64_mac_hotspot_17.0.18_8.tar.gz" : "mise-v2026.10.7-macos-arm64"
            let object: [String: Any] = ["tag_name": tag, "draft": false, "prerelease": false, "assets": [["id": 1, "name": name, "size": data.count, "digest": "sha256:" + sha,
                "browser_download_url": "https://github.com/\(repo)/releases/download/\(tag.replacingOccurrences(of: "+", with: "%2B"))/\(name)"]]]
            return ok(String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self))
        }
        throw FixtureMiss(command: command.description)
    }

    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 { throw FixtureMiss(command: command.description) }
}

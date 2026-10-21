import Core
import CryptoKit
@testable import EnvironmentKit
import Foundation
import TestSupport
import Testing

@Suite("Flutter installation")
struct FlutterInstallationTests {
    @Test("a normal Flutter-root ZIP commits once and the next plan reuses it without downloading")
    func installAndReplan() async throws {
        let (fixture, bytes) = try await payload()
        let runner = FlutterPayloadRunner(data: bytes, directory: fixture.repo.root)
        let plan = try await fixture.inspect(runner)
        let action = try #require(plan.actions["flutter.sdk"])
        #expect(!FileManager.default.fileExists(atPath: action.metadata.destination.path))
        try await action.run(runner: runner, beforeCommit: { paths in
            #expect(paths.allSatisfy { $0.path.hasPrefix(action.metadata.resourceRoot.path + "/") })
        })
        #expect(try FlutterSDK.read(action.metadata.destination).version == "3.41.9")
        #expect(runner.downloads == 1)
        #expect(try String(contentsOf: fixture.repo.url("managed/other-sdk/keep"), encoding: .utf8) == "preserve")
        let next = try await fixture.inspect(runner)
        #expect(next.checks.contains { $0.id == "flutter.sdk" && $0.kind == "reuse" })
        #expect(next.actions.isEmpty)
        #expect(next.dependencyCommand?.executable.hasPrefix(action.metadata.destination.path + "/") == true)
        #expect(runner.downloads == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: action.metadata.resourceRoot.path).allSatisfy { !$0.hasPrefix(".runstir-") })
    }

    @Test("download failure and cancellation preserve source, existing SDKs and clean only owned scratch")
    func failureAndCancellation() async throws {
        for fault in ["download", "cancel"] {
            let (fixture, bytes) = try await payload()
            let runner = FlutterPayloadRunner(data: bytes, directory: fixture.repo.root, fault: fault)
            let plan = try await fixture.inspect(runner)
            let action = try #require(plan.actions["flutter.sdk"])
            let lock = try Data(contentsOf: fixture.repo.url("pubspec.lock"))
            if fault == "cancel" {
                await #expect(throws: CancellationError.self) { try await action.run(runner: runner, beforeCommit: { _ in }) }
            } else {
                await #expect(throws: DomainError.self) { try await action.run(runner: runner, beforeCommit: { _ in }) }
            }
            #expect(!FileManager.default.fileExists(atPath: action.metadata.destination.path))
            #expect(try Data(contentsOf: fixture.repo.url("pubspec.lock")) == lock)
            #expect(try String(contentsOf: fixture.repo.url("managed/other-sdk/keep"), encoding: .utf8) == "preserve")
            #expect(try FileManager.default.contentsOfDirectory(atPath: action.metadata.resourceRoot.path).allSatisfy { !$0.hasPrefix(".runstir-") })
        }
    }

    @Test("a completed SDK remains installed when the following workspace inspection is cancelled")
    func completedInstallSurvivesCancellation() async throws {
        let (fixture, bytes) = try await payload()
        let runner = FlutterPayloadRunner(data: bytes, directory: fixture.repo.root)
        let plan = try await fixture.inspect(runner)
        let action = try #require(plan.actions["flutter.sdk"])
        try await action.run(runner: runner, beforeCommit: { _ in })
        let cancelled = FlutterPayloadRunner(data: bytes, directory: fixture.repo.root, fault: "workspace-cancel")
        await #expect(throws: CancellationError.self) { try await fixture.inspect(cancelled) }
        #expect(try FlutterSDK.read(action.metadata.destination).revision == FlutterFixture.revision)
        #expect(cancelled.downloads == 0)
    }

    func payload() async throws -> (FlutterFixture, Data) {
        let fixture = try FlutterFixture()
        try FileManager.default.removeItem(at: fixture.repo.url("sdk"))
        try FlutterFixture.sdk(repo: fixture.repo, at: "payload/flutter")
        try fixture.repo.write("managed/other-sdk/keep", "preserve")
        let zip = fixture.repo.url("fixture.zip")
        let result = try await SystemProcessRunner().run(ProcessCommand("/usr/bin/zip", ["-q", "-r", zip.path, "flutter"],
            workingDirectory: fixture.repo.url("payload")))
        #expect(result.terminationStatus.isSuccess)
        return (fixture, try Data(contentsOf: zip))
    }
}

final class FlutterPayloadRunner: ProcessRunner, @unchecked Sendable {
    let data: Data
    let directory: URL
    let fault: String?
    let installationRoot: URL
    private let lock = NSLock()
    private var downloadCount = 0
    var downloads: Int { lock.withLock { downloadCount } }

    init(data: Data, directory: URL, fault: String? = nil, installationRoot: URL? = nil) {
        self.data = data; self.directory = directory; self.fault = fault
        self.installationRoot = (installationRoot ?? directory.appendingPathComponent("managed")).standardizedFileURL.resolvingSymlinksInPath()
    }

    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        if command.executable == "curl" {
            if let index = command.arguments.firstIndex(of: "--output") {
                lock.withLock { downloadCount += 1 }
                if fault == "cancel" { throw CancellationError() }
                if fault == "download" { return answer(7, "", "controlled download failure") }
                let target = URL(fileURLWithPath: command.arguments[index + 1])
                guard target.path.hasPrefix(installationRoot.path + "/") else { throw FixtureMiss(command: command.description) }
                try data.write(to: target)
                return answer(0, "")
            }
            if command.arguments.contains("--head") { return answer(0, "HTTP/2 200\r\ncontent-length: \(data.count)\r\n") }
            if command.arguments.last == FlutterRelease.url.absoluteString {
                let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                return answer(0, String(decoding: try FlutterFixture.releaseMetadata(checksum: hash), as: UTF8.self))
            }
        }
        if command.executable.hasSuffix("/bin/dart"), command.arguments == ["pub", "--suppress-analytics", "workspace", "list", "--json"] {
            if fault == "workspace-cancel" { throw CancellationError() }
            return answer(0, "{\"packages\":[{\"name\":\"example\",\"path\":\"\(directory.path)\"}]}")
        }
        if command.executable == "unzip" {
            return try await SystemProcessRunner(environment: ["PATH": "/usr/bin:/bin"], workingDirectory: directory).run(command, onLine: onLine)
        }
        if command.executable == "xcode-select" || command.executable == "/usr/bin/which" || ["ruby", "java", "pod"].contains(command.executable) {
            return answer(1, "", "Tool absent in fixture")
        }
        throw FixtureMiss(command: command.description)
    }

    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
        throw FixtureMiss(command: command.description)
    }

    private func answer(_ code: Int32, _ output: String, _ error: String = "") -> ProcessResult {
        ProcessResult(terminationStatus: .exited(code), standardOutput: output, standardError: error)
    }
}

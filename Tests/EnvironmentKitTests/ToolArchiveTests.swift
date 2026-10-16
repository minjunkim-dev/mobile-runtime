import Core
import CryptoKit
import EnvironmentKit
import Foundation
import TestSupport
import Testing

@Suite("approved tool TAR installation")
struct ToolArchiveTests {
    @Test("a pinned archive installs beside existing tools", arguments: ["node", "ruby", "java"])
    func exactInstall(_ tool: String) async throws {
        let fixture = try await fixture(tool)
        let runner = ToolPayloadRunner(data: fixture.data)
        try await ToolArchive.installTarGzip(fixture.metadata, payloadRoot: "tool", runner: runner)
        #expect(try String(contentsOf: fixture.metadata.destination.appendingPathComponent("bin/\(tool)"), encoding: .utf8) == "fixture \(tool)")
        #expect(try String(contentsOf: fixture.repo.url("store/existing/keep"), encoding: .utf8) == "original")
        #expect(runner.downloads == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.repo.url("store").path).allSatisfy { !$0.hasPrefix(".runstir-tool-") })
    }

    @Test("official JDK-style setgid directories install without special permissions")
    func setgidDirectories() async throws {
        let fixture = try await fixture("java", entries: [
            (path: "tool", body: Data(), type: 53, link: ""),
            (path: "tool/bin", body: Data(), type: 53, link: ""),
            (path: "tool/bin/java", body: Data("fixture java".utf8), type: 48, link: ""),
        ], modes: ["tool": 0o2755, "tool/bin": 0o2755])
        let manager = FileManager.default
        try await ToolArchive.installTarGzip(fixture.metadata, payloadRoot: "tool", runner: ToolPayloadRunner(data: fixture.data), validate: { stage, _ in
            for relative in ["", "bin", "bin/java"] {
                let mode = try #require(try FileManager.default.attributesOfItem(atPath: stage.appendingPathComponent(relative).path)[.posixPermissions] as? Int)
                #expect(mode & 0o7000 == 0)
            }
        })
        for relative in ["", "bin", "bin/java"] {
            let mode = try #require(try manager.attributesOfItem(atPath: fixture.metadata.destination.appendingPathComponent(relative).path)[.posixPermissions] as? Int)
            #expect(mode == 0o755)
        }
        #expect(try String(contentsOf: fixture.repo.url("store/existing/keep"), encoding: .utf8) == "original")
    }

    @Test("a later unreadable directory entry cannot bypass extracted link inspection")
    func unreadableExtractedDirectory() async throws {
        let fixture = try await fixture("node", entries: [
            (path: "tool/bin/node", body: Data("fixture node".utf8), type: 48, link: ""),
            (path: "tool/hidden/child", body: Data("hidden".utf8), type: 48, link: ""),
            (path: "tool/hidden", body: Data(), type: 53, link: ""),
        ], modes: ["tool/hidden": 0o111])
        let manager = FileManager.default
        defer {
            let scratch = (try? manager.contentsOfDirectory(at: fixture.repo.url("store"), includingPropertiesForKeys: nil)) ?? []
            let roots = [fixture.metadata.destination] + scratch.filter { $0.lastPathComponent.hasPrefix(".runstir-tool-") }
                .map { $0.appendingPathComponent("contents/tool") }
            for root in roots { try? manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.appendingPathComponent("hidden").path) }
        }
        await #expect(throws: DomainError.self) {
            try await ToolArchive.installTarGzip(fixture.metadata, payloadRoot: "tool", runner: ToolPayloadRunner(data: fixture.data), validate: { _, _ in
                Issue.record("Unreadable extracted directory reached tool validation")
            })
        }
        #expect(!manager.fileExists(atPath: fixture.metadata.destination.path))
        #expect(try String(contentsOf: fixture.repo.url("store/existing/keep"), encoding: .utf8) == "original")
    }

    @Test("special permissions other than directory setgid never install", arguments: [
        (UInt8(48), 0o4755), (UInt8(48), 0o2755), (UInt8(48), 0o1755),
        (UInt8(53), 0o4755), (UInt8(53), 0o1755), (UInt8(53), 0o6755), (UInt8(53), 0o3755),
    ])
    func rejectedSpecialModes(_ type: UInt8, _ mode: Int) async throws {
        let fixture = try await fixture("node", entries: [
            (path: "tool/special", body: Data(), type: type, link: ""),
            (path: "tool/bin/node", body: Data("fixture node".utf8), type: 48, link: ""),
        ], modes: ["tool/special": mode])
        await #expect(throws: DomainError.self) {
            try await ToolArchive.installTarGzip(fixture.metadata, payloadRoot: "tool", runner: ToolPayloadRunner(data: fixture.data))
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.metadata.destination.path))
        #expect(try String(contentsOf: fixture.repo.url("store/existing/keep"), encoding: .utf8) == "original")
    }

    @Test("download failure and cancellation preserve existing versions", arguments: ["node", "ruby", "java"])
    func failedDownload(_ tool: String) async throws {
        for failure in [ToolPayloadRunner.Fault.download, .cancel] {
            let fixture = try await fixture(tool)
            let runner = ToolPayloadRunner(data: fixture.data, fault: failure)
            do {
                try await ToolArchive.installTarGzip(fixture.metadata, payloadRoot: "tool", runner: runner)
                Issue.record("failed or cancelled download returned success")
            } catch {
                #expect((error is CancellationError) == (failure == .cancel))
            }
            #expect(!FileManager.default.fileExists(atPath: fixture.metadata.destination.path))
            #expect(try String(contentsOf: fixture.repo.url("store/existing/keep"), encoding: .utf8) == "original")
        }
    }

    @Test("a link outside the selected package is rejected before commit")
    func selectedRootBoundary() async throws {
        let fixture = try await fixture("node", entries: [
            (path: "tool/bin/node", body: Data("fixture node".utf8), type: 48, link: ""),
            (path: "shared/outside", body: Data("must not become a tool dependency".utf8), type: 48, link: ""),
            (path: "tool/alias", body: Data(), type: 50, link: "../shared/outside"),
        ])
        await #expect(throws: DomainError.self) {
            try await ToolArchive.installTarGzip(fixture.metadata, payloadRoot: "tool", runner: ToolPayloadRunner(data: fixture.data))
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.metadata.destination.path))
    }

    @Test("contained links and POSIX path headers survive the package move")
    func containedLinksAndPAX() async throws {
        let payload = "path=tool/bin/node\n"
        var count = payload.utf8.count + 2
        while String(count).utf8.count + 1 + payload.utf8.count != count { count = String(count).utf8.count + 1 + payload.utf8.count }
        let fixture = try await fixture("node", entries: [
            (path: "pax-header", body: Data("\(count) \(payload)".utf8), type: 120, link: ""),
            (path: "short-name", body: Data("fixture node".utf8), type: 48, link: ""),
            (path: "tool/alias", body: Data(), type: 50, link: "bin/node"),
        ])
        try await ToolArchive.installTarGzip(fixture.metadata, payloadRoot: "tool", runner: ToolPayloadRunner(data: fixture.data))
        #expect(try String(contentsOf: fixture.metadata.destination.appendingPathComponent("alias"), encoding: .utf8) == "fixture node")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: fixture.metadata.destination.appendingPathComponent("alias").path) == "bin/node")
    }

    @Test("escaping paths, duplicate members, devices and linked parents never install")
    func malformedEntries() async throws {
        let normal = (path: "tool/bin/node", body: Data("fixture node".utf8), type: UInt8(48), link: "")
        let cases = [
            [normal, (path: "../outside", body: Data("bad".utf8), type: 48, link: "")],
            [normal, normal],
            [normal, (path: "tool/device", body: Data(), type: 51, link: "")],
            [normal, (path: "tool/alias", body: Data(), type: 50, link: "bin"), (path: "tool/alias/child", body: Data(), type: 48, link: "")],
        ]
        for entries in cases {
            let fixture = try await fixture("node", entries: entries)
            await #expect(throws: DomainError.self) {
                try await ToolArchive.installTarGzip(fixture.metadata, payloadRoot: "tool", runner: ToolPayloadRunner(data: fixture.data))
            }
            #expect(!FileManager.default.fileExists(atPath: fixture.metadata.destination.path))
        }
    }

    @Test("recheck refusal and a destination race preserve source and the other owner")
    func recheckAndRace() async throws {
        let rejected = try await fixture("node")
        let marker = rejected.metadata.destination
        await #expect(throws: DomainError.self) {
            try await ToolArchive.installTarGzip(rejected.metadata, payloadRoot: "tool", runner: ToolPayloadRunner(data: rejected.data)) { paths in
                if let scratch = paths.first, FileManager.default.fileExists(atPath: scratch.appendingPathComponent("contents/tool/bin/node").path) {
                    throw DomainError(summary: "controlled stale approval", remediation: Remediation(summary: "inspect again"))
                }
            }
        }
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        let raced = try await fixture("node")
        let destination = raced.metadata.destination
        await #expect(throws: DomainError.self) {
            try await ToolArchive.installTarGzip(raced.metadata, payloadRoot: "tool", runner: ToolPayloadRunner(data: raced.data)) { paths in
                if let scratch = paths.first, FileManager.default.fileExists(atPath: scratch.appendingPathComponent("contents/tool/bin/node").path) {
                    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                    try Data("other owner".utf8).write(to: destination.appendingPathComponent("owner"))
                }
            }
        }
        #expect(try String(contentsOf: destination.appendingPathComponent("owner"), encoding: .utf8) == "other owner")
    }

    private func fixture(_ tool: String, entries: [(path: String, body: Data, type: UInt8, link: String)]? = nil, modes: [String: Int] = [:]) async throws -> (repo: FixtureRepo, data: Data, metadata: InstallationMetadata) {
        let repo = try FixtureRepo()
        try repo.write("store/existing/keep", "original")
        let tar = toolFixtureTAR(entries ?? [(path: "tool/bin/\(tool)", body: Data("fixture \(tool)".utf8), type: 48, link: "")], modes: modes)
        let source = repo.url("fixture.tar")
        try tar.write(to: source)
        let compressed = try await SystemProcessRunner().run(ProcessCommand("gzip", ["-k", source.path], workingDirectory: repo.root))
        #expect(compressed.terminationStatus.isSuccess)
        let data = try Data(contentsOf: repo.url("fixture.tar.gz"))
        let metadata = InstallationMetadata(package: "tool.\(tool)", revision: "1.2.3", destination: repo.url("store/\(tool)/1.2.3"),
            resourceRoot: repo.url("store"), artifact: InstallationArtifact(url: URL(string: "https://example.invalid/\(tool).tar.gz")!,
            checksumAlgorithm: "sha256", checksum: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), size: Int64(data.count)),
            repositoryURL: URL(string: "https://example.invalid/releases/1.2.3")!, repositorySHA256: String(repeating: "a", count: 64),
            requiredFile: "bin/\(tool)", executable: true)
        return (repo, data, metadata)
    }
}

func toolFixtureTAR(_ entries: [(path: String, body: Data, type: UInt8, link: String)], modes: [String: Int] = [:]) -> Data {
    var result = Data()
    for entry in entries {
        var header = [UInt8](repeating: 0, count: 512)
        func put(_ text: String, at start: Int, count: Int) {
            for (i, byte) in text.utf8.prefix(count).enumerated() { header[start + i] = byte }
        }
        put(entry.path, at: 0, count: 100)
        put(String(format: "%07o", modes[entry.path] ?? 0o755), at: 100, count: 8)
        put(String(format: "%011o", entry.body.count), at: 124, count: 12)
        for i in 148..<156 { header[i] = 32 }
        header[156] = entry.type
        put(entry.link, at: 157, count: 100)
        put("ustar", at: 257, count: 6)
        let checksum = header.reduce(0) { $0 + Int($1) }
        put(String(format: "%06o", checksum) + "\0 ", at: 148, count: 8)
        result.append(contentsOf: header)
        result.append(entry.body)
        result.append(Data(repeating: 0, count: (512 - entry.body.count % 512) % 512))
    }
    result.append(Data(repeating: 0, count: 1024))
    return result
}

private final class ToolPayloadRunner: ProcessRunner, @unchecked Sendable {
    enum Fault { case none, download, cancel }
    let data: Data
    let fault: Fault
    private let lock = NSLock()
    private var count = 0
    var downloads: Int { lock.withLock { count } }
    init(data: Data, fault: Fault = .none) { self.data = data; self.fault = fault }

    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        guard command.executable == "curl" else { return try await SystemProcessRunner().run(command, onLine: onLine) }
        lock.withLock { count += 1 }
        if fault == .cancel { throw CancellationError() }
        if fault == .download { return ProcessResult(terminationStatus: .exited(22), standardOutput: "", standardError: "controlled download failure") }
        let output = command.arguments.firstIndex(of: "--output")!
        try data.write(to: URL(fileURLWithPath: command.arguments[output + 1]))
        return ProcessResult(terminationStatus: .exited(0), standardOutput: "", standardError: "")
    }

    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 { throw CancellationError() }
}

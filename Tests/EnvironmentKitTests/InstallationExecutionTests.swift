import Core
import CryptoKit
import EnvironmentKit
import Foundation
import TestSupport
import Testing

@Suite("pinned installation executor")
struct InstallationExecutionTests {
    @Test("safe package-local links survive installation and revoked license consent blocks commit")
    func internalLinksAndRevokedLicense() async throws {
        let fixture = try await archive(internalLink: true)
        let metadata = pin(fixture.data, repo: fixture.repo)
        try await InstallationExecution.installSDKZip(metadata, localMetadata: Data(), runner: PayloadRunner(data: fixture.data))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: metadata.destination.appendingPathComponent("alias.jar").path) == "android.jar")
        let revoked = try await archive()
        let revokedPin = pin(revoked.data, repo: revoked.repo)
        let runner = PayloadRunner(data: revoked.data, revokedLicense: revoked.repo.url("sdk/licenses/fixture-license"))
        await #expect(throws: DomainError.self) {
            try await InstallationExecution.installSDKZip(revokedPin, localMetadata: Data(), runner: runner)
        }
        #expect(!FileManager.default.fileExists(atPath: revokedPin.destination.path))
        #expect(!FileManager.default.fileExists(atPath: revoked.repo.url("sdk/licenses/fixture-license").path))
    }

    @Test("generated package metadata replaces a staged link without modifying another package member")
    func stagedMetadataLink() async throws {
        let fixture = try await archive(metadataLink: true)
        let metadata = pin(fixture.data, repo: fixture.repo)
        try await InstallationExecution.installSDKZip(metadata, localMetadata: Data("generated metadata".utf8), runner: PayloadRunner(data: fixture.data))
        #expect(try String(contentsOf: metadata.destination.appendingPathComponent("android.jar"), encoding: .utf8) == "fixture jar")
        #expect(try String(contentsOf: metadata.destination.appendingPathComponent("package.xml"), encoding: .utf8) == "generated metadata")
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: metadata.destination.appendingPathComponent("package.xml").path)) == nil)
    }

    @Test("a verified archive commits one absent package and preserves existing SDK files")
    func exactInstall() async throws {
        let fixture = try await archive()
        let repo = fixture.repo
        try repo.write("sdk/existing/keep", "original")
        let metadata = pin(fixture.data, repo: repo)
        let runner = PayloadRunner(data: fixture.data)
        try await InstallationExecution.installSDKZip(metadata, localMetadata: Data("<repository/>".utf8), runner: runner)
        #expect(runner.downloadDestinations.count == 1)
        #expect(runner.downloadDestinations.allSatisfy { $0.path.hasPrefix(metadata.resourceRoot.path + "/") })
        #expect(try String(contentsOf: repo.url("sdk/platforms/android-36/android.jar"), encoding: .utf8) == "fixture jar")
        #expect(try String(contentsOf: repo.url("sdk/existing/keep"), encoding: .utf8) == "original")
        #expect(FileManager.default.fileExists(atPath: repo.url("sdk/platforms/android-36/package.xml").path))
        await #expect(throws: DomainError.self) {
            try await InstallationExecution.installSDKZip(metadata, localMetadata: Data(), runner: runner)
        }
        #expect(try String(contentsOf: repo.url("sdk/platforms/android-36/android.jar"), encoding: .utf8) == "fixture jar")
    }

    @Test("checksum, revision, truncated archive, and extraction failures never create a destination")
    func rejectedPayloads() async throws {
        for fault in ["checksum", "revision", "truncated", "extract"] {
            let fixture = try await archive(revision: fault == "revision" ? "3" : "2")
            let data = fault == "truncated" ? Data("not a ZIP".utf8) : fixture.data
            let metadata = pin(data, repo: fixture.repo, checksum: fault == "checksum" ? String(repeating: "0", count: 64) : nil)
            let runner = PayloadRunner(data: data, failExtraction: fault == "extract")
            await #expect(throws: DomainError.self) {
                try await InstallationExecution.installSDKZip(metadata, localMetadata: Data(), runner: runner)
            }
            #expect(!FileManager.default.fileExists(atPath: metadata.destination.path))
        }
    }

    @Test("escaping ZIP names and links are rejected before extraction")
    func unsafeArchives() async throws {
        for link in [false, true] {
            let fixture = try await archive(escapingLink: link)
            var data = fixture.data
            if !link {
                let name = Data("payload/android.jar".utf8)
                let replacement = Data(("../" + String(repeating: "x", count: name.count - 3)).utf8)
                while let range = data.range(of: name) { data.replaceSubrange(range, with: replacement) }
            }
            let runner = PayloadRunner(data: data)
            await #expect(throws: DomainError.self) {
                try await InstallationExecution.installSDKZip(pin(data, repo: fixture.repo), localMetadata: Data(), runner: runner)
            }
            #expect(!runner.extracted)
            #expect(!FileManager.default.fileExists(atPath: fixture.repo.url("sdk/platforms/android-36").path))
        }
    }

    @Test("cancellation and a newly occupied destination preserve completed and existing resources")
    func cancelledAndRaced() async throws {
        let fixture = try await archive()
        let metadata = pin(fixture.data, repo: fixture.repo)
        let cancelling = PayloadRunner(data: fixture.data, cancelDownload: true)
        let task = Task {
            try await InstallationExecution.installSDKZip(metadata, localMetadata: Data(), runner: cancelling)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!cancelling.extracted)
        let racing = PayloadRunner(data: fixture.data, occupied: metadata.destination)
        await #expect(throws: DomainError.self) {
            try await InstallationExecution.installSDKZip(metadata, localMetadata: Data(), runner: racing)
        }
        #expect(try String(contentsOf: metadata.destination.appendingPathComponent("owner"), encoding: .utf8) == "other operation")
    }

    private func pin(_ data: Data, repo: FixtureRepo, checksum: String? = nil) -> InstallationMetadata {
        InstallationMetadata(package: "platforms;android-36", revision: "2", destination: repo.url("sdk/platforms/android-36"), resourceRoot: repo.url("sdk"),
            artifact: InstallationArtifact(url: URL(string: "https://dl.google.com/android/repository/fixture.zip")!, checksumAlgorithm: "sha256",
                checksum: checksum ?? SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), size: Int64(data.count)),
            repositoryURL: URL(string: "https://dl.google.com/android/repository/repository2-3.xml")!, repositorySHA256: String(repeating: "a", count: 64),
            licenseID: "fixture-license", licenseSHA1: String(repeating: "b", count: 40), requiredFile: "android.jar")
    }

    private func archive(revision: String = "2", escapingLink: Bool = false, internalLink: Bool = false, metadataLink: Bool = false) async throws -> (repo: FixtureRepo, data: Data) {
        let repo = try FixtureRepo()
        try repo.write("sdk/licenses/fixture-license", String(repeating: "b", count: 40) + "\n")
        try repo.write("payload/source.properties", "Pkg.Revision=\(revision)\n")
        try repo.write("payload/android.jar", "fixture jar")
        if escapingLink { try FileManager.default.createSymbolicLink(atPath: repo.url("payload/link").path, withDestinationPath: "../../outside") }
        if internalLink { try FileManager.default.createSymbolicLink(atPath: repo.url("payload/alias.jar").path, withDestinationPath: "android.jar") }
        if metadataLink { try FileManager.default.createSymbolicLink(atPath: repo.url("payload/package.xml").path, withDestinationPath: "android.jar") }
        let result = try await SystemProcessRunner().run(ProcessCommand("zip", ["-q", "-r", "-y", repo.url("fixture.zip").path, "payload"], workingDirectory: repo.root))
        #expect(result.terminationStatus.isSuccess)
        return (repo, try Data(contentsOf: repo.url("fixture.zip")))
    }
}

private final class PayloadRunner: ProcessRunner, @unchecked Sendable {
    let data: Data
    let failExtraction: Bool
    let cancelDownload: Bool
    let occupied: URL?
    let revokedLicense: URL?
    private let lock = NSLock()
    private var didExtract = false
    private var downloaded: [URL] = []
    var downloadDestinations: [URL] { lock.withLock { downloaded } }
    var extracted: Bool { lock.withLock { didExtract } }
    init(data: Data, failExtraction: Bool = false, cancelDownload: Bool = false, occupied: URL? = nil, revokedLicense: URL? = nil) {
        self.data = data; self.failExtraction = failExtraction; self.cancelDownload = cancelDownload; self.occupied = occupied
        self.revokedLicense = revokedLicense
    }
    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        if command.executable == "curl", let index = command.arguments.firstIndex(of: "--output") {
            let destination = URL(fileURLWithPath: command.arguments[index + 1])
            lock.withLock { downloaded.append(destination) }
            try data.write(to: destination)
            if let revokedLicense { try FileManager.default.removeItem(at: revokedLicense) }
            if cancelDownload { withUnsafeCurrentTask { $0?.cancel() } }
            return ProcessResult(terminationStatus: .exited(0), standardOutput: "", standardError: "")
        }
        if command.executable == "unzip", command.arguments.first == "-q" {
            lock.withLock { didExtract = true }
            if failExtraction { return ProcessResult(terminationStatus: .exited(2), standardOutput: "", standardError: "fixture extraction failed") }
        }
        let result = try await SystemProcessRunner().run(command, onLine: onLine)
        if command.executable == "unzip", command.arguments.first == "-q", let occupied {
            try FileManager.default.createDirectory(at: occupied, withIntermediateDirectories: true)
            try Data("other operation".utf8).write(to: occupied.appendingPathComponent("owner"))
        }
        return result
    }
    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 { fatalError("Installation never spawns a detached process") }
}

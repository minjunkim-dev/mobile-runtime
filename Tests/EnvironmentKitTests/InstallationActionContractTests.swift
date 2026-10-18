import Core
import EnvironmentKit
import Foundation
import SimulatorKit
import TestSupport
import Testing

@Suite("preparation installation action compatibility")
struct InstallationActionContractTests {
    @Test("archive metadata keeps its JSON fields and original destination lease")
    func archiveCompatibility() throws {
        let metadata = archiveMetadata()
        let data = try JSONEncoder().encode(metadata)
        let document = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let artifact = try #require(document["artifact"] as? [String: Any])
        #expect(artifact["url"] as? String == "https://dl.google.com/android/repository/fixture.zip")
        #expect(artifact["checksumAlgorithm"] as? String == "sha256")
        #expect(artifact["checksum"] as? String == String(repeating: "a", count: 64))
        #expect(artifact["size"] as? Int == 12)
        #expect(document["managed"] == nil)
        #expect(metadata.resourceKeys == [metadata.resourceKey])
        #expect(try JSONDecoder().decode(InstallationMetadata.self, from: data) == metadata)
    }

    @Test("managed runtime identity omits fake archive values and locks every observed device")
    func managedIdentity() throws {
        let root = URL(fileURLWithPath: "/Library/Developer/CoreSimulator")
        let pin = runtimePin()
        let metadata = InstallationMetadata(package: "ios.runtime", revision: pin.build,
            destination: root, resourceRoot: root, managed: .iosRuntime(pin),
            repositoryURL: pin.catalogURL, repositorySHA256: pin.catalogSHA256, requiredFile: "")
        let data = try JSONEncoder().encode(metadata)
        let document = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(document["artifact"] == nil)
        #expect(document["managed"] != nil)
        #expect(metadata.inspectionLine.contains("payload checksum: unavailable"))
        #expect(metadata.inspectionLine.contains("catalog SHA-256"))
        #expect(metadata.resourceKeys.contains(.destination(root)))
        #expect(metadata.resourceKeys.contains(.destination(pin.deviceSet)))
        #expect(metadata.resourceKeys.contains(.device(.ios, "device-A")))
        #expect(metadata.resourceKeys.contains(.device(.ios, "device-B")))
        #expect(try JSONDecoder().decode(InstallationMetadata.self, from: data) == metadata)
    }

    @Test("legacy Void actions still recheck approval and return an empty resource result")
    func voidAction() async throws {
        let calls = ActionCalls()
        let action = InstallationAction(metadata: archiveMetadata(), operation: { _, _ in await calls.add() })
        let result = try await action.run(runner: FakeProcessRunner()) { _ in await calls.add() }
        #expect(result.resources.isEmpty)
        #expect(await calls.count == 2)
    }

    @Test("returning actions preserve the actual created identity and state")
    func returningAction() async throws {
        let resource = observedResource()
        let action = InstallationAction(metadata: archiveMetadata(), returning: { _, _ in
            InstallationActionResult(resources: [resource])
        })
        let result = try await action.run(runner: FakeProcessRunner()) { _ in }
        #expect(result.resources == [resource])
        #expect(result.resources.first?.identifier == "created-UDID")
        #expect(result.resources.first?.state == "Shutdown")
    }

    @Test("a failed final approval recheck prevents the provider operation")
    func failedRecheck() async throws {
        let calls = ActionCalls()
        let action = InstallationAction(metadata: archiveMetadata(), operation: { _, _ in await calls.add() })
        await #expect(throws: CancellationError.self) {
            try await action.run(runner: FakeProcessRunner()) { _ in throw CancellationError() }
        }
        #expect(await calls.count == 0)
    }

    @Test("missing or mixed artifact identities cannot start a provider operation", arguments: [false, true])
    func invalidIdentity(mixed: Bool) async throws {
        let archive = archiveMetadata()
        let invalid = InstallationMetadata(package: "fixture", revision: "1", destination: archive.destination,
            resourceRoot: archive.resourceRoot, artifact: mixed ? archive.artifact : nil,
            managed: mixed ? .iosRuntime(runtimePin()) : nil, requiredFile: "")
        let calls = ActionCalls()
        let action = InstallationAction(metadata: invalid, operation: { _, _ in await calls.add() })
        await #expect(throws: DomainError.self) {
            try await action.run(runner: FakeProcessRunner()) { _ in await calls.add() }
        }
        #expect(await calls.count == 0)
    }

    @Test("failure and cancellation retain completed resource observations", arguments: [false, true])
    func partialFailure(cancelled: Bool) async throws {
        let resource = observedResource()
        let error: any Error = cancelled ? CancellationError() : POSIXError(.EIO)
        let action = InstallationAction(metadata: archiveMetadata(), returning: { _, _ in
            throw InstallationActionFailure(underlying: error, result: InstallationActionResult(resources: [resource]))
        })
        do {
            _ = try await action.run(runner: FakeProcessRunner()) { _ in }
            Issue.record("expected the provider failure")
        } catch let failure as InstallationActionFailure {
            #expect(failure.underlying is CancellationError == cancelled)
            #expect(failure.result.resources == [resource])
        }
    }

    private func archiveMetadata() -> InstallationMetadata {
        InstallationMetadata(package: "fixture", revision: "1", destination: URL(fileURLWithPath: "/fixture/sdk/package"),
            resourceRoot: URL(fileURLWithPath: "/fixture/sdk"),
            artifact: InstallationArtifact(url: URL(string: "https://dl.google.com/android/repository/fixture.zip")!,
                checksumAlgorithm: "sha256", checksum: String(repeating: "a", count: 64), size: 12),
            repositoryURL: URL(string: "https://dl.google.com/android/repository/repository2-3.xml")!,
            repositorySHA256: String(repeating: "b", count: 64), requiredFile: "source.properties")
    }

    private func runtimePin() -> IOSRuntimePin {
        IOSRuntimePin(identifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-0", version: "27.0", build: "24A434",
            architecture: "arm64", assetIdentifier: "official-fixture-asset", downloadSize: 12,
            catalogURL: URL(string: "https://devimages-cdn.apple.com/downloads/xcode/simulators/index2.dvtdownloadableindex")!,
            catalogSHA256: String(repeating: "c", count: 64), developerDirectory: "/test/Xcode",
            xcodeVersion: "27.0", xcodeBuild: "18A100",
            existingDeviceIDs: ["device-B", "device-A"], deviceSet: URL(fileURLWithPath: "/fixture/Devices"))
    }

    private func observedResource() -> IOSPreparationResource {
        IOSPreparationResource(kind: .simulator, identifier: "created-UDID", name: "Runstir iPhone",
            runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-0", runtimeBuild: "24A434", version: "27.0",
            architecture: "arm64", deviceTypeIdentifier: "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
            state: "Shutdown", isAvailable: true, origin: .created)
    }
}

private actor ActionCalls {
    private(set) var count = 0
    func add() { count += 1 }
}

import Core
import Foundation
import TestSupport
import Testing
@testable import SimulatorKit

@Suite("iOS resource identity and preparation selection")
struct IOSResourcePreparationTests {
    private let xcode = XcodeInstallation(version: "27.0", build: "18A100", developerDirectory: "/fixture/Xcode", origin: .developerDirEnvironment)
    private let deviceSet = URL(fileURLWithPath: "/fixture/home/Library/Developer/CoreSimulator/Devices")

    @Test("official metadata keeps OS build, architecture and asset identity separate from its digest")
    func catalogPin() throws {
        let catalog = try IOSRuntimeCatalog(data: catalogData())
        let pin = try catalog.pin(version: "27.0", architecture: "arm64", xcode: xcode, existingDeviceIDs: [], deviceSet: deviceSet)
        #expect(pin.version == "27.0" && pin.build == "24A434")
        #expect(pin.architecture == "arm64")
        #expect(pin.assetIdentifier == "fixture-final")
        #expect(pin.catalogSHA256.count == 64)
        #expect(pin.catalogSHA256 != pin.assetIdentifier)
        #expect(pin.developerDirectory == xcode.developerDirectory)
        #expect(pin.downloadSize == 12)
    }

    @Test("a missing, ambiguous, beta or wrong-architecture artifact never becomes latest", arguments: ["missing", "ambiguous", "beta", "architecture"])
    func invalidCatalog(mode: String) throws {
        var entries = [catalogEntry()]
        switch mode {
        case "missing": entries = []
        case "ambiguous": entries.append(catalogEntry(build: "24A999"))
        case "beta": entries[0]["name"] = "iOS 27.0 beta Simulator Runtime"
        default: entries[0]["architectures"] = ["x86_64"]
        }
        let catalog = try IOSRuntimeCatalog(data: catalogData(entries: entries))
        #expect(throws: DomainError.self) {
            try catalog.pin(version: "27.0", architecture: "arm64", xcode: xcode, existingDeviceIDs: [], deviceSet: deviceSet)
        }
    }

    @Test("captured installed resource identities use the existing booted-device preference")
    func capturedReuse() async throws {
        let inventory = try await load(devices: Fixture.text("simctl-list-devices.stdout.json"))
        let selected = try #require(inventory.existing(minimum: MinimumVersion("26.0")!, architecture: "arm64", declared: nil))
        #expect(selected.identifier == "61DECACB-3D94-4748-B5A2-E7A1EB97E6D5")
        let resource = inventory.resource(selected, architecture: "arm64", origin: .reused)
        #expect(resource.state == "Booted")
        #expect(resource.runtimeBuild == "23F77")
        #expect(resource.deviceTypeIdentifier == "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro")
    }

    @Test("a renamed Shutdown iPhone is reused by its measured device type")
    func renamedDevice() async throws {
        let devices = #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-5":[{"udid":"B38C3447-963B-42CB-959F-F5234F5A1092","name":"Personal Simulator","deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-17","state":"Shutdown","isAvailable":true}]}}"#
        let inventory = try await load(devices: devices)
        let selected = try #require(inventory.existing(minimum: MinimumVersion("26.0")!, architecture: "arm64", declared: nil))
        #expect(selected.name == "Personal Simulator")
        #expect(selected.identifier == "B38C3447-963B-42CB-959F-F5234F5A1092")
    }

    @Test("creation uses measured device type bounds and does not boot a device")
    func creationSelection() async throws {
        let inventory = try await load(devices: #"{"devices":{}}"#)
        let request = try inventory.creation(runtimeID: "com.apple.CoreSimulator.SimRuntime.iOS-26-5", version: "26.5",
            build: "23F77", architecture: "arm64", declared: nil, xcode: xcode, deviceSet: deviceSet)
        #expect(request.deviceTypeIdentifier == "com.apple.CoreSimulator.SimDeviceType.iPhone-17")
        #expect(request.runtimeBuild == "23F77")
        #expect(request.name == "iPhone 17 - Runstir - iOS 26.5")
        #expect(request.deviceSet == deviceSet)
    }

    @Test("an existing unavailable name is preserved instead of being replaced")
    func nameCollision() async throws {
        let devices = #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-5":[{"udid":"B38C3447-963B-42CB-959F-F5234F5A1092","name":"iPhone 17 - Runstir - iOS 26.5","deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-17","state":"Creating","isAvailable":false}]}}"#
        let inventory = try await load(devices: devices)
        #expect(throws: DomainError.self) {
            try inventory.creation(runtimeID: "com.apple.CoreSimulator.SimRuntime.iOS-26-5", version: "26.5", build: "23F77",
                architecture: "arm64", declared: nil, xcode: xcode, deviceSet: deviceSet)
        }
    }

    @Test("a missing architecture or build cannot be reused as verified compatible")
    func unknownIdentity() async throws {
        let runner = FakeProcessRunner(responses: [
            "xcrun simctl list runtimes -j": .ok(#"{"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-0","version":"27.0","name":"iOS 27.0","isAvailable":true}]}"#),
            "xcrun simctl --set \(deviceSet.path) list devices -j": .ok(#"{"devices":{}}"#),
            "xcrun simctl list devicetypes -j": .ok(try Fixture.text("simctl-list-devicetypes.stdout.json")),
        ])
        let inventory = try await IOSResourceInventory.load(runner: runner, environment: ["DEVELOPER_DIR": xcode.developerDirectory], deviceSet: deviceSet)
        #expect(inventory.compatibleRuntimes(minimum: MinimumVersion("26.0")!, architecture: "arm64").isEmpty)
        #expect(!runner.log.all.contains { $0.arguments.contains("create") || $0.arguments.contains("boot") })
    }

    private func load(devices: String) async throws -> IOSResourceInventory {
        let runner = FakeProcessRunner(responses: [
            "xcrun simctl list runtimes -j": .ok(try Fixture.text("simctl-list-runtimes.stdout.json")),
            "xcrun simctl --set \(deviceSet.path) list devices -j": .ok(devices),
            "xcrun simctl list devicetypes -j": .ok(try Fixture.text("simctl-list-devicetypes.stdout.json")),
        ])
        return try await IOSResourceInventory.load(runner: runner, environment: ["DEVELOPER_DIR": xcode.developerDirectory], deviceSet: deviceSet)
    }

    private func catalogEntry(build: String = "24A434") -> [String: Any] {
        ["platform": "com.apple.platform.iphoneos", "downloadMethod": "mobileAsset", "contentType": "cryptexDiskImage",
         "dictionaryVersion": 2, "identifier": "fixture-final", "name": "iOS 27.0 Simulator Runtime",
         "simulatorVersion": ["version": "27.0", "buildUpdate": build], "architectures": ["arm64"], "fileSize": Int64(12)]
    }

    private func catalogData(entries: [[String: Any]]? = nil) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: ["downloadables": entries ?? [catalogEntry()]], format: .xml, options: 0)
    }
}

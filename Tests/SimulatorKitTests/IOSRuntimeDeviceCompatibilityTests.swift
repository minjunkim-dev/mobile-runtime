import Core
import Foundation
import TestSupport
import Testing
@testable import SimulatorKit

@Suite("Native runtime device-type compatibility")
struct IOSRuntimeDeviceCompatibilityTests {
    private let duo = "com.apple.CoreSimulator.SimDeviceType.iPhone-Duo"
    private let pro = "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro"
    private let ipad = "com.apple.CoreSimulator.SimDeviceType.iPad-Pro"
    private let runtimeID = "com.apple.CoreSimulator.SimRuntime.iOS-27-1"
    private let xcode = XcodeInstallation(version: "27.1", build: "27A9275", developerDirectory: "/fixture/Xcode", origin: .developerDirEnvironment)
    private let deviceSet = URL(fileURLWithPath: "/fixture/home/Library/Developer/CoreSimulator/Devices")

    @Test("captured 27.1 Duo-only support overrides permissive OS bounds and newest-name ranking")
    func capturedDuoOnlyRuntime() async throws {
        let inventory = try await load(support: [["identifier": duo]])
        let request = try create(inventory)
        #expect(request.deviceTypeIdentifier == duo)
        #expect(request.runtimeIdentifier == runtimeID)
        #expect(request.runtimeBuild == "24A94425")
        #expect(request.name == "iPhone Duo - Runstir - iOS 27.1")
    }

    @Test("declared Pro cannot create on the Duo-only runtime")
    func unsupportedDeclaredPhone() async throws {
        let inventory = try await load(support: [["identifier": duo]])
        #expect(throws: DomainError.self) { try create(inventory, declared: "iPhone 18 Pro") }
        #expect(try create(inventory, declared: "iPhone Duo").deviceTypeIdentifier == duo)
    }

    @Test("each runtime uses its own native support and never borrows another runtime's list")
    func crossRuntimeSupport() async throws {
        let inventory = try await load(support: [["identifier": duo]], olderRuntime: true)
        let old = try inventory.creation(runtimeID: "com.apple.CoreSimulator.SimRuntime.iOS-27-0", version: "27.0",
            build: "24A434", architecture: "arm64", declared: nil, xcode: xcode, deviceSet: deviceSet)
        #expect(old.deviceTypeIdentifier == pro)
        #expect(try create(inventory).deviceTypeIdentifier == duo)
        #expect(throws: DomainError.self) { try create(inventory, declared: "iPhone 18 Pro") }
    }

    @Test("creation compatibility cannot be borrowed for a different runtime identity", arguments: [
        "missing-runtime", "version", "build", "architecture",
    ])
    func mismatchedRuntimeIdentity(field: String) async throws {
        let inventory = try await load(support: [["identifier": duo]])
        #expect(throws: DomainError.self) {
            try inventory.creation(runtimeID: field == "missing-runtime" ? "com.apple.CoreSimulator.SimRuntime.iOS-27-0" : runtimeID,
                version: field == "version" ? "27.0" : "27.1", build: field == "build" ? "24A434" : "24A94425",
                architecture: field == "architecture" ? "x86_64" : "arm64", declared: nil, xcode: xcode, deviceSet: deviceSet)
        }
    }

    @Test("missing, empty or malformed support blocks creation while native availability and existing reuse remain usable", arguments: [
        "missing", "empty", "wrong-type", "missing-id", "wrong-id-type", "empty-id", "foreign-id", "duplicate", "heterogeneous",
    ])
    func unknownCompatibility(mode: String) async throws {
        let support: Any?
        switch mode {
        case "missing": support = nil
        case "empty": support = [] as [String]
        case "wrong-type": support = "not an array"
        case "missing-id": support = [["name": "iPhone Duo"]]
        case "wrong-id-type": support = [["identifier": 1]]
        case "empty-id": support = [["identifier": ""]]
        case "foreign-id": support = [["identifier": "foreign.device"]]
        case "duplicate": support = [["identifier": duo], ["identifier": duo]]
        default: support = [["identifier": duo], "not a device type"] as [Any]
        }
        let inventory = try await load(support: support, existing: true)
        #expect(inventory.compatibleRuntimes(minimum: MinimumVersion("27.0")!, architecture: "arm64").count == 1)
        #expect(inventory.existing(minimum: MinimumVersion("27.0")!, architecture: "arm64", declared: nil)?.identifier ==
            "B38C3447-963B-42CB-959F-F5234F5A1092")
        #expect(throws: DomainError.self) { try create(inventory) }
    }

    @Test("native support still requires the selected device type's OS bounds")
    func nativeSupportDoesNotOverrideBounds() async throws {
        let inventory = try await load(support: [["identifier": duo]], duoMinimum: "27.2")
        #expect(throws: DomainError.self) { try create(inventory) }
        #expect(throws: DomainError.self) { try create(inventory, declared: "iPhone Duo") }
    }

    @Test("the default keeps the existing phone-family selector after native filtering")
    func defaultRemainsPhoneOnly() async throws {
        let inventory = try await load(support: [["identifier": duo], ["identifier": ipad]])
        #expect(try create(inventory).deviceTypeIdentifier == duo)
    }

    @Test("an explicit supported iPad retains the existing declared-device contract")
    func declaredSupportedTablet() async throws {
        let inventory = try await load(support: [["identifier": ipad]])
        #expect(try create(inventory, declared: "iPad Pro").deviceTypeIdentifier == ipad)
        #expect(throws: DomainError.self) { try create(inventory) }
    }

    private func create(_ inventory: IOSResourceInventory, declared: String? = nil) throws -> IOSSimulatorRequest {
        try inventory.creation(runtimeID: runtimeID, version: "27.1", build: "24A94425", architecture: "arm64",
            declared: declared, xcode: xcode, deviceSet: deviceSet)
    }

    private func load(support: Any?, existing: Bool = false, olderRuntime: Bool = false,
                      duoMinimum: String = "27.0") async throws -> IOSResourceInventory {
        // The observed 27.1/24A94425 runtime reports only iPhone-Duo. Deliberately
        // permissive synthetic type bounds isolate the native support constraint.
        var runtime: [String: Any] = ["identifier": runtimeID, "name": "iOS 27.1", "version": "27.1",
            "buildversion": "24A94425", "supportedArchitectures": ["arm64"], "isAvailable": true]
        if let support { runtime["supportedDeviceTypes"] = support }
        var runtimes = [runtime]
        if olderRuntime {
            runtimes.append(["identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-0", "name": "iOS 27.0",
                "version": "27.0", "buildversion": "24A434", "supportedArchitectures": ["arm64"], "isAvailable": true,
                "supportedDeviceTypes": [["identifier": pro]]])
        }
        let devices: [String: [[String: Any]]] = existing ? [runtimeID: [[
            "udid": "B38C3447-963B-42CB-959F-F5234F5A1092", "name": "iPhone 18 Pro", "deviceTypeIdentifier": pro,
            "state": "Shutdown", "isAvailable": true]]] : [:]
        let types: [[String: Any]] = [
            ["identifier": pro, "name": "iPhone 18 Pro", "productFamily": "iPhone",
             "minRuntimeVersionString": "27.0", "maxRuntimeVersionString": "27.255.255"],
            ["identifier": duo, "name": "iPhone Duo", "productFamily": "iPhone",
             "minRuntimeVersionString": duoMinimum, "maxRuntimeVersionString": "27.255.255"],
            ["identifier": ipad, "name": "iPad Pro", "productFamily": "iPad",
             "minRuntimeVersionString": "27.0", "maxRuntimeVersionString": "27.255.255"],
        ]
        func json(_ value: [String: Any]) throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
        }
        let runner = FakeProcessRunner(responses: [
            "xcrun simctl list runtimes -j": .ok(try json(["runtimes": runtimes])),
            "xcrun simctl --set \(deviceSet.path) list devices -j": .ok(try json(["devices": devices])),
            "xcrun simctl list devicetypes -j": .ok(try json(["devicetypes": types])),
        ])
        return try await IOSResourceInventory.load(runner: runner, environment: ["DEVELOPER_DIR": xcode.developerDirectory], deviceSet: deviceSet)
    }
}

import Foundation

/// Apple's catalog identity. Its digest is not a payload checksum.
public struct IOSRuntimePin: Codable, Sendable, Equatable {
    public let identifier: String
    public let version: String
    public let build: String
    public let architecture: String
    public let assetIdentifier: String
    public let downloadSize: Int64
    public let catalogURL: URL
    public let catalogSHA256: String
    public let developerDirectory: String
    public let xcodeVersion: String
    public let xcodeBuild: String
    /// Import requires every observed device to remain Shutdown under its device lease.
    public let existingDeviceIDs: [String]
    public let deviceSet: URL

    public init(identifier: String, version: String, build: String, architecture: String,
                assetIdentifier: String, downloadSize: Int64, catalogURL: URL, catalogSHA256: String,
                developerDirectory: String, xcodeVersion: String, xcodeBuild: String,
                existingDeviceIDs: [String], deviceSet: URL) {
        self.identifier = identifier; self.version = version; self.build = build
        self.architecture = architecture; self.assetIdentifier = assetIdentifier; self.downloadSize = downloadSize
        self.catalogURL = catalogURL; self.catalogSHA256 = catalogSHA256; self.developerDirectory = developerDirectory
        self.xcodeVersion = xcodeVersion; self.xcodeBuild = xcodeBuild
        self.existingDeviceIDs = existingDeviceIDs.sorted(); self.deviceSet = deviceSet
    }
}

public struct IOSSimulatorRequest: Codable, Sendable, Equatable {
    public let name: String
    public let deviceTypeIdentifier: String
    public let runtimeIdentifier: String
    public let runtimeVersion: String
    public let runtimeBuild: String
    public let architecture: String
    public let developerDirectory: String
    public let xcodeVersion: String
    public let xcodeBuild: String
    public let deviceSet: URL

    public init(name: String, deviceTypeIdentifier: String, runtimeIdentifier: String,
                runtimeVersion: String, runtimeBuild: String, architecture: String,
                developerDirectory: String, xcodeVersion: String, xcodeBuild: String, deviceSet: URL) {
        self.name = name; self.deviceTypeIdentifier = deviceTypeIdentifier
        self.runtimeIdentifier = runtimeIdentifier; self.runtimeVersion = runtimeVersion
        self.runtimeBuild = runtimeBuild; self.architecture = architecture
        self.developerDirectory = developerDirectory; self.deviceSet = deviceSet
        self.xcodeVersion = xcodeVersion; self.xcodeBuild = xcodeBuild
    }
}

/// Observations survive partial completion. Unknown identities are never invented.
public struct IOSPreparationResource: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case runtime, simulator }
    public enum Origin: String, Codable, Sendable { case installed, created, reused, unknown }
    public let kind: Kind
    public let identifier: String?
    public let name: String?
    public let runtimeIdentifier: String
    public let runtimeBuild: String?
    public let version: String?
    public let architecture: String?
    public let deviceTypeIdentifier: String?
    /// Runtime availability or the Simulator's actual state, such as Shutdown.
    public let state: String
    public let isAvailable: Bool?
    public let origin: Origin

    public init(kind: Kind, identifier: String?, name: String? = nil, runtimeIdentifier: String,
                runtimeBuild: String?, version: String?, architecture: String?, deviceTypeIdentifier: String? = nil,
                state: String, isAvailable: Bool?, origin: Origin) {
        self.kind = kind; self.identifier = identifier; self.name = name
        self.runtimeIdentifier = runtimeIdentifier; self.runtimeBuild = runtimeBuild
        self.version = version; self.architecture = architecture; self.deviceTypeIdentifier = deviceTypeIdentifier
        self.state = state; self.isAvailable = isAvailable; self.origin = origin
    }
}

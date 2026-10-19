import Foundation

/// Approval binds the canonical input path and its current physical file identity.
public struct AppFileIdentity: Codable, Sendable, Hashable {
    public let path: String
    public let volume: UInt64
    public let file: UInt64

    public init(url: URL) throws {
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        let values = try FileManager.default.attributesOfItem(atPath: resolved.path)
        guard let kind = values[.type] as? FileAttributeType,
              [.typeRegular, .typeDirectory].contains(kind),
              let volume = values[.systemNumber] as? NSNumber,
              let file = values[.systemFileNumber] as? NSNumber else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        path = resolved.path
        self.volume = volume.uint64Value
        self.file = file.uint64Value
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.volume == rhs.volume && lhs.file == rhs.file
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(volume)
        hasher.combine(file)
    }
}

public struct AppFileMetadata: Codable, Sendable, Equatable {
    public let platform: ProjectPlatform
    public let appID: String
    public let name: String?
    public let version: String?
    public let build: String
    public let architectures: [String]
    public let minimumOS: String
    public let launcherActivity: String?
    public let signatureCondition: String
    public let signingIdentity: String?

    public init(platform: ProjectPlatform, appID: String, name: String?, version: String?, build: String,
                architectures: [String], minimumOS: String, launcherActivity: String? = nil,
                signatureCondition: String, signingIdentity: String? = nil) {
        self.platform = platform
        self.appID = appID
        self.name = name.flatMap { $0.isEmpty ? nil : $0 }
        self.version = version.flatMap { $0.isEmpty ? nil : $0 }
        self.build = build
        self.architectures = architectures.sorted()
        self.minimumOS = minimumOS
        self.launcherActivity = launcherActivity
        self.signatureCondition = signatureCondition
        self.signingIdentity = signingIdentity
    }
}

public struct AppFileArtifact: Codable, Sendable, Equatable {
    public let file: AppFileIdentity
    public let contentIdentity: String
    public let contentIdentityAlgorithm: String
    public let metadata: AppFileMetadata
    public let origin: String

    public init(file: AppFileIdentity, contentIdentity: String, metadata: AppFileMetadata) {
        self.file = file
        self.contentIdentity = contentIdentity
        contentIdentityAlgorithm = URL(fileURLWithPath: file.path).pathExtension == "app" ? "sha256-tree-v1" : "sha256"
        self.metadata = metadata
        origin = "user-selected-file"
    }
}

public struct AppFileDevice: Codable, Sendable, Equatable {
    /// Same device identity as project workflows, including avd:<name> on Android.
    public let id: String
    public let handle: String
    public let name: String
    public let os: String
    public let architectures: [String]
    public let ready: Bool
    public let toolIdentity: String

    public init(id: String, handle: String, name: String, os: String, architectures: [String],
                ready: Bool, toolIdentity: String) {
        self.id = id
        self.handle = handle
        self.name = name
        self.os = os
        self.architectures = architectures.sorted()
        self.ready = ready
        self.toolIdentity = toolIdentity
    }
}

public struct AppFileInstalledState: Codable, Sendable, Equatable {
    public let state: String
    public let version: String?
    public let build: String?
    public let location: String?
    public let detail: String?

    public init(state: String, version: String? = nil, build: String? = nil,
                location: String? = nil, detail: String? = nil) {
        self.state = state
        self.version = version
        self.build = build
        self.location = location
        self.detail = detail
    }
}

public struct AppFilePlan: Codable, Sendable {
    public let id: String
    public let artifact: AppFileArtifact
    public let device: AppFileDevice
    public let installed: AppFileInstalledState
    public let replacement: Bool
    public let downgrade: Bool
    public let warnings: [String]
    public let approval: String

    public init(id: String, artifact: AppFileArtifact, device: AppFileDevice,
                installed: AppFileInstalledState, replacement: Bool, downgrade: Bool, warnings: [String]) {
        self.id = id
        self.artifact = artifact
        self.device = device
        self.installed = installed
        self.replacement = replacement
        self.downgrade = downgrade
        self.warnings = warnings
        approval = downgrade ? "DOWNGRADE:" + id : id
    }
}

public struct AppFileOperation: Codable, Sendable {
    public let id: String
    public let command: String
    public var state = "inspecting"
    public var artifact: AppFileArtifact?
    public var devices: [AppFileDevice] = []
    public var plan: AppFilePlan?
    public var requiredInput: [String] = []
    public var completed: [String] = []
    public var installation = "not-requested"
    public var installed: AppFileInstalledState?
    public var launch = "not-requested"
    public var running = "not-observed"
    public let firstScreen: String
    public let externalServer: String
    public var error: String?
    public var nextAction: String?
    public var conflict: ResourceConflict?

    public init(id: String, command: String) {
        self.id = id
        self.command = command
        firstScreen = "unverified"
        externalServer = "unverified; Runstir did not start or connect a development server"
    }
}

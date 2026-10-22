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
    /// Physical iOS builds only; Simulator and Android files have none.
    public let provisioning: AppFileProvisioning?

    public init(platform: ProjectPlatform, appID: String, name: String?, version: String?, build: String,
                architectures: [String], minimumOS: String, launcherActivity: String? = nil,
                signatureCondition: String, signingIdentity: String? = nil, provisioning: AppFileProvisioning? = nil) {
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
        self.provisioning = provisioning
    }
}

/// Facts read from a physical iOS app's embedded Development or Ad Hoc profile and
/// signature. Runstir checks them; it never registers devices or re-signs the app.
public struct AppFileProvisioning: Codable, Sendable, Equatable {
    public let kind: String
    public let profileUUID: String
    public let profileName: String?
    public let teamID: String
    public let applicationIdentifier: String
    /// ISO 8601.
    public let expiration: String
    /// Kept out of JSON and evidence: only the count and the selected device's membership are reported.
    public private(set) var provisionedDevices: [String] = []
    public let provisionedDeviceCount: Int
    public let signatureVerified: Bool
    public let signingTeamID: String?
    public let signingCertificateInProfile: Bool

    private enum CodingKeys: String, CodingKey {
        case kind, profileUUID, profileName, teamID, applicationIdentifier, expiration, provisionedDeviceCount,
             signatureVerified, signingTeamID, signingCertificateInProfile
    }

    public init(kind: String, profileUUID: String, profileName: String?, teamID: String,
                applicationIdentifier: String, expiration: String, provisionedDevices: [String],
                signatureVerified: Bool, signingTeamID: String?, signingCertificateInProfile: Bool) {
        self.kind = kind
        self.profileUUID = profileUUID
        self.profileName = profileName
        self.teamID = teamID
        self.applicationIdentifier = applicationIdentifier
        self.expiration = expiration
        self.provisionedDevices = provisionedDevices
        provisionedDeviceCount = provisionedDevices.count
        self.signatureVerified = signatureVerified
        self.signingTeamID = signingTeamID
        self.signingCertificateInProfile = signingCertificateInProfile
    }
}

/// One observable installation condition. Anything but `satisfied` names a manual action.
public struct AppFilePrerequisite: Codable, Sendable, Equatable {
    public let id: String
    public let state: String
    public let observed: String
    public let action: String?

    public init(id: String, satisfied: Bool?, observed: String, action: String) {
        self.id = id
        state = satisfied.map { $0 ? "satisfied" : "unsatisfied" } ?? "unknown"
        self.observed = observed
        self.action = satisfied == true ? nil : action
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
    /// Platform capability set: runtime slices on iOS, advertised ABIs on Android.
    /// This is not a measurement of the virtual device's current CPU.
    public let architectures: [String]
    public let ready: Bool
    public let toolIdentity: String
    public let runtimeIdentifier: String?
    public let runtimeBuild: String?
    public let runtimeAvailable: Bool?
    public let architectureSource: String?
    /// Physical devices only, as CoreDevice reports them.
    public let pairing: String?
    public let developerMode: String?
    public let connection: String?

    public init(id: String, handle: String, name: String, os: String, architectures: [String],
                ready: Bool, toolIdentity: String, runtimeIdentifier: String? = nil,
                runtimeBuild: String? = nil, runtimeAvailable: Bool? = nil, architectureSource: String? = nil,
                pairing: String? = nil, developerMode: String? = nil, connection: String? = nil) {
        self.id = id
        self.handle = handle
        self.name = name
        self.os = os
        self.architectures = architectures.sorted()
        self.ready = ready
        self.toolIdentity = toolIdentity
        self.runtimeIdentifier = runtimeIdentifier
        self.runtimeBuild = runtimeBuild
        self.runtimeAvailable = runtimeAvailable
        self.architectureSource = architectureSource
        self.pairing = pairing
        self.developerMode = developerMode
        self.connection = connection
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
    public let buildOrderUnknown: Bool
    public let warnings: [String]
    public let approval: String

    public var requiresRiskApproval: Bool { downgrade || buildOrderUnknown }

    public init(id: String, artifact: AppFileArtifact, device: AppFileDevice,
                installed: AppFileInstalledState, replacement: Bool, downgrade: Bool,
                buildOrderUnknown: Bool = false, warnings: [String]) {
        self.id = id
        self.artifact = artifact
        self.device = device
        self.installed = installed
        self.replacement = replacement
        self.downgrade = downgrade
        self.buildOrderUnknown = buildOrderUnknown
        self.warnings = warnings
        approval = (downgrade || buildOrderUnknown) ? "DOWNGRADE:" + id : id
    }
}

public struct AppFileOperation: Codable, Sendable {
    public let id: String
    public let command: String
    public var state = "inspecting"
    public var artifact: AppFileArtifact?
    public var devices: [AppFileDevice] = []
    public var plan: AppFilePlan?
    /// The selected physical iOS device's checked conditions; absent for virtual devices.
    public var prerequisites: [AppFilePrerequisite]?
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

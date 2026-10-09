import Foundation

public enum WorkflowKind: String, Codable, Sendable {
    case build, up, down
}

public struct RuntimeDeviceCandidate: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let detail: String

    public init(id: String, name: String, detail: String) {
        self.id = id
        self.name = name
        self.detail = detail
    }
}

public struct WorkflowOperation: Codable, Sendable {
    public let id: String
    public let kind: WorkflowKind
    public var state: String
    public var selection: ProjectSelection?
    public var device: String?
    public var scheme: String?
    public var configuration: String?
    public var module: String?
    public var variant: String?
    public var requiredInput: [String] = []
    public var devices: [RuntimeDeviceCandidate] = []
    public var schemes: [String] = []
    public var configurations: [String] = []
    public var modules: [String] = []
    public var variants: [String] = []
    public var completed: [String] = []
    public var remaining: [String] = []
    public var nextAction: String?

    public init(id: String, kind: WorkflowKind, state: String) {
        self.id = id
        self.kind = kind
        self.state = state
    }
}

public struct WorkflowEvent: Encodable, Sendable {
    public let schemaVersion = 1
    public let operationId: String
    public let sequence: Int
    public let kind: String
    public let stageId: String?
    public let state: String
    public let detail: String?

    public init(operationId: String, sequence: Int, kind: String, stageId: String? = nil,
                state: String, detail: String? = nil) {
        self.operationId = operationId
        self.sequence = sequence
        self.kind = kind
        self.stageId = stageId
        self.state = state
        self.detail = detail
    }

    public func encoded() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}

import Core
import EnvironmentKit
import Foundation
import Logging

typealias Wiring = WorkflowContext

extension WorkflowContext {
    static func bootstrap(
        verbose: Bool,
        platform: MobilePlatform = .ios,
        includeProjectEnvironment: Bool = true,
        includeRuntimeSDKTools: Bool = true
    ) async -> WorkflowContext {
        bootstrapLogging(verbose: verbose)
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let environment = ProcessInfo.processInfo.environment
        return await make(
            input: ProjectInspectionInput(directory: directory, environment: environment),
            platform: platform == .ios ? .ios : .android,
            anchor: ProjectAnchor.detect(from: directory),
            runner: SystemProcessRunner(),
            includeProjectEnvironment: includeProjectEnvironment,
            includeRuntimeSDKTools: includeRuntimeSDKTools
        )
    }
}

func bootstrapLogging(verbose: Bool) {
    LoggingSystem.bootstrap { label in
        var handler = StreamLogHandler.standardError(label: label)
        handler.logLevel = verbose ? .debug : .info
        return handler
    }
}

func writeError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

enum Terminal {
    static var supportsColor: Bool {
        guard ProcessInfo.processInfo.environment["NO_COLOR"] == nil else { return false }
        return isatty(FileHandle.standardOutput.fileDescriptor) == 1
    }
}

import Foundation
import Logging

func bootstrapLogging(verbose: Bool, silent: Bool = false) {
    LoggingSystem.bootstrap { label in
        if silent { return SwiftLogNoOpLogHandler() }
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

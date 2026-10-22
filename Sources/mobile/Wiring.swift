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

/// Interrupt, terminate and a closed terminal cancel `operation`, so its cleanup runs before the process exits.
func cancellingOnSignals<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    let task = Task { try await operation() }
    let previous = [SIGINT, SIGTERM, SIGHUP].map { ($0, signal($0, SIG_IGN)) }
    let sources = previous.map { number, _ in
        let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
        source.setEventHandler { task.cancel() }
        source.resume()
        return source
    }
    defer {
        sources.forEach { $0.cancel() }
        for (number, handler) in previous { signal(number, handler) }
    }
    return try await task.value
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

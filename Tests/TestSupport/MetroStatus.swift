import Core
import Foundation

/// The `/status` question and its answers, spelled once. Three test targets ask 8081
/// the same way `MetroVerdict` does, and a fixture that drifts from the command it
/// answers is a test that passes without exercising anything.
public enum MetroStatus {
    public static let processTableCommand = "ps -axo pid=,ppid=,lstart="

    /// A manager, its shell and the actual listening Node are distinct processes.
    public static func startupResponses(
        projectRoot: URL, startPID: Int32 = 4242, listenerPID: Int32 = 70947, port: Int = 8081
    ) -> [String: FakeProcessRunner.Response] {
        let shell = startPID + 1
        let tree = "\(startPID) 1 Mon Oct 19 17:00:00 2026\n"
            + "\(shell) \(startPID) Mon Oct 19 17:00:01 2026\n"
            + "\(listenerPID) \(shell) Mon Oct 19 17:00:02 2026\n"
        let pids = [startPID, shell, listenerPID].sorted().map(String.init).joined(separator: ",")
        let rootAndListener = [startPID, listenerPID].sorted().map(String.init).joined(separator: ",")
        return [
            processTableCommand: .ok(tree),
            "lsof -a -p \(pids) -nP -iTCP:\(port) -sTCP:LISTEN -t": .ok("\(listenerPID)\n"),
            "lsof -a -p \(listenerPID) -nP -iTCP:\(port) -sTCP:LISTEN -t": .ok("\(listenerPID)\n"),
            "lsof -a -p \(startPID) -d cwd -Fpn": .ok("p\(startPID)\nfcwd\nn\(projectRoot.path)\n"),
            "lsof -a -p \(rootAndListener) -d cwd -Fpn": .ok(
                "p\(startPID)\nfcwd\nn\(projectRoot.path)\np\(listenerPID)\nfcwd\nn\(projectRoot.path)\n"
            ),
        ]
    }

    /// The status endpoint changes from empty to mine only after the recorded
    /// spawn. Binding can be delayed without changing production timeouts.
    public actor StartingRunner: ProcessRunner {
        private let inner: FakeProcessRunner
        private let root: URL
        private let bindDelay: Duration
        private let listenerPID: Int32
        private let port: Int
        private var spawnedAt: ContinuousClock.Instant?
        public nonisolated let log: FakeProcessRunner.CallLog
        public nonisolated let spawnedPID: Int32

        public init(
            _ inner: FakeProcessRunner, projectRoot: URL, bindDelay: Duration = .zero,
            listenerPID: Int32 = 70947, port: Int = 8081
        ) {
            var inner = inner
            inner.responses.merge(MetroStatus.startupResponses(projectRoot: projectRoot, startPID: inner.spawnedPID,
                listenerPID: listenerPID, port: port)) { existing, _ in existing }
            self.inner = inner
            self.root = projectRoot
            self.bindDelay = bindDelay
            self.listenerPID = listenerPID
            self.port = port
            self.log = inner.log
            self.spawnedPID = inner.spawnedPID
        }

        public func run(
            _ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?
        ) async throws -> ProcessResult {
            var response = inner
            if let spawnedAt {
                if command.executable == "lsof", command.arguments.contains("-p"), command.arguments.contains("-t") {
                    response.responses[command.description] = ContinuousClock.now >= spawnedAt + bindDelay
                        ? .ok("\(listenerPID)\n") : .failed(1, "")
                } else if command.description == "curl -s -i -m 2 http://localhost:\(port)/status" {
                    response.responses[command.description] = .ok(MetroStatus.running(projectRoot: root))
                }
            }
            return try await response.run(command, onLine: onLine)
        }

        public func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
            let pid = try await inner.spawnDetached(command, logFile: logFile)
            spawnedAt = .now
            return pid
        }
    }

    /// Keyed by the full command line, like every other canned response.
    public static let command = "curl -s -i -m 2 http://localhost:8081/status"

    /// What curl `-i` hands back from the Metro serving `projectRoot`: the status
    /// line, the headers, a blank line, the body.
    public static func running(projectRoot: URL) -> String {
        reply(headers: ["X-React-Native-Project-Root": projectRoot.path], body: "packager-status:running")
    }

    public static func reply(
        _ statusLine: String = "HTTP/1.1 200 OK",
        headers: [String: String] = [:],
        body: String
    ) -> String {
        let head = ([statusLine] + headers.map { "\($0.key): \($0.value)" }).joined(separator: "\r\n")
        return head + "\r\n\r\n" + body
    }
}

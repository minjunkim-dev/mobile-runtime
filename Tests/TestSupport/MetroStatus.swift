import Core
import Foundation

/// The `/status` question and its answers, spelled once. Three test targets ask 8081
/// the same way `MetroVerdict` does, and a fixture that drifts from the command it
/// answers is a test that passes without exercising anything.
public enum MetroStatus {
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

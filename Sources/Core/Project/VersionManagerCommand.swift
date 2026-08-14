import Foundation

/// The command that switches tool versions *on this host*. A remediation is defined
/// by being pasteable (CONTEXT.md), and doctor was printing `nvm use` and
/// `rbenv install` to a machine that had neither — both answered
/// `command not found`.
///
/// So the host is measured rather than the repo read: the question is not which
/// manager the project prefers but which one is here to run the command. When none
/// is, there is no command — Remediation allows a summary on its own, and a paste
/// that fails costs more than a missing line.
enum VersionManagerCommand {
    enum Tool {
        case node, ruby
    }

    /// How a host admits to having a manager. nvm is a shell function rather than an
    /// executable, so PATH cannot answer for it and `NVM_DIR` is the signal.
    private enum Presence {
        case onPath(String)
        case environment(String)
    }

    /// - Parameter version: the version being switched to, for the managers that
    ///   need it named. nvm reads the pin file itself.
    /// - Returns: the first candidate this host has, or nil when it has none.
    static func detect(
        for tool: Tool,
        version: String,
        runner: any ProcessRunner,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async throws -> String? {
        for (presence, command) in candidates(for: tool, version: version) {
            switch presence {
            case .environment(let key):
                if environment[key] != nil { return command }
            case .onPath(let executable):
                // Any answer at all means the executable is there; what it printed is
                // the manager's business, not doctor's.
                if case .notOnPath = try await probeVersion(of: executable, using: runner) { continue }
                return command
            }
        }
        return nil
    }

    /// In preference order. mise leads both lists because it manages either tool, and
    /// asdf trails for the same reason — a host with something more specific installed
    /// is usually driving that one.
    private static func candidates(for tool: Tool, version: String) -> [(Presence, String)] {
        switch tool {
        case .node:
            [
                (.onPath("mise"), "mise use node@\(version)"),
                (.environment("NVM_DIR"), "nvm use"),
                (.onPath("fnm"), "fnm use \(version)"),
                (.onPath("asdf"), "asdf install nodejs \(version)"),
            ]
        case .ruby:
            [
                (.onPath("mise"), "mise use ruby@\(version)"),
                (.onPath("rbenv"), "rbenv install \(version)"),
                (.onPath("rvm"), "rvm install \(version)"),
                (.onPath("asdf"), "asdf install ruby \(version)"),
            ]
        }
    }
}

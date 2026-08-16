import Foundation

/// What one query to 8081 found there. Five answers, and only the first is this
/// project's bundler: the `/status` body says `packager-status:running` for *any*
/// Metro, so a run that reads only the body attaches this project's app to whatever
/// bundler happened to be up and calls it a success (#45).
///
/// The identity comes from `X-React-Native-Project-Root`, the header the status page
/// has carried since `@react-native-community/cli-server-api` 12.3.7 — and it is the
/// same comparison React Native's own `isDevServerRunning` makes. Orchestrate, don't
/// replace: we do not invent a rule where the platform already has one.
///
/// `up`'s "may I reuse this" and `down`'s "may I kill this" are the same question,
/// so they read the same verdict (ADR-0007).
public enum MetroVerdict: Sendable, Equatable {
    /// Metro, serving the anchor. The only branch that may be reused or killed.
    case mine
    /// Metro, serving somewhere else. `projectRoot` is what the header said — the
    /// occupant's working directory, which is not promised to be an anchor.
    case another(projectRoot: String)
    /// The port answered and the question could not be put to it. From RN 0.76 a
    /// project without `cli-server-api` serves no `/status` at all, and reading that
    /// as somebody else's Metro would hand a user a sentence about their own.
    case unidentifiable(observed: String)
    /// Something answered, and it was not Metro's answer. A connection that opened
    /// and then said nothing is here too — it is held, whatever holds it.
    case notMetro(observed: String)
    /// Nothing is listening. The only branch that starts one.
    case empty

    /// Fixed. Configuring it was ruled out with the rest of mobile.yml v0 (#11), and
    /// a React Native app's default bundler URL is compiled into the Debug build.
    public static let port = 8081

    /// Asked with curl through the same runner rather than by opening a socket: a new
    /// way to reach the network would be a second seam to fake, and `/status` is the
    /// answer Metro itself publishes for exactly this question. `-i` because the
    /// answer is in the headers as much as in the body.
    ///
    /// - Parameter anchor: the project directory the occupant is measured against.
    ///
    /// Only curl's exit 7 — "failed to connect" — is an empty port. Every other
    /// failure means something answered the connection and then did not finish the
    /// sentence: a timeout (28), an empty reply (52), a reset. Reading those as empty
    /// is how `up` starts a second Metro that cannot bind and reports it as started,
    /// which is exactly the blank screen this verdict exists to replace with a
    /// sentence.
    public static func ask(anchor: URL, runner: any ProcessRunner) async throws -> MetroVerdict {
        let result = try await runner.run(
            ProcessCommand(
                "curl", ["-s", "-i", "-m", "2", "http://localhost:\(port)/status"],
                timeout: .seconds(10)
            )
        )
        switch result.terminationStatus {
        case .exited(0): return read(result.standardOutput, anchor: anchor)
        case .exited(Self.couldNotConnect): return .empty
        case .exited(let code):
            return .notMetro(observed: "curl exited \(code) — the port answered but Metro did not")
        // A probe that was killed brought back no answer at all. Reading it as held is
        // the conservative half of the same rule: a wrong stop costs a sentence, and a
        // wrong start costs a second Metro that cannot bind (#14).
        case .signaled(let signal): return .notMetro(observed: "curl was killed by signal \(signal)")
        }
    }

    /// The sentence that stops a run, or nil for the two branches that do not stop
    /// one. `up` and `down` differ in what they do with `mine`, not in what they say
    /// about the rest.
    public var blocker: DomainError? {
        switch self {
        case .mine, .empty:
            return nil

        case .another(let projectRoot):
            return DomainError(
                summary: "port \(Self.port) is held by another project's Metro",
                observed: "it is serving \(projectRoot)",
                // The header is that process's working directory, not a React Native
                // anchor, so `cd <it> && mobile down` is not promised to work. The
                // line that always works points at the process (ADR-0006).
                remediation: Remediation(
                    summary: "React Native's bundler only listens on \(Self.port), so that one has "
                        + "to stop before this project's can start. This says which process it is.",
                    command: Self.listenerCommand
                )
            )

        case .unidentifiable(let observed):
            return DomainError(
                summary: "port \(Self.port) answered, but which project's Metro is there "
                    + "could not be confirmed",
                observed: observed,
                remediation: Remediation(
                    summary: "A React Native project without `@react-native-community/cli-server-api` "
                        + "serves no `/status`, and neither does anything that is not Metro — from "
                        + "here the two look alike. This says which process is listening on "
                        + "\(Self.port).",
                    command: Self.listenerCommand
                )
            )

        case .notMetro(let observed):
            // The alternative is a blank screen in the simulator and nothing to read.
            return DomainError(
                summary: "port \(Self.port) is held by something that is not Metro",
                observed: observed,
                remediation: Remediation(
                    summary: "React Native's bundler only listens on \(Self.port), so whatever holds "
                        + "it has to go first. This says which process that is.",
                    command: Self.listenerCommand
                )
            )
        }
    }

    /// Which process is listening is `lsof`'s answer in every stopping branch — even
    /// the one where the header already named a directory, and above all the one where
    /// nothing about the port is known beyond the fact that it answered.
    private static let listenerCommand = "lsof -nP -iTCP:\(port) -sTCP:LISTEN"

    /// curl's `CURLE_COULDNT_CONNECT`.
    private static let couldNotConnect: Int32 = 7

    /// What Metro answers `/status` with.
    private static let runningMarker = "packager-status:running"

    private static let projectRootHeader = "x-react-native-project-root"

    private static func read(_ response: String, anchor: URL) -> MetroVerdict {
        let (head, body) = split(response)

        guard body.contains(runningMarker) else {
            // A page served where Metro's status page should be is somebody else's
            // page; anything else — a 404 above all — is a port that could not be
            // asked, and 0.76+ Metro without `cli-server-api` looks exactly like that.
            let observed = excerpt(body.isEmpty ? head : body)
            return statusCode(head) == 200 ? .notMetro(observed: observed) : .unidentifiable(observed: observed)
        }
        guard let root = header(projectRootHeader, in: head) else {
            return .unidentifiable(observed: "\(runningMarker), with no project root header")
        }
        return normalized(URL(fileURLWithPath: root)) == normalized(anchor)
            ? .mine : .another(projectRoot: root)
    }

    /// Head and body, at the blank line curl leaves between them. A response with no
    /// blank line is all head — there is nothing to read as a body.
    private static func split(_ response: String) -> (head: String, body: String) {
        let normalized = response.replacingOccurrences(of: "\r\n", with: "\n")
        guard let separator = normalized.range(of: "\n\n") else { return (normalized, "") }
        return (String(normalized[..<separator.lowerBound]), String(normalized[separator.upperBound...]))
    }

    /// From `HTTP/1.1 404 Not Found`. nil when the head is not one — a verdict that
    /// cannot read the status line has not been told the port serves anything.
    private static func statusCode(_ head: String) -> Int? {
        guard let statusLine = head.split(separator: "\n").first else { return nil }
        let fields = statusLine.split(separator: " ")
        guard fields.count >= 2 else { return nil }
        return Int(fields[1])
    }

    private static func header(_ name: String, in head: String) -> String? {
        for line in head.split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":"),
                line[..<colon].lowercased() == name
            else { continue }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// Two spellings of one directory — a trailing slash, `/var` against
    /// `/private/var` — are one directory.
    private static func normalized(_ directory: URL) -> String {
        directory.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func excerpt(_ text: String) -> String {
        String(text.prefix(200)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

import Core
import Foundation

/// `launch` — terminate, then launch, on every run.
///
/// The relaunch is the guarantee `up` sells: when the command returns, what is on
/// the screen is the code it just built. `simctl launch` on an app that is already
/// running hands back the old instance's pid without restarting it, so without the
/// terminate the promise would hold for the bundle on disk and quietly break on the
/// screen — the worst shape a bug can take, because nothing looks wrong.
public struct LaunchStage: Stage {
    public let id = "launch"

    private let runner: any ProcessRunner
    private let metroRunner: any ProcessRunner
    private let locator: XcodeLocator
    private let project: URL
    /// The upper bound for observing the bundle after the app asks Metro for it.
    /// Injected so tests do not wait, while a first bundle gets enough time on a cold
    /// machine to finish honestly.
    private let readinessWait: Duration
    private let flutterPort: Int?

    public static let defaultReadinessWait: Duration = .seconds(120)

    public init(
        project: URL,
        runner: any ProcessRunner,
        metroRunner: (any ProcessRunner)? = nil,
        locator: XcodeLocator,
        readinessWait: Duration = LaunchStage.defaultReadinessWait,
        flutterPort: Int? = nil
    ) {
        self.project = project
        self.runner = runner
        self.metroRunner = metroRunner ?? runner
        self.locator = locator
        self.readinessWait = readinessWait
        self.flutterPort = flutterPort
    }

    public func run(_ context: inout UpContext) async throws -> StageOutcome {
        let (device, product) = try context.built(for: id)
        let environment = await locator.pinnedEnvironment()
        if let port = flutterPort {
            let listener = try await runner.run(ProcessCommand("lsof", ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN"], timeout: .seconds(10)))
            guard listener.terminationStatus == .exited(1), listener.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                if listener.terminationStatus.isSuccess {
                    throw DomainError(summary: "The selected Flutter VM service port became occupied before launch.",
                        remediation: Remediation(summary: "Preserve its current listener. Select another port or explicitly stop its owning app, then retry."))
                }
                throw ToolUnavailable(description: "Could not confirm that the Flutter VM service port is free before launch.")
            }
        }

        // Every failure ignored, the runner's own included: on a first run there is
        // nothing to terminate, and simctl says so with a paragraph and exit 3.
        _ = try? await runner.run(
            ProcessCommand(
                "xcrun", ["simctl", "terminate", device.udid, product.bundleIdentifier],
                environment: environment,
                timeout: .seconds(30)
            )
        )

        try Task.checkCancellation()
        let flutterLog: URL?
        if flutterPort != nil {
            let logs = RunLogs(project: project)
            guard let file = logs.write("", to: "flutter-launch-\(UUID().uuidString).log") else {
                throw ToolUnavailable(description: "Could not save this Flutter launch log.")
            }
            flutterLog = file
        } else { flutterLog = nil }
        let output = flutterLog.map { ["--stdout=\($0.path)", "--stderr=\($0.path)"] } ?? []
        let launchArguments = flutterPort.map {
            ["--enable-dart-profiling", "--enable-checked-mode", "--verify-entry-points", "--vm-service-port=\($0)"]
        } ?? []
        let command = ProcessCommand(
            "xcrun", ["simctl", "launch"] + output + [device.udid, product.bundleIdentifier] + launchArguments,
            environment: environment,
            timeout: .seconds(60)
        )
        let result = try await runner.run(command)
        guard result.terminationStatus.isSuccess else {
            throw DomainError(
                summary: "\(product.bundleIdentifier) did not start on \(device.name)",
                observed: result.combinedOutput.lastLines(5),
                remediation: Remediation(
                    summary: "Run it by hand to see the whole message. An app that installs and "
                        + "then refuses to start is usually one built for another platform, or "
                        + "one whose deployment target is above this runtime.",
                    command: command.description
                )
            )
        }

        // simctl answers `com.example.MyApp: 3538`. Reporting the pid is half of what
        // this stage is for, so an answer without one is a broken tool, not a broken
        // project — it must not land on the project's exit code.
        guard let pid = Self.pid(in: result.standardOutput) else {
            throw ToolUnavailable(
                description: "`\(command.description)` started the app without printing a pid — "
                    + (result.standardOutput.firstLine ?? "it printed nothing")
            )
        }
        context.appPid = pid
        if let port = flutterPort, let file = flutterLog {
            context.developmentServiceURI = try await flutterServiceURI(log: file, port: port)
        }

        let detail = "\(product.bundleIdentifier) — pid \(pid)"
        guard let metro = context.metro else { return .pass(detail) }
        let ready = await MetroReadiness(
            project: project, runner: metroRunner, timeout: readinessWait
        ).wait(for: metro)
        if ready { return .pass(detail) }

        let hint = metro.logPath.map { " — Metro still bundling; log at \($0)" }
            ?? " — Metro still bundling; check the Metro process on port 8081"
        return .pass(detail + hint)
    }

    private func flutterServiceURI(log: URL, port: Int) async throws -> String {
        let deadline = ContinuousClock.now.advanced(by: readinessWait)
        repeat {
            try Task.checkCancellation()
            let contents = try String(contentsOf: log, encoding: .utf8)
            for line in contents.split(whereSeparator: \.isNewline) {
                guard let range = line.range(of: "The Dart VM service is listening on ") else { continue }
                let value = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                guard let uri = URLComponents(string: value), uri.scheme == "http",
                    ["127.0.0.1", "localhost", "::1"].contains(uri.host ?? ""), uri.port == port,
                    uri.user == nil, uri.password == nil, uri.query == nil, uri.fragment == nil,
                    !uri.path.isEmpty else {
                    throw DomainError(summary: "Flutter reported a different or invalid development service URI.",
                        remediation: Remediation(summary: "Inspect this app's Flutter launch log and selected port, then retry down for this project."))
                }
                let probe = try await runner.run(ProcessCommand("curl", ["--fail", "--silent", "--show-error", "--noproxy", "*",
                    "--connect-timeout", "2", "--max-time", "5", value + (value.hasSuffix("/") ? "" : "/") + "getVM"], timeout: .seconds(10)))
                try Task.checkCancellation()
                if probe.terminationStatus.isSuccess {
                    guard let document = try? JSONSerialization.jsonObject(with: Data(probe.standardOutput.utf8)) as? [String: Any],
                        (document["result"] as? [String: Any])?["type"] as? String == "VM" else {
                        throw DomainError(summary: "The observed Flutter URI did not answer as a Dart VM service.",
                            remediation: Remediation(summary: "Inspect the selected app and service port. Run down before retrying this project."))
                    }
                    return value
                }
            }
            if ContinuousClock.now >= deadline { break }
            try await Task.sleep(for: .milliseconds(100))
        } while true
        throw DomainError(summary: "The Flutter app started, but its development service URI was not observed.",
            remediation: Remediation(summary: "Inspect the Flutter app and launch log at \(log.path). Run mobile down --platform ios before retrying."))
    }

    /// The pid is what a line ends with. Read from the end rather than by splitting on
    /// the colon: a bundle id is dots and dashes, but the tail is the number whatever
    /// simctl decides to print in front of it. Every line is offered, so a future
    /// simctl that prints a notice first still gets its pid read.
    private static func pid(in output: String) -> Int32? {
        output.split(separator: "\n").lazy
            .compactMap { $0.split(separator: " ").last.flatMap { Int32($0) } }
            .first
    }
}

/// The signal differs by ownership: a Metro this run started has a log to read,
/// while a reused one can answer the same `/status` question `up` already trusts.
private struct MetroReadiness: Sendable {
    private let project: URL
    private let runner: any ProcessRunner
    private let timeout: Duration

    init(project: URL, runner: any ProcessRunner, timeout: Duration) {
        self.project = project
        self.runner = runner
        self.timeout = timeout
    }

    func wait(for metro: MetroProcess) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while true {
            if await isReady(metro) { return true }
            let remaining = ContinuousClock.now.duration(to: deadline)
            guard remaining > .zero else { return false }
            try? await Task.sleep(for: min(.milliseconds(250), remaining))
        }
    }

    private func isReady(_ metro: MetroProcess) async -> Bool {
        switch metro.state {
        case .spawned:
            guard let logPath = metro.logPath,
                  let log = try? String(contentsOfFile: logPath, encoding: .utf8)
            else { return false }
            return log.split(whereSeparator: \.isNewline).contains { rawLine in
                let line = rawLine.replacingOccurrences(
                    of: #"\x1B\[[0-9;]*m"#, with: "", options: .regularExpression
                ).split(whereSeparator: \.isWhitespace).joined(separator: " ")
                // Modern Metro omits progress on both done and failed frames.
                // FORCE_COLOR=1 preserves its green success label. Match only the
                // label: an incomplete yellow frame also has a green progress bar.
                let greenBundle = rawLine.range(
                    of: #"^\s*(?:\x1B\[(?:1|7)m)*\x1B\[32m(?:\x1B\[(?:1|7)m)*\s*BUNDLE\b"#,
                    options: .regularExpression
                ) != nil
                let completedBundle = line.uppercased().hasPrefix("BUNDLE ")
                    && (greenBundle || line.contains("100.0%") || line.contains("100%"))
                let connectedApp = line.contains("Running \"") && line.contains(" with {")
                return completedBundle || connectedApp
            }
        case .reused:
            guard let verdict = try? await MetroVerdict.ask(anchor: project, runner: runner)
            else { return false }
            if case .mine = verdict { return true }
            return false
        }
    }
}

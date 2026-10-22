import Core
import CoreFoundation
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
    private let metroPort: Int?
    private let flutterPort: Int?

    public static let defaultReadinessWait: Duration = .seconds(120)

    public init(
        project: URL,
        runner: any ProcessRunner,
        metroRunner: (any ProcessRunner)? = nil,
        locator: XcodeLocator,
        readinessWait: Duration = LaunchStage.defaultReadinessWait,
        metroPort: Int? = nil,
        flutterPort: Int? = nil
    ) {
        self.project = project
        self.runner = runner
        self.metroRunner = metroRunner ?? runner
        self.locator = locator
        self.readinessWait = readinessWait
        self.metroPort = metroPort
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
        let launchArguments = flutterPort.map {
            ["--enable-dart-profiling", "--enable-checked-mode", "--verify-entry-points", "--vm-service-port=\($0)"]
        } ?? []
        let command = ProcessCommand(
            "xcrun", ["simctl", "launch", device.udid, product.bundleIdentifier] + launchArguments
                + (context.metro != nil ? metroPort.map { ["-RCT_jsLocation", "localhost:\($0)"] } ?? [] : []),
            environment: environment,
            timeout: .seconds(60)
        )
        let launchedAt = Date()
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
        if let port = flutterPort {
            context.developmentServiceURI = try await flutterServiceURI(port: port, pid: pid,
                device: device, product: product, launchedAt: launchedAt, environment: environment)
        }

        let detail = "\(product.bundleIdentifier) — pid \(pid)"
        guard let metro = context.metro else { return .pass(detail) }
        let ready = await MetroReadiness(
            project: project, runner: metroRunner, timeout: readinessWait, port: metroPort ?? MetroVerdict.port
        ).wait(for: metro)
        if ready { return .pass(detail) }

        let hint = metro.logPath.map { " — Metro still bundling; log at \($0)" }
            ?? " — Metro still bundling; check the Metro process on port \(metroPort ?? MetroVerdict.port)"
        return .pass(detail + hint)
    }

    private func flutterServiceURI(port: Int, pid: Int32, device: SelectedDevice,
                                   product: BuiltProduct, launchedAt: Date, environment: [String: String]) async throws -> String {
        let deadline = ContinuousClock.now.advanced(by: readinessWait)
        var images: (process: Set<UUID>, sender: Set<UUID>)?
        repeat {
            try Task.checkCancellation()
            if images == nil {
                images = try await flutterImageUUIDs(device: device, product: product,
                    environment: environment, deadline: deadline)
            }
            guard let images else { throw ToolUnavailable(description: "The installed Flutter app image identities are unknown.") }
            let messages = try await flutterHistory(device: device, images: images, pid: pid,
                launchedAt: launchedAt, environment: environment, deadline: deadline)
            for message in messages {
                guard let range = message.range(of: Self.flutterMarker) else { continue }
                let value = message[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                guard let uri = URLComponents(string: value), uri.scheme == "http",
                    ["127.0.0.1", "localhost", "::1"].contains(uri.host ?? ""), uri.port == port,
                    uri.user == nil, uri.password == nil, uri.query == nil, uri.fragment == nil,
                    !uri.path.isEmpty else {
                    throw DomainError(summary: "Flutter reported a different or invalid development service URI.",
                        remediation: Remediation(summary: "Inspect this Flutter app and selected port, then retry down for this project."))
                }
                try await flutterPID(device: device, bundleID: product.bundleIdentifier, pid: pid,
                    environment: environment, deadline: deadline)
                let probe = try await flutterQuery(ProcessCommand("curl", ["--fail", "--silent", "--show-error", "--noproxy", "*",
                    "--connect-timeout", "2", "--max-time", "5", value + (value.hasSuffix("/") ? "" : "/") + "getVM"],
                    timeout: flutterQueryTimeout(deadline), redactArguments: true), failure: "Could not query the observed Flutter development service.", deadline: deadline)
                if probe.terminationStatus.isSuccess {
                    guard let document = try? JSONSerialization.jsonObject(with: Data(probe.standardOutput.utf8)) as? [String: Any],
                        (document["result"] as? [String: Any])?["type"] as? String == "VM" else {
                        throw DomainError(summary: "The observed Flutter URI did not answer as a Dart VM service.",
                            remediation: Remediation(summary: "Inspect the selected app and service port. Run down before retrying this project."))
                    }
                    try await flutterPID(device: device, bundleID: product.bundleIdentifier, pid: pid,
                        environment: environment, deadline: deadline)
                    return value
                }
            }
            let remaining = ContinuousClock.now.duration(to: deadline)
            if remaining <= .zero { break }
            try await Task.sleep(for: min(.seconds(1), remaining))
            if ContinuousClock.now >= deadline { break }
        } while true
        throw DomainError(summary: "The Flutter app started, but its development service URI was not observed.",
            remediation: Remediation(summary: "Inspect the Flutter app and its development service. Run mobile down --platform ios before retrying."))
    }

    private static let flutterMarker = "The Dart VM service is listening on "
    private static let flutterOutputLimit = 1_048_576

    /// Finite collected commands use the existing runner's cancellation and output bound.
    /// Never include their output or command in errors: a service URI contains credentials.
    private func flutterQuery(_ command: ProcessCommand, failure: String,
                              deadline: ContinuousClock.Instant) async throws -> ProcessResult {
        do {
            let result = try await runner.run(command)
            try Task.checkCancellation()
            return result
        } catch is CancellationError { throw CancellationError() }
        catch ProcessError.timedOut where ContinuousClock.now >= deadline {
            throw DomainError(summary: "The Flutter development service readiness deadline expired.",
                remediation: Remediation(summary: "Inspect the selected app and its development service. Run mobile down --platform ios before retrying."))
        }
        catch ProcessError.timedOut { throw ToolUnavailable(description: failure + " [query-timeout]") }
        catch ProcessError.spawnFailed { throw ToolUnavailable(description: failure + " [query-spawn-failed]") }
        catch { throw ToolUnavailable(description: failure + " [query-failed]") }
    }

    private func flutterQueryTimeout(_ deadline: ContinuousClock.Instant) -> Duration {
        min(.seconds(5), max(.milliseconds(1), ContinuousClock.now.duration(to: deadline)))
    }

    private func flutterImageUUIDs(device: SelectedDevice, product: BuiltProduct,
                                   environment: [String: String], deadline: ContinuousClock.Instant) async throws -> (process: Set<UUID>, sender: Set<UUID>) {
        let failure = "Could not identify the installed Flutter app images for bounded log observation."
        let result = try await flutterQuery(ProcessCommand("xcrun",
            ["simctl", "get_app_container", device.udid, product.bundleIdentifier, "app"],
            environment: environment, timeout: flutterQueryTimeout(deadline)), failure: failure, deadline: deadline)
        let path = result.standardOutput.trimmingCharacters(in: .newlines)
        guard result.terminationStatus.isSuccess, path.utf8.count <= 4096, path.hasPrefix("/"), path.hasSuffix(".app"),
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ToolUnavailable(description: failure)
        }
        let bundle = URL(fileURLWithPath: path)
        let info = bundle.appendingPathComponent("Info.plist")
        let attributes = try info.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard attributes.isRegularFile == true, attributes.isSymbolicLink != true,
              (attributes.fileSize ?? Self.flutterOutputLimit + 1) <= Self.flutterOutputLimit,
              let document = try PropertyListSerialization.propertyList(from: Data(contentsOf: info), format: nil) as? [String: Any],
              document["CFBundleIdentifier"] as? String == product.bundleIdentifier,
              let name = document["CFBundleExecutable"] as? String, !name.isEmpty, name != ".", name != "..", !name.contains("/"),
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ToolUnavailable(description: failure)
        }
        var images: [Set<UUID>] = []
        for executable in [bundle.appendingPathComponent(name), bundle.appendingPathComponent("Frameworks/Flutter.framework/Flutter")] {
            let file = try executable.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard file.isRegularFile == true, file.isSymbolicLink != true,
                executable.resolvingSymlinksInPath().path.hasPrefix(bundle.resolvingSymlinksInPath().path + "/")
            else { throw ToolUnavailable(description: failure) }
            let observed = try await flutterQuery(ProcessCommand("/usr/bin/xcrun", ["dwarfdump", "--uuid", executable.path],
                environment: environment, timeout: flutterQueryTimeout(deadline)), failure: failure, deadline: deadline)
            guard observed.terminationStatus.isSuccess, observed.standardOutput.utf8.count <= Self.flutterOutputLimit
            else { throw ToolUnavailable(description: failure) }
            let lines = observed.standardOutput.split(whereSeparator: \.isNewline)
            guard !lines.isEmpty, lines.count <= 16 else { throw ToolUnavailable(description: failure) }
            var uuids: Set<UUID> = []
            var architectures: Set<String> = []
            for line in lines {
                let fields = line.split(separator: " ", maxSplits: 3)
                guard fields.count == 4, fields[0] == "UUID:", let uuid = UUID(uuidString: String(fields[1])),
                    uuid.uuidString == fields[1].uppercased(), String(fields[2]).range(of: #"^\([A-Za-z0-9_]+\)$"#, options: .regularExpression) != nil,
                    fields[3] == executable.path, uuids.insert(uuid).inserted, architectures.insert(String(fields[2])).inserted
                else { throw ToolUnavailable(description: failure) }
            }
            images.append(uuids)
        }
        return (images[0], images[1])
    }

    private func flutterHistory(device: SelectedDevice, images: (process: Set<UUID>, sender: Set<UUID>), pid: Int32, launchedAt: Date,
                                environment: [String: String], deadline: ContinuousClock.Instant) async throws -> [String] {
        // Predicate keys and returned JSON keys differ: processIdentifier versus processID.
        // Reinstalled images can retain an earlier container path in unified logs; bind their current Mach-O UUIDs below.
        let predicate = "processIdentifier == \(pid) AND eventMessage CONTAINS \"\(Self.flutterMarker)\""
        let failure = "Could not read bounded Flutter app log history."
        let result = try await flutterQuery(ProcessCommand("xcrun", ["simctl", "spawn", device.udid, "log", "show",
            "--last", "5m", "--style", "json", "--info", "--debug", "--predicate", predicate],
            environment: environment, timeout: flutterQueryTimeout(deadline)), failure: failure, deadline: deadline)
        let observedAt = Date()
        guard result.terminationStatus.isSuccess else {
            throw ToolUnavailable(description: failure + " [history-nonzero-status]")
        }
        guard result.standardOutput.utf8.count <= Self.flutterOutputLimit else {
            throw ToolUnavailable(description: failure + " [history-output-limit]")
        }
        guard let rows = try? JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [[String: Any]] else {
            throw ToolUnavailable(description: failure + " [history-invalid-json]")
        }
        guard rows.count <= 1024 else {
            throw ToolUnavailable(description: failure + " [history-row-limit]")
        }
        return rows.compactMap { row in
            guard let number = row["processID"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue == Double(pid), let process = row["processImageUUID"] as? String,
                  let processUUID = UUID(uuidString: process), processUUID.uuidString == process.uppercased(), images.process.contains(processUUID),
                  let sender = row["senderImageUUID"] as? String, let senderUUID = UUID(uuidString: sender),
                  senderUUID.uuidString == sender.uppercased(), images.sender.contains(senderUUID), let rawDate = row["timestamp"] as? String,
                  let date = Self.flutterTimestamp(rawDate), date >= launchedAt, date <= observedAt,
                  let message = row["eventMessage"] as? String, message.utf8.count <= 16_384 else { return nil }
            return message
        }
    }

    private static func flutterTimestamp(_ value: String) -> Date? {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,9}[+-]\d{4}$"#, options: .regularExpression) != nil,
              let dot = value.firstIndex(of: ".") else { return nil }
        let zone = value.suffix(5)
        let fraction = value[value.index(after: dot)..<value.index(value.endIndex, offsetBy: -5)]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ssZ"
        formatter.isLenient = false
        guard let whole = formatter.date(from: String(value[..<dot]) + zone),
              let part = Double("0." + fraction) else { return nil }
        return whole.addingTimeInterval(part)
    }

    private func flutterPID(device: SelectedDevice, bundleID: String, pid: Int32,
                            environment: [String: String], deadline: ContinuousClock.Instant) async throws {
        let failure = "The launched Flutter app PID is no longer observable for this bundle. Run down before retrying."
        let result = try await flutterQuery(ProcessCommand("xcrun", ["simctl", "spawn", device.udid, "launchctl", "list"],
            environment: environment, timeout: flutterQueryTimeout(deadline)), failure: failure, deadline: deadline)
        guard result.terminationStatus.isSuccess, result.standardOutput.utf8.count <= Self.flutterOutputLimit,
              result.standardOutput.split(whereSeparator: \.isNewline).contains(where: { line in
                  let columns = line.split(separator: "\t")
                  return columns.count == 3 && columns[2].hasPrefix("UIKitApplication:\(bundleID)[") && Int32(columns[0]) == pid
              }) else { throw ToolUnavailable(description: failure) }
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
    private let port: Int

    init(project: URL, runner: any ProcessRunner, timeout: Duration, port: Int) {
        self.project = project
        self.runner = runner
        self.timeout = timeout
        self.port = port
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
            guard let verdict = try? await MetroVerdict.ask(anchor: project, runner: runner, port: port)
            else { return false }
            if case .mine = verdict { return true }
            return false
        }
    }
}

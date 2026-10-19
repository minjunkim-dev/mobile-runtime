import Core
import Foundation

/// Pins the existing effective local endpoint for each child. It does not pin a
/// server generation. Normal adb auto-start/version handling remains inherited.
struct AndroidADBEndpoint: Sendable, Equatable {
    let socket: String

    init(environment: AndroidEnvironment) throws {
        let values = environment.values
        if let selected = values["ADB_SERVER_SOCKET"] {
            try self.init(socket: selected)
        } else {
            let port = values["ANDROID_ADB_SERVER_PORT"].flatMap { $0.isEmpty ? nil : $0 } ?? "5037"
            let host = values["ANDROID_ADB_SERVER_ADDRESS"]
            try self.init(socket: host.map { "tcp:\($0):\(port)" } ?? "tcp:\(port)")
        }
    }

    init(socket: String) throws {
        let fields = socket.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard fields.first == "tcp", fields.count == 2 || fields.count == 3,
              fields.count == 2 || ["localhost", "127.0.0.1"].contains(fields[1]),
              let text = fields.last, !text.isEmpty, text.allSatisfy(\.isNumber),
              let port = Int(text), (1...65535).contains(port), String(port) == text else {
            throw AndroidStateError("Flutter requires an unambiguous existing local TCP adb server endpoint")
        }
        self.socket = socket
    }

    func arguments(_ arguments: [String]) -> [String] { ["-L", socket] + arguments }
}

/// Flutter VM-service discovery and the one forward owned by this Android run.
/// Callers hold the folder/device/general host-port leases and lifecycle lock.
struct AndroidFlutterService: Sendable {
    static let cleanupID = "android.adb.forward"
    let context: AndroidDoctorContext
    let runner: any ProcessRunner
    let sdk: URL
    let endpoint: AndroidADBEndpoint
    let timeouts: AndroidRuntimeTimeouts

    func marker(serial: String) async throws -> String {
        let result = try await command([
            "-s", serial, "shell", "-x", "logcat", "-v", "threadtime", "-v", "epoch",
            "-v", "usec", "-t", "1",
        ])
        guard let marker = result.standardOutput.split(whereSeparator: \.isNewline)
            .compactMap({ $0.split(whereSeparator: \.isWhitespace).first.map(String.init) })
            .last(where: { Self.epoch($0) != nil }) else {
            throw AndroidStateError("the selected device has no reliable pre-launch log time marker")
        }
        return marker
    }

    func connect(_ original: AndroidActiveRun, marker: String, hostPort: Int,
                 store: AndroidActiveRunStore) async throws -> (AndroidActiveRun, AndroidFlutterConnection) {
        try original.validate()
        guard original.schemaVersion == 2, original.forward == nil,
              let device = original.device, let serial = device.serial,
              let app = original.app, let pid = app.pid, app.launched,
              let entrypoint = original.target.entrypoint,
              (1...65535).contains(hostPort), Self.epoch(marker) != nil else {
            throw AndroidStateError("Flutter service setup requires one launched app and a leased host port")
        }
        let deadline = ContinuousClock.now + timeouts.launch
        let uri: URL
        while true {
            try Task.checkCancellation()
            try await verify(original, pid: pid, deadline: deadline)
            let output = try await command([
                "-s", serial, "shell", "logcat", "-d", "--pid=\(pid)",
                "-v", "threadtime", "-v", "epoch", "-v", "usec", "-T", marker,
            ], deadline: deadline)
            let found = try Self.serviceURI(output.standardOutput, pid: pid, marker: marker)
            try await verify(original, pid: pid, deadline: deadline)
            if let found {
                _ = try remaining(until: deadline)
                uri = found
                break
            }
            guard ContinuousClock.now < deadline else {
                throw AndroidStateError("the selected app did not announce a fresh Flutter VM service")
            }
            if timeouts.poll > .zero { try await Task.sleep(for: min(timeouts.poll, remaining(until: deadline))) }
        }
        guard let devicePort = uri.port else { throw AndroidStateError("Flutter VM service has no device port") }
        guard try await mappings(deadline: deadline)["tcp:\(hostPort)"] == nil else {
            throw DomainError(summary: "the selected host port already has an adb forward",
                remediation: Remediation(summary: "Preserve its owner and select another host port; do not rebind or remove that mapping."))
        }
        try Task.checkCancellation()
        guard try store.read() == original else {
            throw AndroidStateError("Android ownership changed before forward creation")
        }
        var value = original
        value.forward = .init(state: .pending, serial: serial, avd: device.avd,
            applicationId: app.applicationId, module: original.target.module,
            variant: original.target.variant, entrypoint: entrypoint, appPID: pid,
            hostPort: hostPort, devicePort: devicePort, launchMarker: marker,
            operationID: UUID().uuidString, serverSocket: endpoint.socket)
        try store.write(value)
        // Do not check cancellation between a successful child result and its
        // synchronous ownership commit. Unknown child outcomes retain pending.
        let created = try await command([
            "-s", serial, "forward", "--no-rebind", "tcp:\(hostPort)", "tcp:\(devicePort)",
        ], deadline: deadline, checkDeadlineAfter: false)
        let resolved = created.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard resolved.isEmpty || resolved == String(hostPort) else {
            throw AndroidStateError("adb forward creation could not be confirmed; preserve pending ownership")
        }
        value.forward?.state = .created
        do {
            try store.write(value)
        } catch {
            // Creation was confirmed. Cleanup still verifies identity and the
            // global tuple. A failed save never authorizes a port-only removal.
            let known = value
            _ = await Task.detached { try? await remove(known, deadline: deadline) }.value
            throw AndroidStateError("confirmed forward ownership could not be committed; inspect preserved state")
        }
        guard try await mappings(deadline: deadline)["tcp:\(hostPort)"] == Mapping(serial: serial, remote: "tcp:\(devicePort)") else {
            throw AndroidStateError("the created Flutter forward was replaced; preserve ownership")
        }
        try await verify(value, pid: pid, deadline: deadline)
        _ = try remaining(until: deadline)
        return (value, AndroidFlutterConnection(hostPort: hostPort, devicePort: devicePort))
    }

    func remove(_ value: AndroidActiveRun, deadline: ContinuousClock.Instant? = nil) async throws -> TeardownItem {
        try value.validate()
        guard let forward = value.forward else { return .skipped(Self.cleanupID, "not recorded") }
        guard endpoint.socket == forward.serverSocket else {
            return blocked("the selected adb server endpoint differs from the recorded forward")
        }
        let local = "tcp:\(forward.hostPort)"
        guard let current = try await mappings(deadline: deadline)[local] else {
            return .skipped(Self.cleanupID, "recorded forward is absent")
        }
        guard forward.state == .created,
              current == Mapping(serial: forward.serial, remote: "tcp:\(forward.devicePort)") else {
            return blocked("forward ownership is pending or the global mapping was replaced")
        }
        try await verify(value, pid: forward.appPID, allowStoppedApp: true, deadline: deadline)
        // ADB removes by LOCAL only. The immediate tuple check and Runstir leases
        // are best effort; external writers and identical-tuple ABA remain possible.
        guard try await mappings(deadline: deadline)[local] == current else {
            return blocked("the global forward changed before cleanup")
        }
        _ = try await command(["-s", forward.serial, "forward", "--remove", local], deadline: deadline)
        guard try await mappings(deadline: deadline)[local] == nil else {
            return blocked("the forward is present after cleanup; do not delete a replacement")
        }
        return .stopped(Self.cleanupID, local)
    }

    func verify(_ value: AndroidActiveRun, pid: Int32, allowStoppedApp: Bool = false,
                deadline: ContinuousClock.Instant? = nil) async throws {
        guard let device = value.device, let serial = device.serial, let app = value.app else {
            throw AndroidStateError("Flutter app/device ownership is incomplete")
        }
        let devices = try await command(["devices"], deadline: deadline)
        let rows = devices.standardOutput.split(whereSeparator: \.isNewline).map {
            $0.split(whereSeparator: \.isWhitespace).map(String.init)
        }.filter { $0.first == serial }
        guard rows.count == 1, rows[0] == [serial, "device"] else {
            throw AndroidStateError("the recorded Flutter device is not uniquely observable")
        }
        let avd = try await command(["-s", serial, "emu", "avd", "name"], deadline: deadline)
        guard androidAVDName(from: avd.standardOutput) == device.avd else {
            throw AndroidStateError("the Flutter device serial now identifies another AVD")
        }
        let observed = try await appPID(serial: serial, applicationId: app.applicationId, deadline: deadline)
        guard observed == pid || (allowStoppedApp && observed == nil) else {
            throw AndroidStateError("the Flutter app process is absent, replaced or ambiguous")
        }
    }

    func appPID(serial: String, applicationId: String, deadline: ContinuousClock.Instant? = nil) async throws -> Int32? {
        let result = try await command(["-s", serial, "shell", "pidof", applicationId], allowFailure: true, deadline: deadline)
        let fields = result.standardOutput.split(whereSeparator: \.isWhitespace)
        if result.terminationStatus == .exited(1), fields.isEmpty, result.standardError.isEmpty { return nil }
        guard result.terminationStatus.isSuccess, result.standardError.isEmpty, fields.count == 1,
              let pid = Int32(fields[0]), pid > 0 else {
            throw AndroidStateError("the selected Flutter app PID cannot be determined uniquely")
        }
        return pid
    }

    struct Mapping: Equatable { let serial: String; let remote: String }

    func mappings(deadline: ContinuousClock.Instant? = nil) async throws -> [String: Mapping] {
        let result = try await command(["forward", "--list"], deadline: deadline)
        var mappings: [String: Mapping] = [:]
        for line in result.standardOutput.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count == 3, mappings[fields[1]] == nil else {
                throw AndroidStateError("the global adb forward list is unreadable or ambiguous")
            }
            mappings[fields[1]] = Mapping(serial: fields[0], remote: fields[2])
        }
        return mappings
    }

    private func remaining(until deadline: ContinuousClock.Instant) throws -> Duration {
        let budget = ContinuousClock.now.duration(to: deadline)
        guard budget > .zero else { throw AndroidStateError("Flutter VM-service setup exhausted its launch deadline") }
        return budget
    }

    private func command(_ arguments: [String], allowFailure: Bool = false,
                         deadline: ContinuousClock.Instant? = nil, checkDeadlineAfter: Bool = true) async throws -> ProcessResult {
        do {
            let budget = try deadline.map { min(.seconds(15), try remaining(until: $0)) } ?? .seconds(15)
            let result = try await runner.run(context.toolCommand(
                "adb", endpoint.arguments(arguments), sdk: sdk, timeout: budget))
            guard result.standardOutput.utf8.count <= 262_144, result.standardError.utf8.count <= 16_384,
                  allowFailure || result.terminationStatus.isSuccess else {
                throw AndroidStateError("Flutter adb observation failed or exceeded its bounded output")
            }
            if let deadline, checkDeadlineAfter { _ = try remaining(until: deadline) }
            return result
        } catch is CancellationError { throw CancellationError() }
        catch { throw AndroidStateError("Flutter adb observation could not be completed; preserve ownership") }
    }

    static func epoch(_ text: String) -> Double? {
        guard text.range(of: #"^[0-9]{9,12}\.[0-9]{3,6}$"#, options: .regularExpression) != nil,
              let value = Double(text), value.isFinite, value > 0 else { return nil }
        return value
    }

    static func serviceURI(_ output: String, pid: Int32, marker: String) throws -> URL? {
        guard let boundary = epoch(marker) else { throw AndroidStateError("invalid Flutter launch marker") }
        let announcement = "The Dart VM service is listening on "
        var found = Set<URL>()
        for line in output.split(whereSeparator: \.isNewline) {
            guard let range = line.range(of: announcement) else { continue }
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 4, let timestamp = epoch(String(fields[0])),
                  let observedPID = Int32(fields[1]) else {
                throw AndroidStateError("Flutter announcement has no reliable PID/time identity")
            }
            guard timestamp >= boundary, observedPID == pid else { continue }
            let text = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let components = URLComponents(string: text), components.scheme == "http",
                  ["127.0.0.1", "localhost", "::1", "[::1]"].contains(components.host),
                  let port = components.port, (1...65535).contains(port),
                  components.user == nil, components.password == nil,
                  components.query == nil, components.fragment == nil, let uri = components.url else {
                throw AndroidStateError("the selected Flutter app announced an invalid VM service URI")
            }
            found.insert(uri)
        }
        guard found.count <= 1 else { throw AndroidStateError("the selected Flutter app announced conflicting VM services") }
        return found.first
    }

    private func blocked(_ summary: String) -> TeardownItem {
        .blocked(Self.cleanupID, DomainError(summary: summary,
            remediation: Remediation(summary: "Preserve the mapping and active-run record; inspect ownership before retrying.")))
    }
}

import Core
import Darwin
import Foundation

/// The owner runs Flutter beside Gradle, so each process applies its policy once.
final class FlutterAndroidChildBroker: @unchecked Sendable {
    private let state: ChildBrokerState

    init(root: URL, runner: any ProcessRunner,
         command: @escaping @Sendable ([String]) throws -> ProcessCommand) throws {
        state = try ChildBrokerState(root: root, runner: runner, command: command)
        let state = state
        Thread.detachNewThread { state.listen() }
    }

    var environment: [String: String] {
        [ChildBrokerWire.endpointKey: state.endpoint.path, ChildBrokerWire.tokenKey: state.token]
    }

    func close() { state.close() }
    func finish() async {
        state.close()
        await state.waitForChild()
    }
    deinit { close() }
}

public enum FlutterAndroidChildClient {
    public static func runIfRequested(arguments: [String] = CommandLine.arguments) {
        guard arguments.dropFirst().first == ChildBrokerWire.flag else { return }
        signal(SIGPIPE, SIG_IGN)
        let status = run(arguments: arguments, environment: ProcessInfo.processInfo.environment) { channel, bytes in
            let output = channel == .standardOutput ? FileHandle.standardOutput : FileHandle.standardError
            try output.write(contentsOf: bytes)
        }
        Darwin.exit(status)
    }

    /// The same protocol entrypoint without process exit, for native caller fixtures.
    static func run(arguments: [String], environment: [String: String],
                    output: @escaping @Sendable (ProcessOutputChannel, Data) throws -> Void) -> Int32 {
        do {
            guard arguments.dropFirst().first == ChildBrokerWire.flag,
                  let endpoint = environment[ChildBrokerWire.endpointKey],
                  let token = environment[ChildBrokerWire.tokenKey], token.utf8.count == 64 else {
                throw ChildBrokerError.invalid
            }
            let request = ChildBrokerWire.Request(token: token, arguments: Array(arguments.dropFirst(2)))
            try request.validate()
            let bytes = try JSONEncoder().encode(request)
            guard bytes.count <= ChildBrokerWire.requestLimit else { throw ChildBrokerError.invalid }
            let socket = try ChildBrokerSocket()
            defer { socket.close() }
            var address = try ChildBrokerWire.address(endpoint)
            let connected = try socket.access { descriptor in
                withUnsafePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                    }
                }
            }
            guard connected.0 == 0 else { throw ChildBrokerError.closed }
            try socket.verifyPeer()
            try socket.send(kind: 0, bytes: bytes)
            while true {
                let (kind, bytes) = try socket.receive(limit: ChildBrokerWire.frameLimit)
                switch kind {
                case 1: try output(.standardOutput, bytes)
                case 2: try output(.standardError, bytes)
                case 3:
                    guard bytes.count == 5 else { throw ChildBrokerError.invalid }
                    let value = ChildBrokerWire.number(bytes.dropFirst())
                    if bytes[0] == 0, value <= 255 { return Int32(value) }
                    if bytes[0] == 1, (1...127).contains(value) { return Int32(128 + value) }
                    throw ChildBrokerError.invalid
                default: throw ChildBrokerError.invalid
                }
            }
        } catch {
            try? output(.standardError, Data("Protected Flutter child communication failed. Preserve its private execution view.\n".utf8))
            return 2
        }
    }
}

private enum ChildBrokerError: Error { case invalid, closed }

private enum ChildBrokerWire {
    static let flag = "--runstir-flutter-child"
    static let endpointKey = "RUNSTIR_FLUTTER_CHILD_SOCKET"
    static let tokenKey = "RUNSTIR_FLUTTER_CHILD_TOKEN"
    static let requestLimit = 262_144
    static let frameLimit = 65_536

    struct Request: Codable {
        let token: String
        let arguments: [String]

        func validate() throws {
            guard token.utf8.count == 64, arguments.count <= 256,
                  arguments.allSatisfy({ $0.utf8.count <= frameLimit && !$0.utf8.contains(0) }),
                  arguments.reduce(0, { $0 + $1.utf8.count }) <= 131_072 else {
                throw ChildBrokerError.invalid
            }
        }
    }

    static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        let bytes = Array(path.utf8)
        guard path.hasPrefix("/"), !bytes.contains(0), bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw ChildBrokerError.invalid
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
        }
        return address
    }

    static func number(_ bytes: some Collection<UInt8>) -> UInt32 {
        bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    static func bytes(_ value: UInt32) -> Data {
        Data([UInt8(value >> 24), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)])
    }
}

/// Every descriptor operation holds the lock, including the bounded poll. Closing
/// cannot race a later operation onto a descriptor reused by another subsystem.
private final class ChildBrokerSocket: @unchecked Sendable {
    private let lock = NSLock()
    private let writer = NSLock()
    private var descriptor: Int32

    init(_ accepted: Int32? = nil) throws {
        let descriptor = accepted ?? Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw ChildBrokerError.closed }
        self.descriptor = descriptor
        var enabled: Int32 = 1
        guard fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0,
              fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0,
              setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            Darwin.close(descriptor)
            self.descriptor = -1
            throw ChildBrokerError.closed
        }
    }

    func access(_ body: (Int32) -> Int32) throws -> (Int32, Int32) {
        try lock.withLock {
            guard descriptor >= 0 else { throw ChildBrokerError.closed }
            let result = body(descriptor)
            return (result, errno)
        }
    }

    func close() {
        lock.withLock {
            guard descriptor >= 0 else { return }
            _ = Darwin.shutdown(descriptor, SHUT_RDWR)
            Darwin.close(descriptor)
            descriptor = -1
        }
    }

    deinit { close() }

    func verifyPeer() throws {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard try access({ getpeereid($0, &uid, &gid) }).0 == 0, uid == getuid() else {
            throw ChildBrokerError.invalid
        }
    }

    func wait(_ events: Int32, until deadline: ContinuousClock.Instant? = nil) throws {
        while true {
            if let deadline, ContinuousClock.now >= deadline { throw ChildBrokerError.closed }
            var observed: Int16 = 0
            let result = try access { descriptor in
                var item = pollfd(fd: descriptor, events: Int16(events), revents: 0)
                let result = Darwin.poll(&item, 1, 100)
                observed = item.revents
                return result
            }
            if result.0 > 0 {
                guard Int32(observed) & (POLLNVAL | POLLERR) == 0 else { throw ChildBrokerError.closed }
                return
            }
            if result.0 < 0, result.1 != EINTR { throw ChildBrokerError.closed }
        }
    }

    func disconnected() -> Bool {
        var byte: UInt8 = 0
        guard let result = try? access({ Int32(Darwin.recv($0, &byte, 1, MSG_PEEK)) }) else { return true }
        return result.0 >= 0 || (result.1 != EAGAIN && result.1 != EWOULDBLOCK && result.1 != EINTR)
    }

    func send(kind: UInt8, bytes: Data) throws {
        guard bytes.count <= ChildBrokerWire.requestLimit else { throw ChildBrokerError.invalid }
        try writer.withLock {
            var frame = Data([kind])
            frame.append(ChildBrokerWire.bytes(UInt32(bytes.count)))
            frame.append(bytes)
            let deadline = ContinuousClock.now + .seconds(5)
            var offset = 0
            while offset < frame.count {
                let result = try frame.withUnsafeBytes { buffer in
                    try access { Int32(Darwin.send($0, buffer.baseAddress!.advanced(by: offset), frame.count - offset, 0)) }
                }
                if result.0 > 0 { offset += Int(result.0) }
                else if result.0 < 0 && result.1 == EINTR { continue }
                else if result.0 < 0 && (result.1 == EAGAIN || result.1 == EWOULDBLOCK) {
                    try wait(POLLOUT, until: deadline)
                } else { throw ChildBrokerError.closed }
            }
        }
    }

    func receive(limit: Int, until deadline: ContinuousClock.Instant? = nil) throws -> (UInt8, Data) {
        let header = try read(5, until: deadline)
        let count = Int(ChildBrokerWire.number(header.dropFirst()))
        guard count <= limit else { throw ChildBrokerError.invalid }
        return (header[0], try read(count, until: deadline))
    }

    private func read(_ count: Int, until deadline: ContinuousClock.Instant?) throws -> Data {
        var data = Data(count: count)
        var offset = 0
        while offset < count {
            if let deadline, ContinuousClock.now >= deadline { throw ChildBrokerError.closed }
            let result = try data.withUnsafeMutableBytes { buffer in
                try access { Int32(Darwin.recv($0, buffer.baseAddress!.advanced(by: offset), count - offset, 0)) }
            }
            if result.0 > 0 { offset += Int(result.0) }
            else if result.0 < 0 && result.1 == EINTR { continue }
            else if result.0 < 0 && (result.1 == EAGAIN || result.1 == EWOULDBLOCK) {
                try wait(POLLIN, until: deadline)
            } else { throw ChildBrokerError.closed }
        }
        return data
    }
}

private final class ChildBrokerJob: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var cancelled = false
    private var finishing = false
    private var completed = false
    let done = DispatchSemaphore(value: 0)

    func install(_ value: Task<Void, Never>) {
        let cancel = lock.withLock { () -> Bool in
            if !completed { task = value }
            return cancelled
        }
        if cancel { value.cancel() }
    }
    func cancel() {
        let active = lock.withLock { cancelled = true; return task }
        active?.cancel()
    }
    var isFinishing: Bool { lock.withLock { finishing } }
    func finish() { lock.withLock { finishing = true } }
    func complete() { lock.withLock { completed = true; task = nil }; done.signal() }
    func wait() async {
        let active = lock.withLock { task }
        await active?.value
    }
}

private final class ChildBrokerState: @unchecked Sendable {
    let endpoint: URL
    let token = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "")
    private let root: URL
    private let rootIdentity: FlutterAndroidExecution.Identity
    private let nodeDevice: Int32
    private let nodeInode: UInt64
    private let listener: ChildBrokerSocket
    private let runner: any ProcessRunner
    private let command: @Sendable ([String]) throws -> ProcessCommand
    private let lock = NSLock()
    private var closed = false
    private var connection: ChildBrokerSocket?
    private var job: ChildBrokerJob?
    private var closingJob: ChildBrokerJob?

    init(root: URL, runner: any ProcessRunner,
         command: @escaping @Sendable ([String]) throws -> ProcessCommand) throws {
        let rootIdentity = try FlutterAndroidExecution.Identity(root)
        let endpoint = root.appendingPathComponent("s")
        let listener = try ChildBrokerSocket()
        var address = try ChildBrokerWire.address(endpoint.path)
        let bound = try listener.access { descriptor in
            withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
        }
        guard bound.0 == 0 else { throw ChildBrokerError.closed }
        var info = stat()
        guard chmod(endpoint.path, 0o600) == 0, lstat(endpoint.path, &info) == 0,
              info.st_mode & S_IFMT == S_IFSOCK, info.st_uid == getuid(),
              try listener.access({ Darwin.listen($0, 4) }).0 == 0 else {
            listener.close()
            Darwin.unlink(endpoint.path)
            throw ChildBrokerError.closed
        }
        nodeDevice = info.st_dev
        nodeInode = info.st_ino
        self.root = root
        self.rootIdentity = rootIdentity
        self.endpoint = endpoint
        self.runner = runner
        self.command = command
        self.listener = listener
    }

    func close() {
        let active = lock.withLock { () -> (ChildBrokerSocket?, ChildBrokerJob?)? in
            guard !closed else { return nil }
            closed = true
            closingJob = job
            return (connection, job)
        }
        guard let active else { return }
        active.1?.cancel()
        active.0?.close()
        listener.close()
        var info = stat()
        if (try? FlutterAndroidExecution.Identity(root)) == rootIdentity,
           lstat(endpoint.path, &info) == 0, info.st_dev == nodeDevice, info.st_ino == nodeInode,
           info.st_mode & S_IFMT == S_IFSOCK {
            Darwin.unlink(endpoint.path)
        }
    }

    func waitForChild() async {
        let active = lock.withLock { closingJob }
        await active?.wait()
    }

    func listen() {
        defer { close() }
        while !lock.withLock({ closed }) {
            do {
                let accepted = try listener.access { Darwin.accept($0, nil, nil) }
                if accepted.0 < 0 {
                    if accepted.1 == EINTR { continue }
                    guard accepted.1 == EAGAIN || accepted.1 == EWOULDBLOCK else { return }
                    try listener.wait(POLLIN)
                    continue
                }
                let socket = try ChildBrokerSocket(accepted.0)
                let installed = lock.withLock { () -> Bool in
                    guard !closed else { return false }
                    connection = socket
                    return true
                }
                guard installed else { socket.close(); return }
                serve(socket)
                socket.close()
                lock.withLock { connection = nil; job = nil }
            } catch { return }
        }
    }

    private func serve(_ socket: ChildBrokerSocket) {
        do {
            try socket.verifyPeer()
            let (kind, bytes) = try socket.receive(limit: ChildBrokerWire.requestLimit, until: ContinuousClock.now + .seconds(5))
            guard kind == 0 else { throw ChildBrokerError.invalid }
            let request = try JSONDecoder().decode(ChildBrokerWire.Request.self, from: bytes)
            try request.validate()
            let supplied = Array(request.token.utf8), expected = Array(token.utf8)
            guard zip(supplied, expected).reduce(UInt8(0), { $0 | ($1.0 ^ $1.1) }) == 0 else {
                throw ChildBrokerError.invalid
            }
            let selected = try command(request.arguments)
            let job = ChildBrokerJob()
            let runner = runner
            let installed = lock.withLock { () -> Bool in
                guard !closed else { return false }
                self.job = job
                let task = Task.detached {
                    defer { job.complete() }
                    let status: TerminationStatus
                    do {
                        try Task.checkCancellation()
                        let result = try await runner.run(selected, onBytes: { channel, bytes in
                            do {
                                var offset = 0
                                while offset < bytes.count {
                                    let end = min(offset + ChildBrokerWire.frameLimit, bytes.count)
                                    try socket.send(kind: channel == .standardOutput ? 1 : 2, bytes: bytes.subdata(in: offset..<end))
                                    offset = end
                                }
                            } catch { job.cancel(); socket.close() }
                        })
                        try Task.checkCancellation()
                        status = result.terminationStatus
                    } catch is CancellationError { status = .exited(130) }
                    catch {
                        try? socket.send(kind: 2, bytes: Data("Protected Flutter child execution failed.\n".utf8))
                        status = .exited(2)
                    }
                    job.finish()
                    let result: Data
                    switch status {
                    case .exited(let value): result = Data([0]) + ChildBrokerWire.bytes(UInt32(bitPattern: value))
                    case .signaled(let value): result = Data([1]) + ChildBrokerWire.bytes(UInt32(bitPattern: value))
                    }
                    try? socket.send(kind: 3, bytes: result)
                }
                job.install(task)
                return true
            }
            guard installed else { return }
            while job.done.wait(timeout: .now() + .milliseconds(100)) == .timedOut {
                if !job.isFinishing && socket.disconnected() {
                    // An interrupted client cannot leave a queue of still-running SDK jobs.
                    close()
                    return
                }
                if lock.withLock({ closed }) { return }
            }
        } catch {
            // Protocol/auth failures never disclose the request, token or SDK diagnostics.
        }
    }
}

import Core
import CryptoKit
import Darwin
import Foundation

/// Explicit manual execution may bind a Git-tracked source leaf and its internal regular-file target.
struct FlutterSourceLinks: Sendable {
    typealias Entry = FlutterAndroidExecution.Entry
    struct Record: Equatable, Sendable {
        let link: Entry
        let target: String
        let file: Entry
        let parents: [String: Entry]
    }
    let root: URL
    private let identity: Entry
    private let sources: Set<String>
    private let forbidden: [String]
    private let records: [String: Record]
    private let tracking: (ProcessCommand, String, any ProcessRunner)?

    var paths: Set<String> { Set(records.keys.map { root.appendingPathComponent($0).path }) }
    func contains(_ path: URL) -> Bool { paths.contains(Self.spelling(path.path)) }

    private static func spelling(_ path: String) -> String {
        for alias in ["/tmp", "/var", "/etc"] where path == alias || path.hasPrefix(alias + "/") { return "/private" + path }
        return path
    }

    static func capture(root: URL, sources: Set<String>, links: Set<String>, forbidden: [URL], packageRoots: [URL] = [],
                        runner: any ProcessRunner) async throws -> Self {
        let root = try FlutterAndroidExecution.canonical(URL(fileURLWithPath: spelling(try FolderIdentity(directory: root).path)))
        let sources = Set(sources.map(spelling)), links = Set(links.map(spelling))
        guard sources.allSatisfy({ $0.hasPrefix(root.path + "/") }), links.isSubset(of: sources), links.count <= 128 else { throw refused("workspace 입력 목록") }
        let relative = Set(sources.map { String($0.dropFirst(root.path.count + 1)) })
        let selected = links.map { String($0.dropFirst(root.path.count + 1)) }.sorted()
        let identity = try withRoot(root) { try directoryEntry($0) }
        let packages = Set(([root] + packageRoots).map { spelling($0.path) })
        guard packages.allSatisfy({ $0 == root.path || $0.hasPrefix(root.path + "/") }) else { throw refused() }
        let generated = [".dart_tool", "build", ".mobile", "node_modules", ".build", ".gradle", "graft", ".fvm", ".symlinks",
            "vendor/bundle", "ios/Pods", "ios/.symlinks", "ios/vendor/bundle", "ios/Flutter/ephemeral", "android/.gradle", "android/build", "android/app/build"]
        let excluded = forbidden.map { spelling($0.path) } + packages.flatMap { package in generated.map { package + "/" + $0 } }
            .filter { path in !packages.contains(where: { $0 == path || $0.hasPrefix(path + "/") }) }
        let eligibility = Self(root: root, identity: identity, sources: relative, forbidden: excluded, records: [:], tracking: nil)
        guard selected.allSatisfy({ eligibility.source($0) }) else { throw refused("source 링크 범위") }
        var tracking: (ProcessCommand, String, any ProcessRunner)?
        if !selected.isEmpty {
            let command = ProcessCommand("/usr/bin/git", ["--literal-pathspecs", "-C", root.path, "ls-files", "--stage", "-z", "--"] + selected,
                timeout: .seconds(15))
            let result = try await runner.run(command)
            guard result.terminationStatus.isSuccess else { throw refused("Git 추적 조회") }
            let rows = result.standardOutput.split(separator: "\0")
            guard rows.count == selected.count else { throw refused("Git 추적 항목 수") }
            var tracked = Set<String>()
            for row in rows {
                let fields = row.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
                guard fields.count == 2 else { throw refused() }
                let header = fields[0].split(separator: " ")
                guard header.count == 3, header[0] == "120000", header[2] == "0",
                      header[1].range(of: #"\A[0-9a-f]{40,64}\z"#, options: .regularExpression) != nil,
                      selected.contains(String(fields[1])), tracked.insert(String(fields[1])).inserted else { throw refused("Git 링크 mode 또는 stage") }
            }
            tracking = (command, result.standardOutput, runner)
        }
        var result = Self(root: root, identity: identity, sources: relative, forbidden: excluded, records: [:], tracking: tracking)
        var records: [String: Record] = [:]
        for link in selected { records[link] = try result.inspect(link) }
        result = Self(root: root, identity: identity, sources: relative, forbidden: excluded, records: records, tracking: tracking)
        try result.check()
        return result
    }

    func check() throws {
        guard try Self.withRoot(root, { try Self.directoryEntry($0) }) == identity else { throw Self.refused() }
        for (path, record) in records {
            guard try inspect(path, expected: record) == record else { throw Self.refused() }
        }
    }

    func checkTracking() async throws {
        guard let (command, expected, runner) = tracking else { return }
        let result = try await runner.run(command)
        guard result.terminationStatus.isSuccess, result.standardOutput == expected else { throw Self.refused("Git 링크 추적 정보 변경") }
    }

    func protection() -> String {
        func quoted(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        var files = paths
        for record in records.values { files.insert(root.appendingPathComponent(record.target).path) }
        var parents = Set<String>()
        for record in records.values {
            for path in record.parents.keys { parents.insert(root.appendingPathComponent(path).path) }
        }
        for path in files {
            var parent = URL(fileURLWithPath: path).deletingLastPathComponent()
            while parent.path != "/" { parents.insert(parent.path); parent.deleteLastPathComponent() }
        }
        return files.sorted().map { "(deny file-write* (literal \(quoted($0))))" }.joined()
            + parents.sorted().map { "(deny file-write-unlink (literal \(quoted($0))))" }.joined()
    }

    private func source(_ relative: String) -> Bool {
        let components = relative.split(separator: "/").map(String.init)
        let excluded: Set<String> = [".git"]
        let metadata: Set<String> = ["pubspec.yaml", "pubspec_overrides.yaml", ".flutter-plugins", ".flutter-plugins-dependencies",
            "package_config.json", "package_graph.json", "local.properties", "Generated.xcconfig", "flutter_export_environment.sh",
            "AndroidManifest.xml", "Info.plist", "project.pbxproj", "gradlew", "gradlew.bat", "Podfile", "Gemfile", "Package.swift",
            "settings.gradle", "settings.gradle.kts", "build.gradle", "build.gradle.kts", "gradle.properties", "gradle-wrapper.properties", "CMakeLists.txt",
            "mobile.yml", "mobile.yaml", ".metadata", ".fvmrc", ".flutter-version", ".xcode-version", ".tool-versions",
            "mise.toml", ".mise.toml", ".ruby-version", ".node-version", ".nvmrc", ".java-version", "package.json"]
        let metadataExtensions: Set<String> = ["toml", "xcconfig", "pbxproj", "xcscheme", "xcworkspacedata", "plist", "properties", "gradle", "kts", "lock"]
        let absolute = root.appendingPathComponent(relative).path
        return sources.contains(relative) && !components.isEmpty && !components.contains(where: excluded.contains)
            && !metadata.contains(components.last ?? "") && !metadataExtensions.contains(URL(fileURLWithPath: relative).pathExtension)
            && !relative.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            && !forbidden.contains(where: { absolute == $0 || absolute.hasPrefix($0 + "/") })
    }

    private func inspect(_ relative: String, expected: Record? = nil) throws -> Record {
        guard source(relative) else { throw Self.refused("source 링크 범위") }
        return try Self.withRoot(root) { descriptor in
            guard try Self.directoryEntry(descriptor) == identity else { throw Self.refused() }
            var parents: [String: Entry] = ["": identity]
            let (before, text) = try Self.withParent(descriptor, relative: relative, parents: &parents, expected: expected?.parents) {
                try Self.linkEntry($0, $1)
            }
            guard !text.hasPrefix("/"), !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw Self.refused() }
            let (destination, file) = try targetEntry(descriptor, link: relative, text: text,
                parents: &parents, expected: expected?.parents)
            let (after, currentText) = try Self.withParent(descriptor, relative: relative, parents: &parents, expected: expected?.parents) {
                try Self.linkEntry($0, $1)
            }
            guard Self.same(before, after), text == currentText else { throw Self.refused() }
            let link = Entry(kind: .link, mode: UInt16(before.st_mode & 0o777), size: Int64(text.utf8.count), digest: Self.digest(Data(text.utf8)),
                target: text, nodeIdentity: Self.node(before))
            return Record(link: link, target: destination, file: file, parents: parents)
        }
    }

    private func targetEntry(_ descriptor: Int32, link: String, text: String, parents: inout [String: Entry],
                             expected: [String: Entry]?) throws -> (String, Entry) {
        let components = link.split(separator: "/").dropLast().map(String.init)
            + text.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let leaf = components.last, !leaf.isEmpty, leaf != ".", leaf != ".." else { throw Self.refused() }
        var opened: [Int32] = []; defer { for fd in opened.reversed() { close(fd) } }
        var stack = [descriptor], path: [String] = []
        // Keep every visited descriptor and identity, even when a later '..' removes its spelling.
        for name in components.dropLast() {
            if name.isEmpty || name == "." { continue }
            if name == ".." {
                guard stack.count > 1 else { throw Self.refused() }
                stack.removeLast(); path.removeLast(); continue
            }
            path.append(name)
            let relative = path.joined(separator: "/"), absolute = root.appendingPathComponent(relative).path
            guard name != ".git", !forbidden.contains(where: { absolute == $0 || absolute.hasPrefix($0 + "/") }) else { throw Self.refused("source 중간 경로") }
            let fd = openat(stack[stack.count - 1], name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard fd >= 0 else { throw Self.refused("source 중간 경로") }; opened.append(fd)
            let entry = try Self.directoryEntry(fd)
            if let previous = parents[relative] { guard previous == entry else { throw Self.refused() } }
            if let expected { guard expected[relative] == entry else { throw Self.refused() } }
            parents[relative] = entry; stack.append(fd)
        }
        let destination = (path + [leaf]).joined(separator: "/")
        guard source(destination), destination != link else { throw Self.refused("source 대상 범위") }
        let fd = openat(stack[stack.count - 1], leaf, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw Self.refused() }; defer { close(fd) }
        return (destination, try Self.fileEntry(fd))
    }

    private static func linkEntry(_ parent: Int32, _ name: String) throws -> (stat, String) {
        var before = stat()
        guard fstatat(parent, name, &before, AT_SYMLINK_NOFOLLOW) == 0, before.st_mode & S_IFMT == S_IFLNK,
              before.st_nlink == 1, before.st_mode & 0o7000 == 0 else { throw refused() }
        var bytes = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
        let count = readlinkat(parent, name, &bytes, bytes.count)
        var after = stat()
        guard count > 0, count < bytes.count,
              let text = String(data: Data(bytes: bytes, count: count), encoding: .utf8),
              fstatat(parent, name, &after, AT_SYMLINK_NOFOLLOW) == 0, same(before, after) else { throw refused() }
        return (before, text)
    }

    // Open every component, including the workspace's ancestors, without following aliases.
    private static func withRoot<T>(_ root: URL, _ body: (Int32) throws -> T) throws -> T {
        var descriptor = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw refused() }; defer { close(descriptor) }
        for name in root.path.split(separator: "/") {
            guard name != ".", name != ".." else { throw refused() }
            let next = openat(descriptor, String(name), O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard next >= 0 else { throw refused("workspace 부모 경로") }
            close(descriptor); descriptor = next
        }
        return try body(descriptor)
    }

    private static func withParent<T>(_ root: Int32, relative: String, parents: inout [String: Entry],
                                      expected: [String: Entry]?, _ body: (Int32, String) throws -> T) throws -> T {
        let components = relative.split(separator: "/").map(String.init)
        guard let leaf = components.last, components.allSatisfy({ $0 != "." && $0 != ".." }) else { throw refused() }
        var opened: [Int32] = []; defer { for fd in opened.reversed() { close(fd) } }
        var parent = root, path = ""
        for name in components.dropLast() {
            let fd = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard fd >= 0 else { throw refused("source 부모 경로") }; opened.append(fd)
            path = path.isEmpty ? name : path + "/" + name
            let entry = try directoryEntry(fd)
            if let expected { guard expected[path] == entry else { throw refused() } }
            parents[path] = entry; parent = fd
        }
        return try body(parent, leaf)
    }

    private static func directoryEntry(_ descriptor: Int32) throws -> Entry {
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { throw refused() }
        return Entry(kind: .directory, mode: UInt16(info.st_mode & 0o777), size: 0, digest: "", target: nil, nodeIdentity: node(info))
    }

    private static func fileEntry(_ descriptor: Int32) throws -> Entry {
        var before = stat()
        guard fstat(descriptor, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
              before.st_nlink == 1, before.st_mode & 0o7111 == 0 else { throw refused() }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        var hash = SHA256()
        while true {
            let more = try autoreleasepool {
                guard let bytes = try handle.read(upToCount: 4 * 1024 * 1024), !bytes.isEmpty else { return false }
                try Task.checkCancellation(); hash.update(data: bytes); return true
            }
            if !more { break }
        }
        var after = stat()
        guard fstat(descriptor, &after) == 0, same(before, after) else { throw refused() }
        return Entry(kind: .file, mode: UInt16(before.st_mode & 0o777), size: before.st_size,
            digest: hash.finalize().map { String(format: "%02x", $0) }.joined(), target: nil, nodeIdentity: node(before))
    }

    private static func same(_ a: stat, _ b: stat) -> Bool {
        a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_uid == b.st_uid && a.st_mode == b.st_mode
            && a.st_nlink == b.st_nlink && a.st_size == b.st_size
            && a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec
            && a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
    }
    private static func node(_ value: stat) -> String { "\(value.st_dev):\(value.st_ino):\(value.st_uid)" }
    private static func digest(_ value: Data) -> String { SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined() }
    private static func refused(_ condition: String = "링크·대상 identity") -> DomainError {
        DomainError(summary: "수동 Flutter source 파일 링크 또는 대상의 추적·경로·보존 조건을 확인할 수 없습니다: \(condition).",
            remediation: Remediation(summary: "추적된 내부 일반 source 파일 링크만 지원합니다. 기존 링크·대상·lockfile을 보존하고 준비 상태를 확인한 뒤 다시 실행하세요."))
    }
}

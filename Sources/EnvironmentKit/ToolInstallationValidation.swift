import Core
import Darwin
import Foundation

/// Build-runner labels are not deployment targets. Read each staged Mach-O's
/// actual architecture/minimum OS and reject external non-system dependencies.
enum ToolInstallationValidation {
    static func validate(stage: URL, executable: String, version: String, tool: String,
                         host: ToolPreparationHost, runner: any ProcessRunner) async throws {
        let manager = FileManager.default
        let main = stage.appendingPathComponent(executable)
        let binaries = try machOBinaries(stage: stage, main: main)
        var executableRpaths: [URL] = []
        var inspections: [(binary: URL, rpaths: [URL], libraryIDs: [String], dependencies: [String])] = []
        guard let root = canonical(stage)?.path else { throw InstallationExecution.failure("Tool stage cannot be inspected") }
        func contained(_ path: URL) -> Bool { canonical(path)?.path.hasPrefix(root + "/") == true }
        for binary in binaries {
            try Task.checkCancellation()
            let architecture = try await runner.run(ProcessCommand("/usr/bin/lipo", ["-archs", binary.path], timeout: .seconds(30)))
            guard architecture.terminationStatus.isSuccess,
                  architecture.standardOutput.split(whereSeparator: \.isWhitespace).contains(Substring(host.architecture)) else {
                throw InstallationExecution.failure("Pinned tool has no verified \(host.architecture) executable")
            }
            let settings = try await runner.run(ProcessCommand("/usr/bin/otool", ["-arch", host.architecture, "-l", binary.path], timeout: .seconds(30)))
            let lines = settings.standardOutput.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            var minimums: [SemanticVersion] = []
            var rpaths: [String] = []
            var platforms: [String] = []
            var libraryIDs: [String] = []
            var command = ""
            for line in lines {
                if line.hasPrefix("cmd ") { command = String(line.dropFirst(4)) }
                let fields = line.split(whereSeparator: \.isWhitespace)
                if fields.count >= 2,
                   (command == "LC_BUILD_VERSION" && fields[0] == "minos" || command == "LC_VERSION_MIN_MACOSX" && fields[0] == "version"),
                   let version = SemanticVersion(String(fields[1])) { minimums.append(version) }
                if command == "LC_BUILD_VERSION", fields.count >= 2, fields[0] == "platform" { platforms.append(String(fields[1]).lowercased()) }
                if command == "LC_VERSION_MIN_MACOSX" { platforms.append("macos") }
                if command == "LC_RPATH", line.hasPrefix("path "), let path = line.dropFirst(5).components(separatedBy: " (offset").first { rpaths.append(path) }
                if command == "LC_ID_DYLIB", line.hasPrefix("name "), let name = line.dropFirst(5).components(separatedBy: " (offset").first { libraryIDs.append(name) }
            }
            guard settings.terminationStatus.isSuccess, !minimums.isEmpty, !platforms.isEmpty,
                  platforms.allSatisfy({ ["1", "macos"].contains($0) }), minimums.allSatisfy({ $0 <= host.macOS }) else {
                throw InstallationExecution.failure("Pinned tool minimum macOS is unknown or newer than this host")
            }
            let localRpaths = rpaths.compactMap { expand($0, binary: binary, main: main) }
            if binary == main { executableRpaths = localRpaths }
            let libraries = try await runner.run(ProcessCommand("/usr/bin/otool", ["-arch", host.architecture, "-L", binary.path], timeout: .seconds(30)))
            guard libraries.terminationStatus.isSuccess else { throw InstallationExecution.failure("Pinned tool libraries cannot be inspected") }
            let dependencies = libraries.standardOutput.split(whereSeparator: \.isNewline).dropFirst()
                .map { $0.trimmingCharacters(in: .whitespaces).components(separatedBy: " (compatibility version")[0] }
            inspections.append((binary, localRpaths, libraryIDs, dependencies))
        }
        var internalRpaths: [URL] = []
        var identities: [String: Set<String>] = [:]
        for inspection in inspections {
            if let binary = canonical(inspection.binary) { identities[binary.path, default: []].formUnion(inspection.libraryIDs) }
            for path in inspection.rpaths {
                guard let resolved = canonical(path) else { continue }
                var directory: ObjCBool = false
                if (resolved.path == root || contained(resolved)), manager.fileExists(atPath: resolved.path, isDirectory: &directory), directory.boolValue {
                    internalRpaths.append(resolved)
                }
            }
        }
        for inspection in inspections {
            try Task.checkCancellation()
            for dependency in inspection.dependencies {
                if inspection.libraryIDs.contains(dependency) { continue }
                let absolute = dependency.hasPrefix("/") ? URL(fileURLWithPath: dependency).standardizedFileURL.path : dependency
                if absolute.hasPrefix("/usr/lib/") || absolute.hasPrefix("/System/Library/") { continue }
                let candidates: [URL]
                if dependency.hasPrefix("@rpath/") {
                    candidates = (inspection.rpaths + executableRpaths)
                        .map { $0.appendingPathComponent(String(dependency.dropFirst(7))) }
                } else { candidates = expand(dependency, binary: inspection.binary, main: main).map { [$0] } ?? [] }
                if candidates.contains(where: { contained($0) && manager.fileExists(atPath: $0.path) }) { continue }
                let matches: Set<String> = if dependency.hasPrefix("@rpath/"), candidates.allSatisfy({ contained($0) }) {
                    Set(internalRpaths.compactMap { path in
                        guard let target = canonical(path.appendingPathComponent(String(dependency.dropFirst(7)))) else { return nil }
                        guard contained(target), manager.fileExists(atPath: target.path), identities[target.path]?.contains(dependency) == true else { return nil }
                        return target.path
                    })
                } else { [] }
                guard matches.count == 1 else { throw InstallationExecution.failure("Pinned tool needs an unapproved external library; prepare it manually without hidden downloads") }
            }
        }
        var arguments = ["-i", "PATH=/usr/bin:/bin", "HOME=\(stage.path)"]
        if tool == "java" { arguments.append("JAVA_HOME=\(main.deletingLastPathComponent().deletingLastPathComponent().path)") }
        arguments += [main.path] + (tool == "java" ? ["-version"] : ["--version"])
        let output = try await runner.run(ProcessCommand("/usr/bin/env", arguments, workingDirectory: stage, timeout: .seconds(30)))
        guard output.terminationStatus.isSuccess, versionMatches(output.combinedOutput, version: version, tool: tool) else {
            throw InstallationExecution.failure("Staged tool does not report the approved exact version/vendor")
        }
        if tool == "ruby" {
            let features = try await runner.run(ProcessCommand("/usr/bin/env", ["-i", "PATH=/usr/bin:/bin", "HOME=\(stage.path)", main.path,
                "--disable-gems", "-ropenssl", "-rpsych", "-rzlib", "-rfiddle", "-e", "print RUBY_VERSION"], workingDirectory: stage, timeout: .seconds(30)))
            guard features.terminationStatus.isSuccess, features.standardOutput == version else {
                throw InstallationExecution.failure("Portable Ruby's required bundled libraries cannot load; no source compilation or dependency installation was started")
            }
        }
    }

    static func versionMatches(_ output: String, version: String, tool: String) -> Bool {
        let expected = tool == "java" ? String(version.dropFirst("temurin-".count)) : version
        if tool == "java", !output.localizedCaseInsensitiveContains("Temurin") { return false }
        if tool == "node" {
            return output.range(of: "(?m)^v" + NSRegularExpression.escapedPattern(for: expected) + #"\r?$"#, options: .regularExpression) != nil
        }
        return output.range(of: "(?<![0-9.])" + NSRegularExpression.escapedPattern(for: expected) + "(?![0-9.])", options: .regularExpression) != nil
    }

    private static func machOBinaries(stage: URL, main: URL) throws -> [URL] {
        var binaries = [main]
        guard let members = FileManager.default.enumerator(at: stage, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else {
            throw InstallationExecution.failure("Tool stage cannot be inspected")
        }
        for case let member as URL in members where member != main {
            let values = try member.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            let magic = Array(try Data(contentsOf: member, options: .mappedIfSafe).prefix(4))
            if [[UInt8(0xcf), 0xfa, 0xed, 0xfe], [0xfe, 0xed, 0xfa, 0xcf], [0xca, 0xfe, 0xba, 0xbe], [0xbe, 0xba, 0xfe, 0xca]].contains(magic) {
                binaries.append(member)
            }
        }
        return binaries
    }

    private static func expand(_ value: String, binary: URL, main: URL) -> URL? {
        if value.hasPrefix("@loader_path/") { return binary.deletingLastPathComponent().appendingPathComponent(String(value.dropFirst(13))) }
        if value.hasPrefix("@executable_path/") { return main.deletingLastPathComponent().appendingPathComponent(String(value.dropFirst(17))) }
        if value.hasPrefix("/") { return URL(fileURLWithPath: value) }
        return nil
    }

    private static func canonical(_ path: URL) -> URL? {
        guard !path.path.utf8.contains(0) else { return nil }
        let manager = FileManager.default
        var ancestor = path.path
        guard ancestor.hasPrefix("/") else { return nil }
        var missing: [String] = []
        while !manager.fileExists(atPath: ancestor), ancestor != "/" {
            let attributes = try? manager.attributesOfItem(atPath: ancestor)
            if attributes?[.type] as? FileAttributeType == .typeSymbolicLink { return nil }
            guard let slash = ancestor.lastIndex(of: "/") else { return nil }
            let component = String(ancestor[ancestor.index(after: slash)...])
            if !component.isEmpty { missing.append(component) }
            ancestor = slash == ancestor.startIndex ? "/" : String(ancestor[..<slash])
        }
        guard let buffer = realpath(ancestor, nil) else { return nil }
        defer { free(buffer) }
        var components = String(cString: buffer).split(separator: "/").map(String.init)
        for component in missing.reversed() {
            if component == "." { continue }
            if component == ".." { if !components.isEmpty { components.removeLast() } }
            else { components.append(component) }
        }
        return URL(fileURLWithPath: "/" + components.joined(separator: "/"))
    }
}

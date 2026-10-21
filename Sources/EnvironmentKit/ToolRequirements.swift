import AndroidKit
import Core
import Foundation

/// Fixed candidates remain proposals until the release's actual tuple is measured.
/// Declaration bytes are never edited; unsupported syntax is never evaluated.
enum ToolRequirements {
    static let nodeCandidate = "22.23.2"
    static let rubyCandidate = "3.2.2"
    static let javaCandidate = "temurin-17.0.18+8"

    private struct Declaration { let value: String; let origin: String }

    static func resolve(anchor: ProjectAnchor, platforms: [ProjectPlatform], runner: any ProcessRunner) async throws -> [ToolPreparationRequirement] {
        var tools: [PreparedTool] = anchor.framework == .reactNative ? [.node] : []
        let podfile = anchor.directory.appendingPathComponent(anchor.framework == .nativeIOS ? "Podfile" : "ios/Podfile")
        if platforms.contains(.ios), anchor.hasGemfile || anchor.rubyPin != nil || FileManager.default.fileExists(atPath: podfile.path) {
            tools.append(.ruby)
        }
        if platforms.contains(.android), anchor.hasAndroidDirectory { tools.append(.java) }
        var result: [ToolPreparationRequirement] = []
        for tool in tools {
            try Task.checkCancellation()
            var declarations = declarations(tool, anchor: anchor)
            if tool == .ruby, let value = rubyConstraint(anchor),
               ToolPreparationRequirement(tool: tool, version: value, source: CheckSource(origin: "Gemfile")).exactVersion != nil {
                declarations.append(Declaration(value: value, origin: "Gemfile ruby"))
            }
            // Conflicting exact declarations reach the provider together.
            // Qualified Java vendors stay verbatim instead of becoming Temurin.
            if !declarations.isEmpty, declarations.allSatisfy({
                ToolPreparationRequirement(tool: tool, version: $0.value, source: CheckSource(origin: $0.origin)).exactVersion != nil
            }) {
                let observed = tool == .java ? try await observedVersion(tool, directory: anchor.directory, runner: runner) : nil
                for declaration in declarations {
                    result.append(ToolPreparationRequirement(tool: tool, version: declaration.value,
                        source: CheckSource(tier: 1, origin: declaration.origin),
                        blocker: compatibility(tool, version: declaration.value, anchor: anchor, existing: observed == declaration.value)))
                }
                continue
            }
            var observedIdentity: String?
            func compatible(_ version: String) -> Bool {
                let parsed = tool == .java ? ToolJavaObservation.numeric(version) : SemanticVersion(version)
                guard let value = parsed, declarations.allSatisfy({ matches($0.value, tool: tool, identity: version, version: value) }) else { return false }
                return compatibility(tool, version: version, anchor: anchor, existing: version == observedIdentity) == nil
            }
            let fixed = switch tool { case .node: nodeCandidate; case .ruby: rubyCandidate; case .java: javaCandidate }
            let preflight = compatibility(tool, version: fixed, anchor: anchor)
            let android = anchor.framework == .nativeAndroid ? anchor.directory : anchor.directory.appendingPathComponent("android")
            let hasBuildInputs = ["build.gradle", "build.gradle.kts", "app/build.gradle", "app/build.gradle.kts", "gradle/wrapper/gradle-wrapper.properties"].contains { FileManager.default.fileExists(atPath: android.appendingPathComponent($0).path) }
            let unknownJava = tool == .java && !hasBuildInputs && ["An exact Gradle", "One exact AGP", "The bundled"].contains { preflight?.hasPrefix($0) == true }
            let existing = unknownJava ? nil : try await observedVersion(tool, directory: anchor.directory, runner: runner)
            observedIdentity = existing
            let selected = existing.flatMap { compatible($0) ? $0 : nil } ?? (compatible(fixed) ? fixed : nil)
            var origins = declarations.map { "\($0.origin) declares \($0.value)" }
            if origins.isEmpty, tool == .node { origins = anchor.nodeEngines.map { "\($0.origin) engines.node \($0.range)" } }
            if origins.isEmpty, tool == .ruby, let ruby = rubyConstraint(anchor) { origins = ["Gemfile ruby \(ruby)"] }
            let tier: Int = origins.isEmpty ? 2 : 1
            let origin = origins.isEmpty ? "Gradle wrapper + AGP/JDK compatibility" : origins.joined(separator: "; ")
            result.append(ToolPreparationRequirement(tool: tool, version: selected ?? declarations.first?.value,
                source: CheckSource(tier: tier,
                    origin: origin + (selected == existing && selected != nil ? "; observed existing project tool" : "; fixed candidate (actual validation pending)")),
                blocker: selected == nil ? "No exact existing tool or fixed candidate satisfies all project declarations and known compatibility conditions. Preserve declarations and select an exact compatible distribution manually." : nil))
        }
        return result
    }

    private static func declarations(_ tool: PreparedTool, anchor: ProjectAnchor) -> [Declaration] {
        var roots = [anchor.directory]
        if let root = anchor.workspaceRoot?.directory, root != anchor.directory { roots.append(root) }
        var found: [Declaration] = []
        let aliases = tool == .node ? ["node", "nodejs"] : [tool.rawValue]
        let filenames: [String] = switch tool { case .node: [".nvmrc", ".node-version"]; case .ruby: [".ruby-version"]; case .java: [".java-version"] }
        for (index, root) in roots.enumerated() {
            let prefix = index == 0 ? "" : "workspace/"
            func append(_ raw: String, _ name: String) {
                let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                let scalar = value.range(of: #"^[A-Za-z0-9_.+\-]+$"#, options: .regularExpression) != nil
                found.append(Declaration(value: scalar ? value : "unsupported-declaration", origin: prefix + name))
            }
            for name in filenames {
                let file = root.appendingPathComponent(name)
                if exists(file) { append(read(file) ?? "unsupported-declaration", name) }
            }
            if let text = read(root.appendingPathComponent(".tool-versions")) {
                for line in text.components(separatedBy: .newlines) {
                    let fields = line.components(separatedBy: "#")[0].split(whereSeparator: \.isWhitespace)
                    if let name = fields.first, aliases.contains(String(name)) { append(fields.dropFirst().joined(separator: " "), ".tool-versions \(name)") }
                }
            } else if exists(root.appendingPathComponent(".tool-versions")) { append("unsupported-declaration", ".tool-versions") }
            for name in ["mise.toml", ".mise.toml", ".config/mise/config.toml"] {
                let file = root.appendingPathComponent(name)
                guard let text = read(file) else {
                    if exists(file) { append("unsupported-declaration", name) }
                    continue
                }
                var section = ""
                for raw in text.components(separatedBy: .newlines) {
                    let line = raw.components(separatedBy: "#")[0].trimmingCharacters(in: .whitespaces)
                    if line.hasPrefix("[") {
                        section = line
                        if aliases.contains(where: { line == "[tools.\($0)]" }) { append("unsupported-declaration", name + " tools.\(tool.rawValue)") }
                        continue
                    }
                    let fields = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    guard fields.count == 2 else { continue }
                    let key = fields[0].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    guard section == "[tools]" && aliases.contains(key) || section.isEmpty && aliases.contains(where: { key == "tools.\($0)" }) else { continue }
                    let value = fields[1]
                    if value.count >= 2, let quote = value.first, ["\"", "'"].contains(String(quote)), value.last == quote {
                        append(String(value.dropFirst().dropLast()), name + " tools.\(key)")
                    } else { append("unsupported-declaration", name + " tools.\(key)") }
                }
            }
        }
        return found
    }

    private static func compatibility(_ tool: PreparedTool, version: String, anchor: ProjectAnchor, existing: Bool = false) -> String? {
        let parsed = tool == .java ? ToolJavaObservation.numeric(version) : SemanticVersion(version.replacingOccurrences(of: "ruby-", with: ""))
        guard let value = parsed else { return "The declared tool version is not an exact numeric distribution" }
        if tool == .node {
            for range in anchor.nodeEngines {
                guard VersionRange(range.range)?.contains(value) == true else { return "The selected Node does not satisfy readable engines.node in \(range.origin)" }
            }
        }
        if tool == .ruby, let constraint = rubyConstraint(anchor), !rubyMatches(constraint, value) { return "The selected Ruby does not satisfy the Gemfile ruby requirement" }
        if tool == .java {
            let directory = anchor.framework == .nativeAndroid ? anchor.directory : anchor.directory.appendingPathComponent("android")
            let files = ["gradle/gradle-daemon-jvm.properties", "build.gradle", "build.gradle.kts", "app/build.gradle", "app/build.gradle.kts", "gradle.properties"]
            let projectFiles = ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts", "gradle/libs.versions.toml"]
            for name in Set(files + projectFiles).sorted() {
                let file = directory.appendingPathComponent(name)
                if exists(file), read(file) == nil { return "The project JVM declaration input \(name) could not be read; preserve it and inspect access/encoding manually" }
            }
            let contents = files.compactMap { read(directory.appendingPathComponent($0)) }.joined(separator: "\n")
            let requiredMajors = captures(#"(?:toolchainVersion\s*=\s*|JavaLanguageVersion\.of\s*\(\s*|jvmToolchain\s*\(\s*|JavaVersion\.VERSION_(?:1_)?)([0-9]+)"#, in: contents).compactMap(Int.init)
            if let required = requiredMajors.max(), value.major < required { return "The project requires JDK \(required); a JDK \(value.major) candidate cannot satisfy it" }
            let vendors = captures(#"(?m)^\s*toolchainVendor\s*=\s*([^\s]+)"#, in: contents)
                + captures(#"JvmVendorSpec\.([A-Z_]+)"#, in: contents)
            for vendor in vendors {
                let normalized = vendor.lowercased()
                let required = ["adoptium", "temurin", "eclipse_adoptium"].contains(normalized) ? "temurin" : ["azul", "zulu"].contains(normalized) ? "zulu" : normalized
                if !version.hasPrefix(required + "-") { return "The project declares another JDK vendor; preserve that declaration instead of substituting a vendor" }
            }
            guard let wrapper = read(directory.appendingPathComponent("gradle/wrapper/gradle-wrapper.properties")),
                  let gradleText = captures(#"gradle-([0-9]+(?:\.[0-9]+){1,2})-(?:all|bin)\.zip"#, in: wrapper).first,
                  let gradle = SemanticVersion(gradleText) else { return existing ? nil : "An exact Gradle wrapper is required before proposing a JDK" }
            let agpContents = projectFiles.compactMap { read(directory.appendingPathComponent($0)) }.joined(separator: "\n")
            let plugins = captures(#"com\.android\.application[\"']?\s*\)?\s*version\s*[\"']([0-9.]+)"#, in: agpContents)
                + captures(#"com\.android\.tools\.build:gradle:([0-9.]+)"#, in: agpContents)
                + captures(#"(?m)^\s*agp\s*=\s*[\"']([0-9.]+)"#, in: agpContents)
            guard Set(plugins).count == 1, let agpText = plugins.first, let agp = SemanticVersion(agpText) else {
                return existing ? nil : "One exact AGP compatibility input is required before proposing a JDK"
            }
            return AndroidCompatibility.preparationJDKBlocker(major: value.major, gradle: gradle, agp: agp)
        }
        return nil
    }

    private static func rubyConstraint(_ anchor: ProjectAnchor) -> String? {
        let root = anchor.gemInstallProcess?.workingDirectory ?? anchor.directory
        let file = root.appendingPathComponent("Gemfile")
        guard let text = read(file) else { return exists(file) ? "unsupported unreadable Gemfile ruby declaration" : nil }
        let values = captures(#"(?m)^\s*ruby\s*(?:\(\s*)?[\"']([^\"']+)[\"']\s*\)?\s*(?:#.*)?$"#, in: text)
        if values.count == 1 { return values[0] }
        return text.range(of: #"(?m)^\s*ruby\s"#, options: .regularExpression) == nil ? nil : "unsupported Gemfile ruby declaration"
    }

    private static func rubyMatches(_ requirement: String, _ version: SemanticVersion) -> Bool {
        if let pin = VersionPin(requirement) { return pin.matches(version) }
        if requirement.hasPrefix("~>"), let pin = SemanticVersion(String(requirement.dropFirst(2)).trimmingCharacters(in: .whitespaces)) {
            let parts = requirement.dropFirst(2).trimmingCharacters(in: .whitespaces).split(separator: ".").count
            let ceiling = parts >= 3 ? SemanticVersion(major: pin.major, minor: pin.minor + 1) : SemanticVersion(major: pin.major + 1)
            return version >= pin && version < ceiling
        }
        return VersionRange(requirement)?.contains(version) == true
    }

    private static func matches(_ declaration: String, tool: PreparedTool, identity: String, version: SemanticVersion) -> Bool {
        if tool == .java, declaration.contains("-") {
            guard let split = declaration.firstIndex(where: { $0.isNumber }) else { return false }
            let vendor = String(declaration[..<split])
            let pin = String(declaration[split...])
            guard identity.hasPrefix(vendor) else { return false }
            if pin.contains("+") { return identity == declaration }
            return VersionPin(pin)?.matches(version) == true
        }
        return VersionPin(declaration.replacingOccurrences(of: "ruby-", with: ""))?.matches(version) == true
    }

    private static func observedVersion(_ tool: PreparedTool, directory: URL, runner: any ProcessRunner) async throws -> String? {
        if tool == .java {
            do { return try await ToolJavaObservation.observe(directory: directory, runner: runner)?.identity }
            catch let error as ProcessError { guard case .spawnFailed = error else { throw error }; return nil }
        }
        let result: ProcessResult
        do { result = try await runner.run(ProcessCommand(tool.rawValue, tool == .java ? ["-version"] : ["--version"], workingDirectory: directory, timeout: .seconds(15))) }
        catch let error as ProcessError { guard case .spawnFailed = error else { throw error }; return nil }
        guard result.terminationStatus.isSuccess else { return nil }
        switch tool {
        case .node: return captures(#"(?m)^v([0-9]+\.[0-9]+\.[0-9]+)\r?$"#, in: result.combinedOutput).first
        case .ruby: return captures(#"(?m)^ruby ([0-9]+\.[0-9]+\.[0-9]+)(?:p[0-9]+)?(?:\s|$)"#, in: result.combinedOutput).first
        case .java: return captures(#"Temurin-([0-9]+\.[0-9]+\.[0-9]+\+[0-9]+)(?:\s|\)|$)"#, in: result.combinedOutput).first.map { "temurin-" + $0 }
        }
    }

    private static func read(_ file: URL) -> String? { try? String(contentsOf: file, encoding: .utf8) }
    private static func exists(_ file: URL) -> Bool {
        FileManager.default.fileExists(atPath: file.path) || (try? FileManager.default.destinationOfSymbolicLink(atPath: file.path)) != nil
    }
    private static func captures(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }
}

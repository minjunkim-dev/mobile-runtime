import Core
import AndroidKit
@testable import EnvironmentKit
import Foundation
import TestSupport
import Testing

@Suite("project tool preparation requirements")
struct ToolRequirementsTests {
    @Test("Swift-only native iOS adds no Ruby requirement or tool probe")
    func swiftOnlyNativeIOS() async throws {
        let repo = try FixtureRepo()
        try repo.write("App.xcodeproj/project.pbxproj", "native fixture")
        let anchor = try #require(ProjectAnchor.detect(from: repo.root))
        let runner = FakeProcessRunner()
        #expect(try await ToolRequirements.resolve(anchor: anchor, platforms: [.ios], runner: runner).isEmpty)
        #expect(runner.log.all.isEmpty)
    }

    @Test("an unreadable Tier 1 declaration cannot become an absent declaration", arguments: [".nvmrc", ".tool-versions", "mise.toml", "Gemfile"])
    func unreadableDeclaration(_ filename: String) async throws {
        let repo = try project()
        try Data([0xff, 0xfe]).write(to: repo.url(filename))
        let tool: PreparedTool = filename == "Gemfile" ? .ruby : .node
        let requirement = try #require(try await resolve(repo).first { $0.tool == tool })
        #expect(requirement.blocker != nil)
    }
    @Test("exact project declarations outrank the fixed candidates and preserve the Java vendor")
    func exactDeclarations() async throws {
        let repo = try project()
        try repo.write(".nvmrc", "24.14.0\n")
        try repo.write(".ruby-version", "3.3.8\n")
        try repo.write(".java-version", "zulu-21.0.11+10\n")
        let requirements = try await resolve(repo)
        #expect(requirements.first { $0.tool == .node }?.version == "24.14.0")
        #expect(requirements.first { $0.tool == .ruby }?.version == "3.3.8")
        #expect(requirements.first { $0.tool == .java }?.version == "zulu-21.0.11+10")
        #expect(requirements.allSatisfy { $0.source.tier == 1 })
    }

    @Test("a v-prefixed exact Node declaration keeps its normalized compatibility")
    func exactNodePrefix() async throws {
        let repo = try project()
        try repo.write(".nvmrc", "v22.23.2\n")
        let requirement = try #require(try await resolve(repo).first { $0.tool == .node })
        #expect(requirement.exactVersion == "22.23.2")
        #expect(requirement.blocker == nil)
    }

    @Test("compatible observed Node is reused before proposing a pinned candidate")
    func compatibleExisting() async throws {
        let repo = try project()
        let requirements = try await resolve(repo, runner: FakeProcessRunner(responses: ["node --version": .ok("v22.17.0\n"), "ruby --version": .failed(127, "fixture tool absent"), "java -version": .failed(127, "fixture tool absent")]))
        #expect(requirements.first { $0.tool == .node }?.version == "22.17.0")
        #expect(requirements.first { $0.tool == .node }?.source.origin.contains("existing") == true)
    }

    @Test("range conflicts and JDK 21 requirements never produce the JDK 17 candidate")
    func incompatibleCandidate() async throws {
        let repo = try project()
        try repo.write("package.json", #"{"dependencies":{"react-native":"0.83.10"},"engines":{"node":">=24"}}"#)
        try repo.write("android/gradle/gradle-daemon-jvm.properties", "toolchainVersion=21\n")
        let requirements = try await resolve(repo)
        #expect(requirements.first { $0.tool == .node }?.blocker != nil)
        #expect(requirements.first { $0.tool == .java }?.blocker != nil)
        #expect(requirements.first { $0.tool == .java }?.version != "temurin-17.0.18+8")
    }

    @Test("JDK 21 compilation declarations also block the JDK 17 candidate", arguments: [
        "java { toolchain { languageVersion = JavaLanguageVersion.of(21) } }",
        "kotlin { jvmToolchain(21) }",
        "java { sourceCompatibility = JavaVersion.VERSION_21 }",
    ])
    func compilationJDK(_ declaration: String) async throws {
        let repo = try project()
        try repo.write("android/app/build.gradle", declaration)
        let java = try #require(try await resolve(repo).first { $0.tool == .java })
        #expect(java.version != "temurin-17.0.18+8")
        #expect(java.blocker != nil)
    }

    @Test("preparation and doctor share the unchanged AGP Gradle JDK tables")
    func sharedCompatibilityTable() {
        #expect(AndroidCompatibility.preparationJDKBlocker(major: 17, gradle: SemanticVersion("8.10.2")!, agp: SemanticVersion("8.7.3")!) == nil)
        #expect(AndroidCompatibility.preparationJDKBlocker(major: 21, gradle: SemanticVersion("8.0")!, agp: SemanticVersion("8.0")!) != nil)
        #expect(AndroidCompatibility.preparationJDKBlocker(major: 11, gradle: SemanticVersion("9.1")!, agp: SemanticVersion("7.4")!) != nil)
        #expect(AndroidCompatibility.preparationJDKBlocker(major: 17, gradle: SemanticVersion("9.7")!, agp: SemanticVersion("10.0")!) != nil)
    }

    @Test("mise and asdf declarations are read without changing them; conflicts stay explicit")
    func managerDeclarations() async throws {
        let repo = try project()
        let text = "[tools]\nnode = \"22.23.2\"\nruby = \"3.2.2\"\njava = \"temurin-17.0.18+8\"\n[env]\nPRIVATE_VALUE = \"never-copy\"\n"
        try repo.write("mise.toml", text)
        try repo.write(".tool-versions", "nodejs 24.14.0\n")
        let requirements = try await resolve(repo)
        #expect(Set(requirements.filter { $0.tool == .node }.compactMap(\.version)) == ["22.23.2", "24.14.0"])
        #expect(requirements.first { $0.tool == .java }?.version == "temurin-17.0.18+8")
        #expect(!requirements.contains { $0.source.origin.contains("never-copy") || $0.version?.contains("never-copy") == true })
        #expect(try String(contentsOf: repo.url("mise.toml"), encoding: .utf8) == text)
    }

    private func resolve(_ repo: FixtureRepo, runner: (any ProcessRunner)? = nil) async throws -> [ToolPreparationRequirement] {
        let anchor = try #require(ProjectAnchor.detect(from: repo.root))
        return try await ToolRequirements.resolve(anchor: anchor, platforms: [.ios, .android],
            runner: runner ?? FakeProcessRunner(responses: ["node --version": .failed(127, "fixture tool absent"), "ruby --version": .failed(127, "fixture tool absent"), "java -version": .failed(127, "fixture tool absent")]))
    }

    private func project() throws -> FixtureRepo {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies":{"react-native":"0.83.10"},"engines":{"node":">=22.11.0"}}"#)
        try repo.write("Gemfile", "source 'https://rubygems.org'\nruby '>= 2.6.10'\ngem 'cocoapods'\n")
        try repo.directory("ios")
        try repo.write("android/build.gradle", "plugins { id 'com.android.application' version '8.7.3' apply false }\n")
        try repo.write("android/gradle/wrapper/gradle-wrapper.properties", "distributionUrl=https\\://services.gradle.org/distributions/gradle-8.10.2-bin.zip\n")
        return repo
    }
}

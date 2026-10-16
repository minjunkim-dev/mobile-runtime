import Core
import Foundation
import TestSupport
import Testing

@testable import AndroidKit

@Suite("Android project input paths")
struct AndroidInputPathTests {
    @Test("wrapper evidence names the file in the selected framework root", arguments: [false, true])
    func wrapperSource(native: Bool) throws {
        let fixture = try InputPathFixture(native: native)
        guard case .success(let wrapper) = fixture.context.wrapper() else {
            Issue.record("fixture wrapper must be readable")
            return
        }
        #expect(wrapper.source.origin == fixture.prefix + "gradle/wrapper/gradle-wrapper.properties")
        #expect(fixture.runner.log.all.isEmpty)
    }

    @Test("missing wrapper diagnostics identify the actual files to restore", arguments: [false, true])
    func missingWrapper(native: Bool) async throws {
        let fixture = try InputPathFixture(native: native)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fixture.directory.appendingPathComponent("gradlew").path)
        try FileManager.default.removeItem(at: fixture.directory.appendingPathComponent("gradle/wrapper/gradle-wrapper.jar"))
        try FileManager.default.removeItem(at: fixture.directory.appendingPathComponent("gradle/wrapper/gradle-wrapper.properties"))
        let report = await DoctorEngine(checks: androidChecks(context: fixture.context)).run(only: ["android.gradle.wrapper"])
        let result = try #require(report.checks.first)
        let prefix = fixture.prefix
        #expect(result.status == .error)
        #expect(result.outcome.observed == "missing executable \(prefix)gradlew, \(prefix)gradle/wrapper/gradle-wrapper.jar, \(prefix)gradle/wrapper/gradle-wrapper.properties")
        #expect(result.outcome.source.origin == prefix + "gradle/wrapper")
        #expect(fixture.runner.log.all.isEmpty)
    }

    @Test("SDK evidence and conflict recovery name the selected local.properties", arguments: [false, true])
    func sdkPaths(native: Bool) async throws {
        let fixture = try InputPathFixture(native: native)
        guard case .resolved(_, let source) = fixture.context.sdkRoot() else {
            Issue.record("fixture SDK root must resolve")
            return
        }
        #expect(source.origin == fixture.prefix + "local.properties sdk.dir")
        let conflict = fixture.makeContext(androidHome: fixture.repo.url("another-sdk").path)
        let report = await DoctorEngine(checks: androidChecks(context: conflict)).run(only: ["android.sdk"])
        let result = try #require(report.checks.first)
        #expect(result.status == .error)
        #expect(result.outcome.observed == fixture.prefix + "local.properties sdk.dir and ANDROID_HOME point to different SDK roots")
        #expect(result.outcome.source.origin == fixture.prefix + "local.properties + ANDROID_HOME")
        #expect(result.outcome.remediation?.summary == "Make \(fixture.prefix)local.properties sdk.dir and ANDROID_HOME name one installed SDK.")
        #expect(fixture.runner.log.all.isEmpty)
    }

    @Test("daemon JDK evidence names the selected Gradle files", arguments: [false, true])
    func daemonJDKPaths(native: Bool) throws {
        let fixture = try InputPathFixture(native: native)
        let criteria = fixture.prefix + "gradle/gradle-daemon-jvm.properties"
        try fixture.repo.write(criteria, "toolchainVersion=17\n")
        #expect(fixture.context.daemonJDKRequirement().origin == criteria)
        try FileManager.default.removeItem(at: fixture.repo.url(criteria))
        try fixture.repo.write(fixture.prefix + "gradle.properties", "org.gradle.java.home=/fixture-jdk\n")
        #expect(fixture.context.daemonJDKRequirement().origin == fixture.prefix + "gradle.properties org.gradle.java.home")
        #expect(fixture.runner.log.all.isEmpty)
    }
}

private struct InputPathFixture {
    let repo: FixtureRepo
    let anchor: ProjectAnchor
    let prefix: String
    let runner = FakeProcessRunner()
    var directory: URL { prefix.isEmpty ? repo.root : repo.url("android") }
    var context: AndroidDoctorContext { makeContext() }

    init(native: Bool) throws {
        repo = try FixtureRepo()
        prefix = native ? "" : "android/"
        if native {
            try repo.write("settings.gradle.kts", "include(\":app\")\n")
        } else {
            try repo.write("package.json", #"{"dependencies":{"react-native":"0.83.1"}}"#)
        }
        let wrapper = try repo.write(prefix + "gradlew", "fixture wrapper")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
        try repo.write(prefix + "gradle/wrapper/gradle-wrapper.jar", "fixture jar")
        try repo.write(prefix + "gradle/wrapper/gradle-wrapper.properties", "distributionUrl=https\\://services.gradle.org/distributions/gradle-8.13-bin.zip\n")
        try repo.write(prefix + "local.properties", "sdk.dir=\(repo.url("sdk").path)\n")
        anchor = try #require(ProjectAnchor.detect(from: repo.root))
    }

    func makeContext(androidHome: String? = nil) -> AndroidDoctorContext {
        AndroidDoctorContext(anchor: anchor, config: ConfigContext.detect(anchor: anchor, workingDirectory: repo.root),
            hostRunner: runner, projectRunner: runner,
            environment: AndroidEnvironment(values: androidHome.map { ["ANDROID_HOME": $0] } ?? [:]))
    }
}

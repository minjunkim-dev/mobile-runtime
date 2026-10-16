import AndroidKit
import Core
import Foundation
import TestSupport
import Testing

@Suite("selected Java properties observation")
struct JavaObservationTests {
    @Test("raw runtime build vendor architecture and home come from properties")
    func properties() async throws {
        let runner = FakeProcessRunner(responses: ["/selected/bin/java -XshowSettings:properties -version": .ok("java.version = 21.0.11\njava.runtime.version = 21.0.11+10-LTS\njava.vendor = Azul Systems, Inc.\njava.home = /selected\nos.arch = aarch64\n")])
        let result = try await AndroidDoctorContext.observeJava(executable: "/selected/bin/java", directory: URL(fileURLWithPath: "/fixture"), runner: runner)
        guard case .success(let java) = result else { Issue.record("properties unavailable"); return }
        #expect(java.versionText == "21.0.11")
        #expect(java.propertiesVersion == "21.0.11")
        #expect(java.runtimeVersion == "21.0.11+10-LTS")
        #expect(java.vendor == "Azul Systems, Inc.")
        #expect(java.architecture == "aarch64")
        #expect(java.home == "/selected")
    }

    @Test("banner fallback does not invent properties and failures retain diagnostics")
    func missingAndFailure() async throws {
        let runner = FakeProcessRunner(responses: ["java -XshowSettings:properties -version": .ok("openjdk version \"17.0.18\"\n")])
        guard case .success(let java) = try await AndroidDoctorContext.observeJava(directory: URL(fileURLWithPath: "/fixture"), runner: runner) else { Issue.record("legacy fallback lost"); return }
        #expect(java.propertiesVersion == nil && java.runtimeVersion == nil && java.vendor == nil && java.architecture == nil)
        let failed = FakeProcessRunner(responses: ["java -XshowSettings:properties -version": .failed(2, "controlled JDK diagnostic")])
        guard case .failure(let error) = try await AndroidDoctorContext.observeJava(directory: URL(fileURLWithPath: "/fixture"), runner: failed) else { Issue.record("failure lost"); return }
        #expect(error.description == "controlled JDK diagnostic")
    }

    @Test("Java observation propagates cancellation")
    func cancellation() async throws {
        await #expect(throws: CancellationError.self) {
            _ = try await AndroidDoctorContext.observeJava(directory: URL(fileURLWithPath: "/fixture"), runner: CancelledJavaRunner())
        }
    }
}

private struct CancelledJavaRunner: ProcessRunner {
    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult { throw CancellationError() }
    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 { throw CancellationError() }
}

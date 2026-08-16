import Foundation
import Testing
import TestSupport

@testable import Core

private func validation(_ outcome: CheckOutcome) -> UpContext {
    var context = UpContext()
    context.validation = DoctorReport(checks: [
        CheckResult(id: "node.version", category: "Node", title: "Node", outcome: outcome)
    ])
    return context
}

private func result(
    _ id: String,
    _ status: StageStatus,
    _ duration: Duration = .milliseconds(1204),
    detail: String? = nil
) -> StageResult {
    StageResult(id: id, status: status, duration: duration, detail: detail)
}

@Suite("up --json document")
struct UpJSONTests {
    @Test("envelope carries schema version, tool version, command and status")
    func envelope() throws {
        let json = try decode(UpReport(stages: [result("validate", .pass)]))

        #expect(json["schemaVersion"] as? Int == 1)
        #expect(json["toolVersion"] as? String == "9.9.9")
        #expect(json["command"] as? String == "up")
        #expect(json["status"] as? String == "pass")
        #expect(json["error"] == nil)
    }

    /// The envelope field is shared with doctor, so it has to speak doctor's whole
    /// vocabulary: the machine that makes doctor say `warning` cannot make up say
    /// `pass` about the same checks.
    @Test("a warning validate found reaches the envelope status")
    func warningStatus() throws {
        let report = UpReport(
            stages: [result("validate", .pass)],
            context: validation(.warning(remediation: Remediation(summary: "switch node")))
        )

        #expect(report.exitCode == 0)
        #expect(try decode(report)["status"] as? String == "warning")
    }

    @Test("each stage carries id, status and elapsed milliseconds")
    func stages() throws {
        let report = UpReport(stages: [
            result("validate", .pass),
            result("dependencies", .skipped, .milliseconds(4), detail: "node_modules present"),
        ])

        let stages = try #require(try decode(report)["stages"] as? [[String: Any]])

        #expect(stages.map { $0["id"] as? String } == ["validate", "dependencies"])
        #expect(stages.map { $0["status"] as? String } == ["pass", "skipped"])
        #expect(stages[0]["durationMs"] as? Int == 1204)
        #expect(stages[0]["detail"] == nil)
        #expect(stages[1]["detail"] as? String == "node_modules present")
    }

    @Test("a failure serialises the domain error and its remediation")
    func failure() throws {
        let report = UpReport(
            stages: [result("validate", .failed)],
            failure: .domain(
                DomainError(
                    summary: "simulator runtime missing",
                    remediation: Remediation(
                        summary: "Install it.",
                        command: "xcodebuild -downloadPlatform iOS",
                        url: "https://example.test"
                    )
                )
            )
        )

        let json = try decode(report)
        let error = try #require(json["error"] as? [String: Any])

        #expect(json["status"] as? String == "error")
        #expect(error["message"] as? String == "simulator runtime missing")
        let remediation = try #require(error["remediation"] as? [String: Any])
        #expect(remediation["summary"] as? String == "Install it.")
        #expect(remediation["command"] as? String == "xcodebuild -downloadPlatform iOS")
        #expect(remediation["url"] as? String == "https://example.test")
    }

    /// `up` does not roll back, so a failed run leaves the Metro it started behind —
    /// and the line that stops it goes to the machine as well as to the human.
    @Test("a failed run that spawned Metro offers mobile down, on both streams")
    func teardownHint() throws {
        var context = UpContext()
        context.metro = MetroProcess(state: .spawned, pid: 65260, logPath: "/tmp/metro.log")
        let report = UpReport(
            stages: [result("build", .failed)],
            context: context,
            failure: .domain(
                DomainError(summary: "the build failed", remediation: Remediation(summary: "Read the log."))
            )
        )

        let error = try #require(try decode(report)["error"] as? [String: Any])

        #expect(error["teardown"] as? String == report.teardownHint)
        #expect(report.teardownHint?.contains("mobile down") == true)
    }

    /// A reused Metro was there before this run. Telling a user to stop what they
    /// were already using is not a next step.
    @Test("a failed run that reused Metro offers nothing to stop")
    func noTeardownHintOnReuse() throws {
        var context = UpContext()
        context.metro = MetroProcess(state: .reused)
        let report = UpReport(
            stages: [result("build", .failed)],
            context: context,
            failure: .tool("build: could not run")
        )

        #expect(report.teardownHint == nil)
        let error = try #require(try decode(report)["error"] as? [String: Any])
        #expect(error["teardown"] == nil)
    }

    /// What the run produced, as opposed to what it did: the stages say a device was
    /// picked, `result` says which one, and a script needs the udid to talk to it.
    @Test("the device a stage selected reaches result.device")
    func resultDevice() throws {
        var context = UpContext()
        context.device = SelectedDevice(
            name: "iPhone 17 Pro", udid: "61DECACB-3D94-4748-B5A2-E7A1EB97E6D5", runtime: "26.5"
        )

        let json = try decode(UpReport(stages: [result("device", .pass)], context: context))
        let device = try #require((json["result"] as? [String: Any])?["device"] as? [String: Any])

        #expect(device["name"] as? String == "iPhone 17 Pro")
        #expect(device["udid"] as? String == "61DECACB-3D94-4748-B5A2-E7A1EB97E6D5")
        #expect(device["runtime"] as? String == "26.5")
    }

    /// The build's output is on disk rather than on the screen now, so the path has to
    /// come out of a run that worked — otherwise only a failure could ever find it.
    @Test("a successful build's log path reaches result.buildLog")
    func resultBuildLog() throws {
        var context = UpContext()
        context.buildLog = "/var/folders/T/mobile/MyApp-1a2b3c4d/build.log"

        let json = try decode(UpReport(stages: [result("build", .pass)], context: context))
        let outcome = try #require(json["result"] as? [String: Any])

        #expect(outcome["buildLog"] as? String == "/var/folders/T/mobile/MyApp-1a2b3c4d/build.log")
    }

    /// What a script can act on after the run. The `.app` path build also settled on
    /// is derived data — true for one machine until the next clean — so it stays
    /// inside the pipeline and the bundle id is what comes out.
    @Test("the bundle id of what was built reaches result")
    func resultBundleID() throws {
        var context = UpContext()
        context.product = BuiltProduct(
            path: "/Users/USER/Library/Developer/Xcode/DerivedData/MyApp-abc/Build/Products/"
                + "Debug-iphonesimulator/MyApp.app",
            bundleIdentifier: "com.example.MyApp"
        )

        let json = try decode(UpReport(stages: [result("build", .pass)], context: context))
        let outcome = try #require(json["result"] as? [String: Any])

        #expect(outcome["bundleId"] as? String == "com.example.MyApp")
        #expect(outcome["app"] == nil)
    }

    /// So CI can tail the bundler's log and kill the process — the pid is there
    /// precisely because a job has to be able to clean up after itself.
    @Test("a spawned Metro reaches result with its pid and log path")
    func resultMetroSpawned() throws {
        var context = UpContext()
        context.metro = MetroProcess(state: .spawned, pid: 4242, logPath: "/tmp/mobile/MyApp/metro.log")

        let json = try decode(UpReport(stages: [result("metro", .pass)], context: context))
        let metro = try #require((json["result"] as? [String: Any])?["metro"] as? [String: Any])

        #expect(metro["state"] as? String == "spawned")
        #expect(metro["pid"] as? Int == 4242)
        #expect(metro["logPath"] as? String == "/tmp/mobile/MyApp/metro.log")
    }

    /// The other half of the same promise: a reused Metro is somebody else's process,
    /// so there is no pid to report and a job must not find one to kill.
    @Test("a reused Metro reports its state and nothing to clean up")
    func resultMetroReused() throws {
        var context = UpContext()
        context.metro = MetroProcess(state: .reused)

        let json = try decode(UpReport(stages: [result("metro", .skipped)], context: context))
        let metro = try #require((json["result"] as? [String: Any])?["metro"] as? [String: Any])

        #expect(metro["state"] as? String == "reused")
        #expect(metro["pid"] == nil)
        #expect(metro["logPath"] == nil)
    }

    /// The four fields together are the point of `result`: with the device, the
    /// bundle id, the bundler and the app's pid in one document, whatever runs after
    /// `up` never has to ask the machine what this run did.
    @Test("a finished run describes the device, the app, the bundler and the app's pid")
    func resultIsComplete() throws {
        var context = UpContext()
        context.device = SelectedDevice(
            name: "iPhone 17 Pro", udid: "61DECACB-3D94-4748-B5A2-E7A1EB97E6D5", runtime: "26.5"
        )
        context.product = BuiltProduct(path: "/derived/MyApp.app", bundleIdentifier: "com.example.MyApp")
        context.metro = MetroProcess(state: .spawned, pid: 4242, logPath: "/tmp/mobile/MyApp/metro.log")
        context.appPid = 3538

        let json = try decode(UpReport(stages: [result("launch", .pass)], context: context))
        let outcome = try #require(json["result"] as? [String: Any])
        let device = try #require(outcome["device"] as? [String: Any])

        #expect(device["udid"] as? String == "61DECACB-3D94-4748-B5A2-E7A1EB97E6D5")
        #expect(outcome["bundleId"] as? String == "com.example.MyApp")
        #expect((outcome["metro"] as? [String: Any])?["pid"] as? Int == 4242)
        #expect(outcome["appPid"] as? Int == 3538)
    }

    /// No stage produced anything worth naming, so the key is absent rather than an
    /// empty object a consumer has to interpret.
    @Test("result is absent when no stage produced one")
    func noResult() throws {
        #expect(try decode(UpReport(stages: [result("validate", .pass)]))["result"] == nil)
    }

    /// exit 2 promises no JSON, but when there is one it still says what broke.
    @Test("a tool failure has a message and no remediation")
    func toolFailure() throws {
        let report = UpReport(stages: [], failure: .tool("validate: could not run"))
        let error = try #require(try decode(report)["error"] as? [String: Any])

        #expect(error["message"] as? String == "validate: could not run")
        #expect(error["remediation"] == nil)
    }

    private func decode(_ report: UpReport) throws -> [String: Any] {
        let text = try UpJSONDocument(report: report, toolVersion: "9.9.9").encoded()
        return try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }
}

@Suite("up progress lines")
struct StageLineRendererTests {
    private let renderer = StageLineRenderer()

    @Test("name, outcome and elapsed time, one line per stage")
    func line() {
        #expect(renderer.line(result("validate", .pass)) == "validate      pass                    1.2s")
        #expect(
            renderer.line(result("dependencies", .skipped, .milliseconds(40), detail: "node_modules present"))
                == "dependencies  skipped — node_modules present  0.0s"
        )
    }

    /// On a pass the detail is what the reader wanted — which device, which scheme —
    /// so it takes the column outright. A failure keeps its status word: there, the
    /// status is the news.
    @Test("a passing stage shows its detail in place of the status")
    func detailLine() {
        #expect(
            renderer.line(result("device", .pass, .milliseconds(8400), detail: "iPhone 17 Pro (iOS 26.1)"))
                == "device        iPhone 17 Pro (iOS 26.1)  8.4s"
        )
        #expect(
            renderer.line(result("validate", .failed, .seconds(3), detail: "2 checks failed"))
                == "validate      failed — 2 checks failed  3.0s"
        )
    }

    /// A build takes minutes and says nothing while it does. The same columns as a
    /// finished stage, so the wait reads as the row it will eventually become rather
    /// than as a different kind of message.
    @Test("a stage that has not landed yet prints its elapsed time in the same columns")
    func waitingLine() {
        #expect(renderer.waiting("build", elapsed: .seconds(45)) == "build         running…                45.0s")
    }
}

@Suite("up streams")
struct UpWriterTests {
    private let out = Mutable<[String]>([])
    private let error = Mutable<[String]>([])

    private func writer(json: Bool) -> UpWriter {
        let out = out
        let error = error
        return UpWriter(
            json: json,
            toolVersion: "9.9.9",
            renderer: HumanReportRenderer(useColor: false),
            standardOutput: { out.value.append($0) },
            standardError: { error.value.append($0) }
        )
    }

    /// The rule a parser depends on: one document, nothing else. Progress printed
    /// while the pipeline runs is what would break it, so it is printed here too.
    @Test("--json writes one parseable document to stdout and progress to stderr")
    func stdoutIsOnlyJSON() throws {
        let writer = writer(json: true)
        let report = UpReport(
            stages: [result("validate", .pass)],
            context: validation(.warning(remediation: Remediation(summary: "switch node")))
        )

        writer.progress(report.stages[0])
        try writer.finish(report)

        #expect(out.value.count == 1)
        let document = try JSONSerialization.jsonObject(with: Data(out.value[0].utf8)) as? [String: Any]
        #expect(document?["command"] as? String == "up")
        #expect(error.value.contains { $0.contains("validate") })
        // The warning is in the document; --json does not also render it for a human.
        #expect(error.value.contains { $0.contains("switch node") } == false)
    }

    /// A stage that is still working writes through the same door as everything else
    /// a human reads. `--json` is exactly when this matters: the document has not
    /// been written yet, and one stray line would make stdout unparseable.
    @Test("a note from a running stage goes to stderr in either mode")
    func notesStayOnStderr() {
        writer(json: true).note("build         running…                45.0s")

        #expect(out.value.isEmpty)
        #expect(error.value == ["build         running…                45.0s"])
    }

    @Test("without --json nothing goes to stdout at all")
    func humanOutputStaysOnStderr() throws {
        let writer = writer(json: false)
        let report = UpReport(
            stages: [result("validate", .pass)],
            context: validation(.warning(remediation: Remediation(summary: "switch node")))
        )

        writer.progress(report.stages[0])
        try writer.finish(report)

        #expect(out.value.isEmpty)
        #expect(error.value.joined(separator: "\n").contains("→ switch node"))
    }

    @Test("a validate error is rendered once, by doctor's renderer")
    func domainFailureRendersTheReport() throws {
        let remediation = Remediation(summary: "Switch to Node 24.")
        let report = UpReport(
            stages: [result("validate", .failed)],
            context: validation(.error(observed: "Node 18", remediation: remediation)),
            failure: .domain(DomainError(summary: "Node 18", remediation: remediation))
        )

        try writer(json: false).finish(report)

        let text = error.value.joined(separator: "\n")
        #expect(text.contains("[✗] Node — Node 18"))
        // Once: the failure is the check, not a second entry underneath it.
        #expect(text.components(separatedBy: "Switch to Node 24.").count == 2)
    }

    /// exit 2 next to check errors that exit 1: printing only the errors would hide
    /// why the exit code disagrees with them.
    @Test("a tool failure is still printed when validate also found errors")
    func toolFailureIsNeverSwallowed() throws {
        let report = UpReport(
            stages: [result("validate", .failed)],
            context: validation(.error(observed: "Node 18", remediation: Remediation(summary: "Switch to Node 24."))),
            failure: .tool("validate: `xcrun simctl list` timed out")
        )

        try writer(json: false).finish(report)

        let text = error.value.joined(separator: "\n")
        #expect(text.contains("[✗] Node — Node 18"))
        #expect(text.contains("timed out"))
    }
}

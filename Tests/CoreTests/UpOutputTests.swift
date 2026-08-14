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

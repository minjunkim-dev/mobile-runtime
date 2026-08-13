import Foundation
import Testing

@testable import Core

private func result(
    _ id: String,
    category: String,
    _ outcome: CheckOutcome,
    title: String = "a check"
) -> CheckResult {
    CheckResult(id: id, category: category, title: title, outcome: outcome)
}

@Suite("--json document")
struct DoctorJSONTests {
    @Test("envelope carries schema version, tool version, command and status")
    func envelope() throws {
        let report = DoctorReport(checks: [
            result("xcode.installed", category: "Xcode", .pass(observed: "Xcode 26.6 (17F113)"))
        ])

        let json = try decode(report)

        #expect(json["schemaVersion"] as? Int == 1)
        #expect(json["toolVersion"] as? String == "9.9.9")
        #expect(json["command"] as? String == "doctor")
        #expect(json["status"] as? String == "pass")
    }

    @Test("a warning check carries remediation and no reason")
    func warningCheck() throws {
        let report = DoctorReport(checks: [
            result(
                "xcode.version",
                category: "Xcode",
                .warning(
                    observed: "26.6",
                    required: "16.x",
                    source: CheckSource(tier: 2, origin: "matrix"),
                    remediation: Remediation(summary: "downgrade", command: "xcodes install 16.4", url: "https://example.test")
                )
            )
        ])

        let check = try #require((try decode(report)["checks"] as? [[String: Any]])?.first)

        #expect(check["id"] as? String == "xcode.version")
        #expect(check["status"] as? String == "warning")
        #expect(check["observed"] as? String == "26.6")
        #expect(check["required"] as? String == "16.x")
        #expect((check["source"] as? [String: Any])?["tier"] as? Int == 2)
        #expect((check["source"] as? [String: Any])?["origin"] as? String == "matrix")
        #expect((check["remediation"] as? [String: Any])?["command"] as? String == "xcodes install 16.4")
        #expect(check["reason"] == nil)
    }

    @Test("an unknown check carries reason instead of remediation")
    func unknownCheck() throws {
        let report = DoctorReport(checks: [
            result("simulator.daemon", category: "iOS Simulator", .unknown(reason: "Xcode not located"))
        ])

        let check = try #require((try decode(report)["checks"] as? [[String: Any]])?.first)

        #expect(check["reason"] as? String == "Xcode not located")
        #expect(check["remediation"] == nil)
    }

    @Test("host checks omit the source tier")
    func hostSourceHasNoTier() throws {
        let report = DoctorReport(checks: [
            result("simulator.daemon", category: "iOS Simulator", .pass())
        ])

        let check = try #require((try decode(report)["checks"] as? [[String: Any]])?.first)
        let source = try #require(check["source"] as? [String: Any])

        #expect(source["origin"] as? String == "host")
        #expect(source["tier"] == nil)
    }

    private func decode(_ report: DoctorReport) throws -> [String: Any] {
        let text = try DoctorJSONDocument(report: report, toolVersion: "9.9.9").encoded()
        return try #require(
            try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        )
    }
}

@Suite("human output")
struct HumanReportRendererTests {
    private let renderer = HumanReportRenderer(useColor: false)

    @Test("one line per category, remediation indented underneath")
    func categoryGrouping() {
        let report = DoctorReport(checks: [
            result("xcode.installed", category: "Xcode", .pass(observed: "Xcode 26.6 (17F113)")),
            result(
                "simulator.daemon",
                category: "iOS Simulator",
                .error(
                    observed: "simctl did not respond",
                    remediation: Remediation(summary: "Restart CoreSimulator.", command: "killall -9 x")
                )
            ),
        ])

        let lines = renderer.render(report).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        #expect(lines[0] == "[✓] Xcode — Xcode 26.6 (17F113)")
        #expect(lines[1] == "[✗] iOS Simulator — simctl did not respond")
        #expect(lines[2] == "    → Restart CoreSimulator.")
        #expect(lines[3] == "      killall -9 x")
    }

    @Test("verbose adds observed, required and source; plain output does not")
    func verboseDetail() {
        let report = DoctorReport(checks: [
            result(
                "xcode.version",
                category: "Xcode",
                .pass(observed: "26.6", required: "16.x", source: CheckSource(tier: 2, origin: "matrix"))
            )
        ])

        #expect(renderer.render(report).contains("source:") == false)

        let verbose = HumanReportRenderer(useColor: false, verbose: true).render(report)
        #expect(verbose.contains("· xcode.version [pass]"))
        #expect(verbose.contains("observed: 26.6"))
        #expect(verbose.contains("required: 16.x"))
        #expect(verbose.contains("source:   matrix (tier 2)"))
    }

    @Test("unknown shows its reason")
    func unknownReason() {
        let report = DoctorReport(checks: [
            result("simulator.daemon", category: "iOS Simulator", .unknown(reason: "Xcode not located"))
        ])

        #expect(renderer.render(report).contains("? Xcode not located"))
    }

    @Test("colour is opt-in")
    func colour() {
        let report = DoctorReport(checks: [result("a", category: "Xcode", .pass())])

        #expect(renderer.render(report).contains("\u{1B}[") == false)
        #expect(HumanReportRenderer(useColor: true).render(report).contains("\u{1B}[32m"))
    }
}

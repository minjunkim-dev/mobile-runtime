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
        #expect(json["platform"] == nil)
    }

    @Test("Android adds a platform discriminator without changing schema v1")
    func androidPlatform() throws {
        let document = DoctorJSONDocument(
            report: DoctorReport(checks: []),
            toolVersion: "9.9.9",
            platform: "android"
        )
        let json = try #require(
            try JSONSerialization.jsonObject(with: Data(document.encoded().utf8)) as? [String: Any]
        )

        #expect(json["schemaVersion"] as? Int == 1)
        #expect(json["platform"] as? String == "android")
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

    /// An observed value with nothing to compare it against cannot be read: "Node
    /// 24.19.0" does not say why it is a problem, and the remediation underneath says
    /// how to change it without saying to what. Only warning and error need the
    /// target — a `pass` has nothing to move towards.
    @Test("warning and error name the target on the same line")
    func headlineNamesTheTarget() {
        let report = DoctorReport(checks: [
            result(
                "node.version",
                category: "Node",
                .warning(
                    observed: "Node 24.19.0",
                    required: "24.15.0 (.nvmrc)",
                    remediation: Remediation(summary: "Switch to the pinned Node version.")
                )
            ),
            result("xcode.version", category: "Xcode", .pass(observed: "Xcode 26.6", required: "16.1")),
        ])

        let lines = renderer.render(report).split(separator: "\n").map(String.init)

        #expect(lines[0] == "[!] Node — Node 24.19.0 → 24.15.0 (.nvmrc)")
        // source and tier stay behind -v; the headline gains one comparison, not a
        // second line.
        #expect(lines[0].contains(".nvmrc)") == true)
        #expect(lines.contains("[✓] Xcode — Xcode 26.6"))
    }

    /// Folding a category to its worst check answers nothing when every check passes,
    /// and order decided it: `[✓] Xcode` showed "Xcode is installed" while the verdict
    /// that took a lockfile and a `.xcode-version` to reach stayed behind `-v` (#34).
    @Test("an all-pass category leads with its most project-specific check")
    func headlinePrefersTheProjectVerdict() {
        let report = DoctorReport(checks: [
            result("xcode.installed", category: "Xcode", .pass(observed: "Xcode 26.6 at /Applications")),
            result(
                "xcode.version",
                category: "Xcode",
                .pass(
                    observed: "Xcode 26.6 (17F113)", required: "Xcode 26.3 or newer",
                    source: CheckSource(tier: 1, origin: ".xcode-version")
                )
            ),
        ])

        #expect(renderer.render(report).split(separator: "\n").first == "[✓] Xcode — Xcode 26.6 (17F113)")
    }

    /// The fold itself is unchanged: a status that stands out still wins, whichever
    /// tier it came from.
    @Test("a failing host check still leads over a passing project one")
    func headlineStillPrefersTheWorstStatus() {
        let report = DoctorReport(checks: [
            result(
                "simulator.daemon",
                category: "iOS Simulator",
                .error(observed: "simctl did not respond", remediation: Remediation(summary: "Restart it."))
            ),
            result(
                "simulator.runtime",
                category: "iOS Simulator",
                .pass(observed: "iOS 26.5 installed", source: CheckSource(tier: 1, origin: "ios/Podfile"))
            ),
        ])

        #expect(
            renderer.render(report).split(separator: "\n").first
                == "[✗] iOS Simulator — simctl did not respond"
        )
    }

    /// A Check can be a warning with nothing to compare against — the fact is the
    /// whole verdict. The arrow appears only when there is something after it.
    @Test("a warning with no required value keeps its plain headline")
    func headlineWithoutRequired() {
        let report = DoctorReport(checks: [
            result(
                "project.detected",
                category: "Project",
                .warning(
                    observed: "React Native 0.83.9, node_modules missing",
                    remediation: Remediation(summary: "Install the dependencies.")
                )
            )
        ])

        #expect(
            renderer.render(report).split(separator: "\n").first
                == "[!] Project — React Native 0.83.9, node_modules missing"
        )
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
        // -v is meant to say more, and once said less: the reason was the only
        // thing an unknown had, and detail dropped it.
        #expect(
            HumanReportRenderer(useColor: false, verbose: true).render(report)
                .contains("reason:   Xcode not located")
        )
    }

    @Test("colour is opt-in")
    func colour() {
        let report = DoctorReport(checks: [result("a", category: "Xcode", .pass())])

        #expect(renderer.render(report).contains("\u{1B}[") == false)
        #expect(HumanReportRenderer(useColor: true).render(report).contains("\u{1B}[32m"))
    }
}

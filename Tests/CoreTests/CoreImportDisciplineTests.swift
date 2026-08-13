import Foundation
import Testing

/// Core must stay Foundation-only — no Apple frameworks, no iOS domain knowledge.
/// SwiftPM cannot express "this target may not import AppKit", so the boundary is
/// enforced here instead: adding a forbidden import fails the suite.
@Suite("Core import discipline")
struct CoreImportDisciplineTests {
    private static let allowed: Set<String> = ["Foundation", "Subprocess", "System", "Logging"]

    @Test("Core imports nothing outside Foundation and its package dependencies")
    func onlyAllowedImports() throws {
        let core = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // CoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
            .appendingPathComponent("Sources/Core")

        let files = try #require(
            FileManager.default.enumerator(at: core, includingPropertiesForKeys: nil)
        )
        var scanned = 0

        for case let file as URL in files where file.pathExtension == "swift" {
            scanned += 1
            let source = try String(contentsOf: file, encoding: .utf8)
            for line in source.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("import ") else { continue }
                let module = String(trimmed.dropFirst("import ".count))
                    .split(separator: ".").first.map(String.init) ?? ""
                #expect(
                    Self.allowed.contains(module),
                    "\(file.lastPathComponent) imports \(module); Core is Foundation-only"
                )
            }
        }

        #expect(scanned > 0, "found no Core sources to scan — the path is wrong")
    }
}

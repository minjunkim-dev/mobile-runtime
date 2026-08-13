import Foundation

enum Fixture {
    /// Real captured tool output — see Fixtures/README.md for provenance.
    static func text(_ name: String) throws -> String {
        let url = Bundle.module.resourceURL!.appendingPathComponent("Fixtures/\(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }
}

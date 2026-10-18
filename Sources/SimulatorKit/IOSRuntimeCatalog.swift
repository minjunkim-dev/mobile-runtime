import Core
import CryptoKit
import Foundation

/// Apple's public catalog pins a MobileAsset identity, not the bytes of its payload.
public struct IOSRuntimeCatalog: Sendable {
    public static let url = URL(string: "https://devimages-cdn.apple.com/downloads/xcode/simulators/index2.dvtdownloadableindex")!
    public static var command: ProcessCommand {
        ProcessCommand("curl", ["--fail", "--silent", "--show-error", "--location", "--proto", "=https",
            "--proto-redir", "=https", "--max-redirs", "3", "--connect-timeout", "15", "--max-time", "60",
            "--max-filesize", "4000000", url.absoluteString], timeout: .seconds(65))
    }

    public let sha256: String
    private let entries: [Entry]

    private struct Entry: Sendable {
        let identifier: String
        let version: String
        let build: String
        let architectures: [String]
        let size: Int64
    }

    public init(data: Data) throws {
        guard data.count <= 4_000_000,
              let root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entries = root["downloadables"] as? [[String: Any]] else {
            throw Self.failure("Apple's runtime catalog is unavailable or not a supported catalog")
        }
        sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        self.entries = entries.compactMap { item in
            guard item["platform"] as? String == "com.apple.platform.iphoneos",
                  item["downloadMethod"] as? String == "mobileAsset",
                  item["contentType"] as? String == "cryptexDiskImage",
                  item["dictionaryVersion"] as? Int == 2,
                  item["isInternalContent"] as? Bool != true,
                  let name = item["name"] as? String,
                  !["beta", "candidate", "preview", "internal"].contains(where: name.lowercased().contains),
                  let identifier = item["identifier"] as? String, !identifier.isEmpty,
                  let simulator = item["simulatorVersion"] as? [String: String],
                  let version = simulator["version"], SemanticVersion(version) != nil,
                  let build = simulator["buildUpdate"],
                  build.range(of: #"^[0-9]+[A-Z][0-9]+$"#, options: .regularExpression) != nil,
                  let architectures = item["architectures"] as? [String],
                  let size = item["fileSize"] as? Int64, size > 0 else { return nil }
            return Entry(identifier: identifier, version: version, build: build, architectures: architectures, size: size)
        }
    }

    public static func load(runner: any ProcessRunner) async throws -> Self {
        let result = try await runner.run(command)
        guard result.terminationStatus.isSuccess else {
            throw failure("The official runtime catalog could not be read. Check official download access and re-plan; no payload was downloaded.")
        }
        return try Self(data: Data(result.standardOutput.utf8))
    }

    /// New installs use the fixed validated OS candidate, never the newest catalog entry.
    public func pin(version: String, architecture: String, xcode: XcodeInstallation,
                    existingDeviceIDs: [String], deviceSet: URL) throws -> IOSRuntimePin {
        let matches = entries.filter { $0.version == version && $0.architectures.contains(architecture) }
        guard matches.count == 1, let entry = matches.first else {
            throw Self.failure("No single official final runtime identifies iOS \(version) \(architecture). Do not substitute latest, a beta, or another build.")
        }
        let runtimeID = "com.apple.CoreSimulator.SimRuntime.iOS-" + entry.version.replacingOccurrences(of: ".", with: "-")
        return IOSRuntimePin(identifier: runtimeID, version: entry.version, build: entry.build, architecture: architecture,
            assetIdentifier: entry.identifier, downloadSize: entry.size, catalogURL: Self.url, catalogSHA256: sha256,
            developerDirectory: xcode.developerDirectory, xcodeVersion: xcode.version, xcodeBuild: xcode.build,
            existingDeviceIDs: existingDeviceIDs, deviceSet: deviceSet)
    }

    private static func failure(_ message: String) -> DomainError {
        DomainError(summary: message, remediation: Remediation(summary: "Review the exact runtime in the selected Xcode's Components settings, then inspect again. Xcode installation, account access and license approval remain manual.",
            url: "https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components"))
    }
}

import Core
import CryptoKit
import Foundation

/// Official metadata is read during planning. The selected payload is downloaded
/// only by an approved InstallationAction. Volatile download counts and dates do
/// not change the approval identity.
enum ToolReleaseCatalog {
    struct Release: Sendable {
        let version: String
        let artifact: InstallationArtifact
        let repository: URL
        let identity: String
        let payloadRoot: String
        let executable: String
    }

    static func release(_ request: ToolPreparationRequirement, runner: any ProcessRunner) async throws -> Release {
        guard let version = request.exactVersion else { throw InstallationExecution.failure("An exact tool version is required") }
        switch request.tool {
        case .node:
            let filename = "node-v\(version)-darwin-arm64.tar.gz"
            let repository = URL(string: "https://nodejs.org/dist/v\(version)/SHASUMS256.txt")!
            let bytes = try await metadata(repository, runner: runner)
            let matches = String(decoding: bytes, as: UTF8.self).split(whereSeparator: \.isNewline).compactMap { line -> String? in
                let fields = line.split(whereSeparator: \.isWhitespace)
                guard fields.count == 2, fields[1] == filename else { return nil }
                return String(fields[0])
            }
            guard matches.count == 1, matches[0].range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil else {
                throw InstallationExecution.failure("Official Node metadata does not identify one exact arm64 archive")
            }
            let url = URL(string: "https://nodejs.org/dist/v\(version)/\(filename)")!
            let headers = try await metadata(url, head: true, runner: runner)
            let lengths = String(decoding: headers, as: UTF8.self).split(whereSeparator: \.isNewline).compactMap { line -> Int64? in
                let fields = line.split(separator: ":", maxSplits: 1)
                guard fields.count == 2, fields[0].lowercased() == "content-length" else { return nil }
                return Int64(fields[1].trimmingCharacters(in: .whitespacesAndNewlines))
            }
            guard Set(lengths).count == 1, let size = lengths.first, size > 0 else {
                throw InstallationExecution.failure("Official Node archive size is unknown")
            }
            return Release(version: version, artifact: InstallationArtifact(url: url, checksumAlgorithm: "sha256", checksum: matches[0], size: size),
                repository: repository, identity: sha(bytes), payloadRoot: "node-v\(version)-darwin-arm64", executable: "bin/node")
        case .ruby:
            return try await github(repository: "jdx/ruby", tag: version, filename: "ruby-\(version).macos.tar.gz",
                version: version, payloadRoot: "ruby-\(version)", executable: "bin/ruby", runner: runner)
        case .java:
            guard version.hasPrefix("temurin-"), let build = version.split(separator: "+").last,
                  version.contains("+") else { throw InstallationExecution.failure("Only an exact Temurin build is available from this provider; other vendors are never substituted") }
            let numeric = String(version.dropFirst("temurin-".count).split(separator: "+")[0])
            let major = numeric.split(separator: ".")[0]
            return try await github(repository: "adoptium/temurin\(major)-binaries", tag: "jdk-\(numeric)+\(build)",
                filename: "OpenJDK\(major)U-jdk_aarch64_mac_hotspot_\(numeric)_\(build).tar.gz", version: version,
                payloadRoot: "jdk-\(numeric)+\(build)/Contents/Home", executable: "bin/java", runner: runner)
        }
    }

    static func mise(runner: any ProcessRunner) async throws -> Release {
        try await github(repository: "jdx/mise", tag: "v2026.10.7", filename: "mise-v2026.10.7-macos-arm64",
            version: "2026.10.7", payloadRoot: "", executable: "bin/mise", runner: runner)
    }

    private struct GitHubRelease: Decodable {
        struct Asset: Codable {
            let id: Int64
            let name: String
            let size: Int64
            let digest: String?
            let browser_download_url: URL
        }
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }

    private static func github(repository: String, tag: String, filename: String, version: String,
                               payloadRoot: String, executable: String, runner: any ProcessRunner) async throws -> Release {
        let encoded = tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "+")))!
        let url = URL(string: "https://api.github.com/repos/\(repository)/releases/tags/\(encoded)")!
        let release = try JSONDecoder().decode(GitHubRelease.self, from: await metadata(url, runner: runner))
        let assets = release.assets.filter { $0.name == filename }
        guard release.tag_name == tag, !release.draft, !release.prerelease, assets.count == 1, let asset = assets.first,
              let digest = asset.digest, digest.range(of: #"^sha256:[0-9a-f]{64}$"#, options: .regularExpression) != nil,
              asset.size > 0, asset.browser_download_url.scheme == "https", asset.browser_download_url.host == "github.com",
              asset.browser_download_url.user == nil, asset.browser_download_url.password == nil,
              asset.browser_download_url.query == nil, asset.browser_download_url.fragment == nil,
              asset.browser_download_url.path.removingPercentEncoding == "/\(repository)/releases/download/\(tag)/\(filename)" else {
            throw InstallationExecution.failure("Official release metadata has an ambiguous or unpinned tool archive")
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return Release(version: version, artifact: InstallationArtifact(url: asset.browser_download_url, checksumAlgorithm: "sha256",
            checksum: String(digest.dropFirst(7)), size: asset.size), repository: url, identity: sha(try encoder.encode(asset)),
            payloadRoot: payloadRoot, executable: executable)
    }

    private static func metadata(_ url: URL, head: Bool = false, runner: any ProcessRunner) async throws -> Data {
        try Task.checkCancellation()
        let result = try await runner.run(ProcessCommand("curl", ["--fail", "--silent", "--show-error", "--proto", "=https",
            "--max-time", "30"] + (head ? ["--head"] : []) + [url.absoluteString], timeout: .seconds(35)))
        guard result.terminationStatus.isSuccess else { throw InstallationExecution.failure("Official tool metadata is unavailable; inspect again before approval") }
        return Data(result.standardOutput.utf8)
    }

    static func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

// SPIKE — throwaway. 각 단계 성공/실패와 소요시간을 그대로 출력한다.
import Foundation
import Subprocess

// MARK: - helpers

struct SpikeError: Error, CustomStringConvertible {
    let description: String
}

@discardableResult
func sh(_ exe: String, _ args: [String], timeout: Duration? = nil) async throws -> String {
    let start = ContinuousClock.now
    let task = Task {
        try await run(
            .name(exe),
            arguments: Arguments(args),
            output: .string(limit: 4 * 1024 * 1024),
            error: .string(limit: 1024 * 1024)
        )
    }
    var timeoutTask: Task<Void, any Error>?
    if let timeout {
        timeoutTask = Task {
            try await Task.sleep(for: timeout)
            task.cancel()
        }
    }
    do {
        let result = try await task.value
        timeoutTask?.cancel()
        let elapsed = start.duration(to: .now)
        let cmd = "\(exe) \(args.joined(separator: " "))"
        guard result.terminationStatus.isSuccess else {
            throw SpikeError(description: "FAIL(\(result.terminationStatus)) \(cmd)\nstderr: \(result.standardError ?? "")")
        }
        print("  ✓ [\(elapsed)] \(cmd)")
        return result.standardOutput ?? ""
    } catch is CancellationError {
        throw SpikeError(description: "TIMEOUT after \(String(describing: timeout)): \(exe) \(args.joined(separator: " "))")
    }
}

func step(_ name: String) { print("\n== \(name) ==") }

// MARK: - spike

let clock = ContinuousClock.now
var createdUDID: String?

do {
    step("1. Xcode 탐지")
    let devDir = try await sh("xcode-select", ["-p"]).trimmingCharacters(in: .whitespacesAndNewlines)
    let xcodeVer = try await sh("xcodebuild", ["-version"])
    print("  DEVELOPER_DIR=\(devDir)")
    print("  \(xcodeVer.split(separator: "\n").joined(separator: " / "))")

    step("2. runtime / devicetype 목록 (JSON 파싱, isAvailable 필터)")
    let listJSON = try await sh("xcrun", ["simctl", "list", "-j"])
    guard let root = try JSONSerialization.jsonObject(with: Data(listJSON.utf8)) as? [String: Any],
          let runtimes = root["runtimes"] as? [[String: Any]],
          let devicetypes = root["devicetypes"] as? [[String: Any]]
    else { throw SpikeError(description: "simctl list -j 파싱 실패") }

    let availableRuntimes = runtimes.filter { ($0["isAvailable"] as? Bool) == true && ($0["identifier"] as? String)?.contains("iOS") == true }
    guard let runtime = availableRuntimes.last,
          let runtimeID = runtime["identifier"] as? String
    else { throw SpikeError(description: "사용 가능한 iOS runtime 없음") }
    print("  runtime: \(runtimeID) (build \(runtime["buildversion"] ?? "?"))")

    guard let devType = devicetypes.first(where: { ($0["name"] as? String)?.hasPrefix("iPhone 17 Pro") == true }),
          let devTypeID = devType["identifier"] as? String
    else { throw SpikeError(description: "iPhone 17 Pro devicetype 없음") }
    print("  devicetype: \(devTypeID)")

    step("3. simctl create")
    let udid = try await sh("xcrun", ["simctl", "create", "SpikeIOS-\(ProcessInfo.processInfo.processIdentifier)", devTypeID, runtimeID])
        .trimmingCharacters(in: .whitespacesAndNewlines)
    createdUDID = udid
    print("  udid: \(udid)")

    step("4. boot + bootstatus -b (120s 타임아웃)")
    _ = try await sh("xcrun", ["simctl", "bootstatus", udid, "-b"], timeout: .seconds(120))

    step("5. dummy .app install")
    let appPath = FileManager.default.currentDirectoryPath + "/Dummy.app"
    guard FileManager.default.fileExists(atPath: appPath + "/Dummy") else {
        throw SpikeError(description: "Dummy.app 없음 — 먼저 ./make-dummy-app.sh 실행")
    }
    try await sh("xcrun", ["simctl", "install", udid, appPath])

    step("6. launch (PID 확인)")
    let launchOut = try await sh("xcrun", ["simctl", "launch", udid, "com.spike.dummy"])
    print("  → \(launchOut.trimmingCharacters(in: .whitespacesAndNewlines))")

    step("7. screenshot")
    // 함정: launch는 프로세스 spawn 시점 리턴, UI 렌더 완료 보장 없음 → 대기 필요
    try await Task.sleep(for: .seconds(3))
    let shot = "/tmp/spike-ios-\(udid).png"
    try await sh("xcrun", ["simctl", "io", udid, "screenshot", shot])
    let size = ((try? FileManager.default.attributesOfItem(atPath: shot))?[.size] as? Int) ?? 0
    print("  → \(shot) (\(size) bytes)")

    step("8. shutdown + delete")
    try await sh("xcrun", ["simctl", "shutdown", udid], timeout: .seconds(60))
    try await sh("xcrun", ["simctl", "delete", udid])
    createdUDID = nil

    print("\n✅ SPIKE 전체 성공 — 총 \(clock.duration(to: .now))")
} catch {
    print("\n❌ \(error)")
    if let udid = createdUDID {
        print("cleanup: \(udid) 삭제 시도")
        _ = try? await sh("xcrun", ["simctl", "shutdown", udid])
        _ = try? await sh("xcrun", ["simctl", "delete", udid])
    }
    exit(1)
}

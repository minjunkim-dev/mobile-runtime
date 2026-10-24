import Foundation

/// Presence checks support an explicit manual choice; they do not prove lock alignment.
struct PreparedDependenciesStage: Stage {
    let id = "dependencies"
    let anchor: ProjectAnchor
    let includePods: Bool

    func run(_ context: inout UpContext) async throws -> StageOutcome {
        try Task.checkCancellation()
        let files = FileManager.default
        if anchor.framework == .flutter {
            let root = try FlutterProject(directory: anchor.directory).workspaceDirectoryForTeardown()
            for name in ["pubspec.lock", ".dart_tool/package_config.json", ".dart_tool/package_graph.json"] {
                let file = root.appendingPathComponent(name)
                guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                      files.isReadableFile(atPath: file.path) else { throw missing("읽을 수 있는 Flutter 준비 파일: \(name)") }
            }
        } else {
            let root = anchor.installProcess.workingDirectory ?? anchor.directory
            let nodeModules = root.appendingPathComponent("node_modules")
            guard isDirectory(nodeModules) else { throw missing("설치 루트의 node_modules 디렉터리") }
            let marker = nodeModules.appendingPathComponent(".mobile-install.incomplete")
            guard !files.fileExists(atPath: marker.path),
                (try? files.destinationOfSymbolicLink(atPath: marker.path)) == nil else {
                throw missing("완료된 Node 설치: incomplete 표식이 남아 있습니다")
            }
        }
        let ios = anchor.iosDirectory
        if includePods && files.fileExists(atPath: ios.appendingPathComponent("Podfile").path) {
            guard isDirectory(ios.appendingPathComponent("Pods")), !DependenciesStage.podsAreStale(ios) else {
                throw missing("Podfile.lock과 Pods/Manifest.lock이 일치하는 Pods 디렉터리")
            }
            let workspaces = try files.contentsOfDirectory(at: ios, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "xcworkspace" }
            guard workspaces.count == 1, let workspace = workspaces.first, isDirectory(workspace) else {
                throw missing("읽을 수 있는 CocoaPods workspace 한 개")
            }
            let contents = workspace.appendingPathComponent("contents.xcworkspacedata")
            guard (try? contents.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                files.isReadableFile(atPath: contents.path) else {
                throw missing("읽을 수 있는 CocoaPods workspace 한 개")
            }
        }
        let resolver = anchor.framework == .flutter ? " Flutter plugin resolver 정합성 판정도 생략합니다." : ""
        return .skipped("직접 준비한 의존성 사용: 재설치·lock 정렬 재검증 생략. 의존성 정합성은 사용자가 확인해야 합니다." + resolver)
    }

    private func isDirectory(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }

    private func missing(_ item: String) -> DomainError {
        let next = anchor.framework == .flutter
            ? "정확한 Flutter SDK로 의존성과 generated 입력을 직접 준비한 뒤 다시 실행하세요."
            : "직접 준비를 마치거나 --prepared-dependencies를 빼고 lock 기반 설치를 실행하세요."
        return DomainError(summary: "수동 준비한 의존성을 사용할 수 없습니다: \(item).",
            remediation: Remediation(summary: next + " 의존성 설치기는 실행하지 않았습니다."))
    }
}

import Core

/// Presentation only. CLI/JSON values and tool diagnostics keep their original meaning.
public enum GUIText {
    public static func state(_ value: String) -> String {
        ["ready": "선택 항목 확인됨", "planned": "계획 확인됨", "inspecting": "확인 중", "running": "진행 중",
         "succeeded": "완료", "failed": "실패", "cancelled": "취소됨",
         "needs-selection": "선택 필요", "needs-approval": "승인 필요",
         "waiting-manual": "직접 준비가 필요합니다", "partially-completed": "일부 완료", "partial": "일부 완료",
         "pass": "확인됨", "error": "오류", "warning": "주의", "unknown": "확인 불가",
         "skipped": "생략됨", "stopped": "종료됨", "blocked": "진행할 수 없음",
         "not-requested": "요청하지 않음", "not-observed": "확인하지 못함",
         "unconfirmed": "확인되지 않음", "installed": "설치됨", "accepted": "요청 전달됨",
         "requested": "요청함", "absent": "없음", "present": "있음", "required": "필요",
         "not-required": "필요 없음", "unavailable": "사용할 수 없음",
         "started": "시작됨", "unobserved": "아직 확인하지 않음"][value] ?? value
    }

    public static func operation(_ kind: WorkflowKind) -> String {
        switch kind { case .build: "빌드"; case .up: "실행"; case .down: "종료" }
    }

    public static func appRunning(_ value: String) -> String {
        if value == "running" { return "실행 중" }
        if value.hasPrefix("running: ") { return "실행 중: " + value.dropFirst("running: ".count) }
        if value.hasPrefix("unknown: ") { return "확인 불가: " + value.dropFirst("unknown: ".count) }
        return state(value)
    }

    public static func field(_ value: String) -> String {
        ["--app": "앱", "--platform": "플랫폼", "--device": "실행 기기", "--scheme": "Scheme",
         "--configuration": "빌드 구성", "--module": "모듈", "--variant": "빌드 변형",
         "--entrypoint": "Flutter 실행 파일", "--port": "포트", "--trust-repository": "저장소 스크립트 실행 허용"][value] ?? value
    }
}

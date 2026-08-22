# Private iOS 내부 alpha round 1

이 기록은 issue #85의 저장소 게이트 증거다. 후보 SHA와 runbook만 먼저
고정하며, 실제 React Native iOS 프로젝트 실행과 내부 alpha 완료는 주장하지
않는다.

## Handoff

```text
Alpha round: 2026-08-22-1
mobile SHA: 0033d1cef951809cdd6de40604b53b8d47f43a42
Runbook: docs/internal-alpha-runbook.md @ 0033d1cef951809cdd6de40604b53b8d47f43a42
필수 참여자: maintainer 1명, 초대된 RN iOS 개발자 1명
```

후보는 2026-08-22 KST의 최신 `main`에서 고정했다. 이 기록을 추가하는 commit은
후보에 포함되지 않으며, 참여자는 branch나 이 기록의 commit이 아니라 위 40자
SHA를 사용한다.

## 저장소 게이트

검증 전후 `HEAD`는 위 SHA와 일치했고 tracked worktree는 clean이었다.

| Gate | Result | Sanitized summary |
| --- | --- | --- |
| macOS 전체 `swift test` | PASS (exit 0) | 411 tests / 52 suites / 0 failures |
| `scripts/verify-core-linux.sh` | PASS (exit 0) | `Core` target build complete |

### 재현 환경

- Host: macOS 26.6.2 (25G83), arm64
- Xcode: 26.6 (17F113)
- Host Swift: Apple Swift 6.3.3, target `arm64-apple-macosx26.0`
- Docker client/server: 29.4.0, context `orbstack`, server `linux/arm64`
- Linux image: `swift:6.3-noble`
- Linux image digest: `swift@sha256:56ef1be2c1ca36f4c52440357dc1fcdfdb5e113587134fcadeef57c225c71b54`
- Linux Swift: 6.3.3, target `aarch64-unknown-linux-gnu`
- Generated artifacts: ignored `.build/` and `.build-linux/`; unexpected tracked
  mutation 없음

## 판정과 경계

- 저장소 게이트 Alpha blocker: 없음
- 두 게이트 중 하나라도 실패하거나 판정 불가였다면 실제 프로젝트 실행의 성공
  근거로 승격하지 않고 Alpha blocker로 남긴다.
- 이 결과는 위 SHA의 Swift package 테스트와 Linux `Core` compile만 증명한다.
  `doctor --json`, `build --json`, `up --json`, 초기 UI, 실제 프로젝트 tracked
  파일 안전성은 아직 검증하지 않았다.
- Maintainer 실행은 #86, 초대 개발자 독립 실행은 #87에서 같은 SHA로 기록한다.
- 내부 alpha 완료 판정과 ADR-0008의 3-repository Go/No-Go는 이 기록의 범위가
  아니다.

원본 로그, JSON 전체, screenshot, secret, environment file, application data는
이 기록에 포함하지 않았다.

# GitHub 저장소 설정

대상은 `minjunkim-dev/mobile-runtime` / repository ID `1332714423` / public / `main`이다.
GitHub 품질 운영은 1인 개발 기준이다. 로컬 절차는 [리뷰 문서](agents/review.md)를 따른다.

## 기준선과 서버 검증

[repository-settings.json](../.github/repository-settings.json)은 기대값이다. GitHub가 자동 적용하는 파일이 아니다.
관리 설정 조회 권한이 있는 로컬 `gh` 인증으로 다음을 실행한다.

```sh
python3 scripts/check_github_settings.py
```

도구는 GET만 수행한다. repository ID·owner/name·자료형·필수 항목·체크 이름과 App ID·main CodeQL workflow blob을 확인한다.
exit 0은 일치, 1은 drift, 2는 조회 실패·자료 오류·미확인이다. 불완전한 기준선은 API 조회 전에 중단한다.
main에 workflow가 없으면 감사는 통과하지 않는다. PR 파일과 main 반영을 구분한다.
기본 Actions token에 관리 권한을 추가하지 않는다. 오류·누락·drift 경로는 기존 source-only 검사에서 검증한다.

## 공통 정책

| 항목 | 기준 |
| --- | --- |
| 병합 | Squash만, PR title/body, 작업 브랜치 자동 삭제·업데이트 제안 On |
| Allow auto-merge | On. 일괄 예약 없음. 검증 후 exact-head 직접 병합 |
| main 보호 | PR 필수·strict·관리자 적용·선형 이력·대화 해결 On |
| 승인 | GitHub 0명. one-way/broad 최종 head는 사람 승인 |
| 필수 체크 | 기존 `CI`, GitHub Actions App `15368` |
| force push·main 삭제 | Off |
| Actions | GitHub 공식만, 전체 SHA 필수, 기본 token read, PR 생성·승인 Off |
| fork | 모든 외부 기여자 승인. Secret과 쓰기 token 분리 |
| 보안 | Dependency graph·Dependabot alerts/security updates·Secret scanning·Push protection On |
| version update | GitHub Actions 주간. Swift 패키지의 기존 lock과 제품 CI 유지 |
| Release | 미래 공개 Release immutability On. 기존 공개 파일 소급 변경 없음 |

## CodeQL

[advanced workflow](../.github/workflows/codeql.yml)는 Actions·Python·Ruby·Swift를 분석한다.
default setup은 `not-configured`로 둔다. 기존 `CI`는 바꾸지 않는다. CodeQL은 검증 전 필수 체크에 추가하지 않는다.
같은 저장소 PR·main push·주간·수동 이벤트를 사용한다. fork PR 분석 job은 제외한다.
PR의 Swift 분석은 `Sources/`·`Tests/`·`Package*.swift`·`Package.resolved`·CodeQL workflow가 바뀐 경우만 실행한다.
Swift 분석은 공유 macOS runner를 약 25분 점유한다. PR diff를 읽지 못하면 Swift도 분석한다. main push·주간·수동 실행은 항상 Swift를 분석한다.
Swift를 건너뛴 PR의 code scanning은 main의 Swift 구성을 찾지 못했다는 안내를 보일 수 있다. 이 안내는 정상이다. Swift 경고는 main 분석에서 확인한다.
기본 권한은 `contents: read`다. 분석 job만 `security-events: write`를 사용한다. credential persistence는 Off다.

Swift는 기존 제품 CI와 같은 `macos-26` runner의 기본 toolchain을 사용한다. 잠근 의존성을 init 전에 준비하고 init 후 실제 Swift 빌드를 추적한다.
관측한 기존 runner image는 `20260907.0351.1`이며 [공식 목록](https://github.com/actions/runner-images/blob/macos-26-arm64/20260907.0351/images/macos/macos-26-arm64-Readme.md)의 기본 Xcode는 26.6이다.
[CodeQL 2.27.2 공지](https://github.blog/changelog/2026-10-09-codeql-2-27-2-improves-c-go-rust-and-javascript-analysis/#macos-27-compatibility)는 macOS 27 또는 Xcode 27에서 컴파일 추적을 지원하지 않는다고 명시한다.
실행 중 macOS/Xcode major를 확인한다. 미지원 조합이면 실패한다. 제품 SDK를 낮추거나 검사를 skip해서 성공으로 표시하지 않는다. 지원 공백이 생기면 Issue로 추적한다.

성공은 분석과 결과 게시를 뜻한다. 취약점 0건을 뜻하지 않는다. PR 변경분과 main 전체 분석의 경고를 구분한다.
경고는 현재 소스에서 검토한다. 확실한 결함은 직접 수정한다. 오탐은 근거를 기록한다. 경고를 자동 dismissal하지 않는다.

## Bugbot과 배포 경계

Bugbot은 Manual Only·Default·Draft Off·As Comment·위험 점수 On·Incremental Off·Autofix Off다. Cursor On-demand는 Disabled로 유지한다.
저장소 YAML은 Manual Only와 결제 설정을 증명하지 않는다. 대시보드와 personal override를 확인한 경우만 실제 값 확인으로 기록한다.
이번 Cursor 조회는 브라우저 `Page.enable` timeout으로 실패했다. 설정과 결제를 변경하지 않았다. 현재 대시보드 값은 미확인이다.
Copilot MCP tools·PR 승인과 추가 자동 AI 리뷰를 켜지 않는다. ChatGPT/Codex Cloud 계정은 탐색하지 않는다.

기존 [Draft workflow](../.github/workflows/draft-release.yml)는 수동 입력·source SHA·main CI·checksum·미공개 상태를 검증한다. 이번 설정 작업은 workflow를 변경하거나 실행하지 않는다.
공개·production 배포 job이 없으므로 사용하지 않는 release Environment를 만들지 않는다.
설정 적용·PR 검증·main 반영·Draft 실행·공개 배포를 각각 보고한다. 새 쓰기 권한은 사람이 최종 head를 승인한다.

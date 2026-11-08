# GitHub 저장소 설정

대상은 `minjunkim-dev/mobile-runtime` / repository ID `1332714423` / public / `main`이다.
GitHub 품질 운영은 1인 개발 기준이다. 로컬 절차는 [리뷰 문서](agents/review.md)를 따른다.

## 기준선과 서버 검증

[repository-settings.json](../.github/repository-settings.json)은 기대값이다. GitHub가 자동 적용하는 파일이 아니다.
감사와 적용은 소유자가 자기 기기에서 [repo-baseline](https://github.com/minjunkim-dev/repo-baseline)의 `tools/apply_github_settings.py`로 한다. 에이전트는 실행하지 않는다.

```sh
python3 <repo-baseline>/tools/apply_github_settings.py <이 저장소 경로>          # 계획만(GET)
python3 <repo-baseline>/tools/apply_github_settings.py <이 저장소 경로> --apply  # 계획을 승인한 뒤
```

계획 모드는 다른 값을 `DIFF`·`PLAN`으로 보여 주고, 차이나 `MANUAL`이 없으면 0, 있으면 1로 끝난다. `--apply`는 쓴 뒤 다시 감사해 `PASS`·`LIMITED`(0) 또는 `DRIFT after apply`(1)를 낸다. `MANUAL`이 남아도 1이다. 조회·쓰기 실패는 `FAILED`(2)다. 도구가 쓰지 않는 항목(공개 여부, ruleset, CodeQL workflow와 main의 `codeql.yml` blob, 기준선이 관리하지 않는 보호 설정)은 `MANUAL`로 보고한다.
Dependabot이 `.github/workflows/codeql.yml`만 바꾸면 `codeql_main_source.sha`가 `MANUAL` drift로 보인다. 기준선 SHA를 main의 `git hash-object .github/workflows/codeql.yml` 값으로 갱신한다. PR CI는 이 drift를 검사하지 않는다.
기본 Actions token에 관리 권한을 추가하지 않는다.

## 공통 정책

| 항목 | 기준 |
| --- | --- |
| 병합 | Squash만, PR title/body, 작업 브랜치 자동 삭제·업데이트 제안 On |
| Allow auto-merge | Off. 병합은 사람이 최종 head를 읽고 한다 |
| main 보호 | PR 필수·strict·관리자 적용·선형 이력·대화 해결 On |
| 승인 | GitHub 0명. 병합은 사람만 한다. 되돌리기 어려움은 사람이 diff를 읽은 head에서 병합 |
| 필수 체크 | `CI`(GitHub Actions App `15368`). `strict`는 true |
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

## 자체 리뷰와 배포 경계

2026-10-26부터 Bugbot 전용 파일·검사·실행 요구를 제거하고 자체 리뷰를 사용한다. 고유 기준은 코딩 규칙·리뷰 자료 선택 표에 보존한다. 서버 서비스·계정 연결은 변경하지 않는다.
Copilot MCP tools·PR 승인과 추가 자동 AI 리뷰를 켜지 않는다. ChatGPT/Codex Cloud 계정은 탐색하지 않는다.

기존 [Draft workflow](../.github/workflows/draft-release.yml)는 수동 입력·source SHA·main CI·checksum·미공개 상태를 검증한다. 그 workflow는 이 기준선 갱신에서 바꾸거나 실행하지 않는다.
공개·production 배포 job이 없으므로 사용하지 않는 release Environment를 만들지 않는다.
설정 적용·PR 검증·main 반영·Draft 실행·공개 배포를 각각 보고한다. 새 쓰기 권한은 사람이 최종 head를 승인한다.

## 공통 기준 갱신과 설정 관측 기록

2026-11-08에 repo-baseline main `513ac5d`의 코어 + GitHub 프로필로 옮겼다([repo-baseline#71](https://github.com/minjunkim-dev/repo-baseline/issues/71)). 해시 복사 manifest(`.github/repo-baseline.json`)와 복사한 검사기, `Review status`·`PR policy` workflow, `.github/workflow-policy.json`, vendored `matt-code-review`를 지웠다. 리뷰 기준은 루트 `REVIEW.md`, 에이전트 권한은 `.claude/settings.json`이다. 그 전 적용 원본은 `9a3920b`였다.

기존 기준선의 설명용 `exceptions` 배열은 `observations`로 옮겨 보존했다. 관측 기록은 감사 항목을 제외하지 않는다. 실제 미지원·비해당을 감사에서 빼려면 repo-baseline `templates/github/README.md`의 `exceptions` 형식과 사유·근거가 필요하다.

## 과거 Bugbot 확인 기록

이전 설정 점검의 Cursor 조회는 브라우저 `Page.enable` timeout으로 실패했다. 당시 설정과 결제를 변경하지 않았고 대시보드 값은 미확인이었다. 같은 기록을 기준선 `observations`에도 보존한다. 이 과거 실패는 현재 연결 상태나 새 실행 요구를 뜻하지 않는다.

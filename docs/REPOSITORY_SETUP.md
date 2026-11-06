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
PR의 source-only 검사는 codeql.yml blob과 `codeql_main_source.sha`를 비교한다. Dependabot이 codeql.yml만 바꾸면 이 검사가 실패한다. 기준선 SHA를 `git hash-object .github/workflows/codeql.yml` 값으로 갱신한다.
공통 검사기(`check_github_settings.py`·`check_repo_baseline.py`·`check_review_status.py`·`rerun_review_status.py`·`workflow_policy.py`·`pr_author.py`)와 테스트는 `minjunkim-dev/repo-baseline`에서 복사한다. 이 저장소에서 직접 고치지 않는다. 원본을 고친 뒤 `tools/apply_baseline.py`로 다시 적용한다. 복사본이 `.github/repo-baseline.json`의 해시와 다르면 `python3 scripts/check_repo_baseline.py`가 실패한다. CodeQL 단계들이 서로 다른 `github/codeql-action` commit을 쓰는 것도 거부한다. `check_review_status.py`는 기본 브랜치의 [Review status workflow](../.github/workflows/review-status.yml)가 실행한다. PR 제목·브랜치·본문 절은 [PR policy workflow](../.github/workflows/pr-policy.yml)가 실행한다. PR CI의 source-only 테스트는 리뷰 검사기의 동작을 합성 fixture로 확인하고, `scripts/test_workflow_policy.py`는 그 파일이 저장소 루트를 기준으로 읽으므로 `scripts/`에서 실행한다.
기본 Actions token에 관리 권한을 추가하지 않는다. 오류·누락·drift 경로는 기존 source-only 검사에서 검증한다.

## 공통 정책

| 항목 | 기준 |
| --- | --- |
| 병합 | Squash만, PR title/body, 작업 브랜치 자동 삭제·업데이트 제안 On |
| Allow auto-merge | On. 일괄 예약 없음. 검증 후 exact-head 직접 병합 |
| main 보호 | PR 필수·strict·관리자 적용·선형 이력·대화 해결 On |
| 승인 | GitHub 0명. 되돌리기 어려움/broad 최종 head는 사람 승인 |
| 필수 체크 | 기대값 `CI`, `Review status`. 둘 다 GitHub Actions App `15368`. `strict`는 true. 서버에 적용되기 전 보호가 강제하는 체크는 `CI`다. 적용 뒤 Dependabot 버전 전용 PR을 뺀 모든 PR에 소유자의 `review/independent`가 필요하다 |
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

적용 원본은 `minjunkim-dev/repo-baseline`의 main `9a3920b942695257772f25083e8a4fde5d4e3208`다. 복사본의 경로·생태계를 유지하며 `tools/apply_baseline.py`로 갱신했다. 기존 테스트 대상 경로는 `scripts/source-only/`다. `scripts/test_workflow_policy.py`만 원본과 같은 `scripts/`에 둔다. 그 테스트가 자기 위치의 부모를 저장소 루트로 읽기 때문이다. Dependabot `ecosystems`는 빈 목록이다. `.claude/settings.json`은 적용 시점의 원본 템플릿과 바이트가 같다. 해시 manifest에는 없다. 기존 파일을 합치지 않았다. `templates/review-status.yml`은 별도 파일 `.github/workflows/review-status.yml`로 다시 복사했다. `templates/pr-policy.yml`은 `.github/workflows/pr-policy.yml`과 바이트가 같다. 둘 다 해시 대상이 아니고 pin은 템플릿과 같다. 다른 workflow와 합치지 않았다. 두 workflow의 `branches`는 `main`이다. `review-status.yml`의 이벤트는 `pull_request_target`과 `issue_comment`뿐이다. `pr-policy.yml`은 `pull_request`만 쓴다. `Door:` 값은 `되돌리기 쉬움` 또는 `되돌리기 어려움`이다. 옛 `양쪽 문`·`한쪽 문`과 옛 `한쪽 문 승인: <sha>`는 deprecated로 계속 인정한다. 1인 프로필에서 `review/independent`와 `review/security`는 `creator.login`이 저장소 소유자이거나 `scripts/check_review_status.py`의 `STATUS_ACTORS`에 있을 때만 success다. `STATUS_ACTORS`는 비어 있다. 다른 작성자의 status는 실패다. 승인 댓글은 `updated_at`이 `created_at`과 같은 문자열이고 GraphQL `lastEditedAt`이 null이며 `includesCreatedEdit`가 아닐 때만 인정한다. 편집한 댓글은 무효이고 새 댓글을 단다. 이어받기 해시는 diff와 바뀐 파일의 변경 후 blob id다. `.github/workflow-policy.json`은 원본 저장소 파일을 복사하지 않는다. `require_agents_md`는 기본값 true다. `reject_claude_md`는 false다. `CLAUDE.md`는 `@AGENTS.md` 한 줄이라 지우지 않는다. `feature_flags`는 false다. 이 저장소에 flag 레지스트리가 없다. 봇 브랜치 접두사는 기본값 `claude`·`codex`·`dependabot`이다. `cursor`는 더하지 않는다. 로컬 스킬 설정과 일상 작업 진입은 [개발 절차](agents/development.md), 자체 리뷰와 사용자 요청 회고는 [리뷰 절차](agents/review.md)를 따른다. 공통 기준이 더하는 `main` 경계는 원본 [개발 절차](https://github.com/minjunkim-dev/repo-baseline/blob/9a3920b942695257772f25083e8a4fde5d4e3208/docs/development-workflow.md)를 따른다.

기존 기준선의 설명용 `exceptions` 배열은 내용을 보존해 `observations`로 옮겼다. 관측 기록은 API 감사 항목을 제외하지 않는다. 실제 기능 미지원·비해당을 감사 범위에서 제외하려면 원본의 [설정 기준선 형식](https://github.com/minjunkim-dev/repo-baseline/blob/9a3920b942695257772f25083e8a4fde5d4e3208/docs/github-settings-profile.md)에 맞는 `exceptions` 객체와 사유·근거가 필요하다. 예외가 있으면 exit 0이어도 결과는 전체 PASS가 아닌 LIMITED다. 미선언 403·404·누락·권한 오류는 계속 실패한다.

`Review status`는 기본 브랜치에 있다. 이번 갱신은 `templates/review-status.yml`을 다시 복사한다. 주석은 편집된 소유자 댓글도 재실행되고, 검사기가 그 댓글을 승인으로 세지 않는다고 적는다. 댓글 재실행 step은 `COMMENT_ACTION`을 넘긴다. `pull_request_target`과 `pull_request`는 `branches: [main]`만 본다. 검사기는 PR base가 저장소 기본 브랜치가 아니거나 이벤트 base SHA가 그 브랜치 위에 없으면 실패한다. 실패 이름은 `review/base-branch`다. 사이드 base의 소유자 댓글은 체크를 게시하지 않는다. 이벤트 종류는 그대로다. 댓글 재실행 job의 `actions: write`와 `checks: write`는 이전 적용에서 이미 있다. Actions 이벤트 정책은 만들거나 고치지 않는다. 목록 조회가 실패하면 정책이 없는 것으로 보지 않는다. job 이름 `Review status`는 기본 브랜치 workflow에서 이미 성공했다(run `42016041442`). `.github/repository-settings.json`의 `required_status_checks.checks`에 `{"context": "Review status", "app_id": 15368}`을 더했다. `strict`는 true다. 기존 `CI`는 그대로다. context는 `.github/workflows/review-status.yml`의 job `name`과 같다. 이 파일은 기대값이다. 이 변경은 branch protection을 쓰지 않는다. 병합 뒤 소유자가 Mac에서 원본 `tools/apply_github_settings.py`로 적용한다. 적용되면 Dependabot 버전 전용 PR을 뺀 모든 PR(되돌리기 쉬움 포함)에 소유자가 올리는 `review/independent`가 필요하다. 신뢰 경계에 걸리면 `review/security`도 필요하다. status는 소유자만 올린다는 규칙이다. 에이전트가 status를 올리는 것은 금지지만 GitHub가 기술적으로 막지는 않는다. 카나리 결과는 [repo-baseline Issue #32](https://github.com/minjunkim-dev/repo-baseline/issues/32) 댓글에 있다.

이번 갱신은 `.github/repository-settings.json`의 필수 체크 기대값에 `Review status`를 더한다. 권한·CodeQL·배포·`strict`·기존 `CI`는 그대로다. 서버의 branch protection은 이 파일 변경으로 바뀌지 않는다. `actions: write`와 `checks: write`는 Review status의 댓글 재실행 job에만 있다. PR policy workflow의 권한은 `contents: read`다. 과거 실행 기록을 현재 검증 결과로 바꾸지 않는다.

## 과거 Bugbot 확인 기록

이전 설정 점검의 Cursor 조회는 브라우저 `Page.enable` timeout으로 실패했다. 당시 설정과 결제를 변경하지 않았고 대시보드 값은 미확인이었다. 같은 기록을 기준선 `observations`에도 보존한다. 이 과거 실패는 현재 연결 상태나 새 실행 요구를 뜻하지 않는다.

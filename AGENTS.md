# Runstir

프로필: 1인

재현 가능한 모바일 개발 런타임(`mobile` CLI와 macOS GUI). North Star: `git clone → mobile up`.
현재 상태: iOS React Native MVP 구현. 비공개 iOS internal-alpha는 [issue #83](https://github.com/minjunkim-dev/mobile-runtime/issues/83)이 정하고, 닫힌 [decision map #79](https://github.com/minjunkim-dev/mobile-runtime/issues/79)를 잇는다. [MVP 맵 #1](https://github.com/minjunkim-dev/mobile-runtime/issues/1)은 닫힌 과거 기록이다. 현재 결정은 `CONTEXT.md`와 `docs/adr/`에 있다.

## 명령

모든 에이전트와 사람이 같은 명령을 쓴다. 없는 칸은 `N/A: <이유>`다.

- setup: `swift package resolve --force-resolved-versions`
- check: `python3 -B -m unittest discover -s scripts/source-only -p 'test_*.py' && python3 -B scripts/test-release-input.py`  (CI는 actionlint·shellcheck도 돌린다)
- test: `swift test --force-resolved-versions -Xswiftc -warnings-as-errors`
- build: `swift build --force-resolved-versions -Xswiftc -warnings-as-errors`

CI 전체(`.github/workflows/ci.yml`)는 위에 더해 `scripts/verify-*-input.py`, release 패키지 검증, Linux Core 컴파일을 돌린다.

## 길잡이

| 경로 | 무엇 |
| --- | --- |
| `Sources/` | Core(플랫폼 독립), EnvironmentKit(CLI·GUI 공통 판단), SimulatorKit·AndroidKit, `mobile` CLI, RunstirGUI |
| `Tests/` | Swift 테스트와 fixture |
| `scripts/` | 패키징·검증 스크립트. `scripts/source-only/`는 합성 테스트 |
| `CONTEXT.md`, `docs/adr/` | 도메인 용어와 결정. [도메인 읽기](docs/agents/domain.md) |
| `docs/agents/` | [개발 절차](docs/agents/development.md)(작업 진입), [리뷰 절차](docs/agents/review.md)(CI·병합), [이슈 추적](docs/agents/issue-tracker.md), [라벨](docs/agents/triage-labels.md) |
| `docs/REPOSITORY_SETUP.md` | GitHub 설정 기대값과 감사 방법 |
| `REVIEW.md` | 리뷰 기준. 리뷰할 때만 읽는다. 상세 규칙은 `docs/coding-standards.md` |

이 파일이 에이전트 공통 지침이다. 도구별 지침 파일을 따로 두지 않는다. Claude Code는 `CLAUDE.md`가 없으면 이 파일을 읽으므로 `CLAUDE.md`·`.claude/CLAUDE.md`·`CLAUDE.local.md`를 만들지 않는다. 하나라도 있으면 Claude Code가 이 파일을 읽지 않는다. 이슈는 GitHub Issues(`minjunkim-dev/mobile-runtime`)를 `gh`로 다룬다.

## 작업 방식

- 기준 브랜치는 `main` 하나다. 작업 브랜치는 짧게, 병합은 squash다. 끝나지 않은 기능은 꺼진 플래그 뒤에 둔다.
- 완료 주장은 위 명령의 실제 출력이다. PR 본문 Evidence에 명령과 결과를 적는다. CI 성공은 티켓이 요구한 실제 측정을 대신하지 않는다.
- 병합 전에 구현과 다른 컨텍스트의 리뷰어가 `REVIEW.md`로 변경분을 본다. 결과는 PR 본문 Review에 적는다.
- PR 본문의 Merge Danger에 되돌리기 쉬움/어려움, 영향 범위, 되돌리는 법을 적는다. 애매하면 되돌리기 어려움이다.
- 되돌리기 어려움이거나 신뢰 경계(`REVIEW.md`)를 건드리면 보안 리뷰를 더하고, 사람이 diff를 읽고 그 head에서 병합한다.
- 같은 실수가 두 번 나오면 린트·검사로 막고, 그다음 `REVIEW.md` 한 줄, 그다음 이 파일의 길잡이 순서로 고친다.
- 작은 수정에는 전체 명세 절차를 강제하지 않는다.

## 하지 않는 것

- 비밀값(`.env*`, 키, 토큰)을 읽거나 커밋하지 않는다. `.env.example`은 예외다.
- `main`에 직접 push하지 않는다. PR을 병합하지 않는다. 병합은 사람이 한다.
- 브랜치 보호·저장소 설정·CI workflow를 사람 승인 없이 바꾸지 않는다.

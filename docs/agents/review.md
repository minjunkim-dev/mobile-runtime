# PR 품질 절차

로컬 구현 → 로컬 독립 리뷰 → 직접 수정 → 최종 CI → 사람 병합이 기본 흐름이다.
사람은 목표와 합격 기준을 정하고, 최종 head를 읽고 병합한다.
CI 성공은 티켓의 실제 측정이나 독립 리뷰를 대체하지 않는다. 리뷰 기준은 루트 [`REVIEW.md`](../../REVIEW.md)다.

## 구현과 리뷰

1. 최신 `origin/main`과 변경 범위를 기록한다. 티켓의 acceptance criteria를 확인한다.
2. 로컬 구현 에이전트가 필요한 변경을 구현한다. 영향받는 동작 검사를 실행한다.
3. 별도 컨텍스트의 로컬 리뷰 에이전트에게 base SHA, 변경 파일, acceptance criteria, 검증 결과를 전달한다. 리뷰 에이전트는 `REVIEW.md`와 거기서 고른 문서를 읽는다.
4. 리뷰 에이전트는 확실한 문제를 직접 수정하고 커밋한다. 각 에이전트의 파일 소유권을 구분한다. 다른 작업을 되돌리지 않는다. 불확실한 문제와 범위 밖의 문제만 짧게 보고한다.
5. 수정 후 영향받는 검사를 다시 실행한다. 리뷰어가 수정 커밋을 더했으면 최종 head의 diff를 그 수정과 다른 컨텍스트에서 `REVIEW.md`로 다시 본다(POLICY §3의 2라운드: 바뀐 부분만). 최종 head의 필수 `CI` 성공을 확인한다. PR 본문의 Evidence·Merge Danger·Review를 갱신한다.

리뷰는 테스트가 요구 동작을 실행하는지 확인한다. fake가 실제 실패를 표현하는지 확인한다.
독립 리뷰를 실행할 수 없으면 그 한계를 PR에 기록한다.
같은 모델을 사용해도 컨텍스트는 분리한다. 다른 모델 패밀리는 권장이고 필수가 아니다. 쓴 모델은 Review 칸에 기록한다.
이 문서는 에이전트 작업 중 수행할 절차다. PR 생성으로 로컬 에이전트를 자동 기동하는 상시 프로그램을 뜻하지 않는다.

## CI

필수 check 이름 `CI`는 `.github/workflows/ci.yml`의 집계 job이다. 모든 하위 job이 성공해야 `CI`가 성공한다. `.github/repository-settings.json`이 `CI`를 필수 체크로 기록한다.

| 검사 | 확인하는 것 | 확인하지 않는 것 |
| --- | --- | --- |
| Repository hygiene | 라이선스, workflow, shell, source-only 합성 테스트 | 실제 ADB 자원과 provenance |
| macOS Swift build and tests | 잠근 의존성, 경고 없는 빌드, Swift 동작, 실제 CLI 입력 계약 | 실제 모바일 첫 화면과 release 승인 |
| macOS release package verification | 별도 disposable build와 배포 archive의 리소스 독립성 | 공개 배포와 release 승인 |
| Linux Core compile | Apple 프레임워크 없는 Core 컴파일 | Linux 제품 지원 |

수동 `Simulator smoke` workflow는 필수 `CI`가 아니다. 실제 simctl 동작을 확인한다. 실행 시점은 `docs/ci-reproducibility.md`를 따른다.
source-only 테스트는 `test_*.py`를 자동 탐색한다. AST 검사는 정적 I/O 금지 제약에만 사용한다.
새 동작 검사는 interface를 실행한다. 기존 검사를 약화해서 CI를 통과시키지 않는다.
새 formatter 도입은 별도 변경으로 평가한다. 기존 전체 소스를 포맷하는 변경을 섞지 않는다.

## CI 실패 처리

담당 로컬 에이전트는 맡은 PR의 CI가 완료될 때까지 결과를 확인한다.

1. PR의 head·base SHA와 실패한 run·attempt를 기록한다. `gh run view <RUN_ID> --repo <OWNER/REPO> --log-failed`로 실패 로그를 확인한다.
2. 코드 결함과 인프라 장애를 구분한다. 가능한 실패는 로컬에서 재현한다. 재현하지 못한 범위는 기록한다.
3. 범위 안의 원인을 수정하고 관련 검사를 실행한다. 검사 삭제·skip·조건 완화로 실패를 숨기지 않는다. 같은 실패를 근거 없이 반복 재실행하지 않는다.
4. 수정 내용을 커밋·푸시한다. 새 head의 CI를 확인한다. 이전 커밋의 성공을 새 head의 근거로 사용하지 않는다.
5. 최종 head의 diff를 별도 컨텍스트에서 `REVIEW.md`로 다시 검토한다. 신뢰 경계면 보안 리뷰도 다시 한다.

접근 권한 부족이나 해결하지 못한 실패가 남으면 원인과 미확인 범위를 보고한다.

## PR 본문과 병합

`.github/pull_request_template.md`의 Author, Summary, Evidence, Merge Danger, Review를 사용한다.
`Door:`는 `되돌리기 쉬움` 또는 `되돌리기 어려움`만 쓴다. 기준은 repo-baseline `POLICY.md` §4다. 애매하면 되돌리기 어려움이다.
Summary에는 변경 흐름을 보여주는 작은 도식을 둔다. Evidence에는 실제 명령과 결과를 둔다.
문서 변경이면 기존 규칙과 새 규칙을 비교한다. 실행하지 않은 검사를 성공으로 기록하지 않는다.

- 병합은 사람만 한다. 에이전트는 `gh pr merge`를 실행하지 않는다. 자동 병합은 쓰지 않는다(`allow_auto_merge: false`).
- 되돌리기 어려운 데이터 변경, 외부 대량 발송, 파괴적인 정리, 권한 확대, 신뢰 경계 경로는 되돌리기 어려움으로 처리한다. 사람이 최종 head와 영향 범위를 읽고 그 head에서 병합한다. 그 뒤 push가 있으면 다시 읽는다. 병합할 때 `gh pr merge <PR> --squash --match-head-commit <읽은 SHA>`처럼 읽은 head를 지정한다.
- 많은 프로젝트의 실행 동작이나 공개 계약을 바꾸는 변경은 broad로 PR에 적는다. diff 크기로 위험을 결정하지 않는다.
- 사람 판단이 필요한 PR은 `ready-for-human`으로 표시한다.
- 리뷰 이후 커밋이나 base가 바뀌면 영향받는 검증을 갱신한다.

## 회고

사용자가 요청할 때만 한다. 매 PR·정기 자동 회고는 만들지 않는다. repo-baseline `prompts/retro.md` 또는 설치된 `mattpocock-skills:retro` 원문을 따른다.
같은 지적이 두 번 나오면 린트·검사 > `REVIEW.md` 한 줄 > `AGENTS.md` 길잡이 순서로 옮긴다. 사용자가 고른 개선만 반영한다.

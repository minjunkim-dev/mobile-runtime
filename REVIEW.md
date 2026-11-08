# 리뷰 기준

리뷰 에이전트가 읽는 파일이다. 구현 에이전트에게 상시 주입하지 않는다.
리뷰는 구현과 다른 컨텍스트에서 한다. 입력은 변경분(diff), 이 파일, 확정된 완료 기준이다.
상세 규칙은 [코딩 규칙](docs/coding-standards.md)에 있다. 도메인 용어는 `CONTEXT.md`, 결정은 관련 `docs/adr/`를 따른다.

## 실패로 보는 것

| 영역 | 실패 |
| --- | --- |
| 설계 | 실제로 달라지는 동작 없이 seam·추상화를 더한다. Core에 Apple 프레임워크 의존이 들어가 Linux 컴파일이 깨진다. CLI와 GUI의 공통 판단이 EnvironmentKit 밖에 있다. 포맷 변경·대규모 리팩터가 섞였다 |
| 검증 | 테스트가 호출자 interface가 아니라 구현 상수·소스 문자열을 단언한다. fake가 실패·취소·부분 완료를 표현하지 못한다. 버그 수정에 수정 전 실패하는 검사가 없다. 기존 검사를 약화·skip해서 통과시켰다 |
| 실행 | ProcessRunner를 거치지 않거나 명령 인자를 문자열로 조합한다. 종료 상태·취소를 잃는다. plan approval과 repository trust를 섞는다. 실행 직전 조건·lease 검사를 생략한다. 실행이 소유하지 않은 자원·사용자 데이터를 정리한다 |
| 근거 | 알 수 없는 결과를 성공으로 바꾼다(doctor `unknown`, 검증 `inconclusive`, source-only `UNKNOWN`을 써야 한다). MODEL-ONLY·CI·archive 근거를 실제 기기·지원 범위·actual readiness로 올린다. 토큰·key bytes·개인 경로를 로그·공개 근거에 남긴다 |
| CI·패키징 | token에 필요 없는 쓰기·Secret을 준다. Secret 환경에서 PR 코드를 실행한다. 외부 Action을 SHA로 고정하지 않는다. 하위 검사 실패·취소·누락이 집계 `CI` 성공으로 숨는다. Draft가 main 밖 SHA를 쓰거나 기존 Release·태그·asset을 덮어쓴다 |
| 문서 | 사실과 다르다. 명령이 실제로 동작하지 않는다. 실행하지 않은 검사를 성공으로 적는다 |
| 설정 | 사용자를 잘못된 곳으로 보낸다. 권한을 넓힌다 |

## 변경 영역별로 더 읽을 것

| 변경 영역 | 읽을 문서 |
| --- | --- |
| Swift·CLI·GUI·실행 | `CONTEXT.md`, 관련 `docs/adr/`의 public contract·trust·approval·lease 결정 |
| 검사·패키징·source-only | 해당 스크립트의 계약 문서·ADR·티켓의 실제 측정 조건 |
| GitHub·CI·Draft | `docs/REPOSITORY_SETUP.md`, `docs/release-install.md`, 관련 workflow와 입력 계약 |
| 문서·권리 | 바꾼 기준 문서·관련 ADR, `LICENSE`와 출처 기록 |

## 심각도

- P0: 데이터 손실, 보안 구멍, 되돌릴 수 없는 결과. 병합하지 않는다.
- P1: 기능이 틀리거나 깨진다. 병합 전에 고친다.
- P2: 개선 제안. 상한 5개. 넘으면 버린다. 스타일 취향만으로 지적하지 않는다.

## 건너뛸 것

- 포매터·린터가 이미 잡는 스타일.
- 이 PR이 만들지 않은 기존 문제(필요하면 "기존 문제"로 따로 표시한다).
- `docs/evidence/**`의 기록된 출력, `Tests/**/Fixtures/**`의 캡처 fixture, `Package.resolved`의 해시 줄, `licenses/`.

## 신뢰 경계

Door가 되돌리기 어려움이거나 아래를 건드리면 별도 컨텍스트의 보안 리뷰를 더한다. 확실한 문제는 최종 head에서 고치고 다시 검증한다. 보안 리뷰 통과를 실제 실행 안전성의 증거로 쓰지 않는다.

- `.github/workflows/**`, `.github/repository-settings.json`, `.github/dependabot.yml`
- 의존성: `Package.swift`, `Package.resolved`
- 에이전트 권한: `.claude/settings.json`
- 배포: `Formula/`, `packaging/`, `scripts/package-release.sh`, `scripts/validate-release-input.py`, `scripts/verify-release*.sh`·`.py`
- 승인·trust·lease·정리: `Sources/Core/Lease/`, `Sources/Core/Down/`, `Sources/*/*Teardown.swift`, 외부 명령 실행·파일 삭제·경로 검증을 바꾸는 코드

## 보고와 수정

- 근거는 `file:line`이다. 이름만 보고 추측하지 않는다.
- 확실한 결함은 직접 고쳐 커밋하고 영향받는 검사를 다시 돌린다. 판단이 필요한 것(불확실한 동작, ADR 변경, 승인 범위 확대)만 구체적인 질문으로 남긴다.
- 지적은 개별 줄이 아니라 버그 유형으로 묶어, 같은 유형을 한 번에 고치게 한다.
- 보고는 지적 개수(P0/P1/P2)로 시작한다.

## 라운드

- 최대 3라운드. 2라운드부터는 직전 수정으로 바뀐 부분만 본다.
- 이미 보고한 지적은 다시 보고하지 않는다.
- 3라운드 뒤에도 남으면 목록을 늘리지 말고 구현 방식을 다시 생각하라고 보고한다.

## 배운 규칙

리뷰가 놓친 버그나 반복된 오탐이 생기면 한 줄씩 더한다. 사용자가 승인한 것만 넣는다.

- `<YYYY-MM-DD> <규칙>`

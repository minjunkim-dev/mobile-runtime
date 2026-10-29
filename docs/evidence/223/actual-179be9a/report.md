# 로컬 unsigned 후보 증거 보고서

확인 날짜: 2026-10-19. 범위: issue #223 개발·테스트 단계의 증거 연결과 무결성 검사.

후보 source는 `179be9a466dbc57b1d1753f5a67bd87f97c423a5`다. 제품 버전은 `0.1.0-alpha.7`이다.
Core identity는 `ca1ed0772cce65280ab2e818077c933fdd01cc2f922b79942c3d97228957e237`이다.
이 source는 미병합 PR #284의 source다. 최종 출시 후보가 아니다.

원본 `CANDIDATE.json`의 `ciRun=null`, `signing=unsigned`, `notarization=not-requested`, `distributionReady=false`를 유지한다.
CLI archive·DMG·Homebrew formula는 원본 그대로 대조한다. 후보를 실행하거나 mount하거나 재제작하지 않는다.

## 결과 연결

`manifest.json`은 후보와 이 보고서의 checksum을 연결한다. `tuples.json`은 검증 입력을 기록한다.
`results.json`은 gate·표본·CLI/GUI·시도·기대·관측·결과·증거·미검증 조건을 기록한다.
`restricted-index.json`은 제한 원본 19개의 실제 bytes와 SHA256을 고정한다.

| 항목 | 관측 | 판정 범위 |
| --- | --- | --- |
| AC15 package integrity | 실제 CLI archive·DMG·formula와 후보 JSON | 같은 로컬 unsigned 후보의 bytes 연결 |
| AC15 원본 명령 | 원본 8개 명령의 exitCode 0 | 저장된 실제 실행 receipt. 이번 작업의 재실행이 아님 |
| AC15 같은 source CI | 보관된 run 39128989068의 5개 job success | 원본 ciRun과 별도 연결. 현재 GitHub 상태 조회가 아님 |
| AC17 원본 연결 | 원본 index 2개와 나머지 17개 파일 | 명시 allowlist의 무결성 |
| AC17 초기 GUI 시도 | headless 캡처·제한 실행의 관측 한계 | inconclusive 이력 보존 |
| AC17 후속 GUI 시도 | 같은 source의 실제 화면·교체·정상 종료·별도 CLI 보존 receipt | 해당 관측만 pass. 초기 시도도 보존 |
| AC01~AC19 전체 필수 행렬 | 이 bundle에서 수집하지 않은 항목을 명시 | unverified. 전체 게이트 완료가 아님 |

검사는 증거 무결성을 `verified`로 기록할 수 있다. 출시 판정은 `blocked`다. 종료 코드는 1이다.
정확한 OS·도구체인·런타임 버전을 이 작업에서 독립 재고정하지 않았다. tuple에 `unknown`을 남긴다.
기존 관측의 정확한 시각과 실행자를 이 작업에서 독립 확인하지 않았다. 각 attempt의 `observedAt`과 `executor`에 `unknown`을 남긴다. 이 필수 값도 출시 판정을 차단한다.
서명·공증·stapling·Gatekeeper·제한 배포 다운로드·Homebrew 실제 설치와 최종 후보 검증을 최종 단계로 유지한다.
이 보고서는 AC15·AC17의 검사 구현을 입증하는 실제 입력이다. AC15·AC17 전체 수용 기준의 완료를 선언하지 않는다.

## 원본 보관과 공개 검토

실제 보관소는 소유자 Documents의 `Codex/2026-10-18/runstir-222-final-preparation` 폴더다.
보관소 식별자는 `runstir222-final-preparation`이다. 접근 담당자는 `minjunkim-dev`다.
담당자가 로컬 접근을 관리한다. 공개 보고서는 호스트 절대 경로를 포함하지 않는다. 검사에는 `--private-root`로 실제 위치를 전달한다.

공개 자료는 새 JSON과 이 텍스트 보고서다. 구현 담당자가 이 텍스트와 JSON의 비식별 내용을 검토했다.
원본 로그·화면은 제한 보관소에 둔다. 새 공개 화면은 없다. 자동 문자열 검사는 화면의 비식별 안전성을 증명하지 않는다.
인증 정보·private key·민감 환경값과 인증·세션 파일은 수집 대상이 아니다. 전체 폴더를 탐색하거나 hash하지 않는다.

과거 원본 보고서와 두 원본 index를 수정하지 않았다. 초기 GUI 한계와 후속 검증은 서로 다른 attempt다.
이전 결과 snapshot을 인계받으면 `priorResults`에 원본 checksum을 고정한다. 검사는 이전 attempt·요구사항의 삭제와 변경을 차단한다.
후보나 입력이 달라지면 별도 bundle을 만든다. 이전 bundle을 보존한다. checkpoint 자체의 삭제를 탐지하려면 리뷰에서 이전 Git 기록과 인계 checksum을 대조해야 한다.

검사는 선언한 요구사항의 참조·identity·결과를 검사한다. AC01~AC19 gate 누락도 차단한다.
각 AC의 세부 시나리오가 완전한지와 관측의 의미가 맞는지는 독립 리뷰에서 확인한다.
이 검사 결과는 실제 앱·기기·접근성·서명·배포 증거를 대신하지 않는다. fixture는 출시 pass에 합산하지 않는다.

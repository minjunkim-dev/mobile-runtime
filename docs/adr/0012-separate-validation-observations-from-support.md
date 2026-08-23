# ADR-0012: 검증 관측과 지원 범위를 분리한다

- 상태: 채택
- 날짜: 2026-08-23
- 관련: #93 · ADR-0003 · ADR-0004 · ADR-0011

단일 host에서 모든 React Native·Xcode·iOS runtime 조합을 전수 검증할 수 없고 schema v1 Matrix는 최소 버전 하한만 표현하므로, 하나의 로컬 성공이나 실패를 지원 범위로 승격하지 않는다. project SHA·mobile SHA·검증 조합을 고정한 known-good 표본의 결과는 `validated`·`failed`·`inconclusive`로 기록하되, 별도의 지원 범위 근거가 생기기 전에는 Matrix를 바꾸지 않고 doctor의 `unknown`을 유지한다.

조사 실행은 `unknown`을 기록한 뒤 build·up·초기 UI까지 진행할 수 있지만 internal alpha pass로 인정하지 않고 runbook이나 프로젝트 선언을 바꾸지 않는다. 입력 중 하나가 바뀌면 전체 실행을 새로 하며, known-good baseline 전의 부적격 표본은 교체할 수 있지만 검증 결과가 나온 뒤에는 추가 표본의 결과를 누적한다.

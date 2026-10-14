# Runstir Swift 영역 리뷰

- Core의 플랫폼 의존 분리와 CLI·GUI의 공통 EnvironmentKit 판단을 유지한다. 호출자마다 검증 순서를 복제하지 않는다.
- ProcessRunner의 안전한 argv·종료 코드·timeout·취소·부분 완료를 확인한다. 실행이 소유한 자원만 정리한다.
- plan approval·repository trust·실행 직전 조건·lease 검사를 구분한다. 실패하면 실행하지 않는 경계를 유지한다.
- CLI 입력·경로·프로젝트 설정의 정상·거부 흐름과 GUI 상태·비동기 응답의 회귀를 확인한다.
- MODEL-ONLY와 unknown·inconclusive·UNKNOWN 판정을 실제 자원·readiness로 바꾸지 않는다.

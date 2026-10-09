# Runstir 승인형 환경 준비 계약

상태: 2026-10-09 첫 질문 묶음 사용자 승인. 후속 결정과 전체 계약 확인 전이다.
티켓: [결정: 승인형 환경 준비의 변경과 복구 계약](https://github.com/minjunkim-dev/mobile-runtime/issues/182).
기준 source: `1a4ff6dc3815ab6c25df81eaef8ca37acaefe21e`.
제품 코드, 설치 또는 복구 동작을 구현·검증한 문서가 아니다.

## 첫 질문 묶음에서 확정한 정책

사용자는 2026-10-09 `그래 일단 모두 추천대로.`로 아래 다섯 권장안을 승인했다.

1. 환경 준비는 별도 `mobile setup` 명령으로 제공한다. 환경을 검사하고 부족한 항목을 준비한다. `build/up`에서 도구가 부족하면 `setup`을 안내한다.
2. 설치 버전·경로·다운로드·기기 생성 목록을 변경 계획으로 보여주고 계획 전체를 한 번 승인받는다. 저장소 신뢰·라이선스 동의·관리자 권한은 별도로 확인한다. 계획 밖 변경이 필요하면 다시 승인받는다.
3. 기존 도구와 기기를 재사용한다. 필요한 버전은 가능한 경우 나란히 설치한다. 기존 버전 삭제, 전역 설정 변경, 프로젝트 소스·lockfile 변경은 수행하지 않는다.
4. 실패·중단 뒤 완료한 설치는 보존한다. 재실행하면 실제 상태를 다시 검사하고 남은 작업을 계획한다. 설치한 SDK를 일괄 삭제하는 복구는 하지 않는다.
5. 기기 신뢰·Developer Mode·Android 디버깅 승인·Apple 계정과 개발용 서명은 안내한다. 사용자가 처리한 뒤 준비 상태를 다시 검사한다.

Flutter·React Native의 준비 범위는 iOS·Android 양쪽이다. 특정 앱 실행의 플랫폼 선택으로 이 범위를 줄이지 않는다. 플랫폼 입력 후 실행 기기 선택, 근거 있는 기본값, CLI/GUI 공용 계약은 [공통 CLI 계약](./cli-expansion-common-contract.md)을 따른다.

## 기존 계약과의 관계

[ADR-0009](./adr/0009-activate-project-toolchains-without-provisioning.md)의 `build/up` 도구 자동 프로비저닝 금지를 유지한다. 승인형 프로비저닝은 별도 준비 흐름에 속한다. 이번 문서로 기존 제품 동작을 변경하지 않는다.

프로젝트 의존성 정렬, 도구체인 활성화, 새 도구 프로비저닝과 앱 환경값은 각각의 경계를 유지한다. 프로젝트 소스·선언·lockfile을 바꾸는 마이그레이션은 이번 지도의 범위 밖이다. 하위 도구의 자동 다운로드·trust·파일 변경도 승인 범위에서 확인해야 할 대상이다. 승인 계획만으로 그 통제가 구현되었다고 간주하지 않는다.

## 아직 결정하지 않은 정책

- 버전 범위 또는 누락된 선언에서 실제 설치 버전을 고르는 기준.
- 기존 설치 관리자 재사용과 새 설치 수단·경로의 선택 기준.
- 없는 가상 기기의 runtime·기기 조건·생성과 기존 기기 이름 충돌 처리.
- 준비가 의존성 정렬까지 수행하는지와 플랫폼별 부분 완료·수동 단계의 결과.
- 비대화식 승인, 계획의 유효성, 재실행 및 실제 변경 기록의 계약.

세부 CLI 옵션·JSON 필드·모듈 경계는 후속 `/to-spec`에서 구체화한다. 지원 버전과 검증 조합은 [결정: 지원 경계와 새 Mac 검증 기준](https://github.com/minjunkim-dev/mobile-runtime/issues/183)에서 정한다.

## 조사 근거

- [조사: macOS 승인형 도구 설치의 자동화 경계](https://github.com/minjunkim-dev/mobile-runtime/issues/178).
- [조사: Flutter·네이티브 프로젝트의 정본과 실행 경로](https://github.com/minjunkim-dev/mobile-runtime/issues/179).
- [조사: Simulator·Emulator 준비와 생성의 자동화 경계](https://github.com/minjunkim-dev/mobile-runtime/issues/180).
- [조사: 연결 실기기의 준비와 앱 실행 계약](https://github.com/minjunkim-dev/mobile-runtime/issues/185).

설치 도구 전체의 안전한 다운로드 재개·원자적 rollback은 조사에서 확인하지 못했다. 이번 정책은 상태 재검사와 완료 자원 보존을 요구하며, 도구가 지원하지 않는 복구를 약속하지 않는다.

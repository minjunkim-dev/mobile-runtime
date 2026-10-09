# Runstir 지원 경계와 새 Mac 검증 기준

상태: 2026-10-09 질문 1~5의 결정 기록이다. 지원 경계 결정 전체는 진행 중이다.
티켓: [결정: 지원 경계와 새 Mac 검증 기준](https://github.com/minjunkim-dev/mobile-runtime/issues/183).
제품 코드·도구 설치·앱 실행을 구현하거나 검증한 문서가 아니다.

## 첫 질문에서 확정한 정책

사용자는 질문 2를 제외한 추천안을 승인했다. 질문 2는 Simulator/Emulator 검증으로 충분하다고 변경했다.

1. Xcode 지원 하한은 `27.0`이다. Xcode `26.x` 이하는 제외한다. 정식 버전을 지원 대상으로 삼는다. RC·beta는 실험 대상으로 분리한다. Flutter·React Native·Android 도구도 공식 호환 조건과 실제 검증을 만족하는 정식 버전 조합을 지원한다. 숫자가 하한보다 높다는 이유로 모든 미래 버전을 지원한다고 주장하지 않는다. 프로젝트 선언 우선과 설치 버전 재사용 정책을 유지한다. macOS 검증은 보존한 macOS 27 기준 환경에서 시작한다. macOS 하한과 정확한 SDK 버전은 공식 요구사항과 검증 조합으로 잠근다. Xcode 26.x 제외를 macOS 26.x 제외로 해석하지 않는다.
2. 첫 정식 출시의 필수 실행 검증은 네이티브 iOS·네이티브 Android·Flutter iOS/Android·React Native iOS/Android의 여섯 조합을 Simulator/Emulator에서 수행한다. 실기기 검증은 필수 출시 조건이 아니다. 기존 플랫폼·기기 선택 및 실기기 실행 계획을 제거하는 결정은 아니다. Simulator/Emulator 성공을 실기기 검증 성공으로 보고하지 않는다. 실제 실기기 검증 전에는 그 경로를 검증됨으로 표시하지 않는다.
3. 각 조합에 최소 앱과 실제 OSS 앱을 사용한다. Flutter·React Native는 같은 앱의 두 플랫폼을 검증할 수 있다. 특정 기존 앱 이름을 필수 조건으로 삼지 않는다. 앱 형태·공개 접근 가능성·선언과 환경값 준비 가능성을 확인한 뒤 SHA와 검증 조합을 잠근다. 실제 앱은 Runstir 없이 같은 조건에서 build·install·launch·첫 화면에 도달하는 known-good baseline을 확인한다. Runstir 실행은 다른 fresh clone을 사용한다. baseline 부적격 표본 교체와 결과 이후 추가 표본 누적을 구분한다. 실패 기록을 성공 표본으로 대체해 지우지 않는다. 기존 단일 게이트의 tracked 파일 예외를 새 표본에 일반화하지 않는다.
4. 개발 도구가 없는 환경과 기존 도구·기기가 있는 환경을 모두 검증한다. 새 환경은 수동 Xcode 설치·계정·라이선스 안내와 재검사를 포함한다. 기존 환경은 재사용·재실행·중단 후 복구와 자원 보존을 확인한다. Tart는 가능한 검증에 사용한다. Android Emulator 가속 등 실제 Mac이 필요한 경로는 실제 Mac에서 확인한다. VM 결과로 실제 Mac 또는 실기기 성공을 대신하지 않는다. 기준 VM은 보존한다.
5. source·표본 SHA·도구/OS 버전·선택 기기 identity와 doctor/setup/build/up/down 결과를 기록한다. 선택한 기기에서 올바른 앱의 첫 화면을 직접 확인한다. 필요하면 비밀값·개인 정보를 제외한 화면 증거를 남긴다. RN red box·crash·빈 화면과 종료 코드 0만으로는 성공하지 않는다. tracked 파일·기존 자원의 실행 전후 보존도 확인한다. 준비 완료와 앱 실행 성공을 분리한다. 계정 로그인이나 첫 화면 이후의 앱 기능 검증은 이 기준 밖이다. 민감한 파일·환경값·원본 전체 로그를 공개 증거에 넣지 않는다.

## Xcode 배포 상태 확인

2026-10-09 Apple 공식 자료에서 Xcode 27 정식과 Xcode 27.1 RC를 확인했다. Apple은 Xcode 27.1 RC (`27A9275`)를 2026-10-05에 발표했다.

- [Apple Xcode 지원표](https://developer.apple.com/xcode/system-requirements)
- [Xcode 27.1 RC 발표](https://developer.apple.com/news/releases/?id=10052026g)
- [Xcode 27.1 Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_1-release-notes)

배포 상태 확인은 Runstir 호환성 검증이 아니다. Xcode 27.1 정식이 나오면 검증 후 지원 조합에 추가하는 방향을 제안했다. 기존 설치를 자동 교체하지 않는 준비 계약을 유지한다. 구체적인 버전 유지·지원 갱신 정책은 다음 질문에서 확정한다.

## 기존 계약과의 관계

[공통 CLI 계약](./cli-expansion-common-contract.md)과 [준비 계약](./cli-expansion-preparation-contract.md)을 유지한다. [ADR-0012](./adr/0012-separate-validation-observations-from-support.md)의 검증 조합과 지원 범위 구분을 유지한다. [ADR-0018](./adr/0018-use-one-xcode-27-go-sample.md)의 기존 BlueWallet iOS Go 게이트와 과거 검증 결과를 변경하지 않는다.

공동 1.0.0 출시 게이트는 이 결정의 Simulator/Emulator 필수 검증 범위를 입력으로 사용한다. 실기기 실행 계획과 실기기 검증 증거를 구분한다. 이 문서만으로 공동 출시 게이트 전체가 확정되지는 않는다.

## 남은 결정

- 새 정식 버전의 검증·지원 갱신과 기존 검증 버전 유지 정책.
- 미검증 조합·명백한 미지원·필수 요구사항 실패·미선언 요구사항의 처리.
- 실패·취소·재실행·파일과 자원 보존 시나리오 및 구체 버전·표본 선정 인계 조건.

아직 사용자 승인을 받지 않은 세부 정책과 정확한 SDK 버전을 이 문서에서 확정하지 않는다.

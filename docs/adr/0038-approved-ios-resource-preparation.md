# ADR-0038: 승인한 iOS runtime과 Simulator를 준비한다

날짜: 2026-10-16
상태: provider 구현. 공통 setup 연결, 실제 CLI·GUI 검증과 최종 승인은 별도다.
관련: #199, #206, #202, #204, ADR-0009, ADR-0035, ADR-0036

## 준비 경계

`build/up`은 runtime이나 Simulator를 새로 설치·생성하지 않는다.
환경 준비는 기존 `PreparationExecution`의 plan-id·재확인·공통 lease를 사용한다.
`IOSPreparation`은 같은 계획에 필요한 iOS 검사와 `InstallationAction`을 제공한다.
CLI와 GUI에 각각 설치기를 만들지 않는다.

기존 적합 runtime·Simulator를 먼저 재사용한다.
선택 순서는 기존 `SimulatorSelector`의 선언 이름·booted·최신 iPhone 순서를 유지한다.
runtime의 실제 OS build·architecture·availability를 확인한다.
native iOS는 선택한 공유 app scheme의 deployment target보다 낮은 runtime을 고르지 않는다.
새 runtime 후보는 검증 입력의 정확한 `27.0`이다. `latest`나 beta로 대신하지 않는다.
프로젝트 요구가 이 후보보다 높거나 기기 조건이 불명확하면 수동 단계를 반환한다.

## runtime identity와 설치

Apple의 공식 `index2.dvtdownloadableindex`에서 정식 OS·build·architecture·asset identity·크기를 읽는다.
catalog SHA-256은 metadata의 내용 식별값이다. runtime payload checksum이 아니다.
MobileAsset 항목은 별도 payload URL·checksum을 제공하지 않는다.
archive 필드를 가짜 값으로 채우지 않는다. `ManagedInstallation.iosRuntime`에 알려진 pin을 담는다.

공식 `xcodebuild -downloadPlatform iOS -buildVersion <OS> -architectureVariant arm64` 경로를 사용한다.
명령 직전에 선택한 Xcode identity·초기 설정·catalog·기존 Simulator 상태를 다시 확인한다.
명령 뒤에는 실제 runtime OS build·architecture·availability를 대조한다.
이 API에는 asset UUID를 직접 전달하는 인자가 확인되지 않았다.
따라서 이 경로를 payload bytes의 원자적 고정이나 checksum 검증으로 표시하지 않는다.
실제 검증에서 정확한 artifact 보장을 확인하지 못하면 그 조건은 manual/inconclusive다.
잘못된 build나 관측 불가는 실패로 남긴다. 관측한 자원을 삭제하거나 원래 상태로 되돌리지 않는다.

`destination/resourceRoot`는 실제 `/Library/Developer/CoreSimulator` 저장 parent다.
정확한 runtime leaf identity는 typed pin과 관측 결과가 담는다.
runtime import는 관측한 모든 기존 device ID의 lease와 global runtime lease를 함께 요구한다.
기존 device는 모두 `Shutdown`이어야 한다. 다른 Xcode·Simulator 작업도 없어야 한다.
Simulator 생성은 같은 global runtime lease와 실제 `Devices` parent lease를 함께 사용한다.
서로 다른 기존 device의 일반 `up`을 global exclusive lease로 직렬화하지 않는다.
외부 Xcode·simctl은 Runstir lease를 따르지 않는다. 실제 검증은 중앙 자원 lease도 필요하다.

## Simulator 생성과 복구

선택한 Xcode의 device type OS 범위와 실제 runtime identity를 사용한다.
생성 이름은 기존 iPhone selector가 읽을 수 있는 `iPhone … - Runstir - iOS …` 형식이다.
동일 이름의 기존 기기를 덮어쓰거나 삭제하지 않는다.
`simctl create`가 반환한 UDID와 실제 기기의 이름·type·runtime·`Shutdown` 상태를 대조한다.
생성 후 boot하지 않는다. 준비 완료와 앱 실행을 구분한다.

승인한 mutation 직전에 Runstir 소유 recovery journal을 원자적으로 기록한다.
journal은 `Library/Caches/dev.runstir/ios-preparation` 아래에 둔다.
journal을 runtime 설치 위치나 설치 성공 receipt라고 부르지 않는다.
실패·취소 뒤에는 bounded read로 실제 완료 자원을 관측한다.
관측할 수 없는 identity·state는 `unknown`이다. 상태 확인 없이 재설치·재생성하지 않는다.
확인한 완료 자원과 기존 자원은 보존한다. OS 작업의 원자적 취소나 rollback을 약속하지 않는다.
Xcode 설치·로그인·라이선스·관리자 권한은 수동 행동과 다시 확인으로 남긴다.
전역 Xcode 선택을 변경하거나 계정·비밀값을 수집하지 않는다.

## 검증 경계

provider·parser 검사는 `FakeProcessRunner`와 소유 임시 fixture를 사용한다.
공통 setup 연결 검사는 별도로 유지한다. provider 성공을 공통 연결 성공으로 표시하지 않는다.
실제 payload 다운로드·runtime 설치·Simulator 생성·VM 기동·GUI 실행은 아직 검증하지 않았다.
AC02·AC03·AC06의 실제 준비와 기존 자원 보존은 별도 실측을 요구한다.
정확한 runtime availability 관측은 다른 device의 전체 보존이나 앱 실행 성공을 입증하지 않는다.

공식 근거:

- [Apple 추가 Xcode components 설치](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components)
- [Apple runtime catalog](https://devimages-cdn.apple.com/downloads/xcode/simulators/index2.dvtdownloadableindex)
- [Apple Simulator 구성 생성](https://help.apple.com/xcode/mac/current/en.lproj/devf225e58da.html)

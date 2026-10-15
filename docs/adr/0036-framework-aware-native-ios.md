# ADR-0036: framework를 보존하는 프로젝트 선택과 native iOS 실행

날짜: 2026-10-15
상태: Accepted for implementation; broad final-head approval remains required
관련: #199, #210, #205, #211, ADR-0001, ADR-0002, ADR-0003, ADR-0004, ADR-0007

## 결정

`ProjectFramework`는 `react-native`, `flutter`, `native-ios`, `native-android`를 구분한다.
플랫폼은 기존 `ProjectPlatform`으로 유지한다.
`ProjectCandidate.framework`와 `ProjectAnchor.framework`는 같은 선택을 표현한다.
후속 Flutter·native Android 구현은 이 계약을 재사용한다.
이 변경은 두 후속 실행 기능을 구현하지 않는다.

native iOS는 앱 루트의 실제 Xcode 컨테이너를 후보로 노출한다.
`project.pbxproj` 또는 `contents.xcworkspacedata`가 있어야 후보가 된다.
복수 후보는 명시적인 `--app` 선택을 요구한다.
기존 RN 후보 id는 유지한다.
선택 복원은 `ProjectAnchor.detect(candidate:)`를 사용한다.
`iosDirectory`는 native iOS의 실제 앱 루트다.
RN·Flutter의 native host는 독립 후보로 중복 탐지하지 않는다.

native iOS는 선택 컨테이너의 Xcode 목록과 공유 `.xcscheme` 파일의 교집합만 사용한다.
workspace는 선언한 project의 공유 scheme도 포함한다.
native iOS 앱 target과 product는 공유 scheme의 `LaunchAction/BuildableProductRunnable`을 따른다.
build settings에 일치하는 앱이 없거나 여러 개면 실행하지 않는다.
공유 scheme이 여러 개면 기존 scheme 선택 규칙을 적용한다.
`xcodebuild -showBuildSettings -json`으로 앱 target, 실제 configuration,
`iphonesimulator` 플랫폼, deployment target을 측정한다.
실제 Debug가 없으면 다른 구성을 명시적으로 선택해야 한다.
Xcode가 Release로 대체한 결과를 Debug로 기록하지 않는다.
호환 Simulator 후보는 측정한 deployment target을 만족해야 한다.

기존 ProcessRunner, DoctorEngine, Stage, ResourceLeases, InstallRecord를 재사용한다.
native iOS는 Node·패키지 매니저·RN 의존성 설치·Metro를 실행하지 않는다.
Metro 포트도 점유하지 않는다.
build는 Simulator artifact만 만든다.
up만 선택한 기기에 설치하고 실행한다.
down은 해당 앱의 InstallRecord와 기존 소유권 검사를 사용한다.
기기를 종료하거나 앱을 삭제하지 않는다.

SPM 자동 갱신과 자동 resolution을 막는다.
준비된 잠금 의존성이 없으면 Xcode 오류와 로그를 보존한다.
CocoaPods 프로젝트는 준비된 workspace와 일치하는 lock/Manifest를 요구한다.
build와 up에서 native iOS 의존성을 설치하지 않는다.
준비와 필요한 서명은 프로젝트의 기존 절차로 안내한다.
Simulator build는 `CODE_SIGNING_ALLOWED=NO`를 명시한다.
실기기 서명·인증서·provisioning을 자동 처리하지 않는다.
Xcode 요구는 1.0 검증 기준인 27.0 미만으로 낮추지 않는다.
RN compatibility matrix를 native 프로젝트에 적용하지 않는다.

## 검증 경계

행동 검사는 공유 WorkflowExecution을 호출한다.
선택 오류, Debug 대체, 미확인 앱 target, 취소, 소유권 충돌,
build의 설치 부재, native down의 Metro 보존을 확인한다.
fixture 성공은 실제 Runstir 실행 성공이 아니다.
#214의 수동 baseline 성공도 #210 제품 실행의 증거가 아니다.
실제 실행과 GUI 조작의 증거는 별도로 기록한다.

# Flutter iOS 실행

Flutter iOS는 CLI와 GUI의 공통 `EnvironmentInspection`과 `WorkflowExecution`을 사용한다.
`setup`의 양플랫폼 준비 계획은 [ADR-0040](adr/0040-flutter-preparation.md)을 유지한다.
이 문서는 준비된 iOS host의 실행 경계를 설명한다.

## 입력

```sh
mobile doctor --project /path/to/app --platform ios --scheme Runner --configuration Debug --entrypoint lib/main.dart --json
mobile setup --project /path/to/app --entrypoint lib/main.dart --json
mobile build --project /path/to/app --platform ios --scheme Runner --configuration Debug --entrypoint lib/main.dart --json
mobile up --project /path/to/app --platform ios --device <udid> --scheme Runner --configuration Debug --entrypoint lib/main.dart --port 52123 --json
mobile down --project /path/to/app --platform ios --json
```

`--entrypoint`를 생략하면 `lib/main.dart`를 사용한다.
entrypoint는 선택한 Flutter 앱 안의 기존 Dart 파일이어야 한다.
실행 입력은 `Generated.xcconfig`와 Xcode의 실제 build settings에 일치해야 한다.
Runstir는 entrypoint를 바꾸려고 생성 설정이나 앱 소스를 수정하지 않는다.
scheme이 여러 개면 선택을 요구한다.
실제 `Debug`가 있을 때만 이를 기본 configuration으로 사용한다.
다른 configuration도 실제 Flutter build mode가 debug일 때만 사용한다.
Release·Profile이나 Xcode의 configuration 대체는 실행하지 않는다.

`--port`는 Flutter iOS `up`에만 적용한다.
1부터 65535까지의 정수를 받는다.
생략하면 현재 사용할 수 있는 loopback 포트를 선택한다.
기존 listener가 있으면 보존하고 중단한다.
명시한 포트가 이전 앱에서 사용 중이어도 먼저 `down`으로 종료해야 한다.
다른 workflow에 포트를 주면 전달을 지원하지 않는 이유를 표시하고 중단한다.

GUI의 Flutter entrypoint와 VM service port 입력도 같은 계약을 사용한다.
GUI의 환경 확인과 준비 계획에는 같은 entrypoint를 전달한다.
GUI의 환경 확인에는 선택한 scheme과 configuration도 전달한다.

## 준비와 빌드

공식 정식 arm64 Flutter SDK와 bundled Dart exact를 함께 확인한다.
#205의 명시 SDK 선택·공식 metadata·workspace resolver·plugin metadata 계약을 재사용한다.
앱 루트와 Dart resolver가 반환한 의존성 workspace 루트를 구분한다.
네이티브 host를 별도 앱 후보로 추가하지 않는다.
워크스페이스에서 실행할 앱 폴더를 연다.
앱 선언이 없는 Dart workspace root에서 하위 앱을 새로 탐색하지 않는다.

기존 snapshot·engine/Dart stamp·tools lock의 준비 상태를 확인한다.
부족한 SDK를 bootstrap하거나 upgrade하지 않는다.
기존 engine·앱·entrypoint와 맞는 generated native 입력을 요구한다.
Pods가 필요하면 기존 workspace와 일치하는 `Podfile.lock`·`Pods/Manifest.lock`을 요구한다.
build/up은 Dart 정렬과 `pod install`을 실행하지 않는다.
준비 부족은 승인한 setup 또는 수동 준비로 해결한다.
Flutter module의 `.ios` host를 app host로 자동 변환하지 않는다.

기존 iOS device·build·install·launch stage와 `ProcessRunner`를 사용한다.
build는 설치·실행하지 않는다.
up은 선택한 Simulator에만 설치하고 실행한다.
Simulator build는 `CODE_SIGNING_ALLOWED=NO`를 사용한다.
자동 Swift package resolution을 차단한다.
React Native 의존성 명령과 Metro는 실행하지 않는다.
실기기 서명·provisioning은 이 경로에 포함하지 않는다.

공식 `flutter build ios`와 `flutter run`의 프로젝트 migration 경로를 호출하지 않는다.
기존 host의 `xcodebuild`가 호출하는 Flutter assemble은 native child 경계 안에서 실행한다.
해당 child의 outbound IP 연결과 기존 source·lockfile·SDK 실행 payload 쓰기를 제한한다.
프로필은 작업 로그 디렉터리에만 저장한다.
호스트의 보안 설정을 변경하지 않는다.
필수 파일 쓰기가 거부되면 오류를 보존한다.
제한을 우회하거나 다른 SDK로 fallback하지 않는다.

workspace source·lockfile·symlink·mode와 선택 SDK fingerprint를 각 stage 전후에 확인한다.
기존 generated build 디렉터리는 source 검사에서 구분한다.
generated/cache 제외는 검증한 Dart package root의 정해진 상대 경로에만 적용한다.
그 경로도 symlink를 먼저 검사한다.
실제 directory일 때만 generated/cache 제외를 적용한다.
`.dart_tool`·`build`·`.mobile`·`node_modules`·`.build`·`.gradle`·`graft`와 `vendor/bundle`을 구분한다.
native host에서는 `ios/Pods`·`ios/vendor/bundle`·`ios/Flutter/ephemeral`·`android/.gradle`·`android/build`을 구분한다.
검증한 다른 package를 포함하는 경로는 이 제외를 적용하지 않는다.
`lib/build`·`assets/build`·`lib/vendor` 같은 source는 이름이 같아도 보호한다.
중첩 저장소를 포함한 `.git` metadata는 기존 개인정보 경계를 유지한다.
일반 source·lockfile symlink는 파일과 directory 모두 native build child 전에 중단한다.
대상 상태를 확인할 수 없거나 link가 깨졌어도 중단한다.
오류에는 source 상대 경로와 수동 준비 안내만 표시한다.
이 검사로 외부 대상의 내용·권한·hash를 새로 수집하지 않는다.
SDK directory alias는 Dart가 확인한 workspace package의 `.fvm/flutter_sdk` 경로만 기본으로 허용한다.
명시한 `FLUTTER_ROOT`·`PATH`가 workspace 안의 SDK alias를 선택하면 그 정확한 경로도 허용한다.
SDK alias 대상은 선택 SDK의 canonical root와 같아야 한다.
명시한 alias도 기존 #205의 generated input·effective Xcode 경로 검사를 통과해야 한다.
generated plugin alias는 선택 앱의 `ios/.symlinks/plugins/<name>` 경로만 허용한다.
plugin name과 canonical root는 같은 #205 검사가 확인한 iOS native plugin 결과를 사용한다.
새 metadata를 다시 읽어 alias 예외를 늘리지 않는다.
검증한 metadata bytes 또는 정상 부재를 guard 생성 전후와 stage에서 비교한다.
metadata만 바뀌어도 새 상태를 기준으로 받아들이지 않고 중단한다.
경로나 대상이 달라지면 중단한다.
`lib`·`assets`·`ios` 같은 일반 source directory alias는 수동 준비로 안내한다.
directory alias는 link 자체를 관측한다.
이 관측으로 외부 directory 전체의 내용 보존을 주장하지 않는다.
예상 밖 source 변경을 발견하면 다음 stage를 시작하지 않는다.
변경한 파일을 표시한다.
파일을 자동 복원하거나 SDK를 일괄 삭제하지 않는다.
이 검사는 전체 HOME·cache·SDK tree의 무변경을 입증하지 않는다.

## 개발 연결과 종료

작업 폴더·선택 기기·VM service port의 기존 자원 lease를 확보한다.
launch 직전에 포트 listener를 다시 확인한다.
Simulator 앱 인자로 정확한 `--vm-service-port`를 전달한다.
이번 launch의 새 출력 파일에서 loopback 서비스 URI를 읽는다.
선택한 포트와 다른 URI는 거부한다.
그 URI의 `getVM` 응답이 Dart VM을 식별해야 개발 연결을 성공으로 보고한다.
앱 PID만으로 개발 연결 성공을 주장하지 않는다.
`operation.developmentServiceURI`에 관측한 URI를 반환한다.
CLI와 GUI는 같은 결과를 표시한다.
이 URI의 인증 경로와 원본 로그를 공개 증거에 그대로 게시하지 않는다.

down은 기존 설치 기록과 기기 소유권 검사를 사용한다.
기록한 앱만 terminate한다.
앱 삭제·Simulator 종료·SDK 제거·Metro 종료를 수행하지 않는다.
앱 종료로 해당 VM service도 종료한다.
SDK가 없어도 기록한 앱의 종료를 시도한다.
실패와 취소 후 설치한 앱이 남을 수 있다.
남은 자원과 후속 down 안내를 결과에 유지한다.

## 검증 범위

| 기준 | 자동 검증 | 별도 실제 검증 |
| --- | --- | --- |
| #199 AC01 | 공통 후보·entrypoint·effective debug·선택 부족·잘못된 선택 | CLI·GUI의 실제 후보와 선택 화면 |
| #199 AC04 | 공통 doctor/build/up/down, process 실패·취소, source/lock 보존, lease·URI·getVM | 고정 tuple의 실제 build·설치·첫 화면·개발 연결·종료 |

`FlutterIOSWorkflowTests`는 공통 interface를 실행한다.
`FlutterIOSRuntimeTests`는 소유 임시 child에서 파일 보호와 취소를 확인한다.
임시 child는 Flutter나 Xcode 앱을 빌드하지 않는다.
fixture 성공은 실제 Flutter 앱 실행 성공이 아니다.
#213 native baseline과 #205 SDK 준비 성공도 #208 제품 실행 성공으로 승계하지 않는다.
실제 실행은 별도 fresh source·SDK/cache·Simulator·포트·제품 SHA를 고정한 뒤 수행한다.
Runstir Developer ID 서명·공증·배포는 개발과 테스트를 마친 뒤의 별도 단계다.

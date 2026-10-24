# Flutter iOS 실행

Flutter iOS는 CLI와 GUI의 공통 `EnvironmentInspection`과 `WorkflowExecution`을 사용한다.
`setup`의 양플랫폼 준비 계획은 [ADR-0040](adr/0040-flutter-preparation.md)을 유지한다.
이 문서는 준비된 iOS host의 실행 경계를 설명한다.

## 입력

```sh
mobile doctor --project /path/to/app --platform ios --scheme Runner --configuration Debug --entrypoint lib/main.dart --json
mobile setup --project /path/to/app --entrypoint lib/main.dart --json
mobile build --project /path/to/app --platform ios --device <udid> --scheme Runner --configuration Debug --entrypoint lib/main.dart --json
mobile up --project /path/to/app --platform ios --device <udid> --scheme Runner --configuration Debug --entrypoint lib/main.dart --port 52123 --json
mobile down --project /path/to/app --platform ios --json
```

`--entrypoint`를 생략하면 `lib/main.dart`를 사용한다.
entrypoint는 선택한 Flutter 앱 안의 기존 Dart 파일이어야 한다.
직접 준비한 의존성을 실행할 때는 `build/up --prepared-dependencies` 또는 GUI의 같은 선택을 사용한다.
[ADR-0048](adr/0048-explicit-manually-prepared-flutter-dependencies.md)에 따라 lock 정렬과 plugin resolver 정합성 판정을 생략한다.
기본값은 꺼짐이며 아래 SDK·경로·생성 입력·source 보호 검사는 유지한다. doctor와 setup은 이 선택을 사용하지 않는다.
실행 입력은 `Generated.xcconfig`와 Xcode의 실제 build settings에 일치해야 한다.
Runstir는 entrypoint를 바꾸려고 생성 설정이나 앱 소스를 수정하지 않는다.
scheme이 여러 개면 선택을 요구한다.
실제 `Debug`가 있을 때만 이를 기본 configuration으로 사용한다.
다른 configuration도 실제 Flutter build mode가 debug일 때만 사용한다.
Release·Profile이나 Xcode의 configuration 대체는 실행하지 않는다.

`--port`는 Flutter iOS와 Flutter Android의 `up`에 적용한다.
1부터 65535까지의 정수를 받는다.
생략하면 현재 사용할 수 있는 loopback 포트를 선택한다.
기존 listener가 있으면 보존하고 중단한다.
다른 작업이 같은 포트의 공통 lease를 보유해도 중단한다.
명시한 포트가 이전 앱에서 사용 중이어도 먼저 `down`으로 종료해야 한다.
`build`·`down`이나 다른 framework에 포트를 주면 전달을 지원하지 않는 이유를 표시하고 중단한다.

GUI의 Flutter entrypoint와 VM service port 입력도 같은 계약을 사용한다.
GUI의 환경 확인과 준비 계획에는 같은 entrypoint를 전달한다.
GUI의 환경 확인에는 선택한 scheme과 configuration도 전달한다.
GUI의 iOS build에는 선택한 Simulator identity도 전달한다.

Flutter workspace의 `down`도 현재 선언으로 확인한 workspace 폴더를 잠근다.
이 확인에는 SDK나 Dart 실행을 사용하지 않는다.
선택한 앱의 포함 관계나 workspace root를 확인하지 못하면 기존 자원을 보존하고 중단한다.
복잡한 workspace 패턴은 SDK 없는 정리에서 지원하지 않으므로 선언을 확인해야 한다.

Flutter build와 up은 사용 가능한 Simulator identity를 확인한다.
선택 가능한 Simulator가 하나면 이를 선택한다.
여러 개면 명시적 선택을 요구한다.
명시한 identity가 없거나 runtime 하한에 맞지 않으면 generic destination으로 대체하지 않는다.

준비된 Flutter의 `ios.flutter.project` 검사는 선택한 scheme의 실제 deployment target을 사용한다.
같은 검사에서 기존 Simulator runtime의 availability와 버전 하한을 확인한다.
이 분기에서는 정적 요구값의 중복 `simulator.runtime` 행을 표시하지 않는다.
scheme 또는 configuration 선택이 부족하면 경고를 유지하고 build settings와 runtime 하한 판정을 보류한다.
CoreSimulator 응답을 확인한 뒤 runtime 관측이 잘못되면 `unknown`을 유지한다.
SDK가 미확정이면 기존 정적 runtime 검사를 유지한다.
native iOS와 React Native의 기존 runtime 검사 계약은 바꾸지 않는다.

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
build는 선택한 concrete Simulator destination과 `ONLY_ACTIVE_ARCH=YES`를 사용한다.
build와 관련 settings 조회는 같은 canonical input의 `RunLogs/DerivedData`를 사용한다.
산출물은 기존 로그 폴더 아래 `folder-<volume>-<file>/DerivedData`로 분리한다.
현재 input의 폴더 lease identity를 읽지 못하면 도구 실행 전에 중단한다.
기존 로그 digest가 충돌해도 서로 다른 실제 input은 같은 산출물을 쓰지 않는다.
독립 입력은 output 경로를 분리한다. 기존 output 부모나 output이 symlink·일반 파일이면 중단한다.
선택용 settings 조회가 folder lease보다 먼저 실행되는 기존 순서는 유지한다.
외부 경로 교체의 TOCTOU·프로젝트 output override·전체 Xcode cache 격리는 이 검사로 입증하지 않는다.
아키텍처 이름을 고정하지 않는다.
build는 Simulator 부팅·앱 설치·실행 명령을 보내지 않는다.
React Native와 native iOS의 명시적 device build에도 이 비부팅 계약을 적용한다.
이 read-only destination 선택에는 앱 실행용 device lease를 사용하지 않는다.
React Native와 native iOS의 device 미지정 build는 기존 generic destination을 유지한다.
Xcode 자체가 Simulator 상태를 바꾸는지는 실제 검증에서 별도로 측정한다.
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
기본 실행은 일반 source·lockfile symlink를 파일과 directory 모두 native build child 전에 중단한다.
명시적 `--prepared-dependencies`에서는 Git index mode `120000`·stage `0`의 내부 source 파일 링크만 예외로 검증한다.
상대 leaf 링크와 직접 일반 파일 대상이 모두 workspace의 보호 source에 있어야 한다.
링크·대상·부모 identity와 bytes/type/mode를 고정하고 native child 전후에 재검사한다.
대상은 workspace descriptor부터 부모별 `openat/O_NOFOLLOW`로 읽는다.
sandbox는 링크·대상 쓰기와 양쪽 부모 교체를 거부한다. Git 추적 변경도 중단한다.
lock·manifest·metadata·entrypoint·SDK·tool·generated/cache 경로 및 외부·절대·다중·directory 링크는 예외가 아니다.
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
앱 stdout/stderr를 별도 원본 로그 파일로 저장하지 않는다.
같은 Simulator의 bounded unified log history에서 loopback 서비스 URI를 읽는다.
조회는 `log show --last 5m --style json --info --debug`를 사용한다.
`processIdentifier` predicate를 정확한 앱 PID와 서비스 marker에 묶는다.
현재 설치된 앱의 Info.plist·bundle ID·실행 파일 이름과 regular file 상태를 확인한다.
현재 설치된 Flutter framework의 regular file 상태도 확인한다.
두 실행 파일의 canonical 경로는 현재 앱 bundle 안에 있어야 한다.
`/usr/bin/xcrun dwarfdump --uuid`로 두 실행 파일의 Mach-O UUID를 읽는다.
명령에는 현재 설치된 파일 경로를 각각 하나의 인자로 전달한다.
출력의 UUID·architecture·파일 경로를 엄격하게 확인한다.
각 실행 파일은 최대 16개 architecture UUID를 허용한다.
손상·중복·실패·상한 초과는 중단한다.
반환 JSON의 `processID`·`processImageUUID`·`senderImageUUID`를 현재 UUID와 다시 확인한다.
UUID 일치는 전체 파일 hash나 코드 서명 검증을 뜻하지 않는다.
앱 재설치 뒤 unified log의 image path가 이전 설치 경로와 일치한 실제 관측이 있었다.
같은 기록의 UUID는 현재 설치 파일의 UUID와 일치했다.
OS의 image UUID와 경로 캐시가 원인이라는 설명은 추론이다.
과거 설치 경로를 허용 목록에 추가하지 않는다.
unified log의 image path를 현재 설치 경로의 증거로 사용하지 않는다.
반환 timestamp는 이번 launch 시작 이후와 조회 완료 이전이어야 한다.
설치 경로와 실행 파일 이름의 control 문자는 거부한다.
predicate에 파일 경로를 넣지 않는다.
명령 인자는 shell을 거치지 않는다.
각 조회는 기존 ProcessRunner로 실행한다.
조회 timeout은 남은 readiness 시간과 5초 중 작은 값이다.
readiness 관측은 기본 120초를 사용한다.
조회 사이에는 최대 1초를 기다린다.
새 background reader를 만들지 않는다.
출력은 1 MiB·1024개 기록으로 제한한다.
개별 메시지는 16 KiB로 제한한다.
손상된 JSON·조회 실패·timeout은 개발 연결 성공으로 처리하지 않는다.
남은 readiness 시간의 마지막 조회가 timeout이면 readiness 만료로 보고한다.
deadline 이전의 조회 timeout은 도구 실패로 유지한다.
조회 도구 실패는 고정 분류 `query-timeout`·`query-spawn-failed`·`query-failed`를 표시한다.
history 결과는 `history-nonzero-status`·`history-output-limit`·`history-invalid-json`·`history-row-limit`를 구분한다.
이 분류에 원본 명령·출력·URI를 포함하지 않는다.
`getVM` 명령의 인자와 내부 오류 내용도 runner의 일반 로그에서 가린다.
새 분류로 과거 실행의 미수집 원인을 소급 확정하지 않는다.
취소는 유한한 조회 child가 종료한 뒤 반환한다.
선택한 포트와 다른 URI는 거부한다.
그 URI의 `getVM` 응답이 Dart VM을 식별해야 개발 연결을 성공으로 보고한다.
URI 확인 전과 `getVM` 응답 후에 같은 bundle의 live PID를 다시 확인한다.
이 관측은 OS process birth identity를 입증하지 않는다.
같은 실행 파일의 PID가 launch 시간 안에서 재사용되는 경우를 완전히 구분하지 못한다.
unified log가 marker를 보존하지 않으면 관측은 실패할 수 있다.
임의의 네트워크 URI 탐색으로 대체하지 않는다.
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

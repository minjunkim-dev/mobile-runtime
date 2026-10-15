# LocalSend iOS의 검증 입력 결정안

상태: **선택 A 승인·입력 고정·실제 양플랫폼 baseline PASS**.
사용자는 별도 검증 clone의 세 파일 수정을 승인했다.
원본 source와 `Podfile.lock`은 그대로 보존한다.
새 source는 `61145cf100522363e9658af97137097551c64832`다.
새 tree는 `2346d8051c3f556fa545e9c48aa5c1bc7fc2446b`다.

## 현재 입력과 실제 실패

- source: `c1ce322fb3acf08e44f329b8b7208b8b0d91e244`.
- 앱 루트: `app/`.
- 의존성 workspace: 저장소 root.
- entrypoint: `lib/main.dart`.
- Flutter: `3.41.9`, source `00b0c91f06209d9e4a41f71b7a512d6eb3b9c694`.
- 원본 `pubspec.lock` SHA-256: `d14333a18b86726a4d8cc792bd3d65482d8e55e53f5895a3bd21d0cdcf7f5b3a`.
- 원본 `app/ios/Podfile.lock` SHA-256: `b26db1286dbc37f31a03a1375cbe8d3ebd80f1ed84005e9df888ca9060ad1136`.
- CocoaPods: `1.16.2`. 별도 gem·cache 경로를 사용했다.
- Xcode: `27.0 (27A266a)`. 기존 iOS 27 runtime만 사용한다.

`flutter pub get --enforce-lockfile`은 성공했다.
설치한 Flutter 도구는 `pod install --verbose`를 호출한다.
이 기본 호출에는 frozen 옵션이 없다.
작업 전용 `pod` wrapper로 `--deployment`를 강제했다.
SDK와 gem source는 수정하지 않았다.

다음 실제 명령은 `1`로 종료했다.

```text
flutter build ios --config-only --simulator --debug --no-pub --no-codesign --target lib/main.dart
```

실패 로그는 증거 root의 `logs/localsend-ios-config.log`다.
실제 `pod` 인수는 `logs/pod-invocations.args`에 있다.

```text
[!] There were changes to the podfile in deployment mode:
A open_file_ios
A system_date_time_format
R open_filex
```

이 결과는 frozen Pods 준비 실패다.
LocalSend native 앱의 build·install·launch 실패로 확장하지 않는다.
원본 `Podfile.lock`의 `open_filex` 선언과 고정 Dart 의존성에서 생성한 plugin 입력이 맞지 않는다.
준비 실패 뒤 원본 tracked raw byte 1,030개와 index는 유지됐다.
숨김 flag도 없었다.

별도 정적 위험도 있다.
`app/ios/Podfile` 2행은 `platform :ios, '13.0'`이다.
`app/ios/Runner.xcodeproj/project.pbxproj` 509·700·749행의 Runner target은 `13.0`이다.
561·600·636행의 ShareExtension target은 `14.0`이다.
현재 Xcode Simulator SDK의 지원 범위는 `15.0`~`27.0.x`다.
이 target 위험을 LocalSend에서 실제 재현한 것처럼 기록하지 않는다.

## 선택 A: 별도 prepared input 허용

원본과 별도 경로의 clone을 사용한다.
새 clone의 시작 source는 위 LocalSend SHA다.
허용할 수정 범위는 다음 세 파일로 제한한다.

| 파일 | 제안 입력 | 이유 |
| --- | --- | --- |
| `app/ios/Podfile` | platform을 `15.0`으로 명시한다. 필요하면 Simulator Debug Pods target `15.0`을 명시하는 `post_install` 입력을 별도로 심사한다. | Xcode 27의 지원 범위와 native 의존성 입력을 맞춘다. |
| `app/ios/Runner.xcodeproj/project.pbxproj` | 위 여섯 target 값을 `15.0`으로 명시한다. | Runner와 ShareExtension 입력을 함께 고정한다. |
| `app/ios/Podfile.lock` | 고정 Dart lock의 실제 plugin 목록으로 새 lock을 만든다. 모든 resolved Pods 버전·source·checksum과 원본 대비 diff를 보존한다. | 현재 frozen lock의 plugin 집합 모순을 해결한다. |

`pubspec.yaml`, `pubspec.lock`, Dart source, Rust source와 Android 파일은 바꾸지 않는다.
원본 lock을 삭제하거나 자동 복원하지 않는다.
새 clone에 남긴 원본 byte와 변경 diff를 함께 보존한다.
새 source SHA는 위 `61145cf…`로 고정했다.
원본 대비 변경 파일은 위 세 파일뿐이다.
Podfile에는 Debug·`sdk=iphonesimulator*` 조건의 Pods target `15.0`을 명시했다.
원본 Dart lock은 그대로다.
새 `Podfile.lock` SHA-256은 `5595ddad3deb164f454565e62ef48b3fae1e4d0b951116781f0246abe810825f`다.
resolved Pods 38개와 local podspec 25개의 source·version·checksum을 보존했다.
`SPEC CHECKSUMS`는 CocoaPods spec의 SHA-1이다.
local podspec JSON의 raw SHA-256도 따로 기록했다.
이를 upstream 다운로드 archive의 checksum으로 부르지 않는다.
고정 뒤 `pod install --deployment`는 `0`으로 종료했다.
예상 명령을 성공 결과로 세지 않는다.

승인 뒤 다음 절차를 수행했다.

1. 새 경로에 고정 source를 clone한다.
2. 원본 tracked raw byte·mode·index·lock SHA-256을 기록한다.
3. 세 파일의 승인 범위만 변경한다.
4. 작업 전용 CocoaPods로 한 번의 명시적 lock resolution을 수행한다.
5. 전체 resolved Pods·checksum·diff를 검토한다.
6. 새 검증 입력을 commit하고 source·tree·lock identity를 고정한다.
7. 새 cache에서 frozen Dart·Pods 준비를 재검증한다.
8. 새 source의 iOS와 Android build·install·launch·첫 화면을 재검증한다.
9. 원본 보존과 실행 source의 불변성을 따로 감사한다.
10. 별도 fresh clone에 source와 lock을 인계한다.

이는 검증 입력에 대한 한정 승인이다.
Runstir의 자동 migration이나 범용 예외 정책으로 일반화하지 않는다.
#199의 최소 공식 scaffold 교체 승인은 실제 OSS의 native lock 재작성까지 포함하지 않는다.
따라서 별도 사용자 결정을 받았다.
이 승인은 해당 세 파일의 별도 검증 입력에 한정된다.

## 선택 B: 채택하지 않은 원본 무수정 대안

현재 LocalSend SHA는 실패 표본으로 보존한다.
실제 OSS 역할의 교체 후보와 정확한 source SHA를 별도로 결정한다.
현재 대체 OSS source는 **unknown**이다.
최신 버전을 임의로 고르지 않는다.
후보의 license·양플랫폼 source·SDK·lock·native 최소 버전을 먼저 검사한다.
교체를 승인한 뒤 동일한 네 번의 실제 실행과 fresh clone 절차를 수행한다.

## 현재 경계

원본 LocalSend iOS의 target override·Podlock 재생성·자동 migration은 수행하지 않는다.
원본 LocalSend Android의 실제 첫 화면도 별도로 확인했다.
prepared source `61145cf…`의 실제 양플랫폼 build·install·launch·첫 화면을 확인했다.
별도 fresh clone의 frozen Dart·Pods와 source 불변성도 확인했다.
[최종 실행 결과](README.md#prepared-localsend의-실제-ios-baseline)를 참조한다.
후속 Runstir CLI·GUI와 제품 전체 AC05·AC06는 아직 검증하지 않았다.

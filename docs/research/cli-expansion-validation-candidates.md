# 초기 검증 조합과 앱 표본 후보

조사일: 2026-10-09, Asia/Seoul. 티켓: [초기 검증 조합과 앱 표본 후보 고정](https://github.com/minjunkim-dev/mobile-runtime/issues/194).
정책 입력: [지원 경계 결정](https://github.com/minjunkim-dev/mobile-runtime/issues/183#issuecomment-6078466723), [고정 계약](https://github.com/minjunkim-dev/mobile-runtime/blob/423f4ca17907fe083f7dd29f9adbdfdf900d22e0/docs/cli-expansion-support-contract.md).

이 문서는 **조사 후보**를 고정한다. `known-good`, `validated`, 정식 지원 조합을 선언하지 않는다. 설치·SDK 다운로드·기기 생성·빌드·앱 실행·VM 작업을 수행하지 않았다. 공개 선언과 공식 배포 메타데이터만 읽었다. 표본 저장소의 SHA는 조회한 commit이다. 별도 표시가 없으면 앱 정식 release tag가 아니다. 도구 정식 채널과 앱 source commit을 구분한다.

## 공통 도구 후보와 공식 근거

| 항목 | 고정 입력 또는 확인 결과 | 의미와 한계 |
| --- | --- | --- |
| 호스트 | macOS Apple Silicon. 보존한 macOS 27 기준 환경부터 시작 | 실제 OS build와 hardware identity는 baseline에서 기록한다. 이 조사가 macOS 하한을 확정하지 않는다. |
| Xcode | `27.0`, 기존 조사에서 관찰한 build `27A266a` | [Apple 지원표](https://developer.apple.com/xcode/system-requirements), [기존 공식 자료 확인](https://github.com/minjunkim-dev/mobile-runtime/blob/423f4ca17907fe083f7dd29f9adbdfdf900d22e0/docs/cli-expansion-support-contract.md). `27.1 RC`는 정식 후보에서 제외한다. build/runtime를 실행 환경에서 다시 확인한다. |
| Flutter | LocalSend 선언 우선 후보 `3.41.9`, SDK tag SHA `00b0c91f06209d9e4a41f71b7a512d6eb3b9c694` | [공식 tag source](https://github.com/flutter/flutter/tree/00b0c91f06209d9e4a41f71b7a512d6eb3b9c694). 최신 계열 후보는 공식 문서의 `3.47`. `3.47.2` tag SHA `d3b14c876900e553bc736ca19295fc09e3853e8e`도 존재한다. [공식 archive](https://docs.flutter.dev/install/archive), [tag source](https://github.com/flutter/flutter/tree/d3b14c876900e553bc736ca19295fc09e3853e8e). archive의 동적 표는 patch 목록을 반환하지 않았고 배포 JSON 조회는 404였다. 따라서 **최신 정식 patch/arm64 bundle checksum/Dart exact version은 unknown**이다. tag 존재만으로 최신 bundle 배포를 보증하지 않는다. |
| React Native | 최소 표본 `0.87.1`, 실제 앱 `0.85.3` | [공식 versions](https://reactnative.dev/versions)는 최신 정식 계열 `0.87`을 표시한다. template release `0.87.2`의 manifest는 RN `0.87.1`이다. template 버전과 framework 버전은 다르다. 아래 고정 source를 따른다. template `main`의 `nightly`와 `0.88` RC는 제외한다. |
| Node | 설치 후보 `22.23.3` darwin-arm64 | [공식 SHASUMS](https://nodejs.org/dist/latest-v22.x/SHASUMS256.txt)에서 `node-v22.23.3-darwin-arm64.tar.gz`를 확인했다. SHA256 `23b25245dcfb9af7262f8ff142e9e2e0af025368117329e7a7458a51e5922f53`. RN 표본의 `>=22.11.0`은 범위다. 실제 다운로드 검증은 하지 않았다. [고정 배포 경로](https://nodejs.org/dist/v22.23.3/). |
| JDK | 설치 후보 Temurin `17.0.20.1+1` | [공급자 정식 release](https://github.com/adoptium/temurin17-binaries/releases/tag/jdk-17.0.20.1%2B1)는 `prerelease=false`, 발표일 `2026-08-19`였다. arm64 asset·checksum·설치 경로는 baseline 전에 추가로 잠근다. Java source compatibility 값과 Gradle 실행 JDK를 구분한다. |
| Android command-line tools | revision `23.0`, `channel-0` | [Google repository metadata](https://dl.google.com/android/repository/repository2-3.xml)의 `cmdline-tools;latest`. `latest` 별칭만 보존하지 말고 실제 package revision과 archive checksum을 추가로 기록한다. |
| Android platform-tools | `37.0.1`, `channel-0` | 같은 공식 metadata에서 확인했다. 다운로드·설치는 하지 않았다. |
| Android Emulator | `37.2.12`, `channel-0` | 같은 metadata에서 정식 후보를 확인했다. `37.3.3`은 `channel-2`라 제외했다. 실제 Mac 가속 확인이 필요하다. [공식 가속 안내](https://developer.android.com/studio/run/emulator-acceleration). |
| Android system image | `system-images;android-36;google_apis;arm64-v8a`, revision `7`, `channel-0` | [Google system-image metadata](https://dl.google.com/android/repository/sys-img/google_apis/sys-img2-3.xml). 여섯 표본 중 Android 경로의 공통 runtime 후보다. compile/target SDK와 실행 runtime은 다르다. device profile·AVD identity·archive checksum은 unknown이다. API 37 arm64 동일 package는 이번 응답에서 확인하지 못했다. |
| AGP/Gradle | 각 표본 선언을 유지한다 | 최신 공식 AGP 문서는 `9.4.0`, Gradle 최소 `9.6.0`, JDK `17`, Build Tools `36.0.0`, 최대 API `37`을 표시한다. [공식 compatibility](https://developer.android.com/build/releases/agp-9-4-0-release-notes). 이것을 다른 AGP 조합의 근거로 대체하지 않는다. 표본의 older AGP별 공식 compatibility 재확인이 남았다. |
| Ruby/CocoaPods | BlueWallet: Ruby `3.4.11p137`, CocoaPods `1.17.0`, xcodeproj `1.28.1`, Bundler `2.6.9` | [고정 Gemfile.lock][blue-gems]. 다른 표본에 이 lock을 복사하지 않는다. RN 최소 표본은 범위만 선언하고 다른 xcodeproj 상한을 둔다. 해당 해석 결과는 unknown이다. |

`channel-0`는 조회한 Google repository의 stable 채널이다. package source의 선언 값과 배포 확인 값을 구분했다. SDK platform/build-tools/NDK archive checksum은 이번에 고정하지 않았다. 선언한 숫자가 있다는 이유로 모든 artifact의 배포·다운로드 가능성을 검증했다고 주장하지 않는다.

## 여섯 조합에 배정한 source 후보

| 조합 | 최소 역할 표본 | 실제 OSS 앱 | 실행 입력 |
| --- | --- | --- | --- |
| 네이티브 iOS | Apple Food Truck의 단순 target, `3954a769e99f3cc53297d94f2b960ceb2665b3d6` | NetNewsWire, `aea7795bcc0698ced6f28eba53da886eb6217e64` | 각각 root의 Xcode project, `Food Truck` / `NetNewsWire-iOS`, `Debug`, iOS Simulator |
| 네이티브 Android | Android architecture-samples To-do, `ee66e1526b84c026615df032c705842b7d2a521f` | Now in Android, `a49ed253d75e61a2b6ab80a8da677b57437b08eb` | 각각 root, `:app`, `debug` / `demoDebug`, ARM64 Emulator |
| Flutter iOS | Flutter samples `platform_design`, `5541c59ab8e9d7e74c1a35ef22bd43a487fc596c` | LocalSend, `c1ce322fb3acf08e44f329b8b7208b8b0d91e244` | app root `platform_design/` / `app/`, `lib/main.dart`, `Runner`, `Debug`, iOS Simulator |
| Flutter Android | 같은 platform_design SHA | 같은 LocalSend SHA | 같은 app root/entrypoint, `:app`, `debug`, ARM64 Emulator |
| React Native iOS | community template tag `0.87.2`, SHA `bf0ef330c39d85c3f5bab248b83c7eedbce943da` | BlueWallet, `69adb1555038c8b2385952edd0404d2e1ecd7ca7` | 최소 source root `template/`, scheme `HelloWorld`; 실제 앱 root `.`, `BlueWallet`; `Debug`, iOS Simulator |
| React Native Android | 같은 community template SHA | 같은 BlueWallet SHA | 최소 source root `template/`; 실제 앱 root `.`; `:app`, `debug`, ARM64 Emulator |

최소 역할 표본은 기능과 서비스 요구를 줄인 비교 표본이다. Food Truck·To-do·platform_design은 단일 화면 hello-world보다 크다. 따라서 복잡도 때문에 진단이 불명확하면 공식 scaffold로 교체할 수 있다. 그때 생성 source·generator 버전·SHA를 다시 잠근다. 이번에 생성한 앱은 없다. 표본 이름은 출시 정책이 아니다.

RN template은 source 입력을 고정했다. CLI generator 치환·lockfile 생성 뒤의 **실행 앱 SHA는 아직 unknown**이다. `template/` 원본을 바로 standalone known-good 앱으로 세지 않는다. 이 값을 후속 baseline 전 잠가야 한다.

## 표본별 선언과 준비 제한

### 네이티브 iOS

- [Food Truck README][food-readme]는 단순 `Food Truck` target이 Simulator에서 실행된다고 설명한다. 전체 `Food Truck All` target에는 passkey/domain/WeatherKit 설정이 있다. 단순 target을 선택한다. README의 Xcode `14.3 or later`는 `27.0` 실제 호환성 증거가 아니다. [scheme][food-scheme]와 project가 root에 있다. account·device signing은 Simulator baseline의 필수 여부를 별도로 확인한다. private service 값을 first-screen 입력으로 사용하지 않는 경로를 고른다.
- [NetNewsWire README][nnw-readme]는 유료 개발자 계정 없이 build/test할 수 있다고 설명한다. private API keys가 없어 일부 기능을 비활성화하는 개발 build를 제공한다. repo 밖 `SharedXcodeSettings/DeveloperSettings.xcconfig` 또는 제공 `setup.sh`로 설정하는 방식이다. [공식 repo의 no-signing config][nnw-no-sign]도 있다. 앱 root `.`, project `NetNewsWire.xcodeproj`, [scheme `NetNewsWire-iOS`][nnw-scheme]를 고정한다. [project config][nnw-config]는 iOS deployment target `17.0`, Swift `6.2`를 선언한다. 개발 config의 안전한 내용·실제 resolved bundle ID·첫 화면과 네트워크 비필수 여부는 unknown이다. 개인 Team ID나 비밀값을 증거에 기록하지 않는다.
- 대안으로 조사한 [IceCubesApp SHA](https://github.com/Dimillian/IceCubesApp/tree/2ad6e689125801abeb7e356360785c08a4864982)는 README에서 `.xcconfig` 복사와 `DEVELOPMENT_TEAM`/`BUNDLE_ID_PREFIX` 입력을 요구했다. 설정 요구를 줄이기 위해 NetNewsWire를 우선 후보로 남겼다. IceCubes의 Xcode 27 성공을 주장하지 않는다.

### 네이티브 Android

- To-do root의 [version catalog][todo-versions]는 AGP `8.7.3`, Kotlin `2.1.10`, compile/target SDK `35`, min SDK `21`을 선언한다. [wrapper][todo-wrapper]는 Gradle `8.11.1`이다. [app module][todo-app]은 application ID `com.example.android.architecture.blueprints.main`, Java/Kotlin compile target `17`을 선언한다. 별도 flavor 선언을 확인하지 않았다. `debug`를 후보로 둔다. 비밀값 필수 선언은 읽은 README/app 설정에서 확인하지 못했다. merged launcher activity와 dependency resolution은 unknown이다.
- Now in Android [version catalog][nia-versions]의 AGP는 `9.3.2`, Kotlin은 `2.3.0`이다. [wrapper][nia-wrapper]는 Gradle `9.7.1`이다. [Kotlin convention][nia-kotlin]은 compile SDK `36`, min SDK `23`, Java source/target `11`을 둔다. [application convention][nia-app-convention]은 target SDK `36`을 둔다. Java compile target `11`을 실행 JDK `11` 요구로 해석하지 않는다. [app][nia-app]의 demo 경로를 사용해 backend 설정을 줄인다. `demoDebug`의 최종 application ID/launcher와 demo 데이터만으로 first-screen 도달 가능성은 실제 baseline에서 확인한다. exact 실행 JDK/자동 toolchain provisioning 요구도 unknown이다.

### Flutter

- [platform_design pubspec][flutter-min-pub]의 Dart 범위는 `^3.9.0-0`이다. exact Flutter SDK pin은 없다. 이는 Flutter prerelease 사용 의무가 아니다. [Android settings][flutter-min-settings]는 AGP `7.3.0`, [wrapper][flutter-min-wrapper]는 Gradle `7.5`다. 이 오래된 host 설정과 후보 Flutter `3.41.9` 또는 `3.47.2`의 **tracked 파일 무변경 호환성은 unknown**이다. migration이 필요하면 automatic setup에서 멈추는 준비 계약을 적용한다. [README][flutter-min-readme]의 공개 sample 화면과 root를 입력으로 사용한다. Dart entrypoint는 `platform_design/lib/main.dart`다.
- LocalSend [`.fvmrc`][local-fvm]는 Flutter `3.41.9`를 고정한다. [app pubspec][local-pub]의 Flutter `^3.41.0`/Dart `^3.11.0`은 범위다. [root workspace][local-workspace]는 `app`과 내부 package들을 연결한다. app root와 dependency workspace root를 구분한다. [README][local-readme]는 Flutter와 Rust 설치를 요구한다. [Rust toolchain][local-rust]은 `1.97.1`을 고정한다. 이것은 표본 준비 요구다. Runstir가 임의 Rust 도구 설치를 지원한다는 새 정책은 아니다.
- LocalSend [Android settings][local-settings]는 AGP `8.12.1`, Kotlin `2.2.0`, [wrapper][local-wrapper]는 Gradle `8.13`이다. [app module][local-app]은 compile SDK `36`, target SDK `37`, Java target `17`, application ID `org.localsend.localsend_app`, Debug suffix `.debug`를 둔다. NDK/min SDK는 Flutter 제공값 참조이므로 exact resolved 값은 unknown이다. release keystore와 debug 설치를 구분한다. Rust iOS Simulator target 준비·Flutter native plugin dependency·Pods/SwiftPM 해석·권한 전후 첫 화면은 unknown이다. latest Flutter로 임의 교체하지 않는다.

### React Native

- [최소 template manifest][rn-min-package]는 RN `0.87.1`, Node `>=22.11.0`이다. [Gemfile][rn-min-gems]은 Ruby `>=2.6.10`, CocoaPods `>=1.13`에서 `1.15.0/1.15.1` 제외, xcodeproj `<1.26.0`을 선언한다. [Android build][rn-min-build]는 Build Tools `37.0.0`, compile SDK `37`, target SDK `36`, min SDK `24`, NDK `27.1.12297006`, Kotlin `2.2.0`이다. [wrapper][rn-min-wrapper]는 Gradle `9.4.1`이다. AGP exact version은 이 build 파일에 없고 RN plugin 해석이 필요하다. 오래된 xcodeproj 상한과 Xcode 27 project object 지원 여부는 **unknown**이다. baseline에서 source/Gemfile 수정이 필요하면 실패를 남기고 후보를 교체한다. nightly template로 우회하지 않는다.
- BlueWallet [manifest][blue-package]는 RN `0.85.3`, Node `>=22.11.0`이다. [Gemfile.lock][blue-gems]가 위 Ruby/Pods 값을 고정한다. [Android build][blue-build]는 compile/target SDK `36`, Build Tools `36.0.0`, min SDK `24`, NDK `28.2.13676358`, Kotlin `2.1.20`이다. [wrapper][blue-wrapper]는 Gradle `9.3.1`이다. `postinstall`은 release notes/branch 정보 생성과 patches를 수행한다. **tracked 파일 변경 위험**을 baseline 전에 확인한다. read-only 조사로 해당 script 실행 결과를 보증하지 않는다. `index.js` 및 native launcher/product는 baseline에서 확정한다. wallet 생성·실제 자금·로그인은 first-screen 검증에 사용하지 않는다. 필요한 private 환경값 여부는 unknown이다.
- 이 BlueWallet SHA는 기존 [ADR-0018](../adr/0018-use-one-xcode-27-go-sample.md)의 Go SHA를 대체하지 않는다. 기존 성공을 새 SHA 또는 Android에 이전하지 않는다. Xcode 27과 최신 RN의 모든 third-party module 호환성도 unknown이다.

## 후속 baseline에 넘길 입력

1. 후보 source SHA를 fresh clone에 적용한다. RN 최소 앱은 정식 template/generator로 생성한 뒤 생성 source SHA를 잠근다. 소스 범위·app root·dependency root·shared scheme·variant·entrypoint를 확인한다.
2. 각 SDK 정식 artifact의 정확한 version/build/architecture/checksum을 잠근다. 범위 선언·resolved lock·관찰한 설치 버전을 별도 기록한다. unknown AGP/JDK/Pods/Flutter native migration 조건을 확인한다. 설치 필요 여부와 인간 설정을 계획에 넣는다.
3. Runstir 없이 같은 tuple에서 build/install/launch/첫 화면을 확인한다. 원인 불명 실패는 `inconclusive`로 둔다. 부적격 표본 교체와 이후 추가 검증을 구분한다. private 값이 필수면 제공 가능성과 공개 증거 범위를 먼저 해결한다.
4. 다른 fresh clone에서 Runstir를 검증한다. Simulator/Emulator identity, OS/runtime, source 보존, 기존 자원 보존, setup/build/up/down 결과를 기록한다. Android 가속은 실제 Mac에서 확인한다. VM 결과를 실제 Mac·실기기 결과로 바꾸지 않는다.
5. 신규 tuple 성공 뒤에만 해당 조합을 `validated`로 기록한다. 실패를 삭제하지 않는다. 이 표의 모든 후보가 합쳐서 정식 지원 범위를 만드는 것은 아니다. 기존 기준 VM은 보존한다.

이 조사는 설치·실행 없이 재현 입력을 좁혔다. 최신 Flutter bundle·RN 생성 앱 SHA·일부 resolved native 도구·private 환경값·Xcode 27 실호환은 남아 있다. 모두 후속 baseline 입력이다. 별도 제품 정책이나 출시 성공을 대신 결정하지 않았다.

[food-readme]: https://github.com/apple/sample-food-truck/blob/3954a769e99f3cc53297d94f2b960ceb2665b3d6/README.md
[food-scheme]: https://github.com/apple/sample-food-truck/blob/3954a769e99f3cc53297d94f2b960ceb2665b3d6/Food%20Truck.xcodeproj/xcshareddata/xcschemes/Food%20Truck.xcscheme
[nnw-readme]: https://github.com/Ranchero-Software/NetNewsWire/blob/aea7795bcc0698ced6f28eba53da886eb6217e64/README.md
[nnw-scheme]: https://github.com/Ranchero-Software/NetNewsWire/blob/aea7795bcc0698ced6f28eba53da886eb6217e64/NetNewsWire.xcodeproj/xcshareddata/xcschemes/NetNewsWire-iOS.xcscheme
[nnw-config]: https://github.com/Ranchero-Software/NetNewsWire/blob/aea7795bcc0698ced6f28eba53da886eb6217e64/xcconfig/NetNewsWire_project.xcconfig
[nnw-no-sign]: https://github.com/Ranchero-Software/NetNewsWire/blob/aea7795bcc0698ced6f28eba53da886eb6217e64/.github/ios-ci-no-signing.xcconfig
[todo-versions]: https://github.com/android/architecture-samples/blob/ee66e1526b84c026615df032c705842b7d2a521f/gradle/libs.versions.toml
[todo-wrapper]: https://github.com/android/architecture-samples/blob/ee66e1526b84c026615df032c705842b7d2a521f/gradle/wrapper/gradle-wrapper.properties
[todo-app]: https://github.com/android/architecture-samples/blob/ee66e1526b84c026615df032c705842b7d2a521f/app/build.gradle.kts
[nia-versions]: https://github.com/android/nowinandroid/blob/a49ed253d75e61a2b6ab80a8da677b57437b08eb/gradle/libs.versions.toml
[nia-wrapper]: https://github.com/android/nowinandroid/blob/a49ed253d75e61a2b6ab80a8da677b57437b08eb/gradle/wrapper/gradle-wrapper.properties
[nia-kotlin]: https://github.com/android/nowinandroid/blob/a49ed253d75e61a2b6ab80a8da677b57437b08eb/build-logic/convention/src/main/kotlin/com/google/samples/apps/nowinandroid/KotlinAndroid.kt
[nia-app-convention]: https://github.com/android/nowinandroid/blob/a49ed253d75e61a2b6ab80a8da677b57437b08eb/build-logic/convention/src/main/kotlin/AndroidApplicationConventionPlugin.kt
[nia-app]: https://github.com/android/nowinandroid/blob/a49ed253d75e61a2b6ab80a8da677b57437b08eb/app/build.gradle.kts
[flutter-min-pub]: https://github.com/flutter/samples/blob/5541c59ab8e9d7e74c1a35ef22bd43a487fc596c/platform_design/pubspec.yaml
[flutter-min-settings]: https://github.com/flutter/samples/blob/5541c59ab8e9d7e74c1a35ef22bd43a487fc596c/platform_design/android/settings.gradle
[flutter-min-wrapper]: https://github.com/flutter/samples/blob/5541c59ab8e9d7e74c1a35ef22bd43a487fc596c/platform_design/android/gradle/wrapper/gradle-wrapper.properties
[flutter-min-readme]: https://github.com/flutter/samples/blob/5541c59ab8e9d7e74c1a35ef22bd43a487fc596c/platform_design/README.md
[local-fvm]: https://github.com/localsend/localsend/blob/c1ce322fb3acf08e44f329b8b7208b8b0d91e244/.fvmrc
[local-pub]: https://github.com/localsend/localsend/blob/c1ce322fb3acf08e44f329b8b7208b8b0d91e244/app/pubspec.yaml
[local-workspace]: https://github.com/localsend/localsend/blob/c1ce322fb3acf08e44f329b8b7208b8b0d91e244/pubspec.yaml
[local-readme]: https://github.com/localsend/localsend/blob/c1ce322fb3acf08e44f329b8b7208b8b0d91e244/README.md
[local-rust]: https://github.com/localsend/localsend/blob/c1ce322fb3acf08e44f329b8b7208b8b0d91e244/rust-toolchain.toml
[local-settings]: https://github.com/localsend/localsend/blob/c1ce322fb3acf08e44f329b8b7208b8b0d91e244/app/android/settings.gradle
[local-wrapper]: https://github.com/localsend/localsend/blob/c1ce322fb3acf08e44f329b8b7208b8b0d91e244/app/android/gradle/wrapper/gradle-wrapper.properties
[local-app]: https://github.com/localsend/localsend/blob/c1ce322fb3acf08e44f329b8b7208b8b0d91e244/app/android/app/build.gradle
[rn-min-package]: https://github.com/react-native-community/template/blob/bf0ef330c39d85c3f5bab248b83c7eedbce943da/template/package.json
[rn-min-gems]: https://github.com/react-native-community/template/blob/bf0ef330c39d85c3f5bab248b83c7eedbce943da/template/Gemfile
[rn-min-build]: https://github.com/react-native-community/template/blob/bf0ef330c39d85c3f5bab248b83c7eedbce943da/template/android/build.gradle
[rn-min-wrapper]: https://github.com/react-native-community/template/blob/bf0ef330c39d85c3f5bab248b83c7eedbce943da/template/android/gradle/wrapper/gradle-wrapper.properties
[blue-package]: https://github.com/BlueWallet/BlueWallet/blob/69adb1555038c8b2385952edd0404d2e1ecd7ca7/package.json
[blue-gems]: https://github.com/BlueWallet/BlueWallet/blob/69adb1555038c8b2385952edd0404d2e1ecd7ca7/Gemfile.lock
[blue-build]: https://github.com/BlueWallet/BlueWallet/blob/69adb1555038c8b2385952edd0404d2e1ecd7ca7/android/build.gradle
[blue-wrapper]: https://github.com/BlueWallet/BlueWallet/blob/69adb1555038c8b2385952edd0404d2e1ecd7ca7/android/gradle/wrapper/gradle-wrapper.properties

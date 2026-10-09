# CLI 확장: 프로젝트 정본과 실행 경로 조사

조사일: 2026-10-09. 대상 호스트: macOS Apple Silicon.
티켓: [조사: Flutter·네이티브 프로젝트의 정본과 실행 경로](https://github.com/minjunkim-dev/mobile-runtime/issues/179).
Runstir 기준 commit: `1a4ff6dc3815ab6c25df81eaef8ca37acaefe21e`.

이 문서는 사실 조사다. 지원 버전, 탐지 우선순위, 새 CLI 명령을 결정하지 않는다. 아래 명령은 실행 경로의 예시다. 이번 조사에서 설치·빌드·앱 실행·VM 조작은 하지 않았다. 로컬 Xcode 27.0 (`27A266a`)의 `simctl help`만 읽었다.

## 현재 Runstir 계약

| 영역 | 확인한 현재 동작 | 고정 source |
| --- | --- | --- |
| 프로젝트 탐지 | 현재 디렉터리부터 상위로 탐색한다. 가장 가까운 `package.json`의 `dependencies.react-native`가 anchor다. `.git` 또는 filesystem root에서 멈춘다. 하위 앱 전체를 열거하지 않는다. Flutter·네이티브만 있는 프로젝트는 이 탐지를 통과하지 않는다. | [ProjectAnchor](https://github.com/minjunkim-dev/mobile-runtime/blob/1a4ff6dc3815ab6c25df81eaef8ca37acaefe21e/Sources/Core/Project/ProjectAnchor.swift#L330-L405) |
| 선언과 측정 | RN 버전은 설치된 `node_modules/react-native` → lockfile → 정확한 manifest pin 순서로 구한다. manifest range만 있으면 확정 버전이 없다. 다른 근거와의 불일치를 보존한다. | [ReactNativeVersion](https://github.com/minjunkim-dev/mobile-runtime/blob/1a4ff6dc3815ab6c25df81eaef8ca37acaefe21e/Sources/Core/Project/ReactNativeVersion.swift#L12-L95) |
| Tier 1/2/3 | Tier 1은 저장소 선언이다. iOS Tier 2는 RN compatibility matrix다. Xcode/runtime 요구값은 project 선언과 matrix의 더 높은 하한을 쓴다. Tier 3 `mobile.yml` override는 해당 matrix 값을 대신한다. 이 구현을 Flutter·Android 전체에 일반화한 근거는 없다. | [MatrixLookup](https://github.com/minjunkim-dev/mobile-runtime/blob/1a4ff6dc3815ab6c25df81eaef8ca37acaefe21e/Sources/Core/Matrix/MatrixLookup.swift#L32-L150) |
| 사람이 정하는 값 | `ios.scheme`, `ios.device`, `android.module`, `android.variant`, `android.launcherActivity`, `android.avd`가 있다. scheme이 여러 개면 자동 선택하지 않는다. | [MobileConfig](https://github.com/minjunkim-dev/mobile-runtime/blob/1a4ff6dc3815ab6c25df81eaef8ca37acaefe21e/Sources/Core/Config/MobileConfig.swift#L11-L76), [SchemeSelection](https://github.com/minjunkim-dev/mobile-runtime/blob/1a4ff6dc3815ab6c25df81eaef8ca37acaefe21e/Sources/SimulatorKit/SchemeSelection.swift) |
| 도구 활성화 | 커밋된 mise 설정의 기존 도구를 활성화한다. 자동 설치와 trust는 금지한다. 선언한 Yarn/pnpm은 Corepack에서 기존 준비된 manager를 쓴다. 선언과 lockfile manager가 충돌하면 멈춘다. | [ADR-0009](https://github.com/minjunkim-dev/mobile-runtime/blob/1a4ff6dc3815ab6c25df81eaef8ca37acaefe21e/docs/adr/0009-activate-project-toolchains-without-provisioning.md) |
| 의존성 정렬 | 가장 가까운 상위 lockfile의 root에서 manager를 실행한다. npm은 `ci`, Yarn/pnpm/Bun은 frozen install이다. lockfile이 없으면 선언 또는 npm fallback을 쓴다. iOS는 Node 설치 후 필요한 gems와 Pods를 설치한다. `Podfile.lock`과 `Pods/Manifest.lock`의 byte 비교로 Pods stale 상태를 판단한다. 프로젝트가 선언한 pod 설치 script를 우선한다. | [ProjectAnchor 설치 명령](https://github.com/minjunkim-dev/mobile-runtime/blob/1a4ff6dc3815ab6c25df81eaef8ca37acaefe21e/Sources/Core/Project/ProjectAnchor.swift#L133-L294), [DependenciesStage](https://github.com/minjunkim-dev/mobile-runtime/blob/1a4ff6dc3815ab6c25df81eaef8ca37acaefe21e/Sources/Core/Up/DependenciesStage.swift#L12-L159) |
| 플랫폼 경로 | iOS up: validate → dependencies → device → Metro → build → install → launch. Android up: build pipeline → device → install → Metro → reverse → launch. 두 경로 모두 RN anchor를 받는다. Android는 Pods를 설치하지 않는다. | [IOSUpStages](https://github.com/minjunkim-dev/mobile-runtime/blob/1a4ff6dc3815ab6c25df81eaef8ca37acaefe21e/Sources/SimulatorKit/IOSUpStages.swift#L13-L57), [AndroidBuildStage](https://github.com/minjunkim-dev/mobile-runtime/blob/1a4ff6dc3815ab6c25df81eaef8ca37acaefe21e/Sources/AndroidKit/AndroidBuildStage.swift#L1-L55), [AndroidUpStages](https://github.com/minjunkim-dev/mobile-runtime/blob/1a4ff6dc3815ab6c25df81eaef8ca37acaefe21e/Sources/AndroidKit/AndroidUpStages.swift#L769-L846) |

현재 iOS build는 `ios/` 바로 아래의 단일 workspace를 우선한다. workspace가 없으면 단일 project를 쓴다. 여러 workspace를 찾으면 project로 조용히 fallback하지 않는다. build product의 app path와 bundle ID는 `xcodebuild -showBuildSettings -json` 결과에서 구한다. 이 위치 규칙은 일반 네이티브 앱의 위치 규칙을 증명하지 않는다. [XcodeBuildTarget](https://github.com/minjunkim-dev/mobile-runtime/blob/1a4ff6dc3815ab6c25df81eaef8ca37acaefe21e/Sources/SimulatorKit/XcodeBuildTarget.swift).

## 6개 조합의 정본과 선택 입력

아래의 사람 입력은 항상 필수라는 뜻이 아니다. 프로젝트가 여러 후보를 제공하거나 선언을 생략하면 값이 필요하다. framework가 있다는 사실과 실행할 app target이 있다는 사실은 다르다.

| 조합 | 정본 후보와 도구 요구사항 | 의존성/lockfile | 값이 모호한 경우 |
| --- | --- | --- | --- |
| 네이티브 iOS | Xcode project/workspace와 scheme, project build settings. Xcode가 build 도구다. 선택한 scheme/destination으로 실제 설정을 구한다. `.xcode-version`은 현재 Runstir가 읽는 별도 선언이며 모든 Xcode project의 필수 파일이라는 근거는 없다. [Apple CLI][apple-cli], [Apple build][apple-build] | Swift packages를 쓰면 Xcode package dependency와 `Package.resolved`. CocoaPods를 쓰면 `Podfile`/`Podfile.lock`. 어느 manager도 쓰지 않을 수 있다. [SwiftPM][swiftpm], [Pods][pods] | project/workspace, scheme, configuration, 실행 가능한 app product, bundle ID, runtime/device. scheme에는 build/run 설정과 launch arguments/environment가 포함된다. [scheme][scheme] |
| 네이티브 Android | `settings.gradle(.kts)`가 module을 연결한다. root/module `build.gradle(.kts)`와 plugin 설정이 SDK·variant·applicationId를 정한다. wrapper `gradle-wrapper.properties`가 Gradle 배포를 정한다. Gradle 실행 JDK와 Java compile toolchain JDK는 다른 요구값이다. [Android build][android-build], [wrapper][wrapper], [JDK][jdk] | Gradle dependency 선언. locking을 활성화한 configuration은 `gradle.lockfile`을 사용한다. wrapper version 고정은 dependency locking과 다르다. [Gradle locks][gradle-locks] | application module, build type/flavor가 만든 variant, 해당 variant의 applicationId와 launcher activity, device. source manifest만 읽으면 Gradle override와 manifest merge를 놓칠 수 있다. [variants][variants], [Android build][android-build] |
| Flutter iOS | `pubspec.yaml`의 Flutter SDK dependency와 Dart/Flutter environment constraint. iOS host project/scheme도 필요하다. Flutter SDK와 Xcode를 사용한다. plugin의 native dependency 경로는 SDK/project 설정에 따라 SwiftPM과 CocoaPods가 다르다. [pubspec][flutter-pubspec], [SDK constraints][dart-pubspec], [iOS setup][flutter-ios], [Flutter SwiftPM][flutter-spm] | `pubspec.lock`은 Dart packages의 정확한 해석 결과다. native dependency 결과는 SwiftPM/Pods 쪽에도 존재한다. Dart lock만으로 native dependency 준비를 증명하지 않는다. [dependency management][flutter-lock], [Flutter SwiftPM][flutter-spm] | Dart entrypoint, flavor/scheme, device, standalone app인지 module인지. Flutter dependency가 있는 package/plugin도 실행 가능한 app과 다르다. [CLI][flutter-cli], [flavors][flavors], [add-to-app][flutter-add] |
| Flutter Android | 같은 pubspec/SDK constraint에 Android host Gradle 설정이 추가된다. Flutter SDK 외에 Android SDK와 Gradle/JDK 관계도 남는다. [pubspec][flutter-pubspec], [Android deployment][flutter-android], [JDK][jdk] | `pubspec.lock`과 Gradle dependency 체계. Gradle locking은 설정 여부를 확인해야 한다. [Flutter lock][flutter-lock], [Gradle locks][gradle-locks] | entrypoint, flavor, Android module/variant, device, standalone app/module. [flavors][flavors], [add-to-app][flutter-add] |
| React Native iOS | `package.json`의 RN/Node/package manager 선언, JS workspace root. native host는 Xcode project/workspace와 Podfile 등이다. RN 공식 환경 안내는 Node·Xcode·CocoaPods를 다룬다. `.xcode.env`의 `NODE_BINARY`도 Xcode build의 Node 경로에 관여한다. 문서의 현재 권장 도구는 모든 기존 RN 버전의 요구값이 아니다. [RN environment][rn-env], [RN integration][rn-add] | JS manager lockfile과 iOS native locks. Gemfile을 쓰면 gem dependency도 별도다. 현재 Runstir의 manager/Pods 선택 규칙은 위 source 표를 따른다. [RN integration][rn-add], [현재 DependenciesStage](https://github.com/minjunkim-dev/mobile-runtime/blob/1a4ff6dc3815ab6c25df81eaef8ca37acaefe21e/Sources/Core/Up/DependenciesStage.swift) | app/package root, scheme, device, native project 위치, embedded RN 여부. template의 `ios/` 배치가 모든 integration의 배치를 정하지 않는다. [RN integration][rn-add] |
| React Native Android | RN/Node 선언과 Android Gradle host. RN Gradle plugin과 autolinking 설정도 integration에 관여한다. JDK·Android SDK는 native build 요구값이다. [RN environment][rn-env], [RN integration][rn-add] | JS lockfile과 Gradle dependency 체계. JS lockfile 하나로 Gradle dependency 전체를 고정하지 않는다. [RN integration][rn-add], [Gradle locks][gradle-locks] | app root, application module/variant, applicationId/activity, device, embedded RN 여부. [RN integration][rn-add], [variants][variants] |

Flutter의 `environment.sdk`는 Dart SDK constraint다. `environment.flutter`는 Flutter SDK constraint다. 공식 Pub 문서는 Flutter constraint의 **하한만 강제한다**고 명시한다. 이 두 값과 `pubspec.lock`만으로 설치할 Flutter SDK의 정확한 버전을 하나로 확정할 수는 없다. 이는 근거에서 도출한 한계다. 프로젝트가 별도로 SDK를 고정했는지는 별도 조사 대상이다. [SDK constraints][dart-pubspec].

## build → install → launch → stop 경로

모든 예시에서 `<device>`는 이미 준비한 특정 Simulator/Emulator다. app identity와 build product는 선택한 app target의 결과여야 한다. Simulator/runtime 생성과 SDK 설치는 [별도 기기 준비 조사](https://github.com/minjunkim-dev/mobile-runtime/issues/180)의 범위다.

| 조합 | build/install/launch | app stop |
| --- | --- | --- |
| 네이티브 iOS | `xcodebuild -workspace <workspace> -scheme <scheme> -configuration <configuration> -destination 'platform=iOS Simulator,id=<udid>' build`. project만 있으면 `-project`를 쓴다. 생성한 `.app`을 `xcrun simctl install <udid> <app>`로 설치한다. `xcrun simctl launch <udid> <bundleId>`로 실행한다. [Apple build][apple-build], [Apple CLI][apple-cli], 아래 로컬 help 관측 | `xcrun simctl terminate <udid> <bundleId>`. 아래 로컬 help 관측 |
| 네이티브 Android | 선택한 module의 `./gradlew :<module>:assemble<Variant>` → `adb -s <serial> install <apk>` → `adb -s <serial> shell am start -W -n <applicationId>/<activity>`. `install<Variant>` task는 build와 install을 합친다. [Android commands][android-commands], [adb][adb] | `adb -s <serial> shell am force-stop <applicationId>`. [adb][adb] |
| Flutter iOS | `flutter pub get` 후 `flutter build ios --simulator`. `flutter install -d <deviceId>` 또는 생성한 `.app`의 simctl install을 쓴다. `flutter run -d <deviceId> <entrypoint>`는 build/install/run을 맡는다. iOS simulator build flag는 공식 tool source에서 확인했다. [CLI][flutter-cli], [build_ios source][flutter-build-ios] | target app의 simctl terminate를 쓸 수 있다. Flutter resident run session의 정리와 app 종료는 별도 효과다. 이 조사에서 session 종료 계약은 검증하지 않았다. |
| Flutter Android | `flutter pub get` → `flutter build apk` → `flutter install -d <deviceId>`. 개발 실행은 `flutter run -d <deviceId> <entrypoint>`. flavor가 있으면 `--flavor <name>`을 지정할 수 있다. build mode와 split APK 여부에 따라 결과물이 다르다. [CLI][flutter-cli], [Android deployment][flutter-android], [flavors][flavors] | target applicationId의 adb force-stop. Flutter resident session 정리는 별도 미검증이다. [adb][adb] |
| React Native iOS | 공식 예시는 프로젝트 `npm run ios`/`yarn ios` script다. `--simulator` 또는 `--udid`로 대상을 고른다. 현재 Runstir는 위 native Xcode/simctl 경로에 Metro와 bundle readiness를 더한다. 공식 예시를 모든 저장소의 script 이름으로 가정할 수 없다. [RN simulator][rn-ios], [현재 stages](https://github.com/minjunkim-dev/mobile-runtime/blob/1a4ff6dc3815ab6c25df81eaef8ca37acaefe21e/Sources/SimulatorKit/IOSUpStages.swift) | target app의 simctl terminate. Metro 종료에는 별도 ownership 판단이 필요하다. 현재 `down` 구현의 경계다. [현재 IOSTeardown](https://github.com/minjunkim-dev/mobile-runtime/blob/1a4ff6dc3815ab6c25df81eaef8ca37acaefe21e/Sources/SimulatorKit/IOSTeardown.swift) |
| React Native Android | 공식 예시는 프로젝트 `npm run android`/`yarn android` script다. 현재 Runstir는 Gradle APK build, adb install, Metro, adb reverse, adb activity start를 각각 처리한다. [RN device][rn-device], [현재 runtime](https://github.com/minjunkim-dev/mobile-runtime/blob/1a4ff6dc3815ab6c25df81eaef8ca37acaefe21e/Sources/AndroidKit/AndroidUpStages.swift#L149-L439) | adb force-stop. Metro/reverse/Emulator는 해당 run ownership에 따른 별도 정리 대상이다. [현재 AndroidTeardown](https://github.com/minjunkim-dev/mobile-runtime/blob/1a4ff6dc3815ab6c25df81eaef8ca37acaefe21e/Sources/AndroidKit/AndroidTeardown.swift) |

로컬 Apple 도구의 primary help 관측:

```text
xcodebuild -version: Xcode 27.0 / Build version 27A266a
xcrun simctl help install: Usage: simctl install <device> <path>
xcrun simctl help launch: Usage: simctl launch [options] <device> <app bundle identifier> [args]
xcrun simctl help terminate: Usage: simctl terminate <device> <app bundle identifier>
```

`simctl help` 조회는 device를 생성하거나 실행하지 않았다. Apple 문서는 CLI syntax의 primary reference로 설치된 `man`/`help`를 안내한다. [Apple CLI][apple-cli].

## 자동 탐지가 답하지 못하는 경우와 변경 효과

1. monorepo에는 여러 RN/Flutter 앱과 공용 packages가 있을 수 있다. 현재 RN 탐지는 상위 anchor 하나와 가장 가까운 상위 lockfile을 찾는다. 상위 저장소에서 하위 앱 하나를 선택하는 구현은 없다. Flutter에도 Pub workspace가 있으므로 package root와 dependency resolution root를 같다고 가정할 수 없다. [현재 ProjectAnchor](https://github.com/minjunkim-dev/mobile-runtime/blob/1a4ff6dc3815ab6c25df81eaef8ca37acaefe21e/Sources/Core/Project/ProjectAnchor.swift#L330-L495), [Pub workspaces](https://dart.dev/tools/pub/workspaces).
2. scheme/variant는 단순한 이름이 아니다. Xcode scheme은 build/run 대상과 arguments/environment를 정한다. Android flavor/build type은 applicationId와 의존성도 바꿀 수 있다. 특정 후보를 고르는 일은 사람이 정한 실행 의도와 관련된다. [scheme][scheme], [variants][variants], [Android build][android-build].
3. Flutter add-to-app과 RN integration은 native host 안에 framework를 넣는다. `pubspec.yaml`이나 RN dependency를 찾았다는 이유만으로 standalone framework 앱이라고 단정할 수 없다. 반대로 native host 파일을 찾았다고 framework가 없다고 단정할 수도 없다. 이는 두 공식 integration 경로에서 도출한 탐지 한계다. [Flutter add-to-app][flutter-add], [RN integration][rn-add].
4. Flutter 공식 문서는 3.44부터 SwiftPM을 기본으로 사용한다고 명시한다. upgrade 후 run은 `project.pbxproj`와 scheme에 SwiftPM integration을 자동 추가할 수 있다. 지원하지 않는 plugin은 CocoaPods로 fallback한다. 따라서 Flutter run은 tracked source/config 변경이 없는 의존성 정렬이라고 일반화할 수 없다. 이번 조사에서 이 마이그레이션을 실행하지 않았다. [Flutter SwiftPM][flutter-spm].
5. Gradle wrapper는 Gradle 배포를 다운로드할 수 있다. Java toolchain resolver도 누락된 JDK를 다운로드할 수 있다. `pub get`, Xcode package resolution, pod install은 dependency 다운로드와 해석 결과 쓰기를 수행한다. 실제 프로젝트 script/plugin의 추가 효과는 저장소별로 다르다. 공식 build 경로가 있다는 사실은 무변경·오프라인·무승인 실행을 증명하지 않는다. [wrapper][wrapper], [JDK][jdk], [Flutter lock][flutter-lock], [Apple package CI][apple-package-ci], [Pods][pods].

## unknown과 후속 결정 입력

| 항목 | 이번 조사 결과 |
| --- | --- |
| 6개 조합의 macOS/Xcode/Flutter/RN/AGP/JDK 지원 tuple | **unknown**. 일반 문서 경로를 확인했다. 모든 조합의 특정 version tuple 빌드·첫 화면은 검증하지 않았다. |
| 임의 저장소의 필수 app configuration/secret/launch argument | **unknown**. scheme/Gradle/script가 제공할 수 있지만 공통 필수값 목록은 공식 도구 문서만으로 확정되지 않는다. |
| Flutter run의 tracked 파일 보존 | 모든 프로젝트에 보장할 수 없다. 공식 SwiftPM 자동 migration 경로가 존재한다. SDK별·project별 효과를 검증해야 한다. |
| framework가 겹친 프로젝트의 분류/선택 순서 | 공식 integration으로 겹칠 수 있다는 사실만 확인했다. 제품 탐지 정책은 미결정이다. |
| stop 후 app/process/server/device 정리 범위 | app 종료 명령은 확인했다. Runstir가 만들거나 재사용한 resource를 어디까지 정리할지는 CLI/ownership 계약 결정이다. |

기존 `unknown` 판정, source 출처, lockfile 선택, 프로젝트 실행 환경이라는 구분은 현재 코드에 있다. 새 framework가 이 구분을 어떻게 쓰는지는 결정 티켓의 답이다. 이 문서는 기존 ADR이나 구현 범위를 바꾸지 않는다.

[apple-cli]: https://developer.apple.com/documentation/xcode/xcode-command-line-tool-reference
[apple-build]: https://developer.apple.com/library/archive/technotes/tn2339/_index.html
[scheme]: https://developer.apple.com/documentation/xcode/customizing-the-build-schemes-for-a-project
[swiftpm]: https://docs.swift.org/package-manager/PackageDescription/PackageDescription.html
[apple-package-ci]: https://developer.apple.com/documentation/xcode/building-swift-packages-or-apps-that-use-them-in-continuous-integration-workflows
[pods]: https://guides.cocoapods.org/using/pod-install-vs-update.html
[android-build]: https://developer.android.com/build
[android-commands]: https://developer.android.com/build/building-cmdline
[variants]: https://developer.android.com/build/build-variants
[jdk]: https://developer.android.com/build/jdks
[wrapper]: https://docs.gradle.org/current/userguide/gradle_wrapper.html
[gradle-locks]: https://docs.gradle.org/current/userguide/dependency_locking.html
[adb]: https://developer.android.com/tools/adb
[flutter-cli]: https://docs.flutter.dev/reference/flutter-cli
[flutter-pubspec]: https://docs.flutter.dev/tools/pubspec
[dart-pubspec]: https://dart.dev/tools/pub/pubspec#sdk-constraints
[flutter-lock]: https://docs.flutter.dev/packages-and-plugins/dependency-management
[flutter-ios]: https://docs.flutter.dev/platform-integration/ios/setup
[flutter-android]: https://docs.flutter.dev/deployment/android
[flutter-spm]: https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers
[flavors]: https://docs.flutter.dev/deployment/flavors
[flutter-add]: https://docs.flutter.dev/add-to-app
[flutter-build-ios]: https://github.com/flutter/flutter/blob/d2911055736e6f1bfdd202e560e21c56b76e8bf5/packages/flutter_tools/lib/src/commands/build_ios.dart#L37-L69
[rn-env]: https://reactnative.dev/docs/set-up-your-environment
[rn-add]: https://reactnative.dev/docs/integration-with-existing-apps
[rn-ios]: https://reactnative.dev/docs/running-on-simulator-ios
[rn-device]: https://reactnative.dev/docs/running-on-device

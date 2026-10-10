# React Native 고정 표본 baseline — #212

검증일: 2026-10-10, Asia/Seoul. 상태: **부분 검증. #212 완료가 아니다.**
제품 실행 SHA: 없음. 모든 앱 준비·빌드·설치·실행에 Runstir를 사용하지 않았다.

입력은 [#194 조사 정본](https://github.com/minjunkim-dev/mobile-runtime/blob/52ca6150685780cca86d5cb7c0b562033b40bd30/docs/research/cli-expansion-validation-candidates.md)이다.
[지원 계약](./cli-expansion-support-contract.md)과 [공동 게이트 계약](./shared-launch-gate-contract.md)을 적용했다.
[명세 #199](https://github.com/minjunkim-dev/mobile-runtime/issues/199)의 AC05·AC06에 baseline 증거만 제공한다.
과거 BlueWallet Go의 Pod checksum 예외와 #201의 RN 0.82 준비 앱 증거를 적용하지 않았다.

## 판정

| 표본 | Android | iOS | known-good |
| --- | --- | --- | --- |
| 최소 RN `0.87.1` | build·install·launch·첫 화면 확인 | build·install 성공. launch 요청 성공 뒤 UIScene 미채택으로 crash | Android만 확인. 양플랫폼 미충족 |
| BlueWallet `69adb155` | build·install·launch·첫 화면 확인 | frozen Pods 준비 실패. build·install·launch·첫 화면 미실행 | Android만 확인. 양플랫폼 미충족 |

이 실패는 **Runstir 실패가 아니다.** RN 원본 표본의 준비 또는 실행 실패다.
최소 앱과 BlueWallet의 RN·AGP·Gradle·NDK와 bundled CocoaPods·xcodeproj가 다르다.
공통 host·Node·Ruby·JDK·SDK 설치·기기 조건과 표본별 resolved 도구를 분리했다.
이 기록을 같은 전체 검증 조합의 PASS로 합산하지 않는다.
필수 양플랫폼 baseline과 같은 도구 조합 조건은 아직 출시 게이트를 통과하지 못했다.

## source와 lockfile

최소 앱은 정식 `@react-native-community/template` tag `0.87.2`의 SHA `bf0ef330c39d85c3f5bab248b83c7eedbce943da`를 사용했다.
template 버전과 내부 RN `0.87.1`을 구분한다.
`@react-native-community/cli@20.2.0`으로 `RunstirBaselineRN`을 생성했다.
최초 생성 commit은 `a7b475080bae86f2a2408806233a724061ad7bdb`다.
처음 생성한 앱에는 JS·Ruby·Pods lockfile이 없었다.
최초 의존성 해석과 upstream CocoaPods의 생성 변경을 고정한 실행 source는 `b62e3a4d5e7cfc05d7d948a5a4e30f0cc6a82bb4`다.
두 commit과 lockfile을 [source bundle](./evidence/212/minimal-source.bundle)에 보존한다.
AppDelegate·SceneDelegate 또는 컴파일러 workaround를 수동 변경하지 않았다.

upstream `pod install`은 생성 앱의 Xcode project·Info.plist·PrivacyInfo.xcprivacy를 변경했다.
이 변경을 최초 생성 commit의 무변경이라고 주장하지 않는다.
준비 변경과 새 lockfile을 실행 source에 포함했다.
고정 뒤 Ruby `3.4.11`의 `pod install --deployment` 재실행에서 tracked byte가 같았다.

BlueWallet는 공개 원본 SHA `69adb1555038c8b2385952edd0404d2e1ecd7ca7`을 그대로 사용했다.
`packageManager` 필드는 없다. 원본은 `package-lock.json`만 제공한다.
Node `22.23.2`·npm `10.9.8`의 `npm ci`가 성공했다.
`npm install`이나 lockfile migration을 사용하지 않았다.
원본 package.json·package-lock.json·Gemfile.lock·Podfile.lock byte를 보존했다.

| 표본 | 파일 | SHA-256 |
| --- | --- | --- |
| 최소 | package-lock.json | `3478830fc86d9d1ae7cd46ae129eec9c4915b0ec4e2df247e2cb62b136caeee0` |
| 최소 | Gemfile.lock | `3679d60340d049c31b74052580c64ab26b3e6fa611f332c1407121dfc3c791eb` |
| 최소 | ios/Podfile.lock | `cec099ee896ed83dd780bd8da0a03e840c3ba6a0803f90c0bbfcd04efaf17d56` |
| BlueWallet | package-lock.json | `d4baeb805376bc178428464867435c1832b4f94ccbb2d2ea4dfd7286a3d8fc07` |
| BlueWallet | Gemfile.lock | `09528bbbbf3141568bbc664e0ee9270c617ac87c937f36a66911edf3fa916814` |
| BlueWallet | ios/Podfile.lock | `01db3c351c647e5e15988227c8851003c0262159c8c11d3e2240a9d13f3b3e4f` |

## 환경과 선택

공통 실제 host는 macOS `27.0.1`, build `26A434`, Apple Silicon `arm64`다.
Xcode는 `27.0`, build `27A266a`다. `DEVELOPER_DIR` 전역 선택을 바꾸지 않았다.
Node는 기존 `22.23.2`를 사용했다. 두 표본의 정본 범위를 충족한다.
Ruby `3.4.11p137`은 기존 버전을 보존하고 나란히 설치했다.
BlueWallet의 정확한 Ruby 선언을 따랐다.
최소 앱의 최초 lock 생성·Pod 준비는 Ruby `3.3.12`로 수행했다.
고정 전 Ruby lock identity를 `3.4.11`로 갱신했다.
고정 뒤 Ruby `3.4.11`의 frozen Pods 재검사가 성공했다.
JDK는 기존 Zulu `17.66.19.0`을 이번 프로세스에서만 선택했다.
실효 Java는 `17.0.19+10-LTS`, 공급자는 `Zulu17.66+19-CA`다.
전역 mise 설정·PATH·Xcode 선택·라이선스 승인을 바꾸지 않았다.

| 도구/선택 | 최소 앱 | BlueWallet |
| --- | --- | --- |
| React Native | `0.87.1` | `0.85.3` |
| Bundler | `2.5.22` | `2.6.9` |
| CocoaPods / xcodeproj | `1.15.2` / `1.25.1` | `1.17.0` / `1.28.1` |
| Gradle / AGP | `9.4.1` / `9.2.1` | `9.3.1` / `8.13.2` |
| compile / target SDK | `37` / `36` | `36` / `36` |
| build-tools / NDK | `37.0.0` / `27.1.12297006` | `36.0.0` / `28.2.13676358` |
| Android module / variant | `:app` / `debug` | `:app` / `debug` |
| iOS scheme / configuration | `RunstirBaselineRN` / `Debug` | `BlueWallet` / `Debug` (준비 미완료) |

Android SDK root는 같은 로컬 설치다.
재현 명령은 `ANDROID_HOME`·`ANDROID_SDK_ROOT`를 명시한다.
기존 platform `android-37.0` revision `2`와 platform `android-36` revision `2`를 사용했다.
새 `build-tools;37.0.0`만 공식 stable metadata에서 추가했다.
기존 라이선스 기록으로 설치했다. 새 라이선스 동의는 없다.
공식 macOS archive는 `build-tools_r37_macosx.zip`, SHA-1 `eb080751b2b2028eb3604f571027d6f7b3c46321`이다.
설치한 `aapt2`의 SHA-256은 `13a206c0b022ba3b92f21b6f142f3a4b2d0f3bb1ac0bddfa820ee2c6b00c4c99`다.
archive 자체를 별도 다운로드하여 checksum을 검사한 증거는 아니다.

실제 Android 대상은 기존 AVD `Pixel_10_API_37_Play`, serial `emulator-5554`다.
Emulator `37.1.11`, platform-tools `37.0.1`을 재사용했다.
system image는 API `37.0` Google Play ARM64 revision `6`다.
기기 fingerprint는 `google/sdk_gphone64_arm64/emu64a:17/CE2A.260420.019/15611780:user/release-keys`다.
실제 Mac의 `emulator -accel-check`는 code `0`과 `Hypervisor.Framework OS X Version 27.0`을 반환했다.
VM에서 Android 가속을 검증했다고 주장하지 않는다.

iOS 대상은 기존 iPhone 18 Pro, iOS `27.0`, UDID `8C71F44D-7D37-436D-94D3-3D25DCF3FD30`다.
Simulator build에는 `CODE_SIGNING_ALLOWED=NO`를 명시했다.
기존 두 Simulator·Smallnext QA·사용자 GUI를 보존했다.

## 실패 보존과 후보 교체 경계

최소 iOS는 `xcodebuild` 성공과 `simctl install` 성공 뒤 두 번 launch를 요청했다.
첫 요청 PID는 `55086`이다. 두 번째는 `57097`이다.
두 PID 모두 첫 화면 전에 종료했다.
crash의 exception은 `EXC_BREAKPOINT / SIGTRAP`이다.
첫 frame은 `___UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption_block_invoke`다.
고정한 공식 AppDelegate는 UIScene lifecycle을 채택하지 않는다.
이 실행을 launch 성공이나 known-good iOS로 기록하지 않는다.

BlueWallet Android는 `BUILD SUCCESSFUL in 7m 19s`를 반환했다.
기존 동일 앱 ID가 없는 Emulator에 설치했다.
Activity `io.bluewallet.bluewallet/.MainActivity`의 PID `4962`를 확인했다.
선택한 Emulator에서 `Wallets`·`Add a wallet`·빈 `Transactions` 첫 화면을 직접 확인했다.
red box·crash·빈 화면은 관측하지 않았다.
지갑·키·거래 데이터는 생성하지 않았다.

| 산출물 | SHA-256 |
| --- | --- |
| 최소 Android APK | `ea625a29a21df8348c113d817020311059f523c4e4f277505abcf8534623b3d3` |
| BlueWallet Android APK | `3b18c23f5fb0f376f0fccf62c27e409a2c8e2fcc8ac43c9827ee4b24dcb04218` |
| 최소 iOS .app의 로컬 zip | `af040475f573409ec581760345cdde269542a52df956243747d69c6280474ee8` |

실제 산출물과 원본 로그는 로컬 검증 루트에 보존한다.
공개 파일별 checksum은 manifest에서 확인한다.

최초 iOS build의 sandbox 임시 `TMPDIR` 소멸 오류도 보존했다.
실행 환경을 지속 경로 `TMPDIR=/tmp`로 정정한 같은 source의 build는 성공했다.
이 하네스 오류를 template 실패로 분류하지 않는다.

외부 볼륨의 Watchman 접근은 `Operation not permitted`로 실패했다.
권한을 변경하지 않았다.
별도 Metro config의 `resolver.useWatchman=false`로 Node watcher를 선택했다.
원본 Metro config와 tracked 파일을 바꾸지 않았다.
최소 Android 첫 화면은 이 명시한 환경 입력에서 관측했다.
Android의 새 표본 권한 화면에서 nearby-devices 허용을 선택했다.
앱 첫 화면 이후 기능은 검사하지 않았다.

BlueWallet iOS 준비는 `bundle exec pod install --deployment` exit `1`로 중단했다.
원본 npm lock은 lottie-react-native `7.5.0`과 safe-area-context `5.10.1`을 고정한다.
원본 Pod lock은 각각 `7.4.0`과 `5.8.1`을 고정한다.
로그는 `There were changes to the lockfile in deployment mode`를 반환했다.
정본 npm manager를 잘못 고른 문제가 아니다.
Pod lock을 재생성하거나 과거 checksum 예외를 적용하지 않았다.
준비가 실패했으므로 iOS build·install·launch·첫 화면은 미검증이다.

2026-10-10 조회한 정식 template의 최신 tag는 `0.87.2`다.
공식 UIScene 채택 commit `2858702eec721c63077e0bfb33f8eb68748f214f`는 현재 정식 tag에 포함되지 않는다.
`main`은 `react-native: nightly`, CLI `21.0.0-alpha.1`을 선언한다.
그 입력을 정식 교체 후보로 사용하지 않았다.
빌드 성공 SHA를 찾는 탐색과 nightly 우회를 수행하지 않았다.
교체 후보는 baseline 실패 기록을 보존한 뒤 별도 source와 도구 조건으로 고정해야 한다.

## fresh clone 인계

독립 검증 루트는 `/Volumes/P41_USB4/Developer/validation/runstir-212-rn-baseline-20261010`이다.
`minimal-source`와 `bluewallet-source`는 baseline 실행용이다.
`minimal-fresh`와 `bluewallet-fresh`는 실행하지 않은 별도 clone이다.
fresh clone에는 baseline의 node_modules·Pods·build 산출물·앱 데이터·Metro를 복사하지 않았다.
known-good 미충족 표본을 후속 Runstir PASS 입력으로 사용하지 않는다.
원본 로그는 이 로컬 루트에 보존한다. 전체 로그·crash report는 공개하지 않는다.
공개 자료에는 필요한 비식별 발췌와 두 Android 첫 화면만 포함한다.

baseline이 시작한 두 Metro 프로세스를 identity와 cwd 확인 뒤 종료했다.
두 새 Android 표본 앱을 force-stop했다.
baseline의 `adb reverse tcp:8081`을 제거했다.
baseline이 boot한 Emulator만 `adb emu kill`로 정상 종료했다.
기존 AVD를 삭제하거나 초기화하지 않았다.
정리 뒤 adb 기기와 8081 listener는 없었다.
초기 두 booted Simulator와 기존 GUI PID `98365`는 유지했다.
Smallnext QA Simulator를 사용하지 않았다.
새 표본 앱 설치와 선언한 로컬 도구·dependency 준비 산출물은 남겼다.
기존 앱의 데이터와 설치를 교체하지 않았다.

1. source bundle을 새 디렉터리에 clone한다.
2. 생성 source SHA를 확인한다.
3. 아래 명령으로 선언한 기존 도구만 선택한다.
4. JS·Ruby·Pods lockfile의 SHA-256을 확인한다.
5. 실제 대상과 8081을 독점 배정한 뒤 빌드·설치·실행한다.

`SDK_ROOT`는 재확인한 기존 Android SDK 경로다.
`SIMULATOR_UDID`·`EMULATOR_SERIAL`은 독점 배정한 실제 대상 identity다.
`DERIVED_DATA`는 해당 표본만 사용하는 새 산출물 경로다.
`APP_ROOT`·`RUNSTIR_REPO`·`APK`는 각각 표본 root·이 저장소 root·확인한 APK 경로다.
예시 변수를 설정한 뒤 명령을 실행한다.

```sh
git clone docs/evidence/212/minimal-source.bundle minimal-fresh
git -C minimal-fresh checkout --detach b62e3a4d5e7cfc05d7d948a5a4e30f0cc6a82bb4
git clone https://github.com/BlueWallet/BlueWallet.git bluewallet-fresh
git -C bluewallet-fresh checkout --detach 69adb1555038c8b2385952edd0404d2e1ecd7ca7

# 각 표본 root
mise exec node@22.23.2 -- npm ci
mise exec ruby@3.4.11 node@22.23.2 -- bundle config set --local path vendor/bundle
mise exec ruby@3.4.11 node@22.23.2 -- bundle install
# 각 표본 ios/ — BlueWallet는 이 단계에서 원본 lock drift로 중단한다.
mise exec ruby@3.4.11 node@22.23.2 -- bundle exec pod install --deployment

# Android root, 실행 SDK 경로를 실제 설치 경로로 명시한다.
mise exec java@zulu-17.66.19.0 -- env ANDROID_HOME="$SDK_ROOT" ANDROID_SDK_ROOT="$SDK_ROOT" \
  ./gradlew --no-daemon :app:assembleDebug -PreactNativeArchitectures=arm64-v8a

# 최소 앱 root, 대상 UDID를 다시 검증한다.
env TMPDIR=/tmp mise exec node@22.23.2 ruby@3.4.11 -- xcodebuild \
  -workspace ios/RunstirBaselineRN.xcworkspace -scheme RunstirBaselineRN \
  -configuration Debug -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -derivedDataPath "$DERIVED_DATA" CODE_SIGNING_ALLOWED=NO build
```

최소 앱의 실제 Android build는 architecture 제한 없이 수행했다.
BlueWallet의 실제 명령에는 `-PreactNativeArchitectures=arm64-v8a`를 명시했다.
생성 명령과 환경 입력은 [manifest](./evidence/212/manifest.json)에 연결한다.

외부 watcher config를 사용할 때 앱 root를 명시한다.
아래 config는 표본의 원본 Metro config를 읽고 Watchman 선택만 바꾼다.

```sh
BASELINE_APP_ROOT="$APP_ROOT" mise exec node@22.23.2 -- npm start -- \
  --port 8081 --config "$RUNSTIR_REPO/docs/evidence/212/no-watchman-config.cjs"
```

Android 앱은 `adb -s "$EMULATOR_SERIAL" install "$APK"`로 설치했다.
`adb reverse tcp:8081 tcp:8081`로 개발 서버를 연결했다.
`am start -W -n com.runstirbaselinern/.MainActivity`로 최소 앱을 실행했다.
BlueWallet의 Activity는 `io.bluewallet.bluewallet/.MainActivity`다.
iOS는 명시한 UDID의 `simctl install`과 `simctl launch`를 사용했다.
앱 첫 화면과 프로세스 상태는 설치·실행 요청 결과와 별도로 관측했다.

## AC 연결과 남은 조건

| 기준 | 결과 |
| --- | --- |
| #212 source·generator·locks 고정 | 조사 정본, 생성 SHA 두 개, OSS SHA, lock checksum, fresh clone 분리 |
| #212 정확 도구·환경 입력 | 관측 버전과 선택을 기록했다. 표본별 bundled 도구 차이를 같은 tuple로 숨기지 않았다. |
| #212 양플랫폼 최소+OSS 첫 화면 | 미충족. 두 Android 첫 화면 확인. 최소 iOS crash, BlueWallet iOS 준비 실패. |
| #212 실패·교체 이유 보존 | 원본 실패와 하네스·Watchman 실패를 분리했다. SHA 탐색과 lock 예외 없음. |
| #212 fresh clone 인계 | 실행하지 않은 별도 clone과 생성 source bundle 제공. |
| #199 AC05 | baseline 부분 증거다. Runstir CLI·GUI 및 여섯 조합 검증을 대체하지 않는다. |
| #199 AC06 | 실제 Mac Android 가속을 관측했다. VM·새 호스트·대표 실기기를 검증하지 않았다. |

#212를 닫지 않는다. 원본 iOS 문제와 같은 도구 조합 조건이 남아 있다.
정식 교체 후보 또는 승인한 새 표본 입력을 고정한 뒤 미달 항목을 다시 검증한다.

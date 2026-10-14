# RN OSS baseline attempt-03 — Mattermost Mobile

상태: Android build·install·launch·첫 화면 확인. iOS frozen 준비 실패. #212 완료가 아니다.
검증일은 2026-10-10이다. Runstir를 사용하지 않았다.
[tuple 정본](https://github.com/minjunkim-dev/mobile-runtime/issues/212#issuecomment-6092021206)과 원본 source·lock byte 보존 정책을 적용한다.
[최초 실패](./rn-baseline-212.md)와 [최소 앱 iOS 26 성공·BlueWallet v8 실패](./rn-baseline-212-attempt-02.md)를 유지한다.

## 선정과 source

공식 정식 [Mattermost Mobile release-2.44](https://github.com/mattermost/mattermost-mobile/releases/tag/release-2.44) 하나를 선언 근거로 선정했다.
tag SHA는 `c2fe3beda22befd2178dce431793c09111ed903e`다.
같은 이름의 branch는 이 tag와 다르다. tag SHA를 사용했다.
앱 버전은 `2.44.0`, license는 Apache-2.0이다.
RN `0.83.9`, Expo `55.0.23`과 원본 양플랫폼 native project를 사용한다.
원본 iOS 설정은 RN·Expo from-source와 new architecture를 선언한다.
공식 CI는 npm hook을 분리한다.
원본 첫 화면은 계정 없이 사용하는 Server 선택 form이다.
이 선언을 known-good 성공으로 간주하지 않는다.

검증 root는 `/Volumes/P41_USB4/Developer/validation/runstir-212-rn-baseline-20261010/attempt-03-mattermost`다.
공식 origin에서 `mattermost-source`와 `mattermost-fresh`를 별도로 clone했다.
두 clone은 같은 tag SHA다.
준비 전에 tracked 파일 4,216개의 SHA-256을 각각 고정했다.
fresh clone에는 준비·빌드·실행을 수행하지 않았다.
baseline dependency·Pods·build·앱 데이터를 fresh clone으로 복사하지 않았다.

## 선언 도구와 준비

기존 host macOS `27.0.1 (26A434)`와 Xcode `27.0 (27A266a)`를 유지한다.
원본 `.nvmrc`·`.node-version`의 Node `24.15.0`을 기존 설치에서 재사용했다.
실효 bundled npm은 `11.12.1`이다. 원본 engine은 npm `^10 || ^11`이며 exact patch를 선언하지 않는다.
원본 `.ruby-version`의 Ruby `3.2.11`도 기존 설치에서 재사용했다.
Bundler `2.5.11`, CocoaPods `1.16.1`, xcodeproj `1.27.0`을 원본 Gem lock대로 설치했다.
Bundle 준비는 `BUNDLE_FROZEN=true BUNDLE_PATH=<source>/vendor/bundle bundle _2.5.11_ install`이다.
local Bundle config나 전역 선택을 변경하지 않았다.

공식 CI의 Temurin JDK `17` 선언은 exact patch를 고정하지 않는다.
기존 Temurin 17 설치가 없었다.
[Adoptium 공식 GA](https://adoptium.net/temurin/releases/?version=17&os=mac&arch=aarch64&package=jdk)의 `17.0.20.1+1`을 나란히 설치했다.
mise identity는 `java@temurin-17.0.20+101`이다.
실제 `java -version`은 `Temurin-17.0.20.1+1`이다.
공식 macOS ARM64 archive는 `OpenJDK17U-jdk_aarch64_mac_hotspot_17.0.20.1_1.tar.gz`, 185,851,019 bytes다.
공식 API가 선언한 SHA-256은 `196d13ba5f10414bef7f6a05a9b3f00edacb18ebacef2b99485db9e2ee18f0e8`다.
전역 mise 활성화·PATH 변경·관리자 권한·새 라이선스 동의를 수행하지 않았다.

원본 [prepare-node-deps](https://github.com/mattermost/mattermost-mobile/blob/c2fe3beda22befd2178dce431793c09111ed903e/.github/actions/prepare-node-deps/action.yaml)의 다음 단계를 수행했다.

1. `NODE_ENV=development npm ci --ignore-scripts`를 실행한다.
2. 원본 `node_modules/@sentry/cli/scripts/install.js`를 실행한다.
3. 설치된 원본 `patch-package`를 실행한다.
4. 원본 `scripts/generate-assets.js`를 실행한다.
5. 원본 compass font를 선언한 두 ignored font 경로에 복사한다.
6. 원본 `scripts/generate-compass-glyph-map.mjs`를 실행한다.

원본 postinstall의 sounds copy 부분도 ignored Android `res/raw`에 수행했다.
원본 Android CI의 `jetify`를 node_modules에 수행했다.
일반 npm preinstall·postinstall의 non-frozen Gem·Pod 단계는 실행하지 않았다.
원본 dependency patch 외 추가 patch를 만들지 않았다.
이 준비와 frozen Pods 실패 뒤에도 tracked 파일 4,216개의 byte가 같았다.

## iOS frozen 준비 실패

실제 명령은 `RCT_NEW_ARCH_ENABLED=1 BUNDLE_FROZEN=true BUNDLE_PATH=<source>/vendor/bundle mise exec ruby@3.2.11 node@24.15.0 -- bundle _2.5.11_ exec pod install --deployment`다.
명령은 exit `1`이다.
dependency graph와 다른 spec checksum은 달라지지 않았다.
`hermes-engine` 하나만 다음 차이를 보고했다.

| 원본 lock SHA-1 | 실제 Local Podspec SHA-1 |
| --- | --- |
| `28814c9c9296d16aef26cb514de5378d18885e44` | `b25a74331dcb8f58ede30887262c71629246d013` |

실제 Hermes spec은 version `0.14.1`과 공식 Maven `hermes-ios-debug.tar.gz`를 선언한다.
플랫폼은 iOS `15.1`, macOS `10.13`, tvOS `15.1`, visionOS `1.0`이다.
`user_target_xcconfig.HERMES_CLI_PATH`는 실행 clone 아래 `node_modules/hermes-compiler/hermesc/osx-bin/hermesc`의 절대 경로다.
실제 JSON의 SHA-1은 오류에 보고한 새 checksum과 일치한다.
메모리에서 clone 경로 문자열만 다른 fresh 경로로 바꾸면 SHA-1은 `8ebf8a508120f75fd20fdd5ea5d2f7b7a0177e23`으로 바뀐다.
파일을 변경하지 않았다.
Codegen의 상대 경로 선언은 이 Hermes 절대 경로 문제를 해결하지 않는다.

상위 실행 환경의 RN prebuilt·framework·Hermes·Intune override는 없었다.
명령은 원본 new architecture 선택 `RCT_NEW_ARCH_ENABLED=1`만 명시했다.
원본 lock은 원본 serialized Hermes spec과 생성 경로를 제공하지 않는다.
따라서 원본 checksum의 정확한 필드 차이를 역산할 수 없다.
임의 fresh clone 경로의 원본 checksum 동일성을 보장하지 못한다.
원본 lock 재작성·checksum 예외·source patch·flag 변경으로 성공을 탐색하지 않았다.
iOS build·install·launch·첫 화면을 수행하지 않았다.

## 남은 입력과 정책 경계

원본 lock byte와 frozen 준비를 동시에 요구하는 현재 정책에서 OSS iOS known-good은 미달이다.
Mattermost의 실제 원본 준비 실패를 Runstir 실패로 분류하지 않는다.
추가 SHA나 후보의 빌드 성공을 탐색하지 않는다.
원본 checksum 생성 provenance를 제공하거나 경로 의존 checksum 처리 정책을 별도로 결정해야 한다.
정책 변경은 dependency version·graph 변경이나 source 변경과 구분해야 한다.
현재 실행은 그 예외를 승인하거나 적용하지 않는다.

## Android 실제 결과와 정리

기존 Pixel API 37 Google Play ARM64 revision 6을 software·headless 조건으로 사용했다.
기존 `com.mattermost.rnbeta` 설치가 없는 것을 확인했다.
`./gradlew :app:assembleDebug -PreactNativeArchitectures=arm64-v8a`는 12분 33초에 성공했다.
902 tasks를 실행했다. 223 tasks는 Gradle cache에서 재사용했다.
HTTP 의존성 준비 뒤 native 컴파일을 수행했다. timeout 실패는 없었다.
APK는 128,477,303 bytes다. 실제 포함 ABI는 `arm64-v8a` 하나다.
SHA-256은 `cf92d7198ec9a1b6122c53364ad592ca817386c2e829a9fcf16c7a160f397365`다.
install은 성공했다. COLD launch는 7,192ms, wait는 7,196ms다.
PID `3899`가 JS bundle 뒤에도 생존했다.
새 앱의 알림 권한 질문에서 `Don’t allow`를 선택했다.
[첫 화면](./evidence/212/attempt-03/android-first.png)은 Connect to your server·빈 Server URL·Display Name form과 App Version 2.44.0 (Build 814)을 표시했다.
서버·계정 입력과 로그인은 수행하지 않았다.
PNG SHA-256은 `b4f6eaaf000273bd9818fb39e5e9f144bd2618f361d428741038241eb1ef84eb`다.
실행 뒤에도 source와 fresh clone의 tracked 파일 byte가 같았다.

자기 앱을 force-stop하고 자기 adb reverse를 제거했다.
자기 Emulator·Metro·새 Gradle daemon을 종료했다.
이번 작업이 만든 iOS 26 Simulator만 shutdown했다.
초기 두 iOS 27 Simulator는 Booted 상태를 유지했다. 기존 GUI PID 98365도 유지했다.
adb 기기와 8081 listener는 남지 않았다.
원본 AVD 데이터·runtime 설치·기기 정의·앱 설치·로컬 도구는 보존했다.

## 원본 인계 명령

`APP_ROOT`, `SDK_ROOT`, `EVIDENCE_ROOT`, 기기 identity를 먼저 고정한다.
원본 `prepare-node-deps`의 자원 생성 단계는 위 순서를 적용한다.

```sh
git clone https://github.com/mattermost/mattermost-mobile.git mattermost-fresh
git -C mattermost-fresh checkout --detach c2fe3beda22befd2178dce431793c09111ed903e
# app root, .nvmrc와 .ruby-version을 유지한다.
NODE_ENV=development mise exec node@24.15.0 -- npm ci --ignore-scripts
BUNDLE_FROZEN=true BUNDLE_PATH="$APP_ROOT/vendor/bundle" \
  mise exec ruby@3.2.11 node@24.15.0 -- bundle _2.5.11_ install
# ios root. 현재 후보는 이 frozen 단계에서 Hermes checksum 차이로 중단한다.
RCT_NEW_ARCH_ENABLED=1 BUNDLE_FROZEN=true BUNDLE_PATH="$APP_ROOT/vendor/bundle" \
  mise exec ruby@3.2.11 node@24.15.0 -- bundle _2.5.11_ exec pod install --deployment
# android root. 원본 lockfile을 갱신하지 않는다.
ANDROID_HOME="$SDK_ROOT" ANDROID_SDK_ROOT="$SDK_ROOT" \
  mise exec node@24.15.0 java@temurin-17.0.20+101 -- \
  ./gradlew :app:assembleDebug -PreactNativeArchitectures=arm64-v8a
```

정확 locks·도구·실제 first screen·원본 hook 로그 checksum은 [manifest](./evidence/212/attempt-03/manifest.json)에 연결한다.
이 인계는 실제 fresh clone 실행 성공을 의미하지 않는다.

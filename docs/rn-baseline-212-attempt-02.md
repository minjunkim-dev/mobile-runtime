# RN baseline attempt-02 — iOS 26 입력

상태: 최소 앱 양플랫폼 확인. OSS iOS 미달. #212 완료가 아니다.
검증일은 2026-10-10이다. Runstir를 사용하지 않았다.
[최초 attempt](./rn-baseline-212.md)의 iOS 27 crash와 BlueWallet 원본 lock 실패를 보존한다.

[사용자 tuple 확정](https://github.com/minjunkim-dev/mobile-runtime/issues/212#issuecomment-6092021206)을 적용한다.
같은 host·기기 조건에서 표본별 선언 버전을 유지한다.
각 표본의 baseline과 후속 Runstir 실행은 그 표본의 같은 tuple을 사용해야 한다.
표본 간 RN·Ruby·CocoaPods·Gradle 버전 차이는 허용한다.

## 입력과 경계

host는 기존 macOS `27.0.1 (26A434)`, Xcode `27.0 (27A266a)`다.
Node `22.23.2`, npm `10.9.8`, Zulu JDK `17.0.19+10`과 기존 Android SDK를 유지한다.
최소 앱 source는 `b62e3a4d5e7cfc05d7d948a5a4e30f0cc6a82bb4`다.
최소 앱의 Ruby `3.4.11`, Bundler `2.5.22`, CocoaPods `1.15.2`, xcodeproj `1.25.1`을 유지한다.

OSS 후보는 공식 정식 [BlueWallet v8.0.2](https://github.com/BlueWallet/BlueWallet/releases/tag/v8.0.2) 하나다.
source는 `a7fe068709b0f91c504b28accda8bc85ee4c3714`다.
선언상 JS·Pod의 lottie `7.4.0`, safe-area `5.8.1`이 일치하므로 선택했다.
성공한 SHA를 찾는 탐색을 수행하지 않았다.
기존 Ruby `3.4.10p104`, Bundler `2.6.9`, CocoaPods `1.17.0`, xcodeproj `1.28.1`을 사용한다.
RN `0.85.3`, Gradle `9.3.1`, AGP `8.13.2`, NDK `28.2.13676358`을 유지한다.
`npm ci`와 frozen Bundle 준비는 성공했다.
원본 source·Gemfile·lockfile을 변경하지 않았다.

전용 검증 경로는 `/Volumes/P41_USB4/Developer/validation/runstir-212-rn-baseline-20261010/attempt-02-ios26`이다.
`bluewallet-source`는 실행 clone이다. `bluewallet-fresh`는 실행하지 않은 같은 SHA clone이다.
fresh clone에 dependency·Pods·build·앱 데이터를 복사하지 않았다.

## Android 관측

두 표본은 같은 기존 AVD `Pixel_10_API_37_Play`를 순차 사용했다.
Emulator `37.1.11`, API 37 Google Play ARM64 revision 6을 유지했다.
이번 invocation은 `-gpu software -no-window -no-metrics -crash-report-mode disabled`를 명시했다.
snapshot 저장·불러오기를 비활성화했다. AVD 초기화·삭제는 수행하지 않았다.
앞선 auto GPU boot는 Vulkan 메모리 할당 실패로 종료했다.
다음 software boot는 crash report 질문으로 진행하지 못했다.
공식 CLI 도움말로 질문을 비활성화한 같은 AVD 재시도에서 boot가 완료됐다.
이 준비 실패를 앱 실패로 분류하지 않는다.

| 표본 | build | install / launch | 첫 화면 |
| --- | --- | --- | --- |
| 최소 | 9초. 8 executed, 74 up-to-date. 기존 baseline 산출물 재사용 | install -r 성공. COLD 658ms / wait 660ms. PID 6475 | Welcome to React Native, RN 0.87.1, Hermes 250829098.0.17 |
| BlueWallet v8 | 2분 19초. 981 tasks. arm64-v8a Debug | install -r 성공. COLD 3603ms / wait 3604ms. PID 6237 | Wallets, Add a wallet, 빈 Transactions |

최소 APK SHA-256은 `ea625a29a21df8348c113d817020311059f523c4e4f277505abcf8534623b3d3`다.
v8 APK는 47,148,972 bytes다.
v8 APK SHA-256은 `529c6c145c888386167b62a167f4550a941d6a3d2d8f92b09f6437181bcf09b6`다.
v8 package identity는 `io.bluewallet.bluewallet`, versionName `8.0.2`, versionCode `1`이다.
이전 attempt가 설치한 빈 지갑 앱만 `install -r`로 교체했다.
지갑·키·거래 데이터를 생성하지 않았다.
v8의 첫 JS bundle 대기 뒤 PID 4245는 관측되지 않았다.
같은 설치·source를 data reset 없이 재실행하고 PID 6237과 첫 화면을 확인했다.
전체 raw 로그는 로컬에 보존한다.

## v8 iOS frozen Pods 실패

`BUNDLE_FROZEN=true mise exec ruby@3.4.10 node@22.23.2 -- bundle exec pod install --deployment`는 exit 1이다.
이번 오류는 dependency version drift 없이 네 SPEC CHECKSUMS 차이를 보고했다.

| spec | 원본 lock SHA-1 | 실제 spec SHA-1 |
| --- | --- | --- |
| hermes-engine | `86cdbf283775c54dc008895c3eacd24a1f2a40b4` | `c8eb285cb5de59527128fd84565bb5fdeb0d3e6b` |
| React-Core-prebuilt | `9e875134f667c471ab68bf9edf1661fa11b86540` | `97bd92bb9a514bf57d19f8c8898bc6f252a7cc8f` |
| ReactCodegen | `d9475a746f5735bf5e403a1e25e451306ebaae8b` | `1bd7f2174582b0e142f8671735b5c906c08b72ea` |
| ReactNativeDependencies | `0a5c93845772e4b1c5ad065c59a859518b13a6b7` | `c663911f9900d7f0482d7c4d5e6c8c27c9dba9b9` |

`ios/Pods/Local Podspecs/*.podspec.json`의 실제 SHA-1은 오류의 새 checksum과 일치한다.
Hermes spec은 clone의 절대 `hermesc` 경로를 포함한다.
React-Core-prebuilt와 ReactNativeDependencies의 `source.http`는 clone 아래 artifact의 절대 `file://` 경로다.
실제 spec bytes를 메모리에서만 읽고 clone 경로 문자열만 바꾸면 세 checksum도 바뀐다.
실제 spec 파일을 변경하지 않았다.
따라서 임의의 fresh clone 경로에서 checksum 동일성이 자동으로 유지되지 않는다.

ReactCodegen은 절대 경로를 포함하지 않는다.
선언 dependency graph와 RN version은 원본 lock과 일치한다.
원본 네 spec JSON과 생성 환경은 tag에 없다.
checksum에서 원본 JSON 필드나 원본 환경을 역산할 수 없다.
경로 차이로 네 차이를 모두 설명했다고 주장하지 않는다.

상위 실행 환경의 `RCT_USE_PREBUILT_RNCORE`, `RCT_USE_RN_DEP`, `USE_FRAMEWORKS`, `NO_FLIPPER`, `RCT_NEW_ARCH_ENABLED`, `USE_HERMES`, `RCT_HERMES_V1_ENABLED`는 모두 없었다.
환경 값은 출력하지 않았다.
flag 변경·lock 재작성·source patch로 성공을 탐색하지 않았다.
v8 iOS build·install·launch·첫 화면은 수행하지 않았다.
원본 spec provenance 또는 별도 승인한 재현 정책·OSS 입력이 필요하다.

## 준비 입력 정정 이력

처음 local clone의 promisor 설정 누락으로 19개 tracked 파일을 checkout하지 못했다.
같은 SHA의 공식 origin에서 누락 blob을 받았다.
원본 index·source SHA·tracked byte를 확인한 뒤 `npm ci`가 성공했다.
앞선 npm 실패를 upstream lock 누락으로 분류하지 않는다.

`bundle install --deployment`는 tracked `.bundle/config`를 변경했다.
이 명령이 만든 config 차이만 원본 SHA byte로 복구했다.
차이와 전후 checksum은 로컬에 보존했다.
이후 `BUNDLE_FROZEN=true`로 config 쓰기 없이 실행했다.
다른 tracked 파일을 복구하지 않았다.

동일 공식 RN 0.85.3 prebuilt debug·release archive만 전용 download cache로 재사용했다.
URL·version·content checksum을 비교했다.
dependency·Pods·build tree를 복사하지 않았다.

## iOS 26 runtime 설치와 검증 순서

공식 Xcode 입력은 iOS `26.0`, build `23A343`, arm64다.
공식 MobileAsset archive는 7,985,954,816 bytes, SHA-1 `ca08c03cee60164e018953dd6141c87dd4e0635b`를 선언한다.
`xcodebuild -downloadPlatform iOS -buildVersion 26.0 -architectureVariant arm64 -exportPath <전용 runtime 경로>`는 다운로드·자동 설치·export를 완료했다.
`-exportPath`를 설치와 분리된 다운로드로 해석한 실행 준비 오류를 보존한다.
실제 checksum 검증은 자동 설치 뒤에 수행했다. 설치 전 검증을 했다고 주장하지 않는다.
별도 import나 runtime 제거를 수행하지 않았다.
export는 `.aar` 원본이 아니라 `iphonesimulator_26.0_23A343.exportedBundle`의 일곱 파일이다.
내부 `Restore/043-92413-002.dmg`는 8,014,773,567 bytes다.
export와 설치된 DMG의 SHA-256은 모두 `19252564d65ab92616c299ca817f7358d037c1c34628f5e76355cddb90175614`다.
공식 exported BuildManifest의 `sha2-384` digest와 실제 DMG SHA-384도 일치한다.
이 값은 `790b50513c28a4728004580b512384363acce81e04c6ce5ec4a6432e58c7ae172715f268882f6bb6a03bd3f27777b964`다.
공식 `.aar` SHA-1과 다른 형식인 DMG checksum을 직접 비교하지 않았다.
원본 AAR는 exporter가 보존하지 않았다. AAR 자체 SHA-1을 검사한 증거는 없다.
설치 후 host free space는 23,485,394,944 bytes다. 외부 볼륨은 1,478,022,787,072 bytes다.
새 전용 iPhone 16 Pro의 UDID는 `BEAB5D23-2F3D-4EC0-80AD-2892B9F42BE6`다.
초기 두 iOS 27 Simulator는 Booted 상태를 유지했다. 기존 GUI PID 98365도 유지했다.
서비스 재시작이나 초기 기기 shutdown 요구는 없었다.
최소 앱은 같은 source와 새 DerivedData에서 `BUILD SUCCEEDED`를 반환했다.
기존 baseline Pods와 공식 prebuilt archive는 재사용했다. clean-host 빌드 증거는 아니다.
`simctl install` exit 0과 `simctl launch` exit 0 뒤 PID `40994`의 생존을 확인했다.
새 iOS 26 Simulator에서 Welcome to React Native·RN `0.87.1`·Hermes `250829098.0.17` 첫 화면을 확인했다.
[첫 화면](./evidence/212/attempt-02/minimal-ios-first.png)의 SHA-256은 `dbf3bfdb191d7f644529a2ad09a4b939f0e65f11d48c1e9037cadcf8ce2921ff`다.
최소 iOS app zip은 13,792,934 bytes다. SHA-256은 `e691844f3a97e4cba908fdfbd75b089482d00bcc00470fb90b54edfb93738806`다.
직접 외부 볼륨 screenshot 쓰기는 EPERM으로 실패했다. `/tmp` 출력 뒤 전용 검증 경로로 복사했다.
최소 앱은 이 새 tuple에서 양플랫폼 known-good을 충족한다.
BlueWallet v8은 원본 frozen Pods 실패로 양플랫폼 known-good을 충족하지 않는다.

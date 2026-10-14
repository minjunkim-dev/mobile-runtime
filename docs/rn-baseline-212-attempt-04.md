# RN prepared input baseline attempt-04 — Mattermost Mobile

상태: **준비와 frozen 검사 성공. iOS build 실패. #212 미완료.**
검증일은 2026-10-10이다. Runstir를 사용하지 않았다.
[ADR-0020](./adr/0020-rn-baseline-prepared-input.md)의 제한 정책을 적용했다.
[attempt-03의 원본 checksum 실패](./rn-baseline-212-attempt-03.md)와 모든 이전 증거를 유지한다.

## 입력과 감사 경계

baseline source는 공식 Mattermost Mobile tag `release-2.44`의 `c2fe3beda22befd2178dce431793c09111ed903e`다.
새 공식 origin clone을 사용했다.
앱 소스·버전·dependency graph·source 선언을 변경하지 않았다.
허용한 tracked 변경은 `ios/Podfile.lock`의 `SPEC CHECKSUMS.hermes-engine` 값 하나다.
원본 serialized spec은 미확인이다. 원본과의 차이가 경로뿐이라고 주장하지 않는다.

초기 일반 tracked 파일·symlink 4,216개와 Intune gitlink 하나를 감사했다.
모든 Git index entry는 원본 HEAD와 같았다.
`assume-unchanged`와 `skip-worktree`는 없었다.
원본 `.gitattributes`는 `*.bat text eol=crlf`를 선언한다.
`android/gradlew.bat`의 HEAD blob은 LF 2,843 bytes다.
원본 checkout은 CRLF 2,937 bytes이며 선언에 따른 결과와 정확히 같다.
초기 canonical 대응과 원본 checkout raw hash를 각각 검사했다.
준비 뒤에는 초기 checkout raw byte를 보존했다.
Hermes 한 값만 메모리에서 정규화한 lock 전체는 원본과 같다.

첫 감사 helper는 선언한 CRLF checkout을 raw HEAD blob과 직접 비교하여 FAIL을 보고했다.
root의 독립 검사도 symlink를 따라가서 Kotlin 파일의 불일치를 잘못 보고했다.
해당 mode `120000`의 링크 문자열은 HEAD blob과 정확히 같다.
두 결과는 감사 진단 오류다. source 변경이나 앱 실패가 아니다.
최초 helper·FAIL 결과·EOL byte·symlink 진단을 로컬에 보존했다.
수정한 `audit-v2.py`는 초기 감사와 준비 뒤 감사를 통과했다.
메모리 self-check는 Hermes 한 값의 변경을 허용한다.
다른 checksum·버전·추가 tracked 파일·준비 뒤 EOL·`.gitattributes` 변경을 모두 거부했다.
source와 Git 설정을 복구하거나 수정하지 않았다.

## tuple과 독립 준비

host는 macOS `27.0.1 (26A434)` arm64다. Xcode는 `27.0 (27A266a)`다.
표본별 선언 tuple을 [확정한 조건](https://github.com/minjunkim-dev/mobile-runtime/issues/212#issuecomment-6092021206)대로 유지했다.
Node `24.15.0`, npm `11.12.1`, Ruby `3.2.11`, Bundler `2.5.11`을 사용했다.
CocoaPods `1.16.1`, xcodeproj `1.27.0`, RN `0.83.9`, Expo `55.0.23`을 유지했다.
Android 선언은 Temurin `17.0.20.1+1`, Gradle `9.0.0`, AGP `8.12.0`, SDK·Build Tools `36`, NDK `27.1.12297006`이다.
이 attempt에서는 Android build를 수행하지 않았다.

1. `NODE_ENV=development npm ci --ignore-scripts`를 실행했다. exit `0`이다.
2. 원본 CI의 Sentry 설치·patch-package·assets·font·glyph 준비를 실행했다. 모두 exit `0`이다.
3. 원본 sounds copy와 jetify를 실행했다. 모두 exit `0`이다.
4. `BUNDLE_FROZEN=true BUNDLE_PATH=<baseline-root>/vendor/bundle`로 원본 Bundler 설치를 실행했다. exit `0`이다.
5. 원본 from-source·new architecture 조건에서 plain `pod install`을 실행했다. exit `0`이다.
6. Hermes 한 값 외의 byte와 index를 감사했다. PASS다.
7. 같은 조건으로 `pod install --deployment`를 실행했다. exit `0`이다.
8. frozen 검사 뒤와 build 실패 뒤에 byte와 index를 다시 감사했다. 모두 PASS다.

Pod 명령은 `TMPDIR=/tmp`, `RCT_NEW_ARCH_ENABLED=1`, frozen Bundler를 사용했다.
전용 `CP_CACHE_DIR`을 사용했다. 다른 clone의 Pods·node_modules·빌드를 복사하지 않았다.
별도로 검증한 다운로드 archive를 이번 attempt에 수동 재사용하지 않았다.
정확한 명령·종료 상태·raw 로그 hash는 [manifest](./evidence/212/attempt-04/manifest.json)에 기록한다.

| 입력 | SHA |
| --- | --- |
| 원본 Hermes checksum | `28814c9c9296d16aef26cb514de5378d18885e44` |
| 준비 Hermes checksum·실제 spec SHA-1 | `62383905fde533671dca54d2eefc9611977fe593` |
| 원본 Podfile.lock SHA-256 | `64d1d50255e98c08f7722481629507a568e6f4efbce551344b658fe2d8f3ef1b` |
| 준비 Podfile.lock SHA-256 | `19c91cb4e61822f857e4a56e7501a06222caa471e4f1091838b8a9e1f434c117` |

준비 입력은 source SHA·정책·tuple·준비 절차·실제 lock/spec hash로 별도 식별한다.
이 준비 성공을 원본 frozen 준비 성공으로 대체하지 않는다.

## iOS build 실패와 중단

`Mattermost` scheme, `Debug`, Simulator SDK `27.0`을 사용했다.
destination은 기존 전용 iPhone 16 Pro의 iOS `26.0 (23A343)`이다.
새 외장 DerivedData, `CODE_SIGNING_ALLOWED=NO`, `-jobs 6`을 사용했다.
`RCT_NO_LAUNCH_PACKAGER=1`은 자동 Metro 창 실행을 막는다.
앱 코드·Pods deployment target을 보정하지 않았다.

build는 19:05:37에 시작했다. 19:05:48에 exit `65`로 끝났다.
로그는 `ComputeTargetDependencyGraph`와 `CreateBuildDescription`을 기록했다.
첫 error는 raw 로그 line `2462`의 `RNSVG-RNSVGFilters`다.
이 target의 deployment target `12.4`는 Xcode 27의 허용 범위 `15.0`–`27.0.x` 밖이다.
동일한 deployment 검사가 아래 11개 target을 거부했다.
`CompileC`·`SwiftCompile`·`SwiftEmitModule`·`PhaseScriptExecution`·`CompileAssetCatalog` action은 관측하지 못했다.
build description 생성 중 도구 정보 조회는 있었다. 소스 compile 성공 증거는 없다.

| Pods target | deployment target |
| --- | --- |
| RNSVG-RNSVGFilters | 12.4 |
| SDWebImage-SDWebImage | 9.0 |
| CocoaLumberjack-CocoaLumberjackPrivacy | 11.0 |
| ratex-react-native-RaTeXFonts | 14.0 |
| SwiftyJSON-SwiftyJSON | 12.0 |
| Starscream-Starscream_Privacy | 12.0 |
| RNPermissions-RNPermissionsPrivacyInfo | 12.4 |
| SQLite.swift-SQLite.swift | 12.0 |
| react-native-cameraroll-RNCameraRollPrivacyInfo | 9.0 |
| Alamofire-Alamofire | 10.0 |
| react-native-image-picker-RNImagePickerPrivacyInfo | 9.0 |

iOS install·launch·첫 화면은 미실행이다.
필수 build 실패 뒤 새 Android build·install·launch·첫 화면과 fresh dependency 준비를 중단했다.
attempt-03의 Android PASS를 이 새 준비 입력으로 승계하지 않는다.
추가 checksum·source patch·deployment 보정·버전·우회 flag 변경은 없다.
이 실패는 Runstir 실패가 아니다. 현재 표본·Xcode tuple의 baseline build 실패다.

## fresh clone과 최소 앱 인계 상태

attempt-04의 후속 `mattermost-fresh`는 공식 origin에서 `--no-checkout`으로 clone했다.
선정한 candidate object는 `c2fe3beda22befd2178dce431793c09111ed903e`다.
clone의 실제 HEAD는 기본 branch의 `e216404659b7bba5fdcb9e7936efd054f1142d87`다.
index는 비어 있다. candidate checkout·dependency 준비·frozen 검사·인계를 완료하지 않았다.
baseline과 독립한 fresh 준비 성공을 주장하지 않는다.

최소 앱 source와 기존 fresh의 HEAD를 `b62e3a4d5e7cfc05d7d948a5a4e30f0cc6a82bb4`로 다시 확인했다.
두 clone의 JS·Gem·Pod lock hash가 각각 같다. tracked diff도 없다.
기존 source bundle과 attempt-02의 양플랫폼 첫 화면 증거는 유지한다.
최소 앱 fresh에는 node_modules·Pods가 없다. fresh frozen 준비 재현은 미검증이다.
Mattermost 필수 실패 뒤 최소 앱의 새 실행으로 성공을 추가 탐색하지 않았다.
실제 Runstir 제품 실행은 후속 gate의 범위다.

## 자원 보존과 판정

이번 attempt는 Simulator·Emulator·Metro·Gradle을 띄우지 않았다.
전용 iOS 26 기기는 Shutdown 상태다.
초기 iOS 27 두 기기는 Booted 상태를 유지했다. 기존 GUI PID `98365`도 생존했다.
8081 listener·adb 기기·qemu·이번 xcodebuild 프로세스는 남지 않았다.
전역 PATH·Xcode·도구 선택·SDK·runtime·AVD 데이터와 기존 앱을 변경하지 않았다.
새 라이선스 동의는 없다. exclusive 실행 lease를 반납했다.

#212는 OPEN이다. PR #236은 부분 증거이며 이 attempt로 병합 조건을 충족하지 않는다.
현재 준비 정책은 deployment target 보정을 허용하지 않는다.
새 결정 없이 현재 입력으로 다음 실행을 진행하지 않는다.

# RN baseline attempt-22 — iOS 첫 화면과 Simulator 서명

상태: **두 표본의 iOS 첫 화면을 확인했다. attempt-21의 Android 두 첫 화면과 연결한다. 두 fresh clone의 독립 준비와 최종 입력 감사를 통과했다. 최종 리뷰·CI와 병합은 별도 조건이다.**

2026-10-23에 [attempt-21](rn-baseline-212-attempt-21.md)의 준비 입력과 빌드 산출물을 전용 사본으로 이어받았다. 이 사본은 fresh 준비 증거가 아니다. Runstir를 사용하지 않았다. [ADR-0046](adr/0046-rn-baseline-direct-execution.md)의 직접 실행과 사용자 승인 Simulator 로컬 서명 범위를 적용한다.

## 실제 확인

- macOS `27.0.1 (26A434)`, Xcode `27.1 (27A9275)`, iPhone 16 Pro 타입의 전용 private device set, iOS `26.0 (23A343)`를 사용했다. 다른 세션의 기존 Simulator는 변경하지 않았다.
- 최소 RN 원본 source `b62e3a4d5e7cfc05d7d948a5a4e30f0cc6a82bb4`, RN `0.87.1`, Node `22.23.2`를 유지했다. 원본 Metro의 HTTP `packager-status:running`과 listener의 사본 cwd를 확인했다. install·launch가 성공했고 process 생존과 Welcome to React Native 첫 화면을 관측했다. 화면은 RN `0.87.1`, Hermes `250829098.0.17`을 표시했다.
- 최소 RN 실행 파일 SHA-256은 `4ebe81608fea3465261d2e741adb56909d20e8e24c2436f5bccfc7543a404c1f`, 첫 화면 PNG는 `c5163c4bdeb25efc1eeee033d84dac4fcda92db87b4b320d1d34b5de536b3313`다. [실제 화면](evidence/212/attempt-22/minimal-ios-first.png).
- Mattermost source `c2fe3beda22befd2178dce431793c09111ed903e`, RN `0.83.9`, Node `24.15.0`를 유지했다. 기존 unsigned 앱은 install·launch 요청 뒤 첫 실행에서 SIGABRT로 종료됐다. stack은 `RNKeychainManager.getAllServersForInternetPasswords` → `AppDelegate.swift:99`, securityd는 application-identifier/keychain-access-groups 누락과 `-34018`을 기록했다. 첫 화면 실패다.

## 실패를 보존한 후속 실행

1. 사용자의 Simulator 전용 로컬 서명 승인 뒤, 사본 앱에 원본 entitlement의 변수 값을 펼쳐 ad-hoc 서명한 진단은 codesign verify와 설치가 성공했다. 실행은 AMFI `-424`, `The file is adhoc signed but contains restricted entitlements`로 거부됐다. 이 수동 재서명은 Xcode Simulator 빌드 결과나 첫 화면 성공이 아니다. 시스템 보안 설정·원본 entitlement·사용자 기기를 바꾸지 않았다.
2. 사본의 생성 Expo script에 원본 경로의 쓰기 대상이 남아 있어 원본 npm `pod-install` 명령으로 다시 생성했다. Ruby `3.2.11`, Bundler `2.5.11`, CocoaPods `1.16.1`, frozen Bundle과 `--deployment`로 성공했다. 최초 직접 pod 호출이 원본 npm의 `RCT_NEW_ARCH_ENABLED=1`을 빠뜨린 실패는 실행 절차 오류로 보존했다.
3. ADR-0021·0023의 Debug 12개 값만 다시 준비했다. raw text의 12값 역치환이 준비 전과 같음을 확인했다. Expo 쓰기 대상은 모두 사본 경로다. 캐시된 Hermes spec의 compiler 경로는 원본의 읽기 전용 실행 파일을 가리키며 사본 compiler와 SHA-256 `5255e887b542711cc94244d75f59a4351c15ccdfddbeaa12e4a434f7a110cf62`가 같다. 이것은 독립 fresh 입력이라고 주장하지 않는다.
4. private device set은 Xcode 목적지 목록에 없었다. generic iOS Simulator와 `ARCHS=arm64`, `CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`를 선택했다. 최초 `-arch arm64`와 destination을 함께 쓴 호출은 Xcode 인자 오류 exit70으로 컴파일 전에 중단됐다. 인자 표기 오류로 보존했다.

로컬 원본에는 명령·종료 코드·실패 로그·화면·도구와 기기 identity를 남겼다. 실제 경로와 기기 식별자는 공개 기록에서 제외한다. 공간 부족 중에는 새 준비를 시작하지 않았고, Xcode 빌드 직전 내장 Data 여유 `37.57 GiB`를 확인했다.

## Xcode 로컬 서명 결과

`xcodebuild`는 exit0, `BUILD SUCCEEDED`였다(run `db6dfcc8155b449793e558fed50b7ce1`). Xcode는 일반 서명의 빈 entitlement와 `*-Simulated.xcent`의 Simulator entitlement를 분리했다. 설치·실행 exit0 뒤 앱 process 생존과 [서버 접속 첫 화면](evidence/212/attempt-22/mattermost-ios-first.png)을 확인했다. 최초 알림 권한 창이 겹쳐 있지만 서버 접속 제목과 앱 버전 `2.44.0 (814)`가 실제 렌더링됐다. 알림 허용·거부, 서버 URL 입력, 계정 로그인은 수행하지 않았다.

| 산출물 | SHA-256 |
| --- | --- |
| Mattermost Simulator 실행 파일 | `c05a01edcfef27dd709b1be591ae692042433cb4440987cf080d066c56181c90` |
| Mattermost.debug.dylib | `a659ad8b73a053515bcd7d92b1a69a4775759028dcca973ec622219a6bbd2b46` |
| Mattermost 첫 화면 PNG | `97a942386082e41278e5c1b042ab57f3a2709a506a61273471b13a4baff0b299` |

설치·실행 run `eea38b09d6274cb3a0af03432d74f60c`, 화면·process run `6817fb5f4f8040caa8cc3dff920cc0f8`다. 이후에도 process가 생존함을 확인하고 앱과 소유 Simulator를 정상 종료했다(run `27267efa44594051833e77997ab7468c`). 소유 Metro도 종료했다. XcodeBuildMCP의 AX 도구는 private device set을 찾지 못했으며, 이를 앱 실패로 분류하지 않았다. 실제 `simctl --set` 화면과 process가 첫 화면 근거다.

## baseline 실행 뒤 입력 감사

첫 화면·정상 종료 뒤 원본 사본에 읽기 전용 전체 사후 감사를 수행했다(run `807d10afedc14803a75594cc9d40cd9b`, exit0). 최소55개와 Mattermost4,216개 tracked 파일의 실제 checkout byte·파일 유형·실행 bit·index를 대조했다. 최소는 변경이 없고, Mattermost는 승인된 Hermes checksum 한 줄 외 같다. 사본의 생성 Pods project는 Debug12값을 역치환하면 전체 parsed object와 raw text가 준비 전과 같다. Release·나머지 설정도 같다.

이 사후 receipt는 실제 성공한 Mattermost 실행 파일 `c05a01edcfef27dd709b1be591ae692042433cb4440987cf080d066c56181c90`의 재해시와 연결했다. 로컬 `logs/baseline-postflight.json` 및 공개 manifest에 결과를 보존한다. fresh 사본 감사와 구분하며, 최종 상태의 비교가 실행 중 일시적 쓰기의 부재까지 증명하지는 않는다.

## 독립 fresh 준비와 인계

양플랫폼 첫 화면 뒤 새 `fresh/minimal`·`fresh/mattermost`를 준비했다. 최소 RN은 source Git object만 `git clone --no-hardlinks`로 복제하고 고정 SHA를 checkout했다. Mattermost는 공식 HTTPS origin에서 고정 SHA를 새 fetch했다. 시작 시 node_modules·vendor·Pods·Android build가 없었고 세 원본 lock이 일치했다. baseline의 dependency·Pods·빌드 산출물·앱 데이터는 복사하지 않았다. 시작 시 Data 여유는 29,987,393,536 bytes였다.

| 단계 | 최소 RN | Mattermost |
| --- | --- | --- |
| Node 준비 | Node22.23.2 `npm ci` exit0 | Node24.15.0의 원본 CI `NODE_ENV=development npm ci --ignore-scripts`, Sentry installer·patch-package·assets·compass·sounds·jetify exit0 |
| 원본 Metro | HTTP `packager-status:running`, listener cwd가 새 사본, 종료 확인 | HTTP `packager-status:running`, listener cwd가 새 사본, 종료 확인 |
| Ruby 준비 | Ruby3.4.11·clone 전용 Bundler2.5.22·frozen Bundle exit0 | Ruby3.2.11·Bundler2.5.11·frozen Bundle exit0 |
| Pods | CocoaPods1.15.2, `pod install --deployment` exit0 | CocoaPods1.16.1, 원본 `npm run pod-install` 후 `npm run pod-install -- --deployment` exit0 |
| source·index | 55 tracked 파일의 checkout byte·유형·실행 bit 동일, index 변경 없음 | 4,216 tracked 파일의 checkout byte·유형·실행 bit 동일(허용 Hermes 한 값만 정규화), index 변경 없음. 원본 미초기화 Intune gitlink 보존 |
| 생성 Pods project | 추가 보정 없음 | 최종 frozen 설치 뒤 승인된 Debug 12개 값만 변경. 전체 parsed object와 raw text 역치환 동일, Release 불변 |
| native 실행 | 수행하지 않음 | 수행하지 않음 |

최소 Bundler bootstrap은 공식 RubyGems2.5.22 archive의 SHA-256 `763f30d598ee58742eea29285875435ea722218d4df149de35bce37c02ce968e`를 metadata와 대조한 뒤 새 사본의 `vendor/bundle/tool-bootstrap`에 설치했다. global gem을 추가하지 않았다. `GEM_HOME`·`GEM_PATH`·PATH는 해당 준비 process에만 적용했다.

Mattermost의 원본 Hermes checksum `28814c9c9296d16aef26cb514de5378d18885e44`만 이 fresh 경로에서 생성된 `f1195f5308ac056f7e8fe4840abd403d5fbc763c`로 바뀌었다. 실제 Local Podspec JSON의 SHA-1과 같다. 원본 spec provenance를 복원했다거나 원본과의 차이가 경로뿐이라고 주장하지 않는다. 새 spec의 compiler 경로는 새 사본 내부다. 두 표본 모두 Pods/Manifest.lock과 준비된 Podfile.lock이 같다.

[공개 manifest](evidence/212/attempt-22/manifest.json)에 source·원본/준비 lock hash·검사 실행 ID·화면 hash를 연결했다. 원본 stdout/stderr·정확한 명령·기기 identity·실제 경로는 로컬 제한 증거에 보존한다. 두 fresh root와 로그의 실제 경로는 별도 로컬 `HANDOFF.md`에 명시한다.

### 다음 Runstir 검증에 전달하는 조건

- 공통 host는 macOS27.0.1/26A434 arm64, Xcode27.1/27A9275, iOS26.0/23A343·Android API37이다. 전용 iOS 기기는 두 표본 모두 iPhone16Pro 타입을 사용했다. Android는 attempt-21의 Pixel_10_API_37_Play tuple을 따른다. 다른 host/runtime 선택은 새 결과로 기록한다.
- 최소 RN은 Node22.23.2/npm10.9.8, Ruby3.4.11/Bundler2.5.22/CocoaPods1.15.2/xcodeproj1.25.1, Zulu17.0.19, Gradle9.4.1/AGP9.2.1, compile37/target36/build-tools37.0.0/NDK27.1.12297006이다.
- Mattermost는 Node24.15.0/npm11.12.1, Ruby3.2.11/Bundler2.5.11/CocoaPods1.16.1/xcodeproj1.27.0, Temurin17.0.20.1+1, Gradle9.0.0/AGP8.12.0, compile36/target36/build-tools36.0.0/NDK27.1.12297006이다. 선언이 exact patch를 고정하지 않는 도구는 관측한 선택값이다.
- fresh 입력은 현재 내장 Data volume의 준비된 root에서 사용한다. 다른 경로로 옮기면 Hermes 경로 checksum과 generated script 경로를 재준비·감사한다. frozen Pod 재생성 뒤에는 생성 Debug 12값을 다시 확인한다.
- 원본 Metro를 먼저 확인하고 실제 대상·포트·산출물 소유권을 확보한다. Watchman을 끄는 과거 진단 config는 사용하지 않는다. 기본 Debug scheme은 최소 `RunstirBaselineRN`, OSS `Mattermost`다. Android는 `:app/debug`이며 OSS baseline은 `-PreactNativeArchitectures=arm64-v8a`를 사용했다.
- Mattermost iOS의 실제 성공 명령은 `xcodebuild -workspace ios/Mattermost.xcworkspace -scheme Mattermost -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath <OWN_DERIVED_DATA> ARCHS=arm64 CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build`다. 원본 entitlement를 수정하지 않는다. 이 Simulator 로컬 서명은 제품의 실제 기기 자동 재서명이나 배포 자격을 허용하지 않는다.
- Runstir가 준비를 다시 수행할 때 위 입력을 보존하는지와 CLI·GUI 각각의 실제 첫 화면은 후속 #225~230 기능 게이트에서 판정한다. fresh에서 native build·설치·실행은 아직 하지 않았다.

## AC 연결

#212는 고정 입력, 표본별 정확한 도구/host 선택, 서로 다른 최소+OSS의 양플랫폼 첫 화면, 실패 이력, 별도 fresh 준비·인계의 근거를 갖췄다. #199 AC05에는 RN baseline과 fresh 입력만 연결한다. 전체 여섯 조합과 같은 후보의 CLI·GUI 실행을 대체하지 않는다. AC06에는 실제 Mac의 Android 가속·실행을 연결하며, Tart guest 가속·새 host·전체 실기기 검증을 주장하지 않는다. #224 이후 순서와 유료 Ad Hoc IPA·서명/공증 보류를 유지한다.

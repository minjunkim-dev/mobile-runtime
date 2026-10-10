# RN baseline #212 attempt-06: iOS native 필수 실패

2026-10-10 기록이다. Mattermost의 원본 선언과 ADR-0020의 Hermes 한 값 준비를 유지했다. frozen Pods 설치와 ADR-0021의 정확한 11개 resource bundle Debug 보정은 통과했다. native iOS build는 exit 65로 실패했다. Q5의 필수 실패 중단 기준을 적용했다. partial `.app` 디렉터리는 1개다. Mattermost 실행 파일은 0개다. 완성 앱·앱 ZIP·APK·첫 화면 screenshot도 0개다. 이 partial 디렉터리를 설치하거나 실행할 수 있는 완성 앱으로 판정하지 않는다. 추가 source·target·도구 예외를 적용하지 않았다. #212는 OPEN이다. PR #236은 미병합이다. 실제 Runstir를 실행하지 않았다.

## 고정 입력과 준비

정책 main은 `3853cbbdc08675b7a8a658818a1cccd14004e5f3`이다. 원본 source는 [Mattermost `c2fe3beda22befd2178dce431793c09111ed903e`](https://github.com/mattermost/mattermost-mobile/tree/c2fe3beda22befd2178dce431793c09111ed903e)다. 새 baseline clone에서 원본 source·JS/Ruby locks·선언 버전·graph를 유지했다. Node `24.15.0`, npm `11.12.1`, Ruby `3.2.11`, Bundler `2.5.11`, CocoaPods `1.16.1`, xcodeproj `1.27.0`, Temurin `17.0.20.1+1`을 관측했다. RN `0.83.9`·Expo `55.0.23`과 원본 from-source 선택을 유지했다. Xcode `27.0 (27A266a)`와 SDK `27.0`, 의도한 iOS runtime `26.0 (23A343)`을 구분한다. Android compileSDK `36`과 기존 runtime API `37` Google Play arm64 revision 6도 구분한다. Hermes 한 값만 정규화하면 Podfile.lock 전체 byte가 원본과 같다. 원본 serialized spec provenance는 unknown이다. 원본 대비 경로만 달랐다는 증거는 없다.

4216 tracked 파일의 source 감사는 준비 후와 iOS 실패 후 모두 통과했다. raw byte·파일 kind·Git 실행 bit·index·flags 불변 조건을 유지했다. POSIX 권한 진단은 Git 실행 bit와 구분한다. attempt-05의 과잉 full POSIX guard 중단 이력은 보존한다.

`pod install --deployment` 성공 뒤 generated Pods project에서 승인한 11개 resource bundle의 Debug `IPHONEOS_DEPLOYMENT_TARGET`만 `16.4`로 준비했다. raw 변경은 11개 값이다. helper SHA-256은 `83f0dc24c22d24dd5df8f3dc6fafde3b3a2313c14ae4421dcf74c482b90489b1`다. 원본 generated project raw SHA-256은 `88e616365610ebcf3a74d0ea2f45caa8e6c48d111cb8a8c6c7ef52102a276fbd`다. 준비 project raw SHA-256은 `2cb73e5830dd26c488ccaef0100797a885c9d6b7fb0694f21a8a0561e64040a8`다. 전체 parsed object 역정규화 비교와 array 순서 검사를 통과했다. Release·다른 target·다른 설정·source·graph는 바뀌지 않았다. 독립 review의 material finding은 0개다. iOS 실패 후 generated project의 준비 hash도 그대로다.

## native iOS 필수 실패

native Debug build는 `2026-10-10T20:36:51+09:00`에 시작했다. `2026-10-10T20:41:34+09:00`에 exit `65`로 끝났다. attempt-04와 달리 실제 compile 단계에 들어갔다.

첫 compiler error는 `node_modules/expo-router/ios/LinkPreview/LinkPreviewNativeActionView.swift:141`의 `baseUiAction.subtitle = subtitle`다. compiler는 `'subtitle' is only available in iOS 16.0 or newer`를 반환했다. 실제 compiler target은 `arm64-apple-ios15.1-simulator`였다.

ExpoRouter `55.0.14`의 원본 podspec은 iOS `15.1`을 선언한다. 생성 ExpoRouter framework target의 Debug와 Release도 `15.1`이다. 보정 전후 값은 같다. ExpoRouter framework target은 ADR-0021이 허용한 11개 resource bundle 대상 밖이다. 해당 target이나 source를 추가로 바꾸지 않았다.

SDK `UIMenuElement.h:62`는 `subtitle`에 `API_AVAILABLE(ios(15.0))`를 선언한다. `UIAction.h`에는 `subtitle` 선언이 없다. 따라서 공식 UIKit header가 iOS 16.0을 선언했다고 주장하지 않는다. Swift import availability와 compiler 진단이 다른 별도 원인은 미확정이다. compiler가 이 사용에 iOS 16.0 이상을 요구했다는 관측만 고정한다.

## 다운로드와 archive cache

Hermes debug `0.14.1` archive는 새로 다운로드했다. release archive는 공식 SHA-256·SHA-1과 일치한 raw archive cache를 재사용했다. 설치 명령을 중단하지 않았다. 원본 source command flag도 바꾸지 않았다. debug partial은 건드리지 않았다. Pods·node_modules·vendor·build 또는 풀어 놓은 dependency 디렉터리를 복사하지 않았다. 공식 archive cache 재사용을 독립 dependency 디렉터리 준비와 구분한다.

## 미실행과 cleanup

iOS install·launch·첫 화면, 새 Android 입력 build·install·launch·첫 화면, Mattermost fresh clone·독립 준비, 최소 RN fresh clone·frozen 준비는 미실행이다. baseline native 실패를 fresh 성공이나 양플랫폼 known-good으로 바꾸지 않는다. configured candidate SHA를 실제 fresh checkout HEAD로 기록하지 않는다. actual Runstir gate는 후속 범위다.

cleanup은 PASS다. 기존 iOS 27 Simulator 두 개와 GUI를 보존했다. 작업의 iOS 26 Simulator는 Shutdown 상태다. `8081` listener, adb device, 실제 xcodebuild·qemu·emulator는 없다. 새 Simulator·Emulator·Metro를 시작하지 않았다. xcodebuild는 exit 65로 종료했다. 자원을 삭제하지 않았다. 실행 lease를 반납했다. 원본 cleanup SHA-256은 `c1a7ff60b9408f457bebcc8946111b053f1ec7a2ebea55341d0d66a741bab749`다.

## 증거와 공개 경계

[공개 manifest](evidence/212/attempt-06/manifest.json)는 원본 raw identity와 실행 결과를 요약한다. root 파일은 88개다. 원본 manifest의 evidence record 86개와 별도 공식 release archive cache 1개의 size·SHA-256이 모두 일치했다. SHA256SUMS는 88개 항목이다. root 파일 87개와 cache 1개를 포함한다. SHA256SUMS 파일 자체는 자기 index에서 제외하며 별도 hash로 고정했다. root 파일 88개는 이 SHA256SUMS 파일을 포함한다. 공개 inventory는 root 88개와 cache 1개를 구분하여 식별한다.

command result와 log는 각각 17개다. 모든 command result의 step·시작·종료·exit를 원본 manifest와 대조했다. 16개 command는 exit 0이었다. iOS build 한 개는 exit 65였다. 실패 뒤 source 감사와 generated project·22개 xcconfig hash 검사도 PASS다. 이 PASS를 native build PASS로 취급하지 않는다.

원본 REPORT SHA-256은 `8898011ae33104cf7283f914067bdc1593cf97fe6180b983450385656f11f03e`다. 원본 manifest는 `2d813ebd54c902e4d27af1f936a8d33dce14df7d3f5113b367af5a63abec8f55`다. 원본 SHA256SUMS는 `3cda1994350c772db0a2e22d5c3d8a36509868238f5077c32ba5ffcf46e6acb7`다. 원본 post-source 감사는 `323358d79fb8cae11b6c3be4563a25bf6a38db7e527e1c0f14ac6a2ca560c6ab`다. 원본 post-generated 검사는 `40b49716483e2796399eb2114ebd43151ea3e602b3b9ea09b464556b824f050b`다. 이 hash는 공개 치환 파일의 hash가 아니다.

raw 자료는 `<LOCAL_VALIDATION_ROOT>/attempt-06-generated-pods`에 보존한다. 실패 raw log·process text·메모리 dump·helper는 공개하지 않는다. host 절대 경로와 기기 이름·UUID는 공개 요약에서 제외한다. 원본 raw hash를 공개 치환 파일 hash로 제시하지 않는다. 공개 요약을 원본 raw byte 감사의 대체 증거로 사용하지 않는다.

새 실행이나 추가 예외에는 별도 결정이 필요하다. 이번 기록은 source patch나 추가 target 보정을 자동 채택하지 않는다. 최소 RN·실제 OSS 양플랫폼 baseline과 별도 fresh 인계 조건은 남아 있다. 기존 실패와 이전 최소 RN 양플랫폼 PASS를 보존한다.

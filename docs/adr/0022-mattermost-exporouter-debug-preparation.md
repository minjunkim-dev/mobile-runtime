---
status: accepted
---

# ADR-0022: Mattermost ExpoRouter의 생성 Debug 설정을 제한하여 준비한다

2026-10-10 사용자가 추가 범위와 새 실행 조건의 공유 이해를 확인했다. 원본 source·버전·Release를 유지하면서 생성 ExpoRouter framework target의 Debug 한 값만 원본 Pods 선언값으로 준비하는 제한된 사람 예외를 채택한다. 정책 반영·helper 독립 검토·새 lease 뒤 새 baseline과 독립 fresh 준비를 진행한다. 정책 채택은 실제 성공을 뜻하지 않는다.

## 확인한 실패와 미확인 원인

[#212 attempt-06](https://github.com/minjunkim-dev/mobile-runtime/blob/9d4a5aac70ff1d228a3222c571962d49e082bdfe/docs/rn-baseline-212-attempt-06.md)은 [ADR-0020](0020-rn-baseline-prepared-input.md)의 Hermes 한 값 준비와 frozen Pods 검사, [ADR-0021](0021-mattermost-generated-pods-preparation.md)의 resource bundle 11개 Debug 보정을 통과했다. source·전체 generated project의 사후 감사도 통과했다. native iOS build는 ExpoRouter Swift compile에서 exit `65`로 실패했다. install·launch·첫 화면·새 Android·fresh 준비는 수행하지 않았다.

최초 실패 위치는 `node_modules/expo-router/ios/LinkPreview/LinkPreviewNativeActionView.swift:141`이다. compiler는 `baseUiAction.subtitle = subtitle`에 iOS `16.0+`를 요구했다. 실제 compiler target은 `arm64-apple-ios15.1-simulator`였다. 설치한 ExpoRouter `55.0.14`의 원본 `ExpoRouter.podspec:21–22`와 생성 target의 Debug·Release 값은 모두 `15.1`이다. ExpoRouter는 `com.apple.product-type.framework`이며 ADR-0021의 resource bundle 11개에 포함되지 않는다.

SDK `UIMenuElement.h:62`에는 `subtitle`의 iOS `15.0` 선언이 있다. 이 header 값과 Swift diagnostic의 차이에 관한 원인은 미확정이다. 이 정책은 원인 규명이나 build 성공을 선언하지 않는다. 실제 compiler가 요구한 하한을 넘는 생성 Debug 입력을 별도로 식별하고 새 실행에서 결과를 확인한다.

## 추가 허용 범위

대상 source는 Mattermost `c2fe3beda22befd2178dce431793c09111ed903e` 하나다. 원본 [Podfile.properties.json](https://github.com/mattermost/mattermost-mobile/blob/c2fe3beda22befd2178dce431793c09111ed903e/ios/Podfile.properties.json)의 `deploymentTarget`과 생성 Pods project의 Debug·Release 하한은 `16.4`다. 원본 앱 project의 명시 deployment 값 8개는 `16.0`이다. 이 값들을 같은 앱 최소값으로 표현하지 않는다. 원본 앱 project와 source·의존성 버전·graph·tool tuple, ADR-0020의 source/lock/index/flags 감사를 유지한다. 이번 준비 값 `16.4`는 기존 ADR-0021의 11개 값과 같은 Pods 선언값으로 선택한다.

마지막 frozen `pod install --deployment` 성공 뒤 `ios/Pods/Pods.xcodeproj/project.pbxproj`에서 다음 **한 값**을 추가로 준비하는 사람 예외를 허용한다.

| target | product type | configuration | 원본 값 | 준비 값 |
|---|---|---|---|---|
| `ExpoRouter` | `com.apple.product-type.framework` | `Debug` | `15.1` | `16.4` |

ADR-0021의 resource bundle 11개 Debug 보정은 그대로 유지한다. 따라서 새 생성 project의 전체 허용 차이는 그 11값과 이번 한 값을 합한 **12개 Debug 값**이다. ADR-0021의 다른 target 불변 조건에서 이번 ExpoRouter Debug 한 값만 추가 예외로 다룬다. Release와 나머지 target/configuration/설정/object/array는 모두 유지한다.

앱 project, Podfile, ExpoRouter podspec·Swift source·package source, lock의 다른 값, build flag, Xcode/SDK 선택과 버전을 바꾸지 않는다. 기존 실패 로그와 packet을 보존한다. Pods project의 `16.4` 미만인 다른 generated target을 자동 보정하지 않는다. attempt-06에는 기존 보정 뒤 `16.4` 미만 target 172개가 남았지만, 낮은 선언 값 자체를 실제 compile 실패로 판정하지 않는다. 이번 예외는 실제 실패를 확인한 ExpoRouter 하나로 제한한다.

helper는 외부 수동 준비 도구다. Runstir 제품 코드나 자동 target 보정 기능을 추가하지 않는다. 다른 source·Pod 버전·SDK 조합·Release build에 이 예외를 적용하지 않는다.

## 재현과 감사

1. 새 baseline clone을 원본 SHA에서 독립 준비한다. 초기 raw checkout·종류·Git 실행 mode·index·flags와 원본 EOL 선언을 고정한다. 기존 원본 npm/hook, frozen Bundle, ADR-0020의 Hermes 한 값 준비와 마지막 frozen Pods 성공을 확인한다. 기존 attempt-06의 준비 디렉터리를 이어 쓰지 않는다.
2. 마지막 frozen 설치 후 생성 project의 raw hash·전체 parsed object·configuration matrix와 연결된 xcconfig를 고정한다. ExpoRouter의 이름·framework type·고유 Debug configuration·원본 `15.1`·Release `15.1`을 확인한다. 기존 ADR-0021의 11개 대상도 다시 확인한다. 중복 이름, 공유 configuration, 조건부/xcconfig deployment override, 허용 대상이나 입력의 불일치가 있으면 중단한다.
3. hash를 고정한 외부 helper로 정확한 12개 Debug 값만 준비한다. 전체 object에서 그 12값만 원래 값으로 역치환하면 변경 전 전체 object와 같아야 한다. raw diff와 역치환 결과도 보존한다. Release·다른 설정·object 추가/삭제·array 순서 변경을 거부하는 메모리 self-check와 독립 검토를 수행한다. helper 입력 identity에 같은 clone의 frozen/source 감사 결과를 연결한다.
4. 채택한 정책과 새 실행 입력·단일 lease를 고정한 뒤 native iOS Debug baseline을 검증한다. 성공하면 같은 표본 tuple에서 install·launch·첫 화면과 Android baseline을 직렬 확인한다. 이후 별도 Mattermost fresh clone을 독립 준비하고 frozen/source/12값 감사를 인계한다. 최소 RN의 fresh frozen 준비도 별도로 확인한다. baseline의 Pods·node_modules·vendor·build 산출물을 다른 clone으로 복사하지 않는다. ADR-0020이 허용한 공식 raw archive cache만 origin/hash/use를 기록하여 재사용한다.
5. 준비 뒤와 실제 실행 뒤 source·lock·index·flags 및 generated project를 다시 감사한다. 허용 밖 변경이나 추가 필수 실패가 나오면 중단하고 증거를 보존한다. 추가 target·source·checksum·flag·도구를 바꾸지 않는다. 다시 조건을 바꾸려면 별도 결정과 새 실행이 필요하다. 다른 작업의 Simulator·Emulator·Metro와 GUI를 변경하지 않는다.

## 판정과 후속 범위

이 입력의 결과는 **생성 Pods를 보정한 준비 입력의 baseline**으로 기록한다. source SHA, 원본 lock, clone별 준비 lock/spec, helper hash, frozen/source receipt, 전후 project hash와 정확한 12값 차이, tool/runtime/device/명령/exit를 함께 인계한다. 원본 serialized spec의 provenance unknown과 모든 이전 실패를 유지한다. 원본 무보정 baseline 성공으로 바꾸지 않는다. 원본 앱 project의 `16.0`보다 높은 framework Debug 설정을 포함하므로 iOS `16.0`이나 `16.4` 기기의 지원을 추론하지 않는다. 실제 선택한 iOS `26.0`의 검증 조합에만 결과를 귀속한다.

정책 채택과 준비 성공은 known-good 판정이 아니다. #212의 최소 RN 앱과 실제 OSS 앱 각각의 양플랫폼 build·install·launch·첫 화면 및 별도 fresh 인계 조건은 그대로다. 필수 증거가 남으면 #212와 PR #236은 미완료 상태를 유지한다.

ADR-0021의 후속 Runstir 경계도 유지한다. 현재 npm lifecycle과 Pods generation은 생성 ExpoRouter framework 설정도 다시 만들 수 있다. 실제 보정 유지나 재적용을 실험한 결과는 없다. 해당 문제는 후속 Runstir gate에서 별도로 결정한다. 이번 정책으로 Runstir dependency 실행 정책을 바꾸지 않는다. 실제 Runstir CLI·GUI, 공동 여섯 조합, 일반 RN 지원과 1.0.0 출시를 증명하지 않는다.

## 대안과 적용 조건

원본 입력을 유지하고 다른 OSS 후보를 조사할 수 있다. ExpoRouter source나 버전을 바꾸는 방법도 있지만 이번 원본 보존 범위와 다르다. 모든 Pods target을 일괄 올리는 방법은 관측한 한 compile 실패보다 넓다. 이 정책은 원본 source·버전을 보존하는 대신 생성 Debug 한 값의 별도 조건을 추가한다.

사용자가 추가 범위와 감사·중단·후속 경계의 공유 이해를 확인했다. 정책을 main에 반영하고 새 실행 계획과 helper를 독립 검토한다. 그 뒤 새 lease로 실행한다. ADR-0020의 중단 기준은 유지한다.

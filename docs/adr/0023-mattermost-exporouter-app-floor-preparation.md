---
status: accepted
---

# ADR-0023: ExpoRouter Debug 준비 값을 원본 앱의 compiler 하한에 맞춘다

사용자가 2026-10-11 범위와 새 실행 조건을 확정했다. [ADR-0022](0022-mattermost-exporouter-debug-preparation.md)의 attempt-07 실패 뒤 새 실행에서만 이 정책을 적용한다. 정책 main 반영과 새 helper 독립 검토 및 새 단독 lease 전에는 실제 실행을 재개하지 않는다. 기존 실패와 정책을 보존한다.

## 확인한 실패

Mattermost source는 `c2fe3beda22befd2178dce431793c09111ed903e`다. attempt-07은 마지막 frozen Pods, source 4,216개 파일 감사, 정확한 12개 Debug 값 준비와 독립 검토를 통과했다. native iOS build는 exit `65`로 실패했다. 첫 오류는 `Pods/Target Support Files/Pods-Mattermost/ExpoModulesProvider.swift:21:17`이다.

compiler는 앱을 iOS `16.0`으로 컴파일하면서 최소 deployment target이 iOS `16.4`인 `ExpoRouter` module을 import할 수 없다고 보고했다. 원본 앱 project의 명시 deployment 값 8개는 `16.0`이다. ADR-0022로 준비한 ExpoRouter Debug 값은 `16.4`다. 실패 뒤 source와 전체 generated project의 사후 감사도 통과했다. install·launch·첫 화면·새 Android·Mattermost fresh·최소 RN fresh 준비는 시작하지 않았다. 이 실패는 실제 Runstir 실행 결과가 아니다.

원본 `Podfile.properties.json`의 `deploymentTarget`과 생성 Pods project의 Debug·Release 하한 `16.4`는 원본 앱 project의 `16.0`과 다르다. 두 값을 같은 앱 최소값으로 표현하지 않는다. 이 제안은 원본 선언을 바꾸지 않는다.

## 결정 범위

[ADR-0020](0020-rn-baseline-prepared-input.md)의 Hermes 한 값 준비와 원본 source·lock·종류·Git 실행 mode·index·flags 감사 조건을 유지한다. [ADR-0021](0021-mattermost-generated-pods-preparation.md)의 resource bundle 11개 Debug 값 `16.4`도 유지한다. 새 실행에서 ADR-0022의 ExpoRouter Debug 준비 값만 다음과 같이 대체한다.

| target | product type | configuration | 원본 값 | 새 준비 값 |
|---|---|---|---|---|
| `ExpoRouter` | `com.apple.product-type.framework` | `Debug` | `15.1` | `16.0` |

`16.0`은 원본 앱 project의 실제 compiler 하한이다. attempt-06의 Swift diagnostic도 `subtitle`에 iOS `16.0+`를 요구했다. 두 관측 조건에 맞춘 후보 입력이다. 이 값으로 전체 build가 성공한다고 단정하지 않는다. SDK header의 iOS `15.0` 선언과 Swift diagnostic 차이의 원인은 여전히 미확정이다.

전체 허용 차이는 **resource bundle 11개 Debug 값 `16.4`와 ExpoRouter 1개 Debug 값 `16.0`을 합한 정확한 12개 값**이다. 앱 project의 `16.0`, ExpoRouter Release의 `15.1`, Pods project의 `16.4`를 유지한다. 다른 target/configuration/설정/object/array, source·Podfile·properties·podspec·버전·의존성 graph·build flag·Xcode/SDK·tool tuple을 바꾸지 않는다. 낮은 deployment 값 자체를 실패로 판정하지 않는다. 추가 target을 자동 보정하지 않는다.

helper는 외부 수동 준비 도구다. Runstir 제품 코드나 자동 보정 기능을 추가하지 않는다. 다른 source·Pod 버전·SDK·Release에 이 예외를 적용하지 않는다. 기존 attempt-07 디렉터리나 준비 입력을 이어 쓰지 않는다.

최소 RN source는 `b62e3a4d5e7cfc05d7d948a5a4e30f0cc6a82bb4`를 유지한다. 같은 host·기기 조건에서 표본별 원본 RN·Pods·Gradle 선언을 유지한다. Mattermost의 Hermes·생성 Pods 예외를 최소 RN에 적용하지 않는다.

## 필요한 새 실행 조건

1. 사용자와 범위·감사·중단 조건의 공유 이해를 확인한다. 정책을 main에 반영한다. 새 helper와 계획을 독립 검토한다. 새 단독 lease 뒤에만 실행한다.
2. 원본 SHA에서 새 baseline clone을 독립 준비한다. 초기 checkout과 원본 npm/hook, frozen Bundle, Hermes 한 값 준비, 마지막 frozen `pod install --deployment` 성공을 확인한다. 같은 clone의 source snapshot과 frozen receipt를 helper 입력에 연결한다.
3. 전체 raw project와 parsed object를 새 입력에서 고정한다. ExpoRouter의 framework type·고유 Debug 원본 `15.1`·Release `15.1`과 기존 bundle 11개를 확인한다. 모든 configuration-list owner와 각 target의 Debug·Release 구성 및 scoped xcconfig 24개를 감사한다. 조건부/xcconfig deployment override나 모호한 입력은 거부한다.
4. 정확한 12개 값만 준비한다. 전체 object와 raw에서 그 12값만 원래 값으로 역치환하면 변경 전과 같아야 한다. 준비 뒤와 실제 실행 뒤 source와 generated project를 다시 감사한다. 최초 receipt를 덮어쓰지 않는다. 사후 감사도 같은 clone·snapshot·source digest·변경 전 object에 연결한다. 허용 밖 차이, 다른 clone의 receipt, 변경된 raw/object/xcconfig를 거부하는 메모리 검사와 독립 검토를 수행한다.
5. 최신 자원 검사를 통과하면 iOS native build·install·launch·첫 화면, 같은 표본 tuple의 Android baseline을 직렬 확인한다. 성공 뒤 Mattermost fresh clone과 최소 RN fresh clone을 각각 독립 준비한다. Pods·node_modules·vendor·build 산출물을 복사하지 않는다. 공식 raw archive cache만 ADR-0020의 origin/hash/use 조건으로 재사용한다. 추가 필수 실패나 허용 밖 변경이 나오면 모든 후속 실행을 중단한다. 추가 source·target·flag·도구 보정은 하지 않는다. 다른 작업의 Simulator·Emulator·Metro와 기존 GUI를 보존한다.

## 판정과 경계

결과는 생성 Pods를 보정한 준비 입력의 baseline으로 기록한다. 원본 무보정 baseline 성공으로 바꾸지 않는다. 기존 실패와 원본 serialized spec의 provenance unknown을 유지한다. 정책 채택과 준비 성공만으로 known-good을 선언하지 않는다.

#212는 최소 RN 앱과 실제 OSS 앱 각각의 양플랫폼 build·install·launch·첫 화면과 독립 fresh 인계를 요구한다. 남은 증거가 있으면 #212와 PR #236을 미완료로 유지한다. 실제 iOS `26.0` tuple에만 결과를 귀속한다. iOS `16.0`·`16.4` 기기 지원이나 Release 성공을 추론하지 않는다.

실제 Runstir의 npm lifecycle과 Pods generation이 보정을 유지하는지는 확인하지 않았다. 후속 Runstir gate에서 별도로 결정한다. 실제 Runstir CLI·GUI, 공동 여섯 조합, 일반 RN 지원과 1.0.0 출시는 이번 정책의 판정 범위에 포함하지 않는다.

원본 source나 앱 최소값을 바꾸는 대안과 다른 OSS 후보를 조사하는 대안을 검토했다. 관측한 module import 경계에 맞춰 생성 Debug 한 값의 준비 조건만 바꾸는 가장 좁은 경로를 선택했다. 추가 필수 실패가 나오면 모든 후속 실행을 중단한다. 다시 조건을 바꾸려면 별도 결정과 새 실행이 필요하다.

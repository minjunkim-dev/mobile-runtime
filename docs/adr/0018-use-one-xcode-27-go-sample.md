# ADR-0018: Xcode 27 Go 게이트를 단일 표본으로 고정한다

- 상태: 채택
- 날짜: 2026-10-07
- 관련: #160 · #152 · ADR-0008 · ADR-0012 · ADR-0016 · ADR-0017

## 배경

maintainer는 Xcode 27.0 이상 정식 버전에서 검증하기로 했다. Xcode 26.6 이하를 검증하지 않는다. 기존 세 프로젝트의 upstream 대응은 후속 검증으로 남긴다.

ADR-0017의 후보 baseline 실패 후 BlueWallet을 조사했다. BlueWallet의 독립 실행은 네 Pod checksum을 재생성하면 첫 화면에 도달했다. 이 관측 뒤에 표본과 파일 규칙을 바꾼다. 따라서 기존 게이트를 통과했다고 주장하지 않는다. 새 게이트를 열고 새 실행 전에 입력을 고정한다. 앞선 조사 실행의 성공을 새 Go 증거로 합산하지 않는다.

## 결정

현재 iOS Go 게이트는 BlueWallet 한 개의 1/1이다. 이 결정은 ADR-0008·ADR-0016·ADR-0017의 현재 iOS 게이트 표본, 3/3 기준, tracked 파일 규칙을 아래 범위에서 대체한다. 과거 No-Go 판정과 내부 alpha 기준은 바꾸지 않는다. Android 게이트도 바꾸지 않는다.

| 입력 | 고정값 |
| --- | --- |
| 표본 | `BlueWallet/BlueWallet` |
| 표본 SHA | `c29968f676a68803e18d44f853cdd6a1f0024890` |
| React Native | `0.85.3` |
| Xcode | `27.0` (`27A266a`) 정식 |
| simulator runtime | iOS `27.0` |
| host | macOS `27.0.1`, Apple Silicon arm64 |
| Node / npm | `24.21.0` / `11.19.0` |
| Ruby / Bundler / CocoaPods | `3.4.10` / `2.6.9` / `1.17.0` |
| mobile SHA | `92308d60a25ae13160d09e43235cda6abface0fe` |

Xcode 27.0 이상 정식을 검증 대상으로 삼는다. 이번 결과는 위 조합에만 귀속한다. 다른 정식 버전은 별도 실행으로 검증한다. RC·beta 결과를 이번 결과에 합산하지 않는다. 표본이 실패하면 다른 SHA를 고르지 않는다.

### 사람 준비와 파일 예외

ADR-0016의 도구 설치, 신뢰 결정, 앱 환경값, untracked `mobile.yml` 준비를 허용한다. baseline과 Go에 같은 준비를 적용한다. 앱 소스, Podfile, 앱 빌드 설정, extension target을 수정하지 않는다. `mobile`이 Pods deployment target을 보정하는 기능은 이번 범위에 없다.

유일한 tracked 준비 예외는 `ios/Podfile.lock`의 `SPEC CHECKSUMS` 안에 있는 다음 네 항목의 checksum 값 재생성이다.

- `hermes-engine`
- `React-Core-prebuilt`
- `ReactCodegen`
- `ReactNativeDependencies`

네 값 외의 모든 tracked byte는 고정 SHA와 같아야 한다. 의존성 버전, 의존성 그래프, source 선언, Podfile checksum, CocoaPods 버전도 같아야 한다. 이 예외는 의존성 갱신을 허용하지 않는다. 네 차이의 원인을 모두 host 경로로 단정하지 않는다.

`npm ci`와 frozen Bundler로 의존성을 설치한다. `pod install`로 네 checksum을 재생성한다. `pod install --deployment` 성공은 이 게이트의 요건이 아니다. RN artifact mirror는 공식 `https://repo.reactnative.dev/maven2`를 사용한다. 두 실행에서 같은 mirror를 사용하고 그 사실을 기록한다.

실제 tracked 파일 byte를 HEAD blob과 비교한다. Git index도 HEAD와 같아야 한다. `assume-unchanged`와 `skip-worktree`는 허용하지 않는다. clone 직후에는 예외를 포함한 변경이 없어야 한다. 준비 뒤와 실행 뒤에는 네 값만 정규화한 lockfile 전체가 HEAD와 같아야 한다.

### 실행과 판정

1. 별도 fresh clone에서 `mobile` 없이 build·install·launch·첫 화면을 확인한다.
2. baseline이 성공하면 다른 fresh clone에서 같은 준비를 적용한다.
3. 고정 mobile SHA로 `doctor` → `build` → `up`을 실행한다.
4. `up`이 실행한 앱의 첫 화면을 직접 확인한다.
5. tracked audit와 판정을 [Go round runbook](../go-round-runbook.md)에 기록한다.

두 실행은 같은 host, simulator, 검증 조합을 사용한다. baseline의 Metro와 앱을 중지한 뒤 Go를 실행한다. 다른 실행의 성공, 다른 mobile SHA의 성공, baseline 도구가 대신 실행한 앱을 Go 증거로 합산하지 않는다. mobile 소스를 수정하면 새 SHA를 고정하고 전체 실행을 다시 한다.

untracked `mobile.yml`은 `BlueWallet` scheme과 전용 simulator 이름을 지정한다. Xcode `27.0`과 `iosRuntime: "27.0"`을 사람이 override로 선언한다. 이 선언을 자동 추론이나 Matrix 지원 근거로 보고하지 않는다. required check의 error와 unresolved unknown을 성공으로 처리하지 않는다.

첫 화면은 ADR-0016의 기준을 따른다. RN red box, crash, 흰 화면은 실패다. 초기 UI 이후의 네트워크·앱 기능은 이 게이트에 넣지 않는다. wallet 생성이나 거래는 실행하지 않는다.

baseline 성공 전에는 known-good으로 판정하지 않는다. 전체 Go 증거와 고정 source CI가 성공하기 전에는 No-Go다. 문서 PR도 review와 required `CI` 성공을 확인한다.

Go는 ADR-0016의 이름 결정과 외부 배포 허용 범위만 연다. 이번 작업에서 외부 배포를 실행하지 않는다. 한 표본의 결과로 React Native iOS 일반 지원이나 Xcode 27 전체 지원을 주장하지 않는다(ADR-0012).

## 후속 검증

2026-10-07의 새 실행은 [Go round runbook](../go-round-runbook.md)에 기록했다. 독립 baseline과 별도 fresh clone의 mobile 실행은 성공했다. 현재 판정은 고정 SHA와 검증 조합에 한정한 1/1 Go다. 기존 No-Go 결과는 바꾸지 않는다.

mattermost-mobile, Rainbow, Joplin은 upstream의 Xcode 27 대응 뒤 별도 입력으로 검증한다. 이 검증은 현재 1/1 게이트의 필수 조건이 아니다. 기존 후보 실패와 준비 실패 기록은 유지한다.

## 대안

- 기존 세 프로젝트의 대응을 기다린다: 현재 게이트로는 채택하지 않는다. maintainer가 단일 표본으로 새 게이트를 열었다.
- mobile이 deployment target 하한을 수정한다: 채택하지 않는다. 소스 변경 없는 검증 경계를 바꾸며 별도 ADR과 구현 검증이 필요하다.
- checksum 변경을 전부 허용한다: 기각한다. 네 항목 외의 변경은 실패다.

# Xcode 27 Go round

기준은 [ADR-0018](adr/0018-use-one-xcode-27-go-sample.md)에 고정했다. 실행 ticket은 [#160](https://github.com/minjunkim-dev/mobile-runtime/issues/160)이다. 입력은 실행 전에 기록했다. 기존 세 프로젝트와 BlueWallet 조사 실행의 성공을 합산하지 않는다.

## 입력과 절차

ADR-0018의 표본 SHA, mobile SHA, 도구 버전을 사용한다. 별도 fresh clone 두 개를 사용한다. baseline은 mobile 없이 실행한다. Go는 같은 준비 뒤 `mobile doctor --json`, `mobile build --json`, `mobile up --json`을 프로젝트 root에서 실행한다.

두 clone에서 `npm ci --no-audit --no-fund`, `BUNDLE_FROZEN=true bundle _2.6.9_ install`, `ENTERPRISE_REPOSITORY=https://repo.reactnative.dev/maven2 BUNDLE_FROZEN=true bundle _2.6.9_ exec pod install`을 실행한다. pod 명령은 `ios`에서 실행한다. 도구는 ADR-0018의 버전으로 선택한다. extension target은 유지한다.

의존성 다운로드 cache를 두 clone에 동일하게 사용한다. RN core·dependencies의 debug·release archive 네 개는 공식 mirror의 `.sha1`과 일치함을 확인했다. 이 cache는 배포된 의존성 archive다. 이전 실행의 앱, 생성된 Pods 프로젝트, 앱 빌드 결과는 복사하지 않는다. baseline의 첫 다운로드는 중지하고 같은 명령으로 재개했다.

Hermes는 CocoaPods download cache도 사용한다. `250829098.0.10`의 공식 mirror source URL이 같은 cache만 재사용한다. 현재 podspec checksum에 맞는 항목이 없어 CocoaPods `Cache.copy_and_clean`과 `Cache.write_spec`으로 cache 항목을 준비했다. 현재 specification과 source URL은 바꾸지 않았다. installer 코드는 수정하지 않았다. 두 clone에 같은 준비를 적용했다. 느린 Hermes 다운로드는 각 clone에서 중지하고 `pod install`을 재개했다.

두 clone에 같은 untracked `mobile.yml`을 준비한다.

```yaml
ios:
  device: Mobile Xcode27 Go Gate
  scheme: BlueWallet
overrides:
  xcode: "27.0"
  iosRuntime: "27.0"
```

이 override는 사람의 실행 입력이다. 자동 추론 결과나 Matrix 지원 근거가 아니다. 앱의 최소 iOS deployment target을 27로 변경하지 않는다.

clone 직후, 의존성 준비 뒤, 실행 뒤에 실제 tracked byte를 HEAD blob과 비교한다. index와 숨김 flag도 확인한다. ADR-0018의 네 checksum 값만 정규화한 lockfile을 전체 byte 비교한다. 그 외의 차이는 실패다.

baseline은 `BlueWallet.xcworkspace` / `BlueWallet` / `Debug` / arm64로 build·install·launch한다. 같은 clone의 Metro를 port 8081에서 실행한다. 전용 iOS 27.0 simulator의 첫 화면을 직접 확인한다. baseline Metro와 앱을 중지한 뒤 Go를 시작한다.

Go 앱은 `mobile up`으로 실행한다. 화면 검증 도구로 앱을 재빌드하거나 다시 실행하지 않는다. 실제 앱 첫 화면과 RN red box·crash·흰 화면 여부를 확인한다.

## 결과

2026-10-07에 실행했다. 입력은 ADR-0018과 같다. 독립 baseline과 별도 fresh clone의 Go가 성공했다. **현재 판정은 1/1 Go다.** 검증 결과는 `validated`다. 결과는 고정 mobile SHA와 이 검증 조합에만 귀속한다.

### 독립 baseline

- 별도 fresh clone의 HEAD는 `c29968f676a68803e18d44f853cdd6a1f0024890`이다. clone 직후 tracked blob 1,410개가 HEAD와 같았다.
- `npm ci`, frozen Bundler, `pod install`이 exit 0으로 끝났다. Podfile 의존성 116개와 설치 Pod 117개를 기록했다.
- XcodeBuildMCP의 native build·install·launch가 성공했다. arm64, Debug, iOS 27.0, `BlueWallet` scheme을 사용했다. 빌드는 198,392 ms였다. build error는 0개였다. warning 554개는 기록했다. extension target도 빌드했다.
- 처음에는 JS bundle 로딩 화면이었다. Metro의 iOS bundle 응답 HTTP 200을 확인했다. 이어 실제 `Wallets`, `Add a wallet`, `Transactions` 첫 화면을 직접 확인했다. RN red box·crash·흰 화면은 없었다. accessibility snapshot 도구는 timeout이 났다. screenshot으로 첫 화면을 확인했다.
- 준비 뒤와 실행 뒤 audit가 통과했다. 변경 경로는 `ios/Podfile.lock` 하나였다. 네 checksum 값 외의 tracked byte는 같았다. index 변경과 숨김 flag는 0개였다. `Pods/Manifest.lock`도 같았다.

이 표본은 ADR-0018의 준비 예외를 적용한 검증 조합에서 known-good이다. ADR-0017의 strict tracked 무변경 표본으로 보고하지 않는다. baseline 앱과 Metro를 중지한 뒤 Go를 시작했다.

### Go

별도 fresh clone도 clone 직후 tracked blob 1,410개가 HEAD와 같았다. 같은 npm·Ruby·Pod 준비를 적용했다. 준비 뒤 audit가 통과했다.

`mobile doctor --json`은 exit 0이었다. 11개 check가 모두 `pass`였다. `error`와 `unknown`은 0개였다. Xcode와 runtime 요구는 untracked override에서 왔다.

`mobile build --json`은 exit 0, 전체 `pass`였다. `validate`와 `dependencies`가 `pass`였다. 같은 simulator가 이미 booted라 `device`는 `skipped`였다. native `build`는 `pass`, 119,664 ms였다. build 뒤 audit도 통과했다. 두 clone의 Pods deployment target 258개 구성은 모두 15.1 이상이었다. mobile의 target 보정 없이 빌드했다.

`mobile up --json`은 exit 0, 전체 `pass`였다. 아래 stage 결과를 기록했다.

| stage | status | duration ms |
| --- | --- | ---: |
| validate | pass | 1,430 |
| dependencies | pass | 31,551 |
| device | skipped: 같은 simulator가 이미 booted | 168 |
| metro | pass: 새 Metro 시작 | 1,767 |
| build | pass | 121,618 |
| install | pass | 880 |
| launch | pass | 120,440 |

`up`이 새 Metro를 시작했다. listener의 실제 cwd는 Go clone이었다. baseline Metro가 종료돼 port 8081이 비어 있음을 `up` 전에 확인했다. 설치한 bundle ID는 `io.bluewallet.bluewallet`이었다. JSON에 app PID와 iOS 27.0 device가 기록됐다.

`launch`에는 `Metro still bundling` 메모가 남았다. Metro 로그는 progress가 없는 `BUNDLE ./index.js`와 `BUNDLE navigation/DrawerRoot.tsx`를 출력했다. 현재 완료 감지는 `100%` 또는 `Running ... with {` 신호를 기다리므로 120초를 기다렸다. 이 메모를 완료 신호로 해석하지 않았다. 별도로 실제 앱의 `Wallets`, `Add a wallet`, `Transactions` 첫 화면을 screenshot과 accessibility snapshot으로 확인했다. RN red box·crash·흰 화면은 없었다. 이 화면 확인이 게이트의 초기 UI 증거다. readiness 메모 개선은 후속 사항이다. Go blocker는 아니다.

`up` 뒤에도 실제 tracked blob 1,410개를 다시 확인했다. 네 checksum 값 외의 변경은 없었다. index 변경과 숨김 flag는 0개였다. `Pods/Manifest.lock`은 준비된 lockfile과 같았다. 아래 값은 최종 audit에서 확인한 checksum이다.

| SPEC CHECKSUMS 항목 | HEAD | baseline | Go |
| --- | --- | --- | --- |
| hermes-engine | `86cdbf283775c54dc008895c3eacd24a1f2a40b4` | `6efbc53a52933d05233dede38d873951f3f8cbea` | `662c35a482632335a0beb98723836927ffb68ec3` |
| React-Core-prebuilt | `9e875134f667c471ab68bf9edf1661fa11b86540` | `67b31a50446ec874f1523e650ff1ca0850c70ab3` | `0617d417a540f84727bf65e59ca1cf846d2e934d` |
| ReactCodegen | `d9475a746f5735bf5e403a1e25e451306ebaae8b` | `1bd7f2174582b0e142f8671735b5c906c08b72ea` | `1bd7f2174582b0e142f8671735b5c906c08b72ea` |
| ReactNativeDependencies | `0a5c93845772e4b1c5ad065c59a859518b13a6b7` | `be632191b9048d07624d6943fc3213404be0ec1b` | `d33a481d435298b577a35d4c733710153a44d78e` |

npm은 승인 목록 밖의 install script 7개와 `react-native-screens` patch 버전 차이를 경고했다. 설치는 exit 0이었다. 선언된 patch를 그대로 적용했다. 승인 목록과 patch 파일을 바꾸지 않았다. 초기 UI 이후의 앱 기능은 검증하지 않았다.

고정 mobile source의 [CI run 37557571056](https://github.com/minjunkim-dev/mobile-runtime/actions/runs/37557571056)은 성공했다. 문서 PR의 최종 head CI도 merge 전에 확인한다. raw 로그, screenshot, host 경로, simulator UDID, 환경값은 공개 문서에 넣지 않는다.

## 판정 범위

현재 gate는 ADR-0018의 단일 표본 1/1이다. 이전 세 프로젝트의 No-Go와 준비 실패는 유지한다. Xcode 26.6 이하를 검증하지 않았다. Xcode 27.1 RC와 다른 Xcode 27 정식 버전도 이번 결과에 합산하지 않았다. Matrix와 mobile 소스는 수정하지 않았다. 이름 결정과 외부 배포 실행은 별도 map으로 남긴다.

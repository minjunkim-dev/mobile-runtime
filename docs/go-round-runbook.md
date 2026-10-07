# Xcode 27 Go round

기준은 [ADR-0018](adr/0018-use-one-xcode-27-go-sample.md)에 고정했다. 실행 ticket은 [#160](https://github.com/minjunkim-dev/mobile-runtime/issues/160)이다. 입력은 실행 전에 기록했다. 기존 세 프로젝트와 BlueWallet 조사 실행의 성공을 합산하지 않는다.

## 입력과 절차

ADR-0018의 표본 SHA, mobile SHA, 도구 버전을 사용한다. 별도 fresh clone 두 개를 사용한다. baseline은 mobile 없이 실행한다. Go는 같은 준비 뒤 `mobile doctor --json`, `mobile build --json`, `mobile up --json`을 프로젝트 root에서 실행한다.

두 clone에서 `npm ci --no-audit --no-fund`, `BUNDLE_FROZEN=true bundle _2.6.9_ install`, `ENTERPRISE_REPOSITORY=https://repo.reactnative.dev/maven2 BUNDLE_FROZEN=true bundle _2.6.9_ exec pod install`을 실행한다. pod 명령은 `ios`에서 실행한다. 도구는 ADR-0018의 버전으로 선택한다. extension target은 유지한다.

의존성 다운로드 cache를 두 clone에 동일하게 사용한다. RN core·dependencies의 debug·release archive 네 개는 공식 mirror의 `.sha1`과 일치함을 확인했다. 이 cache는 배포된 의존성 archive다. 이전 실행의 앱, 생성된 Pods 프로젝트, 앱 빌드 결과는 복사하지 않는다. baseline의 첫 다운로드는 중지하고 같은 명령으로 재개했다.

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

2026-10-07 실행 대기다. 판정은 No-Go다. baseline과 Go 결과를 확인한 뒤 이 절에 sanitized 증거를 기록한다. raw 로그, screenshot, host 경로, simulator UDID, 환경값은 공개 문서에 넣지 않는다.

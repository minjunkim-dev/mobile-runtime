# Runstir (런스터)

Reproducible mobile development environments.

`doctor`, `build`, `up`은 프로젝트의 Gradle, package manager, Podfile 코드를
실행 사용자 권한과 상속된 환경으로 실행한다. `doctor`는 파일 검사에 그치지 않는다.
신뢰한 프로젝트에서만 실행한다. 검토하지 않은 프로젝트는 민감한 환경값이 없는
별도 환경에서 조사한다.

```
git clone my-app
cd my-app
mobile up
```

North Star: `git clone → mobile up`.

Status: iOS React Native MVP와 Android Phase 4A CLI provider 구현이 `main`에
반영됐다. Private Phase 4A Android 내부 alpha는 SHA를 고정한 공개 OSS 실제 앱
표본 하나와 macOS 검증 조합 하나에서 통과했다(#128). 일반적인 React Native
Android 지원을 뜻하지 않는다. CLI가 현재 실행 표면이고,
SwiftUI macOS 앱은 같은 Core/provider 계약을 표현할 후속 표면이다. 현재 계약과
제약은 [CONTEXT.md](CONTEXT.md)와 [ADRs](docs/adr/)에 둔다.

개발 `main`의 소스 없는 앱 파일 실행은 [지원·실제 검증 상태](docs/app-file-direct-install.md#지원과-실제-검증-상태)를 확인한다.
대표 iOS Development 실기기 결과와 미검증 Ad Hoc·Android 실기기를 구분하며, 공개 배포판의 검증 완료를 뜻하지 않는다.

제품명은 Runstir다. CLI 명령어는 `mobile`이다. iOS의 Xcode 27 Go 게이트는
고정 BlueWallet 표본과 검증 조합에서 통과했다. [실행 증거](docs/go-round-runbook.md)를 확인한다.
일반적인 React Native 지원을 뜻하지 않는다.

## 설치

GitHub Releases에서 macOS Apple Silicon용 archive 하나에 iOS와 Android를 함께 제공한다. Homebrew로 같은 archive를 설치할 수 있다.
현재 release version은 `0.1.0-alpha.4`다. 내부 CLI version은 `0.1.0`이다.
[설치 안내](docs/release-install.md)를 따른다. 실행 파일과 두 resource bundle을 함께 유지한다.
배포물의 직접 다운로드·실행 검증이 끝나기 전에는 공개 배포 완료로 판정하지 않는다.
검증 조합과 결과는 release notes에 기록한다. 다른 호스트의 배포는 후속 작업이다.

## Building

```
swift build
swift test
.build/debug/mobile doctor        # host checks; --json for machines, -v for detail
.build/debug/mobile build         # validate and compile; no Metro, install, or launch
.build/debug/mobile doctor --platform android --json
.build/debug/mobile build --platform android
.build/debug/mobile up --platform android --json # build, install, and launch on an existing AVD
.build/debug/mobile down --platform android --json
```

React Native·Flutter에서 의존성을 직접 준비했다면 `mobile build/up --prepared-dependencies` 또는
GUI의 **직접 준비한 의존성 사용**을 명시적으로 선택할 수 있습니다. 기본값은 꺼짐입니다.
이 모드는 의존성 재설치와 lock 정렬 재검증을 생략합니다. Flutter plugin resolver를 포함한 의존성 정합성은 사용자가 확인해야 합니다.
Flutter의 추적된 내부 source 파일 링크는 링크·대상·부모를 검증해 허용하며, 외부·directory 링크와 lock·metadata·SDK 경계는 유지합니다.
RN의 node_modules·미완료 표식, Flutter의 workspace 준비 파일·생성 경로·SDK, iOS Pods와 workspace 검사는 유지합니다.
[ADR-0047](docs/adr/0047-explicit-manually-prepared-rn-dependencies.md)과 [ADR-0048](docs/adr/0048-explicit-manually-prepared-flutter-dependencies.md)의 경계를 따르며 setup·native·down에는 적용하지 않습니다.


원시 로그와 오류 JSON에는 프로젝트 도구 출력이 그대로 남을 수 있다. 원시
로그는 민감정보로 보고, 공유하거나 이슈에 붙이기 전에 확인한다.

Exit codes: `0` no errors, `1` domain failure, `2` tool failure, `64` usage error.

### `build --json` and `up --json`

Machine consumers should use exit code `0`, or the absence of the top-level
`error` key, to detect success. A successful document omits `error`; it does not
emit `"error": null`. `status` describes how clean the environment is and may be
`warning` on a successful run, so do not require `status == "pass"`.

On failure, `result` may still contain device or Metro state collected before
the failure.

`Core` may not depend on Apple frameworks. Linux has none, so compiling it there
is that boundary — run `scripts/verify-core-linux.sh` (Docker) after touching
`Sources/Core`.

Android uses an already-installed compatible Emulator, SDK, and JDK; the provider
does not provision them. The Android alpha handoff, public OSS sample, exact
SHAs, validation tuple, and sanitized evidence are in
[`docs/private-android-alpha-runbook.md`](docs/private-android-alpha-runbook.md).

## License

Copyright 2026 MINJUN KIM

SPDX-License-Identifier: Apache-2.0

Apache License 2.0. 전문은 [LICENSE](LICENSE).

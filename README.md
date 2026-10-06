# mobile (working name)

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

이 저장소는 pre-alpha이고 working name은 `mobile`이다. No-Go이며, 소스 공개가
외부 배포나 일반 지원을 보증하지 않는다.

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

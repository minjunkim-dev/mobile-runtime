# 구현 스택 비교 조사: Swift(SPM) vs Go vs Rust vs TypeScript(Bun)

> Issue #2 리서치 결과. **결정 없음 — 사실 수집만.** 결정은 후속 grilling 티켓에서.
> 조사일: 2026-08-13

대상: "reproducible mobile development runtime" CLI + core. 코드 대부분이 simctl / xcodebuild / gradle 등 외부 프로세스 호출(orchestration)이라는 전제.

## 요약 비교표

| 기준 | Swift (SPM) | Go | Rust | TypeScript (Bun) |
|---|---|---|---|---|
| 단일 바이너리 | macOS는 사실상 기본(런타임 OS 내장). Linux는 Static Linux SDK로 완전 정적 링크 가능하나 Go만큼 매끄럽지 않음 | `go build` 한 방, 크로스컴파일 표준 기능 | `cargo build --release`, cross/zig로 크로스컴파일 성숙 | `bun build --compile`로 가능하나 런타임 포함 ~50–100MB. `--target`으로 크로스컴파일 지원 |
| Homebrew 배포 | 쉬움(선례 다수: xcodes, tuist, swiftformat 등). bottle 빌드에 macOS Xcode 필요 | 가장 쉬움. 바이너리 릴리스 + tap 또는 core 편입 표준 경로 | Go와 동급으로 쉬움 (mise 등 선례) | 가능하나 2류: node_modules를 libexec에 격리해야 하고, 네이티브 애드온 있으면 node 메이저 버전마다 rebuild. bun 컴파일 바이너리로 우회 가능하나 용량 큼 |
| Linux CI에서 Android 파트 | Swift는 공식 Linux 지원. 단 Foundation 서브셋(FoundationNetworking 등 분리), 정적 링크 시 몇 가지 함정 있음. Apple 프레임워크 의존 없이 짜면 동작 | 문제 없음(1급 지원) | 문제 없음(1급 지원) | 문제 없음(bun/node 모두 Linux 1급) |
| 모바일 개발자 기여자 풀 | **최적**. iOS 개발자는 그대로 기여 가능. tuist가 "프로젝트 정의를 Swift로 쓰면 기존 지식을 그대로 활용"을 명시적 셀링포인트로 삼음 | 모바일 개발자 대부분 비주류 언어. 다만 배우기 쉬움 | 모바일 개발자 풀에서 가장 낯섦(러닝커브 최대) | RN/Expo 계열 개발자에게 친숙. 네이티브(iOS/Android) 개발자에겐 중립 |
| macOS GUI 코어 재사용 | **직접 import**. core를 SPM 라이브러리로 두면 SwiftUI 앱에서 그대로 사용 | C FFI(cgo 역방향, buildmode=c-archive) 필요. 실무에서 잘 안 쓰는 경로 | UniFFI(Mozilla)로 Swift 바인딩 자동 생성 — Firefox가 실전 검증. cargo-swift로 Swift Package 패키징 가능. 다만 빌드 파이프라인 한 층 추가 | GUI에서 재사용하려면 Node/Bun 사이드카 프로세스(Tauri/Electron 패턴) 또는 JSC 임베드 — 간접적 |
| subprocess DX | 종전 Foundation.Process는 Obj-C 시절 API로 낙후(파이프 데드락 등 footgun). **swift-subprocess**(swiftlang 공식, Swift 6.1+)가 async/await 기반으로 교체 중 — "Process를 대체할 canonical한 방법"이 목표. 신생이라 레퍼런스 적음 | `os/exec` 표준lib로 충분, 스트리밍/파이프/컨텍스트 취소 성숙. CLI 도구의 사실상 홈그라운드 | `std::process` + tokio::process / duct 등 성숙. 에러 처리 장황하지만 견고 | `child_process`/`Bun.spawn`/execa 등 성숙하고 인체공학 좋음. 스트리밍 로그 처리 쉬움 |

## 기준별 상세

### 1. 단일 바이너리 + Homebrew

- **Swift**: macOS 타깃은 런타임이 OS에 내장이라 SPM `swift build -c release` 산출물이 그대로 배포 가능. Linux는 Swift 5.3.1부터 stdlib 정적 링크 지원, 이후 [Static Linux SDK](https://www.swift.org/documentation/articles/static-linux-getting-started.html)로 libc까지 완전 정적 링크 가능해짐. 단 "go build만큼 straightforward하지 않다"는 평가, 크로스컴파일(x86_64→aarch64 + static-stdlib) 이슈 사례 존재([forums](https://forums.swift.org/t/aarch64-cross-compilation-not-working-with-static-swift-stdlib/76439)).
- **Go/Rust**: 단일 정적 바이너리 + 크로스컴파일이 표준 워크플로. Homebrew tap에 바이너리 릴리스 물리는 것이 가장 마찰 없음.
- **TypeScript**: 전통 경로(npm 기반 formula)는 Homebrew 공식 문서가 node_modules 격리·네이티브 애드온 rebuild 이슈를 명시([Node for Formula Authors](https://docs.brew.sh/Node-for-Formula-Authors.html)). `bun build --compile`은 [단일 실행 파일](https://bun.com/docs/bundler/executables) + `--target` 크로스컴파일을 지원하지만 Bun 런타임 포함으로 **~50–100MB**.

### 2. Linux CI runner에서 Android 파트 실행

네 후보 모두 "가능". 차이는 마찰 수준.

- Go / Rust / TS: Linux 1급 플랫폼. 논점 없음.
- Swift: 공식 Linux 툴체인 존재(swift-subprocess도 macOS/Linux/Windows 지원 명시). 단 Foundation이 서브셋이고(FoundationNetworking 분리, weak-link로 인한 정적 링크 누락 함정 사례), CI 이미지에 Swift 툴체인 설치 단계가 추가됨. Apple 전용 프레임워크를 core에서 격리하는 규율 필요.
- 공통 전제: Android 파트의 실제 무게(gradle, adb, sdkmanager)는 어차피 JVM/플랫폼 도구라 CLI 언어와 무관.

### 3. 오픈소스 기여자 풀 (모바일 개발자 관점)

- 이 도구의 타깃 사용자 = iOS/Android 개발자. **사용자가 곧 기여자 후보**라는 관점에서 Swift가 구조적 우위 (tuist, xcodes 커뮤니티가 실증).
- TypeScript는 RN/Expo/Flutter-web 계열까지 포함하면 풀이 가장 넓지만, "네이티브 툴링에 관심 있는 개발자"로 좁히면 Swift 쪽으로 기움.
- Rust는 mise/moon 같은 devtool 기여자 풀은 활발하나 모바일 개발자와 교집합이 작음. Go도 유사.

### 4. macOS GUI에서 core 재사용

- **Swift**: core를 SPM 타깃으로 분리하면 SwiftUI 앱이 `import Core` 한 줄. 유일하게 변환 계층이 0.
- **Rust**: [UniFFI](https://github.com/mozilla/uniffi-rs)가 Swift/Kotlin 바인딩 자동 생성, Firefox 모바일/데스크톱에서 실전 사용. [cargo-swift](https://github.com/antoniusnaumann/cargo-swift)로 Swift Package화 가능. 검증된 경로지만 IDL/proc-macro 관리 + 빌드 파이프라인 복잡도 추가.
- **Go**: `-buildmode=c-archive` + cgo 헤더로 가능은 하나 UniFFI급 자동화 생태계 부재. 실무 선례 드묾.
- **TypeScript**: in-process 재사용 불가. GUI가 CLI를 사이드카 프로세스로 spawn하는 구조(Tauri 사이드카 패턴)가 현실적 — 이는 "GUI가 CLI의 껍데기"라는 아키텍처를 강제함(반드시 나쁜 건 아님).

### 5. subprocess orchestration DX

이 도구의 본질 = simctl/xcodebuild/gradle 호출 래퍼.

- **Go**: `os/exec` + context 취소 + 파이프 스트리밍이 표준lib만으로 완결. 이 장르(CI runner, 빌드 도구)의 최다 선례 언어.
- **TS**: `Bun.spawn`/execa 등 인체공학 최상. async 스트림 처리 자연스러움.
- **Rust**: 성숙하고 견고. 타입/에러 처리가 장황한 대신 실수 여지 적음.
- **Swift**: 종전 `Foundation.Process`는 NSTask 유래로 "언어 진화를 못 따라왔다"고 공식 인정([proposal](https://github.com/swiftlang/swift-foundation/blob/main/Proposals/0007-swift-subprocess.md)). 공식 후속 [swift-subprocess](https://github.com/swiftlang/swift-subprocess)(Swift 6.1+, structured concurrency 기반, 크로스플랫폼)가 "canonical한 프로세스 실행 방법으로 Process를 대체" 목표. API는 현대적이나 2025년에야 안정화된 신생 — 커뮤니티 레퍼런스와 엣지케이스 축적이 타 언어 대비 얇음.

### 6. 유사 도구 선례

| 도구 | 언어 | 선택 이유 / 알려진 후회·한계 |
|---|---|---|
| [fastlane](https://docs.fastlane.tools/) | Ruby | 2014년 당시 iOS 커뮤니티 표준 스크립트 언어. **후회 사례의 대표격**: 시스템 Ruby 사용 비권장, Ruby/bundler 버전 매트릭스 관리가 CI 통증 포인트(Ruby 3.4+에서 default gem 제거로 파손 등, [discussion](https://github.com/fastlane/fastlane/discussions/29812)). "로컬과 CI의 Ruby+fastlane 버전을 맞춰라"가 공식 가이드일 정도로 런타임 의존이 부채 |
| [maestro](https://github.com/mobile-dev-inc/Maestro) | Kotlin/JVM | Android 툴링(adb, idb 클라이언트)과의 JVM 생태계 친화성. 한계: **Java 17+ 설치 요구** — 단일 바이너리 아님, curl \| bash 설치 스크립트로 JVM 의존을 감춤 |
| [xcodes](https://github.com/XcodesOrg/xcodes) | Swift | Apple 생태계 전용 도구라 Swift가 자연스러움. Homebrew tap 배포 문제없음. macOS 전용이라 Linux 논점 자체가 없음 |
| [tuist](https://github.com/tuist/tuist) | Swift | "프로젝트 정의도 Swift" — 사용자(iOS 개발자)의 기존 지식·툴링 재활용을 명시적 설계 원칙으로 삼음. 전부 Swift + SPM 모노레포로 대규모 CLI 유지보수 실증 |
| [mise](https://mise.jdx.dev/dev-tools/comparison-to-asdf.html) | Rust | asdf(bash) 대비 20–200x 성능, shim 제거, Windows 지원이 Rust 선택 이유. devtool CLI에서 Rust의 배포·성능 우위 실증 |
| [Bitrise CLI](https://github.com/bitrise-io/bitrise) | Go | 모바일 CI runner를 Go로 — "Mac/Linux 머신에서 워크플로 실행"이라는 본 프로젝트와 가장 유사한 문제를 Go 단일 바이너리로 해결한 선례 |
| EAS CLI (Expo) | TypeScript/Node | 사용자 기반(RN 개발자)이 이미 Node 보유 → npm 배포가 오히려 자연스러움. 단 네이티브-only 개발자에겐 Node 런타임이 추가 의존 |
| xcbeautify, swiftformat, periphery | Swift | Apple 툴체인 주변 도구들은 Swift + Homebrew 조합이 사실상 관례로 정착 |

선례에서 읽히는 패턴:
- **런타임 의존(Ruby/JVM/Node)은 시간이 갈수록 부채가 된다** — fastlane과 maestro가 각각 증언. 단일 바이너리 계열(Go/Rust/Swift-macOS)은 이 문제가 없음.
- **"사용자 언어 = 구현 언어" 전략**(tuist/Swift, EAS/TS)은 기여자 풀과 DSL 재사용에서 이득.
- **"인프라 언어" 전략**(Bitrise/Go, mise/Rust)은 배포·성능·크로스플랫폼에서 이득.
- 이 프로젝트는 두 전략이 정확히 충돌하는 지점에 있음 (Swift ↔ Go/Rust). 이 트레이드오프가 grilling 티켓의 핵심 논점.

## 출처

- swift-subprocess: https://github.com/swiftlang/swift-subprocess , 제안서 https://github.com/swiftlang/swift-foundation/blob/main/Proposals/0007-swift-subprocess.md
- Swift Static Linux SDK: https://www.swift.org/documentation/articles/static-linux-getting-started.html
- Swift 정적링크/크로스컴파일 이슈: https://forums.swift.org/t/static-linking-on-linux-in-swift-5-3-1/41989 , https://forums.swift.org/t/aarch64-cross-compilation-not-working-with-static-swift-stdlib/76439
- Bun 단일 실행 파일: https://bun.com/docs/bundler/executables
- Homebrew Node formula 가이드: https://docs.brew.sh/Node-for-Formula-Authors.html
- mise vs asdf: https://mise.jdx.dev/dev-tools/comparison-to-asdf.html
- fastlane Ruby/CI 운영 가이드·이슈: https://www.polpiella.dev/install-ruby-and-gems-on-ci-cd , https://github.com/fastlane/fastlane/discussions/29812
- maestro (Kotlin, Java 17+ 요구): https://github.com/mobile-dev-inc/Maestro
- xcodes: https://github.com/XcodesOrg/xcodes
- tuist: https://github.com/tuist/tuist
- Bitrise CLI: https://github.com/bitrise-io/bitrise
- UniFFI: https://github.com/mozilla/uniffi-rs , cargo-swift: https://github.com/antoniusnaumann/cargo-swift

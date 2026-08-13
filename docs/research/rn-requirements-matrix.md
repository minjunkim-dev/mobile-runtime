# RN 프로젝트 환경 요구사항 소스 전수 조사 + Tier 2 호환성 매트릭스

> Issue #3 리서치 결과. 조사일: 2026-08-13.
> Tier 1 = repo 파일에 명시적으로 선언된 요구사항. Tier 2 = 선언은 없지만 호환성 매트릭스로 유도되는 요구사항.
> RN 버전별 실측 데이터는 `facebook/react-native` 및 `react-native-community/template`의 각 릴리즈 태그에서 파일을 직접 읽어 확인했다 (표 아래 출처 참조).

---

## 1. Tier 1: 요구사항 선언 파일 전수 목록 + 파싱 방법

### 1.1 Node / 패키지 매니저

| 파일 | 형식 / 정확한 문법 | 파싱 방법 | 비고 |
|---|---|---|---|
| `.nvmrc` | 한 줄 텍스트. `18`, `18.20.4`, `v18.20.4`, `lts/iron`, `lts/*`, `node` 모두 유효 | 파일 전체 trim → 버전 문자열. `v` prefix 제거. `lts/*` 별칭은 별도 해석 필요 | nvm 전용이지만 fnm도 읽음 |
| `.node-version` | 한 줄 텍스트. `18.20.4` 또는 `v18.20.4` | 동일 (trim, `v` 제거) | nodenv / fnm / asdf(레거시 플러그인) |
| `.tool-versions` | 줄 단위 `<도구> <버전> [fallback...]`, `#` 주석 허용. 예: `nodejs 18.20.4`, `ruby 3.2.2`, `java temurin-17.0.9` | 줄 split → 첫 토큰이 도구명. Node는 `nodejs`, Java는 `temurin-`/`openjdk-` 등 배포판 prefix 주의 | asdf. mise도 하위호환으로 읽음 |
| `mise.toml` / `.mise.toml` / `.config/mise/config.toml` | TOML. `[tools]` 테이블: `node = "20"`, `ruby = { version = "3.2" }`, 배열(`["20", "18"]`)도 유효 | TOML 파서 필수. 문자열/인라인 테이블/배열 3가지 케이스 처리 | mise는 `.tool-versions`도 읽으므로 mise.toml 우선 |
| `package.json` → `engines` | `"engines": { "node": ">=20", "npm": ">=10" }` — **semver range** (정확 버전 아님) | JSON 파싱 → semver range 매칭 | npm은 기본 경고만, yarn(berry)·pnpm은 에러. RN 템플릿 0.83 기준 `">=20"` 포함 |
| `package.json` → `packageManager` | `"packageManager": "yarn@3.6.4"` 또는 `+sha224.<hash>` suffix | `<이름>@<정확버전>[+hash]` split | corepack이 강제. 있으면 패키지 매니저 요구의 최우선 소스 |
| `package.json` → `volta` | `"volta": { "node": "18.20.4", "yarn": "1.22.19" }` — 정확 버전 | JSON 파싱 | Volta 사용 팀만. 존재 시 정확 pin이라 신뢰도 높음 |

### 1.2 Ruby / CocoaPods (iOS 툴체인)

| 파일 | 형식 / 문법 | 파싱 방법 | 비고 |
|---|---|---|---|
| `Gemfile` | Ruby DSL. `ruby ">= 2.6.10"`, `gem 'cocoapods', '>= 1.13', '!= 1.15.0'` | 완전 파싱은 Ruby 평가 필요. 실용적으로는 정규식: `^\s*ruby\s+(.+)$`, `^\s*gem\s+['"]cocoapods['"]\s*,\s*(.+)$` → 인자들을 gem requirement 리스트로 해석 | RN 템플릿에 항상 포함. cocoapods gem 제약이 여기 선언됨 |
| `Gemfile.lock` | Bundler 고유 포맷. `RUBY VERSION\n   ruby 3.2.2p53`, `BUNDLED WITH\n   2.4.10`, `GEM` 섹션에 `cocoapods (1.15.2)` | 섹션 헤더 기반 라인 파싱 | 설치된 정확 버전. 존재하면 Gemfile보다 구체적 |
| `.ruby-version` | 한 줄 `3.2.2` | trim | rbenv/rvm/asdf. **RN 템플릿에는 없음** (0.73·0.83 모두 미포함 확인) — 사용자가 직접 추가한 경우만 |
| `Podfile` | Ruby DSL. `platform :ios, '15.1'` 또는 RN 헬퍼 `platform :ios, min_ios_version_supported` | 리터럴이면 정규식, 헬퍼 호출이면 정적 파싱 불가 → `node_modules/react-native/scripts/cocoapods/helpers.rb`의 `min_ios_version_supported` 반환값으로 해석 | RN 기본 템플릿은 헬퍼 사용 |
| `Podfile.lock` | YAML. 최하단 `COCOAPODS: 1.15.2` | YAML 파싱 (또는 마지막 줄 정규식) | **lock을 생성한 CocoaPods 버전** 기록. 호스트 pod 버전과 다르면 lock 재생성 diff 발생 위험 → doctor의 좋은 검증 포인트 |

### 1.3 Android (Gradle / SDK)

| 파일 | 형식 / 문법 | 파싱 방법 | 비고 |
|---|---|---|---|
| `android/gradle/wrapper/gradle-wrapper.properties` | Java properties. `distributionUrl=https\://services.gradle.org/distributions/gradle-8.14.3-bin.zip` | properties 파싱 (`\:` 이스케이프 주의) → 정규식 `gradle-([\d.]+(?:-\w+)?)-(bin|all)\.zip` | 사실상 100% 존재 + 정확 버전. Android 소스 중 최고 신뢰도 |
| `android/build.gradle` (루트) | Groovy DSL. RN 관례: `ext { buildToolsVersion = "36.0.0"; minSdkVersion = 24; compileSdkVersion = 36; targetSdkVersion = 36; ndkVersion = "..."; kotlinVersion = "..." }`. 구식 프로젝트는 `classpath("com.android.tools.build:gradle:8.x.x")` | 정규식으로 충분: `(compileSdk\|targetSdk\|minSdk)(Version)?\s*[=]?\s*(\d+)`, `buildToolsVersion\s*=\s*"([\d.]+)"` | RN 템플릿은 ext 블록 관례 유지 중 (0.83까지 확인) |
| `android/app/build.gradle(.kts)` | `android { compileSdk 36 }` / kts: `compileSdk = 36` | 루트 ext를 참조(`rootProject.ext.compileSdkVersion`)하는 게 RN 관례 → 루트 우선 파싱, 리터럴이면 앱 모듈 값이 우선 | |
| `gradle/libs.versions.toml` | TOML. `[versions] agp = "8.12.0"` / `[plugins] android-application = { id = "com.android.application", version.ref = "agp" }` | TOML 파싱 | **주의**: RN 앱 템플릿의 android 폴더에는 AGP 버전이 명시되지 않음 — AGP는 `com.facebook.react.settings` 플러그인 경유로 RN이 관리. 정확한 AGP는 `node_modules/react-native/gradle/libs.versions.toml`의 `agp` 키에서 읽는 것이 확실 |
| `android/settings.gradle` | `pluginManagement { ... }`, `plugins { id("com.facebook.react.settings") }` | 버전 리터럴이 있으면 정규식 | 보통 버전 정보 없음 |
| `.pbxproj` (`ios/*.xcodeproj/project.pbxproj`) | NeXTSTEP old-style plist. `IPHONEOS_DEPLOYMENT_TARGET = 15.1;` (Debug/Release 설정마다 반복) | 정규식 `IPHONEOS_DEPLOYMENT_TARGET\s*=\s*([\d.]+)` → 최소값 채택 | Podfile platform과 이중 선언. Xcode 버전 자체는 **어디에도 선언되지 않음** → Xcode는 Tier 2 전용 |

### 1.4 RN 버전 자체의 소스

| 소스 | 내용 | 신뢰도 |
|---|---|---|
| `node_modules/react-native/package.json` → `version` | 설치된 정확 버전 | 최상 (설치돼 있을 때) |
| `yarn.lock` / `package-lock.json` / `pnpm-lock.yaml` | resolve된 정확 버전 | 상 (미설치여도 판별 가능) |
| `package.json` → `dependencies["react-native"]` | semver range (`0.83.1`, `^0.83.0`) | range라서 최후 수단 |

---

## 2. Tier 2: 호환성 매트릭스 실데이터

### 2.1 RN 버전별 요구사항 (0.73 ~ 0.87)

Node/Xcode/JDK/CocoaPods/최소 Android 열은 릴리즈 워킹그룹 공식 지원 표([reactwg/react-native-releases support.md](https://github.com/reactwg/react-native-releases/blob/main/docs/support.md)) 기준.
AGP/Gradle/SDK/iOS 열은 각 릴리즈 태그의 실제 파일에서 실측:
- AGP: `packages/react-native/gradle/libs.versions.toml`
- Gradle/compileSdk/targetSdk/minSdk/buildTools: 템플릿 `android/gradle/wrapper/gradle-wrapper.properties`, `android/build.gradle` (0.73~0.74는 `facebook/react-native` 내 template, 0.75+는 [`react-native-community/template`](https://github.com/react-native-community/template))
- 최소 iOS: `packages/react-native/scripts/cocoapods/helpers.rb`의 `min_ios_version_supported`
- Node 최소: `packages/react-native/package.json`의 `engines.node`

| RN | Node 최소 | Xcode 최소 | JDK | AGP (템플릿) | Gradle (템플릿) | compileSdk / buildTools | targetSdk | minSdk | 최소 iOS | CocoaPods |
|---|---|---|---|---|---|---|---|---|---|---|
| 0.73 | ≥18 | 15.1¹ | 17 | 8.1.1 | 8.3 | 34 / 34.0.0 | 34 | 21 | 13.4 | 1.13.x~1.15.2 |
| 0.74 | ≥18 | 15.1 | 17 | 8.2.1 | 8.6 | 34 / 34.0.0 | 34 | 23 | 13.4 | 〃 |
| 0.75 | ≥18 | 15.1 | 17 | 8.5.0 | 8.8 | 34 / 34.0.0 | 34 | 23 | 13.4 | 〃 |
| 0.76 | ≥18 | 15.1 | 17 | 8.6.0 | 8.10.2 | 35 / 35.0.0 | 34 | 24 | 15.1 | 〃 |
| 0.77 | ≥18 | 15.1 | 17 | 8.7.2 | 8.10.2 | 35 / 35.0.0 | 34 | 24 | 15.1 | 〃 |
| 0.78 | ≥18 | 15.1 | 17 | 8.8.0 | 8.12 | 35 / 35.0.0 | 35 | 24 | 15.1 | 〃 |
| 0.79 | ≥18 | 15.1 | 17 | 8.8.2 | 8.13 | 35 / 35.0.0 | 35 | 24 | 15.1 | 〃 |
| 0.80 | ≥18 | 15.1 | 17 | 8.9.2 | 8.14.1 | 35 / 35.0.0 | 35 | 24 | 15.1 | 〃 |
| 0.81 | ≥20.19.4 | 16.1 | 17 | 8.11.0 | 8.14.3 | 36 / 36.0.0 | 36 | 24 | 15.1 | 〃 |
| 0.82 | ≥20.19.4 | 16.1 | 17 | 8.12.0 | 9.0.0 | 36 / 36.0.0 | 36 | 24 | 15.1 | 〃 |
| 0.83 | ≥20.19.4 | 16.1 | 17 | 8.12.0 | 9.0.0 | 36 / 36.0.0 | 36 | 24 | 15.1 | 〃 |
| 0.84 | ≥22.11.0 | 16.1 | 17 | — | — | — | — | — | — | 〃 |
| 0.85 | ≥22.11.0 | 16.1 | 17 | — | — | — | — | — | — | 〃 |
| 0.86 | ≥22.11.0 | 16.1 | 17 | — | — | — | — | — | — | 〃 |
| 0.87 | ≥22.11.0 | **26.0** | 17 | — | — | — | — | — | — | 〃 |

¹ support.md는 "현재 지원 정책" 기준으로 소급 갱신되는 문서라, 0.73 출시 당시 최소 Xcode(14.3)와 다를 수 있음. doctor 매트릭스는 support.md를 원본으로 삼는 것이 유지보수상 옳다 (아래 4절).

주요 변곡점 요약:
- **0.73**: JDK 11→17, AGP 8.x 진입
- **0.76**: 최소 iOS 13.4→15.1, minSdk 23→24, compileSdk 35
- **0.81**: Node 18→20.19.4, Xcode 16.1 필수, compileSdk 36 (Android 16 edge-to-edge 강제) — [릴리즈 블로그](https://reactnative.dev/blog/2025/08/12/react-native-0.81)
- **0.82**: Gradle 9 진입
- **0.84**: Node 22.11.0 (LTS)
- **0.87**: Xcode 26 필수

### 2.2 AGP 버전 → 최소 Gradle / JDK / 최대 API level (Google 공식)

출처: [AGP 릴리즈 노트](https://developer.android.com/build/releases/gradle-plugin) 및 각 버전별 릴리즈 노트 페이지 (`developer.android.com/build/releases/past-releases/agp-X-Y-0-release-notes`). 8.9/8.11/8.12/9.0/9.3 행은 해당 페이지에서 직접 확인.

| AGP | 최소 Gradle | 필요 JDK (최소) | 기본 buildTools | 최대 API level |
|---|---|---|---|---|
| 7.0~7.4 | 7.0~7.5 | **11** | — | 33 |
| 8.0 | 8.0 | **17** | 30.0.3 | 33 |
| 8.1 | 8.0 | 17 | 33.0.1 | 34 |
| 8.2 | 8.2 | 17 | 34.0.0 | 34 |
| 8.3 | 8.4 | 17 | 34.0.0 | 34 |
| 8.4 | 8.6 | 17 | 34.0.0 | 34 |
| 8.5 | 8.7 | 17 | 34.0.0 | 34 |
| 8.6 | 8.7 | 17 | 34.0.0 | 34 |
| 8.7 | 8.9 | 17 | 35.0.0 | 35 |
| 8.8 | 8.10.2 | 17 | 35.0.0 | 35 |
| 8.9 | 8.11.1 | 17 | 35.0.0 | 35 |
| 8.10 | 8.11.1 | 17 | 35.0.0 | 35 |
| 8.11 | 8.13 | 17 | 35.0.0 | 36 |
| 8.12 | 8.13 | 17 | 35.0.0 | 36 |
| 8.13 | 8.13 | 17 | 36.0.0 | 36 |
| 9.0 | 9.1.0 | 17 | 36.0.0 | 36.1 |
| 9.3 | 9.5.0 | 17 | 36.0.0 | 37 |

핵심: **RN 0.73+ 범위에서는 AGP가 전부 8.x/9.x → JDK 최소 요구는 항상 17로 단순**. 복잡한 건 JDK **상한** 쪽이다 (아래 2.3).

### 2.3 Gradle 실행 가능 JDK 범위 (JDK 상한 검증용)

doctor가 잡아야 할 흔한 실패는 "JDK가 너무 낮음"이 아니라 "**너무 새 JDK + 오래된 Gradle**" (예: JDK 21 + Gradle 8.3 → 빌드 실패). 출처: [Gradle Compatibility Matrix](https://docs.gradle.org/current/userguide/compatibility.html).

| JDK | Gradle 실행 지원 시작 버전 |
|---|---|
| 17 | 7.3 |
| 20 | 8.3 |
| 21 | 8.5 |
| 22 | 8.8 |
| 23 | 8.10 |
| 24 | 8.14 |
| 25 | 9.1.0 |
| 26 | 9.4.0 |

즉 검증식: `gradle-wrapper.properties의 Gradle 버전`이 `호스트 JDK`를 지원하는가 (상한) AND JDK ≥ 17 (AGP 8+ 하한).

### 2.4 compileSdk → build-tools / platform 관계

- 관례: **build-tools 메이저 = compileSdk** (compileSdk 36 → `build-tools;36.0.0`). RN 템플릿도 이 관례를 따름 (2.1 표에서 전 구간 일치 확인).
- `buildToolsVersion`을 생략하면 AGP가 자기 기본 build-tools(2.2 표)를 사용 — 선언이 없어도 에러 아님.
- doctor 검증식: `sdkmanager` 기준으로 `platforms;android-<compileSdk>` 존재 + `build-tools;<compileSdk>.0.0` (또는 AGP 기본 버전) 존재.
- 상한: compileSdk가 AGP의 최대 API level(2.2 표)을 넘으면 AGP 경고/실패 → `compileSdk ≤ AGP 최대 API` 도 함께 검증 가능.

---

## 3. 소스 신뢰도와 우선순위 관례

### 3.1 파일별 존재 확률 (RN 프로젝트 관례 기준 추정)

| 소스 | 존재 확률 | 근거 |
|---|---|---|
| `package.json` (engines 포함 여부는 별개) | ~100% | 필수 파일. 템플릿에 `engines.node` 포함 (0.83: `>=20`) |
| `gradle-wrapper.properties` | ~100% | 템플릿 포함 + wrapper 관례가 사실상 표준 |
| 루트 `build.gradle` ext 블록 (SDK 버전들) | ~95% | RN 템플릿 관례. eject/커스텀 시 앱 모듈로 이동 가능 |
| `Podfile` | ~100% (iOS 지원 시) | 템플릿 포함 |
| `Podfile.lock` | ~80% | `pod install` 후 생성. CI-only 프로젝트는 커밋 안 할 수도 |
| `Gemfile` | ~90% | 0.70부터 템플릿 포함. 삭제하는 팀 존재 |
| `Gemfile.lock` | ~60% | bundler를 실제로 쓰는 팀만 |
| `.nvmrc` / `.node-version` | ~40% | 템플릿 미포함, 팀 관례로 추가 |
| `.tool-versions` / `mise.toml` | ~15% | asdf/mise 사용 팀만 |
| `packageManager` 필드 | ~30% | corepack 도입 팀. 증가 추세 |
| `.ruby-version` | ~10% | **RN 템플릿에 미포함** (0.73, 0.83 실측) |
| `libs.versions.toml` (앱 repo 내) | ~10% | RN 앱 템플릿은 미사용. brownfield/모노레포에서 등장 |

### 3.2 충돌 시 우선순위 관례

| 충돌 | 우선순위 관례 | 이유 |
|---|---|---|
| `.nvmrc` vs `engines.node` | 의미가 다름: `.nvmrc` = "개발 환경 pin"(정확 버전), `engines` = "동작 최소 요건"(range). doctor는 **둘 다 검증**하고, 호스트 Node가 `.nvmrc` pin과 다르면 warning, `engines` range 밖이면 error 권장 | npm은 engines를 경고만 하지만 yarn berry/pnpm은 에러 |
| `.nvmrc` vs `.node-version` vs `.tool-versions` vs `mise.toml` | 같은 "pin" 계층 안에서는 도구별 읽는 파일이 다를 뿐. 관례: `mise.toml > .tool-versions`(mise 기준), 나머지는 동급 — 서로 다르면 그 자체가 repo 버그이므로 **불일치 경고**가 올바른 동작 | |
| `packageManager` vs lockfile 종류 | `packageManager`가 정본 (corepack 강제). lockfile은 종류 판별용 | |
| `Gemfile ruby` vs `.ruby-version` | `Gemfile`이 정본 — bundler는 둘이 충돌하면 에러를 냄 | Bundler 동작 |
| `Gemfile`의 cocoapods 제약 vs `Podfile.lock COCOAPODS` | Gemfile = 요구 range, Podfile.lock = 마지막 실행 버전(사실 기록). 검증은 Gemfile range로, "호스트 pod ≠ lock 생성 버전"은 lock diff 경고로 | |
| `Podfile platform` vs pbxproj `IPHONEOS_DEPLOYMENT_TARGET` | CocoaPods 빌드에서는 Podfile이 pod 타깃을 지배, 앱 타깃은 pbxproj가 지배. doctor는 pbxproj 값(앱 실제값) 우선, 둘 불일치 시 경고 | |
| 앱 repo의 AGP 선언 vs `node_modules/react-native/gradle/libs.versions.toml` | 앱에 명시가 없으면 RN 것이 실효값. 앱에 명시가 있으면 앱 것이 우선 (오버라이드) | RN gradle plugin 구조 |
| Tier 1 선언 vs Tier 2 매트릭스 | **Tier 1이 항상 우선** (프로젝트가 명시했으면 그것이 진실). Tier 2는 Tier 1이 침묵하는 항목(특히 Xcode)만 채움 | 설계 원칙 |

---

## 4. Tier 2 매트릭스 유지보수 비용

최근 1년(2025-08 ~ 2026-08) 기준 매트릭스 행 추가/수정이 필요했던 릴리즈:

| 소스 | 릴리즈 횟수 (최근 1년) | 매트릭스 영향 |
|---|---|---|
| RN 마이너 (0.81~0.87, 7개) | 연 **6~7회** | 매번 1행 추가. 요구사항 자체가 바뀐 건 0.81(Node/Xcode/SDK), 0.84(Node), 0.87(Xcode) 3회 |
| AGP 마이너 (8.13, 9.0, 9.1, 9.2, 9.3) | 연 **~5회** | JDK 최소는 17로 불변 → 실질 갱신은 최소 Gradle/최대 API 행 추가 수준 |
| Xcode 메이저 (16→26) | 연 1회 (+마이너 수회) | RN 지원 표가 이미 반영하므로 별도 행 불필요 |
| Node LTS | 연 1회 | RN engines가 반영하므로 별도 행 불필요 |

**결론: 연 10~12회의 소규모(1행 추가) 갱신, 그중 "검증 로직에 영향 주는" 변화는 연 3~4회.**

비용 절감 권장사항:
1. 매트릭스를 코드가 아닌 **데이터 파일(JSON/TOML)로 분리**하고, 1행 추가 = 1커밋이 되게 한다.
2. 원본을 [reactwg support.md](https://github.com/reactwg/react-native-releases/blob/main/docs/support.md) 하나로 고정 — RN 팀이 Node/Xcode/JDK/CocoaPods/minSdk를 이미 유지보수해 주고 있고, 소급 갱신까지 해 준다. AGP/Gradle/SDK 열만 자체 실측(템플릿 파일 3개 curl)으로 보강하면 된다.
3. 갱신 감지는 support.md 파일의 변경 감시(주기적 diff)로 자동화 가능 — 사람이 추적할 릴리즈 캘린더가 필요 없다.

---

## 출처

- RN 공식 지원 표: https://github.com/reactwg/react-native-releases/blob/main/docs/support.md
- RN 0.81 릴리즈 블로그 (Node 20.19.4 / Xcode 16.1 / Android 16): https://reactnative.dev/blog/2025/08/12/react-native-0.81
- RN 0.83 릴리즈 블로그: https://reactnative.dev/blog/2025/12/10/react-native-0.83
- RN 템플릿 실측: `facebook/react-native` 태그별 `packages/react-native/gradle/libs.versions.toml`, `packages/react-native/scripts/cocoapods/helpers.rb`, `packages/react-native/package.json`; `react-native-community/template` 태그별 `template/android/*`
- AGP 릴리즈 노트 (버전별 호환성 표): https://developer.android.com/build/releases/gradle-plugin , past-releases: `agp-8-9-0`, `agp-8-11-0`, `agp-8-12-0`, `agp-9-0-0` 등
- Gradle–JDK 호환성 매트릭스: https://docs.gradle.org/current/userguide/compatibility.html
- Java versions in Android builds (AGP 8.x → JDK 17): https://developer.android.com/build/jdks

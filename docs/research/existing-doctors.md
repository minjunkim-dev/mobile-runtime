# 기존 doctor류 도구 분석

> Issue #4 리서치 결과. `mobile doctor` 스펙(프로젝트를 읽어 환경 그래프를 만들고 호스트를 검증)의 입력 자료.
> 조사일: 2026-08-13. 소스코드 직접 확인 기준 (main/master 브랜치).

---

## 1. `npx react-native doctor` (@react-native-community/cli-doctor)

### 검사 항목 전체

소스: [`packages/cli-doctor/src/tools/healthchecks/index.ts`](https://github.com/react-native-community/cli/blob/main/packages/cli-doctor/src/tools/healthchecks/index.ts)

| 카테고리 | 검사 항목 |
|---|---|
| Common | `nodeJS`, `yarn`, `npm`, `watchman`(macOS만) |
| Android | `adb`, `jdk`, `androidStudio`, `ANDROID_HOME` 환경변수, `gradle`, `androidNDK`(`--contributor` 플래그 시에만) |
| iOS (macOS만) | `xcode`, `ruby`, `cocoaPods` |
| 프로젝트 감지 시 추가 | `packager`(Metro 포트 점유), `androidSDK`, `xcodeEnv`(`.xcode.env` 파일) |

### 프로젝트별 요구사항을 읽는가?

**부분적으로만 읽는다.** 구조상 3단계:

1. `loadConfigAsync()`로 RN 프로젝트 config 로드를 시도. 실패하면 "detached mode"로 기본 검사만 실행 ("Detected that command has been run outside of React Native project, running basic healthchecks").
2. 프로젝트가 감지되면 `packager`/`androidSDK`/`xcodeEnv` 검사가 추가되고, 일부 검사(jdk, androidSDK 등)는 설치된 RN 버전에 맞는 버전 범위를 참조.
3. `react-native.config.js`의 `healthChecks` 필드로 **커스텀 검사를 주입할 수 있는 플러그인 포인트**가 존재 (`additionalChecks = config.healthChecks`). 다만 실제 생태계에서 거의 쓰이지 않음.

핵심 한계: 검사 목록과 버전 매트릭스가 **CLI 릴리스에 하드코딩**되어 있다. 프로젝트의 `build.gradle`(AGP/Kotlin/compileSdk), `Podfile`, `Gemfile`, `.nvmrc`, `package.json engines` 등 프로젝트가 실제로 선언한 요구사항을 파싱해서 검증하지는 않는다.

### 출력 형식

- 카테고리별 그룹핑된 ✓/✖/● 리스트 + 마지막에 `Errors: N / Warnings: N` 요약.
- 문제가 있으면 **인터랙티브 키 입력 대기** (`f` 전체 수정 / `e` 에러만 / `w` 경고만 / 종료). raw mode stdin 리스너 기반.

### 자동 수정 (`--fix`)

- 각 healthcheck가 `runAutomaticFix`를 구현하며, `win32AutomaticFix`/`darwinAutomaticFix`/`linuxAutomaticFix`로 **플랫폼별 수정 로직 오버라이드** 가능.
- `--fix` 플래그로 비대화식 전체 수정 가능. 수정 범위는 도구 설치 안내~환경변수 설정 안내 수준이 많고, 실제 설치를 대신 해주는 항목은 제한적.

### agent/CI 친화성

- `--json` **없음**. 출력은 사람용 컬러 텍스트뿐.
- exit code 규약 불명확: 검사 실패 시에도 인터랙티브 메뉴로 진입(키 입력 대기)하며, 수정 실패 시에만 `CLIError`. **CI에서 게이트로 쓰기 어렵다.**

---

## 2. `expo-doctor`

소스: [`packages/expo-doctor`](https://github.com/expo/expo/tree/main/packages/expo-doctor) (expo/expo 모노레포)

### 검사 항목 (src/checks/, 2026-08 기준 22개)

프로젝트/의존성 중심: `ExpoConfigSchemaCheck`(app.json을 SDK별 스키마로 검증), `ExpoConfigCommonIssueCheck`, `InstalledDependencyVersionCheck`(SDK 호환 버전 검증), `SupportPackageVersionCheck`(expo-modules-autolinking 등 지원 패키지), `PeerDependencyChecks`, `PackageJsonCheck`, `IllegalPackageCheck`, `DirectPackageInstallCheck`, `GlobalPackageInstalledLocallyCheck`, `LockfileCheck`, `PackageManagerVersionCheck`, `MetroConfigCheck`, `NativeToolingVersionCheck`(Xcode/CocoaPods 버전), `ProjectSetupCheck`, `ReactNativeDirectoryCheck`(New Architecture 호환성·유지보수 상태를 reactnative.directory 메타데이터로 검증), `StoreCompatibilityCheck`, `VectorIconsCheck`, `ExpoRouterReactNavigationCheck`, `AppConfigFieldsNotSyncedToNativeProjectsCheck`(prebuild 프로젝트에서 app.json 필드가 네이티브에 반영 안 되는 문제), `AutolinkingDependencyDuplicatesCheck`, `DependencyVersionOverrideCheck`, `EnvLocalFilesCheck`.

### SDK 버전 매트릭스 활용 방식

- `getProjectConfigAsync()`로 프로젝트의 `exp`(app config)와 `pkg`를 읽고, `resolveChecksInScope(exp, pkg)`가 **SDK 버전과 프로젝트 형태(managed/bare)에 따라 실행할 검사 집합을 동적으로 결정**. SDK 46 미만은 아예 거부.
- 의존성 버전 검증은 Expo가 서버에서 관리하는 SDK별 호환 버전 목록(bundled native modules API)과 대조 → **버전 매트릭스가 도구 릴리스가 아닌 서버 데이터**라서 항상 최신. 대신 **네트워크 의존적**이다 (`EXPO_DOCTOR_WARN_ON_NETWORK_ERRORS`로 완화 가능).
- 모든 검사는 `Promise.all` 병렬 실행, 검사 간 공유 캐시 사용.

### 무엇을 안 하나

호스트 툴체인(JDK, Android SDK, ANDROID_HOME, emulator)은 사실상 검사하지 않는다. Expo의 전제("EAS 클라우드에서 빌드하니 로컬 네이티브 툴체인은 우리 문제 아님") 때문. `NativeToolingVersionCheck`가 Xcode/CocoaPods를 일부 보는 정도.

### agent/CI 친화성

- 비대화식 환경 자동 감지(`isInteractive()`)로 ora 스피너 제거 → EAS Build 로그 친화적.
- 실패 시 `Log.exit`로 **non-zero exit code 보장** → CI 게이트로 사용 가능.
- `--json` **없음**. `--verbose`만 존재.

---

## 3. `flutter doctor`

소스: [`packages/flutter_tools/lib/src/doctor.dart`](https://github.com/flutter/flutter/blob/master/packages/flutter_tools/lib/src/doctor.dart)

### 검사 항목 (validators)

`FlutterValidator`(SDK/channel/버전/캐시), Android 툴체인(+`--android-licenses`), `XcodeValidator`(macOS), `ChromeValidator`/web, `AndroidStudioValidator`, IntelliJ/`VsCodeValidator`(IDE 플러그인까지), `LinuxDoctorValidator`, `VisualStudioValidator`+`WindowsVersionValidator`(Windows), `ProxyValidator`(프록시 환경 감지 시), `DeviceValidator`(연결된 디바이스), `HttpHostValidator`(pub.dev/Maven 등 필요 호스트 네트워크 도달성). 호스트 플랫폼과 활성 workflow에 따라 validator 목록이 조립된다.

### UX가 사랑받는 이유

1. **요약 우선, 상세는 opt-in**: 기본 출력은 카테고리당 정확히 한 줄(`[✓] Flutter (Channel stable, 3.x.x, ...)`), 상세는 `-v`. "Doctor summary (to see all details, run flutter doctor -v)"를 명시.
2. **5단계 상태 모델**: `success`/`partial`/`notAvailable`/`missing`/`crash` → `[✓]`/`[!]`/`[✗]` 시각화. "설치 안 됨"과 "부분 설치"를 구분해서 알려준다.
3. **Remediation이 메시지의 1급 시민**: 각 실패 메시지가 구체적 해결 명령을 포함하고, `contextUrl`이 있으면 `🔨 URL`로 문서 링크를 붙인다.
4. **엔지니어링 디테일**: validator 병렬 실행 + 스피너 + 느린 검사 경고(slowWarning), 전체 4분30초 타임아웃 가드, 버그리포트용 PII-stripped 출력 변형(`DoctorText`), 요약 마지막에 `! Doctor found issues in N categories.` 카운트.
5. Flutter가 SDK 배포까지 소유하므로 **검사와 툴체인 버전의 진실 공급원이 하나** — RN 생태계처럼 매트릭스가 어긋날 일이 구조적으로 적다.

### 프로젝트를 읽는가 / 자동 수정

- **읽지 않는다.** 순수 호스트-전역 검사 (어느 디렉터리에서 실행해도 동일). 프로젝트별 Flutter 버전 고정은 서드파티(FVM/mise) 영역.
- 자동 수정은 `--android-licenses` 하나뿐. 나머지는 remediation 텍스트 제공.

### agent/CI 친화성

- `--json`/`--machine` **없음** (flutter 자체의 `--machine`은 daemon용, doctor에는 미적용).
- exit code: `diagnose()`가 bool 반환 — `missing`/`crash`가 있으면 non-zero. `partial`/`notAvailable`은 issue 카운트에는 포함되지만 실패는 아님. CI 게이트로 사용 가능.

---

## 4. rnx-kit `align-deps` (Microsoft)

소스: [`packages/align-deps`](https://github.com/microsoft/rnx-kit/tree/main/packages/align-deps)

### 프로파일 모델 구조

3계층 선언 모델 (`package.json`의 `rnx-kit.alignDeps`):

```
preset (프로파일 컬렉션, 예: microsoft/react-native)
 └─ profile (RN minor 버전당 1개, 예: "0.73")
     └─ capability → { name, version } (예: "netinfo" → @react-native-community/netinfo@x)
```

- **requirements**: `["react-native@0.73"]` 같은 조건으로 병합된 preset에서 조건을 만족하는 프로파일만 선별 → 선별된 프로파일이 버전의 진실 공급원.
- **capabilities**: 패키지가 사용하는 기능의 추상 선언. 실제 패키지명/버전은 프로파일이 결정.
- **kitType** (`app`/`library`): library면 `peerDependencies`+`devDependencies`로, app이면 `dependencies`로 선언 위치까지 검증.
- development/production 요구사항 분리 지원. 커스텀 preset으로 내장 프로파일 확장/오버라이드 가능(사내 포크 대응).
- `--requirements` 플래그(구 `--vigilant`)로 **설정 없는 패키지도 강제 검증** 가능 → 모노레포 전체 정렬에 사용.

### 무엇을 검증하나 / 안 하나

- 검증 대상은 **오직 `package.json`의 의존성 선언**. `--write`로 자동 수정(원 클릭 정렬), `--diff-mode allow-newer` 같은 완화 모드 제공.
- 호스트 환경, 네이티브 파일(gradle/Podfile), 설치된 도구는 전혀 안 봄. lockfile/실제 설치 상태도 안 봄.
- 프로파일 자체가 rnx-kit 저장소에서 **수동 큐레이션** (RN 새 버전마다 프로파일 추가 PR 필요).

### agent/CI 친화성

- 불일치 시 non-zero exit → CI 게이트로 설계됨 (Microsoft 모노레포에서 실제 그렇게 사용).
- `--json` **없음**. 출력은 사람용 diff 텍스트.

---

## 5. 비교표

| | rn doctor | expo-doctor | flutter doctor | align-deps |
|---|---|---|---|---|
| 검사 대상 | 호스트 툴체인 | 프로젝트 파일/의존성 | 호스트 툴체인 | package.json 의존성 |
| 프로젝트 선언을 읽나 | 부분적 (RN 버전, config plugin) | O (app config + SDK 매트릭스) | X | O (alignDeps 설정) |
| 버전 매트릭스 출처 | CLI 릴리스에 하드코딩 | Expo 서버 API (동적) | Flutter SDK 자체 | 수동 큐레이션 프로파일 |
| 자동 수정 | O (`--fix`, 플랫폼별) | X (안내만) | android-licenses만 | O (`--write`) |
| `--json` | X | X | X | X |
| 신뢰 가능한 exit code | X (인터랙티브 대기) | O | O | O |
| 확장 포인트 | `config.healthChecks` | X | X | 커스텀 preset |
| 네트워크 필요 | X | O (일부 검사) | 일부 (HttpHostValidator) | X |

## 6. 공통 한계 — 왜 '환경 드리프트' pain이 남는가

1. **프로젝트 선언 vs 호스트 검증의 gap이 구조적이다.** 호스트를 보는 도구(rn/flutter doctor)는 프로젝트가 실제 요구하는 버전을 읽지 않고, 프로젝트를 읽는 도구(expo-doctor/align-deps)는 호스트를 검증하지 않는다. 네 도구 중 어느 것도 "이 프로젝트의 `build.gradle`이 AGP 8.6을 쓰니 JDK 17+가 필요하고, `Gemfile.lock`이 CocoaPods 1.15를 고정하니 시스템 pod 1.12는 틀렸다"를 말해주지 못한다.
2. **검사 목록이 도구에 하드코딩** — 프로젝트로부터 유도되지 않는다. RN doctor의 버전 매트릭스는 CLI 릴리스에 묶여 있어 프로젝트의 CLI 버전이 낡으면 검사 기준도 낡는다. align-deps 프로파일도 수동 갱신.
3. **커버되지 않는 드리프트 축들**: Gradle wrapper ↔ AGP ↔ Kotlin ↔ JDK 호환성 체인, Xcode 버전 ↔ iOS deployment target, Ruby 버전 ↔ Gemfile ↔ CocoaPods, `engines`/`.nvmrc` ↔ 실제 node, corepack/패키지매니저 버전, 에뮬레이터/시뮬레이터 이미지 존재 여부, 환경변수(JAVA_HOME이 잘못된 JDK를 가리키는 경우), 모노레포에서 hoisting으로 인한 중복 네이티브 모듈(expo-doctor만 일부 커버).
4. **agent/CI 친화성 부재**: 4개 도구 모두 `--json` 미지원. 결과를 프로그램적으로 소비하려면 사람용 텍스트를 파싱해야 한다. exit code조차 RN doctor는 신뢰 불가.
5. **수정의 실행력 편차**: flutter doctor는 진단은 최고지만 고쳐주지 않고, rn doctor의 `--fix`는 커버리지가 얕고, align-deps `--write`는 package.json 밖을 못 고친다.

### `mobile doctor` 스펙에 주는 시사점

- **차별화 코어 = gap 3번 축**: 프로젝트 파일(gradle/Podfile/Gemfile/engines)을 파싱해 요구사항 그래프를 만들고 호스트와 대조하는 도구는 현재 없다.
- align-deps의 **선언적 프로파일 모델**(capability → 버전 해석)과 expo-doctor의 **서버 사이드 매트릭스**(도구 릴리스와 분리된 호환성 데이터)는 차용할 가치가 있는 설계.
- UX는 flutter doctor 공식을 따를 것: 카테고리당 1줄 요약 + 5단계 상태 + remediation 명령/문서 URL 동봉 + `-v` 상세.
- `--json`과 명확한 exit code 규약은 **그 자체로 차별화 포인트** (4개 도구 전부 미지원).

## 출처

- react-native-community/cli: [healthchecks/index.ts](https://github.com/react-native-community/cli/blob/main/packages/cli-doctor/src/tools/healthchecks/index.ts), [commands/doctor.ts](https://github.com/react-native-community/cli/blob/main/packages/cli-doctor/src/commands/doctor.ts)
- expo/expo: [expo-doctor/src/checks](https://github.com/expo/expo/tree/main/packages/expo-doctor/src/checks), [expo-doctor/src/doctor.ts](https://github.com/expo/expo/blob/main/packages/expo-doctor/src/doctor.ts), [README](https://github.com/expo/expo/blob/main/packages/expo-doctor/README.md)
- flutter/flutter: [flutter_tools/lib/src/doctor.dart](https://github.com/flutter/flutter/blob/master/packages/flutter_tools/lib/src/doctor.dart)
- microsoft/rnx-kit: [align-deps README](https://github.com/microsoft/rnx-kit/blob/main/packages/align-deps/README.md)

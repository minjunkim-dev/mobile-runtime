# React Native Android 요구사항 정본과 호환성 추론 규칙

- 조사 티켓: [#107](https://github.com/minjunkim-dev/mobile-runtime/issues/107)
- 상위 지도: [#106 Private Phase 4A Android 내부 alpha](https://github.com/minjunkim-dev/mobile-runtime/issues/106)
- 조사일: 2026-08-23
- 범위: macOS host, React Native Android, 기존 Android Emulator

## 결론

안전한 추론 순서는 다음과 같다.

1. 프로젝트가 고정한 React Native와 Gradle wrapper를 찾는다.
2. 평가된 Gradle build에서 AGP와 `com.android.application` module을 찾는다.
3. 선택 module의 실행 가능한 debuggable variant를 열거한다.
4. 그 variant의 SDK 수준, application ID, merged manifest를 읽는다.
5. Gradle·AGP·Android의 **해당 버전 공식 자료**로 JDK, Gradle, AGP,
   `compileSdk`, Build Tools의 호환성을 교차 검증한다.
6. build 후 APK와 설치된 package를 이용해 application ID, min/target SDK,
   ABI, launcher를 다시 검증한다.
7. 여러 유효 후보 중 사용자의 의도만으로 결정할 수 있는 module, variant,
   launcher, AVD만 `mobile.yml`로 선택한다.

`package.json`만 보고 최신 React Native 문서의 숫자를 가져오거나,
`android/app`·`MainActivity`·`debug`를 고정값으로 가정하면 안 된다. Gradle
build는 subproject, plugin, flavor, variant filter와 convention plugin으로 최종
모델을 바꿀 수 있다. Gradle은 `settings.gradle(.kts)`가 subproject 구조를
정의한다고 명시하고, Android는 variant가 build type과 product flavor의 조합이며
filter로 비활성화될 수 있다고 명시한다
([Gradle multi-project builds](https://docs.gradle.org/current/userguide/multi_project_builds.html),
[Android build variants](https://developer.android.com/build/build-variants)).

이 문서는 지원 버전 표가 아니다. 공식 표에 있는 조합은 **후보 호환성**이고,
실제 지원 주장은 [#106](https://github.com/minjunkim-dev/mobile-runtime/issues/106)이
정한 것처럼 통과한 project/mobile SHA와 RN·JDK·Gradle·SDK·Emulator API/ABI
조합에만 귀속한다.

## 증거 등급

### Tier 1 — 프로젝트 선언·선택 variant의 정본

다음은 프로젝트가 실제 build에 입력하거나 build가 산출한 값이다.

- package-manager lockfile이 해석한 `react-native`와
  `@react-native/gradle-plugin` 버전
- `android/gradle/wrapper/gradle-wrapper.properties`의 `distributionUrl`
- `settings.gradle(.kts)`, version catalog, root/module build script, included build와
  convention plugin을 **Gradle이 평가한 결과**
- `gradle/gradle-daemon-jvm.properties`, `org.gradle.java.home`, Java toolchain 선언
- 선택 application variant의 SDK 수준과 `ApplicationVariant.applicationId`
- 선택 variant의 merged manifest와 build된 APK

Host의 SDK 위치·설치 package와 기존 AVD의 API/ABI는 요구사항 선언이 아니라
Tier 1 요구와 비교할 **현재 inventory 관측값**이다. 이 값은 실행 가능 여부는
증명하지만 프로젝트의 지원 version 범위를 만들지는 않는다.

Tier 1끼리 충돌하면 `mobile.yml`로 덮지 않는다. 실제 Gradle 평가 결과와 최종
artifact가 정적 문자열 검색보다 우선한다. Gradle의 `buildEnvironment` task는
buildscript classpath의 실제 선택 dependency를 보여준다
([Gradle dependency reports](https://docs.gradle.org/current/userguide/viewing_debugging_dependencies.html)).

### Tier 2 — 버전에 묶인 공식 호환성 자료

Tier 1에서 정확한 Gradle·AGP·React Native 버전을 얻은 다음에만 다음 자료를
적용한다.

- Gradle 버전별 Java runtime compatibility matrix
- AGP release note의 최소 JDK, 최소 Gradle, 최대/지원 API, 기본·최소 Build Tools
- Android의 API level별 최소 AGP 표
- 정확히 일치하는 React Native versioned 환경 문서, release tag와 template tag

`current`, `main`, `latest`의 값은 과거 프로젝트의 요구사항이 아니다. 예를 들어
React Native의 환경 문서가 JDK 17을 **권장**해도, 그것만으로 모든 RN 버전의
JDK를 17로 고정하지 않는다
([RN environment setup](https://reactnative.dev/docs/set-up-your-environment)).
React Native 값이 필요하면 프로젝트의 정확한 버전에 대응하는
[versioned docs](https://reactnative.dev/versions),
[React Native release tag](https://github.com/facebook/react-native/tags),
[Community template tag](https://github.com/react-native-community/template/tags)를
같이 고정한다.

### Tier 3 — `mobile.yml` 사용자 선택

Tier 3은 유효 후보가 여러 개라 프로젝트 선언만으로 사용자의 의도를 알 수 없을
때 사용한다. Tier 1의 실제 build 설정을 바꾸거나 잘못된 호환 조합을 정상으로
만드는 탈출구가 아니다.

| 값 | 자동 선택 | `mobile.yml` 필요 | override로 해결하면 안 되는 경우 |
|---|---|---|---|
| application module | `com.android.application` 후보가 하나 | 후보가 둘 이상 | 후보가 없음 |
| variant | 실행 가능한 debuggable 후보가 하나 | 후보가 둘 이상 | 선택 variant의 Gradle task가 없음 |
| launcher component | merged manifest의 `MAIN`+`LAUNCHER`가 하나 | 둘 이상 | launcher가 없음 |
| AVD | #113에서 정할 결정 규칙으로 하나가 남음 | 호환 AVD가 여럿이고 규칙으로 못 고름 | 호환 AVD가 없음 |
| JDK/Gradle/AGP/SDK 요구 | Tier 1과 버전 고정 Tier 2로 결정 | 공식 자료가 없는 fork 등에서 사용자가 검증한 기대값을 명시할 때만 고려 | 프로젝트의 wrapper·AGP·SDK 선언과 충돌 |

정확한 key 이름과 status 등급은 후속 계약 티켓 #108, #109, #112, #113에서
결정한다. 이 조사에서 새 schema를 선행 확정하지 않는다.

## 필드별 정본과 추론 규칙

### 1. React Native 버전

1. lockfile의 해석된 `react-native` 버전을 Tier 1로 사용한다. `package.json`의
   semver range만 있으면 정확한 버전으로 취급하지 않는다.
2. `@react-native/gradle-plugin`이 별도 lock entry이면 그 해석 버전도 함께
   기록한다. 두 package가 같은 버전이라고 가정하지 않는다.
3. Tier 2 기본값이나 권장 도구를 참조할 때는 exact release/template tag만 쓴다.
   React Native template는 Gradle wrapper, SDK 수준, module plugin, application ID와
   launcher 선언이 실제로 버전별로 달라지는 first-party 자료다
   ([template Android source](https://github.com/react-native-community/template/tree/main/template/android),
   [RN Gradle plugin source](https://github.com/facebook/react-native/tree/main/packages/gradle-plugin)).
4. tag가 없거나 fork가 upstream과 다르면 upstream tuple을 추정하지 않고
   프로젝트의 평가된 Gradle 모델을 사용한다.

Template tag의 값은 새 프로젝트 기본값일 뿐 기존 프로젝트의 Tier 1 선언을
덮지 않는다.

### 2. Gradle wrapper

정본은 `android/gradle/wrapper/gradle-wrapper.properties`의
`distributionUrl`이다. Gradle은 wrapper가 선언된 Gradle distribution을 내려받아
실행하며 system Gradle 대신 wrapper 사용을 권장한다
([Gradle Wrapper](https://docs.gradle.org/current/userguide/gradle_wrapper.html)).

추론 규칙:

- URL의 exact distribution version을 Tier 1로 읽는다.
- wrapper script/JAR/properties가 빠졌거나 URL이 exact version을 고정하지 않으면
  전역 `gradle`로 대체하지 않고 재현성 오류로 보고한다.
- `distributionSha256Sum`이 있으면 무결성 검증 선언으로 보존한다. 없다고 다른
  version을 추론하지 않는다.
- 이후 모든 Gradle 질의와 build는 프로젝트 `./gradlew`로 실행한다.

### 3. Android Gradle Plugin

AGP version 후보 위치는 다음과 같다.

- top-level plugin DSL의 `com.android.application` version
- `gradle/libs.versions.toml` 등 version catalog alias
- legacy `buildscript` classpath의 `com.android.tools.build:gradle:<version>`
- included convention build 또는 lock된 React Native Gradle Plugin에 동봉된
  dependency declaration

Android 공식 문서는 plugin DSL과 legacy classpath 양쪽 선언 형식을 보여준다
([AGP version configuration](https://developer.android.com/build/releases/about-agp),
[Groovy-to-Kotlin migration](https://developer.android.com/build/migrate-to-kotlin-dsl)).

정적 파일에서 version이 보이지 않으면 `./gradlew buildEnvironment` 등 Gradle의
평가·resolution 결과로 exact AGP를 찾는다. dynamic version(`+`, 열린 range)은
그때 resolve된 관측값은 남길 수 있지만 재현 가능한 requirement pin으로
일반화하지 않는다.

exact AGP를 얻은 뒤에만 다음 Tier 2 검사를 한다.

- AGP → 최소 Gradle: [AGP/Gradle compatibility table](https://developer.android.com/build/releases/about-agp)
- API level → 최소 AGP: 같은 문서의 API level별 minimum tool table
- AGP → 최소 JDK·기본/최소 Build Tools: **그 AGP version의 release note**

표의 최소값은 upgrade 권고이지 project의 wrapper나 `compileSdk`를 대신하는
기본값이 아니다. wrapper/AGP/SDK tuple이 표를 만족하지 않으면 오류이며
`mobile.yml`로 숨기지 않는다.

### 4. Gradle client·daemon을 실행하는 JDK

Gradle client JVM, daemon JVM, source compilation toolchain을 분리한다. Wrapper
client는 실행 시점의 `JAVA_HOME` 또는 `PATH`의 JVM에서 시작하고, 실제 build를
수행하는 daemon은 별도 JVM을 선택할 수 있다
([Gradle client and daemon](https://docs.gradle.org/current/userguide/gradle_daemon.html#the_gradle_client_and_daemon)).
Android와 Gradle은 Java toolchain이 compiler/test JDK를 선택하며 Gradle daemon
JVM과도 다른 값일 수 있다고 명시한다
([Android Java versions](https://developer.android.com/build/jdks),
[Gradle toolchains](https://docs.gradle.org/current/userguide/toolchains.html)).

Tier 1은 세 JVM 역할을 따로 관측한다.

1. client JVM: `./gradlew`를 시작한 `JAVA_HOME`/`PATH`의 `java`
2. daemon JVM: `gradle/gradle-daemon-jvm.properties`의 criteria,
   `org.gradle.java.home`, 실행 환경 JVM 순으로 적용되는 실제 선택값
3. compiler/test JVM: Java toolchain, `sourceCompatibility`,
   `targetCompatibility`의 평가 결과

Daemon JVM criteria가 있으면 `JAVA_HOME`과 `org.gradle.java.home`보다 우선한다
([Gradle Daemon JVM criteria](https://docs.gradle.org/current/userguide/gradle_daemon.html#daemon_jvm_criteria)).
이 우선순위는 daemon 선택에만 적용되며 client가 어떤 JVM에서 시작했는지를
바꾸지 않는다.

daemon의 허용 JDK 집합은 다음 hard constraint의 교집합이다.

- exact wrapper Gradle의 **버전별** Java runtime compatibility matrix
  ([Gradle compatibility](https://docs.gradle.org/current/userguide/compatibility.html))
- exact AGP release note의 최소 JDK
- project daemon JVM criteria가 있으면 그 criteria

RN versioned 문서의 권장 JDK는 진단 설명과 해결 안내에 쓸 수 있지만 hard
constraint 표가 허용하는 JDK를 단독으로 금지하는 근거로 쓰지 않는다. 교집합이
비면 project tuple 자체가 충돌한다. Client는 별도로 wrapper를 실제 실행해
호환성을 판정하고 client/daemon JVM과 vendor/version을 각각 보고한다.

Daemon JVM criteria는 toolchain download repository가 구성돼 있으면 matching
JDK를 자동 provision할 수 있다. Phase 4A는 JDK를 설치하지 않으므로 local matching
JDK가 없으면 필요한 criteria와 해결 안내를 반환하고 자동 다운로드하지 않는다
([daemon JVM auto-provisioning](https://docs.gradle.org/current/userguide/gradle_daemon.html#sec:daemon_jvm_criteria)).

### 5. `compileSdk`, `minSdk`, `targetSdk`

Tier 1은 선택 application module/variant의 **effective Gradle model**이다.

- `compileSdk`: application module의 `android` 설정
- `minSdk`, `targetSdk`: `defaultConfig`에 build type/flavor/variant 설정을 적용한 값
- Gradle property, root `ext`, version catalog, convention plugin을 참조하면 그
  참조를 끝까지 평가한다.

Android는 Gradle의 `minSdk`·`targetSdk`가 source manifest의 `<uses-sdk>` 값을
덮는다고 명시하므로 source manifest를 먼저 읽지 않는다
([manifest `<uses-sdk>` precedence](https://developer.android.com/guide/topics/manifest/manifest-intro),
[app module configuration](https://developer.android.com/build/configure-app-module)).

검증 규칙:

- exact `compileSdk`에 필요한 `platforms;android-<api>` package가 설치돼 있어야 한다.
- exact `compileSdk`가 exact AGP의 공식 API-level minimum을 만족해야 한다.
- build 후 Build Tools의 `aapt2 dump badging`으로 application ID, min SDK, target
  SDK를 교차 확인한다. `apkanalyzer manifest application-id|min-sdk|target-sdk`가
  설치돼 있으면 추가 corroboration으로 쓸 수 있다. 어느 쪽도 compile SDK를
  artifact의 정본으로 제공하지 않으므로 compile SDK는 APK에서 역추정하지 않는다
  ([AAPT2 dump](https://developer.android.com/tools/aapt2#dump),
  [apkanalyzer](https://developer.android.com/tools/apkanalyzer)).

`compileSdk`나 `targetSdk`를 RN version만으로 채우지 않는다. matching template
tag는 프로젝트가 참조하는 값을 해석하는 보조 근거일 뿐이다.

### 6. application module

1. `settings.gradle(.kts)`가 포함한 subproject를 열거한다. directory 이름 `app`은
   후보 이름일 뿐 정본이 아니다.
2. 각 subproject에서 평가된 `com.android.application` plugin 적용 여부를 본다.
   `com.android.library`와 `com.android.test` module은 launch 대상에서 제외한다.
3. application module이 하나면 자동 선택한다. 둘 이상이면 Tier 3 module 선택이
   필요하다. 하나도 없으면 지원 대상 RN application project가 아니다.

Plugin alias나 convention plugin 때문에 단순 grep으로 판정되지 않으면 Gradle
evaluation을 사용한다. Android 공식 plugin ID는
[AGP build configuration](https://developer.android.com/build/migrate-to-kotlin-dsl)에
정의돼 있다.

### 7. build variant

AGP는 build type과 각 flavor dimension의 product flavor를 조합해 variant를 만들고,
variant filter로 일부를 끌 수 있다
([build variants](https://developer.android.com/build/build-variants)). 따라서
`debug` 문자열을 조립해 존재한다고 가정하지 않는다.

1. 선택 application module의 평가 후 활성 variant와 Gradle tasks를 열거한다.
2. 평가된 AGP build type/variant에서 `debuggable`인 후보만 남기고, RN Gradle
   Plugin의 `debuggableVariants` 선언이 있으면 Metro/bundle 동작도 함께 기록한다.
   이름에 `debug`가 포함됐는지는 판정 근거가 아니다.
3. 각 후보에 APK를 만들고 설치할 task가 실제로 있는지 확인한다. Android 문서는
   `assemble<Variant>`·`install<Variant>` task와 `tasks`로 실제 후보를 확인하는
   방법을 정의한다
   ([command-line build](https://developer.android.com/build/building-cmdline)).
4. runnable debuggable 후보가 정확히 하나일 때만 자동 선택한다. exact `debug`가
   있어도 다른 후보가 함께 있으면 Tier 3 variant 선택을 요구한다.
5. 선택한 variant 이름과 `assemble`/`install` task 이름을 함께 보존한다.

React Native 자체도 추가 debuggable variant를 도입할 수 있으므로 suffix만 보는
휴리스틱은 안전하지 않다. 예를 들어 RN 0.82는 `debugOptimized` build type을
추가했다
([React Native 0.82 release](https://reactnative.dev/blog/2025/10/08/react-native-0.82)).

### 8. application ID

`namespace`, source package, manifest의 옛 `package`를 application ID로 가정하지
않는다. Android는 `applicationId`가 별도 값이며, 명시하지 않은 경우에만
namespace 값을 사용하고 build type/flavor suffix가 variant별 최종 ID를 바꿀 수
있다고 명시한다
([application ID](https://developer.android.com/build/configure-app-module),
[variant suffixes](https://developer.android.com/build/build-variants)).

우선순위:

1. 선택 variant의 AGP `ApplicationVariant.applicationId` provider
2. 선택 variant의 merged manifest/final APK
3. build 후 `aapt2 dump badging`의 package 값; 설치돼 있으면 `apkanalyzer manifest
   application-id`로 추가 확인

AGP Variant API는 이 값을 "final manifest의 application ID"로 정의한다
([ApplicationVariant API](https://developer.android.com/reference/tools/gradle-api/7.2/com/android/build/api/variant/ApplicationVariant)).
정적 `defaultConfig.applicationId`만 읽어 suffix를 직접 이어 붙이지 않는다.

### 9. launch activity 또는 alias

정본은 선택 variant의 merged manifest이다. Gradle은 main, build type, flavor,
variant, library manifest를 우선순위에 따라 합치므로
`src/main/AndroidManifest.xml` 하나만 읽으면 안 된다
([manifest merger](https://developer.android.com/build/manage-manifests)).

launcher 후보는 같은 intent filter에 다음 둘을 가진 enabled component다.

- `android.intent.action.MAIN`
- `android.intent.category.LAUNCHER`

Android는 두 값의 조합이 launcher entry라고 정의한다
([intents and filters](https://developer.android.com/guide/components/intents-filters)).
후보에는 `<activity>`뿐 아니라 `<activity-alias>`도 포함한다. alias가 launcher
filter를 소유할 수 있다
([`activity-alias`](https://developer.android.com/guide/topics/manifest/activity-alias-element)).

후보가 하나면 자동 선택하고 둘 이상이면 Tier 3 launcher 선택을 요구한다. build
후에는 `aapt2 dump badging <apk>`의 `launchable-activity`와 설치된 package의 intent
resolution으로 교차 확인한다. Android는 `aapt2 dump badging` 출력이 launchable
activity를 포함한다고 문서화한다
([AAPT2 badging example](https://developer.android.com/guide/topics/manifest/uses-feature-element#test)).

### 10. Android SDK root와 package

Build가 실제 사용하는 SDK root는 `local.properties`의 `sdk.dir`과 host
`ANDROID_HOME`에서 관측한다. Android는 `sdk.dir`을 AGP용 local environment
property로, `ANDROID_HOME`을 SDK 설치 directory로 정의하며
`ANDROID_SDK_ROOT`는 deprecated로 분류한다
([Android build properties](https://developer.android.com/build#properties-files),
[Android environment variables](https://developer.android.com/tools/variables)).

`sdk.dir`과 `ANDROID_HOME`이 모두 있으면 정규화한 경로가 같은지 검증한다. 다르면
AGP build와 `adb`/Emulator가 서로 다른 SDK를 볼 수 있으므로 Phase 4A에서는 한쪽을
묵시적으로 선택하지 않고 충돌을 보고한다. `ANDROID_SDK_ROOT`가 남아 있으면
`ANDROID_HOME`과 일치 여부만 진단하고 새 정본으로 승격하지 않는다.

필수 package는 사용 단계별로 구분한다.

| package/tool | 필요 조건 | version 정본 |
|---|---|---|
| SDK Platform | 항상 build | effective `compileSdk` |
| Build Tools | 항상 build | project `buildToolsVersion`; 없으면 exact AGP의 공식 default |
| Platform-Tools / `adb` | install, launch, stop, device 관측 | 설치된 실제 version; 임의 최소값을 만들지 않음 |
| Emulator | 기존 AVD boot/stop | 설치된 실제 version과 실행 가능 여부 |
| Command-line Tools | optional `sdkmanager`, `avdmanager`, `apkanalyzer`를 호출할 때 | 설치된 실제 version |
| NDK/CMake | project가 exact version이나 native build를 요구할 때 | project 선언, 없으면 matching RN/AGP 공식 자료 |

Android는 SDK Platform이 해당 API로 compile할 때 필요하고 system image가 해당
API의 Emulator에 필요하다고 설명한다
([SDK Platform packages](https://developer.android.com/tools/releases/platforms)).
Build Tools를 명시하지 않으면 AGP 3.0+가 plugin별 default를 고른다
([Build Tools releases](https://developer.android.com/tools/releases/build-tools)).
SDK tool별 package와 위치는
[Android command-line tools](https://developer.android.com/tools)에 정의돼 있다.

Phase 4A는 SDK·system image·AVD를 설치하지 않는다. 따라서 missing package는
필요한 `sdkmanager` package ID와 해결 안내만 반환한다. Gradle이 license가
승인된 missing package를 자동 다운로드할 수 있어도 이 milestone에서는 그
부작용을 실행하지 않는다. Android의 자동 다운로드 동작 자체는
[SDK Manager 문서](https://developer.android.com/studio/intro/update#download-with-gradle)에
명시돼 있다.

### 11. 기존 Android Emulator

기존 AVD는 `emulator -list-avds`로 열거하고 `emulator -avd <name>`으로 시작한다
([Emulator command line](https://developer.android.com/studio/run/emulator-commandline)).
호환 후보가 되려면 최소한 다음을 만족해야 한다.

1. AVD system image와 Emulator package가 실제로 설치돼 있다.
2. system image API level이 선택 variant의 final `minSdk` 이상이다. Android는
   더 낮은 API의 system image에는 app이 설치·실행되지 않는다고 명시한다
   ([AVD system images](https://developer.android.com/studio/run/managing-avds),
   [`uses-sdk`](https://developer.android.com/guide/topics/manifest/uses-sdk-element)).
3. Boot 전에는 AVD system-image ABI와 APK native ABI의 교집합을 후보 힌트로 쓴다.
   Boot 후에는 device의 `ro.product.cpu.abilist`와 APK native ABI의 교집합으로
   최종 판정한다. Android Package Manager는 device의 primary/secondary ABI에
   맞는 native library를 선택하므로 nominal system-image ABI 하나만으로 확정하지
   않는다 ([Android ABIs](https://developer.android.com/ndk/guides/abis)).
4. merged manifest가 요구하는 system library와 실제 초기 UI에 필요한 AVD
   capability가 있다. API/ABI만으로 모든 hardware·Google API 요구를 일반화하지
   않는다.
5. macOS host의 acceleration 상태는 `emulator -accel-check`로 관측한다. 공식
   Emulator는 hypervisor가 없어도 더 느린 translation으로 실행할 수 있으므로
   acceleration 부재를 compatibility hard failure로 일반화하지 않는다. Phase 4A가
   별도 성능 정책을 정하기 전에는 warning과 실제 boot 결과로 남긴다
   ([Emulator acceleration](https://developer.android.com/studio/run/emulator-acceleration)).

ABI는 `reactNativeArchitectures`, `ndk.abiFilters`, APK split 설정 때문에 variant와
invocation마다 달라질 수 있다. RN CLI의 active-architecture 동작도
`reactNativeArchitectures` Gradle property를 사용한다
([RN Android build speed](https://reactnative.dev/docs/build-speed)). 따라서 RN
version이나 host CPU만으로 AVD ABI를 고르지 않고, effective Gradle property와
build된 APK의 `/lib/<abi>/`를 교차 확인한다.

호환 AVD가 없으면 생성하거나 image를 다운로드하지 않고 실패한다. 여러 AVD의
우선순위와 이번 실행이 boot한 AVD의 소유권·종료 규칙은 #113에서 확정한다.

## 명령별 최소 입력

| 명령 | 필요한 정본 | build 후 교차 검증 |
|---|---|---|
| `mobile doctor` | exact RN/wrapper/AGP, client·daemon JDK, module/variant, SDK root/packages, 기존 AVD 후보 | 없음 |
| `mobile build` | 선택 module/variant와 `assemble<Variant>` task | APK application ID, min/target SDK, ABI, launcher |
| `mobile up` | build artifact, final application ID/launcher, 선택 AVD, `adb` | boot API/ABI, install 성공, resolved launcher, 초기 UI |
| `mobile down` | `mobile`이 기록한 app/Metro/AVD ownership | 사용자가 먼저 실행한 AVD를 종료하지 않았는지 |

## 구현 경계

- 정적 parser는 빠른 후보 탐지에만 쓴다. 최종 판정은 wrapper가 평가한 Gradle
  model/task와 selected variant artifact로 한다.
- Android Studio 설치 자체를 CLI runtime requirement로 만들지 않는다. 필요한
  JDK·SDK package와 executable을 개별 진단한다.
- `sdkmanager`, `avdmanager`는 provisioning이 아니라 inventory/해결 안내가 실제로
  필요할 때만 요구한다.
- `compileSdk`는 AVD 선택 기준이 아니다. runtime 하한은 final `minSdk`이며 ABI와
  manifest capability를 별도로 확인한다.
- matching 공식 표가 없거나 fork가 upstream과 달라지면 `unknown`을 유지한다.
  인접 version의 성공을 지원 범위로 외삽하지 않는다.
- 최종 완료 증거에는 exact tuple과 실제 통과한 단계만 남긴다. 전체 로그,
  환경 파일, screenshot, secret은 남기지 않는다.

## 공식 출처 색인

### Gradle

- [Wrapper](https://docs.gradle.org/current/userguide/gradle_wrapper.html)
- [Java compatibility](https://docs.gradle.org/current/userguide/compatibility.html)
- [Daemon JVM criteria](https://docs.gradle.org/current/userguide/gradle_daemon.html#daemon_jvm_criteria)
- [Java toolchains](https://docs.gradle.org/current/userguide/toolchains.html)
- [Multi-project builds](https://docs.gradle.org/current/userguide/multi_project_builds.html)
- [Dependency reports](https://docs.gradle.org/current/userguide/viewing_debugging_dependencies.html)

### Android / AGP

- [AGP compatibility and API-level minimums](https://developer.android.com/build/releases/about-agp)
- [Java versions in Android builds](https://developer.android.com/build/jdks)
- [App module configuration](https://developer.android.com/build/configure-app-module)
- [Build variants](https://developer.android.com/build/build-variants)
- [Command-line builds](https://developer.android.com/build/building-cmdline)
- [Manifest merger](https://developer.android.com/build/manage-manifests)
- [SDK command-line tools](https://developer.android.com/tools)
- [SDK Platform packages](https://developer.android.com/tools/releases/platforms)
- [Build Tools](https://developer.android.com/tools/releases/build-tools)
- [APK Analyzer CLI](https://developer.android.com/tools/apkanalyzer)
- [AVD management](https://developer.android.com/studio/run/managing-avds)
- [Emulator command line](https://developer.android.com/studio/run/emulator-commandline)
- [Android ABIs](https://developer.android.com/ndk/guides/abis)

### React Native

- [Versioned documentation index](https://reactnative.dev/versions)
- [Environment setup](https://reactnative.dev/docs/set-up-your-environment)
- [Android ABI build selection](https://reactnative.dev/docs/build-speed)
- [React Native release tags](https://github.com/facebook/react-native/tags)
- [React Native Gradle Plugin source](https://github.com/facebook/react-native/tree/main/packages/gradle-plugin)
- [Community template tags](https://github.com/react-native-community/template/tags)

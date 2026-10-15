# ADR-0035: 승인한 정확한 Android SDK archive만 나란히 설치한다

상태: 채택. #204의 공통 준비 설치 경계다. 실제 설치 검증과 #199의 준비 게이트는 별도로 기록한다.

## 요구와 관측

`AndroidDoctorContext`는 공개 opaque actor다. 공개 입력은 기존 anchor/config/runner/environment다.
공개 출력 `sdkRequirements()`는 SDK root, module별 AGP·Gradle·daemon JDK 버전, compile SDK·Build Tools·NDK·CMake 요구와 근거다.
원본 Gradle model, daemon Java home, private environment, variant APK 경로는 공개하지 않는다.
`androidChecks(context:)`와 요구 조회는 한 actor의 `modelTask`를 공유한다. 실행 조건을 다시 확인할 때는 새 관측을 사용한다.

준비는 모든 평가된 application module의 개발 variant 요구를 합친다. 호환성 위반이나 불명확한 버전은 설치 차단 근거다.
wrapper나 React Native 입력이 로컬에 없으면 관측이 이를 내려받지 않는다. 기존 설치와 일치하는 package를 우선 재사용한다.
상대 SDK 경로는 호출자의 cwd가 아닌 [Gradle root 기준](https://android.googlesource.com/platform/tools/base/+/studio-master-dev/build-system/gradle-core/src/main/java/com/android/build/gradle/internal/SdkLocator.kt)으로 해석한다.
이미 검증한 `cmake.dir`을 사용하면 그 정확한 CMake 버전과 근거를 기록한다. 같은 CMake를 SDK에 중복 설치하지 않는다.
SDK 패키지 준비는 `platforms`, `build-tools`, 필요한 `ndk`, 필요한 `cmake`를 다룬다.
Emulator·system image·AVD 생성은 후속 provider의 범위다. SDK 준비 성공을 앱 실행 성공으로 표시하지 않는다.

공식 호환 근거는 [AGP–Gradle/API 표](https://developer.android.com/build/releases/about-agp),
[Gradle Java 표](https://docs.gradle.org/current/userguide/compatibility.html), 기존 AGP 기본 CMake 표다.
2026-10-15에 AGP 7.x–9.4의 기존 표와 [9.4의 Gradle 9.6.0/JDK 17 요구](https://developer.android.com/build/releases/agp-9-4-0-release-notes)를 확인했다. 표에 없는 버전은 unknown이다.
같은 날 각 stable AGP 7.0–9.4 release note의 Build Tools minimum/default를 확인했다. 선언이 minimum보다 낮으면 [AGP SdkHandler](https://android.googlesource.com/platform/tools/base/+/studio-master-dev/build-system/gradle-core/src/main/java/com/android/build/gradle/internal/SdkHandler.java)처럼 default를 요구한다. 준비·doctor·build는 같은 계산을 쓴다. 표에 없는 AGP의 Build Tools를 추측하지 않는다.
AGP 8.11–8.13의 선언되지 않은 CMake는 기존 고정 source 근거에 따라 3.22.1이다. 다른 AGP에서 기본값을 추측하지 않는다.
Gradle 관측과 assemble은 `-Dorg.gradle.java.installations.auto-download=false`와 `-Pandroid.builder.sdkDownload=false`를 전달한다.
이 옵션은 JDK·SDK 자동 설치를 막는다. 프로젝트가 실행하는 임의의 사용자 코드를 격리하는 sandbox를 뜻하지 않는다.
[Gradle toolchain 공식 지침](https://docs.gradle.org/current/userguide/toolchains.html#sub:disable_auto_provision)은 `-D`를 지정한다.
[Gradle 9 변경](https://docs.gradle.org/current/userguide/upgrading_version_9.html)은 toolchain용 `-P` 처리가 제거된 범위를 설명한다.
SDK 옵션은 [AGP BooleanOption](https://android.googlesource.com/platform/tools/base/+/studio-master-dev/build-system/gradle-core/src/main/java/com/android/build/gradle/options/BooleanOption.kt)의 `android.builder.sdkDownload`다.

## 고정 metadata와 승인

설치 계획은 [공식 repository2-3.xml](https://dl.google.com/android/repository/repository2-3.xml)을 읽는다.
stable channel의 정확한 package path와 revision을 선택한다. host가 있으면 macOS와 arm64 조건을 확인한다.
host architecture가 없는 공식 macOS 공통 archive는 그 metadata 그대로 기록한다. 이것만으로 실행 호환을 입증하지 않는다.
base platform과 extension platform을 구분한다. 중복 path와 모호한 archive는 차단한다. 구형 schema로 내려가지 않는다.
관측한 전체 metadata의 SHA-256, archive URL·공식 SHA-1·size, 실제 package revision, 목적 경로, license ID·정확한 text SHA-1을 계획에 묶는다.
공식 legacy checksum은 SHA-1이다. HTTPS와 metadata SHA-256 pin을 함께 사용한다. 이를 공급자가 배포한 SHA-256 archive 서명으로 표현하지 않는다.

계획 승인은 license 동의와 관리자 권한을 대신하지 않는다. 선택한 SDK root의 정확한 license hash가 없으면 수동 대기한다.
Runstir는 `sdkmanager --licenses`, `yes`, `sudo`, license record 복사나 추가를 실행하지 않는다.
수동 처리 후 새 계획을 확인하고 승인한다. 쓰기 권한 부족도 별도 수동 단계다.
CLI와 GUI는 같은 `PreparationExecution`과 계획 identity를 사용한다. 화면에 정확한 URL·revision·checksum·size·destination·resource key를 표시한다.

## 실행과 보존

`InstallationArtifact`와 `InstallationMetadata`는 후속 준비 provider가 재사용할 최소 계약이다.
`InstallationAction`은 공개 계획에 실행 closure를 직렬화하지 않고 provider 동작을 공통 실행 loop에 연결한다.
공통 loop는 승인·lease·완료 기록을 처리한다. provider는 `beforeCommit`으로 실행 직전과 최종 변경 직전의 조건을 다시 확인한다.
`InstallationExecution.download`는 소유한 임시 디렉터리에서 고정 payload를 받는다.
플랫폼 설치 형식이 다르면 해당 provider가 설치 동작을 제공한다. Android의 첫 실행기는 검증한 ZIP을 사용한다.

1. 승인 identity를 비교한다. 실행 직전 계획을 다시 관측한다.
2. 작업 폴더와 설치 root의 `ResourceKey.destination` lease를 함께 얻는다. SDK 패키지마다 다른 lock을 만들지 않는다.
3. lease 이후 계획을 다시 관측한다. 패키지마다 요구·목적 경로·license와 source를 다시 확인한다.
4. 새 임시 경로에서 archive의 size·checksum을 확인한다. ZIP 중앙·로컬 header, 경로, 중복 이름, 파일 형식과 링크를 추출 전에 확인한다.
5. 소유한 stage에서 추출한다. 링크의 실제 목적 경로, `source.properties` revision과 필수 파일을 확인한다.
6. 다운로드 뒤와 최종 commit 직전에 조건·source·license를 재확인한다. 같은 volume의 임시 stage를 `RENAME_EXCL`로 이동한다.
7. 완료한 package를 기록한다. 실패·취소 때 소유한 임시 stage만 정리한다. 완료한 설치, 기존 destination, 기존 SDK와 cache를 삭제하지 않는다.

기존 destination이 불완전하거나 revision을 읽을 수 없어도 교체하지 않는다. dangling link와 경로 alias도 덮어쓰지 않는다.
예상 밖 source 변경을 보고한다. source와 lockfile을 자동 복원하지 않는다. 새 계획은 실제 남은 package만 설치한다.
SDK 설치 성공 뒤에도 실행 기기·수동 단계가 남으면 부분 완료다. `build`/`up`, 첫 화면, VM과 실제 Mac 근거를 구분한다.

## 검증 경계

행동 검사는 소유한 임시 prefix와 합성 license·archive를 사용한다. 실제 ZIP과 파일 변화를 확인한다.
계획 전용, license 대기, 재승인, metadata 변경, SDK root 충돌, checksum·revision·추출 실패, 경로·링크 이탈,
취소, 부분 완료 보존, 남은 단계 재실행, source 변경 시 commit 차단을 검증한다.
이 검사는 실제 Google payload 설치나 도구 없는 Mac의 성공 근거가 아니다. 실제 검증은 별도 자원 lease와 전후 보존 감사 뒤 기록한다.

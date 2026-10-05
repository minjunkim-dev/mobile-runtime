# AGP 기본 CMake

확인일: 2026-10-05. 공식 Android 문서와 공식 AGP stable tag 소스를 확인했다.

| AGP 확인 버전 | 버전 미지정 CMake | 공식 tag 근거 |
| --- | --- | --- |
| `8.11.0` | `3.22.1` | `studio-2025.1.1`: [BUILD_VERSION](https://android.googlesource.com/platform/tools/base/+/refs/tags/studio-2025.1.1/common/release_version.bzl#3), [CmakeLocator.kt](https://android.googlesource.com/platform/tools/base/+/refs/tags/studio-2025.1.1/build-system/gradle-core/src/main/java/com/android/build/gradle/internal/cxx/configure/CmakeLocator.kt#133) |
| `8.12.0` | `3.22.1` | `studio-2025.1.2`: [BUILD_VERSION](https://android.googlesource.com/platform/tools/base/+/refs/tags/studio-2025.1.2/common/release_version.bzl#3), [CmakeLocator.kt](https://android.googlesource.com/platform/tools/base/+/refs/tags/studio-2025.1.2/build-system/gradle-core/src/main/java/com/android/build/gradle/internal/cxx/configure/CmakeLocator.kt#133) |
| `8.13.0` | `3.22.1` | `studio-2025.1.3`: [BUILD_VERSION](https://android.googlesource.com/platform/tools/base/+/refs/tags/studio-2025.1.3/common/release_version.bzl#3), [CmakeLocator.kt](https://android.googlesource.com/platform/tools/base/+/refs/tags/studio-2025.1.3/build-system/gradle-core/src/main/java/com/android/build/gradle/internal/cxx/configure/CmakeLocator.kt#133) |

세 tag의 `CmakeLocator.kt:133`은 `LATEST_WITH_FILE_API`를 `3.22.1`로 정의한다. `:141`은 이를 `DEFAULT`로 선택한다.
AGP `8.12.0`의 `:285–287`은 DSL 버전 미지정 시 기본값을 선택한다. `:279–280`과 `:423–424`는 기본 SDK 패키지를 다운로드한다.
같은 파일 `:128`의 `3.10.2`는 `LATEST_WITH_SERVER_API`다. 미지정 버전의 fallback이 아니다.
`:258–268`의 버전 비교와 `:395–413`의 구형 SDK 디렉터리 탐색도 기본 요구 버전을 검사한다. `:354–356`의 유효한 `cmake.dir`는 미지정 DSL의 예외다.
`android.sdk`는 미지정 DSL에서 `cmake.dir`의 실행 파일과 `--version` 응답을 읽으면 기본 SDK 패키지를 요구하지 않는다. 이 관측은 Tier 1이다. 경로나 버전을 읽을 수 없으면 `unknown`이다.
[공통 설치 문서](https://developer.android.com/studio/projects/install-ndk#configure-specific-version-of-cmake)는 미지정 버전을 `3.10.2`로 적는다. 이 설명은 위 stable tag의 기본값과 다르다.
[AGP 8.12 API 문서](https://developer.android.com/reference/tools/gradle-api/8.12/com/android/build/api/dsl/Cmake#version)는 기본값 숫자를 적지 않는다. 숫자의 근거로 위 tag 소스를 사용한다.
표는 기존 AGP→Gradle 표처럼 major/minor로 조회한다. 확인하지 않은 major/minor 행은 `unknown`으로 남긴다.

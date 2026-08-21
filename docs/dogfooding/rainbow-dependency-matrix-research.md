# Rainbow / Xcode 26.6 의존성 조합 조사

조사일: 2026-08-21  
조사 범위: 공식 upstream 1차 자료와 기존 로컬 실패 로그의 대조. 이 단계에서는 설치·의존성 갱신·프로젝트 수정·빌드를 수행하지 않았다.  
실험 범위: 조사 뒤 mobile-runtime 저장소 밖의 격리 checkout에서 후보 A를 별도로 마이그레이션하고 빌드·launch 가능성만 검증했다. 이 실험은 Rainbow에 합칠 수 있는 완료 변경이나 3/3 앱 UI 증거가 아니다.

## 결론

문제는 로컬 Xcode 설치가 아니라 **Rainbow의 현재 React Native 계열이 고정한 `fmt 11.0.2`와 Xcode 26.6의 Apple Clang 21 조합**이다. `RCT-Folly`도 `fmt = 11.0.2`를 정확히 요구하므로 CocoaPods에서 `fmt`만 독립적으로 올릴 수 있는 구조가 아니다. [Rainbow `Podfile.lock`](https://github.com/rainbow-me/rainbow/blob/bb6110b846ca6955125d490c0eb1f0812fccadf7/ios/Podfile.lock#L1392), [React Native 0.81.6 `RCT-Folly.podspec`](https://github.com/facebook/react-native/blob/v0.81.6/packages/react-native/third-party-podspecs/RCT-Folly.podspec)

공식 upstream이 채택한 해결 조합은 **React Native 0.83.5 이상 + `fmt 12.1.0`**이다. 현재 0.83 계열의 최신 패치인 **React Native 0.83.10**도 `fmt 12.1.0`을 그대로 사용하므로, 장기적으로 검증할 1순위 조합은 다음과 같다. [React Native 0.83.5 릴리스](https://github.com/facebook/react-native/releases/tag/v0.83.5), [React Native 0.83.10 릴리스](https://github.com/facebook/react-native/releases/tag/v0.83.10), [0.83.10 `fmt.podspec`](https://github.com/facebook/react-native/blob/v0.83.10/packages/react-native/third-party-podspecs/fmt.podspec)

> **권장 후보:** Xcode 26.6 + Expo SDK 55 + React Native 0.83.10 + React 19.2.x + matching `@react-native/*` 0.83.10 + `fmt 12.1.0` + Node 22 + Rainbow가 고정한 Ruby 3.4.8 / Yarn 4.13.0 / CocoaPods 1.16.2

다만 Rainbow는 현재 Expo 54 / RN 0.81.6에서 iOS `new_arch_enabled => false`를 명시한다. Expo SDK 55와 React Native 0.82 이상은 Legacy Architecture를 지원하지 않으므로, 위 조합은 단순 의존성 한 줄 변경이 아니라 **Expo SDK 55 및 New Architecture 전환을 포함한 정식 업그레이드 작업**이다. [Rainbow `package.json`](https://github.com/rainbow-me/rainbow/blob/bb6110b846ca6955125d490c0eb1f0812fccadf7/package.json#L266), [Rainbow `Podfile`](https://github.com/rainbow-me/rainbow/blob/bb6110b846ca6955125d490c0eb1f0812fccadf7/ios/Podfile#L67-L73), [Expo SDK 55 공식 발표](https://expo.dev/changelog/sdk-55), [React Native 0.82 공식 발표](https://reactnative.dev/blog/2025/10/08/react-native-0.82#new-architecture-only)

이 마이그레이션은 mobile-runtime 구현 범위에 포함하지 않는다. Rainbow가 제품 작업으로 채택할 때는 Expo 54에서 New Architecture를 먼저 활성화해 native module과 화면을 안정화한 뒤 Expo 55로 올린다. 두 전환을 한 번에 배포 가능한 변경으로 취급하지 않는다. [Expo SDK 55 업그레이드 가이드](https://expo.dev/blog/upgrading-to-sdk-55), [Expo New Architecture 가이드](https://docs.expo.dev/guides/new-architecture/)

## 기준 스냅샷

Rainbow 공식 저장소에는 조회 시점에 `main` head가 없고 기본 개발선은 `develop`이다. 최신 원격 `develop`은 [`bb6110b846ca6955125d490c0eb1f0812fccadf7`](https://github.com/rainbow-me/rainbow/commit/bb6110b846ca6955125d490c0eb1f0812fccadf7)였다. 조사용 checkout `29eade9a97e1dd47a307aeb57772138901987d1f`보다 앞서지만, 아래 핵심 버전과 아키텍처 설정은 동일하다.

| 계층 | 최신 `develop` 선언 | 근거 |
| --- | --- | --- |
| Xcode | 26.3 | [`.xcode-version`](https://github.com/rainbow-me/rainbow/blob/bb6110b846ca6955125d490c0eb1f0812fccadf7/.xcode-version) |
| Node | 22, 엔진은 `>=22.0.0` | [`.node-version`](https://github.com/rainbow-me/rainbow/blob/bb6110b846ca6955125d490c0eb1f0812fccadf7/.node-version), [`package.json`](https://github.com/rainbow-me/rainbow/blob/bb6110b846ca6955125d490c0eb1f0812fccadf7/package.json#L464-L468) |
| Ruby | 3.4.8 | [`.ruby-version`](https://github.com/rainbow-me/rainbow/blob/bb6110b846ca6955125d490c0eb1f0812fccadf7/.ruby-version) |
| Yarn | 4.13.0 | [`package.json`](https://github.com/rainbow-me/rainbow/blob/bb6110b846ca6955125d490c0eb1f0812fccadf7/package.json#L464) |
| CocoaPods | 1.16.2 | [`Podfile.lock`](https://github.com/rainbow-me/rainbow/blob/bb6110b846ca6955125d490c0eb1f0812fccadf7/ios/Podfile.lock#L5668) |
| Expo | 54.0.33 | [`package.json`](https://github.com/rainbow-me/rainbow/blob/bb6110b846ca6955125d490c0eb1f0812fccadf7/package.json#L266) |
| React | 19.1.4 | [`package.json`](https://github.com/rainbow-me/rainbow/blob/bb6110b846ca6955125d490c0eb1f0812fccadf7/package.json#L302) |
| React Native | 0.81.6 | [`package.json`](https://github.com/rainbow-me/rainbow/blob/bb6110b846ca6955125d490c0eb1f0812fccadf7/package.json#L306) |
| RN 도구 패키지 | babel/metro/typescript config 0.81.6 | [`package.json`](https://github.com/rainbow-me/rainbow/blob/bb6110b846ca6955125d490c0eb1f0812fccadf7/package.json#L409-L411) |
| iOS 아키텍처 | Legacy (`new_arch_enabled => false`) | [`Podfile`](https://github.com/rainbow-me/rainbow/blob/bb6110b846ca6955125d490c0eb1f0812fccadf7/ios/Podfile#L67-L73) |
| fmt | 11.0.2 | [`Podfile.lock`](https://github.com/rainbow-me/rainbow/blob/bb6110b846ca6955125d490c0eb1f0812fccadf7/ios/Podfile.lock#L1392), [RN 0.81.6 `fmt.podspec`](https://github.com/facebook/react-native/blob/v0.81.6/packages/react-native/third-party-podspecs/fmt.podspec#L11-L18) |
| RCT-Folly | 2024.11.18.00, `fmt = 11.0.2` | [`Podfile.lock`](https://github.com/rainbow-me/rainbow/blob/bb6110b846ca6955125d490c0eb1f0812fccadf7/ios/Podfile.lock#L1654-L1671) |
| Hermes | 0.81.6 | [`Podfile.lock`](https://github.com/rainbow-me/rainbow/blob/bb6110b846ca6955125d490c0eb1f0812fccadf7/ios/Podfile.lock#L1556-L1558) |

로컬 표준 Xcode는 26.6 build 17F113, Apple Clang 21.0.0이다. Apple은 Xcode 26.6에 포함된 SDK와 지원 범위를 공식 릴리스 노트에 명시한다. [Apple Xcode 26.6 릴리스 노트](https://developer.apple.com/documentation/xcode-release-notes/xcode-26_6-release-notes)

## 확정 사실

### 1. 실패 지점은 Rainbow 앱 코드보다 앞선 `fmt` Pod 컴파일이다

기존 로컬 빌드는 `ios/Pods/fmt/include/fmt/format-inl.h`의 5개 위치에서 `call to consteval function ... is not a constant expression`로 종료됐다. 로그는 임시 경로의 비영속 산출물이므로 이 문서에는 저장하지 않는다.

React Native 공식 이슈에도 Xcode 26.4 / Apple Clang 21에서 같은 파일과 같은 다섯 위치의 오류가 재현됐고, `fmt`와 `RCT-Folly`를 12.1.0으로 맞춘 뒤 컴파일됐다고 보고됐다. [React Native #55601](https://github.com/facebook/react-native/issues/55601)

따라서 현재 증거가 지목하는 범위는 Metro, JavaScript, 앱 비즈니스 로직이 아니라 **RN이 소스 빌드하는 C++ 전이 의존성**이다. 최초 40분 정지는 별도 빌드 오케스트레이션 현상이며, 이 의존성 오류와 같은 원인이라고 단정할 근거는 없다.

### 2. `fmt`만 임의로 올리는 것은 현재 dependency graph와 충돌한다

RN 0.81.6의 `fmt.podspec`은 11.0.2를 고정하고, `RCT-Folly.podspec`도 `fmt 11.0.2`를 정확히 요구한다. [RN 0.81.6 `fmt.podspec`](https://github.com/facebook/react-native/blob/v0.81.6/packages/react-native/third-party-podspecs/fmt.podspec#L11-L18), [RN 0.81.6 `RCT-Folly.podspec`](https://github.com/facebook/react-native/blob/v0.81.6/packages/react-native/third-party-podspecs/RCT-Folly.podspec)

React Native의 공식 수정도 `fmt.podspec` 하나만 바꾸지 않았다. iOS `RCT-Folly` 제약, iOS prebuild 설정, Android Gradle 버전 카탈로그를 함께 12.1.0으로 정렬했다. [공식 수정 커밋 `faeef2b`](https://github.com/facebook/react-native/commit/faeef2b90a56633ad44289b994d31e7ce590b145)

### 3. upstream의 선택은 `fmt 12.1.0`이다

React Native 0.83.5 릴리스 노트는 Xcode 26.4 빌드 수정으로 `fmt 12.1.0` 상향을 명시한다. [React Native 0.83.5 릴리스](https://github.com/facebook/react-native/releases/tag/v0.83.5)

`fmt 12.1.0` 자체 릴리스 노트에도 Clang 21 + C++20 컴파일 수정과 `FMT_USE_CONSTEVAL` 사용자 설정 지원이 포함돼 있다. [fmt 12.1.0 릴리스](https://github.com/fmtlib/fmt/releases/tag/12.1.0)

`fmt 11.1.0`에는 관련 compile-time check 정리 커밋이 포함돼 있어 기술적으로는 더 작은 후보가 될 수 있다. 그러나 React Native가 Xcode 문제에 대해 실제로 릴리스한 조합은 11.1.0이 아니라 12.1.0이다. 검증 우선순위는 upstream이 채택한 12.1.0이 높다. [fmt `6797f0c`](https://github.com/fmtlib/fmt/commit/6797f0c39a4ef13061cbc3bb850c35af7428fdc4), [RN 공식 수정](https://github.com/facebook/react-native/commit/faeef2b90a56633ad44289b994d31e7ce590b145)

### 4. RN 0.83 업그레이드는 아키텍처 전환을 동반한다

React Native 0.82부터 `newArchEnabled=false`와 `RCT_NEW_ARCH_ENABLED=0`은 무시되고 New Architecture만 실행된다. 공식 권장 순서도 0.81에서 먼저 New Architecture를 활성화하고 검증한 다음 0.82 이상으로 올리는 것이다. [React Native 0.82 공식 발표](https://reactnative.dev/blog/2025/10/08/react-native-0.82#how-to-migrate)

Rainbow는 최신 `develop`에서도 명시적으로 Legacy Architecture를 사용한다. 따라서 `react-native` 버전만 0.83.10으로 바꾸는 것은 올바른 실험이 아니다. [Rainbow `Podfile`](https://github.com/rainbow-me/rainbow/blob/bb6110b846ca6955125d490c0eb1f0812fccadf7/ios/Podfile#L67-L73)

## 최선 후보 조합

### A. 장기 권장: 공식 릴리스 조합으로 정식 업그레이드

| 구성요소 | 후보 | 선택 이유 |
| --- | --- | --- |
| Xcode | 로컬 26.6 유지 | 설치나 다운그레이드 없이 실제 개발 환경을 검증 대상으로 삼음. [Apple 릴리스 노트](https://developer.apple.com/documentation/xcode-release-notes/xcode-26_6-release-notes) |
| Expo | SDK 55 | RN 0.83 / React 19.2와 New Architecture를 공식 조합으로 제공. [Expo SDK 55 발표](https://expo.dev/changelog/sdk-55) |
| React Native | 0.83.10 | Xcode 수정이 처음 릴리스된 0.83.5 이후의 0.83 최신 패치. [0.83.5](https://github.com/facebook/react-native/releases/tag/v0.83.5), [0.83.10](https://github.com/facebook/react-native/releases/tag/v0.83.10) |
| React | 19.2.x | RN 0.83.10 peer range가 `^19.2.0`. [RN 0.83.10 `package.json`](https://github.com/facebook/react-native/blob/v0.83.10/packages/react-native/package.json) |
| `@react-native/*` | 0.83.10으로 정렬 | RN 도구 패키지를 현재처럼 core minor/patch와 맞춰 혼합 버전을 피함. [RN 0.83.10 `package.json`](https://github.com/facebook/react-native/blob/v0.83.10/packages/react-native/package.json) |
| fmt | RN이 제공하는 12.1.0 | Clang 21 수정이 포함된 upstream 선택. 앱에서 별도 override하지 않음. [`fmt.podspec`](https://github.com/facebook/react-native/blob/v0.83.10/packages/react-native/third-party-podspecs/fmt.podspec) |
| RCT-Folly | RN 0.83.10 제공 버전 | 이 podspec이 `fmt 12.1.0`을 함께 고정하므로 세트로 사용. [`RCT-Folly.podspec`](https://github.com/facebook/react-native/blob/v0.83.10/packages/react-native/third-party-podspecs/RCT-Folly.podspec) |
| Node | Rainbow의 22 유지 | RN 0.83.10 최소 `>=20.19.4`를 충족. [RN 0.83.10 `package.json`](https://github.com/facebook/react-native/blob/v0.83.10/packages/react-native/package.json), [Rainbow `.node-version`](https://github.com/rainbow-me/rainbow/blob/bb6110b846ca6955125d490c0eb1f0812fccadf7/.node-version) |
| Ruby / Yarn / CocoaPods | 3.4.8 / 4.13.0 / 1.16.2 유지 | 이번 C++ 오류와 무관한 축은 고정해 실험 변수를 줄임. [Rainbow pins](https://github.com/rainbow-me/rainbow/tree/bb6110b846ca6955125d490c0eb1f0812fccadf7) |
| Architecture | New Architecture | RN 0.82+의 필수 조건. [RN 0.82 발표](https://reactnative.dev/blog/2025/10/08/react-native-0.82#new-architecture-only) |

이 조합이 가장 깨끗한 이유는 Xcode를 피하거나 컴파일러 기능을 끄지 않고, React Native와 그 전이 의존성을 upstream이 릴리스한 단위 그대로 사용하기 때문이다.

### B. 단기 대안: RN 0.81.6에 공식 `fmt 12.1.0` 변경을 백포트

New Architecture 전환을 즉시 할 수 없다면, RN 0.81.6/Legacy Architecture를 유지하면서 [`faeef2b`](https://github.com/facebook/react-native/commit/faeef2b90a56633ad44289b994d31e7ce590b145)의 dependency alignment를 프로젝트가 소유한 패치로 백포트하는 실험은 가능하다.

그러나 이는 **공식적으로 배포된 RN 0.81.x 조합이 아니다**. 0.81 계열의 최신 태그는 0.81.6이며 `fmt 12.1.0` 백포트 릴리스가 없다. [React Native 0.81.6 태그](https://github.com/facebook/react-native/releases/tag/v0.81.6), [0.81.6 `fmt.podspec`](https://github.com/facebook/react-native/blob/v0.81.6/packages/react-native/third-party-podspecs/fmt.podspec)

따라서 B는 장기 해법이 아니라 A의 아키텍처 전환 비용을 판단하기 위한 제한적 후보로만 다룬다. 채택하려면 iOS뿐 아니라 공식 커밋이 건드린 Android 의존성까지 같이 정렬하고, 프로젝트가 해당 패치를 명시적으로 소유해야 한다. [공식 수정의 전체 diff](https://github.com/facebook/react-native/commit/faeef2b90a56633ad44289b994d31e7ce590b145)

## 검증 매트릭스

| 순서 | Xcode | RN / Architecture | fmt | 목적 | 기대/판정 |
| --- | --- | --- | --- | --- | --- |
| 0 | 26.6 | 0.81.6 / Legacy | 11.0.2 | 현재 실패 재현 | **이미 실패 확인**. 동일한 다섯 `consteval` 오류로 기준선을 고정했다. |
| 1 | 26.6 | Expo 55 / RN 0.83.10 / New | RN 제공 12.1.0 | 장기 권장 조합 검증 | clean dependency resolve → Pod 설치 → Debug simulator build → 앱 설치/launch → Metro 연결까지 모두 통과해야 함. [Expo SDK 55](https://expo.dev/changelog/sdk-55), [RN 0.83.10](https://github.com/facebook/react-native/releases/tag/v0.83.10) |
| 2 | 26.6 | Expo 55 / RN 0.83.10 / New | RN 제공 12.1.0 | native module 회귀 검증 | Rainbow의 모든 autolinked native module이 codegen/compile/link를 통과하고 핵심 지갑 흐름 smoke test가 통과해야 함. [Expo SDK 55 업그레이드 안내](https://expo.dev/changelog/sdk-55#upgrading-your-app), [RN 업그레이드 가이드](https://reactnative.dev/docs/upgrading) |
| 3 | 26.6 | 0.81.6 / Legacy | 12.1.0 백포트 | A가 즉시 불가능할 때만 | iOS와 Android의 fmt/RCT-Folly dependency graph가 모두 정렬되고 전체 빌드가 통과해야 함. 통과해도 “upstream-supported”로 표기하지 않음. [공식 수정](https://github.com/facebook/react-native/commit/faeef2b90a56633ad44289b994d31e7ce590b145) |
| 제외 | 26.6 | 0.81.6 / Legacy | 11.1.0 임의 교체 | 더 작은 버전 점프 | 관련 수정은 포함하지만 RN이 선택·릴리스한 Xcode 해결 조합이 아니므로 12.1.0보다 먼저 검증하지 않음. [fmt 수정](https://github.com/fmtlib/fmt/commit/6797f0c39a4ef13061cbc3bb850c35af7428fdc4), [RN 릴리스 선택](https://github.com/facebook/react-native/releases/tag/v0.83.5) |

각 실험은 하나의 격리된 checkout에서 lockfile까지 함께 고정하고, 성공 증거를 단계별로 분리해야 한다. `fmt` 컴파일 성공만으로 Rainbow 앱 실행이나 dogfooding 성공을 주장하지 않는다.

## 피해야 할 우회책

- `Pods/fmt/include/fmt/base.h`를 `post_install`에서 문자열 치환해 `consteval`을 끄지 않는다. 생성 산출물을 매 설치마다 변형하고 실제 upstream dependency fix를 숨긴다. 논의는 존재하지만 React Native가 릴리스한 해결책은 `fmt 12.1.0` 상향이다. [fmt #4740](https://github.com/fmtlib/fmt/issues/4740), [RN 0.83.5 릴리스](https://github.com/facebook/react-native/releases/tag/v0.83.5)
- 컴파일 플래그만으로 `FMT_USE_CONSTEVAL=0`을 강제해 최종 해법으로 삼지 않는다. 12.1.0은 이 매크로를 설정 가능하게 만들었지만, 정상 조합에서는 기능 비활성화가 아니라 수정 버전을 사용해야 한다. [fmt 12.1.0 릴리스](https://github.com/fmtlib/fmt/releases/tag/12.1.0)
- `Podfile.lock`의 `fmt` 숫자만 직접 바꾸지 않는다. RN 0.81.6의 `RCT-Folly`가 11.0.2를 정확히 요구한다. [RN 0.81.6 `RCT-Folly.podspec`](https://github.com/facebook/react-native/blob/v0.81.6/packages/react-native/third-party-podspecs/RCT-Folly.podspec)
- RN 0.83.10으로 올리면서 `new_arch_enabled => false`를 그대로 두지 않는다. 0.82 이상에서는 해당 설정이 무시된다. [RN 0.82 공식 발표](https://reactnative.dev/blog/2025/10/08/react-native-0.82#new-architecture-only)
- Xcode를 추가 설치하거나 다운그레이드하는 것으로 dependency incompatibility를 해결했다고 보지 않는다. Xcode 26.3은 현재 저장소의 재현 가능한 기준선일 뿐, 로컬 표준 Xcode 26.6 지원을 만드는 해법은 아니다. [Rainbow `.xcode-version`](https://github.com/rainbow-me/rainbow/blob/bb6110b846ca6955125d490c0eb1f0812fccadf7/.xcode-version)
- 캐시 삭제나 DerivedData 초기화를 이 오류의 수정으로 기록하지 않는다. 정지 상태를 정리하는 데는 도움이 될 수 있지만, 재현된 `fmt 11.0.2` 컴파일 오류는 그대로 남는다. [React Native 재현 이슈](https://github.com/facebook/react-native/issues/55601)

## 의사결정 게이트

1. Rainbow가 New Architecture 전환을 지금 수용할 수 있는지 먼저 판단한다. 가능하면 Expo 54에서 New Architecture를 먼저 안정화하고, 그 뒤 후보 A로 올린다. [Expo SDK 55 업그레이드 가이드](https://expo.dev/blog/upgrading-to-sdk-55), [RN 공식 마이그레이션 순서](https://reactnative.dev/blog/2025/10/08/react-native-0.82#how-to-migrate)
2. 불가능하면 후보 B를 별도 브랜치의 명시적 upstream backport로만 평가한다. `fmt` 헤더 mutation이나 컴파일러 기능 비활성화는 평가 대상에서 제외한다. [RN 공식 수정](https://github.com/facebook/react-native/commit/faeef2b90a56633ad44289b994d31e7ce590b145)
3. 어떤 후보도 실제 Xcode 26.6 clean build와 앱 launch 전에는 “호환됨”으로 확정하지 않는다. 공식 수정은 Xcode 26.4를 대상으로 릴리스됐고, Xcode 26.6 적용 가능성은 강하지만 로컬 프로젝트 검증이 최종 게이트다. [RN 0.83.5 릴리스](https://github.com/facebook/react-native/releases/tag/v0.83.5), [Apple Xcode 26.6 릴리스 노트](https://developer.apple.com/documentation/xcode-release-notes/xcode-26_6-release-notes)

## 2026-08-21 격리 마이그레이션 실험 결과

- 격리 checkout: mobile-runtime 저장소 밖의 일회성 작업 디렉터리. 아래 변경은 커밋되지 않았으며 Rainbow 병합 후보가 아니다.
- 브랜치/기준점: `codex/rainbow-expo55-xcode266`, Rainbow `develop`의 `bb6110b846ca6955125d490c0eb1f0812fccadf7`
- 고정 조합: Expo 55.0.29, React Native 0.83.10, React 19.2.0, New Architecture, `fmt` 12.1.0, RCT-Folly 2024.11.18.00, Reanimated 4.2.1, Worklets 0.7.4, Metro 0.83.8, Rock 0.12.11
- 패키지 정합성: `expo install --check` 통과. Rainbow의 New Architecture 지원 WebView fork 13.16.1은 `expo.install.exclude`로 명시해 Expo가 upstream 13.16.0으로 덮어쓰지 않게 했다.
- iOS: 로컬 Xcode 26.6에서 iPhone 17 Pro/iOS 26.5 Simulator 대상 Debug 빌드 통과(`xcodebuild` 종료 코드 0). 앱 설치와 프로세스 시작도 통과했다.
- `mobile` 검증: 실험 당시 `main` `62fd149fad9f624b968d64d308842f3621988854`에서 385개 테스트가 통과했다. 같은 바이너리로 `mobile up --json`을 실행해 `validate`·`dependencies`·`device`·`metro`·`build`·`install`·`launch` 7단계와 최상위 `status: pass`, 종료 코드 0을 확인했다. 최초 기본 DerivedData 빌드는 600.7초였다.
- 런타임 게이트: 저장소의 `GoogleService-Info.plist`가 placeholder API key를 포함해 Firebase Installations 초기화에서 즉시 종료된다. 로컬에도 유효한 Rainbow Firebase 설정이 없고, 현재 GitHub 자격으로 `rainbow-me/rainbow-env`에 접근할 수 없다.
- JS 게이트: public metadata 기반 GraphQL 산출물은 생성됐지만 `GRAPH_ENS_API_KEY`가 없어 ENS 산출물을 생성하지 못했다. TypeScript의 남은 11개 오류와 Metro의 단일 root failure는 모두 누락된 `src/graphql/__generated__/ens.ts`에서 파생된다.
- 판정: 이 격리 후보에서 **mobile의 7단계 orchestration과 Xcode 26.6 native build·프로세스 시작은 통과**했다. Firebase/ENS 값은 이 실행 환경 판정에는 필요하지 않지만 실제 Rainbow 화면·지갑 기능 E2E에는 필요하다. 해당 값을 우회하거나 임의 값으로 대체하지 않았으므로 앱 UI 증거는 없으며, ADR-0008의 잠긴 3/3 No-Go 판정도 유지한다. `up-round-3.md`는 잠긴 원본 checkout 재검증이고 이 절은 별도 마이그레이션 가능성 실험이므로 서로 다른 증거다.

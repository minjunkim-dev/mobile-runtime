# ADR-0015: 이름이 debug인 variant는 자동 선택한다

- 상태: 채택
- 날짜: 2026-10-05
- 관련: #146 · #108 · #109 · ADR-0012

#108과 #109은 선택된 application module에서 assemble·install이 있는 debuggable variant가 둘 이상이면 모호로 보고 `mobile.yml`의 `android.variant`를 요구했다. RN 0.82 이상 template은 `debug` 옆에 debuggable `debugOptimized`를 만들기 때문에, 그 계약은 표준 프로젝트마다 설정 파일을 요구한다. `react-native run-android`의 기본 mode는 `debug`다.

## 결정

- 선택된 module의 runnable debuggable variant 중 이름이 정확히 `debug`인 것이 있으면 doctor·build·up이 그것을 고른다. 세 명령은 같은 `AndroidTargetSelector`를 쓴다.
- `debug`가 없는 flavor 조합(`stagingDebug`, `prodDebug` 등)은 계속 모호다. 하나뿐이면 그 하나를 고른다.
- `mobile.yml`의 `android.variant`는 자동 선택보다 우선한다. 지정한 이름이 runnable debuggable 목록에 없으면 에러다.

## 대안

- **debuggable variant가 둘 이상이면 항상 설정 요구**: 기각. RN 기본 template이 설정 없이 돌지 않는다.
- **debuggable 중 첫 번째를 고름**: 기각. 평가 순서에 의존하고 `react-native run-android`의 기본 mode와 어긋난다.

## 결과

- `debug`와 `debugOptimized`만 있는 프로젝트는 `mobile.yml` 없이 `debug`로 doctor·build·up이 진행한다.
- flavor가 갈라진 variant는 여전히 사용자가 고른다. 지원 범위나 Matrix는 바꾸지 않는다.

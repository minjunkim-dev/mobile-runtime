# ADR-0001: Core는 Foundation만 의존하고, 그 경계는 Linux 컴파일로 강제한다

- 상태: 채택
- 날짜: 2026-08-13
- 관련: #9(패키지 구조), #15(doctor 스펙), #16(tracer bullet)

## 배경

Android provider는 Phase 4로 예고돼 있다. iOS 도메인 코드가 Core에 섞이면 그때 분리 비용이 지금 분리 비용보다 크다(#15 user story 49).

그래서 SPM 타깃을 Core / SimulatorKit / mobile 셋으로 나누고, **Core는 Foundation만 의존**하기로 했다. 문제는 강제 수단이다. SwiftPM에는 "이 타깃은 AppKit을 import할 수 없다"를 선언하는 방법이 없다. macOS에서 빌드하는 한 SDK 전체가 사정권에 있고, 규율은 리뷰어의 기억력에만 걸린다.

#16의 acceptance criteria는 "Core가 Apple 프레임워크를 import하면 **컴파일이 깨지는 것**을 확인한다"고 요구한다.

## 결정

**Linux 컨테이너에서 Core를 컴파일하는 것을 그 경계로 삼는다.** Linux에는 Apple 프레임워크가 존재하지 않으므로, 금지된 import는 선언이 아니라 컴파일 실패로 드러난다.

- `scripts/verify-core-linux.sh` — 공식 Swift 이미지에서 `swift build --target Core`.
- 게이트 범위는 **Core 타깃 하나**로 좁힌다. 전체 `swift test`로 넓히지 않는다. SimulatorKit은 설계상 Apple 전용이어도 되는 타깃이라, 언젠가 Apple API를 쓰는 순간 게이트가 잘못 실패한다. 영원히 참이어야 하는 불변식만 게이트에 건다.
- `Tests/CoreTests/CoreImportDisciplineTests.swift`의 import 스캔은 폐기하지 않는다. Docker 없이 즉시 도는 **빠른 메아리**로 남긴다 — 도구가 없는 환경에서도 규율이 보이게 하기 위해서다.

허용 목록: Foundation, 그리고 Core가 선언한 패키지 의존성(Subprocess, Logging).

## 결과

- 규율이 사람 기억에서 컴파일러로 옮겨갔다. 위반은 리뷰가 아니라 빌드가 잡는다.
- Core 개발에 Docker가 필요해졌다. 단 로컬 반복 개발에는 아니고, `Sources/Core`를 건드린 변경을 merge하기 전 1회.
- 이식성 차이가 조기에 드러난다. 실제로 이 게이트를 처음 돌렸을 때 swift-subprocess가 `standardOutput`을 Darwin에서는 `String?`, Linux에서는 `String`으로 준다는 사실이 경고로 드러났다. macOS에서만 빌드했으면 몰랐을 차이다.
- Core에 절대경로 실행이 빠졌다. `Subprocess.Executable.path(_:)`가 요구하는 `FilePath`는 Apple 플랫폼 모듈 `System`에서 오기 때문이다. 현재 호출자는 전원 PATH 이름을 쓰므로 비용이 없다. 절대경로가 실제로 필요해지면 이 ADR을 다시 열어야 한다 — 조용히 `import System`을 추가하는 것은 이 결정을 무효화한다.

## 대안

- **import 스캔 테스트만 둔다.** 문자열 검사라 우회가 쉽고, AC가 요구한 "컴파일이 깨진다"가 아니다. 보조로 남겼다.
- **Linux를 지원 플랫폼으로 선언한다.** 제품으로서 의미가 없다. Linux에는 Xcode도 simctl도 없다. Linux는 지원 대상이 아니라 **경계 검사 도구**다.

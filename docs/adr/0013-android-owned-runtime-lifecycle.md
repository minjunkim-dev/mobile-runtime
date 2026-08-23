# ADR-0013: Android 활성 실행은 소유 자원만 역순 정리한다

- 상태: 채택
- 날짜: 2026-08-23
- 관련: [Android Emulator up·down 소유권 계약 확정](https://github.com/minjunkim-dev/mobile-runtime/issues/113) · [Private Android alpha runbook과 후보 SHA 검증](https://github.com/minjunkim-dev/mobile-runtime/issues/117) · PR [#124](https://github.com/minjunkim-dev/mobile-runtime/pull/124) · ADR-0007 · ADR-0010

Android provider는 프로젝트·플랫폼별 활성 실행 기록에 Emulator, Metro, `adb reverse`, 앱의 `started|reused` 또는 `created|reused` 상태를 자원 획득 즉시 원자적으로 남긴다. 같은 대상을 향한 반복 `up`은 기존 실행에 합류하되 소유권을 낮추지 않고, 다른 대상이나 동시 lifecycle 명령은 멈춘다. PID만 믿지 않고 AVD 이름·serial·프로젝트 anchor·현재 mapping·application ID처럼 자원별 identity를 다시 확인한 뒤, 이번 활성 실행이 만든 자원만 정리한다.

`up`은 `validate → dependencies → android.build`를 무부작용 prefix로 끝낸 다음 Emulator, 앱 설치, Metro, reverse, launch를 진행한다. 실패하면 소유 자원을 역순으로 best-effort rollback하고, `down`도 같은 non-fail-fast 정리 job을 `app → adb.reverse → metro → emulator` 순서로 사용한다. 재사용한 자원과 identity를 확인할 수 없는 자원은 보존하며 uninstall, clear-data, AVD 생성·삭제, `SIGKILL`은 하지 않는다. 남은 기록은 후속 `down`이 재시도하고, 기록이 없으면 세계를 재추론하지 않고 할 일 없음으로 끝낸다.

이 결정은 실패한 `up`이 자원을 남기는 기존 iOS 계약보다 엄격하지만 ADR-0007을 바꾸지 않는다. Android의 정확한 소유 증거가 기존 iOS의 Metro 정체성·설치 기록과 다르므로 공통 provider abstraction도 아직 만들지 않는다. lifecycle 계약은 Core의 CLI 출력과 향후 SwiftUI macOS 앱 표현 양쪽에서 사용할 수 있도록 UI와 분리하되, Private Phase 4A의 납품 범위는 CLI Android provider까지다.

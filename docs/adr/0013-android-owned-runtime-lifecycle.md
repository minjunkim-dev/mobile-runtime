# ADR-0013: Android 활성 실행은 소유 자원만 역순 정리한다

- 상태: 채택
- 날짜: 2026-08-23
- 관련: [Android Emulator up·down 소유권 계약 확정](https://github.com/minjunkim-dev/mobile-runtime/issues/113) · [Private Android alpha runbook과 후보 SHA 검증](https://github.com/minjunkim-dev/mobile-runtime/issues/117) · PR [#124](https://github.com/minjunkim-dev/mobile-runtime/pull/124) · ADR-0007 · ADR-0010

Android provider는 프로젝트·플랫폼별 활성 실행 기록에 Emulator, Metro, `adb reverse`, 앱의 `started|reused` 또는 `created|reused` 상태를 자원 획득 즉시 원자적으로 남긴다. 같은 대상을 향한 반복 `up`은 기존 실행에 합류하되 소유권을 낮추지 않고, 다른 대상이나 동시 lifecycle 명령은 멈춘다. PID만 믿지 않고 AVD 이름·serial·프로젝트 anchor·현재 mapping·application ID처럼 자원별 identity를 다시 확인한 뒤, 이번 활성 실행이 만든 자원만 정리한다.

`up`은 `validate → dependencies → android.build`를 무부작용 prefix로 끝낸 다음 Emulator, 앱 설치, Metro, reverse, launch를 진행한다. 실패하면 소유 자원을 역순으로 best-effort rollback하고, `down`도 같은 non-fail-fast 정리 job을 `app → adb.reverse → metro → emulator` 순서로 사용한다. 재사용한 자원과 identity를 확인할 수 없는 자원은 보존하며 uninstall, clear-data, AVD 생성·삭제, `SIGKILL`은 하지 않는다. 남은 기록은 후속 `down`이 재시도하고, 기록이 없으면 세계를 재추론하지 않고 할 일 없음으로 끝낸다.

이 결정은 실패한 `up`이 자원을 남기는 기존 iOS 계약보다 엄격하지만 ADR-0007을 바꾸지 않는다. Android의 정확한 소유 증거가 기존 iOS의 Metro 정체성·설치 기록과 다르므로 공통 provider abstraction도 아직 만들지 않는다. lifecycle 계약은 Core의 CLI 출력과 향후 SwiftUI macOS 앱 표현 양쪽에서 사용할 수 있도록 UI와 분리하되, Private Phase 4A의 납품 범위는 CLI Android provider까지다.

## SDK root 실패 분류 (#265, 2026-10-15)

SDK root 선언 누락과 선언 간 충돌은 사용자 환경의 도메인 실패다. `up`·Android rollback·`down`은 같은 원인과 remediation을 보고하며 exit 1을 사용한다. SDK root를 정하지 못해 소유권을 관측하지 못한 정리 항목은 `unknown`으로 남긴다. 해당 자원과 소유 기록을 보존한다. SDK root 없이도 안전하게 확인할 수 있는 자원은 기존 best-effort 정리를 계속한다. 실제 도구 실행·기록 장애가 함께 있으면 exit 2를 유지한다. 취소는 exit 130을 유지한다. rollback은 원래 `up` 실패를 보존하며 종료 코드만 기존 우선순위에 따라 올릴 수 있다.

## 남은 앱 claim 정리 (#361, 2026-11-01)

claim은 이 프로젝트의 Runstir 실행이 그 기기에 남긴 앱을 뜻한다. `down`이 그 앱의 force-stop과 중지를 관측하면 실행은 끝난다. Emulator를 보존해도 그 기기의 claim을 해제한다. 중지를 관측하지 못하면 claim을 보존하고 `android.claim` 항목에 이유를 남긴다. 그 뒤 OS나 앱 자신이 프로세스를 다시 띄워도 Runstir 실행이 아니다. 재시작을 막거나 감시하지 않는다. active run 기록이 없어도 claim 파일은 소유 기록이다. 소유 프로젝트의 `down`은 기기 lease를 잡고 claim의 앱을 관측한다. 중지됐으면 claim을 해제한다. 실행 중이면 AVD와 serial 대응을 확인한 뒤 그 application ID만 force-stop하고, 중지를 관측하면 해제한다. 관측할 수 없으면 claim을 보존하고 AVD를 켠 뒤 다시 `down`하라고 안내한다. 다른 프로젝트의 claim과 claim 없는 reservation은 바꾸지 않는다. 다른 프로젝트의 `up`이 남은 claim 때문에 거부되면 owner 프로젝트와 `mobile down --platform android`를 안내한다. 기록이 없을 때 세계를 재추론하지 않는다는 원칙과 충돌하지 않는다. claim 파일 자체가 기록이다.

## 기기에 닿지 않은 up의 reservation (#373, 2026-11-02)

`up`은 단계 전에 기기 reservation을 쓴다. 이때 그 기기에 있던 이 프로젝트의 reservation을 대체한다. `up`이 빌드된 제품 없이 끝나면 fail-fast pipeline이 런타임 단계를 하나도 실행하지 않은 것이다. 이때 `up`은 대체한 reservation을 되돌린다. 이전 claim이 있으면 다시 쓰고, 없으면 파일을 지운다. 빌드 중 취소와 빌드 실패가 여기에 해당한다. 기기에 닿은 뒤의 실패와 강제 종료가 남긴 claim 없는 reservation은 그대로 보존한다. 소유 프로젝트의 `down`은 여전히 그것을 바꾸지 않는다. 다른 프로젝트의 Android `up`이 이 reservation 때문에 거부되면 owner 프로젝트에서 그 AVD로 `mobile up --platform android`을 다시 실행해 결과를 기록하고 `mobile down --platform android`을 실행하라고 안내한다. iOS reservation은 바꾸지 않는다.

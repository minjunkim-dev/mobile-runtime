# SpikeIOS 결과 (2026-08-13)

환경: Xcode 26.6 (17F113) / Swift 6.3.3 / iOS 26.5 runtime (23F77) / iPhone 17 Pro

## 결과

전 단계 성공, 2회 연속. 총 44~58초 (boot 28~45s가 지배적, 나머지 단계 합계 ~12s).

```
Xcode 탐지 → list -j 파싱(isAvailable 필터) → create → bootstatus -b
→ install(수제 .app) → launch(PID) → screenshot(렌더 확인) → shutdown → delete
```

Simulator.app 없이 headless로 전 과정 동작. 스크린샷에서 앱 UI(녹색 배경 + 라벨) 렌더 확인.

## 발견한 함정

1. **launch는 UI 렌더 완료를 보장 안 함.** launch 직후 스크린샷은 런치 전환 애니메이션(검은 화면)이 찍힘. 3초 대기 후 정상. boot(→bootstatus)와 같은 계열의 "리턴 ≠ 완료" 함정 — Core에서는 폴링 또는 설정 가능한 settle 대기가 필요.
2. **swift-subprocess 1.0.0 레퍼런스 얇음 실감.** 제안서 시절 타입명 `CollectedResult`가 1.0에서 `ExecutionResult`로 변경 — 문서보다 소스를 봐야 했음. API 자체는 async/await 기반으로 깔끔, non-zero exit이 throw가 아니라 terminationStatus 검사인 점도 orchestration에 적합.
3. **타임아웃은 라이브러리에 없음** — Task cancel 조합으로 직접 구성. bootstatus 120s 타임아웃 패턴 동작 확인 (이번엔 미발동).
4. **수제 .app 번들로 install 검증 가능** — Info.plist 7키 + swiftc(-parse-as-library, iphonesimulator SDK) 산출물이면 install/launch 됨. xcodebuild 불필요. 테스트 픽스처로 재사용 가치.
5. bootstatus -b는 idempotent(미부팅 시 부팅 시작 + 대기) 동작 확인 — boot를 따로 부를 필요 없음.

## Core 설계에 넘길 판단 재료 (#9)

- swift-subprocess 채택 지지: API 품질 좋음. 단 타임아웃/스트리밍 래퍼(ProcessRunner)는 우리 층에서 제공.
- JSON 파싱은 spike에선 JSONSerialization — Core에선 Codable 모델로.
- "리턴 ≠ 완료" 함정이 boot/launch 두 곳에서 확인됨 → 상태 폴링을 1급 개념으로.

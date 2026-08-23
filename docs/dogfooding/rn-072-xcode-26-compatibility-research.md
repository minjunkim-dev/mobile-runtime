# RN 0.72 / Xcode 26.6 / iOS Simulator 26.5 호환성 조사

조사일: 2026-08-23
대상: [GitHub issue #93](https://github.com/minjunkim-dev/mobile-runtime/issues/93)

## 결론

현재 조합의 검증 결과는 **`inconclusive`**다. 지원 범위를 설정할 Tier 2 근거가 없으므로 Matrix를 변경하지 않고 doctor의 `unknown`을 유지한다. 이것은 “RN 0.72가 Xcode 26.6에서 반드시 동작하지 않는다”는 incompatibility 판정이 아니다. 현재 저장소의 매트릭스가 RN 0.72를 다루지 않고, 실제 known-good 프로젝트의 build·launch·초기 UI 증거도 확보되지 않아 결과를 이 조합에 귀속할 수 없다는 판정이다. 검증 관측과 지원 범위의 경계는 [ADR-0012](../adr/0012-separate-validation-observations-from-support.md)에 기록했다.

따라서 #93의 remediation 경로는 다음이다.

1. 기존 개발 절차로 정상 실행되는 RN 0.72 iOS 프로젝트를 known-good 표본으로 확보하고 project SHA를 고정한다.
2. project SHA·mobile SHA·검증 조합을 고정한다. 같은 host에서 project-native build·install·launch·초기 UI baseline을 먼저 확인한 뒤 `doctor --json`의 `unknown`을 기록하고 별도 조사 실행으로 `build --json` → `up --json` → 초기 UI 확인을 진행한다. 실행 전후 tracked 상태도 비교한다.
3. 전체 체인이 성공하면 해당 검증 조합을 `validated`, known-good baseline 이후 동일한 mobile/toolchain 실패가 재현되면 `failed`, 결과를 귀속할 수 없으면 `inconclusive`로 기록한다. 어느 한 결과도 단독으로 지원 범위나 Matrix 행으로 승격하지 않는다.
4. project SHA·mobile SHA·검증 조합 중 하나가 바뀌면 전체 조사 실행을 새로 한다. 이번 조사에서는 검증 대상 프로젝트의 tracked 파일을 변경하지 않았다.

## 현재 issue 상태와 acceptance criteria

Issue #93은 2026-08-23 **CLOSED · COMPLETED**로 종료됐다. 제목은 “alpha: RN 0.72에서 Xcode 26.6·iOS 26.5 호환성 근거 판정”이며, 최종 결정은 `inconclusive`, Matrix 변경 없음, doctor `unknown` 유지다. [live issue](https://github.com/minjunkim-dev/mobile-runtime/issues/93), [decision comment](https://github.com/minjunkim-dev/mobile-runtime/issues/93#issuecomment-5383557036)

| Acceptance criterion | 판정 | 근거 |
| --- | --- | --- |
| RN 0.72 + Xcode 26.6 + iOS 26.5의 지원 여부를 Tier 2로 결정 | **충족 — `inconclusive`** | 현재 matrix에 RN 0.72 행이 없고 exact 조합의 known-good build·launch evidence도 없어 지원 또는 비지원으로 귀속하지 않는다. [matrix](https://github.com/minjunkim-dev/mobile-runtime/blob/283e6528bcb8b48ae35f8a3b2980289823457f2c/Sources/Core/Resources/matrix.json#L2-L26), [ADR-0012](../adr/0012-separate-validation-observations-from-support.md) |
| 지원한다면 matrix와 regression test가 두 check를 근거 있는 pass/warning으로 판정 | **해당 없음 / 충족** | 지원으로 판정하지 않았으므로 Matrix와 테스트를 변경하지 않는다. 기존 테스트는 RN 0.72 lookup이 `nil`임을 고정하고 matrix coverage를 `0.73–0.87`로 유지한다. [matrix tests](https://github.com/minjunkim-dev/mobile-runtime/blob/283e6528bcb8b48ae35f8a3b2980289823457f2c/Tests/CoreTests/CompatibilityMatrixTests.swift#L9-L56), [doctor tests](https://github.com/minjunkim-dev/mobile-runtime/blob/283e6528bcb8b48ae35f8a3b2980289823457f2c/Tests/SimulatorKitTests/DoctorMatrixChecksTests.swift#L1-L25) |
| 지원하지 않거나 근거가 부족하면 unknown을 유지하고 remediation 제공 | **충족(이번 findings 기준)** | 아래의 명시적 unknown 판정과 표본·재실행 remediation으로 다음 행동을 결정할 수 있다. 저장소 규칙도 근거가 없을 때 `unknown`을 사용하도록 한다. [CONTEXT](https://github.com/minjunkim-dev/mobile-runtime/blob/283e6528bcb8b48ae35f8a3b2980289823457f2c/CONTEXT.md#L13-L44) |
| 같은 alpha 후보를 바꾸는 수정이면 새 SHA로 전체 evidence matrix 재실행 | **현재 적용할 수정 없음** | Matrix·code·alpha 후보를 수정하지 않았다. project SHA·mobile SHA·검증 조합 중 하나가 바뀌는 후속 조사에는 전체 재실행 규칙을 적용한다. [ADR-0012](../adr/0012-separate-validation-observations-from-support.md) |
| project tracked 파일을 변경하지 않음 | **관측상 충족** | 검증 대상 프로젝트의 조사 전후 tracked 상태가 clean이었다. 저장소에는 조사·결정 문서만 추가한다. [issue acceptance criteria](https://github.com/minjunkim-dev/mobile-runtime/issues/93) |

## 관측된 저장소·issue evidence

- #93 본문은 실제 RN 0.72 프로젝트에서 `doctor --json`이 exit 0이었지만 필수 check `xcode.version`과 `simulator.runtime`을 `unknown`으로 판정했고, runbook 규칙 때문에 build·up·초기 UI를 실행하지 않았다고 기록한다. [issue #93](https://github.com/minjunkim-dev/mobile-runtime/issues/93)
- issue comment는 같은 project SHA의 project-native iOS build가 Xcode exit 65 / arm64 link failure로 중단되어 launch와 초기 UI를 확인하지 못했고, 따라서 known-good 표본으로 승인하지 않았다고 추가한다. [comment](https://github.com/minjunkim-dev/mobile-runtime/issues/93#issuecomment-5379950352)
- 후속 comment는 RN 0.72 첫 표본을 known-good 전제 미충족으로 교체했으며, #93은 해당 조합의 별도 호환성 조사로 유지한다고 명시한다. [comment](https://github.com/minjunkim-dev/mobile-runtime/issues/93#issuecomment-5379999080)
- 현재 issue의 observed failure는 “지원 불가”의 직접 증거가 아니라, 표본 적격성·matrix lookup·실행 evidence가 모두 결정에 충분하지 않았다는 증거다. 이 문장은 위 issue 기록과 저장소의 `unknown` 계약을 결합한 **inference**다. [issue](https://github.com/minjunkim-dev/mobile-runtime/issues/93), [ADR-0003](https://github.com/minjunkim-dev/mobile-runtime/blob/283e6528bcb8b48ae35f8a3b2980289823457f2c/docs/adr/0003-evidence-chain-for-judgements.md#L21-L37)
- 최종 decision comment는 이 결과를 `inconclusive`로 확정하고 Matrix·code·alpha runbook을 변경하지 않은 채 issue를 종료했다. [decision comment](https://github.com/minjunkim-dev/mobile-runtime/issues/93#issuecomment-5383557036)

## 현재 matrix coverage

저장소의 bundled matrix는 schema 1, updated `2026-08-14`이며 React Native 행의 범위는 **0.73–0.87, 총 15개 minor 행**이다. matrix가 기록한 iOS 하한은 다음과 같다. [matrix.json](https://github.com/minjunkim-dev/mobile-runtime/blob/283e6528bcb8b48ae35f8a3b2980289823457f2c/Sources/Core/Resources/matrix.json#L1-L30)

| RN 행 | Xcode 하한 | iOS runtime 하한 |
| --- | --- | --- |
| 0.73–0.75 | 15.1 | 13.4 |
| 0.76–0.80 | 15.1 | 15.1 |
| 0.81–0.86 | 16.1 | 15.1 |
| 0.87 | 26.0 | 15.1 |

RN **0.72 행은 존재하지 않는다**. lookup은 minor prefix를 사용하므로 0.72.0은 가장 가까운 0.73 행으로 추정되지 않고 `nil`이 된다. 이 동작은 regression test로 명시되어 있고, matrix가 답하지 못하면 pass가 아니라 unavailable/unknown 경로로 내려간다. [CompatibilityMatrixTests](https://github.com/minjunkim-dev/mobile-runtime/blob/283e6528bcb8b48ae35f8a3b2980289823457f2c/Tests/CoreTests/CompatibilityMatrixTests.swift#L30-L40), [MatrixLookup](https://github.com/minjunkim-dev/mobile-runtime/blob/283e6528bcb8b48ae35f8a3b2980289823457f2c/Sources/Core/Matrix/MatrixLookup.swift#L161-L183)

따라서 현재 matrix의 0.87 행 `Xcode 26.0 / runtime 15.1`을 RN 0.72에 전이하거나, Xcode 26.6과 iOS 26.5가 더 새 버전이라는 이유로 0.72를 통과시키는 것은 저장소의 Tier 2 규칙이 아니다. 이는 데이터 구조와 exact-row lookup에 따른 **inference**다. [Tier 2 정의](https://github.com/minjunkim-dev/mobile-runtime/blob/283e6528bcb8b48ae35f8a3b2980289823457f2c/CONTEXT.md#L13-L24), [CompatibilityMatrix](https://github.com/minjunkim-dev/mobile-runtime/blob/283e6528bcb8b48ae35f8a3b2980289823457f2c/Sources/Core/Matrix/CompatibilityMatrix.swift#L1-L31)

이번 조사에서 해당 두 테스트 suite를 로컬 실행했고 모두 통과했다. 이 결과가 증명하는 것은 “현재 matrix의 no-row/unknown 계약과 일반 host-check 로직이 회귀하지 않았다”는 것뿐이며, RN 0.72의 실제 Xcode 26.6 build·launch 호환성은 증명하지 않는다. [matrix test source](https://github.com/minjunkim-dev/mobile-runtime/blob/283e6528bcb8b48ae35f8a3b2980289823457f2c/Tests/CoreTests/CompatibilityMatrixTests.swift), [doctor matrix test source](https://github.com/minjunkim-dev/mobile-runtime/blob/283e6528bcb8b48ae35f8a3b2980289823457f2c/Tests/SimulatorKitTests/DoctorMatrixChecksTests.swift)

## 공식 upstream evidence

- React Native Releases Working Group의 공식 support policy 표는 RN 0.72의 Xcode minimum을 **15.1**로 기록한다. 같은 공식 release 자료에서 0.72.17은 “out of the support window”이며 0.75로 migrate하라고 안내한다. 이는 RN 0.72의 공식 지원 상태와 historical minimum을 알려주지만, Xcode 26.6 + iOS 26.5의 실제 build·launch 성공을 보증하지 않는다. [support policy](https://github.com/reactwg/react-native-releases/blob/main/docs/support.md), [RN 0.72.17 release](https://github.com/facebook/react-native/releases/tag/v0.72.17)
- Apple의 Xcode 26.6 release notes는 Xcode 26.6에 iOS 26.5 SDK가 포함되고 macOS Tahoe 26.2 이상이 필요하다고 명시한다. 이는 **Apple toolchain 조합이 존재한다는 관측**이지, RN 0.72가 그 조합에서 동작한다는 React Native 호환성 증거가 아니다. [Apple Xcode 26.6 release notes](https://developer.apple.com/documentation/Xcode-Release-Notes/xcode-26_6-release-notes)
- 위 공식 자료 어디에도 “React Native 0.72가 Xcode 26.6 및 iOS Simulator 26.5에서 지원된다”는 exact-combination claim은 확인되지 않았다. 이것은 공식 문서가 직접 incompatibility를 선언했다는 뜻이 아니라, 현재 issue의 Tier 2 지원 결정을 채울 **unverified gap**이다. [RN support policy](https://github.com/reactwg/react-native-releases/blob/main/docs/support.md), [Apple release notes](https://developer.apple.com/documentation/Xcode-Release-Notes/xcode-26_6-release-notes)

## Evidence boundary

### 확인된 것

- issue는 CLOSED · COMPLETED이고, RN 0.72 표본은 known-good으로 승인되지 않아 최종 결과가 `inconclusive`다. [issue #93](https://github.com/minjunkim-dev/mobile-runtime/issues/93)
- 저장소 matrix는 RN 0.73–0.87만 포함하며 RN 0.72 lookup을 의도적으로 `nil`로 테스트한다. [matrix](https://github.com/minjunkim-dev/mobile-runtime/blob/283e6528bcb8b48ae35f8a3b2980289823457f2c/Sources/Core/Resources/matrix.json#L8-L29), [test](https://github.com/minjunkim-dev/mobile-runtime/blob/283e6528bcb8b48ae35f8a3b2980289823457f2c/Tests/CoreTests/CompatibilityMatrixTests.swift#L30-L40)
- matrix가 답하지 못할 때 저장소의 계약은 근거 없는 pass가 아니라 `unknown`이다. [CONTEXT](https://github.com/minjunkim-dev/mobile-runtime/blob/283e6528bcb8b48ae35f8a3b2980289823457f2c/CONTEXT.md#L32-L44), [doctor tests](https://github.com/minjunkim-dev/mobile-runtime/blob/283e6528bcb8b48ae35f8a3b2980289823457f2c/Tests/SimulatorKitTests/DoctorMatrixChecksTests.swift#L176-L220)
- alpha runbook은 required `unknown`/`error`, build 증거 부족, 초기 UI 미관측, tracked mutation을 Alpha blocker로 정의한다. 별도 조사 실행은 이 alpha 성공 기준을 완화하지 않고 관측 근거만 수집한다. [runbook](https://github.com/minjunkim-dev/mobile-runtime/blob/283e6528bcb8b48ae35f8a3b2980289823457f2c/docs/internal-alpha-runbook.md#L67-L121), [ADR-0012](../adr/0012-separate-validation-observations-from-support.md)

### 추론한 것

- Xcode 26.6이 RN 0.72의 공식 historical minimum 15.1보다 높다는 사실만으로 exact compatibility를 판정할 수 없다. 이 저장소의 matrix는 “framework minor → measured requirement” 데이터이며, 인접 minor의 행을 복사하는 fallback이 아니다. [CONTEXT](https://github.com/minjunkim-dev/mobile-runtime/blob/283e6528bcb8b48ae35f8a3b2980289823457f2c/CONTEXT.md#L13-L24), [ADR-0003](https://github.com/minjunkim-dev/mobile-runtime/blob/283e6528bcb8b48ae35f8a3b2980289823457f2c/docs/adr/0003-evidence-chain-for-judgements.md#L21-L37)
- 현재 가장 정직한 사용자-facing 판정은 `unsupported/unknown with remediation` 중 **unknown with remediation**이다. 실제 실패가 재현되어 incompatibility가 확정된 것이 아니기 때문이다. [issue evidence](https://github.com/minjunkim-dev/mobile-runtime/issues/93), [status policy](https://github.com/minjunkim-dev/mobile-runtime/blob/283e6528bcb8b48ae35f8a3b2980289823457f2c/docs/adr/0004-status-grade-policy.md)

### 아직 검증하지 못한 것

- RN 0.72의 특정 patch release와 그 iOS dependency graph가 Xcode 26.6 / iOS Simulator 26.5에서 실제로 compile·link·install·launch되는지.
- project-native Xcode exit 65 / arm64 link failure의 근본 원인이 RN 0.72 자체인지, 프로젝트 dependency/configuration인지.
- matrix에 RN 0.72를 추가할 수 있을 정도의 authoritative per-tag evidence와 독립 known-good 표본.
- exact 조합으로 `doctor` 두 check를 통과한 뒤 `build`, `up`, 초기 UI 및 전후 Git cleanliness까지 완주한 Tier 2/alpha evidence.

## 권장 결정

`#93`은 **`inconclusive`로 종료**한다. Matrix와 코드는 변경하지 않고 doctor의 `unknown`을 유지한다. known-good RN 0.72 프로젝트를 확보하거나 기존 표본의 정상 baseline을 복구하면 같은 mobile SHA와 검증 조합으로 조사 실행을 수행하고 #93을 다시 연다. 성공은 해당 조합의 `validated` 관측으로만 기록하며, 일반 지원 범위나 Matrix 행으로 승격하려면 별도의 authoritative 근거와 결정이 필요하다. 실패는 `failed` 검증 결과와 project-specific blocker를 분리해 기록한다. [ADR-0012](../adr/0012-separate-validation-observations-from-support.md), [ADR-0005](https://github.com/minjunkim-dev/mobile-runtime/blob/283e6528bcb8b48ae35f8a3b2980289823457f2c/docs/adr/0005-remediation-is-measured-not-assumed.md)

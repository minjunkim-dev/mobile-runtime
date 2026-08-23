# Private iOS 내부 alpha round 2

## Handoff

- Candidate `mobile` SHA: `9e667f938b0e0859e8659fc51e197da976001a31`
- Ordered runbook: `docs/internal-alpha-runbook.md`
- Distribution: exact private source SHA; installer나 별도 배포물 없음
- Round rule: #92와 #95 수정으로 `mobile` SHA가 바뀌어 maintainer와 초대 개발자 matrix를 모두 새로 실행했다.
- 이 문서를 추가하는 후속 documentation commit은 검증 후보에 포함하지 않는다.

## 저장소 게이트와 호스트

동일한 candidate SHA의 detached worktree에서 `swift build` 전후 tracked 상태가
clean임을 확인했다.

| Gate | Result | Evidence summary |
| --- | --- | --- |
| `swift test` | PASS (exit 0) | 52 suites, 415 tests, 0 failures |
| `scripts/verify-core-linux.sh` | PASS (exit 0) | Linux `Core` target build complete |

- macOS `26.6.2` (`arm64`)
- Xcode `26.6` (`17F113`)
- Swift `6.3.3`
- Docker `29.4.0`, server `linux/arm64`
- Simulator: `iPhone 17 Pro`, iOS `26.5`

## Maintainer 실행

### Participant evidence

- Participant alias: `maintainer-rn-ios-b`
- Project SHA: `e58a9b4aee58b1d833b41f1b436de458f40fca71`
- Known-good preparation: project-owned `./setup.sh --verify`; dependency payload drift 발견 후 공식 `./setup.sh --ios-only`
- Expected initial UI: 파란 온보딩 첫 화면, 캐릭터 이미지, 안내 문구와 `SKIP`
- Before tracked state: clean

### 초기 실패와 수정

1. `mobile.yml`이 없는 첫 실행에서 `doctor --json`은 exit 0 / warning
   (9 pass, 1 warning)이었고, 두 scheme 중 하나를 선택하지 않아 `build --json`은
   validate stage에서 exit 1로 중단됐다.
2. participant가 project-owned untracked `mobile.yml`에 device와 `rn079-dev`
   scheme을 선언했다. tracked 파일은 편집하지 않았다.
3. 재실행한 doctor, build, up은 모두 exit 0이었지만 예상 UI 대신 project
   dependency payload의 누락 모듈 오류 화면이 나타났다. UI 미확인이므로 이
   실행은 성공 증거로 쓰지 않았다.
4. `./setup.sh --ios-only`로 project dependency baseline을 복구하고 `mobile down`
   후 동일 candidate/project SHA에서 전체 순서를 다시 실행했다.

### 최종 command summary

| Step | Result | Summary |
| --- | --- | --- |
| `doctor --json` | PASS (exit 0) | status pass, 11/11 checks pass |
| `build --json` | PASS (exit 0) | validate, dependencies, build pass; compile success |
| `up --json` | PASS (exit 0) | Metro listener, build, install, launch pass |
| UI 확인 | PASS | freshly built app의 예상 온보딩 첫 화면 직접 관측 |

### 상태와 피드백

- Full status snapshot SHA-256 before/after:
  `8b09b0e0999e11598fef8816c38d26821a4e4938041dcebb7689649fde6f1bf7`
- Full snapshot byte-for-byte equal: yes
- After tracked state: clean
- Existing/generated state: ignored 8, untracked 1 (`mobile.yml`); before/after 동일
- Unexpected tracked mutation: none
- Maintainer intervention: none; participant가 project setup과 untracked config를 준비
- Feedback: scheme 선택은 명시적 project config가 필요했다. dependency baseline
  복구 뒤 runbook 순서만으로 전체 flow를 완료했다.

## 초대 개발자 독립 실행

### Participant evidence

- Participant alias: `invited-rn-ios-c`
- Project SHA: `e17840395a8becbab3e81276adbc511abde38b9d`
- Known-good preparation: project-owned `./setup.sh --verify` PASS
- Expected initial UI: branded initial screen
- Before tracked state: clean

### 초기 실패와 수정

1. `mobile.yml`이 없는 첫 실행에서 `doctor --json`은 exit 0 / warning
   (8 pass, 1 warning)이었고, root workspace의 다중 scheme을 선택하지 않아
   `build --json`은 validate stage에서 exit 1로 중단됐다.
2. participant가 project-owned untracked `mobile.yml`에 device와 app scheme
   `App`을 선언했다. tracked 파일은 편집하지 않았다.
3. 동일 candidate/project SHA에서 doctor부터 전체 순서를 다시 실행했다.

### 최종 command summary

| Step | Result | Summary |
| --- | --- | --- |
| `doctor --json` | PASS (exit 0) | status pass, 10/10 checks pass |
| `build --json` | PASS (exit 0) | root workspace + nested project에서 compile success |
| `up --json` | PASS (exit 0) | Metro listener, build, install, launch pass |
| UI 확인 | PASS | freshly built app의 branded initial screen 직접 관측 |

### 상태와 피드백

- Full status snapshot SHA-256 before/after:
  `e067aa352d7a697eb174232f22a57c6f3d8375b0ab70a63d84c057f42d277058`
- Full snapshot byte-for-byte equal: yes
- After tracked state: clean
- Existing/generated state: ignored 62, untracked 1 (`mobile.yml`); before/after 동일
- Unexpected tracked mutation: none
- Maintainer intervention: none; participant가 project setup과 untracked config를 준비
- Feedback: #92 수정 뒤 root workspace와 nested Xcode project 조합이 doctor와
  build에서 같은 target으로 판정됐다. 초기 UI 이후의 network/permission prompt는
  project-specific behavior이며 필수 flow에 영향을 주지 않았다.

## 수정 연결과 알려진 제약

- #92는 PR #101에서 root workspace fallback을 공통 build target 선택에 적용하고
  회귀 테스트를 추가해 해결했다. macOS Swift tests와 Linux Core compile이 통과했다.
- #95는 PR #102에서 Metro listener 또는 start process 종료를 readiness 판정에
  반영하고 회귀 테스트를 추가해 해결했다. 같은 두 CI gate가 통과했다.
- #93은 최종 두 참여자 표본에 포함되지 않은 RN 0.72 탈락 표본의 호환성 조사다.
  2026-08-23 `inconclusive`로 종료했으며 Matrix와 doctor의 `unknown`을 유지한다.
  이 결정은 현재 성공 matrix의 필수 증거를 무효화하지 않는다(ADR-0012).
- #96은 PR #104에서 Metro bundle 완료 신호를 인식하도록 수정하고 회귀 테스트를
  추가해 해결했다. 당시 실제 listener, build, install, launch, 초기 UI를 별도로
  확인했으므로 수정 전에도 이번 판정을 막지 않는 non-blocker였다.
- development warning UI와 초기 UI 이후 project-specific prompt는 예상 초기
  화면과 필수 command flow를 막지 않아 명시적으로 수용한다.

## 완료 판정과 경계

- Candidate SHA에서 저장소 게이트와 두 독립 실제 프로젝트의
  `doctor → build → up → UI 확인 → tracked 무변경` matrix가 모두 통과했다.
- 초기 scheme/config 실패와 maintainer project dependency baseline 실패는 수정과
  전체 재실행 이력과 함께 보존했다.
- 필수 `error`·`unknown`, build/up 실패, UI 미확인, tracked mutation,
  보안·데이터 손실 위험, undocumented intervention은 최종 matrix에 남지 않았다.
- 모든 Alpha blocker는 해소됐다. #93은 `inconclusive` 결정으로, #96은 PR #104로
  각각 종료됐으며 private alpha 완료 판정은 바뀌지 않는다.
- 따라서 **private iOS 내부 alpha를 완료로 선언한다.**
- 이 판정은 private iOS 내부 alpha에만 적용된다. ADR-0008의 3-repository
  Go/No-Go를 변경하지 않으며 public, external, 일반 React Native 지원을
  승인하거나 확장하지 않는다.
- secrets, raw environment files, complete logs, screenshots, application data는
  이 기록에 포함하지 않았다.

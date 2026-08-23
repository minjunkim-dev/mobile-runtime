# Private iOS 내부 alpha round 1

이 기록은 issue #85의 저장소 게이트, issue #86의 maintainer 실제 프로젝트,
issue #87의 초대 개발자 실제 프로젝트 실행 증거다. 내부 alpha 완료는 아직
주장하지 않는다.

## Handoff

```text
Alpha round: 2026-08-22-1
mobile SHA: 0033d1cef951809cdd6de40604b53b8d47f43a42
Runbook: docs/internal-alpha-runbook.md @ 0033d1cef951809cdd6de40604b53b8d47f43a42
필수 참여자: maintainer 1명, 초대된 RN iOS 개발자 1명
```

후보는 2026-08-22 KST의 최신 `main`에서 고정했다. 이 기록을 추가하는 commit은
후보에 포함되지 않으며, 참여자는 branch나 이 기록의 commit이 아니라 위 40자
SHA를 사용한다.

## 저장소 게이트

검증 전후 `HEAD`는 위 SHA와 일치했고 tracked worktree는 clean이었다.

| Gate | Result | Sanitized summary |
| --- | --- | --- |
| macOS 전체 `swift test` | PASS (exit 0) | 411 tests / 52 suites / 0 failures |
| `scripts/verify-core-linux.sh` | PASS (exit 0) | `Core` target build complete |

### 재현 환경

- Host: macOS 26.6.2 (25G83), arm64
- Xcode: 26.6 (17F113)
- Host Swift: Apple Swift 6.3.3, target `arm64-apple-macosx26.0`
- Docker client/server: 29.4.0, context `orbstack`, server `linux/arm64`
- Linux image: `swift:6.3-noble`
- Linux image digest: `swift@sha256:56ef1be2c1ca36f4c52440357dc1fcdfdb5e113587134fcadeef57c225c71b54`
- Linux Swift: 6.3.3, target `aarch64-unknown-linux-gnu`
- Generated artifacts: ignored `.build/` and `.build-linux/`; unexpected tracked
  mutation 없음

## Maintainer 실제 프로젝트 실행 (#86)

초대 개발자의 add-to-app 표본과 다른 React Native 0.72 iOS host를 표본
후보로 점검했다. 프로젝트 이름과 경로는 기록하지 않고
`maintainer-rn-ios-a`로 식별한다. 현재 project SHA의 정상 실행 근거를
재확인하지 못해 이 후보를 known-good 표본으로 승인하지 않았으며, 아래 결과는
#86 완료 증거가 아니라 Alpha blocker 증거다.

```text
## Participant evidence

- Alpha round: 2026-08-22-1
- Role: maintainer
- Independent run: yes
- mobile full SHA: 0033d1cef951809cdd6de40604b53b8d47f43a42
- Project alias: maintainer-rn-ios-a
- Project full SHA: 571e9e91c90d4d7dfb45a40b2db05b0ab18b94ec
- Known-good 근거: 없음; project-native iOS build가 Xcode exit 65 / arm64 link failure로 중단되어 현재 SHA의 정상 build·launch·초기 UI를 확인하지 못함
- Before tracked state: clean
- Host: macOS 26.6.2 / arm64 / Xcode 26.6 (17F113)
- Simulator: iPhone 17 Pro - iOS 26.5 / runtime 26.5 (23F77)
- Project-owned app environment ready: no (`.env*` 파일이 없고 준비 절차나 example도 확인되지 않음; 값은 열람하지 않음)
- Expected initial UI: 확인 불가 (현재 SHA의 마지막 정상 실행 근거 없음)

### Command summary
- Known-good eligibility recheck (project-native command): exit 1 / Xcode exit 65 / arm64 link failure / launch no / tracked clean after
- doctor --json: exit 0 / status unknown / required unknown `xcode.version`, `simulator.runtime` / tracked clean after / 8 pass, 2 unknown
- build --json: not run / compile success no
- up --json: not run / launch success no
- Stopped stage: doctor

### Observation and state
- Initial UI observed: no
- Observed UI: doctor required unknown으로 downstream 실행 전 중단
- After tracked state: clean
- Generated/ignored delta: none
- Untracked delta: none
- Unexpected tracked mutation: none

### Feedback and decision
- 질문, 마찰, 누락된 문서: RN 0.72 + Xcode 26.6 + iOS runtime 26.5 조합의 Tier 2 근거와 다음 행동 안내가 없음
- Maintainer intervention: none
- Alpha blockers: known-good 표본 근거 없음, project-native build 실패, required unknown 2건, mobile build/up/UI 증거 없음, app environment 미준비
- Non-blockers와 수용 근거 또는 issue 링크: 없음
- 수정 사항과 링크: #93
- 재실행 범위 / mobile SHA / project SHA / 결과: 수정 전 재실행 없음
- 알려진 제약: mobile SHA가 바뀌면 두 참여자의 전체 evidence matrix를 새 SHA로 다시 실행
- Participant result: blocked
```

`mobile doctor` 실행 전후 `git status --porcelain=v1 --untracked-files=all --ignored=matching`
snapshot은 byte-for-byte 같았고, tracked-only 상태도 두 시점 모두 clean이었다.
`doctor` exit가 0이어도 required `unknown`은 runbook상 Alpha blocker이므로
`mobile build`와 `mobile up`을 실행하지 않았다. 별도 표본 적격성 재확인도
tracked 파일을 바꾸지 않았지만 project-native build가 실패했으므로 이 project
SHA는 이번 round의 known-good 전제를 충족하지 않는다.

첫 후보를 탈락시킨 뒤, 실제 개발 절차로 정상 실행 가능한 React Native 0.79
iOS 프로젝트를 `maintainer-rn-ios-b`로 다시 선정했다. 임시 `mobile.yml`은
실행 전에 device와 scheme만 선언했으며 secret이나 환경값을 포함하지 않았다.

```text
## Participant evidence — replacement sample

- Alpha round: 2026-08-22-1
- Role: maintainer
- Independent run: yes
- mobile full SHA: 0033d1cef951809cdd6de40604b53b8d47f43a42
- Project alias: maintainer-rn-ios-b
- Project full SHA: d4d784df5c1589175a5baabdcd2a69b1194ab8fb
- Known-good 근거: 2026-08-22 KST project-native setup verify, iOS build, install, launch가 모두 exit 0이고 온보딩 초기 화면을 Simulator에서 직접 확인
- Before tracked state: clean
- Host: macOS 26.6.2 / arm64 / Xcode 26.6 (17F113)
- Simulator: iPhone 17 Pro - iOS 26.5 / runtime 26.5 (23F77)
- Project-owned app environment ready: yes (project setup verify 통과와 local iOS 실행 파일 존재만 확인; 값은 열람하지 않음)
- Expected initial UI: 파란 배경의 앱 온보딩 첫 화면과 캐릭터 이미지

### Command summary
- Known-good eligibility recheck (project-native commands): setup verify exit 0 / build exit 0 / install yes / launch yes / tracked clean after
- doctor --json: exit 1 / status error / `package-manager.version` error / tracked clean after / 10 pass, 1 error
- build --json: not run / compile success no
- up --json: not run / launch success no
- Stopped stage: doctor

### Observation and state
- Project-native initial UI observed: yes
- Observed project-native UI: 파란 온보딩 첫 화면, 캐릭터 이미지, 안내 문구와 SKIP 컨트롤이 표시됨
- mobile up initial UI observed: no
- After tracked state: clean
- Generated/ignored delta: none
- Untracked delta: none (`mobile.yml`은 두 snapshot에 동일하게 존재)
- Unexpected tracked mutation: none

### Feedback and decision
- 질문, 마찰, 누락된 문서: committed lockfile은 npm을 선택하지만 packageManager 선언은 yarn을 선택함
- Maintainer intervention: 표본 준비 단계에서 device와 scheme만 `mobile.yml`에 선언; tracked 파일 편집 없음
- Alpha blockers: doctor `package-manager.version` error, mobile build/up/UI 증거 없음, full-run tracked 안전성 미검증
- Non-blockers와 수용 근거 또는 issue 링크: project-native 초기 화면의 development warning toast는 온보딩 화면 표시를 막지 않아 baseline 확인에 한해 수용
- 수정 사항과 링크: #94
- 재실행 범위 / mobile SHA / project SHA / 결과: #94 해소 뒤 같은 mobile SHA와 새 project SHA로 전체 matrix 재실행
- 알려진 제약: mobile SHA가 바뀌면 두 참여자의 전체 evidence matrix를 새 SHA로 다시 실행
- Participant result: blocked
```

대체 표본의 `mobile doctor` 실행 전후 full status snapshot hash는
`3c242b230bd05d0e342e616ccd1c7653eb97bf2fde66d33eb0acda0588320bff`로
같았고 tracked-only 상태도 두 시점 모두 clean이었다. known-good 기준선의
build·install·launch와 UI 관측은 project-native 실행 증거이며 `mobile up`
성공으로 승격하지 않는다. doctor가 exit 1을 반환했으므로 runbook에 따라
`mobile build`와 `mobile up`은 실행하지 않았다.

### 대체 표본 수정·재실행

#94에서 canonical package manager를 npm 10.9.8로 정하고 committed
`package-lock.json`과 `packageManager` 선언을 정렬했다. 그 다음 같은 후보를
새 project SHA에서 재실행해 doctor 11/11 pass와 build 성공을 확인했다.
다만 project-native 기준선에서 남아 있던 Metro를 재사용한 첫 `up`은 dependency
정렬 중 바뀐 `node_modules`를 Metro가 다시 색인하지 못해 예상 UI 대신
module-resolution RedBox를 표시했다. Metro가 없는 재시도에서는 표본에 표준
`start` script가 없어 Metro가 뜨지 않았는데도 `up`이 exit 0을 반환했고 앱은
초기 UI 전에 종료됐다. 최초 실패는 지우지 않고, Metro bind 실패를 pass로 처리한
도구 결함을 Alpha blocker #95로 분리했다.

표본의 기존 `metro` script를 표준 `start` entrypoint로 노출한 뒤 project-native
setup verify, lint, Jest 103 suites(1029 pass, 2 skip)를 다시 통과했다. 최종 project
SHA에서 Metro가 없는 상태로 전체 matrix를 다시 실행했다.

```text
## Participant evidence — replacement sample revalidation

- Alpha round: 2026-08-22-1
- Role: maintainer
- Independent run: yes
- mobile full SHA: 0033d1cef951809cdd6de40604b53b8d47f43a42
- Project alias: maintainer-rn-ios-b
- Project full SHA: e58a9b4aee58b1d833b41f1b436de458f40fca71
- Known-good 근거: 같은 host와 project SHA에서 setup verify, lint, Jest, iOS build·install·launch·초기 UI를 직접 확인
- Before tracked state: clean
- Host: macOS 26.6.2 / arm64 / Xcode 26.6 (17F113)
- Simulator: iPhone 17 Pro - iOS 26.5 / runtime 26.5 (23F77)
- Project-owned app environment ready: yes (준비 여부만 확인; 값은 열람하지 않음)
- Expected initial UI: 파란 배경의 앱 온보딩 첫 화면과 캐릭터 이미지

### Command summary
- Known-good eligibility recheck: setup verify exit 0 / lint exit 0 / Jest exit 0 / 103 suites, 1029 pass, 2 skip
- doctor --json: exit 0 / status pass / 11 pass, 0 error, 0 unknown / tracked clean after
- build --json: exit 0 / status pass / compile success yes / tracked clean after
- up --json: exit 0 / status pass / Metro listener, build, install, launch pass / tracked clean after
- Stopped stage: none

### Observation and state
- Project-native initial UI observed: yes
- mobile up initial UI observed: yes
- Observed mobile up UI: 파란 온보딩 첫 화면, 캐릭터 이미지, 안내 문구와 SKIP 컨트롤이 표시됨
- After tracked state: clean
- Generated/ignored delta: none
- Untracked delta: none (임시 `mobile.yml`은 두 snapshot에 동일하게 존재)
- Unexpected tracked mutation: none

### Feedback and decision
- 질문, 마찰, 누락된 문서: package manager와 Metro entrypoint를 표준 계약에 맞추는 project 수정이 필요했음
- Maintainer intervention: device·scheme `mobile.yml`, package manager 선언 정렬, 기존 Metro script의 표준 `start` alias 추가
- Alpha blockers: 최초 Metro start 실패·bind timeout을 pass로 처리한 도구 결함 #95
- Non-blockers와 수용 근거 또는 issue 링크: 실제 bundle과 UI가 완료됐지만 launch가 120초 뒤에도 `Metro still bundling`으로 표시한 지연·오판 #96; development warning toast는 예상 UI를 막지 않아 수용
- 수정 사항과 링크: #94 해소, #95·#96 후속 추적
- 재실행 범위 / mobile SHA / project SHA / 결과: 같은 mobile SHA / 위 최종 project SHA / doctor → build → up → 초기 UI 전체 pass
- 알려진 제약: mobile SHA가 바뀌면 두 참여자의 전체 evidence matrix를 새 SHA로 다시 실행
- Participant result: pass
```

최종 실행 전후 full status snapshot hash는
`73dba098b09dd02d0a3fe6cdfffd615c22efb43dcd27d2ea28e0751d79ee1e96`로
같았고 tracked-only 상태도 모든 명령 뒤 clean이었다. screenshot, raw log,
환경값과 앱 데이터는 증거에 포함하지 않았다.

## 초대 개발자 독립 실행 (#87)

참여자는 private source와 위 SHA의 runbook만 사용했다. 후보 worktree의 `HEAD`를
40자 SHA로 확인하고 `swift build`한 뒤에도 후보 tracked 상태가 clean임을
확인했다. 세 실제 프로젝트를 순서대로 점검했지만, #86의 merged evidence와
대조한 결과 A와 B는 maintainer가 사용한 표본과 같은 프로젝트였다. 따라서 A와
B는 "maintainer와 다른 실제 프로젝트" 조건의 수용 증거에서 제외하고 최초 실패
이력으로만 보존한다. C만 초대 개발자의 독립 표본으로 판정한다. 프로젝트 이름과
경로, JSON·로그 원문, 환경값은 기록하지 않는다.

### 제외된 선행 표본

- A / project SHA `571e9e91c90d4d7dfb45a40b2db05b0ab18b94ec`:
  #86의 최초 `maintainer-rn-ios-a`와 같은 표본이다. project-owned
  `setup.sh --verify`는 통과했지만 RN 0.72.4가 matrix 범위 0.73–0.87 밖이라
  `doctor --json`은 exit 0 / status `unknown` / required unknown으로 끝났다.
  build와 up은 실행하지 않았고 tracked 상태와 ignored 15개, untracked 0개는
  실행 전후 동일했다.
- B / project SHA `d4d784df5c1589175a5baabdcd2a69b1194ab8fb`:
  #86의 대체 `maintainer-rn-ios-b`와 같은 표본의 수정 전 SHA다. project-owned
  `setup.sh --verify`는 통과했지만 Yarn 선언과 committed npm lockfile이 충돌해
  `doctor --json`은 exit 1 / status `error`로 끝났다. 다중 scheme 미선택
  warning도 남았고 이후 build 대상을 불명확하게 하므로 Alpha blocker로
  분류했다. build와 up은 실행하지 않았고 tracked 상태와 ignored 25개, 기존
  untracked 13개는 실행 전후 동일했다.

```text
## Participant evidence

- Alpha round: `2026-08-22-1`
- Role: invited developer
- Independent run: yes
- mobile full SHA: `0033d1cef951809cdd6de40604b53b8d47f43a42`
- Project alias (민감한 repo 이름 불필요): invited-rn-ios-c
- Project full SHA: `e17840395a8becbab3e81276adbc511abde38b9d`
- Known-good 근거: 같은 SHA에서 project-owned `setup.sh --verify` PASS
- Before tracked state: clean
- Host: macOS 26.6.2 / arm64 / Xcode 26.6 (17F113)
- Simulator: iPhone 17 Pro / iOS 26.5
- Project-owned app environment ready: yes (값 제외)
- Expected initial UI: branded splash

### Command summary

- `doctor --json`: exit 0 / status `pass` / 9/9 checks pass / tracked clean after
- `build --json`: exit 1 / status `error` / validate·dependencies pass, 이미
  booted device skip 뒤 build stage에서 `no Xcode project to build in ios/` /
  tracked clean after / compile success no
- `up --json`: 미실행 / launch success no
- Stopped stage: build

### Observation and state

- Initial UI observed: no
- Observed UI (짧은 텍스트): 없음
- After tracked state: clean
- Generated/ignored delta: none; 62→62
- Untracked delta: none; 0→0
- Unexpected tracked mutation: none

### Feedback and decision

- 질문, 마찰, 누락된 문서: 질문 없음. root `ios/*.xcworkspace`가 참조하는 nested
  Xcode project는 `doctor`에서 통과하지만 build target 탐색에서는 거부됐다.
- Maintainer intervention: none
- Alpha blockers: build 실패와 `doctor`/build 판정 불일치; fail-fast로 `up`을
  실행하지 않아 launch와 초기 UI 증거 없음
- Non-blockers와 수용 근거 또는 issue 링크: 기존 ignored/untracked artifact는
  수와 상태가 바뀌지 않아 명시적으로 수용
- 수정 사항과 링크: project 편집 없음. 제품 Alpha blocker는
  [#92](https://github.com/minjunkim-dev/mobile-runtime/issues/92)로 추적
- 재실행 범위 / mobile SHA / project SHA / 결과: 위 mobile SHA와 project SHA로
  doctor부터 독립 실행해 build에서 blocked. mobile SHA가 바뀌면 두 참여자의
  전체 evidence matrix를 새 round로 재실행한다.
- 알려진 제약: #86의 최종 `maintainer-rn-ios-b`와 다른 add-to-app 실제
  프로젝트임을 확인했다. #92가 해소되기 전에는 build·up·초기 UI를 증명할 수
  없다.
- Participant result: blocked
```

## 판정과 경계

- 저장소 게이트 Alpha blocker: 없음
- Maintainer 실제 프로젝트 결과: **pass** — 최종 project SHA에서 같은 후보의
  doctor·build·up, 예상 초기 UI, full-run tracked 안전성을 모두 확인
- 두 게이트 중 하나라도 실패하거나 판정 불가였다면 실제 프로젝트 실행의 성공
  근거로 승격하지 않고 Alpha blocker로 남긴다.
- 이 결과는 위 SHA의 Swift package 테스트와 Linux `Core` compile만 증명한다.
  Maintainer 대체 표본의 최종 실행은 별도로 전체 matrix와 초기 UI까지 증명한다.
  #93은 탈락한 첫 표본의 별도 호환성 조사로 남기되 현재 alpha의 blocker에서는
  제외한다. 후속 #93은 2026-08-23 `inconclusive`로 종료했고 Matrix와 doctor의
  `unknown`을 유지했다(ADR-0012). #94는 해소됐고 #95는 당시 내부 alpha 완료를
  막는 별도 native blocker였다. #96은 당시 추적 중인 non-blocker였고 후속
  PR #104로 해결됐다.
- 초대 개발자 실행은 서로 다른 add-to-app 표본 C의 doctor와 tracked 파일
  무변경까지만 증명했다. build는 #92로 실패했고 `up`과 초기 UI 관측은 없으므로
  #87 참여자 결과는 **blocked**다.
- #92와 #95가 남아 있고 두 참여자의 성공 증거가 모두 갖춰지지 않았으므로 내부
  alpha 완료를 선언하지 않는다. #96은 추적 중인 non-blocker다.
- 내부 alpha 완료 판정과 ADR-0008의 3-repository Go/No-Go는 이 기록의 범위가
  아니다.

원본 로그, JSON 전체, screenshot, secret, environment file, application data는
이 기록에 포함하지 않았다.

# Private iOS 내부 alpha runbook

이 문서는 issue #83의 private iOS 내부 alpha를 maintainer와 초대된 React Native iOS 개발자가 같은 기준으로 독립 실행하기 위한 단일 handoff다. 한 alpha round는 **private `mobile` source 접근 + exact `mobile` commit SHA + 이 runbook의 증거 체크리스트**로 고정한다. installer, TestFlight, public package 같은 별도 배포 절차는 만들거나 요구하지 않는다.

## 1. Maintainer가 handoff를 고정한다

아래 값을 먼저 채워 두 참여자에게 동일하게 전달한다.

```text
Alpha round: [식별자 또는 날짜]
mobile SHA: [40자 full commit SHA]
Runbook: docs/internal-alpha-runbook.md @ 위 mobile SHA
필수 참여자: maintainer 1명, 초대된 RN iOS 개발자 1명
```

branch나 tag 이름만 전달하지 않는다. 참여자는 private source에서 전달받은 SHA의 별도 worktree를 만들고 직접 일치 여부를 확인한다. 기존 checkout의 tracked·untracked 파일은 build input에 섞지 않는다.

```sh
MOBILE_SOURCE='<private-mobile-source의 absolute path>'
MOBILE_SHA='<handoff의 40자 SHA>'
MOBILE_WORKTREE_ROOT="$(mktemp -d)"
MOBILE_WORKTREE="$MOBILE_WORKTREE_ROOT/mobile"

git -C "$MOBILE_SOURCE" fetch origin
git -C "$MOBILE_SOURCE" worktree add --detach "$MOBILE_WORKTREE" "$MOBILE_SHA"
cd "$MOBILE_WORKTREE"
test "$(git rev-parse HEAD)" = "$MOBILE_SHA"
test -z "$(git status --porcelain=v1 --untracked-files=all)"
swift build
test -z "$(git status --porcelain=v1 --untracked-files=no)"
MOBILE_BIN="$(pwd)/.build/debug/mobile"
test -x "$MOBILE_BIN"
```

이 worktree는 commit의 tracked source만으로 시작한다. `swift build` 뒤 tracked 상태가 바뀌면 binary를 사용하지 않고 Alpha blocker로 기록한다. 이 alpha를 위해 installer나 다른 배포 수단을 추가하지 않는다.

## 2. 참여자가 실제 프로젝트 기준선을 기록한다

각 참여자는 서로 다른, 자신의 **known-good 실제 React Native iOS 프로젝트**를 사용한다. fixture나 새 샘플 앱으로 바꾸지 않는다. 프로젝트는 같은 host와 같은 project SHA에서 기존 개발 절차로 실행 가능한 상태여야 한다. fresh clone은 필수가 아니다.

프로젝트 소유자가 앱 실행에 필요한 환경값을 직접 준비한다. `mobile`이나 maintainer가 secret을 설치·수집·전달하지 않는다. 값 자체가 아니라 준비 여부만 증거에 기록한다.

```sh
cd <react-native-project>
PROJECT_SHA="$(git rev-parse HEAD)"
git status --porcelain=v1 --untracked-files=no

sw_vers -productVersion
uname -m
xcodebuild -version
xcrun simctl list runtimes
xcrun simctl list devices booted

STATE_BEFORE="$(mktemp)"
git status --porcelain=v1 --untracked-files=all --ignored=matching > "$STATE_BEFORE"
```

첫 `git status` 출력은 비어 있어야 한다. 즉, 실행 전 index와 working tree의 tracked 파일이 clean이어야 한다. ignored 환경 파일이나 기존 generated artifact는 허용하되 값을 열거나 증거에 첨부하지 않는다.

실행 전에 다음도 텍스트로 기록한다.

- project full SHA와 known-good 근거(마지막 정상 실행 시점 또는 확인 방법)
- macOS 버전과 architecture, Xcode 버전, 사용할 Simulator device/runtime
- 프로젝트 소유 앱 환경값 준비 여부(값은 제외)
- `up` 뒤 확인할 예상 초기 화면 한 줄

## 3. 정해진 순서로 독립 실행한다

반드시 아래 순서를 지킨다. 각 단계의 JSON 전체나 complete log 대신 exit code, 최상위 `status`, 오류가 있으면 오류 code와 중단 stage만 요약한다. 이 runbook처럼 exit code를 확보한 실행에서는 exit code `0`만 명령 성공으로 판단한다. JSON만 보존한 consumer에게는 `build`와 `up`의 최상위 `error` 부재가 성공 기준이다. 성공한 JSON의 `status`는 `warning`일 수 있으므로 `status == "pass"`만 요구하지 않는다.

### 3.1 `doctor --json`

```sh
"$MOBILE_BIN" doctor --json
printf 'doctor exit=%s\n' "$?"
git status --porcelain=v1 --untracked-files=no
```

이 runbook에서는 `doctor`가 반환한 모든 `checks[]`를 실행 대상에 필요한 check로 취급한다. exit code가 `0`이 아니거나 어느 check든 `error` 또는 판정할 수 없는 `unknown`이 있거나 tracked mutation이 있으면 여기서 중단하고 Alpha blocker로 기록한다. `doctor`에는 최상위 `error`가 없으므로 그 부재를 성공 기준으로 쓰지 않는다.

### 3.2 `build --json`

`doctor`가 다음 단계 진행 가능할 때만 실행한다.

```sh
"$MOBILE_BIN" build --json
printf 'build exit=%s\n' "$?"
git status --porcelain=v1 --untracked-files=no
```

exit code `0`을 **build 성공 증거**로 따로 기록한다. 이는 compile 증거일 뿐 install, launch, UI 성공이 아니다. non-zero exit나 tracked mutation이 있으면 중단한다.

### 3.3 `up --json` 후 UI 확인

`build`가 성공했을 때만 실행한다.

```sh
"$MOBILE_BIN" up --json
printf 'up exit=%s\n' "$?"
git status --porcelain=v1 --untracked-files=no
```

`up`의 exit code가 `0`이 아니거나 tracked mutation이 있으면 중단한다. 성공 뒤 방금 빌드·설치·실행된 앱에서 미리 적은 예상 초기 화면을 직접 본다. process exit, PID, Simulator launch만으로 UI 성공이라 판정하지 않는다. 관측 결과는 screenshot이 아닌 짧은 텍스트로 기록한다. 예상 UI 미관 이후의 로그인, Firebase 등 프로젝트 고유 동작은 이 round 범위가 아니다.

## 4. 실행 전후 Git 상태를 분류한다

```sh
STATE_AFTER="$(mktemp)"
git status --porcelain=v1 --untracked-files=all --ignored=matching > "$STATE_AFTER"
diff -u "$STATE_BEFORE" "$STATE_AFTER"
git status --porcelain=v1 --untracked-files=no
rm -f "$STATE_BEFORE" "$STATE_AFTER"
```

마지막 `git status` 출력은 비어 있어야 한다. `diff`는 로컬에서만 검토하고 증거에는 아래 분류와 개수만 남긴다.

- `!!`: ignored artifact. 새로 생겼다면 프로젝트가 예상한 generated/ignored 파일인지 확인한다.
- `??`: untracked artifact. generated 파일인지 확인하고, ignore 누락이나 문서 마찰이면 별도로 기록한다.
- 그 밖의 status code: tracked 파일 또는 index mutation. 예상 여부와 무관하게 Alpha blocker다.

파일 내용, raw diff, 환경 파일은 증거에 첨부하지 않는다. generated·ignored 변화와 unexpected tracked mutation을 같은 항목으로 뭉개지 않는다.

## 5. Sanitized 증거 체크리스트

각 참여자는 아래 블록을 복사해 한 번 작성한다. 실패 뒤 재실행해도 최초 실패를 지우지 않고 같은 기록에 추가한다.

```text
## Participant evidence

- Alpha round:
- Role: maintainer | invited developer
- Independent run: yes | no
- mobile full SHA:
- Project alias (민감한 repo 이름 불필요):
- Project full SHA:
- Known-good 근거:
- Before tracked state: clean | not clean
- Host: macOS / architecture / Xcode
- Simulator: device / runtime
- Project-owned app environment ready: yes | no (값 제외)
- Expected initial UI:

### Command summary
- doctor --json: exit / status / error code 또는 required unknown / tracked clean after / 요약
- build --json: exit / status / error code / tracked clean after / compile success yes|no
- up --json: exit / status / failing stage 또는 error code / tracked clean after / launch success yes|no
- Stopped stage: none | doctor | build | up | UI | Git comparison

### Observation and state
- Initial UI observed: yes | no
- Observed UI (짧은 텍스트):
- After tracked state: clean | mutated
- Generated/ignored delta: none | 종류와 개수
- Untracked delta: none | 종류와 개수
- Unexpected tracked mutation: none | sanitized 경로와 개수

### Feedback and decision
- 질문, 마찰, 누락된 문서:
- Maintainer intervention: none | clarification only | command 실행 또는 project 편집
- Alpha blockers:
- Non-blockers와 수용 근거 또는 issue 링크:
- 수정 사항과 링크:
- 재실행 범위 / mobile SHA / project SHA / 결과:
- 알려진 제약:
- Participant result: pass | blocked
```

필수 증거에는 다음을 넣지 않는다.

- secrets, token, credential 또는 실제 환경값
- raw `.env` 등 environment file
- complete logs 또는 JSON 전체
- screenshot
- application data나 초기 UI 이후 사용자 데이터

문제 분석에 추가 자료가 꼭 필요하면 해당 프로젝트 소유자가 별도로 최소 범위를 정하고 sanitize한다. alpha round의 필수 증거 저장소에는 원본을 복사하지 않는다.

## 6. 판정과 maintainer 개입 경계

다음은 **Alpha blocker**다.

- `doctor`가 반환한 check의 `error` 또는 `unknown`, 필수 명령 실패
- build 성공 증거, 초기 UI 시각 관측, 전후 Git 상태 중 하나가 없음
- unexpected tracked mutation, security 또는 data-loss 위험
- 초대된 개발자의 terminal에서 maintainer가 명령을 실행하거나 프로젝트를 편집함
- 두 필수 참여자 중 한 명이라도 runbook만으로 독립 실행하지 못함

영향 없는 warning은 이유를 기록했을 때만 non-blocker다. 미관 문제와 예상 초기 UI 이후의 프로젝트 고유 동작도 필수 흐름에 영향이 없으면 non-blocker다. non-blocker는 issue로 추적하거나 round 기록에서 명시적으로 수용한다.

초대된 개발자는 질문할 수 있고 maintainer는 runbook을 설명할 수 있다. 그러나 maintainer가 대신 명령을 실행하거나 프로젝트를 수정해야 했다면 독립 성공이 아니다. 이를 문서 결함 또는 제품 결함으로 기록하고 수정한 뒤 영향받은 표본을 재실행한다.

## 7. 수정 후 재검증한다

- `mobile` SHA가 그대로면 실패한 표본과 수정 때문에 무효가 된 증거만 재실행한다. 최초 실패와 최종 결과를 함께 남긴다.
- `mobile` SHA가 바뀌면 이전 round 결과를 섞지 않는다. 새 SHA로 두 참여자의 전체 evidence matrix를 다시 실행한다.
- project가 known-good이 아니었다면 project를 고치거나 교체하고 새 project SHA로 그 표본을 다시 실행한다. 이를 `mobile` 결함으로 계산하지 않는다.
- 모든 Alpha blocker가 해소되고 non-blocker가 issue화되거나 명시적으로 수용된 뒤 maintainer가 내부 alpha 완료를 선언한다. 별도 승인 회의나 초대 개발자의 formal sign-off는 필요 없다.

내부 alpha 완료는 private 사용 근거일 뿐이다. [ADR-0008](adr/0008-keep-the-three-repository-gate.md)의 3-repository Go/No-Go를 바꾸거나 3/3 Go, public 전환, 일반적인 React Native 지원을 주장하지 않는다.

# Private Android 내부 alpha runbook

이 문서는 issue #117의 Android 후보를 maintainer 소유의 known-good React Native
Android 프로젝트 한 개에서 반복 검증하기 위한 단일 handoff다. fixture나 다른
개발자의 프로젝트를 필수 표본으로 추가하지 않는다. 이번 후보 준비와 아래의 공개
생성 표본 smoke는 실제 private 프로젝트 alpha(#118)나 일반적인 React Native
Android 지원 판정이 아니다.

## 1. Handoff와 후보를 고정한다

```text
Alpha round: [식별자 또는 날짜]
mobile full SHA: [40자 SHA]
Runbook: docs/private-android-alpha-runbook.md
Participant: maintainer
Project alias: [민감한 저장소명 대신 쓸 별칭]
```

branch나 tag 이름만 전달하지 않는다. 후보 SHA의 clean detached worktree에서
binary와 저장소 게이트를 만든다.

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
swift test
scripts/verify-core-linux.sh
test -z "$(git status --porcelain=v1 --untracked-files=no)"
MOBILE_BIN="$MOBILE_WORKTREE/.build/debug/mobile"
test -x "$MOBILE_BIN"
```

순서는 setup(`swift build`) → repository tests(`swift test`) → Linux Core →
tracked-clean 확인이다. 같은 Swift source의 PR에서 GitHub `macOS Swift tests`와
`Linux Core compile`도 green이어야 실제 프로젝트 실행을 시작한다. build 또는
test 실패, CI 미완료·실패, tracked mutation은 Alpha blocker다. installer나 별도
배포물은 만들지 않는다.

## 2. Maintainer 프로젝트와 검증 조합을 고정한다

maintainer가 자신의 known-good 실제 React Native Android 프로젝트를 선택한다.
프로젝트 고유 절차로 native Android 기준선이 정상임을 먼저 확인하고, 같은 host와
project SHA에서 `mobile`을 실행한다. 환경값과 secret은 프로젝트 소유자가 준비하고
값 자체는 열거나 전달하지 않는다.

```sh
cd <react-native-project>
PROJECT_SHA="$(git rev-parse HEAD)"
test -z "$(git status --porcelain=v1 --untracked-files=no)"

STATE_BEFORE="$(mktemp)"
git status --porcelain=v1 --untracked-files=all --ignored=matching > "$STATE_BEFORE"
shasum -a 256 "$STATE_BEFORE"

sw_vers -productVersion
uname -m
node --version
java -version
./android/gradlew --version
```

실행 전에 아래 tuple을 텍스트로 고정한다. 저장소명, URL, SDK 경로, 환경값은 적지
않는다.

- project와 `mobile`의 40자 full SHA
- React Native, Node, JDK vendor/version, Gradle, Android Gradle Plugin
- compileSdk, targetSdk, minSdk, Build Tools
- 프로젝트가 요구하면 NDK와 CMake version
- 선택한 AVD 별칭, system-image API와 ABI
- known-good 근거와 확인할 예상 초기 UI 한 줄

tuple이나 두 SHA 중 하나가 바뀌면 같은 round 결과로 합치지 않고 처음부터 다시
실행한다. 실행 중 SDK·system image·AVD를 자동 설치하거나 다른 AVD를 임의 선택하지
않는다.

## 3. 명령과 중단 규칙

반드시 `doctor → build → up → 초기 UI → down` 순서로 실행한다. 각 명령의 complete
JSON이나 log 대신 exit code, 최상위 `status`, 실패 code·stage와 짧은 summary만
남긴다. exit `0`과 최상위 `error` 부재를 명령 성공 기준으로 삼되, `doctor`의 모든
실행 대상 check도 별도로 판정한다. 영향 없는 warning은 근거를 기록하면 허용할 수
있지만 required check의 `error` 또는 `unknown`은 허용하지 않는다.

### 3.1 Doctor

```sh
"$MOBILE_BIN" doctor --platform android --json
printf 'doctor exit=%s\n' "$?"
git status --porcelain=v1 --untracked-files=no
```

non-zero exit, required `error`·`unknown`, tuple 불일치, tracked mutation이 있으면
Alpha blocker로 기록하고 build로 진행하지 않는다.

### 3.2 Build

```sh
"$MOBILE_BIN" build --platform android --json
printf 'build exit=%s\n' "$?"
git status --porcelain=v1 --untracked-files=no
```

exit `0`, 최상위 `error` 부재, `validate → dependencies → android.build` 완료를
각각 기록한다. 이는 compile과 APK 검증 증거일 뿐 install·launch·UI 성공이 아니다.
실패나 tracked mutation이 있으면 up으로 진행하지 않는다.

### 3.3 Up과 초기 UI

```sh
"$MOBILE_BIN" up --platform android --json
printf 'up exit=%s\n' "$?"
git status --porcelain=v1 --untracked-files=no
```

exit `0`, 최상위 `error` 부재와
`validate → dependencies → android.build → android.device → android.install → metro
→ android.reverse → android.launch` 결과를 기록한다. 이어 방금 빌드·설치·실행된
앱에서 예상 초기 UI를 직접 본다. PID나 launch 성공만으로 UI를 판정하지 않는다.
관측은 짧은 텍스트로만 남긴다.

### 3.4 Down과 소유 리소스 확인

`up`을 호출했다면 성공 여부와 관계없이 마지막에 실행한다.

```sh
"$MOBILE_BIN" down --platform android --json
printf 'down exit=%s\n' "$?"
git status --porcelain=v1 --untracked-files=no
```

앱, `adb reverse`, `mobile`이 시작한 Metro와 Emulator 각각의 `stopped` 또는 정당한
`skipped` 근거를 기록한다. `mobile`이 소유한 리소스가 남거나, 다른 Emulator·프로세스
종료를 요구하거나, AVD wipe 같은 파괴적 수동 조치가 필요하면 Alpha blocker다.

## 4. 실행 전후 상태를 비교한다

```sh
STATE_AFTER="$(mktemp)"
git status --porcelain=v1 --untracked-files=all --ignored=matching > "$STATE_AFTER"
shasum -a 256 "$STATE_AFTER"
diff -u "$STATE_BEFORE" "$STATE_AFTER"
git status --porcelain=v1 --untracked-files=no
rm -f "$STATE_BEFORE" "$STATE_AFTER"
```

diff는 로컬에서만 확인한다. before/after SHA-256, byte-for-byte 동일 여부, status별
개수만 증거로 남긴다. ignored/generated 변화는 분리해서 설명하고, tracked/index
mutation은 예상 여부와 무관하게 Alpha blocker다. 파일 내용이나 raw diff는 저장하지
않는다.

## 5. Sanitized evidence

```text
## Maintainer Android alpha evidence

- Alpha round:
- Participant: maintainer
- Project alias:
- mobile full SHA:
- Project full SHA:
- Known-good 근거:
- Before tracked state: clean | not clean
- Tuple: RN / Node / JDK vendor+version / Gradle / AGP
- Android SDK: compile / target / min / Build Tools / NDK / CMake
- Emulator: AVD alias / system-image API / ABI
- Expected initial UI:

### Repository gates
- setup swift build: exit / tracked clean after
- swift test: exit / suites / tests / failures
- local Linux Core: exit / result
- remote macOS Swift tests: URL / result
- remote Linux Core compile: URL / result

### Command summary
- doctor: exit / status / required error-or-unknown / tracked clean after / summary
- build: exit / status / failing stage-or-error / tracked clean after / compile success
- up: exit / status / failing stage-or-error / tracked clean after / launch success
- Initial UI: observed yes|no / 짧은 텍스트
- down: exit / status / app·reverse·Metro·Emulator 결과 / owned residue
- Stopped stage: none | repository gate | doctor | build | up | UI | down | state

### State and decision
- Full status SHA-256 before / after:
- Full snapshot byte-for-byte equal: yes | no
- After tracked state: clean | mutated
- Generated/ignored delta: none | 종류와 개수
- Untracked delta: none | 종류와 개수
- Unexpected tracked mutation: none | sanitized 종류와 개수
- Initial failures and fixes:
- Alpha blockers:
- Non-blockers와 근거 또는 issue:
- Maintainer result: pass | blocked
```

필수 증거에는 secrets·token·credential, 환경 파일이나 실제 환경값, 저장소명·URL,
SDK absolute path, complete logs·raw JSON·raw diff, screenshot, 앱 데이터나 초기 UI
이후 사용자 데이터를 넣지 않는다. 실패 뒤 재실행해도 최초 실패와 수정은 지우지
않는다.

## 6. Candidate Emulator smoke

다음은 실제 Android Emulator에서 수행한 최소 제품 smoke다. 공개 CLI가 생성한
React Native 표본이므로 private maintainer 프로젝트 alpha를 대신하지 않는다. 이
문서를 추가하는 후속 documentation commit은 검증 후보에 포함하지 않는다.

- Candidate `mobile` SHA: `27504820f1032e73e1bf6d97da6f1c7e4227b99a`
- Generated sample SHA: `52646124a30dc01f8a0e80a6f8450294120bf4eb`
- Host: macOS `26.6.2`, arm64, Node `24.19.0`, Azul JDK `17.0.19`
- Native tuple: RN `0.81.6`, Gradle `8.14.3`, AGP `8.11.0`, compile/target SDK
  `36`, min SDK `24`, Build Tools `36.0.0`, NDK `27.1.12297006`, CMake
  `3.22.1`
- Emulator: `Pixel_9_API_36_1_Play`, system image API `36.1` (device SDK `36`),
  `arm64-v8a`
- Repository gates at candidate SHA: `swift test` exit `0`, 55 suites / 456 tests /
  0 failures; Linux Core exit `0`

| Step | Result | Sanitized summary |
| --- | --- | --- |
| `doctor --json` | PASS (exit 0) | status pass, 11/11 checks pass |
| `build --json` | PASS (exit 0) | validate, dependencies, android.build pass |
| `up --json` | PASS (exit 0) | 8/8 stages pass; owned Emulator와 Metro 시작 |
| 초기 UI | PASS | `Welcome to React Native`, RN 0.81.6, Hermes 직접 관측 |
| `down --json` | PASS (exit 0) | app, reverse, Metro, owned Emulator stopped |

- Full status snapshot SHA-256 before/after:
  `f763950aad37c162b1aba42d812bed22771ec99ab94bdace482f4a28e9693373`
- Snapshot byte-for-byte equal: yes
- Before/after tracked state: clean
- 실행 후 device, port 8081 listener, Android active-run record: none
- screenshot, complete JSON/log, 환경값, 앱 데이터는 증거에 저장하지 않았다.

최종 pass 전에 발견한 실패도 숨기지 않는다. Gradle model을 materialize하고 variant,
CMake, ABI를 명시해 required unknown을 해소했다. 실제 실행에서 AGP version 탐지,
assemble 후 artifact 확인, Build Tools 36 manifest 형식, Emulator AVD의 CRLF identity,
Emulator 종료 대기 결함을 공통 경로에서 수정하고 회귀 테스트를 남겼다. all-ABI APK의
저장공간 실패는 표본을 실제 Emulator ABI로 좁혀 해소했으며 AVD를 wipe하지 않았다.

## 7. 완료 판정과 경계

required error·unknown, repository/build/up/UI/down 실패, tracked mutation, 소유권이
불명확한 cleanup 또는 security·data-loss 위험이 하나라도 남으면 `blocked`다. warning은
필수 흐름에 영향이 없고 근거가 기록됐을 때만 non-blocker다.

이 runbook과 candidate smoke의 완료는 #117의 후보 준비 근거다. maintainer의 실제
private 프로젝트로 같은 순서를 통과해야 #118을 판정할 수 있다. 그 결과도 내부 사용
근거일 뿐 public 전환이나 전체 React Native Android 조합 지원을 뜻하지 않는다.

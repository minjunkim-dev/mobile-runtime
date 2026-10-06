# Private Android 내부 alpha runbook

이 문서는 Private Phase 4A Android 내부 alpha를 SHA를 고정한 공개 OSS 실제
React Native Android 앱 한 개에서 반복 검증하기 위한 단일 handoff다. 표본 정의는
`CONTEXT.md`의 **내부 alpha**와 **Known-good 표본**을 따른다. fixture나 생성
표본은 필수 표본을 대신하지 않는다. maintainer 소유 프로젝트 검증은 후속
milestone이다. 6절의 결과는 일반적인 React Native Android 지원 판정이 아니다.

## 1. Handoff와 후보를 고정한다

```text
Alpha round: [식별자 또는 날짜]
mobile full SHA: [40자 SHA]
Runbook: docs/private-android-alpha-runbook.md
Participant: maintainer
Sample: [공개 OSS 표본 이름과 저장소 URL]
```

branch나 tag 이름만 전달하지 않는다. 후보 SHA의 clean detached worktree에서
binary와 저장소 게이트를 만든다.

```sh
MOBILE_SOURCE='<mobile source checkout의 absolute path>'
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
tracked-clean 확인이다. 같은 SHA의 GitHub 필수 check `CI`(hygiene, macOS Swift
build and tests, Linux Core compile 포함)도 green이어야 실제 프로젝트 실행을 시작한다. build 또는
test 실패, CI 미완료·실패, tracked mutation은 Alpha blocker다. installer나 별도
배포물은 만들지 않는다.

## 2. 공개 OSS 표본과 검증 조합을 고정한다

maintainer가 공개 OSS 실제 React Native Android 앱 한 개를 고르고 SHA를 고정한다.
`mobile` 없이 프로젝트 고유 절차로 build·install·launch·초기 UI에 도달하는
known-good baseline을 먼저 확인한다. 같은 host와 project SHA에서 `mobile`을
실행한다. 앱 환경값이나 secret이 필요한 표본은 고르지 않는다. 표본 교체는 known-good
baseline 전에만 한다.

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

실행 전에 아래 tuple을 텍스트로 고정한다. 공개 표본의 이름과 저장소 URL은 적는다.
SDK absolute path, 홈 경로, 환경값은 적지 않는다.

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
## 공개 OSS 표본 Android alpha evidence

- Alpha round:
- Participant: maintainer
- 표본: 이름 — 저장소 URL
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
- remote CI (`CI`): URL / result

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

필수 증거에는 secrets·token·credential, 환경 파일이나 실제 환경값,
SDK absolute path·홈 경로, complete logs·raw JSON·raw diff, screenshot, 앱 데이터나 초기 UI
이후 사용자 데이터를 넣지 않는다. 실패 뒤 재실행해도 최초 실패와 수정은 지우지
않는다.

## 6. Phase 4A Android alpha 결과 (2026-10-06)

이 runbook 순서로 공개 OSS 표본에서 수행한 최종 검증 실행이다. 이 결과를 기록하는
후속 documentation commit은 검증 후보에 포함하지 않는다.

- 표본: FreeKiosk — https://github.com/RushB-fr/freekiosk (MIT)
- Project full SHA: `0c89e035dccdaf1a1c840a030eca30e10f23783a`
- `mobile` full SHA: `c6b1d19ccb67827ccfdeef1665f448b095ffc258`
- Known-good baseline: [#126](https://github.com/minjunkim-dev/mobile-runtime/issues/126)
  (`mobile` 없이 native build·install·launch·초기 UI 통과, tracked clean)
- 실행 증거: [#127](https://github.com/minjunkim-dev/mobile-runtime/issues/127)
- Host: macOS `27.0.1` (`26A434`), arm64
- Tuple: RN/RNGP `0.82.0`, Node `22.23.1`, npm `10.9.8`, Homebrew OpenJDK
  `21.0.12.1`(`JAVA_HOME`), Gradle `8.13`, AGP `8.12.0`, Kotlin `2.1.20`
- Android SDK: compile/target `36`, min `24`, Build Tools `36.0.0`, NDK
  `27.1.12297006`, CMake `3.22.1`(버전 미지정, AGP 기본값)
- Emulator: `Pixel_10_API_37_Play`, system image API `37`
  (`google_apis_playstore`), `arm64-v8a`
- `mobile.yml`: 없음. 공개 template 기반 ignored Gradle 로컬 설정(arm64 ABI 제한,
  Hermes 설정)만 있다.
- 예상 초기 UI: `FreeKiosk / Professional Kiosk Application / Start Configuration`

### 6.1 단계별 결과

| Step | Result | Sanitized summary |
| --- | --- | --- |
| Repository gates | PASS | `swift build` exit 0, `swift test` 55 suites / 468 tests / 0 failures, Linux Core exit 0, [원격 `CI`](https://github.com/minjunkim-dev/mobile-runtime/actions/runs/37385154392) success |
| `doctor --json` | PASS (exit 0) | status pass, 10/10 checks pass, required error·unknown 0 |
| `build --json` | PASS (exit 0) | validate, dependencies, android.build pass (53s) |
| `up --json` | PASS (exit 0) | 8/8 stages pass (55s); owned Emulator와 Metro 시작 |
| 초기 UI | PASS | bundle HTTP 200. 앱의 전체화면 안내와 위치 권한 dialog를 해제(거부)한 뒤 `FreeKiosk / Start Configuration` 직접 관측 |
| `down --json` | PASS (exit 0) | app, reverse, Metro, owned Emulator stopped; device 0, 8081 listener 0 |

- Full status snapshot SHA-256 before/after:
  `bd7fc5fa990514618a8a7c88b3d5fc91c3a0b110c8131e6ec3e684763a2b3e07`
- Snapshot byte-for-byte equal: yes
- Before/after tracked state: clean. Generated/ignored delta와 untracked delta: none
- 각 명령 뒤 tracked state: clean
- screenshot, complete JSON/log, 환경값, 앱 데이터는 증거에 저장하지 않았다.

### 6.2 최초 실패와 수정

최종 pass 전의 실패를 지우지 않는다. 각 수정은 merge 뒤 새 `mobile` SHA에서 runbook을
처음부터 다시 실행했다.

| Alpha blocker | 증상 | 수정 |
| --- | --- | --- |
| [#143](https://github.com/minjunkim-dev/mobile-runtime/issues/143) | 4자리 Java 버전 `21.0.12.1`을 해석하지 못해 `android.jdk` error | PR #144: Java 관측 전용 parser |
| [#146](https://github.com/minjunkim-dev/mobile-runtime/issues/146) | RN 0.82의 `debug`·`debugOptimized` 때문에 `android.target` 선택에 `mobile.yml` 필요 | PR #147: `debug` 자동 선택 ([ADR-0015](adr/0015-default-android-debug-variant.md)) |
| [#145](https://github.com/minjunkim-dev/mobile-runtime/issues/145) | CMake 버전 미지정 표본에서 `android.sdk` unknown | PR #148: AGP 기본 CMake Tier 2 표와 `cmake.dir` 예외 ([근거](research/agp-default-cmake.md)) |
| [#149](https://github.com/minjunkim-dev/mobile-runtime/issues/149) | `up`이 `node_modules`를 재설치한 직후 Metro bundle 500, 앱 crash | PR #150: 재설치 뒤 Metro 시작 전에 watchman watch 초기화 |

- #149의 1차 수정(`--reset-cache`)은 3회 중 2회 실패해 폐기했다. 원인은 watchman
  recrawl 중 불완전한 파일 목록이었다. 최종 수정은 build→up 3회 반복에서 3/3 통과했다.
- 실행 준비 중 표본 루트에서 에이전트가 만든 빈 SwiftPM `.build/`를 발견해 삭제했다.
  `mobile`이나 표본의 결함이 아니다.
- baseline의 Kotlin daemon 정지(68분)는 `mobile build` 7회에서 재현되지 않았다.

### 6.3 Non-blocker

- 첫 실행의 위치 권한 dialog와 전체화면 안내는 앱 고유 동작이다.
- Dev LogBox toast는 초기 UI 이후 앱 고유 기능 문제다.
- `dependencies`가 매 `build`·`up`마다 `npm ci`를 실행한다(약 7~60s). 이는
  [#74](https://github.com/minjunkim-dev/mobile-runtime/issues/74)의 lockfile 정렬
  결정에 따른 동작이다. 동작에는 영향이 없으므로 비용으로 수용한다.

### 6.4 이전 후보 smoke (참고)

공개 CLI 생성 표본에서 `mobile` `27504820f1032e73e1bf6d97da6f1c7e4227b99a`로 같은 순서를
통과했다(RN `0.81.6`, Azul JDK `17.0.19`, AGP `8.11.0`, API `36.1`). 생성 표본은 실제
앱 표본을 대신하지 않으므로 완료 판정 근거로 쓰지 않는다.

## 7. 완료 판정과 경계

required error·unknown, repository/build/up/UI/down 실패, tracked mutation, 소유권이
불명확한 cleanup 또는 security·data-loss 위험이 하나라도 남으면 `blocked`다. warning은
필수 흐름에 영향이 없고 근거가 기록됐을 때만 non-blocker다.

6절의 결과로 Private Phase 4A Android 내부 alpha를 완료로 판정한다. 이 판정은 macOS
host, 6절의 검증 조합 하나, 공개 OSS 표본 하나에만 적용한다. 아래 사항은 주장하지
않는다.

- maintainer 소유 프로젝트 검증(후속 milestone)
- 초대 개발자의 독립 검증
- 일반적인 React Native Android 지원이나 지원 범위
- Go 판정, 정식 이름, 외부 배포. ADR-0008의 No-Go와 범위는 바뀌지 않는다. 소스
  공개는 [ADR-0014](adr/0014-open-source-is-not-go.md)의 범위만 따른다.

`mobile` SHA, project SHA, 검증 조합 중 하나가 바뀌면 새 검증 실행이다. 기존 결과를
승계하지 않는다.

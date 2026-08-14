# Dogfooding: mattermost-mobile

`mobile doctor`의 early signal 검증 (#21). 판정이 아니라 자료다 — Go/No-Go #2는 `up`까지 완성된 뒤 별도 이슈에서 내린다.

이 repo를 고른 이유(#5): **선언 파일 삼중 중복** — `.nvmrc` + `.node-version` + `package.json engines`가 모두 Node를 말한다.

## 실행 환경

측정 시점: 2026-08-14.

| 항목 | 값 |
| --- | --- |
| macOS | 26.6.1 (25G76) |
| Xcode | 26.6 (17F113), `xcode-select -p` = `/Applications/Xcode.app/Contents/Developer` |
| iOS runtime | iOS 26.5 (23F77) 1종만 설치 |
| Node | v24.19.0 |
| npm | 11.17.0 |
| yarn | 미설치 — `yarn`은 mise shim이고 버전이 설정돼 있지 않다 |
| pnpm | 11.18.0 |
| Ruby | 4.0.6 (mise) |
| bundler | 4.0.16 |
| CocoaPods | 미설치 — `pod`는 mise shim이고 버전이 붙어 있지 않다 |
| 버전 관리자 | mise 2026.8.3. **nvm·rbenv 모두 미설치** |
| mobile | 0.1.0, `swift build`(debug), 커밋 `319d4e1` |

대상 repo: `mattermost/mattermost-mobile` @ `10207015a5023d844c65885ed134814f6c22294a` (2026-08-13), `git clone --depth 1`, **의존성 미설치 상태**(= `git clone` 직후, North Star 시나리오).

아래 출력에서 clone 절대경로는 `$REPO`로 줄였다. 그 외는 그대로다.

## 실행 절차

```bash
git clone --depth 1 https://github.com/mattermost/mattermost-mobile.git
cd mattermost-mobile
mobile doctor
mobile doctor -v
mobile doctor --json
```

소요 시간: **0.78s/run** (warm, 3회 평균). exit code `1`.

## repo가 선언한 것

| 파일 | 값 |
| --- | --- |
| `.nvmrc` | `24.15.0` |
| `.node-version` | `24.15.0` |
| `package.json` engines | `node: ^22.11.0 \|\| ^24.15.0`, `npm: ^10 \|\| ^11` |
| `package.json` packageManager | 없음 (lockfile은 `package-lock.json`) |
| `package.json` react-native | `0.83.9` (정확한 핀) |
| `.ruby-version` | `3.2.11` |
| `Gemfile.lock` | `cocoapods (1.16.1)` |
| `ios/Podfile` | `platform :ios, podfile_properties['deploymentTarget'] \|\| '16.4'` |
| `project.pbxproj` | `IPHONEOS_DEPLOYMENT_TARGET = 16.0` |
| scheme | `Mattermost`, `MattermostShare`, `NotificationService` (3개) |

## 사람용 출력

```
[?] Xcode
    ? node_modules is absent, so the installed React Native version could not be measured — run `npm install` first, then re-run mobile doctor
[?] iOS Simulator
    ? node_modules is absent, so the installed React Native version could not be measured — run `npm install` first, then re-run mobile doctor
[✗] mobile.yml — 3 schemes — Mattermost, MattermostShare, NotificationService — and nothing declares which one to build
    → Declare the scheme in $REPO/mobile.yml: `ios:` on one line, `  scheme: Mattermost` on the next.
      xcodebuild -list -project $REPO/ios/Mattermost.xcodeproj
[!] Project — React Native 0.83.9 declared, node_modules missing
    → Install the project's dependencies — doctor never installs them for you.
      npm install
[!] Node — Node 24.19.0
    → Switch to the pinned Node version — the team runs on it.
      nvm use
[?] CocoaPods
    ? `pod --version` did not report a version — mise ERROR No version is set for shim: pod
[!] Ruby — Ruby 4.0.6
    → Switch to the pinned Ruby version — the project's gems are built against it.
      rbenv install 3.2.11
```

## `--json` 판정 요약

`status: "error"`, `schemaVersion: 1`, `toolVersion: "0.1.0"`, exit `1`. stdout은 JSON만, note는 stderr로 갔다(별도 파일로 분리해 확인).

| id | status | required / reason |
| --- | --- | --- |
| `xcode.installed` | pass | Xcode 26.6 (17F113) at `/Applications/Xcode.app/Contents/Developer` |
| `xcode.version` | unknown | node_modules 부재로 RN 버전 실측 불가 |
| `simulator.daemon` | pass | CoreSimulator 응답, 1/1 runtime available |
| `simulator.runtime` | unknown | node_modules 부재로 RN 버전 실측 불가 |
| `config.values` | **error** | `ios.scheme`, scheme이 3개라서 |
| `project.detected` | warning | RN 0.83.9 declared, node_modules missing |
| `node.version` | warning | `24.15.0 (.nvmrc)` vs Node 24.19.0 |
| `cocoapods.version` | unknown | `pod --version`이 버전을 못 냄 (mise shim 에러 원문 그대로) |
| `ruby.version` | warning | `Ruby 3.2.11 (.ruby-version)` vs Ruby 4.0.6 |

## Tier 2 보조 실행 (node_modules 스텁)

pristine clone에서는 Tier 2가 전부 `unknown`이라 매트릭스 경로가 한 줄도 실행되지 않는다. 매트릭스 판정을 보려고 **`node_modules/react-native/package.json`만 `{"version":"0.83.9"}`로 만든 뒤** 재실행했다 — 실제 `npm install`이 아니라 스텁이다.

```
· xcode.version [pass] observed: Xcode 26.6 (17F113)
  required: Xcode 16.1 or newer   source: compatibility matrix (react-native 0.83) (tier 2)
· simulator.runtime [pass] observed: iOS 26.5 installed and available
  required: an iOS 15.1 or newer simulator runtime, available
· project.detected [pass] observed: React Native 0.83.9 at mattermost-mobile/
```

전체 exit는 여전히 `1` — `config.values` error가 남기 때문.

## 발견

### 미탐 (치명)

1. **`project.detected`가 스텁 하나로 `pass`가 된다.** 위 보조 실행에서 `node_modules`에는 `react-native/package.json` 한 개뿐이었는데 "dependencies installed"로 통과했다. 깨진·부분 설치가 그대로 pass가 되고, 그 위에 얹힌 Tier 2 판정도 근거를 얻은 것처럼 보인다. → #22
2. **runtime 요구가 프로젝트의 deployment target을 보지 않는다.** 매트릭스는 RN 0.83에 `iOS 15.1 or newer`를 요구하는데, 이 repo의 Podfile은 `16.4`, pbxproj는 `16.0`이다. iOS 15.x runtime만 있는 호스트에서 `simulator.runtime`은 `pass`가 되지만 앱은 설치조차 되지 않는다. 이 호스트는 26.5만 있어 실증되지 않았고, 경로는 데이터로 확정된다. → #23
3. **클론 직후 가장 값어치 있는 두 판정이 비어 있다.** `xcode.version`·`simulator.runtime`이 둘 다 `unknown`이다. 같은 실행의 다른 줄은 `React Native 0.83.9 declared`라고 이미 말하고 있고, 이 repo의 선언은 range가 아니라 정확한 핀이다. 미탐은 아니지만(침묵 대신 `unknown`), North Star(`git clone → mobile up`)의 첫 순간에 doctor가 답을 못 내는 지점이다. → #30
4. **`pod` 부재가 `error`가 아니라 `unknown`이다.** `Gemfile.lock`이 CocoaPods 1.16.1을 잠갔고 이 호스트에는 CocoaPods가 없다 — 빌드가 확실히 실패하는 상태다. shim이 PATH에 있어 `notOnPath`가 아닌 `unreadable`로 떨어지면서 `unknown`이 됐다. `unknown` + reason이라 침묵은 아니지만, 판정 등급이 실제 상태보다 약하다. 다만 reason에 mise 원문(`No version is set for shim: pod`)이 그대로 실려 원인 추적은 즉시 됐다. → #24

### 오탐 (경고)

5. **pristine clone이 `error`로 끝난다.** 호스트도 repo도 멀쩡한데 exit 1이다. 원인은 scheme 3개 + `mobile.yml` 미선언이며 #11/#20에서 의도적으로 정한 동작이다. 다만 검증 대상 3개 repo가 **3/3 전부** 이 경로에 걸렸다 — 판정 등급 재검토 대상. → #28

### 매트릭스 불일치

6. 이 repo 기준으로 **매트릭스 행 자체의 불일치는 없다**. RN 0.83 → Xcode 16.1 이상 요구는 호스트 26.6과 모순되지 않는다. 불일치는 행의 값이 아니라 **행이 담는 축**에 있다 — 프레임워크 최소치만 있고 프로젝트 최소치(deployment target)가 없다(위 2번).

### Remediation 복붙 검증

| 명령 | 결과 |
| --- | --- |
| `xcodebuild -list -project $REPO/ios/Mattermost.xcodeproj` | ✅ 그대로 동작, scheme 3개 출력 |
| `npm install` | ✅ 이 repo의 lockfile은 `package-lock.json` — 맞는 매니저 |
| `nvm use` | ❌ `zsh: command not found: nvm` |
| `rbenv install 3.2.11` | ❌ `zsh: command not found: rbenv` |

`nvm`/`rbenv`가 remediation에 하드코딩돼 있다. 이 호스트는 mise를 쓰고, 두 명령 다 실행되지 않는다. → #27

### 사람용 출력 가독성

- 카테고리 그룹핑과 상태 기호는 의도대로 읽힌다. `[?] Xcode` 한 줄이 `xcode.installed [pass]`와 `xcode.version [unknown]`을 함께 접어 최악 상태만 보여주는 것도 소음 없이 납득된다.
- **기본 출력에 `required`가 없다.** `[!] Node — Node 24.19.0`은 관측값만 있고 무엇과 어긋났는지가 없다. `-v` 없이는 "24.19.0이 왜 문제인지"를 알 수 없다. → #29
- `mobile.yml`을 만든 적 없는 사용자에게 `[✗] mobile.yml` 카테고리는 낯설다. 다만 remediation 첫 줄이 파일 경로와 두 줄짜리 내용을 그대로 적어줘서 막히지는 않는다.

## 후속 이슈

이 티켓에서는 고치지 않는다. 분리된 이슈: #22, #23, #24, #27, #28, #29, #30.

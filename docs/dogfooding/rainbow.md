# Dogfooding: rainbow

`mobile doctor`의 early signal 검증 (#21). 판정이 아니라 자료다 — Go/No-Go #2는 `up`까지 완성된 뒤 별도 이슈에서 내린다.

이 repo를 고른 이유(#5): **선언 파일 다양성 최대** — `mise.toml`, `.xcode-version`, `.node-version`, `.ruby-version`, `.yarnrc.yml`, `packageManager`, `Gemfile.lock`이 한 repo에 모여 있다.

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
| CocoaPods | 미설치 — `pod`도 같은 상태의 shim |
| 버전 관리자 | mise 2026.8.3. **nvm·rbenv 모두 미설치** |
| mobile | 0.1.0, `swift build`(debug), 커밋 `319d4e1` |

대상 repo: `rainbow-me/rainbow` @ `29eade9a97e1dd47a307aeb57772138901987d1f` (2026-08-13), `git clone --depth 1`, **의존성 미설치 상태**.

**호스트 조건 하나를 먼저 밝혀둔다**: rainbow는 `mise.toml`을 커밋해 두는데, 갓 클론한 config는 mise가 신뢰하지 않는다(`mise trust` 미실행). 그래서 이 디렉터리 안에서는 mise shim 전체(`yarn`, `pod`, `python3` …)가 실패한다. 아래 `unknown` 두 건의 원인이며, doctor의 결함이 아니라 실측 대상 호스트의 실제 상태다.

아래 출력에서 clone 절대경로는 `$REPO`로 줄였다. 그 외는 그대로다.

## 실행 절차

```bash
git clone --depth 1 https://github.com/rainbow-me/rainbow.git
cd rainbow
mobile doctor
mobile doctor -v
mobile doctor --json
```

소요 시간: **0.67s/run** (warm, 3회 평균). exit code `1`.

## repo가 선언한 것

| 파일 | 값 |
| --- | --- |
| `.node-version` | `22` (메이저만) |
| `package.json` engines | `node: >=22.0.0` |
| `package.json` packageManager | `yarn@4.13.0` (lockfile은 `yarn.lock`, `.yarnrc.yml` 존재) |
| `package.json` react-native | `0.81.6` (정확한 핀) |
| `.ruby-version` | `3.4.8` (개행 없음) |
| `.xcode-version` | **`26.3`** |
| `mise.toml` | `[tools] maestro = "cli-2.7.0"`, `foundry = "1.7.1"` / `[settings] idiomatic_version_file_enable_tools = ["node", "ruby"]` |
| `Gemfile.lock` | `cocoapods (1.16.2)`, `fastlane (2.232.1)` |
| `ios/Podfile` | `platform :ios, '15.1'` |
| `project.pbxproj` | `IPHONEOS_DEPLOYMENT_TARGET = 15.1`, `17.5` |
| CI | `macos-26-xlarge` runner |
| scheme | 8개 |

## 사람용 출력

```
[?] Xcode
    ? node_modules is absent, so the installed React Native version could not be measured — run `yarn install` first, then re-run mobile doctor
[?] iOS Simulator
    ? node_modules is absent, so the installed React Native version could not be measured — run `yarn install` first, then re-run mobile doctor
[✗] mobile.yml — 8 schemes — ImageNotification, OpenInRainbow, PriceWidgetExtension, Rainbow, Rainbow-LocalRelease, SelectTokenIntent, SelectTokenIntentUI, ShareWithRainbow — and nothing declares which one to build
    → Declare the scheme in $REPO/mobile.yml: `ios:` on one line, `  scheme: ImageNotification` on the next.
      xcodebuild -list -project $REPO/ios/Rainbow.xcodeproj
[!] Project — React Native 0.81.6 declared, node_modules missing
    → Install the project's dependencies — doctor never installs them for you.
      yarn install
[!] Node — Node 24.19.0
    → Switch to the pinned Node version — the team runs on it.
      nvm use
[?] Package manager
    ? `yarn --version` did not report a version — mise ERROR error parsing config file: $REPO/mise.toml
[?] CocoaPods
    ? `pod --version` did not report a version — mise ERROR error parsing config file: $REPO/mise.toml
[!] Ruby — Ruby 4.0.6
    → Switch to the pinned Ruby version — the project's gems are built against it.
      rbenv install 3.4.8
```

## `--json` 판정 요약

`status: "error"`, exit `1`.

| id | status | required / reason |
| --- | --- | --- |
| `xcode.installed` | pass | Xcode 26.6 (17F113) |
| `xcode.version` | unknown | node_modules 부재로 RN 버전 실측 불가 |
| `simulator.daemon` | pass | 1/1 runtime available |
| `simulator.runtime` | unknown | node_modules 부재로 RN 버전 실측 불가 |
| `config.values` | **error** | `ios.scheme`, scheme이 8개라서 |
| `project.detected` | warning | RN 0.81.6 declared, node_modules missing |
| `node.version` | warning | `22 (.node-version)` vs Node 24.19.0 |
| `package-manager.version` | unknown | `yarn 4.13.0` — yarn shim이 버전을 못 냄 |
| `cocoapods.version` | unknown | `CocoaPods 1.16.2 (Gemfile.lock)` — pod shim이 버전을 못 냄 |
| `ruby.version` | warning | `Ruby 3.4.8 (.ruby-version)` vs Ruby 4.0.6 |

## Tier 2 보조 실행 (node_modules 스텁)

`node_modules/react-native/package.json`만 `{"version":"0.81.6"}`로 만들고 재실행 — 실제 `yarn install`이 아니라 스텁이다.

```
· xcode.version [pass] observed: Xcode 26.6 (17F113)
  required: Xcode 16.1 or newer   source: compatibility matrix (react-native 0.81) (tier 2)
· simulator.runtime [pass] observed: iOS 26.5 installed and available
  required: an iOS 15.1 or newer simulator runtime, available
```

## 발견

### 미탐 (치명)

1. **`.xcode-version`을 읽지 않는다.** repo가 Xcode 26.3을 파일로 선언해 놨는데 doctor의 `xcode.version`은 매트릭스만 보고, node_modules가 없으면 `unknown`으로 끝난다. 스텁을 넣어 매트릭스를 태워도 요구값은 `Xcode 16.1 or newer`다 — Xcode 16.1만 깔린 호스트는 `pass`를 받지만 repo 선언(26.3)에는 미달이다. Tier 1 소스가 Xcode 축에서만 비어 있다. → #25
2. **`project.detected`가 스텁 하나로 `pass`가 된다** (mattermost-mobile과 동일). → #22

### 오탐 (경고)

3. **pristine clone이 `error`로 끝난다** — scheme 8개 + `mobile.yml` 미선언. 의도된 동작이지만 3/3 repo가 전부 걸렸다. → #28
4. **remediation의 예시 scheme이 `ImageNotification`이다.** 알파벳 첫 번째를 고르다 보니 앱 확장이 앱보다 먼저 제안된다. 복붙하면 문법은 맞지만 사용자가 원한 앱(`Rainbow`)이 아니다. → #28에 함께 기록.

### 매트릭스 불일치

5. **행 값의 불일치는 없다** — RN 0.81 → Xcode 16.1 이상 / iOS 15.1 이상은 이 repo의 Podfile(`platform :ios, '15.1'`)과 일치한다. 다만 repo가 CI에서 `macos-26-xlarge`를 쓰고 `.xcode-version 26.3`을 선언하는 것과 매트릭스 최소치(16.1) 사이 간극이 크다 — 매트릭스는 "프레임워크가 요구하는 하한"이지 "이 프로젝트가 실제로 쓰는 값"이 아니라는 점이 여기서 가장 크게 드러났다(위 1번, #25).

### `unknown` 두 건에 대한 평가 — 정직한 동작

6. `package-manager.version`과 `cocoapods.version`의 `unknown`은 **doctor가 옳게 행동한 사례**다. mise가 신뢰하지 않는 `mise.toml` 때문에 shim이 실패했고, doctor는 추측하지 않고 `unknown`을 내면서 외부 도구의 에러 원문을 그대로 실었다. 원인(`mise trust` 미실행)을 이 문장 하나로 즉시 특정할 수 있었다. 판단 불가를 침묵하지 않는다는 규칙이 실전에서 값을 했다.
7. 반대로 `.ruby-version`에 개행이 없어도(`3.4.8` EOF) 파싱은 정상이었다.

### Remediation 복붙 검증

| 명령 | 결과 |
| --- | --- |
| `yarn install` | ✅ 매니저 선택이 맞다 — `yarn.lock`/`packageManager`를 보고 골랐다 |
| `xcodebuild -list -project $REPO/ios/Rainbow.xcodeproj` | ✅ 동작 (mattermost-mobile에서 동일 형태 검증) |
| `nvm use` | ❌ `command not found: nvm` |
| `rbenv install 3.4.8` | ❌ `command not found: rbenv` |

이 repo는 `mise.toml`을 커밋해 두고 있다 — 프로젝트가 쓰는 버전 관리자를 doctor가 이미 볼 수 있는 자리에 있는데도 nvm/rbenv를 안내한다. → #27

### 사람용 출력 가독성

- 8개 scheme을 한 줄에 나열하니 줄이 길다. 다만 목록이 곧 답이라 잘라내기도 애매하다.
- Node 줄에 요구값이 없어 `-v` 없이는 `22`와 어긋났다는 사실을 알 수 없다. → #29

## 후속 이슈

이 티켓에서는 고치지 않는다. 분리된 이슈: #22, #25, #27, #28, #29, #30.

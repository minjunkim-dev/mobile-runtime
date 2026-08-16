# Dogfooding: up 라운드 2

라운드 1(#44)이 낸 발견 11건 중 닫힌 것을 고친 뒤, 같은 호스트에서 **같은 커밋의 같은 repo 3개**를 다시 돌린 기록. 라운드 1이 repo별 전체 서사라면 이 문서는 **무엇이 달라졌고 무엇이 그대로인가**의 대조표다.

이번 라운드에는 축이 하나 늘었다. `down`(#58)이 생겼으므로 "up이 남긴 것을 도구가 치울 수 있는가"도 함께 실측한다.

## 실행 환경

측정 시점: 2026-08-16. 호스트는 라운드 1과 같다.

| 항목 | 값 |
| --- | --- |
| macOS | 26.6.1 (25G76) |
| Xcode | 26.6 (17F113) |
| iOS runtime | iOS 26.5 (23F77) 1종만 설치 |
| 시뮬레이터 | `iPhone 17 Pro - iOS 26.5` 1대가 이미 booted |
| Node | v24.19.0 (mise) |
| 버전 관리자 | mise 2026.8.3 |
| mobile | 0.1.0, `swift build`(debug), 커밋 `3ba68d6` |

repo 3개는 라운드 1과 **같은 커밋**을 `git fetch --depth 1 <sha>`로 받아 **의존성 미설치 상태**에서 시작했다.

| repo | 커밋 | 패키지 매니저 |
| --- | --- | --- |
| `mattermost/mattermost-mobile` | `10207015` | npm |
| `rainbow-me/rainbow` | `29eade9a` | yarn 4.13.0 |
| `laurent22/joplin` (`packages/app-mobile`) | `2654b336` | yarn 4.16.0 (workspaces) |

호스트 준비는 라운드 1과 같다(`MISE_RUBY_VERSION=3.3.9`, repo별 `MISE_YARN_VERSION`, `LANG=en_US.UTF-8`). CocoaPods만 방식이 다르다: 라운드 1은 호스트의 1.16.2를 지우고 1.16.1을 깔았지만, 이번에는 `pod`을 `pod _1.16.1_`로 넘기는 래퍼를 PATH 앞에 두었다 — mattermost의 solidarity가 정확히 1.16.1을 요구하고, 호스트 전역 gem 상태는 건드리지 않는 편이 되돌리기 쉽다.

아래 출력에서 clone 절대경로는 `$REPO`로 줄였다.

## 라운드 1 발견 11건의 현재 상태

| | 라운드 1 발견 | 이슈 | 라운드 2 |
| --- | --- | --- | --- |
| **H** | 남의 프로젝트 Metro를 재사용하고 exit 0 (**미탐**) | #45 | **해결.** 같은 상황을 재현했고 exit 1로 멈춘다 — 아래 "#45 재현" |
| **F** | 정상 빌드가 4 MiB 출력 한도로 exit 2 (**오탐/치명**) | #55 | **해결.** mattermost 최초 빌드가 243.2s에 `** BUILD SUCCEEDED **`, exit 0 |
| **D** | 선언된 pod 설치 명령을 무시하고 맨 `pod install` | #48 | **작동.** rainbow에서 선언된 `yarn run install-pods`가 실제로 돌아 295.9s에 Pods를 깔았다 — 다만 그 앞의 gem 설치가 빠져 있다(#59). mattermost·joplin은 repo 자신의 `postinstall`이 pod까지 끝내 이 경로가 타지 않았다 |
| **B** | `dependencies` 실패가 전체 로그를 안 남긴다 | #49 | **재실측 못 함.** 이번 라운드에서 설치가 한 번도 실패하지 않았다 |
| **K** | `build` 실패의 tail 20줄이 거의 언제나 경고 | #51 | **해결.** rainbow의 실패가 화면 첫 줄에 `error: Unable to open base configuration reference file …` |
| **E** | scheme 미선언인데 `metro`를 띄운 **뒤** `build`에서 멈춘다 | #53 | **그대로.** mattermost 1차가 정확히 그 순서로 멈췄고, Metro가 남았다 |
| **J** | scheme 후보를 알파벳 첫 번째로 제안 | #52 | **그대로.** rainbow에서 여전히 `scheme: ImageNotification`(알림 확장)을 권한다 |
| **A** | 도구 stderr의 첫 줄만 실어 조치 문장이 잘린다 | #50 | **그대로.** rainbow의 `mise trust`가 여전히 화면에서 사라진다 |
| **C** | 반쪽 `node_modules`를 "설치됨"으로 본다 (**미탐**) | #46 | **재실측 못 함.** 설치가 실패하지 않아 반쪽 상태가 만들어지지 않았다 |
| **I** | `launch`의 settle 3초가 화면을 재지 않는다 (**미탐**) | #47 | **그대로.** exit 0 시점의 화면이 `Bundling 12%…`였다 — 아래 "settle 재확인" |
| **G** | `--json`의 `status`가 `warning`인데 exit 0 | #54 | **그대로**(문서 티켓). mattermost 관통이 `status: warning` + exit 0 |

## #45 재현 — 라운드 1의 미탐이 있던 자리

라운드 1: mattermost의 Metro가 8081에 떠 있는 상태로 joplin에서 `up`을 돌리자 `metro skipped — already running on 8081`으로 재사용하고 build·install·launch가 모두 pass, **exit 0**. 화면은 mattermost 번들러의 빨간 화면이었다.

라운드 2, 같은 상황을 그대로 만들었다(mattermost `up` 관통 → Metro 살려둔 채 joplin에서 `up`):

```
validate      3 of 9 checks need attention  0.7s
dependencies  installed node_modules  218.0s
device        skipped — iPhone 17 Pro - iOS 26.5 is already booted  0.1s
metro         failed — port 8081 is held by another project's Metro  0.0s

[✗] metro — port 8081 is held by another project's Metro — it is serving $REPO(mattermost)
    → React Native's bundler only listens on 8081, so that one has to stop before this
      project's can start. This says which process it is.
      lsof -nP -iTCP:8081 -sTCP:LISTEN
```

exit **1**. 어느 프로젝트의 Metro인지 `X-React-Native-Project-Root`가 준 경로로 말한다.

**다음 행동을 알 수 있었나 — 예.** 화면이 "남의 것"이라고 말하고, 그 프로젝트 경로와 프로세스를 찾는 명령이 함께 나온다. 라운드 1에서 이 자리는 화면에 아무 말도 없었다.

## `down` 실측 (새 축)

`mobile down`은 #58로 이번 라운드 직전에 들어왔다. 세 경로를 모두 실물에서 확인했다.

| 상황 | 출력 | exit |
| --- | --- | --- |
| 이 프로젝트의 Metro + 설치 기록 있음 | `metro stopped — pid 70947` / `app stopped — com.mattermost.rnbeta on 61DECACB…` | 0 |
| 이 프로젝트의 Metro, 설치 기록 없음 | `metro stopped — pid 70203` / `app skipped — no install record — nothing to stop` | 0 |
| 남의 Metro가 8081을 쥐고 있음 | `metro blocked — port 8081 is held by another project's Metro — it is serving …` + `lsof` 줄 | 0 |
| 아무것도 없음 | `metro skipped — nothing on 8081` / `app skipped …` / `nothing to stop` | 0 |

`down` 뒤에 포트는 비었고(`lsof` 무응답) 시뮬레이터의 앱도 종료됐다(`launchctl list`에 없음). 라운드 1에서 손으로 두 번 죽여야 했던 Metro가 이번에는 한 줄로 정리된다.

실패한 `up`도 그 줄을 스스로 권한다 — mattermost 1차(scheme 미선언으로 build에서 정지) 화면 마지막 줄:

```
The Metro this run started is still on 8081 — `mobile down` stops it.
```

## mattermost-mobile

| 차수 | 결과 | 소요 | exit |
| --- | --- | --- | --- |
| 1차 (clone 직후) | `build`에서 scheme 미선언으로 정지. `dependencies`는 154.4s에 관통 | 157s | 1 |
| 2차 (`mobile.yml`에 `ios.scheme: Mattermost`) | **관통** — build 243.2s, install 5.1s, launch 4.3s | 254s | 0 |
| 3차 (재실행, AC 2) | deps·device·metro 전부 skip, build 증분 | 104s | 0 |
| 4차 (`--json`) | 같은 관통, warm | 16s | 0 |

라운드 1에서 이 repo는 6차까지 갔다(npm preinstall 게이트, 반쪽 node_modules, pod env, scheme, 4 MiB 한도). 이번에는 **2차에서 관통했다.** 남은 정지 한 번은 scheme 미선언 — repo가 선언하지 않은 것을 도구가 물은 것이고, #53이 가리키는 것은 그 물음의 **순서**다(이미 `validate`가 아는데 `metro`를 띄운 뒤 `build`에서 멈춘다).

빌드 중 침묵도 사라졌다. 라운드 1은 348초 동안 `running… Ns` 22줄이 전부였지만, 이번에는 컴파일러가 내는 줄이 그대로 흐른다(#55의 스트리밍).

### `--json` 소비 확인 (AC 3)

```
keys:    command, result, schemaVersion, stages, status, toolVersion
status:  warning        command: up      schemaVersion: 1
stages:  validate pass 802 / dependencies skipped 1 / device skipped 79 / metro skipped 11 /
         build pass 10778 / install pass 644 / launch pass 3403
result:  device{name,udid,runtime}, bundleId=com.mattermost.rnbeta, metro{state:reused},
         appPid=81972, buildLog=…/build.log
error:   없음
```

exit 0. `status: warning`과 exit 0이 갈리는 것은 #54가 문서로 잡아둔 그대로다.

## joplin (`packages/app-mobile`)

| 차수 | 결과 | 소요 | exit |
| --- | --- | --- | --- |
| 1차 (8081을 mattermost가 쥔 상태) | `metro`에서 정지 — **#45 재현** | 219s | 1 |
| 2차 (`down` 뒤, `ios.scheme: Joplin` 선언) | **관통** — build 88.8s, install 0.3s, launch 3.4s | 93s | 0 |
| 3차 (재실행, AC 2) | deps·device·metro skip, build 20.5s | 25s | 0 |

`dependencies`는 워크스페이스 루트에서 옳게 돌았고(라운드 1과 같음), Pods는 repo 자신의 설치 스크립트가 만들었다.

## rainbow

| 차수 | 결과 | 소요 | exit |
| --- | --- | --- | --- |
| 1차 (mise.toml 미신뢰) | `validate`에서 정지 — 라운드 1과 같은 자리, 같은 잘린 문장 | 1s | 1 |
| 2차 (`mise trust` 뒤) | `dependencies`가 **Pods 설치에서 실패** — bundler가 gem을 못 찾는다 | 134s | 1 |
| 3차 (`bundle install`을 손으로 한 뒤) | `dependencies` 관통(Pods 295.9s), `build`에서 scheme 미선언으로 정지 | 298s | 1 |
| 4차 (`ios.scheme: Rainbow` 선언) | `build` 실패 — `debug.xcconfig` 없음 | 13s | 1 |

### 1차 — #50이 그대로다

```
[✗] Package manager — `yarn --version` did not report a version —
    mise ERROR error parsing config file: $REPO/mise.toml → yarn 4.13.0
```

mise가 두 번째 줄에 `mise trust $REPO`를 적어 보내지만 화면에는 첫 줄만 남는다. 라운드 1과 한 글자도 다르지 않다.

### 2차 — 라운드 1에서 관통하던 자리가 막혔다

```
dependencies  failed — installing Pods failed  132.7s
```

라운드 1의 이 자리는 703초에 `installed node_modules and Pods`였다. 그때의 `up`은 맨 `pod install`을 돌렸고 그 경로는 bundler를 타지 않는다. #48 이후 `up`은 repo가 선언한 `yarn run install-pods`(= `bundle exec pod install --repo-update`)를 돌리므로, `Gemfile.lock`의 gem이 없으면 여기서 멈춘다.

화면 10줄은 전부 bundler backtrace 프레임이고, 원인은 로그 **첫 줄**에 있다:

```
Could not find fastlane-2.232.1, activesupport-7.0.8.7, … in locally installed gems (Bundler::GemNotFound)
```

**다음 행동을 알 수 있었나 — 아니오.** remediation이 준 `cd $REPO && yarn run install-pods`를 그대로 붙여 넣어 봤고 **같은 에러로 exit 1**이다. 실제로 필요한 것은 `bundle install`인데 화면 어디에도 없다. → 티켓 **#59**(gem 설치 전제), **#60**(원인 줄 대신 backtrace)

`bundle install`은 26초에 끝났고, 그 뒤 `dependencies`는 295.9초에 관통했다 — 즉 **선언된 pod 설치 자체는 옳게 작동한다.** 빠진 것은 그 앞 단계다.

### 4차 — #51은 해결됐다

라운드 1에서는 화면 20줄이 전부 경고였고 진짜 원인은 로그 2544행에 있었다. 라운드 2의 같은 실패:

```
[✗] build — the build failed — $REPO/ios/Rainbow.xcodeproj:1:1: error: Unable to open base
    configuration reference file '$REPO/ios/debug.xcconfig'.
    (같은 줄 5회 더)
** BUILD FAILED **
    → The whole build log is at …/build.log.
      xcodebuild -workspace $REPO/ios/Rainbow.xcworkspace -scheme Rainbow …
```

**다음 행동을 알 수 있었나 — 예, 한 번에.** 화면 첫 줄이 원인이다. (관측: 같은 `error:` 줄이 타깃 수만큼 6번 반복된다. 중복 제거 여지가 있지만 원인 도달에는 지장이 없어 티켓으로 올리지 않았다.)

rainbow가 clone 직후 빌드되지 않는 것은 라운드 1의 결론 그대로다 — `ios/debug.xcconfig`는 `.gitignore`에 있고 `.env`가 있어야 생성된다. **도구의 결함이 아니라 North Star 사거리에 대한 자료다.** 달라진 것은 그 사실에 도달하는 비용이고, 이번에는 화면 한 줄이었다.

## settle 재확인 (#47)

joplin에서 `down` 직후 `up`을 돌리고(16초, Metro warm) 시뮬레이터 화면을 시간별로 찍었다.

| 시각 | 화면 |
| --- | --- |
| `up`이 exit 0을 낸 순간 | 상태 표시줄에 **`Bundling 12%…`**, 앱 UI 없음 |
| +15s | 노트 목록이 그려져 있다 |
| +30s | 동일 |

라운드 1(90초)보다 짧아진 것은 Metro가 warm하고 joplin 번들이 작기 때문이지 settle이 화면을 재게 됐기 때문이 아니다. **`up`이 성공을 말하는 순간 화면은 아직 번들을 받고 있다** — #47은 그대로 열려 있고, 폴링할 신호(`Bundling N%`)가 화면에 찍혀 있다는 것까지 이번에 확인했다.

관측 하나 더: 앞선 mattermost 실행이 띄운 알림 권한 알럿이 그 뒤로도 화면에 남아 joplin 위에 떠 있었다. `down`은 앱을 종료하지만 앱이 띄운 시스템 알럿은 시뮬레이터에 남는다.

## 세 repo 요약

| repo | 라운드 1 | 라운드 2 | 관통까지 |
| --- | --- | --- | --- |
| mattermost-mobile | 6차에 관통(4 MiB 한도로 한 번 exit 2) | **2차에 관통** — 254s | scheme 선언 1회 |
| joplin | 3차에 관통(2차는 남의 Metro에 붙은 채 exit 0) | **2차에 관통** — 93s | `down` 1회 + scheme 선언 1회 |
| rainbow | 3차까지, 빌드 불가(repo 온보딩) | 4차까지, 빌드 불가(repo 온보딩) | 도달 못 함 |

재실행(AC 2)은 세 repo 모두 라운드 1의 결론을 다시 확인했다: mattermost 254s → 104s, joplin 93s → 25s. `dependencies`·`device`·`metro` 세 줄이 전부 skip이다.

## 발견 (라운드 2)

라운드 1의 축을 그대로 쓴다 — **미탐**(실재 문제를 pass로 통과), **오탐**(멀쩡한데 error).

| | 발견 | 분류 | 자리 |
| --- | --- | --- | --- |
| **L** #59 | 선언된 pod 설치가 bundler를 요구하는데 gem 설치 단계가 없다. 화면이 준 명령을 복붙해도 같은 에러다(ADR-0006 위반) | 순서/메시지 | `DependenciesStage.installPods` |
| **M** #60 | `dependencies` 실패의 tail 10줄이 backtrace 프레임이라 원인 줄이 잘린다. 설치기는 원인을 **먼저** 말한다 | 메시지 | `DependenciesStage.install` — #51의 반대편 |
| **N** #61 | 보고되는 Metro pid가 8081을 쥔 프로세스가 아니라 start 스크립트의 pid다(70899↔70947, 87163↔87206) | 보고 | `MetroStage` / `UpJSONDocument.result.metro` |

라운드 1의 미탐 3건 중 **#45는 닫혔고**, #46·#47은 이번 조건에서 재현되지 않았거나(설치가 실패하지 않음) 그대로 열려 있다(#47은 위에서 다시 관측). 라운드 2에서 새로 나온 미탐은 없다.

## fog 트리거 재확인

라운드 1이 승격시킨 둘의 결과를 실측으로 되짚었다.

- **xcodebuild streaming(#55)** — 승격이 옳았다. 4 MiB로 죽던 mattermost 최초 빌드가 243.2초에 관통했고, 빌드 중 화면에 컴파일러 줄이 흐른다. 라운드 1의 "348초 동안 `running…` 22줄"은 사라졌다.
- **`down`·Metro 수명 관리(#58)** — 승격이 옳았다. 라운드 1에서 손으로 두 번 죽여야 했던 Metro가 이번 라운드에서는 `mobile down` 네 번으로 정리됐고, 실패한 `up`이 그 줄을 스스로 권한다. 남의 Metro를 만났을 때 `down`은 죽이지 않고 `blocked`로 말한다.
- **device boot ∥ build 병렬화** — 이번에도 재판정 조건이 성립하지 않았다. 시뮬레이터가 계속 booted였고 `device`는 0.1초였다.

## 이 라운드가 호스트에 한 일 (재현용)

| 변경 | 되돌리는 법 |
| --- | --- |
| clone 3개를 `~/Workspace/03_Lab/mobile-dogfooding/`에 받음 | 디렉터리 삭제 |
| mise ruby 3.3.9에 `cocoapods 1.16.1` 설치(1.16.2·1.17.0은 그대로 둠) | `gem uninstall cocoapods -v 1.16.1` |
| `pod _1.16.1_`로 넘기는 PATH 래퍼(`<clone 루트>/.bin/pod`) | 디렉터리 삭제. 호스트 PATH에는 넣지 않았다 |
| rainbow clone의 `mise.toml`을 `mise trust` | `mise trust --untrust <clone>` |
| 두 repo clone에 `mobile.yml` 생성(scheme 선언) | clone 삭제와 함께 사라진다 |
| 실행 시 env: `MISE_RUBY_VERSION`·`MISE_YARN_VERSION`·`LANG` | 프로세스 env뿐, 남는 것 없음 |

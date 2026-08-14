# Dogfooding: up 라운드 1

`mobile up`의 관통 실측 (#44). doctor 라운드 1(#21)·라운드 2(`round-2.md`)와 같은 호스트·같은 세 repo·같은 커밋이다 — 비교 가능성을 위해 표본을 바꾸지 않았다. 판정이 아니라 자료다 — Go/No-Go #2는 별도 이슈에서 내린다.

기록의 초점은 성공 여부가 아니라 **어디서 멈췄고 그 메시지로 다음 행동을 알 수 있었는가**다.

## 실행 환경

측정 시점: 2026-08-14 ~ 08-15(자정을 넘겨 이어 돌렸다).

| 항목 | 값 |
| --- | --- |
| macOS | 26.6.1 (25G76) |
| Xcode | 26.6 (17F113) |
| iOS runtime | iOS 26.5 (23F77) 1종만 설치 |
| 시뮬레이터 | `iPhone 17 Pro - iOS 26.5` 1대가 이미 booted 상태 |
| Node | v24.19.0 (mise) |
| npm | 11.17.0 |
| 버전 관리자 | mise 2026.8.3 |
| mobile | 0.1.0, `swift build`(debug), 커밋 `ebebd01` |

대상 repo 3개는 라운드 1·2와 **같은 커밋**을 `git fetch --depth 1 <sha>`로 받아 **의존성 미설치 상태**에서 시작했다.

| repo | 커밋 | 패키지 매니저 |
| --- | --- | --- |
| `mattermost/mattermost-mobile` | `10207015` | npm |
| `rainbow-me/rainbow` | `29eade9a` | yarn 4.13.0 |
| `laurent22/joplin` (`packages/app-mobile`) | `2654b336` | yarn 4.16.0 (workspaces) |

아래 출력에서 clone 절대경로는 `$REPO`로, 다른 repo의 clone을 가리켜야 할 때는 `$REPO(mattermost)`처럼 줄였다. 그 외는 그대로다.

## 이 라운드가 어떻게 굴러갔나

doctor 라운드는 한 번 돌리면 끝이었다. `up`은 아니다 — 멈추면 **그 자리를 사람이 치우고 다시 돌리는** 것이 이 명령의 사용법이고, 그래서 이 문서는 repo마다 "1차에서 멈춤 → 무엇을 했나 → 2차"의 연속으로 적는다. 각 차수 끝에 **그 메시지만 보고 다음 행동을 알 수 있었는가**를 붙였다. 그것이 이 라운드가 재는 것이다.

세 repo는 **직렬로** 돌렸다. 빌드가 CPU를 다 쓰므로 동시에 돌리면 Stage 시간이 서로를 오염시킨다.

## 0차 — 호스트 그대로, 세 repo 전부 `validate`에서 정지

라운드 2 doctor가 남긴 호스트 상태(= `pod`·`ruby`·`yarn`이 mise shim인데 버전 미설정) 그대로 세 repo에서 `mobile up`을 돌렸다. 세 번 다 첫 Stage에서 멈춘다.

| repo | 멈춘 Stage | 소요 | exit | 원인 Check |
| --- | --- | --- | --- | --- |
| mattermost-mobile | `validate` | 1.2s | 1 | `cocoapods.version`, `ruby.version` |
| rainbow | `validate` | 0.9s | 1 | `package-manager.version`, `cocoapods.version`, `ruby.version` |
| joplin | `validate` | 0.8s | 1 | `package-manager.version`, `cocoapods.version` |

```
validate      failed — 2 environment checks failed  1.2s

[✗] CocoaPods — `pod --version` did not report a version — mise ERROR No version is set for shim: pod → CocoaPods 1.16.1 (Gemfile.lock)
    → `pod` is on PATH but reports no version, so it cannot be used. Fix whatever provides it — the line above is what it said — then re-run mobile doctor.
```

**다음 행동을 알 수 있었나 — 예.** 원문(`mise ERROR No version is set for shim: pod`)이 그대로 실려 있어 mise에 버전을 지정하면 된다는 것이 한 줄로 읽힌다. #33이 "틀린 명령을 붙이느니 원문만 싣는다"로 고친 자리가 up에서도 그대로 작동한다.

**단, rainbow에서는 아니다.** rainbow는 `mise.toml`을 커밋해 두는데 이 호스트에서 trust되지 않았다:

```
[✗] Ruby — `ruby --version` did not report a version — mise ERROR error parsing config file: $REPO/mise.toml → Ruby 3.4.8 (.ruby-version)
```

mise가 실제로 stderr에 적어 보낸 것은 **두 줄**이고, 실행 가능한 문장은 두 번째 줄에 있다:

```
mise ERROR error parsing config file: $REPO/mise.toml
mise ERROR Config files in $REPO/mise.toml are not trusted.
Trust them with `mise trust`. See https://mise.jdx.dev/cli/trust.html
```

up(과 doctor)이 싣는 것은 첫 줄뿐이다. 남은 화면은 "파싱 오류"라고만 말하고, 실제 조치인 `mise trust`는 사라진다. → 후속 티켓 **A**(#50)

### 호스트 준비

여기서 멈춘 채 기록을 끝낼 수도 있었지만 AC 2·3·6이 build 이후를 재도록 요구한다. doctor가 준 remediation을 그대로 따라 호스트를 고쳤다 — 그것이 이 도구의 사용법이다.

| 조치 | 이유 |
| --- | --- |
| `MISE_RUBY_VERSION=3.3.9` | mise에 이미 설치돼 있던 ruby. 각 repo가 핀한 3.2.11/3.4.8과 다르므로 doctor는 **warning**으로 낮춰 부르고 진행한다 |
| `gem install cocoapods -v 1.16.1` | 이 호스트의 mise ruby에는 1.16.2가 있었다. mattermost의 preinstall이 정확히 1.16.1을 요구한다(아래 2차) |
| `MISE_YARN_VERSION=4.13.0` / `4.16.0` | rainbow·joplin용. `mise install yarn@…`로 받아 실행 시점 env로만 지정했다 — 호스트 전역 설정은 건드리지 않았다 |

호스트를 고친 뒤 `validate`는 세 repo 모두 통과한다(핀 불일치는 warning으로 남고 파이프라인은 진행).

## mattermost-mobile

### 1차 — `dependencies`, npm이 repo 자신의 preinstall에서 죽는다

```
validate      5 of 9 checks need attention  1.1s
dependencies  failed — installing node_modules failed  57.1s

[✗] dependencies — installing node_modules failed — npm warn deprecated inflight@1.0.6: This module is not supported, and leaks memory. Do not use it. Check out lru-cache if you want a good and tested way to coalesce async requests by a key value, which is much more comprehensive and powerful.
npm warn deprecated glob@7.2.3: Old versions of glob are not supported, and contain widely publicized security vulnerabilities, which have been fixed in the current version. Please update. Support for old versions may be purchased (at exorbitant rates) by contacting i@izs.me
npm warn deprecated rimraf@2.7.1: Rimraf versions prior to v4 are no longer supported
(node:30215) [DEP0190] DeprecationWarning: Passing args to a child process with shell option true can lead to security vulnerabilities, as the arguments are not escaped, only concatenated.
(Use `node --trace-deprecation ...` to show where the warning was created)
npm error code 2
npm error path $REPO
npm error command failed
npm error command sh -c ./scripts/preinstall.sh && npx solidarity
npm error A complete log of this run can be found in: /Users/swifty/.npm/_logs/2026-08-14T14_21_50_209Z-debug-0.log
    → Run the install by hand to see the whole output — an installer that fails usually says why in more lines than fit here.
      npm install
```

exit 1, 58초.

**다음 행동을 알 수 있었나 — 반쯤.** "npm install을 손으로 돌려 보라"는 맞는 안내이고 그대로 하면 원인이 나온다. 하지만 화면에 실린 10줄 중 6줄이 `npm warn deprecated`다. 실패한 명령 이름(`./scripts/preinstall.sh && npx solidarity`)은 살아남았지만 **그 명령이 무엇을 거부했는지**는 한 글자도 없다. 손으로 돌려 보니 이랬다:

```
[23:23:17] 'ruby' binary >=3.2.0 [failed]
[23:23:17] 'pod' binary 1.16.1 [failed]
Solidarity checks failed
```

즉 이 repo는 자기만의 환경 게이트를 갖고 있고, `pod` **1.16.1 정확히**를 요구한다. 위에서 호스트에 1.16.1을 깐 이유다.

`build`는 실패 시 전체 로그를 파일로 쓰고 그 경로를 remediation에 싣는다(`RunLogs`). `dependencies`는 그러지 않는다 — tail 10줄이 전부고, 그 10줄이 경고로 채워지면 남는 것이 없다. → 후속 티켓 **B**(#49)

### 2차 — `dependencies`, 실패한 설치가 남긴 `node_modules`를 "설치됨"으로 본다

1차의 npm이 exit 2로 죽었지만 `node_modules/`는 1.2GB만큼 남았다. 2차는 그것을 보고 node 설치를 건너뛴다:

```
validate      3 of 9 checks need attention  1.0s
dependencies  failed — installing Pods failed  8.8s
```

`[✓] Project — React Native 0.83.9 at $REPO/` — doctor도 같은 이유로 pass다. 실제로는 `postinstall`(`patch-package`)이 한 번도 돌지 않은 반쪽 트리다. 존재만 보는 규칙(#13에서 의도적으로 고른 것)이 **실패한 설치**까지 성공으로 읽는다. → 후속 티켓 **C**(#46)

그리고 Pods 실패의 tail 10줄은 이번에도 원인이 아니었다:

```
[✗] dependencies — installing Pods failed — #  -------------------------------------------
mise node@24.15.0            [1/3] install
mise node@24.15.0            [1/3] download node-v24.15.0-darwin-arm64.tar.gz
mise node@24.15.0            [2/3] checksum node-v24.15.0-darwin-arm64.tar.gz
mise node@24.15.0            [3/3] extract node-v24.15.0-darwin-arm64.tar.gz
mise node@24.15.0            [3/3] node -v
mise node@24.15.0            [3/3] v24.15.0
mise node@24.15.0            [3/3] npm -v
mise node@24.15.0            [3/3] 11.12.1
mise node@24.15.0          ✓ installed
    → Run the install by hand to see the whole output — an installer that fails usually says why in more lines than fit here.
      cd $REPO/ios && pod install
```

`pod install`이 도는 동안 mise가 `.nvmrc`의 node를 자동 설치했고, 그 진행 로그가 tail 창을 밀어냈다. B와 같은 뿌리다.

**다음 행동을 알 수 있었나 — 아니오.** 화면의 10줄 중 실패에 대한 것은 첫 줄의 `#  ----` 하나뿐이다. remediation의 복붙 명령을 손으로 돌리기 전에는 무엇이 잘못됐는지 알 수 없고, 그 복붙 명령마저 아래 3차에서 같은 이유로 실패한다.

### 3차 — `pod install`에 프로젝트가 선언한 env가 빠져 있다

remediation이 시킨 대로 `cd $REPO/ios && pod install`을 손으로 돌리자 원인이 나왔다:

```
[!] Invalid `Podfile` file:
[!] Invalid `react-native-paste-input.podspec` file: [!] react-native-paste-input 2.0.1 requires the React Native New Architecture (Fabric/TurboModules)..
```

이 repo의 `package.json`은 pod 설치 방법을 직접 선언한다:

```json
"pod-install": "cd ios && RCT_NEW_ARCH_ENABLED=1 pod install",
```

up의 `dependencies`는 언제나 맨 `pod install`을 돈다. 프로젝트가 선언한 스크립트를 읽지 않으므로 **이 repo에서는 up이 Pods를 영원히 설치하지 못한다**. remediation이 시키는 복붙 명령(`cd $REPO/ios && pod install`)도 같은 이유로 실패한다 — 사람이 따라 해도 같은 벽에 부딪힌다. → 후속 티켓 **D**(#48)

**다음 행동을 알 수 있었나 — 아니오.** 화면이 준 명령을 그대로 따라도 같은 벽이다. 답은 `package.json`의 `pod-install` 스크립트에 있는데 up도 화면도 그 존재를 말하지 않는다.

`RCT_NEW_ARCH_ENABLED=1 pod install`을 손으로 돌려(4분 남짓) 다음 차수로 갔다.

### 4차 — `metro`를 띄운 뒤에야 scheme 미선언으로 멈춘다

```
validate      3 of 9 checks need attention  1.0s
dependencies  skipped — already installed  0.0s
device        skipped — iPhone 17 Pro - iOS 26.5 is already booted  0.1s
metro         started on 8081 — pid 38872, log at /var/folders/…/T/mobile/mattermost-mobile-bc9bedc7/metro.log  0.0s
build         failed — 3 schemes — Mattermost, MattermostShare, NotificationService — and nothing declares which one to build  0.6s
```

exit 1, 2초.

**다음 행동을 알 수 있었나 — 예.** `mobile.yml`에 무엇을 어떻게 쓰라는지가 문장으로 나오고, 확인용 `xcodebuild -list` 명령까지 붙는다.

관측 두 가지:

1. **같은 문장이 두 번 나온다.** `validate`의 warning(`[!] mobile.yml — 3 schemes …`)과 `build`의 error(`[✗] build — 3 schemes …`)가 글자까지 같다. 등급만 다르다(ADR-0004의 의도된 차이). 읽는 사람에게는 같은 화면에 같은 문장 두 줄이다.
2. **1초에 알 수 있던 사실 때문에 Metro가 남는다.** scheme이 미선언이라는 것은 `validate`의 `config.values`가 이미 알고 있다. 그런데 파이프라인은 `metro`를 spawn한 **다음** `build`에서 그것으로 멈춘다. up에는 `down`이 없으므로 그 Metro는 사용자가 직접 죽여야 한다. → 후속 티켓 **E**(#53), 그리고 fog 트리거 3의 실측 근거

`mobile.yml`에 `ios: scheme: Mattermost`를 적고 다음 차수로 갔다.

### 5차 — `build`가 4 MiB 출력 한도에 걸려 exit 2

```
validate      2 of 10 checks need attention  1.0s
dependencies  skipped — already installed  0.0s
device        skipped — iPhone 17 Pro - iOS 26.5 is already booted  0.1s
metro         skipped — already running on 8081  0.0s
build         running…                15.2s
build         failed — could not run  18.3s

[✗] build — build: failed to run `xcodebuild -workspace $REPO/ios/Mattermost.xcworkspace -scheme Mattermost -configuration Debug -destination platform=iOS Simulator,id=61DECACB-… build`: The process's output exceeded the limit of 4194304 bytes.
    → This step could not run at all — that is the tool or the machine, not the project.
```

exit **2**, 19초.

`ProcessRunner`가 자식 출력을 문자열로 모으며 두는 한도(`outputLimit = 4 * 1024 * 1024`)다. mattermost-mobile의 **최초 빌드**(Pods까지 처음부터 컴파일)는 **18초 만에** 그 한도를 넘긴다. 나중에 `xcodebuild clean` 후 다시 돌렸을 때는 한도 아래로 통과했다 — 즉 이 폭탄은 `git clone → mobile up`의 **바로 그 첫 실행**에서만 터진다. North Star가 겨냥하는 그 실행이다. 프로젝트는 멀쩡하고 빌드는 정상 진행 중이었는데 도구가 자기 버퍼 때문에 죽인다 — 이 라운드에서 가장 무거운 발견이다. → 후속 티켓 **F**(#55)

**다음 행동을 알 수 있었나 — 아니오.** 메시지는 정확하지만(4194304 바이트), 사용자가 할 수 있는 일이 없다. remediation은 "도구나 머신 문제"라고만 말한다. 한도를 낮추거나 우회할 플래그가 없다.

이 상태로는 install·launch·재실행을 잴 수 없으므로, **관측을 계속하기 위해** `outputLimit`만 512 MiB로 올린 조사용 바이너리를 따로 빌드했다(커밋하지 않았다, 저장소 트리는 그대로다). 아래 6차부터는 그 바이너리다. 수정은 F 티켓이 받는다.

### 6차 — 관통

```
validate      2 of 10 checks need attention  0.9s
dependencies  skipped — already installed  0.0s
device        skipped — iPhone 17 Pro - iOS 26.5 is already booted  0.1s
metro         skipped — already running on 8081  0.0s
build         running…                15.3s
build         running…                31.0s
…
build         Mattermost              348.0s
install       com.mattermost.rnbeta   6.8s
launch        com.mattermost.rnbeta — pid 51488  4.6s
```

exit **0**, 총 361초. 시뮬레이터에 Mattermost 로그인 화면(앱 버전 2.43.0, 빌드 799)이 떠 있는 것을 스크린샷으로 확인했다. **North Star가 이 repo에서 한 번 관통했다.**

빌드 348초 동안 화면에 나온 것은 `running… Ns` 22줄이 전부다. 컴파일 중인 파일도, 남은 타깃 수도, 실패 가능성이 있는 경고도 보이지 않는다. → fog 트리거 1의 실측 근거

### 7차 — 재실행 (AC 2)

같은 repo에서 아무것도 바꾸지 않고 두 번 더 돌렸다.

| 차수 | 총 시간 | validate | dependencies | device | metro | build | install | launch | exit |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 6차 (cold build) | 361s | 0.9s | skipped 0.0s | skipped 0.1s | skipped 0.0s | **348.0s** | 6.8s | 4.6s | 0 |
| 7차 | 138s | 1.8s | skipped 0.0s | skipped 0.2s | skipped 0.0s | **131.4s** | 0.7s | 3.5s | 0 |
| 8차 (`--json`) | 18s | 0.9s | skipped 0.0s | skipped 0.1s | skipped 0.0s | **13.4s** | 0.7s | 3.6s | 0 |

- **booted 스킵** — 작동한다. `device`가 0.1~0.2s에 `already booted`로 끝난다.
- **deps 스킵** — 작동한다. 0.0s.
- **Metro 재사용** — 작동한다. 4차에서 spawn된 pid 38872를 이후 모든 차수가 `already running on 8081`로 재사용한다. `--json`의 `result.metro`는 `{"state":"reused"}`뿐 — pid도 로그 경로도 없다(스펙대로: 남의 프로세스는 정리 대상이 아니다).
- **두 번째 실행이 확연히 빠른가** — 예, 2.6배(361s → 138s). 다만 **아무것도 바꾸지 않은 재빌드가 131초**다. 8차에서 13.4초로 떨어진 것을 보면 7차의 131초는 xcodebuild가 아직 다시 할 일이 남아 있었다는 뜻이고(RN의 번들·스크립트 phase), 정말로 안정된 상태의 no-op 빌드는 13초다. up 자신이 더하는 오버헤드는 validate 1s + launch settle 3s ≈ 4초로, 어느 차수에서도 지배적이지 않다.

`build`가 어느 쪽인지(348s인가 13s인가) 사용자가 미리 알 방법은 없다. 화면은 두 경우 모두 `running…`이다.

## `--json` 소비 확인 (AC 3)

세 repo에서 나온 문서 여섯 개(mattermost 2건, joplin 1건, rainbow 3건)를 실제로 `jq`로 파싱했다. **stdout에는 JSON만** 나온다 — 진행 줄과 doctor 렌더링은 전부 stderr로 갔고, `jq -e .`가 여섯 건 모두 통과한다.

envelope 4필드와 비어 있지 않은 `stages`를 여섯 문서에 한 번에 물었다:

```
jq -e 'has("schemaVersion") and has("toolVersion") and has("command")
       and has("status") and has("stages") and ((.stages|length)>0)' *.out
→ 전부 true
```

repo별 키 구성(성공에는 `error`가 없고, 실패에는 `result`가 있을 수도 없을 수도 있다):

| 문서 | `status` | 키 |
| --- | --- | --- |
| mattermost 관통 | `warning` | `command, result, schemaVersion, stages, status, toolVersion` |
| mattermost scheme 실패 | `error` | 위 + `error` |
| joplin 관통 | `warning` | `command, result, schemaVersion, stages, status, toolVersion` |
| rainbow `validate` 실패 | `error` | `command, error, schemaVersion, stages, status, toolVersion` — **`result` 없음** |
| rainbow scheme 실패 | `error` | `command, error, result, …` |
| rainbow build 실패 | `error` | `command, error, result, …` |

rainbow의 `validate` 실패만 `result`가 통째로 없다 — 아무 Stage도 아직 아무것도 확보하지 못했기 때문이고, 스펙대로다("Stage가 무언가를 넣기 전까지는 없다").

### 성공 (exit 0)

```json
{
  "command": "up",
  "schemaVersion": 1,
  "toolVersion": "0.1.0",
  "status": "warning",
  "stages": [
    {"id": "validate",     "status": "pass",    "durationMs": 904,   "detail": "2 of 10 checks need attention"},
    {"id": "dependencies", "status": "skipped", "durationMs": 1,     "detail": "already installed"},
    {"id": "device",       "status": "skipped", "durationMs": 94,    "detail": "iPhone 17 Pro - iOS 26.5 is already booted"},
    {"id": "metro",        "status": "skipped", "durationMs": 13,    "detail": "already running on 8081"},
    {"id": "build",        "status": "pass",    "durationMs": 13386, "detail": "Mattermost"},
    {"id": "install",      "status": "pass",    "durationMs": 720,   "detail": "com.mattermost.rnbeta"},
    {"id": "launch",       "status": "pass",    "durationMs": 3620,  "detail": "com.mattermost.rnbeta — pid 56129"}
  ],
  "result": {
    "device": {"name": "iPhone 17 Pro - iOS 26.5", "udid": "61DECACB-…", "runtime": "26.5"},
    "bundleId": "com.mattermost.rnbeta",
    "metro": {"state": "reused"},
    "appPid": 56129
  }
}
```

- envelope 4필드(`schemaVersion`·`toolVersion`·`command`·`status`)가 doctor와 같은 모양이다.
- `error` 키는 **아예 없다**(null이 아니라 부재). 소비자는 `.error // empty`로 갈라도 되고 `has("error")`로 갈라도 된다.
- `status`가 `"warning"`인데 exit는 `0`이다. Node·Ruby 핀 불일치가 validate의 warning으로 남았기 때문이고, 스펙대로다 — 다만 **CI가 `status == "pass"`를 성공 조건으로 쓰면 관통한 실행을 실패로 읽는다.** 성공 판정은 exit code나 `error` 부재로 해야 한다. 문서에 적을 만한 함정이다. → 후속 티켓 **G**(#54, 문서)

### 도메인 실패 (exit 1)

`mobile.yml`을 잠시 치우고 같은 명령을 돌렸다.

```json
{
  "status": "error",
  "stages": [
    {"id": "validate", "status": "pass", "durationMs": 909},
    {"id": "dependencies", "status": "skipped", "durationMs": 1},
    {"id": "device", "status": "skipped", "durationMs": 97},
    {"id": "metro", "status": "skipped", "durationMs": 9},
    {"id": "build", "status": "failed", "durationMs": 609}
  ],
  "error": {
    "message": "3 schemes — Mattermost, MattermostShare, NotificationService — and nothing declares which one to build",
    "remediation": {
      "summary": "Declare the scheme in mobile.yml: `ios:` on one line, `  scheme: Mattermost` on the next.",
      "command": "xcodebuild -list -project ios/Mattermost.xcodeproj"
    }
  },
  "result": {
    "device": {"name": "iPhone 17 Pro - iOS 26.5", "udid": "61DECACB-…", "runtime": "26.5"},
    "metro": {"state": "reused"}
  }
}
```

- `stages`는 **실패한 Stage에서 끝난다** — 뒤 Stage는 목록에 없다. 어디까지 갔는지가 배열 길이로 읽힌다.
- 실패해도 `result`가 있다. 그때까지 확보된 device·metro가 들어 있고 `bundleId`·`appPid`는 없다. 부분 성공을 부분 문서로 말한다.
- `error.remediation`이 사람용 출력과 같은 문장·같은 명령이다.

### 도구 실패 (exit 2)

mattermost 5차가 exit 2다(사람용 출력으로 관측). `--json`으로 같은 상태를 다시 만들려고 clean 후 재빌드했지만 그때는 출력이 한도 아래로 내려가 통과해 버렸다 — 한도를 넘는 것은 **Pods까지 처음부터 컴파일하는 최초 빌드**뿐이다. 따라서 exit 2의 JSON 문서는 이 라운드에서 실측하지 못했다. 사람용 출력에서 확인된 것은 remediation이 도메인 문장이 아니라 "도구나 머신 문제"라는 고정 문장이라는 점이다(스펙대로).

exit code는 관측된 범위에서 스펙대로 갈린다 — 0(관통), 1(도메인: scheme 미선언·빌드 실패·validate 실패), 2(도구: 출력 한도). `stages`·`result`·`error`도 스펙대로다.

**AC 3의 상태: 0과 1은 JSON 문서로 확인, 2는 사람용 출력으로만 확인.** exit 2를 JSON으로 다시 만들려면 "Pods까지 처음부터 컴파일하는 최초 빌드"를 한 번 더 만들어야 하는데, 그 조건은 clone을 새로 받는 것과 같다. 다음 라운드에서 새 clone의 첫 실행을 `--json`으로 돌리면 공짜로 얻는다. 발견은 위 G 한 건.

## joplin (`packages/app-mobile`)

모노레포. 앵커는 `packages/app-mobile`이고 락파일과 워크스페이스 루트는 `joplin/`이다 — 라운드 1 doctor가 `npm install`을 안내해 #26을 낳았던 자리다.

### 1차 — `dependencies`가 워크스페이스 루트에서 옳게 돌았다

```
validate      3 of 9 checks need attention  0.9s
dependencies  installed node_modules  312.2s
device        skipped — iPhone 17 Pro - iOS 26.5 is already booted  0.1s
metro         skipped — already running on 8081  0.0s
build         failed — 3 schemes — Joplin, Joplin-tvOS, ShareExtension — and nothing declares which one to build  0.9s
```

exit 1, 314초.

- `yarn install`이 **워크스페이스 루트에서** 돌았다(anchor 옆이 아니라). #26이 doctor에서 고친 규칙을 up의 `dependencies`도 같은 앵커 정보로 쓴다.
- `[✓] Package manager — yarn 4.16.0` — 0차에서 error였던 자리가 통과로 바뀌었다.
- Pods는 up이 설치하지 않았다. joplin의 루트 `postinstall`이 install 도중 `pod install`을 직접 돌려서 `Podfile.lock == Pods/Manifest.lock`이 이미 성립했기 때문이다. `dependencies`가 "installed node_modules"만 말한 것은 정확한 보고다.
- 멈춘 곳은 mattermost와 같다 — scheme 미선언.

**다음 행동을 알 수 있었나 — 예.** mattermost와 같은 문장, 같은 명령.

### 2차 — 관통했는데 화면은 남의 앱이다 (치명)

`mobile.yml`에 `scheme: Joplin`을 적고 다시 돌렸다. 이번에는 **출하 바이너리**(4 MiB 한도 그대로)로 돌렸는데, joplin의 빌드 출력은 한도 아래라 그대로 통과한다.

```json
{"status": "warning",
 "stages": [{"id":"validate","status":"pass","durationMs":745},
            {"id":"dependencies","status":"skipped","durationMs":0},
            {"id":"device","status":"skipped","durationMs":79},
            {"id":"metro","status":"skipped","durationMs":8},
            {"id":"build","status":"pass","durationMs":97821},
            {"id":"install","status":"pass","durationMs":329},
            {"id":"launch","status":"pass","durationMs":3622}],
 "result": {"appPid": 65260, "bundleId": "net.cozic.joplin", "metro": {"state":"reused"}, …}}
```

exit **0**, 103초. 그런데 시뮬레이터 화면은 이랬다:

```
Unable to resolve module ./.expo/.virtual-metro-entry from
  $REPO(mattermost)/.:

None of these files exist:
  * .expo/.virtual-metro-entry(.ios.js|.native.js|.js|.ios.jsx|.native.jsx|.jsx|.ios.json|
    .native.json|.json|.ios.ts|.native.ts|.ts|.ios.tsx|.native.tsx|.tsx)
  * .expo/.virtual-metro-entry
```

(빨간 화면 전문. 줄바꿈만 폭에 맞춰 접었다.)

8081을 잡고 있던 것은 **mattermost-mobile의 Metro**였다. `metro` Stage는 `/status`가 `packager-status:running`을 답하면 재사용한다 — 그 Metro가 **어느 프로젝트의 것인지는 묻지 않는다**. joplin 앱이 mattermost의 번들러에 붙어 빨간 화면을 띄웠고, up은 `launch pass`, `exit 0`, `status: warning`으로 끝났다.

**다음 행동을 알 수 있었나 — 물어볼 기회조차 없었다.** up은 성공을 말했다. 화면을 직접 보지 않았다면 이 실행은 관통으로 기록됐을 것이다.

CONTEXT.md가 relaunch를 두는 이유("up이 끝나면 화면에 방금 빌드한 코드가 있다")가 여기서 **디스크에서만 참**이 된다. 도구가 성공을 보고하는데 화면이 틀린 것 — 가장 나쁜 모양이다. → 후속 티켓 **H**(#45) (미탐, 이 라운드에서 가장 치명)

### 3차 — 자기 Metro로 다시

8081의 mattermost Metro를 손으로 죽이고(`kill`; up에는 `down`이 없다) 다시 돌렸다.

```
validate      1 of 10 checks need attention  0.8s
dependencies  skipped — already installed  0.0s
device        skipped — iPhone 17 Pro - iOS 26.5 is already booted  0.1s
metro         started on 8081 — pid 65766, log at /var/folders/…/T/mobile/app-mobile-181f2a61/metro.log  0.0s
build         Joplin                  22.0s
install       net.cozic.joplin        0.6s
launch        net.cozic.joplin — pid 66430  3.6s
```

exit 0, 27초. 화면은 이번엔 joplin이다 — 다만 up이 끝난 시점의 화면은 `Loading from Metro…`였고, 그 뒤 흰 화면으로 약 **90초**를 더 보낸 다음에야 노트 목록이 떴다. Metro의 첫 번들이 4050 모듈을 도는 동안이다(`metro.log`의 `BUNDLE ./index.js ▓▓▓… 84.7% (3728/4050)`).

**다음 행동을 알 수 있었나 — 해당 없음(멈추지 않았다).** 대신 끝난 뒤가 문제였다.

`launch`의 settle 3초는 "앱이 그렸는가"를 재지 않는다 — 벽시계 추측이고, LaunchStage 주석이 스스로 그렇게 적어 두었다. 실측으로 그 추측이 첫 실행에서 30배 어긋난다. **폴링할 신호는 바로 옆에 있다** — 방금 이 Stage가 spawn한 Metro의 로그가 번들 진행률을 퍼센트로 적고 있다. → 후속 티켓 **I**(#47)

### 4차 — 재실행 (AC 2)

| 차수 | 총 시간 | dependencies | metro | build | install | launch | exit |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1차 (clone 직후) | 314s | **312.2s** | skipped(남의 것) | failed 0.9s | — | — | 1 |
| 2차 (cold build) | 103s | skipped 0.0s | skipped(남의 것) | **97.8s** | 0.3s | 3.6s | 0 |
| 3차 (자기 Metro) | 27s | skipped 0.0s | started 0.0s | 22.0s | 0.6s | 3.6s | 0 |
| 4차 | 14s | skipped 0.0s | skipped(자기 것) | 8.4s | 0.4s | 3.4s | 0 |

booted 스킵·deps 스킵·Metro 재사용 모두 작동한다. 4차의 14초 중 4.4초(31%)가 up 자신의 고정비다 — `validate` 1.0s와 `launch`의 settle 3.4s.

## rainbow

### 1차 — mise.toml이 trust되지 않아 `validate`에서 정지

0차와 같은 자리다. 여기서 **잘려 나간 두 번째 줄을 실측으로 확인했다**: `mise trust`를 한 번 실행하자 `package-manager.version`·`cocoapods.version`·`ruby.version` 세 error가 동시에 사라졌다.

```
$ mise trust
mise trusted $REPO
$ yarn --version → 4.13.0    $ ruby --version → 3.3.9    $ pod --version → 1.16.1
```

up이 보여준 문장(`mise ERROR error parsing config file: $REPO/mise.toml`)만 보고는 그 명령에 도달할 수 없다. mise가 이미 답을 적어 보냈고 up이 그 줄을 버렸다. → 티켓 **A**(#50)

### 2차 — `dependencies` 관통, `build`에서 8개 scheme

```json
{"id":"validate","status":"pass","durationMs":791,"detail":"5 of 10 checks need attention"}
{"id":"dependencies","status":"pass","durationMs":700939,"detail":"installed node_modules and Pods"}
{"id":"device","status":"skipped","durationMs":90}
{"id":"metro","status":"pass","durationMs":12,"detail":"started on 8081 — pid 75447, …"}
{"id":"build","status":"failed","durationMs":979,"detail":"8 schemes — … — and nothing declares which one to build"}
```

exit 1, 703초. **`dependencies`가 세 repo 중 유일하게 Pods까지 스스로 설치했다**(node_modules와 Pods 둘 다, 11분 40초). rainbow는 `install-pods` 스크립트로 `bundle exec pod install --repo-update`를 선언하지만, 맨 `pod install`로도 이 repo는 설치된다 — 티켓 D의 실패는 mattermost 고유다.

**다음 행동을 알 수 있었나 — 예, 그런데 따라 하면 틀린 것을 빌드한다.** remediation이 제안하는 이름이 알파벳 첫 번째다:

```
Declare the scheme in mobile.yml: `ios:` on one line, `  scheme: ImageNotification` on the next.
```

`ImageNotification`은 알림 확장이고 앱이 아니다. 8개 중 사람이 원하는 것은 `Rainbow`다. 복붙하면 확장 타깃을 빌드하고, 그 결과는 시뮬레이터에 앱이 없는 성공이다. → 후속 티켓 **J**(#52)

### 3차 — `build` 실패, 그런데 tail 20줄에 원인이 없다

`scheme: Rainbow`를 선언하고 다시 돌렸다. exit 1, 13초.

`error.message`에 실린 20줄은 전부 `IPHONEOS_DEPLOYMENT_TARGET` 경고와 run-script 경고이고, 마지막 세 줄이 `** BUILD FAILED **` / `The following build commands failed:` / `(1 failure)`다. **에러 줄은 한 줄도 없다.** 실제 원인은 로그 파일 2544번째 줄에 있었다:

```
$REPO/ios/Rainbow.xcodeproj:1:1: error: Unable to open base configuration reference file '$REPO/ios/debug.xcconfig'.
```

**다음 행동을 알 수 있었나 — 예, 다만 한 단계 건너서.** 화면만으로는 알 수 없고, remediation이 준 로그 경로를 열어야 안다.

`build`는 `dependencies`와 달리 전체 로그를 파일로 남기고 그 경로를 remediation에 싣는다 — 그래서 `grep error: <경로>` 한 번으로 원인에 도달한다. 설계가 의도한 대로 작동했다. 다만 **화면에 뿌리는 20줄이 xcodebuild에서는 거의 언제나 경고**라는 것이 실측이다. tail 대신 `error:` 줄을 우선 뽑았다면 이 화면이 그대로 답이었다. → 후속 티켓 **K**(#51)

### rainbow는 clone 직후 빌드할 수 없는 repo다

`ios/debug.xcconfig`는 `.gitignore`에 있고, `scripts/postinstall.sh`가 **`.env`가 있을 때만** 생성한다. `.env`는 API 키를 담는 파일이라 repo에 없다. 빈 `.env`를 만들어 postinstall을 직접 돌려 봤지만 이번엔 스크립트 자신이 yarn 4에서 깨진다:

```
Some global NPM packages are required. Installing: patch-package rn-nodeify
Usage Error: The 'yarn global' commands have been removed in 2.x
```

즉 `git clone → mobile up`이 성립하지 않는 repo가 표본 셋 중 하나 있다. up의 결함은 아니다 — **North Star의 사거리에 대한 자료**다. 세 repo 중 관통은 2/3이고, 나머지 하나는 도구가 아니라 repo의 온보딩 조건 때문에 멈춘다.

## 세 repo 요약

| | mattermost-mobile | joplin | rainbow |
| --- | --- | --- | --- |
| 도달한 최종 Stage | `launch` ✅ | `launch` ✅ | `build` ❌ |
| 0차(호스트 그대로) 멈춘 곳 | `validate` | `validate` | `validate` |
| 호스트 준비 후 첫 실행이 멈춘 곳 | `dependencies`(npm preinstall) | `build`(scheme) | `validate`(mise trust) |
| 관통까지 필요한 사람의 개입 | pod 버전 고정, `RCT_NEW_ARCH_ENABLED=1 pod install` 수동, `mobile.yml` scheme, 출력 한도 상향 | `mobile.yml` scheme, 8081의 남의 Metro 종료 | `mise trust`, `mobile.yml` scheme, (그리고 `.env` — 해결 못 함) |
| 최초 관통 시간 | 361s (build 348s) | 103s (build 97.8s) | — |
| 재실행 | 138s → 18s | 27s → 14s | — |

## 발견 (AC 5)

CONTEXT.md의 두 축을 그대로 쓴다 — **미탐**(실재 문제를 pass로 통과, 치명), **오탐**(멀쩡한데 warning/error). 미탐 3건이 먼저다. 도구가 성공을 말하는데 사실이 아닌 것이 가장 비싸다.

`오탐`으로 분류한 F는 등급만 다르다: 축은 오탐(멀쩡한 프로젝트에 error)이 맞지만, 나타나는 방식이 `exit 2`(도구 장애)라 심각도는 경고가 아니라 치명이다. 이슈 제목이 "치명"이라고 부르는 이유다.

| | 발견 | 분류 | 자리 |
| --- | --- | --- | --- |
| **H** #45 | 8081의 Metro가 **다른 프로젝트의 것**이어도 재사용하고 `exit 0`을 보고한다. joplin 앱이 mattermost의 번들러에 붙어 빨간 화면을 띄웠는데 up은 `launch pass`였다 | **미탐** | `MetroStage` — `/status`의 `packager-status:running`만 보고 프로젝트 정체성은 묻지 않는다 |
| **C** #46 | 실패한 `npm install`이 남긴 반쪽 `node_modules`를 "설치됨"으로 보고 건너뛴다. doctor의 `project.detected`도 같은 이유로 pass | **미탐** | `DependenciesStage.installNode` — 존재 여부만 본다 |
| **I** #47 | `launch`의 settle 3초 뒤 `exit 0`인데 화면은 `Loading from Metro…`였고, 노트 목록이 뜰 때까지 90초가 더 걸렸다 | **미탐** | `LaunchStage.settle` — 벽시계 추측. 폴링할 신호(Metro 로그의 번들 진행률)가 바로 옆에 있다 |
| **F** #55 | 정상 빌드가 출력 4 MiB를 넘겨 `exit 2`로 죽는다. mattermost의 **최초** 빌드가 18초 만에 넘긴다 | **오탐** | `ProcessRunner.outputLimit` |
| **D** #48 | 프로젝트가 선언한 pod 설치 명령을 무시하고 맨 `pod install`을 돈다. mattermost는 `RCT_NEW_ARCH_ENABLED=1`이 필요해 up이 영영 설치하지 못한다 | 미지원 | `DependenciesStage.installPods` |
| **A** #50 | 도구 stderr의 **첫 줄만** 실어 실제 조치 문장이 잘린다. rainbow의 `mise trust`가 그 자리에서 사라졌다 | 메시지 | `ToolVersionProbe` 계열(up·doctor 공통) |
| **B** #49 | `dependencies` 실패는 전체 로그를 남기지 않는다. tail 10줄이 `npm warn`·mise 진행 로그로 채워져 원인이 밀려난다 | 메시지 | `DependenciesStage.install` — `build`만 `RunLogs`를 쓴다 |
| **K** #51 | `build` 실패의 tail 20줄이 거의 언제나 경고다. rainbow의 진짜 `error:` 줄은 로그 2544행에 있었다 | 메시지 | `BuildStage` — tail 대신 `error:` 우선 |
| **E** #53 | `validate`가 이미 아는 scheme 미선언 때문에 `metro`를 띄운 **뒤** `build`에서 멈춘다. 남은 Metro는 사용자가 죽여야 하고, 같은 문장이 화면에 두 번 나온다 | 순서 | `IOSUpStages` 순서 + `SchemeSelector` 등급 차 |
| **J** #52 | scheme 후보를 알파벳 첫 번째로 제안한다. rainbow에서는 `ImageNotification`(알림 확장)을 권한다 | 메시지 | `SchemeSelector.Miss.undecided` |
| **G** #54 | `--json`의 `status`가 `warning`인데 exit는 0이다. CI가 `status == "pass"`로 성공을 판정하면 관통을 실패로 읽는다 | 문서 | `UpJSONDocument` 스펙 문서화 |

## fog 승격 판정 (AC 6)

기준은 #13이 계획 시점에 잠가 둔 세 트리거다. 판정 시점에 기준을 바꾸지 않았다.

### 1. 빌드 중 침묵이 실제로 고통이었는가 → xcodebuild streaming: **예, 승격**

- mattermost 최초 빌드 348초 동안 화면에 나온 것은 `running… Ns` 22줄뿐이다. 무엇을 컴파일 중인지, 얼마나 남았는지, 경고가 쌓이는지 알 수 없다.
- 침묵은 불편으로 끝나지 않았다. **F가 그 침묵의 다른 얼굴이다** — 출력을 스트리밍하지 않고 문자열로 모으기 때문에 4 MiB 한도가 존재하고, 그 한도가 최초 빌드를 죽인다. 한도를 올리면 이번엔 39 MiB(40,859,199 바이트, 실측)를 메모리에 쥔다.
- 실패했을 때 화면에 남는 20줄이 경고로 채워지는 것(K)도 같은 뿌리다. 스트리밍이면 `error:` 줄이 나오는 순간 보인다.

ADR-0002(collected output)를 `build`에 한해 다시 여는 근거가 실측으로 셋 모였다.

### 2. device boot ∥ build 병렬화: **아니오, 승격하지 않음**

- 모든 차수에서 `device`는 0.1~0.2초였다(`already booted`). 361초짜리 실행에서 0.05%다.
- 이 호스트에는 시뮬레이터가 이미 부팅돼 있어 **cold boot을 한 번도 재지 못했다**. 따라서 아래는 실측이 아니라 **추정**이다: `simctl bootstatus`가 통상 수십 초라면 348초 빌드와 병렬화해 얻는 것은 10% 안쪽이고, 얻는 대신 "빌드가 아직 없는 기기를 향해 시작된다"는 순서 보장을 잃는다.
- 즉 이 트리거만은 **실측으로 대조하지 못했고**, 그래서 승격하지 않는다 — 승격의 근거가 없는 것이지 반증이 있는 것이 아니다.
- 재판정 조건: 부팅되지 않은 호스트에서 `device`가 빌드 시간의 20%를 넘게 먹는 것이 관측되면 다시 연다.

### 3. `down`·`stop` 동사 + Metro 수명 관리: **예, 승격**

- 이 라운드에서 Metro를 **두 번** 손으로 죽여야 했다. 한 번은 실패한 실행이 남긴 것(mattermost 4차), 한 번은 다른 프로젝트의 것이 8081을 잡고 있어서(joplin 2차).
- 후자는 그냥 불편이 아니라 **H, 즉 성공을 보고하는 거짓말**로 이어졌다. Metro 수명 관리 없이는 이 미탐을 구조적으로 막을 수 없다 — 재사용 판단에 프로젝트 정체성이 들어가야 하고, 정체성을 아는 순간 "누구의 것인지"와 "누가 정리하는지"가 같은 질문이 된다.
- `up`이 exit 0으로 끝나며 남기는 것(Metro·시뮬레이터·앱)의 정리 동사가 없다는 것은 실측 전에도 알던 사실이지만, 이번에 그것이 **오작동의 원인**이 된다는 자료가 나왔다.

승격된 둘은 각각 티켓이 됐다 — 스트리밍 #56, `down`·Metro 수명 #57. 둘 다 결정이 필요한 자리라 `wayfinder:grilling`이다.

## 후속 티켓 (AC 5)

각 발견의 내용은 위 표에 있다. 여기서는 어느 티켓이 되었는지만 적는다.

| 티켓 | 발견 | 라벨 | 제목 |
| --- | --- | --- | --- |
| #45 | H | `미탐` | up 미탐: 8081의 Metro가 다른 프로젝트의 것이어도 재사용하고 exit 0을 보고한다 |
| #46 | C | `미탐` | up 미탐: 실패한 설치가 남긴 부분 node_modules를 '설치됨'으로 보고 건너뛴다 |
| #47 | I | `미탐` | up 미탐: launch의 settle 3초가 '화면이 그려졌다'를 재지 않는다 |
| #55 | F | `오탐` | up 치명: build 출력이 4 MiB 한도를 넘어 최초 빌드가 exit 2로 죽는다 |
| #48 | D | — | up: 프로젝트가 선언한 pod 설치 명령을 무시하고 맨 pod install을 돈다 |
| #49 | B | — | up: dependencies 실패가 전체 로그를 남기지 않아 tail 10줄이 경고로 채워진다 |
| #50 | A | — | up·doctor: 도구 stderr의 첫 줄만 실어 실제 조치 문장이 잘린다 |
| #51 | K | — | up: build 실패의 tail 20줄이 거의 언제나 경고다 — error: 줄을 우선한다 |
| #52 | J | — | up: scheme 후보를 알파벳 첫 번째로 제안해 확장 타깃을 권한다 |
| #53 | E | — | up: validate가 이미 아는 scheme 미선언 때문에 metro를 띄운 뒤 build에서 멈춘다 |
| #54 | G | — | docs: up --json의 status는 warning이어도 exit 0 |
| #56 | — | `wayfinder:grilling` | build 출력 스트리밍 — ADR-0002를 build 한 단계에 한해 다시 연다 |
| #57 | — | `wayfinder:grilling` | down·stop 동사와 Metro 수명 관리 |

미탐 3건에는 `미탐`, 오탐 1건에는 `오탐` 라벨을 트래커에 새로 만들어 붙였다 — 나머지는 정확성 축의 문제가 아니라 메시지·순서·문서다.

doctor 라운드 1이 8건, 라운드 2가 3건을 낳았다. up 라운드 1은 11건 + fog 승격 2건이다.

**미탐 3건이 이 라운드의 값이다.** 셋 다 "도구가 성공을 말하는데 사실이 아니다"의 다른 얼굴이고, 셋 다 관통에 성공한 실행에서만 보인다 — 멈추는 것만 보던 doctor 라운드에서는 나올 수 없던 종류다.

## 이 라운드가 호스트에 한 일 (재현용)

측정을 위해 검증 호스트에 남긴 변경이다. 다음 라운드가 같은 자리에서 시작하도록 적어 둔다.

| 변경 | 되돌리는 법 |
| --- | --- |
| mise ruby 3.3.9에 `cocoapods 1.16.1` 설치, 기존 `1.16.2` 제거 | `gem install cocoapods -v 1.16.2 && gem uninstall cocoapods -v 1.16.1` |
| `mise install yarn@4.13.0 yarn@4.16.0` | `mise uninstall yarn@4.13.0 yarn@4.16.0` |
| rainbow clone의 `mise.toml`을 `mise trust` | `mise trust --untrust <clone>` |
| 실행 시 env: `MISE_RUBY_VERSION`·`MISE_YARN_VERSION`·`LANG=en_US.UTF-8` | 프로세스 env뿐, 남는 것 없음 |
| mise가 `.nvmrc`를 보고 자동 설치한 node 24.15.0 | `mise uninstall node@24.15.0` |

호스트 전역 mise 설정(`~/.config/mise/config.toml`)은 건드리지 않았다. `outputLimit`을 올린 조사용 바이너리는 저장소에 커밋하지 않았다.

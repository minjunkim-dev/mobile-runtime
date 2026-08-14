# Dogfooding 라운드 2: 세 repo 재실행

라운드 1(#21)이 낸 발견 8건을 고친 뒤 같은 호스트·같은 커밋의 같은 repo 3개에 다시 돌린 기록. 라운드 1이 repo별 전체 기록이라면 이 문서는 **무엇이 달라졌나**의 비교표다. 판정이 아니라 자료다 — Go/No-Go #2는 `up`까지 완성된 뒤 별도 이슈에서 내린다.

## 실행 환경

측정 시점: 2026-08-14. 호스트는 라운드 1과 같다.

| 항목 | 값 |
| --- | --- |
| macOS | 26.6.1 (25G76) |
| Xcode | 26.6 (17F113), `xcode-select -p` = `/Applications/Xcode.app/Contents/Developer` |
| iOS runtime | iOS 26.5 (23F77) 1종만 설치 |
| Node | v24.19.0 |
| 버전 관리자 | mise 2026.8.3. **nvm·rbenv 모두 미설치** |
| `pod`·`ruby`·`yarn` | mise shim, 버전 미설정 (라운드 1과 동일) |
| mobile | 0.1.0, `swift build`(debug), 커밋 `4e91b37` |

대상 repo 3개 모두 라운드 1과 **같은 커밋**을 `git fetch --depth 1 <sha>`로 받아 **의존성 미설치 상태**에서 실행했다.

| repo | 커밋 |
| --- | --- |
| `mattermost/mattermost-mobile` | `10207015` |
| `rainbow-me/rainbow` | `29eade9a` |
| `laurent22/joplin` (`packages/app-mobile`) | `2654b336` |

소요 시간: **0.79s/run** (mattermost-mobile, warm, 3회 평균). 라운드 1은 0.78s — 근거 파일이 늘었지만 측정 가능한 차이는 없다.

아래 출력에서 clone 절대경로는 `$REPO`로 줄였다.

## 라운드 1 발견 8건의 현재 상태

| # | 라운드 1 발견 | 이슈 | 라운드 2 |
| --- | --- | --- | --- |
| 1 | `project.detected`가 스텁 하나로 "dependencies installed" pass | #22 | **해결.** `required`가 "a React Native project with an ios/ directory"로 좁아졌다 |
| 2 | runtime 요구가 deployment target을 안 본다 | #23 | **해결.** mattermost-mobile이 `iOS 16.4 or newer`를 요구한다 |
| 3 | 클론 직후 Tier 2가 전부 `unknown` | #30 | **해결.** 3/3 repo가 락파일에서 RN 버전을 해석했다 |
| 4 | `pod` 부재가 `error`가 아니라 `unknown` | #24 | **해결.** 3/3 `error`. joplin은 `Gemfile`만으로 판정이 생겼다 |
| 5 | 멀쩡한 repo가 scheme 때문에 exit 1 | #28 | **해결.** scheme은 `warning`이다. exit 1은 남았지만 원인이 다르다(아래 참조) |
| 6 | 매트릭스 행 자체의 불일치는 없음 | — | 그대로. 축이 부족했던 것이고 #23·#25로 메웠다 |
| 7 | Remediation이 nvm·rbenv 하드코딩 | #27 | **해결.** 이 호스트에서 전부 `mise use …`로 나온다 |
| 8 | 기본 출력에 `required`가 없다 | #29 | **해결.** warning/error 줄이 `observed → required`를 싣는다 |

여기에 라운드 1 이후 파생된 #25(`.xcode-version`)·#26(워크스페이스 루트)·#31·#32(등급 규칙 확대)까지 반영돼 있다.

## Tier 2 — 근거 체인이 실제로 어떻게 풀렸나

`git clone` 직후, `node_modules` 없이. 라운드 1에서는 이 네 줄이 전부 `unknown`이었다.

| repo | `xcode.version` | `simulator.runtime` |
| --- | --- | --- |
| mattermost-mobile | `Xcode 16.1 or newer` — 매트릭스 (react-native 0.83.9 **from package-lock.json**) | `iOS 16.4 or newer` — **`ios/Podfile.properties.json`**, 매트릭스는 15.1 |
| rainbow | `Xcode 26.3 or newer` — **`.xcode-version`**, 매트릭스는 16.1 | `iOS 15.1 or newer` — `ios/Podfile`, 매트릭스도 15.1 |
| joplin | `Xcode 16.1 or newer` — 매트릭스 (react-native 0.81.6 **from yarn.lock**) | `iOS 15.1 or newer` — `ios/Podfile`, 매트릭스도 15.1 |

네 가지 근거가 전부 실물에서 한 번씩 이겼다: npm 락, yarn berry 락, `.xcode-version`, `Podfile.properties.json`. joplin의 `yarn.lock`에는 react-native 항목이 둘(0.81.6 / 0.70.6)인데 앵커의 descriptor로 맞는 쪽을 집었다.

`-v` source 문자열 예시:

```
· simulator.runtime [pass] An iOS runtime this project can run on is installed and available
  required: an iOS 16.4 or newer simulator runtime, available
  source:   ios/Podfile.properties.json — the compatibility matrix (react-native 0.83.9 from package-lock.json) says 15.1 (tier 1)
```

## 사람용 출력 (mattermost-mobile)

```
[✓] Xcode — Xcode 26.6 (17F113) at /Applications/Xcode.app/Contents/Developer via xcode-select
[✓] iOS Simulator — CoreSimulator responded — 1 of 1 runtimes available
[!] mobile.yml — 3 schemes — Mattermost, MattermostShare, NotificationService — and nothing declares which one to build → ios.scheme, because this project has more than one scheme
    → Declare the scheme in $REPO/mobile.yml: `ios:` on one line, `  scheme: Mattermost` on the next.
      xcodebuild -list -project $REPO/ios/Mattermost.xcodeproj
[!] Project — React Native 0.83.9, node_modules missing → the project's dependencies installed
    → Install the project's dependencies — doctor never installs them for you. `package-lock.json` is what picks it.
      npm install
[!] Node — Node 24.19.0 → 24.15.0 (.nvmrc)
    → Switch to the pinned Node version — the team runs on it.
      mise use node@24.15.0
[✗] CocoaPods — `pod --version` did not report a version — mise ERROR No version is set for shim: pod → CocoaPods 1.16.1 (Gemfile.lock)
    → Install the gems the project declares — pod install runs out of them.
      bundle install
[✗] Ruby — `ruby --version` did not report a version → Ruby 3.2.11 (.ruby-version)
    → Install the pinned Ruby, then re-run mobile doctor.
      mise use ruby@3.2.11
      https://www.ruby-lang.org/
```

joplin은 워크스페이스 루트가 앵커와 달라 install 안내가 `cd $REPO && yarn install`로 나오고, remediation이 `yarn.lock` **at the workspace root**를 근거로 댄다. 라운드 1에서 `npm install`을 안내하던 자리다.

## 판정 요약

| id | mattermost-mobile | rainbow | joplin |
| --- | --- | --- | --- |
| `xcode.installed` | pass | pass | pass |
| `xcode.version` | pass | pass | pass |
| `simulator.daemon` | pass | pass | pass |
| `simulator.runtime` | pass | pass | pass |
| `config.values` | warning | warning | warning |
| `project.detected` | warning | warning | warning |
| `node.version` | warning | warning | warning |
| `package-manager.version` | (선언 없음) | **error** | **error** |
| `cocoapods.version` | **error** | **error** | **error** |
| `ruby.version` | **error** | **error** | (`.ruby-version` 없음) |

exit code는 3/3 모두 `1`. 라운드 1과 같은 숫자지만 **원인이 바뀌었다**: 라운드 1의 exit 1은 scheme 미선언(고를 수 있었던 선택)이었고, 라운드 2의 exit 1은 `ruby`·`pod`·`yarn`이 이 호스트에서 실제로 실행 불가라는 사실이다. 즉 지금 이 머신에서 세 repo 중 어느 것도 빌드할 수 없고, doctor가 그렇게 말한다.

이 호스트를 고쳐 확인하지는 않았다 — 호스트 파손 상태 자체가 라운드 1이 발견한 등급 문제의 재료였으므로 그대로 두었다.

## 라운드 2에서 새로 보이는 것

### 1. mise 설정 오류가 3개 Check에 같은 문장으로 복제된다 (rainbow)

rainbow는 `mise.toml`을 커밋해 두는데 이 호스트에서 trust되지 않아 mise가 거부한다. 세 Check가 같은 원인을 각자 보고한다:

```
[✗] Package manager — `yarn --version` did not report a version — mise ERROR error parsing config file: $REPO/mise.toml → yarn 4.13.0
[✗] CocoaPods   — `pod --version` did not report a version — mise ERROR error parsing config file: $REPO/mise.toml → CocoaPods 1.16.2 (Gemfile.lock)
[✗] Ruby        — `ruby --version` did not report a version — mise ERROR error parsing config file: $REPO/mise.toml → Ruby 3.4.8 (.ruby-version)
```

원인 하나에 error 세 줄이고, **셋 다 remediation이 원인과 어긋난다** — 실제 해법은 `mise trust`인데 화면은 `corepack enable` / `bundle install` / `mise use ruby@3.4.8`을 권한다. 도구 원문을 그대로 실은 덕에 사람은 한 줄 만에 원인을 알지만, 복붙 가능한 명령은 그 원인을 가리키지 않는다. #27이 "실행되는 명령"을 보장했다면 여기서 남은 것은 "**맞는** 명령"이다.

라운드 1에서도 같은 mise 원문이 실렸지만 그때는 `unknown` 한 줄이라 이 중복이 드러나지 않았다. 등급이 올라가면서 보이게 된 문제다.

### 2. `[✓] Xcode` 한 줄이 Tier 2 판정을 접어버린다

`xcode.installed`(host)와 `xcode.version`(tier 2)이 한 카테고리라 둘 다 pass면 헤드라인은 `xcode.installed`의 observed만 보인다. 이번에 가장 값어치 있게 바뀐 판정(`Xcode 26.3 or newer` — rainbow의 `.xcode-version`이 매트릭스를 이긴 것)이 기본 출력에는 한 글자도 안 나온다. 라운드 1의 "카테고리 접기는 납득된다"는 관찰은 **최악 상태만 보이면 된다**는 전제였는데, pass끼리 접힐 때는 더 흥미로운 쪽이 사라진다.

### 3. remediation의 절대경로가 길다

`Declare the scheme in $REPO/mobile.yml:` 줄이 실제로는 120자가 넘는 절대경로를 싣는다. 라운드 1에도 있던 성질이지만, #29로 헤드라인이 길어지면서 화면당 줄바꿈이 늘었다.

### 4. Remediation 복붙 검증

| 명령 | 결과 |
| --- | --- |
| `mise use node@24.15.0` | ✅ `mise`는 PATH에 있고 `use`는 유효한 서브커맨드 — 상태를 바꾸므로 실행하지는 않았다 |
| `bundle install` | ✅ `bundle`은 PATH에 있다(mise shim) |
| `corepack enable` | ✅ PATH에 있다. 다만 rainbow에서는 원인이 corepack이 아니다(위 1번) |
| `xcodebuild -list -project $REPO/ios/Mattermost.xcodeproj` | ✅ 라운드 1과 동일하게 동작 |
| `cd $REPO && yarn install` | ✅ joplin의 워크스페이스 루트를 정확히 가리킨다 |

라운드 1에서 실패했던 `nvm use`·`rbenv install`은 이 호스트에서 더 이상 생성되지 않는다.

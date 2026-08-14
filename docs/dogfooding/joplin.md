# Dogfooding: joplin

`mobile doctor`의 early signal 검증 (#21). 판정이 아니라 자료다 — Go/No-Go #2는 `up`까지 완성된 뒤 별도 이슈에서 내린다.

이 repo를 고른 이유(#5): **yarn workspaces 모노레포** — RN 앱은 `packages/app-mobile`에 있고, 앵커 탐색이 서브패키지를 찾아내는지 검증한다.

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

대상 repo: `laurent22/joplin` @ `2654b33620775080d1d59c552259d41e33dad3d2` (2026-08-10), `git clone --depth 1`, **의존성 미설치 상태**.

아래 출력에서 clone 절대경로는 `$REPO`로 줄였다. 그 외는 그대로다.

## 실행 절차

```bash
git clone --depth 1 https://github.com/laurent22/joplin.git
cd joplin && mobile doctor                      # 워크스페이스 루트
cd packages/app-mobile && mobile doctor         # RN 앵커
mobile doctor -v
mobile doctor --json
```

소요 시간: 루트 **0.15s/run**, `packages/app-mobile` **0.67s/run** (warm, 3회 평균).

## repo가 선언한 것

| 위치 | 파일 | 값 |
| --- | --- | --- |
| 루트 | `package.json` | `workspaces: ["packages/*"]`, `packageManager: yarn@4.16.0`, `engines: { node: ">=22.12", yarn: "4.12.0" }` |
| 루트 | `yarn.lock` | 존재 (**락파일은 루트에만**) |
| `packages/app-mobile` | `package.json` | `engines: { node: ">=20" }`, `react-native: 0.81.6`, `packageManager` 없음 |
| `packages/app-mobile` | `.node-version` | `22` |
| `packages/app-mobile` | `Gemfile` | `gem 'cocoapods', '>= 1.13', '!= 1.15.0', '!= 1.15.1'` — **`Gemfile.lock`은 커밋되지 않음** |
| `packages/app-mobile` | `ios/Podfile` | `platform :ios, podfile_properties['ios.deploymentTarget'] \|\| '15.1'` |
| `packages/app-mobile` | `project.pbxproj` | `IPHONEOS_DEPLOYMENT_TARGET = 15.6`, `18.6` |
| CI | workflows | `macos-15-intel` runner |
| scheme | | `Joplin`, `Joplin-tvOS`, `ShareExtension` (3개) |

## 사람용 출력 — 워크스페이스 루트

```
note: no project detected — host checks only
[✓] Xcode — Xcode 26.6 (17F113) at /Applications/Xcode.app/Contents/Developer via xcode-select
[✓] iOS Simulator — CoreSimulator responded — 1 of 1 runtimes available

No issues found.
```

exit `0`. `--json`으로 다시 돌렸을 때 stdout에는 JSON만(888 bytes), note는 stderr(47 bytes)로 나갔다 — 파이프 규약은 지켜진다.

## 사람용 출력 — `packages/app-mobile`

```
[?] Xcode
    ? node_modules is absent, so the installed React Native version could not be measured — run `npm install` first, then re-run mobile doctor
[?] iOS Simulator
    ? node_modules is absent, so the installed React Native version could not be measured — run `npm install` first, then re-run mobile doctor
[✗] mobile.yml — 3 schemes — Joplin, Joplin-tvOS, ShareExtension — and nothing declares which one to build
    → Declare the scheme in $REPO/packages/app-mobile/mobile.yml: `ios:` on one line, `  scheme: Joplin` on the next.
      xcodebuild -list -project $REPO/packages/app-mobile/ios/Joplin.xcodeproj
[!] Project — React Native 0.81.6 declared, node_modules missing
    → Install the project's dependencies — doctor never installs them for you.
      npm install
[!] Node — Node 24.19.0
    → Switch to the pinned Node version — the team runs on it.
      nvm use
```

exit `1`. 검사 항목은 7개뿐이다 — `package-manager.version`, `cocoapods.version`, `ruby.version`이 **한 줄도 나오지 않았다**.

| id | status | required / reason |
| --- | --- | --- |
| `xcode.installed` | pass | Xcode 26.6 (17F113) |
| `xcode.version` | unknown | node_modules 부재로 RN 버전 실측 불가 |
| `simulator.daemon` | pass | 1/1 runtime available |
| `simulator.runtime` | unknown | node_modules 부재로 RN 버전 실측 불가 |
| `config.values` | **error** | `ios.scheme`, scheme이 3개라서 |
| `project.detected` | warning | RN 0.81.6 declared, node_modules missing |
| `node.version` | warning | `22 (.node-version)` vs Node 24.19.0 |

## Tier 2 보조 실행 (node_modules 스텁)

`node_modules/react-native/package.json`만 `{"version":"0.81.6"}`로 만들고 재실행 — 실제 설치가 아니라 스텁이다.

```
· xcode.version [pass] required: Xcode 16.1 or newer   source: compatibility matrix (react-native 0.81) (tier 2)
· simulator.runtime [pass] required: an iOS 15.1 or newer simulator runtime, available
· project.detected [pass] observed: React Native 0.81.6 at app-mobile/
```

## 발견

### 앵커 탐색 — 의도대로 동작

1. `packages/app-mobile`에서 실행하면 그 서브패키지를 앵커로 잡는다(`React Native 0.81.6 at app-mobile/`). 모노레포 서브패키지 탐색은 검증됐다.
2. 루트에서 실행하면 `no project detected — host checks only` + exit 0. 상향 탐색만 하는 현재 설계의 논리적 귀결이고 error가 아닌 note라는 점도 스펙대로다. 다만 클론 직후 루트에서 한 번 돌려보는 것이 가장 자연스러운 첫 동작이라는 점은 기록해 둔다. → #26

### 미탐 (치명)

3. **`npm install`을 안내한다.** 이 repo는 yarn workspaces이고 `yarn.lock`은 루트에만 있다. `packages/app-mobile`에서 `npm install`을 그대로 복붙하면 워크스페이스가 깨진다. 앵커 옆만 보고 매니저를 고른 결과다(rainbow에서는 같은 로직이 `yarn install`로 맞게 나왔다 — 단일 repo였기 때문). → #26
4. **패키지 매니저 Check가 통째로 사라진다.** 루트가 `packageManager: yarn@4.16.0`을 선언했는데 앵커에는 그 필드가 없어서 Check 자체가 실행되지 않았다. 이 호스트에는 yarn이 없다 — 실재하는 문제인데 `unknown`조차 나오지 않는다. rainbow에서는 같은 상황이 `[?] Package manager`로 드러났다. **모노레포에서만 침묵한다.** → #26
5. **CocoaPods Check가 사라진다.** `Gemfile`은 CocoaPods를 요구하는데 `Gemfile.lock`이 커밋돼 있지 않아 Check가 조건 미달로 빠졌다. 이 호스트에는 CocoaPods가 없으므로 `pod install`은 확실히 실패한다. 침묵은 "판단 불가는 `unknown`으로 명시한다"는 규칙과 어긋난다. → #24
6. **runtime 요구가 프로젝트 deployment target을 보지 않는다** — 매트릭스는 15.1을 요구하지만 pbxproj는 15.6/18.6이다. → #23
7. **`project.detected`가 스텁 하나로 `pass`가 된다** — 3개 repo 공통. → #22

### 오탐 (경고)

8. **pristine clone이 `error`로 끝난다** — scheme 3개 + `mobile.yml` 미선언. 3/3 repo 공통. → #28

### 매트릭스 불일치

9. 행 값의 불일치는 없다. RN 0.81 → Xcode 16.1 / iOS 15.1은 이 repo의 Podfile 기본값(15.1)과 일치한다. 불일치는 pbxproj의 실제 deployment target(15.6/18.6)과 매트릭스 최소치 사이에 있다(위 6번).

### Node 등급 구분 — 의도대로 동작

10. 앵커의 `engines: node >=20`은 만족(24.19.0), `.node-version: 22` 핀은 불일치 → `warning`. "핀은 팀 관례라 warning, engines는 계약이라 error"라는 구분이 실제 repo에서 그대로 작동했다. 다만 루트의 더 엄격한 `engines: node >=22.12`는 읽히지 않았다(만족하는 값이라 결과는 같았지만, 근거는 우연이다). → #26

### Remediation 복붙 검증

| 명령 | 결과 |
| --- | --- |
| `npm install` | ❌ **틀린 매니저** — yarn workspaces를 깬다 (실행하지 않았다) |
| `xcodebuild -list -project $REPO/packages/app-mobile/ios/Joplin.xcodeproj` | ✅ 동작 |
| `nvm use` | ❌ `command not found: nvm` |

### 사람용 출력 가독성

- 검사 7줄은 짧고 읽힌다. 문제는 **없는 줄**이다 — 패키지 매니저·CocoaPods가 조용히 빠져서, 출력만 봐서는 "검사했고 괜찮다"인지 "아예 안 봤다"인지 구분되지 않는다.
- Node 줄에 요구값이 없다. → #29

## 후속 이슈

이 티켓에서는 고치지 않는다. 분리된 이슈: #22, #23, #24, #26, #28, #29, #30.

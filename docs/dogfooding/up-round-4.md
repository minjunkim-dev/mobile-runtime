# Dogfooding: up 라운드 4 — iOS Go 전 조사 실행

[Map #152](https://github.com/minjunkim-dev/mobile-runtime/issues/152)의 repo별 조사 실행 기록이다. ADR-0012의 조사 실행이며 Go round 성공으로 합산하지 않는다. 판정 기준은 ADR-0016이다. 첫 화면 렌더링만 앱 UI 도달로 본다.

## 공통 실행 환경

| 항목 | 값 |
| --- | --- |
| macOS | 27.0.1 (26A434) |
| Xcode | 27.0 (27A266a). 설치된 Xcode는 이것 하나다 |
| iOS runtime | iOS 27.0 (24A434) 1종 |
| 시뮬레이터 | `iPhone 18 Pro - iOS 27.0`이 이미 booted |
| mise | 2026.10.1. 사용자 shell은 `mise activate zsh`를 쓴다 |
| 자동 설치 방지 | 모든 `mobile` 명령에 `MISE_AUTO_INSTALL=false` |

host 도구는 [#153](https://github.com/minjunkim-dev/mobile-runtime/issues/153)에서 준비했다. repo별로 더 준비한 항목은 각 절에 적는다.

## mattermost-mobile

- 날짜: 2026-10-06
- 이슈: [#155](https://github.com/minjunkim-dev/mobile-runtime/issues/155)
- `mobile`: `main` `723b6aaea5766366ab02cb04f57565d3b638b8dc`, `swift build`(debug)
- repo: `mattermost/mattermost-mobile` `10207015a5023d844c65885ed134814f6c22294a`. 새 디렉터리에 `git fetch --depth 1` 후 checkout했다.
- 검증 조합: RN 0.83.9 / Xcode 27.0 / iOS 27.0 runtime. 패키지 매니저는 npm(`package-lock.json`)이다. repo는 Xcode를 선언하지 않는다. matrix 하한은 Xcode 16.1이다.
- 검증 결과: **`inconclusive`**. 첫 화면에 도달하지 못했다. `mobile` 없이 실행한 xcodebuild도 같은 error로 실패한다. 이 검증 조합에서 표본은 known-good이 아니므로 결과를 `mobile`에 귀속할 수 없다.
- Go blocker: 없음.

### 사람의 준비

| 항목 | 내용 | 시점 | 근거 |
| --- | --- | --- | --- |
| untracked `mobile.yml` | `ios.scheme: Mattermost` | 실행 전 | #153 3절 |
| CocoaPods 1.16.1 | Ruby 3.2.11에 `gem install cocoapods -v 1.16.1` | 실행 2 뒤 | repo 선언 도구(`Gemfile.lock`, `.solidarity`) |
| Android SDK | SDK가 있는 외장 SSD를 연결했다. `ANDROID_HOME`과 `emulator`가 살아났다 | 실행 5 뒤 | repo 선언 도구(`.solidarity`의 Android 항목) |
| `mise trust`·앱 환경값 | 필요 없음 | — | #153 3절 |
| `overrides.xcode` | 쓰지 않음. 다른 Xcode가 설치되어 있지 않다 | — | — |

CocoaPods와 Android SDK는 #153 3절에 없던 항목이다. 둘 다 repo가 선언한 도구이므로 ADR-0016의 사람 준비 범위에 든다.

### 단계별 결과

| # | 명령 | 조건 | 결과 | 원인 분류 |
| --- | --- | --- | --- | --- |
| 1 | `doctor` | mise 미활성 shell | `warning`, exit 0. Node 24.21.0·Ruby 4.0.7을 측정해 pin 불일치 warning을 냈다 | 분류 대상 아님. 사용자 shell 조건으로 다시 실행했다 |
| 2 | `doctor` | `zsh -i`(mise 활성) | `error`, exit 1. `cocoapods.version`: Ruby 3.2.11에 `pod`가 없다 | host 준비 누락 |
| 3 | `build` | 2와 같음 | `validate` 실패, 0.9s. 설치·파일 변경은 없었다 | host 준비 누락 |
| 4 | `doctor` | CocoaPods 1.16.1 설치 뒤 | `warning`, exit 0. `node_modules missing` 1건만 남았다 | — |
| 5 | `build` | 4와 같음 | `dependencies` 실패, 59.3s. repo의 preinstall `npx solidarity`가 Android 항목(`emulator` binary, `ANDROID_HOME`)을 거부했다 | host 준비 누락 |
| 6 | `build` | Android SDK 연결 뒤 | `validate` pass 1.4s → `dependencies` pass 148.1s → `device` skipped → `build` **실패** 11.6s | host 준비 누락(Xcode) |
| 7 | `up` | 6과 같음 | `validate` pass → `dependencies` pass 47.6s → `device` skipped → `metro` started → `build` **실패** 10.7s | host 준비 누락(Xcode) |
| 8 | `down` | 7 뒤 | `metro stopped`, `app skipped — no install record` | — |
| 9 | `xcodebuild`(`mobile` 없음) | 6의 remediation 명령을 직접 실행 | exit 65. 6·7과 같은 error 11건 | baseline 실패 |

6·7·9의 실패 원인은 xcodebuild error 11건이다. 11건 모두 같은 종류다.

```
Pods.xcodeproj: error: The iOS Simulator deployment target 'IPHONEOS_DEPLOYMENT_TARGET' is set to 9.0,
but the range of supported deployment target versions is 15.0 to 27.0.x.
(in target 'SDWebImage-SDWebImage' from project 'Pods')
```

대상 11개는 모두 pod의 resource bundle target이다(`<Pod>-<Bundle>` 형식). 설정값은 9.0–14.0이다. 다른 compile error는 없다. 같은 SHA는 라운드 2에서 Xcode 26.6으로 `** BUILD SUCCEEDED **`에 도달했다.

### 실패 원인 분류

1. **CocoaPods 1.16.1 — host 준비 누락.** #153은 `mobile up`의 `bundle install`이 1.16.1을 설치한다고 보았다. 그러나 repo의 `pod-install` script는 bare `pod install`을 실행한다. solidarity도 PATH의 `pod` 1.16.1을 요구한다. 따라서 repo Ruby(3.2.11)에 CocoaPods 1.16.1을 직접 설치해야 한다.
2. **Android SDK — host 준비 누락.** repo의 preinstall은 iOS 빌드에도 Android SDK를 요구한다. 이 host는 SDK를 외장 SSD에 둔다. SSD를 분리하면 `npm ci`가 실패한다.
3. **Xcode 27 — host 준비 누락, 미해결.** 잠긴 SHA의 Pods는 Xcode 27에서 빌드되지 않는다. repo는 Xcode를 선언하지 않는다. ADR-0016은 이 경우 사람이 다른 Xcode를 설치하고 `overrides.xcode`로 지정하도록 허용한다. maintainer는 이후 Go 게이트를 Xcode 27로 통일하기로 했다. 표본 재고정은 [#156](https://github.com/minjunkim-dev/mobile-runtime/issues/156)과 ADR-0017이 맡는다.

`mobile` 결함이 첫 화면 도달을 막은 사례는 없다. 따라서 Go blocker 티켓을 만들지 않았다.

### Go blocker가 아닌 관찰

아래 관찰은 판정에 영향이 없다. ADR-0012에 따라 matrix·runbook은 바꾸지 않았다.

- `xcode.version`은 Xcode 27.0을 `pass`로 판정했다. matrix는 하한만 가진다. 그래서 상한 비호환은 build 단계에서 드러난다.
- 실행 2의 remediation은 `mise doctor`다. 실제 원인은 repo Ruby에 `pod` gem이 없는 것이다. 이 원인은 `observed`에 실린 mise 메시지로만 알 수 있다.
- 실행 5의 화면 메시지는 `npm error` 줄만 싣는다. solidarity가 거부한 항목은 remediation이 가리키는 전체 install log에서 확인했다(#49 동작 확인).
- 실행 5는 부분 `node_modules`(883개)와 `.mobile-install.incomplete` marker를 남겼다. 실행 6은 marker를 보고 `npm ci`를 다시 실행했다.
- 실행 7의 `up`은 실행 6이 설치를 마친 뒤에도 `npm ci`를 다시 실행했다(47.6s).

### tracked 파일 상태

| 시점 | `git status --porcelain` |
| --- | --- |
| clone 직후 | 변경 없음 |
| `mobile.yml` 작성 뒤 | `?? mobile.yml` |
| 실행 1–5 뒤 | `?? mobile.yml` |
| 실행 6 뒤 | ` M ios/Podfile.lock`, `?? mobile.yml` |
| 실행 7–9 뒤 | 실행 6 뒤와 같음 |

실행 6에서 `ios/Podfile.lock`의 `SPEC CHECKSUMS` 119줄이 바뀌었다. 버전·의존성 줄은 바뀌지 않았다. `mobile`은 이 파일을 직접 쓰지 않았다. `mobile`이 `npm ci`를 실행했고, repo의 `postinstall`(`scripts/postinstall.sh`)이 `npm run pod-install`로 `pod install`을 실행했다. 이 `pod install`이 파일을 바꿨다. checksum이 바뀐 원인은 확정하지 못했다. 라운드 1·2 기록에는 이 변경이 없다.

따라서 이 실행은 #155 완료 조건의 "tracked 파일 수정 없음"을 충족하지 못했다. known-good 표본은 tracked 파일을 바꾸지 않아야 한다. 같은 현상은 ADR-0017의 새 후보에서도 관측됐다.

### 저장하지 않은 것

전체 install·build·Metro log, screenshot, 환경값은 저장하지 않았다. 위 출력은 필요한 줄만 옮겼다.

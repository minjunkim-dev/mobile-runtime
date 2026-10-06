# Dogfooding: up 라운드 4 — iOS Go 전 조사 실행

[Map #152](https://github.com/minjunkim-dev/mobile-runtime/issues/152)의 repo별 조사 실행 기록이다. ADR-0012의 조사 실행이며 Go round 성공으로 합산하지 않는다. 판정 기준은 ADR-0016이다. 첫 화면 렌더링만 앱 UI 도달로 본다.

## 공통 실행 환경

| 항목 | 값 |
| --- | --- |
| macOS | 27.0.1 (26A434) |
| Xcode | 27.0 (27A266a), 설치된 Xcode는 이것 하나 |
| iOS runtime | iOS 27.0 (24A434) 1종 |
| 시뮬레이터 | `iPhone 18 Pro - iOS 27.0`이 이미 booted |
| mise | 2026.10.1, 사용자 shell은 `mise activate zsh` |
| 자동 설치 방지 | 모든 `mobile` 명령에 `MISE_AUTO_INSTALL=false` |

host 도구는 [#153](https://github.com/minjunkim-dev/mobile-runtime/issues/153)에서 준비했다. repo별로 더 준비한 항목은 각 절에 적는다.

## mattermost-mobile

- 날짜: 2026-10-06
- 이슈: [#155](https://github.com/minjunkim-dev/mobile-runtime/issues/155)
- `mobile`: `main` `723b6aaea5766366ab02cb04f57565d3b638b8dc`, `swift build`(debug)
- repo: `mattermost/mattermost-mobile` `10207015a5023d844c65885ed134814f6c22294a`, 새 디렉터리에 `git fetch --depth 1` 후 checkout
- RN 0.83.9, npm(`package-lock.json`). Xcode 선언 없음. matrix 하한은 Xcode 16.1이다.
- 결과: **`failed`**. 첫 화면에 도달하지 못했다. `build` 단계에서 Xcode 27이 Pods를 거부했다. Go blocker는 없다.

### 사람의 준비

| 항목 | 내용 | 시점 |
| --- | --- | --- |
| untracked `mobile.yml` | `ios.scheme: Mattermost` | 실행 전 |
| CocoaPods 1.16.1 | Ruby 3.2.11에 `gem install cocoapods -v 1.16.1` | doctor 2회차 뒤 |
| Android SDK | SDK가 있는 외장 SSD를 연결해 `ANDROID_HOME`과 `emulator`를 살렸다 | build 2회차 뒤 |
| `mise trust`·앱 환경값 | 필요 없음 | — |
| `overrides.xcode` | 쓰지 않음. 설치된 Xcode가 27.0 하나다 | — |

### 단계별 결과

| # | 명령 | 조건 | 결과 | 분류 |
| --- | --- | --- | --- | --- |
| 1 | `doctor` | mise 미활성 shell | `warning`, exit 0. Node 24.21.0·Ruby 4.0.7을 측정해 pin 불일치 warning | host shell. 사용자 shell 조건으로 다시 실행 |
| 2 | `doctor` | `zsh -i`(mise 활성) | `error`, exit 1. `cocoapods.version`: `pod` shim이 Ruby 3.2.11에 없다 | host 준비 부족 |
| 3 | `build` | 2와 같음 | `validate` 실패, 0.9s. 설치·파일 변경 없음 | host 준비 부족 |
| 4 | `doctor` | CocoaPods 1.16.1 설치 뒤 | `warning`, exit 0. `node_modules missing` 1건만 남음 | — |
| 5 | `build` | 4와 같음 | `dependencies` 실패, 59.3s. repo의 preinstall `npx solidarity`가 Android 항목(`emulator` binary, `ANDROID_HOME`)에서 거부 | host 준비 부족 |
| 6 | `build` | Android SDK 연결 뒤 | `validate` pass 1.4s → `dependencies` pass 148.1s → `device` skipped → `build` **실패** 11.6s | host: Xcode 27 비호환 |
| 7 | `up` | 6과 같음 | `validate` pass → `dependencies` pass 47.6s → `device` skipped → `metro` started → `build` **실패** 10.7s | host: Xcode 27 비호환 |
| 8 | `down` | 7 뒤 | `metro stopped`, `app skipped — no install record` | — |

6·7의 build 실패 원인은 xcodebuild error 11건이다. 11건 모두 같은 종류다.

```
Pods.xcodeproj: error: The iOS Simulator deployment target 'IPHONEOS_DEPLOYMENT_TARGET' is set to 9.0,
but the range of supported deployment target versions is 15.0 to 27.0.x.
(in target 'SDWebImage-SDWebImage' from project 'Pods')
```

대상 11개는 모두 pod의 resource bundle target이다(`<Pod>-<Bundle>` 형식). 설정값은 9.0–14.0이다. 다른 compile error는 없다. Xcode 27은 허용 범위 밖의 deployment target을 error로 처리한다. 같은 SHA는 라운드 2에서 Xcode 26.6으로 `** BUILD SUCCEEDED **`에 도달했다. 이 판정은 Xcode 27.0 / iOS 27.0 조합에만 귀속한다.

### 실패 원인 분류

1. **CocoaPods 1.16.1 부재 — host 준비 부족.** #153은 `mobile up`의 `bundle install`이 1.16.1을 설치한다고 보았다. 하지만 repo의 `pod-install` script는 bare `pod install`이다. solidarity도 PATH의 `pod` 1.16.1을 요구한다. 따라서 repo Ruby(3.2.11)에 CocoaPods 1.16.1이 직접 있어야 한다.
2. **Android SDK 부재 — host 준비 부족.** repo의 preinstall이 iOS 빌드에도 Android SDK를 요구한다. 이 host의 SDK는 외장 SSD에 있다. SSD가 빠지면 `npm ci`가 실패한다.
3. **Xcode 27 비호환 — host 준비 부족(미해결).** repo는 Xcode를 선언하지 않는다. matrix 하한(16.1)은 27.0이 충족한다. 그래도 잠긴 SHA의 Pods는 Xcode 27에서 빌드되지 않는다. 해결하려면 사람이 Xcode 26.x와 그 runtime을 설치하고 `overrides.xcode`를 써야 한다. ADR-0016이 허용하는 준비다.

`mobile` 결함으로 첫 화면 도달이 막힌 사례는 없다. 따라서 Go blocker 티켓을 만들지 않았다.

### Go blocker가 아닌 관찰

판정에 영향이 없다. ADR-0012에 따라 matrix·runbook은 바꾸지 않았다.

- `xcode.version`은 Xcode 27.0을 `pass`로 판정했다. matrix가 하한만 가지므로 상한 비호환은 build에서야 드러난다.
- 2의 remediation은 `mise doctor`다. 실제 원인(repo Ruby에 `pod` gem 없음)은 `observed`의 mise 메시지에서만 읽을 수 있다.
- 5의 화면 메시지는 `npm error` 줄만 싣는다. solidarity가 무엇을 거부했는지는 remediation이 가리키는 전체 install log에서 확인했다(#49 동작 확인).
- 5가 남긴 부분 `node_modules`(883개)와 `.mobile-install.incomplete` marker에서 `doctor`의 `project.detected`는 `pass`였다. `build`는 marker를 보고 `npm ci`를 다시 실행했다. 재설치 동작은 맞고, doctor 보고만 설치 완료처럼 보인다.
- 7의 `up`은 6에서 설치를 마친 뒤에도 `npm ci`를 다시 실행했다(47.6s). lockfile이 있으면 매번 package manager가 정렬을 검사하는 설계대로다.

### tracked 파일 상태

| 시점 | `git status --porcelain` |
| --- | --- |
| clone 직후 | 변경 없음 |
| `mobile.yml` 작성 뒤 | `?? mobile.yml` |
| 1–5 뒤 | `?? mobile.yml` |
| 6 뒤 | ` M ios/Podfile.lock`, `?? mobile.yml` |
| 7·8 뒤 | 6과 같음 |

`ios/Podfile.lock`의 변경은 `SPEC CHECKSUMS` 119줄뿐이다. 버전·의존성 줄은 바뀌지 않았다. 변경 주체는 `mobile`이 아니다. `mobile`이 실행한 `npm ci`의 repo `postinstall`(`scripts/postinstall.sh` → `npm run pod-install`)이 `pod install`을 실행했다. checksum이 왜 다른지는 확정하지 못했다. 라운드 1·2 기록에는 이 변경이 없다. Go round 전에 같은 현상이 Xcode 26.x에서도 나는지 확인해야 한다.

### 저장하지 않은 것

전체 install·build·Metro log, screenshot, 환경값은 저장하지 않았다. 위 출력은 필요한 줄만 옮겼다.

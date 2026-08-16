# ADR-0006: pod 설치 방법은 프로젝트가 선언한 것을 읽고, mobile.yml을 열지 않는다

- 상태: 채택
- 날짜: 2026-08-15
- 관련: #48(티켓), #44(dogfooding up 라운드 1), #11(mobile.yml v0 범위) · ADR-0003(근거 체인)

> 처음 `0005`로 커밋했다가 `0006`으로 옮겼다. 0005는 맵(#1)이 #36의 도구 소유자 판정 규칙 앞으로 이미 예약해 둔 번호이고, 그 구현(#37)이 아직 열려 있어 파일만 없었다. 번호는 먼저 잡는 것이 아니라 먼저 결정된 것이 갖는다.

## 배경

Dogfooding(#44)에서 `up`의 `dependencies`가 mattermost-mobile의 Pods를 **영영 설치하지 못했다**. 이 repo의 `Podfile`은 New Architecture 플래그 없이는 평가 자체를 거부한다:

```
[!] Invalid `react-native-paste-input.podspec` file: react-native-paste-input 2.0.1 requires the React Native New Architecture (Fabric/TurboModules).
```

그 플래그를 어디에 두는지는 repo가 이미 적어두었다:

```json
"pod-install": "cd ios && RCT_NEW_ARCH_ENABLED=1 pod install",
```

`up`은 언제나 맨 `pod install`을 돌았고, 실패 remediation이 준 복붙 명령(`cd <ios> && pod install`)도 같은 이유로 실패했다 — 사람이 화면을 그대로 따라 해도 같은 벽이었다.

표본 3종 중 rainbow도 자기 명령(`install-pods`: `bundle exec pod install --repo-update`)을 선언한다. 그 repo는 맨 `pod install`로도 설치돼서 우연히 통과했을 뿐이다. joplin은 선언이 없고 루트 `postinstall`이 설치를 겸한다. 즉 **선언은 흔하고, 맨 명령이 통하는 것은 우연이다.**

티켓 #48은 두 설계를 올려놓고 결정을 이 자리로 미뤘다.

## 결정

**앵커 `package.json`의 `scripts`에서 pod 설치 스크립트를 찾으면 그것을 프로젝트의 패키지 매니저로 돌린다. 없을 때만 맨 `pod install`.** `mobile.yml`에 `ios.podInstall`을 열지 않는다.

### 왜 mobile.yml이 아닌가

Tier 3(mobile.yml)은 "추론 불가능해서 사용자가 직접 선언하는 정보"다. 이 값은 추론 불가능하지 않다 — repo가 이미 `package.json`에 적어두었고, 그 선언이 사람과 CI가 실제로 쓰는 정본이다. 여기에 `ios.podInstall`을 열면 같은 사실이 두 곳에 살면서 갈라지고, #11이 v0에서 잠근 설정 최소주의도 깨진다. Tier 1이 답하는 질문에 Tier 3을 여는 것은 계층의 방향을 뒤집는 일이다.

### 스크립트로 인정하는 조건

**이름이 관행 목록에 있고, 본문이 실제로 pod 설치를 돈다** — 둘 다 성립해야 한다.

- 이름만 보면 `pods`라는 이름의 청소·린트 스크립트를 설치로 돌린다.
- 본문만 보면 joplin의 루트 `postinstall`이 걸린다. 그 스크립트는 `pod install`을 돌긴 하지만 다른 열두 가지를 하는 길에 돈다 — 그것을 Pods 단계로 돌리면 install 전체를 한 번 더 도는 것이다.
- 본문은 `pod install`과 `pod-install`(동명의 npm 패키지, `npx pod-install`) 둘 다 인정한다. RN 앱의 상당수가 후자로 적는다.
- 이름 목록은 순서 있는 고정 목록이다(`pod-install` → `pods-install` → `install-pods` → `install:pods` → `pod:install` → `pods`). 여러 개를 선언한 매니페스트가 실행마다 다른 것을 고르면, ADR-0003이 근거 하나를 정본으로 세운 이유가 그대로 무너진다.
- **앵커의 매니페스트만 읽는다.** `ios/`는 앵커의 것이고, 워크스페이스 루트의 스크립트는 남의 패키지 install이다.

### 실행 위치와 복붙 명령

- 선언된 스크립트는 **앵커에서** 돈다(`cd ios`는 대개 스크립트 자신의 첫 단어다). 맨 `pod install`은 `Podfile`이 있는 `ios/`에서 돈다.
- `up`이 도는 명령과 실패가 건네는 복붙 명령은 **한 자리에서** 나온다(`podInstallProcess` / `podInstallCommand`). 이 티켓이 시작된 실패가 정확히 둘이 갈린 것이었다.
- 복붙 명령은 무엇이 그것을 골랐는지 함께 말한다(ADR-0003). `yarn run pod-install`은 그것이 대체한 `pod install`보다 자기 설명력이 약하다.

## 결과

- **mattermost-mobile**: 해결. `RCT_NEW_ARCH_ENABLED=1`이 실린다.
- **joplin**: 변화 없음. 이름 게이트가 `postinstall`을 걸러낸다.
- **rainbow**: 동작이 바뀐다. 맨 `pod install`이 아니라 선언된 `bundle exec pod install --repo-update`를 돈다. `bundle install`이 선행되지 않은 호스트에서는 **전에 통과하던 repo가 실패한다.** 이것을 폴백으로 덮지 않는다 — repo가 선언한 것이 정본이고, gem이 없다는 사실은 doctor의 `cocoapods` Check가 이미 따로 판정한다. 조용히 맨 명령으로 내려앉으면 "선언된 것을 읽는다"가 우연히 통하는 repo에서만 참인 규칙이 된다.
- 로그 파일 이름이 설치 대상 기준으로 바뀐다(`node_modules-install.log` / `Pods-install.log`). 선언된 pod 설치는 Node install과 같은 `yarn`으로 도는 탓에, 실행 파일 이름을 쓰면 두 번째가 첫 번째를 덮어쓴다.

## 열어둔 것

- 관행 이름에 걸렸지만 본문이 아니어서 쓰지 않은 스크립트를 화면에 알리지 않는다. "선언을 봤지만 안 썼다"를 말할 출력 자리가 아직 없다 — 생기면 그때 싣는다.
- Android(`gradlew`)에는 같은 질문이 아직 없다. RN adapter의 iOS 경로만 이 결정의 대상이다.

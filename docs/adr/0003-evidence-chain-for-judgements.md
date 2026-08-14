# ADR-0003: 판정 근거는 Tier 안에서 체인으로 고르고, 프로젝트 선언은 매트릭스와 합성한다

- 상태: 채택
- 날짜: 2026-08-14
- 관련: #21(dogfooding), #22, #23, #25, #26, #30 · ADR-0004(등급 정책)

## 배경

Dogfooding(#21)에서 pristine clone 3개(mattermost-mobile / rainbow / joplin)에 `mobile doctor`를 돌린 결과, 근거를 고르는 방식에서 네 가지가 한꺼번에 드러났다.

1. **가장 값어치 있는 두 판정이 클론 직후에 비어 있다.** `xcode.version`·`simulator.runtime`이 3/3 repo에서 `unknown`이었다. 이유는 `MatrixLookup`이 매트릭스 입력을 `node_modules/react-native`의 실측으로만 인정하기 때문이다. 그런데 같은 실행의 다른 줄은 이미 `React Native 0.83.9 declared`라고 말하고 있었고, 세 repo 전부 선언이 range가 아니라 정확한 핀이었으며, 해석이 끝난 버전이 커밋된 락파일에 들어 있었다. North Star는 `git clone → mobile up`인데 그 첫 순간에 doctor가 답을 못 냈다.

2. **repo가 적어둔 요구를 읽지 않는다.** rainbow는 `.xcode-version`에 26.3을 선언하지만 doctor는 매트릭스 하한(RN 0.81 → Xcode 16.1)만 본다. mattermost-mobile은 deployment target 16.4를 선언하지만 매트릭스는 iOS 15.1을 요구한다 — iOS 15.x runtime만 있는 호스트에서 `simulator.runtime`이 `pass`가 되지만 앱은 설치조차 되지 않는다. 미탐 경로다.

3. **모노레포에서 근거의 위치를 틀린다.** joplin은 `yarn.lock`이 워크스페이스 루트에만 있고 `packageManager: yarn@4.16.0`도 루트가 선언한다. 앵커(`packages/app-mobile`) 옆만 보는 현재 구조는 패키지 매니저 Check를 통째로 건너뛰고, install 안내로 `npm install`을 냈다 — 복붙하면 워크스페이스가 깨진다.

4. **`node_modules` 하나가 근거로 과대평가된다.** `node_modules/react-native/package.json`만 스텁으로 만들어도 `project.detected`가 "dependencies installed"로 통과했다.

Tier 1/2/3 계층(#1에서 잠긴 원칙)은 **요구가 어디서 오는가**를 가른다. 이번에 드러난 것은 그 축이 아니라, **한 Tier 안에서 여러 근거가 경합할 때 무엇을 먼저 믿는가**였다. 그 이름이 없었다.

## 결정

**근거 체인(evidence chain)을 도입한다** — 하나의 요구에 대해 근거 후보를 순서대로 두고, 먼저 답하는 것을 쓰되 어느 근거였는지를 결과에 싣는다.

### RN 버전 (매트릭스 입력)

`실측(node_modules) → 락파일 → 정확한 핀 → unknown`

- 락파일은 `package-lock.json`(lockfileVersion 2/3)과 `yarn.lock`(berry) 둘만 읽는다. `pnpm-lock.yaml`·`bun.lock`은 한 단계 약한 근거로 폴백할 뿐 미탐이 되지 않는다.
- yarn berry는 **앵커의 선언 range를 descriptor 키로 매칭**한다(`react-native@npm:0.81.6`). joplin의 `yarn.lock`에는 react-native 항목이 둘이고(`@joplin/app-mobile` 0.81.6, `@joplin/react-native-alarm-notification` 0.70.6), 단순 스캔은 틀린 버전을 집는다.
- npm 락은 설치 경로를 키로 쓰는 `packages` 맵을 읽는다(lockfileVersion 1은 이 맵이 없어 다음 근거로 내려간다). 버전 충돌이 나면 npm이 앵커 옆에 사본을 남기므로, **앵커 아래의 중첩 항목이 호이스팅된 항목을 이긴다** — 앵커가 실제로 빌드하는 쪽이 그것이다(#30 구현에서 정한 세부).
- "선언 range는 측정이 아니다"라는 기존 규율은 유지된다. 락파일은 range가 아니라 해석된 결과이고, 정확한 핀은 range가 아니다.
- 실측과 락파일이 어긋나면 **실측이 이기고, 불일치를 `-v`에 노출한다**. `mobile.yml` Override 충돌과 같은 규율이다 — 충돌은 숨기지 않는다.

### Xcode·iOS runtime 요구

요구 = **`max(매트릭스 하한, 프로젝트 선언)`**. Check id는 늘리지 않고 같은 Check 안에서 합성하며, `-v`에 두 근거와 승자를 함께 보인다.

- Xcode의 프로젝트 선언은 `.xcode-version`. 값은 버전 문자열만이고, 매트릭스 하한과 같은 비교기(`MinimumVersion`)로 **하한으로 읽는다** — `26.3`은 26.3.x를 포함해 그 위를 허용한다. 새 파서를 만들지 않는다.
  - 최초 문안은 여기서 prefix 매칭 비교기(`VersionPin`)를 재사용하라고 적었다. `VersionPin`에는 순서가 없어 `max`도 "승자"도 성립하지 않으므로, 같은 문단의 합성 규칙을 따라 하한으로 정정한다(#25 구현에서 드러남). 순서 비교 한 줄(`MinimumVersion.exceeds`)만 늘었다.
  - 차이가 보이는 곳은 선언보다 새 호스트뿐이다: `.xcode-version` 26.3 + Xcode 27은 `pass`이고, prefix 핀이었다면 `error`다. 두 해석 모두 #25의 미탐(16.1 호스트가 26.3 선언을 통과하던 것)은 막는다. 선언보다 새 Xcode를 막는 것은 이 Check가 아니라 별도 판정의 일이다.
- runtime의 프로젝트 선언은 deployment target이고, 소스 체인은 `ios/Podfile.properties.json`의 `deploymentTarget` → Podfile `platform :ios` 리터럴 → 없음이다. 검증 repo 3개가 이 체인으로 전부 정확히 풀린다(16.4 / 15.1 / 15.1).
- **`project.pbxproj`는 읽지 않는다.** 타깃마다 값이 달라(joplin 15.6/18.6, rainbow 15.1/17.5) 어느 것이 앱인지 알려면 scheme 선택이 필요한데, ADR-0004에서 그 선택은 미확정으로 남을 수 있는 상태로 정했다. 모호한 소스를 근거로 삼지 않는다.
- **`mise.toml`·`.tool-versions`는 읽지 않는다.** rainbow조차 `mise.toml`에는 maestro·foundry만 두고 node/ruby는 `.node-version`/`.ruby-version`에 위임한다 — 관례 파일이 이미 정본이다. 관리자별 포맷을 하나 열면 asdf·proto·volta로 끝없이 늘어난다.

### 워크스페이스

**앵커에서 위로 올라가 만나는 첫 락파일의 위치를 워크스페이스 루트로 본다.**

- 패키지 매니저는 락파일 종류가 정한다. install 명령도 거기서 나온다 — 종류가 매니저를, 위치가 실행할 자리를 정한다. 워크스페이스 루트가 앵커와 다르면 `cd`가 명령의 일부다. 복붙되는 명령이므로 무엇이 그 명령을 골랐는지(락파일 이름)를 remediation이 함께 말한다.
- 루트와 앵커의 `engines`는 함께 읽어 **더 엄격한 쪽**을 요구로 삼는다. `packageManager`는 워크스페이스 계약이므로 루트가 우선한다.
  - 구현은 "더 엄격한 쪽을 고른다"가 아니라 **둘 다 요구로 두고 어긴 쪽을 판정에 싣는다**로 정정한다(#26 구현에서 드러남). 두 range의 엄격함에는 일반적으로 순서가 없고(`>=20 <22` vs `>=21`), 교집합은 비교 가능한 경우 "더 엄격한 쪽"과 같은 답을 낸다 — joplin에서는 그대로 `>=22.12`가 error의 근거가 된다. range 비교기를 새로 만들지 않기 위한 선택이다.
  - 각 선언은 따로 판정한다. 파싱 못 하는 range 하나가 나머지 선언의 판정까지 `unknown`으로 끌어내리면, 앵커가 깨진 순간 루트의 계약이 사라져 #26이 한 겹 안쪽에서 재현된다.
- 락파일 위치는 실측 신호라 `workspaces` 필드를 파싱하는 것보다 단순하고, npm·pnpm workspaces에도 그대로 통한다.

### 근거로 쓰지 않는 것

`node_modules`의 **존재**는 "설치가 완결됐다"의 근거가 아니다. `project.detected`는 그 주장을 하지 않는다(ADR-0004).

## 결과

- 클론 직후에도 Tier 2 판정이 나온다. 검증 repo 3개 전부 락파일에서 RN 버전이 해석된다.
- `.xcode-version`·deployment target이 근거에 들어오면서, 매트릭스가 프레임워크 하한만 담는다는 사실이 미탐이 아니게 된다. `matrix.json` 데이터는 손대지 않는다.
- 근거가 늘어난 만큼 `-v` 출력이 판정의 감사 로그 역할을 한다. source 문자열이 "무엇을 믿고 이렇게 판정했는가"의 유일한 기록이므로, 근거를 추가하면서 source 표기를 빠뜨리는 것은 이 결정을 무효화한다.
- 파서가 늘었다: npm 락(JSON), yarn berry 락(텍스트), `Podfile.properties.json`(JSON), Podfile `platform` 한 줄(정규식). yarn berry와 Podfile 두 개만 손으로 읽는 파싱이고, 둘 다 실패 시 체인의 다음 근거로 내려간다.

## 대안

- **현행 유지(실측만).** 규율은 가장 단순하지만 North Star 시나리오에서 doctor가 침묵한다. dogfooding이 정확히 그것을 보여줬다.
- **정확한 핀만 인정하고 락파일은 읽지 않는다.** 파서가 안 늘지만 range로 선언한 repo에서는 여전히 답이 없다. 락파일은 그 경우까지 덮는다.
- **`workspaces` 필드로 워크스페이스를 찾는다.** npm/yarn/pnpm이 각각 다른 자리에 적고(`package.json` vs `pnpm-workspace.yaml`), 락파일 탐색이 더 짧다.
- **pbxproj까지 읽어 최대값.** 더 정확해 보이지만 scheme 미선택 상태에서 어느 타깃의 값인지 결정할 수 없다. 모호한 근거로 등급을 올리면 오탐이 된다.

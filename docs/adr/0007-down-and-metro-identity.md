# ADR-0007: Metro는 소유가 아니라 정체성으로 판정하고, `down`은 그 판정 위에 선다

- 상태: 채택
- 날짜: 2026-08-16
- 관련: #57(fog 승격 티켓), #45(미탐), #44(dogfooding up 라운드 1), #13(up 파이프라인 스펙), #12(CLI 계약) · ADR-0004(등급 정책)

## 배경

#13이 계획 시점에 잠가 둔 fog 트리거 셋 중 세 번째(`down`·`stop` 동사 + Metro 수명 관리)가 #44 실측으로 승격 조건을 충족했다.

라운드 1에서 Metro를 **두 번** 손으로 죽여야 했다. 한 번은 실패한 실행이 남긴 것(scheme 미선언으로 `build`가 멈췄는데 `metro`는 이미 spawn된 뒤였다 — #53), 한 번은 다른 프로젝트의 것이 8081을 잡고 있어서다.

후자는 불편으로 끝나지 않고 **성공을 보고하는 거짓말**이 됐다(#45): joplin 앱이 mattermost의 Metro에 붙어 빨간 화면을 띄웠는데 `up`은 `launch pass`, `exit 0`이었다. 지금의 Metro 판정은 `/status`의 바디에 `packager-status:running`이 있는지만 보는데, 그 문자열은 **어느** Metro든 답한다.

즉 "이 Metro는 누구의 것인가"와 "누가 정리하는가"가 같은 질문이다. `MetroProcess`가 이미 `state: reused | spawned`를 구분해 둔 것은 그 질문이 계약에 반쯤 들어와 있었다는 뜻이다.

## 조사

RN 0.73~0.87의 실제 배포 패키지(metro 0.80/0.81/0.83/0.87, `@react-native/dev-middleware`, `@react-native/community-cli-plugin`, `@react-native-community/cli-server-api` 12/14/20)를 직접 열어 확인했다.

- **`/status`는 `X-React-Native-Project-Root` 응답 헤더를 함께 낸다.** `cli-server-api/src/statusPageMiddleware.ts`가 `process.cwd()`를 싣는다. 12.3.7(RN 0.73)부터 20.2.0까지 동일하다.
- **RN 자신이 정확히 이 판정을 쓴다.** `community-cli-plugin/src/utils/isDevServerRunning.js`: 포트가 차 있으면 `/status`를 물어 바디가 `packager-status:running`이고 헤더가 projectRoot와 같을 때만 `matched_server_running`, 아니면 `port_taken`. 0.73~0.87 로직이 같다.
- **다른 엔드포인트는 정체성을 흘리지 않는다.** `/json`, `/json/list`, `/json/version`, `/open-debugger`, `/symbolicate`, `/assets` 전부. inspector-proxy의 페이지 서술자에는 projectRoot가 없고, 앱이 붙기 전에는 목록 자체가 비어 있다.
- **HTTP 종료 엔드포인트가 없다.** metro·dev-middleware·cli-server-api 어디에도 없다. 프로세스를 죽이는 것이 유일한 경로다.
- **pidfile·lockfile이 없다.** RN도 metro도 실행 중인 서버를 식별하는 파일을 남기지 않는다.
- **한계**: RN 0.76부터 `community-cli-plugin`이 `cli-server-api`를 `require.resolve`로 찾고 없으면 no-op 스텁으로 대체한다. metro 본체는 `/status`를 서빙하지 않으므로 그 경우 엔드포인트 자체가 없다.

## 결정

### 1. Metro는 정체성으로 판정한다. 소유를 추적하지 않는다

`/status`의 `X-React-Native-Project-Root`가 앵커 디렉터리와 같으면 이 프로젝트의 Metro다. pid를 파일에 남기지 않는다.

대안이었던 소유 추적(`up`이 spawn한 pid를 남기고 그것만 죽인다)을 버린 이유:

- pid는 stale해진다. 프로세스가 이미 죽었거나 pid가 재사용됐을 때 파일은 그 사실을 모른다.
- 손으로 띄운 Metro를 영영 못 치운다. 라운드 1에서 손으로 죽인 두 건 중 하나가 정확히 그 모양이었다.
- **RN 자신의 판정과 갈라진다.** "Orchestrate, don't replace"는 우리가 새 규칙을 발명하지 않는다는 뜻이기도 하다.

**받아들인 대가**: `down`은 이 프로젝트의 Metro면 죽인다 — 사용자가 어제 손으로 띄운 것이라도. 소유를 모르기 때문이다. 이 트레이드오프가 `정리 대상`이라는 용어를 "띄운 것"이 아니라 "누구의 것인가"로 정의하게 만든 이유다.

판정은 다섯 갈래다: **내 것 / 남의 것 / 확인 불가 / Metro 아님 / 비어 있음.** `up`의 재사용 판정과 `down`의 "죽여도 되는가"가 **같은 판정기**를 쓴다 — doctor와 up이 기기 셀렉터를 공유하는 것과 같은 이유다. 판정과 실행이 갈리면 up이 내 것이라 재사용한 Metro를 down이 못 죽인다.

### 2. 확인 불가는 1급 상태다

`/status`가 아예 없는 경우(위 한계)를 "Metro 아님"으로 뭉뚱그리지 않는다. 멈추는 것은 같지만 화면에 나가는 문장이 다르다 — "포트를 다른 게 잡고 있다"가 아니라 **"8081이 답했지만 어느 프로젝트의 Metro인지 확인할 수 없다"** 다. doctor의 `unknown`이 하는 일 그대로이고, 판단 불가를 침묵으로 덮지 않는다는 규율의 같은 적용이다.

멈추는 쪽을 고른 것은 #14가 잠근 기준 때문이다: **미탐이 오탐보다 비싸다.**

### 3. `down` 하나. `stop`은 만들지 않는다

`stop`과 `down`이 갈리려면 "멈춘 채 남아 있는" 중간 상태가 있어야 하는데, Metro에도 앱에도 그런 상태가 없다. 두 동사를 두면 차이를 설명해야 하고, 설명할 차이가 없다.

`down`은 **이 프로젝트의 Metro와 이 프로젝트가 설치한 앱**을 겨눈다. **시뮬레이터는 겨누지 않는다** — `up`이 부팅했더라도 머신의 자원이고, 끄면 다음 `up`이 수십 초를 더 쓸 뿐 푸는 문제가 없다.

`up` 자체는 실패해도 롤백하지 않는다(#13의 fail-fast, 롤백 없음 유지). 대신 실패한 `up`이 `mobile down`을 remediation으로 싣는다 — 단, `metro.state == .spawned`일 때만. 재사용이었다면 그 Metro는 실행 전부터 있던 것이고, 사용자가 쓰던 것을 끄라고 권하는 셈이 된다.

### 4. 앱만 상태를 남긴다

`up`이 `install` 직후 `{udid, bundleId}`를 실행 로그와 같은 프로젝트별 temp 디렉터리에 기록하고 `down`이 읽는다. 없으면 앱을 건너뛴다.

1번과 모순이 아니라 **같은 규율의 다른 답**이다 — 있는 근거를 쓴다. Metro는 세계에 물어볼 수 있지만(포트가 답한다), 시뮬레이터는 "어느 앱이 mobile이 설치한 것인가"를 말해주지 않는다. 다시 계산하려면 `xcodebuild -showBuildSettings`가 필요하고 그것은 scheme 결정을 요구하는데, scheme 미선언은 dogfooding **3/3 repo 전부**가 걸린 자리다 — `down`이 가장 필요한 repo에서 `down`이 안 도는 셈이 된다.

**캐시가 아니라 기록이다.** 없으면 건너뛰고 그렇게 말하지, 재계산으로 메우지 않는다. `down`이 앱을 끈 뒤에도 지우지 않는다 — `down`은 terminate만 하고 uninstall하지 않으므로 앱은 여전히 거기 있다.

### 5. `SIGTERM`만 쏜다

HTTP 종료 경로가 없으므로 프로세스를 죽인다. `SIGTERM` 후 짧게 기다렸다 `/status`로 확인한다(같은 판정기 재사용). 여전히 살아 있으면 **에스컬레이션하지 않고 사람에게 넘긴다** — 도메인 실패(exit 1) + `lsof -nP -iTCP:8081 -sTCP:LISTEN`.

`SIGKILL`을 우리가 쏘지 않는 이유는 `up`이 시뮬레이터를 만들지 않는 이유와 같다: 되돌릴 수 없는 것은 사람의 손에 남긴다. 종료 핸들러를 건너뛰면 watchman 구독이나 자식 프로세스가 남아, 이 결정이 푼 문제를 다른 모양으로 되돌린다. 필요하면 remediation이 그 명령을 적어준다.

### 6. `down`은 파이프라인이 아니다

`up`은 7단계 직렬 + fail-fast다. `down`의 두 일은 서로 독립이라 fail-fast가 해롭다 — Metro를 못 죽였다고 앱을 안 끌 이유가 없다. `DoctorEngine`이 fail-fast가 아닌 것과 같다. 둘 다 시도하고 결과를 모아 보고한다. `Stage` 프로토콜은 `up` 전용으로 남는다.

항목 id는 `metro`·`app`으로 `up`의 stage id와 같은 단어를 쓴다 — 가리키는 대상이 같기 때문이고, `metro-teardown` 같은 새 단어는 읽는 사람에게 개념을 하나 더 만든다.

종료 규약: 정리할 것이 없으면 exit 0("nothing to stop" — 할 일이 없었다는 사실이지 판단 불가가 아니다), 앱 terminate 실패는 무시(`LaunchStage`가 이미 같은 판단을 내렸다), Metro를 못 죽이면 exit 1. envelope·exit code 규약은 #12 공통.

`down`은 프로젝트를 요구한다 — 정체성 판정이 앵커와 비교하는 일이고 설치 기록도 프로젝트 경로로 찾는다.

## CLI 계약과의 관계

#12는 *"MVP 명령은 `doctor`/`up` 둘뿐 … dogfooding에서 불편이 실측되면 fog로 승격"* 이라고 적었다. 새 동사는 그 결정과의 충돌이 아니라 그 결정이 예고한 경로다. flat verb 규약도 그대로다.

## 결과

- #45의 미탐이 헤더 하나로 닫힌다 — joplin에서 mattermost의 Metro는 "남의 것"이라 재사용 대상이 아니다.
- 남의 Metro가 8081을 쥐고 있을 때 **그 프로젝트의 경로를 이름으로 말할 수 있다.** 지금의 점유 메시지는 "naming the occupant is not ours to do"라며 `lsof`에 미뤘는데, 이 갈래에서는 미룰 필요가 없다. 다만 복붙 명령은 여전히 `lsof`다 — 헤더 값은 그 프로세스의 CWD일 뿐 RN 앵커라는 보장이 없어서, `cd <경로> && mobile down`은 통하지 않을 수 있다(ADR-0006이 세운 규율: 화면이 주는 명령은 실제로 통해야 한다).
- 워크스페이스 루트에서 사람이 `yarn start`를 했다면 헤더가 루트를 가리켜 앵커와 불일치한다 → "남의 것"으로 읽고 죽이지 않는다. 보수적으로 틀리는 방향이다.
- 구현은 둘로 갈린다: 판정기 + `up` 재사용은 #45, `down` 명령은 별도 티켓. 판정기를 낳는 쪽이 다른 쪽을 열어준다.

## 열어둔 것

- `down`이 앱을 **uninstall**하지는 않는다. 요구가 실측되면 다시 연다.
- 시뮬레이터 shutdown은 `down`의 일이 아니다. 재판정 조건: 부팅된 시뮬레이터가 남아서 생기는 실패가 관측될 때.
- 설치 기록을 여러 기기로 확장하지 않는다. `up`은 한 번에 한 기기를 쓴다.

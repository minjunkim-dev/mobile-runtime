# mobile (working name)

Reproducible mobile development runtime. 프로젝트가 요구하는 환경을 추론·검증·기동한다 — North Star는 `git clone → mobile up`.

## Language

### 요구사항 계층

**Tier 1 (선언 파일)**:
앱 repo에 이미 존재하는 선언 파일(.nvmrc, package.json engines, Gemfile.lock, .xcode-version, Podfile의 deployment target, 락파일 등)에서 파싱한 요구사항.
_Avoid_: 설정 파일 추론

**Tier 2 (호환성 매트릭스)**:
어디에도 선언되지 않는 요구사항(Xcode, JDK 상한 등)을 프레임워크 버전에서 도출하는 실측 데이터.
_Avoid_: 하드코딩 버전 표

**Tier 3 (mobile.yml)**:
추론 불가능해서 사용자가 직접 선언하는 정보. 추론 가능한 것은 넣지 않는다.

**Override**:
Tier 2 추론과 mobile.yml이 충돌할 때 mobile.yml이 이기는 규칙. Tier 2 전용 — Tier 1은 정본 파일 수정이 올바른 경로라 override 대상이 아니다. 충돌 사실은 숨기지 않는다.

**Matrix (매트릭스)**:
Tier 2의 데이터 그 자체. 프레임워크 버전 → 요구 도구 버전 매핑.

### doctor

**Check (검사)**:
doctor가 실행하는 단위 검증. 안정적인 id가 계약이다.
_Avoid_: health check, validation item

**Status (상태)**:
Check의 결과. `pass` / `warning`(동작하지만 어긋남) / `error`(빌드·실행 실패 예상) / `unknown`(판단 불가) 4단계.

**unknown**:
"모른다"를 침묵 대신 명시하는 1급 상태. 판단 근거 소스가 없을 때 쓴다.
_Avoid_: skipped, N/A

**Remediation**:
warning/error에 반드시 붙는 복구 안내. 설명 + 복붙 가능한 명령(가능한 경우) + 문서 URL(선택).
_Avoid_: fix suggestion, hint

**근거 체인 (Evidence chain)**:
하나의 요구에 대해 같은 Tier 안에서 경합하는 근거들의 우선순위. 먼저 답하는 근거를 쓰되 어느 것이었는지 결과에 싣는다. Tier가 "요구가 어느 계층에서 오는가"라면 근거 체인은 "그 계층 안에서 무엇을 먼저 믿는가"다. ADR-0003 참조.
_Avoid_: fallback(조용히 내려앉는다는 뜻이 섞인다)

**Host check**:
프로젝트와 무관하게 머신 상태만 보는 Check (Xcode 설치, CoreSimulator 데몬 등).

**Project check**:
프로젝트 선언을 읽어야 성립하는 Check. 프로젝트 미탐지 시 실행되지 않는다.

### CLI

**Envelope**:
모든 `--json` 문서가 공유하는 공통 필드 집합(스키마 버전·도구 버전·명령·종합 상태). 명령별 본문은 envelope 위에 얹힌다.

**도메인 실패 / 도구 장애**:
exit code로 구분되는 실패 2종. 도메인 실패는 사용자 프로젝트·환경의 문제(remediation 동반), 도구 장애는 mobile 자체의 인프라 문제. 도메인 에러의 2층 구분(#9)과 같은 축.

### up

**Stage (단계)**:
up 파이프라인의 실행 단위. doctor의 Check처럼 안정적인 id가 계약이다. 직렬 실행, fail-fast.

**Stage status**:
Stage의 결과. `pass` / `skipped`(이미 되어 있어 할 일이 없었다) / `failed` 3단계. Check의 Status와 다른 어휘다 — Check는 머신에 대한 판정을 내리고 Stage는 자기가 무엇을 했는지 보고한다. 여기서의 `skipped`는 doctor가 금지한 그 `skipped`(판단 불가를 침묵으로 덮는 말)가 아니라 수행된 작업에 대한 사실이라 예외로 둔다.

**Stage 컨텍스트 (Stage context)**:
Stage가 다음 Stage에 넘기는 값의 명시적 타입. 앞 Stage가 실제로 넣은 것만 뒤가 읽는다 — 전역 가변 상태 없음.

**기기 선택 (Device selection)**:
어느 시뮬레이터를 쓸지 정하는 순서 — `mobile.yml`의 `ios.device` → 이미 booted된 기기 → 사용 가능한 최신 runtime의 최신 iPhone(세대가 높은 쪽, 같으면 이름이 가장 단순한 모델). doctor의 `config.values`와 up의 `device` Stage가 **같은 셀렉터**를 쓴다 — 판정과 실행이 갈리면 doctor가 쓸 수 있다고 한 기기를 up이 안 쓰는 일이 생긴다. 후보가 없으면 `simctl create` 명령을 주고 멈춘다. 시뮬레이터를 만들어 주지는 않는다.

**scheme 결정 (Scheme selection)**:
어느 scheme을 빌드할지 정하는 순서 — `mobile.yml`의 `ios.scheme` → 프로젝트에 하나뿐이면 그것. 여럿인데 선언이 없으면 고르지 않는다. doctor의 `config.values`와 up의 `build` Stage가 **같은 셀렉터**를 쓰고, 등급만 다르다 — doctor는 warning(아직 아무도 고르지 않았을 뿐 머신은 멀쩡하다, ADR-0004), up은 error(고르지 않으면 빌드할 수 없다). scheme 목록은 언제나 `.xcodeproj`에서 읽는다 — workspace를 읽으면 Pod scheme이 쏟아진다.

**빌드 대상 (Build target)**:
xcodebuild가 겨누는 것 — `ios/*.xcworkspace`가 정확히 하나면 그것, 하나도 없으면 `ios/*.xcodeproj`. CocoaPods는 workspace로만 링크되므로 이 순서가 뒤집히면 링크 실패로 끝난다. workspace가 여럿이면 "없음"이 아니라 모호함이라 project로 내려가지 않고 멈춘다. "scheme 목록을 어디서 읽는가"와는 다른 질문이다.

**빌드 산출물 (Built product)**:
build Stage가 확정해 install·launch에 넘기는 `.app` 경로와 bundle id. 빌드 로그 파싱이 아니라 `xcodebuild -showBuildSettings`가 근거다 — 로그 포맷은 Xcode 버전마다 움직인다.

**실행 로그 (Run log)**:
Stage의 전체 출력을 담는 파일. 앱 repo가 아니라 시스템 임시 디렉터리 아래 프로젝트별 경로에 쓴다(앱 repo에 `.gitignore` 항목을 요구하지 않기 위해). 경로는 언제나 실패와 함께 출력된다 — 사람이 찾을 수 없는 로그는 없는 로그다.

**UpReport / 파이프라인 status**:
up의 종합 결과. envelope의 `status`는 doctor와 같은 어휘를 쓴다 — 실패는 `error`, 그 외에는 Stage들이 관측한 것(validate의 warning은 up에서도 warning)이다. exit code 규칙(0/1/2)은 `DoctorReport`와 같다.

**프로젝트 의존성 (Project dependencies)**:
앱 repo 자신의 의존성(node_modules, Pods). up이 설치하는 정상 단계 — "자동 설치 금지" 원칙의 대상이 아니다.

**도구 프로비저닝 (Tool provisioning)**:
호스트 도구(Xcode, iOS runtime 등)의 설치. V1은 detect/validate만, 설치는 V2. "자동 설치 금지" 원칙이 가리키는 대상.

**Settle**:
launch 리턴 ≠ UI 렌더 완료라서 두는 설정형 고정 대기(기본 3s). 폴링 가능한 신호가 생기면 교체 대상.

### Dogfooding

**파손 시나리오 (Fault scenario)**:
doctor의 error 경로를 검증하기 위해 호스트를 의도적으로 깨뜨리는 재현 절차. 호스트 파손이라 검증 repo와 무관하다.
_Avoid_: failure injection, chaos test

**미탐 / 오탐**:
doctor 정확성의 두 실패 축. 미탐 = 실재 문제를 pass로 통과(치명 — doctor 신뢰의 근간), 오탐 = 멀쩡한데 warning/error(경고 — 개선 대상).

**Go/No-Go 게이트**:
다음 단계 진입 전 사전에 박아둔 기준으로 내리는 판정. #1 = feasibility(spike), #2 = 유용성(dogfooding). 기준은 판정 시점이 아니라 계획 시점에 잠근다.

### 구조

**Adapter**:
프레임워크별 프로젝트 해석기. MVP는 RN adapter 하나.
_Avoid_: plugin, provider(→ 플랫폼 쪽 용어)

**앵커 (Anchor)**:
프로젝트 탐지의 기준점 — RN에서는 react-native를 의존성으로 가진 package.json. adapter 활성화와 mobile.yml 탐색이 같은 앵커를 공유한다.

**워크스페이스 루트 (Workspace root)**:
앵커에서 위로 올라가 만나는 첫 락파일의 위치. 패키지 매니저와 install 실행 위치가 여기서 나오고, 루트가 선언한 `packageManager`·`engines`도 앵커의 것과 함께 요구가 된다. 단일 repo에서는 앵커와 같은 자리다. `workspaces` 필드는 파싱하지 않는다 — ADR-0003.
_Avoid_: monorepo root(모노레포가 아닌 단일 repo에도 있다)

**도메인 에러**:
외부 도구의 exit code + stderr를 해석해 만든 의미 있는 실패(복구 힌트 포함). 인프라 에러(spawn 실패·타임아웃)와 구분된다.

# mobile (working name)

Reproducible mobile development runtime. 프로젝트가 요구하는 환경을 추론·검증·기동한다 — North Star는 `git clone → mobile up`.

현재 `main`은 iOS React Native MVP와 Android Phase 4A CLI provider를 제공한다.
Private Phase 4A Android 내부 alpha는 SHA를 고정한 공개 OSS 실제 앱 표본 하나와
macOS 검증 조합 하나에서 통과했다(`docs/private-android-alpha-runbook.md` 6절). CLI가 현재 실행 표면이며 SwiftUI
macOS 앱은 같은 Core/provider 계약을 표현할 후속 표면이다.

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

**build**:
프로젝트 환경과 의존성을 검증하고 앱 산출물까지 만들되 설치·실행하지 않는 명령. `up`의 launch 계약과 앱 UI dogfooding 게이트를 약화시키지 않고, 앱 환경값 없이 가능한 검증을 분리한다.

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
up의 종합 결과. envelope의 `status`는 doctor와 같은 어휘를 쓴다 — 실패는 `error`, 그 외에는 Stage들이 관측한 것(validate의 warning은 up에서도 warning)이다. 실행의 성패는 `status`가 아니라 exit code로 판단한다. exit `0`이면 `status: warning`이어도 성공이다. JSON 문서만 보존한 소비자는 최상위 `error` 키의 부재로 성공을 판정한다 — 성공 문서에는 `error: null`이 아니라 키 자체가 없다. 실패 문서에도 실패 전까지 확보한 기기·Metro 같은 부분 `result`가 있을 수 있다. exit code 규칙(0/1/2)은 `DoctorReport`와 같다.

**프로젝트 의존성 (Project dependencies)**:
앱 repo 자신의 의존성(node_modules, Pods). up이 설치하는 정상 단계 — "자동 설치 금지" 원칙의 대상이 아니다.

**프로젝트 의존성 정렬 (Project dependency alignment)**:
lockfile을 읽기 전용 정본으로 두고 node_modules·Bundle gems·Pods 같은 설치 산출물을 그 상태에 맞추는 일. 소스 선언이나 lockfile을 바꾸는 마이그레이션과 다르다.

**도구체인 활성화 (Toolchain activation)**:
프로젝트가 선언한 이미 설치된 Node·Ruby·JDK 등을 이번 실행이 사용하도록 고르는 비파괴적 Resolve 단계. 커밋된 도구 관리자 설정이 있으면 그것이 정본이며, 없을 때만 현재 셸의 도구를 쓴다.

**프로젝트 실행 환경 (Project execution environment)**:
도구체인 활성화 결과를 project check·의존성 정렬·Metro·build가 함께 쓰는 명령 환경. 호스트 capability를 다루는 명령 환경과 구분한다. `packageManager`가 Yarn/pnpm을 선언하면 세 package-manager 경로는 모두 Corepack을 오프라인으로 사용하며, cache에 없는 manager는 자동 다운로드하지 않고 validation에서 멈춘다. 선언과 lockfile이 서로 다른 manager를 고르면 어느 쪽도 임의로 우선하지 않고 validation error로 멈춘다. 복구 명령도 같은 프로젝트 실행 환경을 보존하지만 사람이 명시적으로 실행하기 전에는 설치하지 않는다.

**선언된 pod 설치 (Declared pod install)**:
Pods를 어떻게 설치하는가에 대한 근거 체인 — 앵커 `package.json`의 관행 이름 스크립트(`pod-install`, `install-pods` 등) → 맨 `pod install`. 스크립트로 인정하려면 **이름이 관행 목록에 있고 본문이 실제로 pod 설치를 돈다**는 두 조건이 함께 성립해야 한다. 한쪽만 보면 `pods`라는 이름의 청소 스크립트를 설치로 돌리거나(이름만), 루트 `postinstall` 전체를 pod 설치로 착각한다(본문만). repo가 설치 방법을 적어두는 것은 맨 `pod install`이 거기서 통하지 않기 때문이다 — mattermost-mobile의 `RCT_NEW_ARCH_ENABLED=1`이 없으면 `Podfile` 평가 자체가 거부된다. up이 돌리는 명령과 실패 remediation이 주는 복붙 명령은 언제나 같은 답에서 나오고, 그 명령을 무엇이 골랐는지도 함께 나간다. ADR-0006 참조.

**Metro 판정 (Metro verdict)**:
8081 포트 한 번의 질의(`/status`)가 내는 다섯 갈래. **내 것** = 응답 바디가 Metro이고 `X-React-Native-Project-Root` 헤더가 앵커와 같다, **남의 것** = Metro이지만 헤더가 다른 프로젝트를 가리킨다, **확인 불가** = 포트는 답했는데 정체성을 물을 수 없다, **Metro 아님** = 응답이 있으나 Metro의 것이 아니다(연결 자체가 실패한 것과 구분된다 — 연결이 됐는데 말을 끝내지 않은 것도 여기다), **비어 있음** = 연결 실패, 그때만 띄운다. 포트는 8081 고정이다.

`up`의 재사용 판정과 `down`의 "죽여도 되는가"는 **같은 판정기**를 쓴다 — 기기 셀렉터를 doctor와 up이 공유하는 것과 같은 이유로, up이 내 것이라 재사용한 Metro를 down이 남의 것이라 못 죽이면 그 균열은 사용자에게 나타난다. 내 것만 재사용하고 내 것만 죽인다. 나머지 셋은 멈춘다.

**확인 불가 (Unidentifiable)**:
포트가 답했지만 어느 프로젝트의 Metro인지 물을 수 없는 상태. RN 0.76부터 `@react-native-community/cli-server-api`가 없으면 `/status` 미들웨어가 no-op 스텁이 되고, metro 본체는 `/status`를 서빙하지 않아 엔드포인트 자체가 사라진다. doctor의 `unknown`과 같은 급의 1급 상태다 — "Metro 아님"으로 뭉뚱그리면 사용자는 자기 Metro를 남으로 지목하는 문장을 읽는다. 멈추는 것은 같지만 말하는 것이 다르다.
_Avoid_: 점유(무엇이 잡고 있는지 안다는 뜻이 섞인다)

**Detached spawn**:
자식을 띄우고 기다리지 않는 실행. 출력은 실행 로그로 리다이렉트되고 PID만 돌아온다. up이 종료해도 Metro가 따라 죽지 않게 하려는 것 — 프로세스 그룹까지 떼지는 않으므로 터미널의 Ctrl-C는 아직 닿는다.
_Avoid_: daemon, background job

**MetroProcess**:
up이 남긴 Metro의 보고. `state`(reused/spawned)와, spawn했을 때만 PID·로그 경로. 재사용에는 PID가 없다 — **우리가 띄우지 않은** 프로세스이고, CI는 자기가 띄운 것만 정리해야 한다. 재사용이 성립했다는 것은 그 Metro가 이 프로젝트의 것이라는 뜻이지(Metro 판정), 이 실행이 시작했다는 뜻이 아니다. 실패한 `up`이 `mobile down`을 권하는 것은 `spawned`일 때뿐인 이유가 그것이다.

**도구 프로비저닝 (Tool provisioning)**:
Xcode·iOS runtime·도구 관리자 자체 또는 누락된 Node·Ruby·JDK 버전을 설치하거나 저장소 설정을 trust하는 일. 명시적 사용자 동의가 필요한 별도 흐름이며 `up`은 수행하지 않는다.

**앱 환경값 (App environment)**:
Firebase·ENS·`.env`처럼 앱 기능 실행에 필요한 프로젝트별 설정과 비밀값. 일반 도구체인 활성화·프로젝트 의존성 정렬과 분리한다. build 입력 자체인 값이 없으면 build도 실패할 수 있지만, build 성공만으로 launch나 Firebase·ENS 기능 성공을 주장하지 않는다.

**Settle**:
launch 리턴 ≠ UI 렌더 완료라서 두는 설정형 고정 대기(기본 3s). 폴링 가능한 신호가 생기면 교체 대상.

**Relaunch**:
launch Stage가 매 실행에서 terminate 후 다시 띄우는 것. `simctl launch`는 이미 떠 있는 앱에 대해 재시작 없이 옛 인스턴스의 PID를 돌려주므로, terminate 없이는 "up이 끝나면 화면에 방금 빌드한 코드가 있다"는 보장이 디스크에서만 참이 된다. terminate 실패는 무시한다 — 안 떠 있던 앱을 못 끈 것은 실패가 아니다.

**Android 활성 실행 (Android active run)**:
한 프로젝트의 Android `up`이 얻은 실행 자원을 `down`까지 이어서 식별하는 생명주기. 같은 대상을 향한 반복 `up`은 기존 활성 실행에 합류하며, 별개의 CLI 호출이나 앱 세션을 뜻하지 않는다.
_Avoid_: Android 세션, `up` 호출

**Android 소유 자원 (Android-owned resource)**:
Android 활성 실행이 새로 시작·연결·launch했고 현재 identity까지 다시 확인할 수 있는 정리 대상. 실행 전부터 존재했거나 재사용한 Emulator·Metro·adb reverse는 포함하지 않는다.
_Avoid_: Android 정리 대상, 프로젝트 자원

**Android rollback**:
Android `up` 실패 시 그 활성 실행의 소유 자원만 획득 역순으로 정리하는 best-effort 복구. 확인할 수 없거나 정리하지 못한 자원은 기록에 남아 후속 `down`이 재시도한다.
_Avoid_: 초기화, 강제 정리

### down

**정리 대상 (Teardown target)**:
`down`이 플랫폼 계약에 따라 겨누는 집합. 기준은 누가 띄웠는가가 아니라 **누구의 것인가**다. iOS에서는 이 프로젝트의 Metro와 설치 앱을 겨누며 시뮬레이터는 포함하지 않는다. Android에서는 Android active run이 identity를 기록한 이 프로젝트의 앱·adb reverse·Metro와 이번 실행이 부팅한 Emulator를 역순으로 겨눈다. 재사용했거나 identity를 확인할 수 없는 자원은 보존한다.
_Avoid_: 띄운 것(누가 시작했는가라는 틀린 축을 가리킨다), 잔존물(치워야 할 쓰레기라는 뜻이 섞인다 — 살아 있는 Metro는 정상이고 의도된 상태다)

**설치 기록 (Install record)**:
`up`이 `install` 직후 남기는 `{udid, bundleId}`. `down`이 어느 기기의 어느 앱을 끌지 아는 유일한 경로다 — 시뮬레이터는 "어느 앱이 mobile이 설치한 것인가"를 말해주지 않고, 다시 계산하려면 scheme 결정이 필요한데 그것은 dogfooding 3/3 repo가 걸린 자리다. Metro가 상태를 두지 않는 것과 모순이 아니라 같은 규율의 다른 답이다: **있는 근거를 쓴다** — Metro는 세계에 물어볼 수 있고 앱은 물어볼 데가 없다. **캐시가 아니라 기록이다** — 없으면 앱을 건너뛰고 그렇게 말하지, 재계산으로 메우지 않는다. 자리는 실행 로그와 같은 프로젝트별 temp 디렉터리다.

**Teardown 결과**:
`down`이 항목마다 내는 보고. 항목 id는 `metro`·`app`으로 `up`의 stage id와 같은 단어를 쓴다 — 가리키는 대상이 같기 때문이다. 항목 상태는 다섯이다: **stopped**(끔), **skipped**(정리할 것이 없었음), **blocked**(무언가 있는데 이 프로젝트의 것이 아니라 손대지 않음 — Metro 판정의 남의 것/확인 불가/Metro 아님이 여기로 온다. 판정이 쓴 문장을 그대로 싣는다 — 어느 프로젝트를 서빙하는지와 `lsof` 줄까지), **failed**(우리 것인데 끄지 못함), **unknown**(job을 돌리지 못해 아무것도 관측하지 못함 — doctor의 그 `unknown`이다). `blocked`·`unknown`이 `skipped`와 갈리는 이유는 화면에 나가는 문장이다 — 남의 Metro가 8081을 쥐고 있거나 아예 물어보지도 못했는데 "nothing to stop"을 읽으면 기계가 비어 있다는 뜻이 된다. `up`과 달리 **fail-fast가 아니다**: 두 일은 서로 독립이고, Metro를 못 죽였다고 앱을 안 끌 이유가 없다(doctor 쪽 규율). 정리할 것이 하나도 없으면 exit 0이다 — 할 일이 없었다는 사실이지 판단 불가가 아니다.

### Dogfooding

**파손 시나리오 (Fault scenario)**:
doctor의 error 경로를 검증하기 위해 호스트를 의도적으로 깨뜨리는 재현 절차. 호스트 파손이라 검증 repo와 무관하다.
_Avoid_: failure injection, chaos test

**미탐 / 오탐**:
doctor 정확성의 두 실패 축. 미탐 = 실재 문제를 pass로 통과(치명 — doctor 신뢰의 근간), 오탐 = 멀쩡한데 warning/error(경고 — 개선 대상).

**Go/No-Go 게이트**:
사전에 잠근 증거 기준으로 특정 전환 또는 주장을 허용할지 내리는 판정. 기준과 차단 범위는 계획 시점에 잠그며, No-Go는 그 경계를 통과하지 못했다는 뜻이지 프로젝트 전체 중단을 뜻하지 않는다. #1 = feasibility(spike), #2 = 유용성(dogfooding). 게이트는 플랫폼별로 잠근다. 현재 iOS 게이트는 ADR-0018의 단일 표본 1/1이다. ADR-0008·ADR-0017의 세 repo 판정은 과거 기록으로 유지한다. 게이트의 fresh clone은 사람이 앱 환경값을 준비하는 것을 허용한다. `mobile`이 앱 환경값을 만들거나 입력하는 것은 허용하지 않는다(ADR-0016).

**Go round**:
Go/No-Go 게이트를 판정하는 단일 실행 묶음이다. 같은 `mobile` SHA와 같은 host로 잠긴 표본 전부를 한 번에 실행한다. 다른 round의 성공을 합산하지 않는다.
_Avoid_: dogfooding round, 검증 실행

**내부 alpha (Internal alpha)**:
private 저장소 접근권이 있고 검증 표본의 앱 환경값을 직접 준비하는 maintainer가
실제 프로젝트에서 해당 플랫폼의 MVP/provider를 사용하는 단계다. iOS round는
초대된 RN iOS 개발자를 별도 표본으로 포함할 수 있지만, Private Phase 4A Android의
필수 표본은 SHA를 고정한 공개 OSS 실제 RN Android 앱 한 개다. maintainer 소유
프로젝트 검증은 후속 milestone이다. 외부 배포, 일반적인
React Native 지원 주장, Go 판정을 뜻하지 않는다.

**Alpha blocker**:
필수 증거·독립 실행·안전성·tracked 파일 무변경 중 하나를 깨뜨려 내부 alpha 완료를 막는 결함. 기록된 warning, 미관 문제, 초기 UI 이후의 프로젝트 고유 기능 문제는 포함하지 않는다.
_Avoid_: release blocker, Go/No-Go blocker

**Go blocker**:
Go round에서 잠긴 표본의 앱 UI 도달을 막는 `mobile` 결함. 표본 고유 문제와 사람의 host 준비 누락은 포함하지 않는다.
_Avoid_: Alpha blocker, release blocker

**검증 조합 (Validation tuple)**:
프레임워크·도구체인·플랫폼 런타임 버전을 함께 고정한 하나의 관측 단위다. 결과는 그 조합에만 귀속하며 더 넓은 버전 범위로 일반화하지 않는다.
_Avoid_: 지원 범위, 호환성 정책

**지원 범위 (Support envelope)**:
공식 근거와 누적된 검증 조합으로 설정한 지원 경계다. 하나의 로컬 검증 조합만으로는 성립하지 않는다.
_Avoid_: 검증 조합, tested on

**Known-good 표본 (Known-good sample)**:
고정된 프로젝트 revision이 같은 검증 조합에서 mobile 없이도 build·install·launch·초기 UI에 도달하고 tracked 파일을 바꾸지 않는 검증 표본이다. ADR-0018의 현재 iOS 게이트만 네 Pod checksum 값 재생성 예외를 적용한다. 다른 tracked byte는 같아야 한다. mobile SHA는 표본이 아니라 각 검증 실행에서 별도로 고정한다.
_Avoid_: clean repo, test project

**검증 결과 (Validation verdict)**:
고정된 검증 실행의 결과로, 전체 증거 체인이 성공하면 `validated`, known-good baseline 이후 동일한 mobile/toolchain 실패가 재현되면 `failed`, 결과를 귀속할 수 없으면 `inconclusive`다. 검증 조합에만 귀속하며 doctor의 Status나 지원 판정으로 일반화하지 않는다.
_Avoid_: support status, doctor status

**조사 실행 (Investigation run)**:
known-good 표본에서 `unknown`을 기록한 뒤 고정된 mobile SHA와 검증 조합으로 build·up·초기 UI까지 진행해 검증 결과를 얻는 실행이다. Internal alpha pass가 아니며 runbook이나 프로젝트 선언을 바꾸지 않는다.
_Avoid_: alpha exception, override run

**검증 실행 (Validation run)**:
project SHA·mobile SHA·검증 조합을 함께 고정한 한 번의 증거 수집이다. 하나라도 바뀌면 새 실행이며 기존 결과는 변경된 입력으로 승계하지 않는다.
_Avoid_: rerun, latest result

**표본 교체 (Sample replacement)**:
known-good baseline 전에 부적격 표본을 다른 프로젝트로 바꾸는 일이다. 검증 결과가 나온 뒤에는 교체하지 않고 추가 표본의 결과를 누적한다.
_Avoid_: retry, failed sample replacement

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

**출력 목적지 (Output sink)**:
자식 프로세스의 출력이 어디로 가는가 — `collected`(문자열로 모아 결과에 실어 돌려준다, 상한 있음) 또는 `streamed`(파일로 흘려보내고 메모리에는 한 줄만 남는다). 커맨드가 들고 다니는 **데이터**이고, 흘러가는 줄을 볼지 말지는 `run`의 콜백 파라미터라 커맨드는 순수한 값으로 남는다. 어느 줄이 의미 있는지는 목적지가 아니라 호출자의 지식이다 — `error:`가 중요하다는 것은 xcodebuild에 대한 앎이지 프로세스에 대한 앎이 아니다(ADR-0002).
_Avoid_: streaming 모드(무엇이 흐르는지가 아니라 어디로 가는지가 축이다)

**주목 줄 (Notable line)**:
흘러가는 출력 중 사람 화면에 끼워 넣을 만한 줄 — xcodebuild에서는 `error:`와 빌드 종료 줄. Stage가 판정하고, 실패 문장의 `observed`도 여기서 나온다(하나도 없으면 tail로 내려간다). 긴 빌드의 heartbeat는 이 목록과 별개로 최근 `(in target '…' from project '…')` 대상을 보여준다. 전체는 언제나 로그 파일에 남으므로 이 선별은 버리는 것이 아니라 **먼저 보여줄 것을 고르는** 일이다.

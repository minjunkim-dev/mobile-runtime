# #214 네이티브 iOS 고정 입력과 실행 증거

## 새 시도 04: 별도 배포 표현의 사전 pin과 native 2개 표본

2026-10-16의 새 시도 `source-baseline / AC05 / 20261016-04`에서 두 표본의 native build·install·launch·가림없는 첫 화면을 확인했다.
Runstir를 실행하지 않았다.
새 증거의 최종 독립 리뷰·필수 CI·티켓 완료 판정은 아직 남아 있다.
#214는 `OPEN`이다.
과거 시도 01~03의 archive checksum `unknown`과 전체 `inconclusive`는 그대로다.

| 표본 | 새 시도 04의 관측 |
| --- | --- |
| Food Truck `3954a769e99f3cc53297d94f2b960ceb2665b3d6` | native build·install·launch와 Truck·New Orders·Forecast 첫 화면 PASS. |
| NetNewsWire `aea7795bcc0698ced6f28eba53da886eb6217e64` | 첫 build exit65를 보존했다. 원래 generator의 명시 준비 후 build·install·launch PASS. 검정 화면과 popup 이력을 보존했다. 같은 설치 앱의 추가 launch에서 가림없는 Feeds·Smart Feeds·On My iPhone·Settings·Add 화면 PASS. |

Root가 두 최종 PNG를 직접 열었다.
Root는 작성자와 별도 컨텍스트다.
서로 다른 모델을 사용하지 않았다.
화면 확인은 최종 전체 diff 독립 리뷰를 대신하지 않는다.

| 새 기록 | 내용 |
| --- | --- |
| [tuple](source-baseline/AC05/20261016-04/tuple.json) | 첫 build 전 pin, source 4개, OS/arch, 선택, 서명, own device, lock·SPM·사람 준비. |
| [Apple prepin](source-baseline/AC05/20261016-04/apple-distribution-prepin.json) | App Store 서명 Xcode.app fulltree·seal·CDHash와 runtime Restore DMG SHA·엄격 서명·read-only same-FS binding. |
| [결과](source-baseline/AC05/20261016-04/results.json) | 표본·단계·시도별 결과와 남은 한계. |
| [명령 설명](source-baseline/AC05/20261016-04/commands.md) / [정확 argv](source-baseline/AC05/20261016-04/commands.json) | 정규화한 명령·환경·시각·종료 코드와 private 원본 명령 SHA. |
| [보존](source-baseline/AC05/20261016-04/source-preservation.json) | 새 source 4개·옛 원본 2개·bundle 4개·기존 기기 18대·앱 43개 비교. |
| [새 fresh clone 인계](source-baseline/AC05/20261016-04/fresh-clone-handoff.json) | 아직 사용하지 않은 별도 Runstir clone 2개와 NNW 원본 generator 준비. |
| [제한 원본 목록](source-baseline/AC05/20261016-04/private-evidence-index.json) | 비식별 공개 발췌와 원본 hash 연결. |

Apple prepin SHA256은 `93ad655b95b357fa489c92d49fa0ad0e7e6a55ba4cf70c8be25df31f9f1eac70`이다.
Root는 별도 Spec 검토의 남은 결함 0건을 확인한 뒤 새 실행을 승인했다.
Xcode `27.0 / 27A266a`의 `codesign --deep --strict`와 `spctl`은 exit0이다.
regular 파일 125,827개의 bytes와 mode·symlink를 fulltree로 고정했다.
MAS receipt 1개는 stat-only다.
resource seal과 다른 서명 제어 파일을 구분했다.
명시 resource 목록에 없다는 이유로 설치 후 추가 파일로 판정하지 않았다.
omitted `PkgInfo` 2개의 생성 시점과 출처는 `unknown`이다.

Runtime `27.0 / 24A434 / arm64`의 host Restore DMG는 8,067,000,161 bytes다.
SHA256은 `5136453f500b73dc3518f262d8a51e4be0c136e38a550998febf7759de6ba0fd`다.
엄격 서명 검증은 exit0이다.
그 정확한 DMG가 backing image인 read-only·unshadowed volume의 runtime bundle을 사용했다.
동일 filesystem 객체라는 연결을 확인했다.
두 plaintext tree를 별도로 전수 hash한 비교는 아니다.
읽을 수 없는 `modelmanagerd` 하위 경로는 inventory에서 제외했다.
catalog archive 8,053,150,208 bytes나 #206 guest export와 같은 원본 download라고 주장하지 않는다.
이 새 배포 표현을 원본 XIP/PKG·catalog archive checksum으로 바꾸어 부르지 않는다.
과거 unknown을 소급해서 해결하지 않는다.

NNW는 원래 기본 `com.ranchero.NetNewsWire.iOS-DEBUG`와 `NetNewsWire-iOS / Debug`를 사용했다.
옛 `org.runstir.baseline214` override를 사용하지 않았다.
#210의 Runstir artifact나 성공을 pure-native 증거로 옮기지 않았다.
후속 Runstir도 새 fresh clone에서 같은 선택을 별도로 검증해야 한다.

[Food PNG](source-baseline/AC05/20261016-04/food-truck-first-screen.png)와 [NNW 최종 PNG](source-baseline/AC05/20261016-04/netnewswire-unobscured.png)를 보존했다.
Food의 외장 경로 캡처와 stdout `-` 캡처 실패 2회를 남겼다.
같은 원래 launch PID에서 승인된 내부 staging으로 캡처했다.
TCC·권한·보안 설정을 바꾸지 않았다.
NNW V1의 generated source 누락·exit65와 V2의 [3초 검정 화면](source-baseline/AC05/20261016-04/netnewswire-v2-black.png)을 남겼다.
V3의 [10초·30초 popup 화면](source-baseline/AC05/20261016-04/netnewswire-v3-notification.png)도 계속 `inconclusive`다.
원래 `updateSecrets.sh` 명시 준비와 새 own DerivedData는 별도 V2 입력이다.
정확한 Xcode planning 인과는 확정하지 않았다.
generated ignored 출력은 random salt로 달라졌다.
hash와 생성 이력만 남겼다.
OAuth 값과 signing key를 공급하거나 공개하지 않았다.

최종 notification followup은 같은 설치 앱을 한 번 launch했다.
build·install을 반복하지 않았다.
앱 화면 입력·알림 버튼 입력·권한 변경 조작은 모두 0회다.
알림 authorization enum과 popup 재표시 부재 원인은 `unknown`이다.
popup 부재를 알림 거부 완료로 해석하지 않는다.
Root는 Device Hub의 sidebar 표시와 소유 row 선택을 사용했다.
관측 후 기존 선택 row와 sidebar 숨김 상태를 복귀했다.
다른 기기의 Start는 누르지 않았다.
전체 GUI preference bytes가 같다는 주장은 하지 않는다.

새 source 4개와 옛 원본 2개의 tracked bytes·mode·HEAD/tree·raw index·Git stage/flags가 각 pin과 같다.
Food/NNW built·installed bundle 4개의 기존 전체 manifest도 현재 bytes·mode·파일 목록과 같다.
Runstir fresh clone 2개에는 generator·의존성 준비·build·install·launch를 실행하지 않았다.
untracked·ignored·generated SecretKey·mobile.yml도 없다.
native 첫 단계와 별도 followup에서 각각 기존 기기 18대의 비교 diff는 `{}`다.
기존 Booted 기기의 앱 43개 전체 반환 metadata도 각 구간 전후 같다.
소유 앱 terminate exit0과 정확 PID 부재를 확인했다.
소유 Simulator shutdown exit0과 최종 `Shutdown`을 확인했다.
앱 userdata·HOME·전역 SDK/cache 전체 bytes 보존은 검증하지 않았다.

이 새 기록은 #214의 입력 고정·native 4단계·보존·fresh 인계에 연결한다.
AC05의 native baseline 선행 증거다.
Runstir CLI·GUI 후보 게이트는 미검증이다.
AC06의 도구 없는 기준 VM·Mac Android 가속·실기기를 이 기록으로 검증하지 않았다.
macOS 공식 하한 26.6과 실제 host 27.0.1 / `26A434` / `Mac16,8` / arm64를 구분한다.
macOS 26.6에서 실행하지 않았다.
Apple 로그인 요청 철회 상태를 유지한다.

## 과거 시도 01~03의 기록

명세: [#199](https://github.com/minjunkim-dev/mobile-runtime/issues/199).
티켓: [#214](https://github.com/minjunkim-dev/mobile-runtime/issues/214).
관측일: 2026-10-15~16, Asia/Seoul.

아래 과거 시도 01~03의 기록 당시 판정은 `inconclusive`다. 이 증거는 Runstir 없는 네이티브 iOS 조사 실행이다.
설치한 Xcode와 runtime의 원본 배포 archive checksum은 `unknown`이다.
설치 파일 또는 metadata의 checksum으로 원본 배포 archive checksum을 대체하지 않는다.
따라서 실제 앱 실행 성공이 있어도 전체 baseline을 `known-good`이나 `validated`로 판정하지 않는다.

최초 기록 key는 `source-baseline / AC05 / 20261015-01`이다.
첫 화면 보완 기록 key는 `source-baseline / AC05 / 20261016-03`이다.
출시 후보, CLI artifact, GUI DMG와 Core build identity는 이 조사 실행에 적용하지 않는다.
Runstir를 실행하지 않았으므로 이 증거는 CLI·GUI의 AC05 통과 증거가 아니다.

| 표본 | 고정 source | 현재 관측 |
| --- | --- | --- |
| 최소 역할 | Food Truck `3954a769e99f3cc53297d94f2b960ceb2665b3d6` | 실제 build·install·launch·첫 화면 확인. tracked 553개 파일의 원본 byte와 index 보존 확인. |
| 실제 OSS | NetNewsWire `aea7795bcc0698ced6f28eba53da886eb6217e64` | 시도 01의 명령 구성 실패와 시도 02의 팝업 이력을 보존했다. 시도 02의 native build 앱을 시도 03에서 재설치·실행했다. CUA로 가림 없는 Feeds 화면을 확인했다. tracked 1352개 파일과 index·lock을 보존했다. |

고정 입력은 [tuple.json](source-baseline/AC05/20261015-01/tuple.json)에 기록한다.
단계별 판정은 [시도 01](source-baseline/AC05/20261015-01/results.json)과
[시도 02](source-baseline/AC05/20261015-02/results.json),
[시도 03](source-baseline/AC05/20261016-03/results.json)에 기록한다.
명령과 수동 준비는 [commands.md](source-baseline/AC05/20261015-01/commands.md)에 기록한다.
실행자는 Codex의 #214 담당 컨텍스트다.
원본 로그와 기기 identity는 담당 maintainer의 제한 접근 저장소에 둔다.
[제한 원본 목록](private-evidence-index.json)에 원본 checksum과 접근 경계를 기록한다.
[별도 fresh clone 입력](fresh-clone-handoff.json)은 baseline clone과 분리했다.
공개 기록에는 기기 identity의 SHA-256만 남긴다.

## macOS 범위

[Apple 공식 Xcode 지원표](https://developer.apple.com/xcode/system-requirements/)의
Xcode 27 행은 macOS Tahoe 26.6 이상을 명시한다. 2026-10-15에 확인했다.
설치한 Xcode 27.0의 `Info.plist`도 `LSMinimumSystemVersion=26.6`을 명시한다.
실제 조사 host는 macOS 27.0.1 build `26A434`, `Mac16,8`, `arm64`다.
macOS 26.6에서 실행하지 않았다.
공식 실행 하한과 이번에 관측한 tuple을 구분한다.
Xcode 27.0을 macOS 27.0 하한으로 해석하지 않는다.

## 수용 기준 연결

| #214 수용 기준 | 근거와 남은 조건 |
| --- | --- |
| source·scheme·configuration·toolchain·runtime·앱·기기·사람 준비 고정 | `tuple.json`, `commands.md`. 원본 배포 archive checksum은 미확인이다. |
| macOS 하한과 실제 tuple 구분 | 위 공식 근거와 실제 host 관측. 하한 OS 실행은 미검증이다. |
| 두 표본의 build·install·launch·첫 화면과 source·기존 자원 보존 | `results.json`의 표본별 실제 결과를 사용한다. 미검증 단계를 성공으로 승격하지 않는다. |
| unknown·inconclusive·실패와 별도 fresh clone 인계 | 필수 unknown을 유지한다. Runstir 실행용 fresh clone은 baseline clone과 분리한다. |
| 명세 AC05·AC06 연결 | AC05의 사전 baseline 조사에만 해당한다. AC06의 기준 VM, 도구 없는 환경과 실제 Mac Android 가속을 검증하지 않았다. |

기존 iPhone 18 Pro에는 앱을 설치하지 않았다.
기존 기기의 종료·삭제·erase를 실행하지 않았다.
새로 만든 #214 전용 Simulator 한 대만 사용한다.
관측 뒤 전용 Simulator만 종료했다. 종료 명령은 exit 0으로 끝났다.
전용 기기의 최종 상태는 `Shutdown`이다. 기존 기기의 최종 상태는 `Booted`다.
기존 기기의 43개 앱 ID·버전·종류 inventory는 전후 같았다.
이 inventory 비교는 기존 앱 사용자 데이터 전체의 보존 증거가 아니다.
이 결과를 실기기, 다른 runtime, 새 Xcode, 지원 범위 또는 공동 출시 성공으로 일반화하지 않는다.

## NetNewsWire 첫 화면 보완: 시도 03

2026-10-16에 원래 시도 02의 native `.app`을 재사용했다.
실행파일 SHA·bundle metadata·170개 파일 수·35,094,448 bytes가 당시 기록과 같다.
원래 기록에는 전체 bundle 파일 manifest가 없다.
기록하지 않은 과거 resource byte의 동일성은 미확인이다.
이번 시도에서 수집한 전체 bundle manifest는 전후 같다.
재빌드와 Runstir 실행은 하지 않았다.

[가림 없는 Feeds 화면](source-baseline/AC05/20261016-03/netnewswire-feeds-unobscured.jpg)을 확인했다.
이번 시도에는 알림 팝업이 나타나지 않았다. 권한 선택도 하지 않았다.
이전 알림 선택 완료와 현재 authorization enum은 `unknown`이다.
원래 native app ID는 `org.runstir.baseline214.NetNewsWire.iOS-DEBUG`다.
#210 app ID인 `com.ranchero.NetNewsWire.iOS-DEBUG`와 다르다.
#210의 알림 거부나 앱 실행 결과를 이 증거로 사용하지 않았다.
이 증거를 #210의 동일 app ID·동일 tuple 게이트 완료로 일반화하지 않는다.
기존 전용 기기와 앱 데이터를 유지한 재실행이다.
새 기기나 새 사용자 데이터의 최초 실행을 검증하지 않았다.

15:45:11~15:46:58 UTC의 좁은 실행 구간에서 기존 43개 앱을 비교했다.
container 경로를 포함한 전체 `simctl listapps` 반환 metadata가 같다.
모든 Simulator의 state·name·type·availability·runtime 비교 결과도 같다.
source·index·lock·package pin·원래 artifact의 전후 hash가 같다.
기존 앱 사용자 데이터 전체 byte와 이 구간 밖의 변경은 검증하지 않았다.
전용 앱 종료와 전용 Simulator 종료는 모두 exit 0이다.
전용 앱 PID 부재와 최종 `Shutdown`을 확인했다. GUI/iOS lease를 반환했다.
명령·원본 hash·한계는 [시도 03 명령](source-baseline/AC05/20261016-03/commands.md)과 결과에 기록했다.

과거 tuple의 다음 확인에는 원본 Xcode·runtime 배포 checksum이 필요하다.
가림 없는 첫 화면 성공으로 이 필수 unknown을 대체하지 않는다.
#214를 완료로 표시하지 않았다.
Apple 로그인 요청 철회 상태를 유지했다.

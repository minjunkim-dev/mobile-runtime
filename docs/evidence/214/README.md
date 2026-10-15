# #214 네이티브 iOS 고정 입력과 실행 증거

명세: [#199](https://github.com/minjunkim-dev/mobile-runtime/issues/199).
티켓: [#214](https://github.com/minjunkim-dev/mobile-runtime/issues/214).
관측일: 2026-10-15~16, Asia/Seoul.

현재 판정은 `inconclusive`다. 이 증거는 Runstir 없는 네이티브 iOS 조사 실행이다.
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

다음 확인에는 원본 Xcode·runtime 배포 checksum이 필요하다.
가림 없는 첫 화면 성공으로 이 필수 unknown을 대체하지 않는다.
#214를 완료로 표시하지 않았다.
Apple 로그인 요청 철회 상태를 유지했다.

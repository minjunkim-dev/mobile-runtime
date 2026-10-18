# #206 새 VM GUI 준비 — 생성 성공·재검사·정상 종료

상태: `2026-10-18`의 새 GUI는 exact plan 승인 뒤 Simulator 생성 `succeeded / exit 0`을 표시했다.
재검사는 같은 runtime·기기의 `reuse`를 표시했다. 실제 GUI 종료 코드도 `0`이다.
최종 native 자원 비교·선택 자원 보존·export·VM 정상 종료도 확인했다.
실행 중 화면이나 관측 도구의 exit `0`을 준비 성공으로 바꾸지 않는다.

이 기록은 [새 CLI 설치 성공](actual-cli-6e19a33-resume.md) 뒤의 별도 GUI 실행이다.
CLI가 설치한 runtime을 재사용한다. GUI가 runtime을 새로 다운로드하거나 설치한 사례가 아니다.
`4dede50`의 [과거 GUI 기록](actual-vm-gui.md)과 `d4628c9`의 [설치 시도 취소](actual-runtime-d4628c9.md)도 별도 실행이다.

## 고정 입력과 공개 범위

| 항목 | 값 |
| --- | --- |
| 제품 source | `6e19a3329e0f983bcfda29c82f35f7ba489957b8` |
| 문서 시작 head | `a79b37899cdba842eb001b35d7adef7be7937fcc` |
| GUI 실행 파일 SHA-256 | `086bf3c215f2c954263462ecb37d8bcfc2f6b4ba557f00ce590cb9c80b0e9a75` |
| GUI bundle ID | `dev.runstir.validation206.runtime.6e19a33` |
| Food Truck source | `3954a769e99f3cc53297d94f2b960ceb2665b3d6`, tracked 파일 553개 |
| 선택 Xcode | `27.1 / 27A9275` |
| runtime | `27.0 / 24A434 / arm64`, 재사용 |
| 저장소 스크립트 신뢰 | `false` |
| GUI 소유 경로 | `<GUI_SOURCE>`, `<GUI_HOME>`, `<GUI_DEVICE_SET>` |

GUI는 CLI와 별도 HOME·device set을 사용한다.
source 복제본은 tracked 파일과 `.git`을 일반 복사했다.
현재 HEAD·tree·index·tracked blob 검증 범위만 따른다. 전체 과거 Git object graph 보존은 입증하지 않았다.
전용 bundle ID나 실행 파일 hash는 Developer ID·공증·Gatekeeper 배포 승인이 아니다.

비공개 증거 묶음 ID는 `206-runtime-resume-20261018`이다.
[정규화 JSON](actual-gui-6e19a33-resume.json)의 `receiptRefs`는 묶음 내부 상대 경로·bytes·mode·SHA-256을 연결한다.
원본 절대 경로·환경 값·Terminal history·원본 화면은 공개 자료에 넣지 않았다.
plan-id는 원본 값을 보존했다. 정규화한 경로로 다시 계산하지 않았다.

## 승인한 계획

계획 화면은 `needs-approval / exit 0`을 표시했다.
Root는 plan-id `35195c339bed74b4c8472f5b5b8f017eef6251094d24ad106654e23753727cfa`를 검토했다.
화면 `02`는 이 plan-id를 표시했다. 화면 `03`·`04`는 기존 runtime의 재사용과 exact identity를 표시했다.
화면 `05`·`06`·`07`은 다음 생성 범위를 표시했다. 작성자는 화면 `01`부터 `07`까지 원본을 직접 확인했다.

| 계획 항목 | 승인 범위 |
| --- | --- |
| runtime | `com.apple.CoreSimulator.SimRuntime.iOS-27-0`, build `24A434`, `arm64`, `reuse` |
| 자동 변경 | `ios.simulator.create` 1개 |
| 새 기기 이름 | `iPhone 18 Pro - Runstir - iOS 27.0` |
| 기기 종류 | `com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro` |
| 대상 | `<GUI_DEVICE_SET>` |
| recovery state | `<GUI_HOME>/Library/Caches/dev.runstir/ios-preparation` |
| 생성 경계 | boot하지 않는다. 기존 이름과 기기를 교체하지 않는다 |

`ROOT-plan-approval-v1.json`은 `01:41:00 UTC`의 검토와 클릭 전 승인 의도를 기록했다.
그 원본의 `executionStatus`는 `not-yet-clicked`다. 이 필드를 실제 클릭의 증거로 쓰지 않는다.
`ROOT-ui-observation-v1.json`은 `01:41 UTC`경 Root가 native GUI의 `현재 계획 승인·준비`를 정확히 1회 누른 사실을 기록했다.
Root는 `01:42 UTC` 화면에서 `ios.simulator.create running`을 관측했다.
이 실행 진입 화면의 원본 export는 없다. Root의 관측 영수증과 실행 중 프로세스 관측을 구분한다.
저장소 스크립트 신뢰·runtime 다운로드·기존 자원 삭제·기기 boot·앱 build/install/launch는 이 승인 범위에 없다.

## GUI 완료·재검사·프로세스 종료

| 원본 관측 | 직접 확인한 범위 | 입증하지 않는 범위 |
| --- | --- | --- |
| `05-launch/stdout`, `01:11:24 UTC` | GUI PID `4126`, launcher PID `4124`, 실제 kernel 경로의 실행 파일 hash 일치, 선택 환경 12개 일치 | 준비 완료·전체 과거 자식 프로세스 부재 |
| `06-plan/stdout`, `01:22:26 UTC` | 같은 GUI PID·실행 파일 hash·선택 환경 유지, 당시 관측 자식 0개 | 이후 승인·변경의 결과 |
| `07-checkpoint/stdout`, `01:41:56 UTC` | 같은 GUI PID와 `xcodebuild` PID `4611`을 직접 자식으로 관측 | Simulator 생성 완료·operation exit·자식 정상 종료 |
| 세 관측 도구의 `exit.json` | 관측 도구가 각각 exit `0` | GUI·준비 작업의 종료 코드 |
| Root의 후속 화면 관측 | exact plan 1회 승인 후 `ios.simulator.create running` | 성공·재검사·최종 보존 |
| 화면 `08`, `01:46 UTC` | `setup: succeeded / exit 0`, `ios: succeeded`, 완료 변경 `ios.simulator.create` | 앱 build·install·launch |
| 화면 `09`, `01:47 UTC` | 실행 없는 재검사 `needs-approval / exit 0`, runtime·device `reuse`, 남은 작업 줄 없음 | 새 승인·재실행 성공 |
| 화면 `10`와 `08-after-quit/stdout` | native 앱 메뉴 종료 뒤 창 부재, 실제 GUI exit `0`, 관측했던 자식 잔존 0개 | 관측하지 못한 과거·reparented 자식의 부재 |

관측 도구는 `controlActions: 0`, `GUIPlanApproveInstallActions: 0`을 기록했다.
이는 관측 도구가 GUI 승인을 수행하지 않았다는 뜻이다. Root의 별도 native GUI 승인을 부정하지 않는다.
자식 목록은 각 관측 시점의 트리다. 이전에 관측하지 못했거나 부모가 바뀐 자식의 부재는 입증하지 않는다.
승인 뒤 흰 화면 캡처가 발생했다. 이 캡처만으로 성공·실패·crash를 판정하지 않는다.

화면 `08`의 완료 후 관측 plan-id는 `85092bdc78f11ef97c22637a49d4881801a3b42774f23e4c9067369a60433d97`다.
원래 승인한 `35195c…`와 구분한다. 새 기기 관측이 포함된 결과 계획이다.
화면은 GUI 소유 기기 `F89B51CB-943C-48EA-A280-E0A6D45B7548`의 `Shutdown` 상태를 표시했다.
runtime은 계속 `27.0 / 24A434 / arm64`의 `reuse`다.
Root는 `준비 계획 확인`을 다시 1회 눌렀다.
화면 `09`는 같은 결과 plan-id와 같은 기기의 `reuse`를 표시했다.
`needs-approval / exit 0`은 공통 inspection 상태다. 이를 새 실행의 성공으로 부르지 않는다.

Root는 `01:47 UTC` native 앱 메뉴의 종료를 눌렀다.
`08-after-quit/stdout`의 launcher 영수증은 GUI PID `4126`의 실제 exit `0`을 `01:47:37 UTC`에 기록했다.
그 관측은 `GUIAbsent: true`, 현재 자식 0개, 이전에 관측한 자식 잔존 0개를 기록했다.
종료 뒤 `environmentExact: false`는 GUI가 없어 선택 환경이 빈 상태임을 나타낸다.
이를 실행 중 환경 불일치로 바꾸지 않는다.

## 최종 native 자원과 보존

최종 export는 원본 58개·6,773,037B다.
작성자는 원본 58개를 bytes·mode·SHA-256으로 다시 검증했다. 불일치는 0개다.
작성자는 완료·재검사·종료 화면 `08`·`09`·`10`의 원본도 직접 확인했다.
INDEX는 10,536B이며 SHA-256은 `957620e1093a11587ba097630a13ec69c0f69c1ea83531a4d20663fddc348efc`다.
이 수치는 다른 CLI·과거 export와 겹칠 수 있으므로 합산하지 않는다.

`ROOT-final-audit-v1.json`과 before·after 원본을 별도로 읽었다.
after의 선택 검사 19개는 모두 true다. 작성자는 다음 원본 비교도 다시 수행했다.

| 비교 대상 | 직접 재검증한 결과 | 범위 |
| --- | --- | --- |
| before·after 공통 14개 key | 전부 동일 | original/new source, SDK, tools, old candidate·plan 영수증·preparation state, 이전 CLI의 named 경로, GuestAgent·launchctl PATH, global Xcode 선택, xcode-select, runtime·managed runtime |
| source | 각각 tracked 553개·index·상태·설정 SHA 동일 | `?? mobile.yml`은 준비 전부터 존재했다. GUI가 새로 만든 변경이 아니다 |
| `mobile.yml` | SHA-256 `bc5d87ed00dca889de5f3fe132693a2929f67f6e5bfc669e2065c70f8e1ba9f4` 동일 | 원본·새 source의 준비 입력 |
| GUI candidate | 준비 때 고정한 파일 map 28개와 최종 map 동일 | before에 없던 새 candidate를 전부터 존재한 파일처럼 비교하지 않는다 |
| 이전 CLI 검증 경로 | named source 2개·candidate·attempts·소유 device tree 동일 | 전체 이전 HOME나 전체 root 보존이 아니다 |
| runtime·managed runtime | native 명령의 전체 JSON 동일 | 기존 iOS `27.0/24A434/arm64`를 재사용했다 |
| admin 기본 device set | `exists`·`path`·`devices` 동일. native 명령의 전체 JSON도 동일 | 기기 2개다. receipt의 timestamp·scope 문구는 비교 대상이 아니다 |
| 새 GUI device set | 빈 상태에서 정확한 기기 1개로 변경 | `F89B51CB-943C-48EA-A280-E0A6D45B7548`, exact 이름·종류·runtime, `Shutdown`, available |
| recovery journal | 디렉터리는 존재하며 entries는 0개 | 완료 뒤 상태다. 과거 취소 journal과 구분한다 |
| 선택 admin HOME | `Library/Caches`의 mtime만 달랐다 | bytes·mode는 같았다. 변경 actor는 unknown이다 |

기본 기기와 runtime의 전체 JSON 동일은 이 GUI 실행의 before·after 범위다.
CLI 설치 전후의 기본 기기는 identity·name·type·runtime·state 비교였다는 별도 범위를 유지한다.

## VM 종료와 보호 대상

`stop-after-gui-01`의 실제 exit는 `0`이다.
이 VM을 시작했던 `boot-install-02` 프로세스의 실제 exit도 `0`이다.
Root는 최종 시점에 테스트 VM과 보호 VM 2개가 모두 stopped임을 확인했다.
작성자는 제거 준비 전과 GUI stop 뒤의 `VMs` map 전체가 같은지 직접 비교했다.
보호 대상 2개의 작은 metadata 파일 SHA와 `overlay.asif` disk stat은 모두 같았다.
이 비교는 전체 VM disk hash가 아니다. 전체 disk 보존이나 실행 중 모든 순간의 동일성을 입증하지 않는다.

## AC 연결과 남은 gate

| 요구 범위 | 이 GUI의 판정 | 별도 근거 또는 한계 |
| --- | --- | --- |
| #206 runtime 설치 | 이 GUI는 `reuse` | 실제 설치 성공은 새 CLI 기록에 있다. payload 전송 자체는 그 기록에서도 미증명이다 |
| #206 GUI 계획·승인 | exact 계획 화면·Root의 1회 승인 영수증·완료 화면 `08` 연결 | 재검사 `09`는 새 실행 성공이 아니다 |
| #206 Simulator 생성 | `succeeded / exit 0`, 새 UDID·Shutdown·available·exact runtime/type/name 확인 | 기기를 boot하거나 앱을 실행하지 않았다 |
| #206 기존 자원 보존 | 위 표의 선택 자원·전역 선택·기존 기기·runtime 비교 완료 | 전체 HOME·cache·disk 동일성이 아니다 |
| #199 AC02·AC03·AC06 | GUI 생성·재검사·보존·정상 종료를 연결했다 | [통합 근거표](actual-runtime-d4628c9.md#ac별-근거)의 과거 취소·fixture·새 CLI 근거와 구분한다 |
| 수명주기 | GUI 실제 exit `0`, 관측 자식 잔존 0개, export 58개 일치, VM stop·boot 프로세스 exit `0` | 관측하지 못한 자식·daemon의 부재는 입증하지 않는다 |

이 GUI에서 whole HOME·cache·disk 보존은 입증하지 않았다.
cache metadata가 바뀌어도 행위자를 추정하지 않는다.
과거 검증 VM 9개의 삭제로 과거 guest 전체 로그를 다시 복구할 수 없다는 한계는 유지한다.
새 baseline과 새 실행은 과거 증거의 빈칸을 채우지 않는다.

공개 manifest는 최종 CLI·GUI 요약 8개의 bytes·mode·SHA-256을 고정한다.
최종 독립 리뷰·필수 CI·위험별 승인·병합·main CI를 완료로 표시하지 않는다.

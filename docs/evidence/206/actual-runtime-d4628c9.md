# #206 runtime 설치 시도 취소와 후속 검증 입력

`d4628c9`의 실제 CLI·GUI는 runtime 설치 시도 취소 `130`을 반환했다.
재검사는 정확한 `iOS 27.0 / 24A434 / arm64`의 수동 복구를 안내했다.
이 두 실행은 payload 성장을 관측하지 못했다. 중간 다운로드 취소와 네트워크 전송은 `inconclusive`다.
runtime 설치·Simulator 생성·자동 재시도 성공으로 표시하지 않는다.
새 baseline의 `6e19a33` CLI 설치·생성 성공은 [별도 기록](actual-cli-6e19a33-resume.md)에 연결했다.
그 성공으로 과거 취소 실행의 미확인 범위를 덮어쓰지 않는다.

[공개 JSON](actual-runtime-d4628c9.json)은 제한 원본을 bundle ID·상대 경로·bytes·mode·SHA256으로 연결한다.
개인 host·guest 절대경로, raw 환경, Terminal 이력과 화면은 공개하지 않았다.
표시용 `<SOURCE>`, `<OWN_HOME>`, `<DEVICE_SET>` 별칭은 원본 bytes가 아니다.
실제 plan ID는 원본 경로와 관측 입력으로 계산했다.

## source와 입력 구분

| 구분 | 고정 입력과 범위 |
| --- | --- |
| 과거 재사용·생성 | `4dede50eeca35ad59307c779160bf988a6e4bee1`. [기존 기록](actual-vm-gui.md)에 당시 성공·실패·한계를 보존한다. |
| 이번 취소 실측 | source `d4628c9615d06ac7ae95813d0e0f2ca7795bdf54`, tree `afc62b0671ea3b3b2bb2b46fe8529dd7d3ca9fe3`. CLI와 GUI는 서로 다른 runtime 없는 VM clone을 사용했다. |
| 현재 통합 후보 | head `6e19a3329e0f983bcfda29c82f35f7ba489957b8`, base `3211df5ac08168bcd3b7848f13c37ff40c7cd185`. `Sources/`, `Tests/`, `Package.swift`, `Package.resolved`는 d4628c9와 blob이 같다. |
| 새 검증 입력 | 별도 보존 baseline clone·Xcode `27.1/27A9275`. 같은 `6e19a33` CLI의 설치·생성 성공은 별도 기록이다. 새 GUI와 최종 lifecycle은 미확인이다. |

d4628c9의 Food Truck source는 `3954a769e99f3cc53297d94f2b960ceb2665b3d6`이다.
기존 source와 별도 검증 source는 각각 tracked 553개를 비교했다.
선택 scheme은 `Food Truck`이다. child HOME·device set·임시 경로를 분리했다.
기존 Xcode `27.0/27A266a`와 기존 다른 runtime 3개를 보존 대상으로 삼았다.

| 실측 파일 | SHA256 |
| --- | --- |
| d4628c9 CLI | `0323e9ab6bb6551887004afdf4a5995e8e4d7e0d173d69fd0e17bddb4e6eef36` |
| d4628c9 검증 GUI | `5dd99544cf875998edfb15acaec33c2f9daf588865900c1b05c0c165da58016f` |

GUI는 전용 bundle ID와 local ad hoc 서명을 사용했다.
새 통합 후보의 GUI bundle을 실제 실행했다고 바꾸어 기록하지 않는다.
제품 source blob 동일성은 배포 서명·공증·Gatekeeper 검증이나 실제 설치 성공을 뜻하지 않는다.

## 승인한 runtime과 실제 CLI

승인한 runtime은 `27.0 / 24A434 / arm64`다.
asset ID는 `93b56b3a-f17c-5f56-937e-b66a83688c43`이다.
catalog의 크기는 8053150208B다. 실제 수신 payload 크기가 아니다.
[Apple catalog](https://devimages-cdn.apple.com/downloads/xcode/simulators/index2.dvtdownloadableindex)의 SHA256은 아래와 같다.

```text
aa2e0518b95223f8de060d00c29cdefcca54389d9250f369521f60428b5ae322
```

이 SHA256은 metadata identity다. payload checksum은 공개되지 않았다.
runtime 저장 parent는 `/Library/Developer/CoreSimulator`다.
Simulator 생성 목적지는 소유 `<DEVICE_SET>`이다.
정규화한 실제 설치 명령은 아래와 같다.

```text
xcodebuild -downloadPlatform iOS -buildVersion 27.0 -architectureVariant arm64
```

| CLI 단계 | 관측 |
| --- | --- |
| 승인 계획 | plan `a05b267b7d60a0d5b7c385862b9ce59042b945f5d60a0f527fc2a5909cac4452`에 exact runtime과 기기 생성 조건을 고정했다. |
| 설치 시도 | 소유 CLI 아래의 exact Xcode child를 관측했다. 600초 동안 payload 성장을 관측하지 못했다. |
| 취소 | exact 소유 CLI PID에 SIGINT 1회를 보냈다. 실제 CLI는 `cancelled / exit 130`, completed `[]`, changedFiles `[]`를 반환했다. runtime 자원은 `unknown`이다. |
| harness 결과 | `accepted:false`, `downloadObserved:false`, `networkTransferVerified:false`다. 외부 harness transport exit `1`과 제품 exit `130`을 구분한다. |
| 재검사 | plan `07941cd363a4913574ab83cbe75e88193e7cea79e09dcd4e82bf6490536ce4f3`은 `needs-approval / exit 0`이다. 자동 설치·생성은 0개다. exact runtime의 `ios.resources` 수동 복구를 표시했다. |

취소 뒤 목표 runtime은 없었다. 소유 device set의 기기는 0개였다.
관측한 소유 프로세스 잔여는 0개였다. 미관측·reparented child 전체의 부재를 뜻하지 않는다.
recovery journal 1개의 hash metadata를 보존했다. raw journal bytes는 export하지 않았다.
journal 삭제·재작성, 새 승인·설치 재시도, 수동 설치는 수행하지 않았다.
수동 안내를 자동 복구 완료로 표시하지 않는다.

## 실제 GUI와 수동 재검사

GUI는 같은 runtime tuple과 소유 device set을 표시했다.
exact plan `de882afcf40f174c7e54d7a62128a6a82b6224424e11978e5c8f87612e285df4`를 승인했다.
repository trust는 false였다.
공식 catalog pin·목적지 화면, 소유 Xcode child와 별도 승인 영수증을 함께 연결했다.
흰 화면인 원본 14번은 승인 증거에서 제외한다.

GUI는 `ios.runtime.install: running`을 표시했다.
payload 성장과 네트워크 전송은 관측하지 못했다.
GUI 작업 취소 1회 뒤 `setup: cancelled / exit 130`을 표시했다.
설치 성공과 Simulator 생성 성공은 입증하지 못했다.

재검사 plan은 아래와 같다.

```text
e64c51b46933941451af5f107bec8d694522b7a4c770d2a3f88312954e966dcd
```

재검사는 `needs-approval / exit 0`과 iOS `waiting-manual`을 표시했다.
`ios.resources`는 `iOS 27.0 build 24A434 arm64`의 unresolved system state를 표시했다.
선택한 Xcode의 Components·Simulator 상태를 먼저 확인하도록 안내했다.
수동 설치를 완료한 뒤 다시 검사하도록 안내했다.
journal과 기존 자원을 보존했다. 자동 설치·생성 재시도는 수행하지 않았다.

## 보존과 정상 종료

| 경로 | 확인 범위 |
| --- | --- |
| CLI 취소 | named 검사 18개가 true다. source·SDK·도구·후보·이전 근거·기존 runtime·기본 기기 목록·기존 journal metadata를 비교했다. 목표 runtime 부재와 소유 기기 0개를 확인했다. |
| GUI 마감 | named 검사 17개가 true다. source·SDK 10434 entries·도구·후보 28개·기존 runtime 3개·기본 device set·GuestAgent PATH·launchctl PATH·전역 Xcode 선택의 기록 범위를 확인했다. 목표 runtime과 소유 기기는 없었다. |
| CLI lifecycle | 정상 VM stop과 원 boot process가 각각 exit `0`이다. 보호 VM 6개의 작은 metadata SHA·disk stat이 timestamp를 제외하고 같다. |
| GUI lifecycle | 메뉴 정상 종료 뒤 실제 GUI child exit `0`을 회수했다. GUI와 관측 child가 없었다. 정상 VM stop과 원 boot process가 각각 exit `0`이다. 보호 VM 7개의 작은 metadata SHA·disk stat이 timestamp를 제외하고 같다. |

source·SDK·도구·이전 근거의 해당 원본 snapshot을 다시 비교했다.
GUI 후보 28개는 준비 전 부재와 최종 manifest 대조를 구분한다. 준비 전과 파일이 같다는 뜻이 아니다.
CLI의 xcode-select 비교는 pinned child 환경이다. 모든 전역 Xcode preference가 같다는 뜻이 아니다.
GUI는 DEVELOPER_DIR를 제거한 전역 선택 관측도 비교했다.

두 경로에서 선택한 admin HOME의 `Library/Caches`와 `Library/Developer/Xcode` metadata가 바뀌었다.
변경 actor·원인은 unknown이다. 전체 HOME·cache·임시 경로·VM disk bytes의 동일성은 입증하지 않았다.
GUI 최종 VM snapshot 9개는 당시 기록이다. 현재 VM 목록으로 사용하지 않는다.

## 진단과 후속 입력의 한계

과거 소유 Xcode child는 MobileAsset Future 완료를 기다리는 stack을 보였다.
이 stack만으로 deadlock·계정 문제·권한 문제·네트워크 실패를 확정하지 않는다.
당시 daemon log 426270B 중 262144B만 보존했다.
파싱 가능한 구간은 `12:23:53.302862–12:23:54.401848 UTC`다.
전체 설치 시도의 daemon log를 확보했다고 주장하지 않는다.

Root는 과거 검증 VM 9개의 삭제로 guest를 다시 열 수 없다고 보고했다.
host export·화면·snapshot 원본은 남아 있으며 이번에 hash를 확인했다.
과거 전체 daemon log의 누락은 새 baseline의 로그로 소급 보완할 수 없다.

새 검증은 별도 보존 baseline의 clone과 Xcode `27.1/27A9275`를 사용한다.
시험 입력에서 iOS runtime이 없는 상태를 별도로 준비했다.
제거 감사는 실제 제거 명령 2개의 exit `0`과 별도 최종 inventory를 연결한다.
준비 도중 이미 사라진 unusable image 1개의 변경 actor는 unknown이다.
이 준비를 Runstir 설치나 과거 journal의 복구 성공으로 세지 않는다.

새 CLI의 exact plan은 `928507946c7ea83273d8c1c40051a300d3edf1d42dcd3a4839c9050559c7f226`이다.
승인 대상은 `ios.runtime.install`과 `ios.simulator.create`다. repository trust는 false다.
이 문서는 준비·승인 영수증과 preflight export 102개를 연결한다.
[후속 CLI 기록](actual-cli-6e19a33-resume.md)은 실제 설치·생성 성공과 최종 CLI 보존 감사의 export 244개를 연결한다.
새 GUI와 최종 GUI·VM 정상 종료는 아직 미확인이다.
Apple daemon의 요청·시작·초기 progress 메시지도 payload bytes·전체 네트워크 전송 완료의 증거로 바꾸지 않는다.

## AC별 근거

[#206](https://github.com/minjunkim-dev/mobile-runtime/issues/206)의 현재 수용 기준과 [#199](https://github.com/minjunkim-dev/mobile-runtime/issues/199)의 Testing Decisions를 기준으로 구분한다.
공통 실패·조건 변경 분기는 fixture로 검사한다. 실제 설치·자원 변경 요구는 별도 실측으로 검증한다.

| #206 조건 | 연결한 근거 | 남은 근거·한계 |
| --- | --- | --- |
| AC1 OS·architecture·artifact·재사용 | CLI plan·GUI 화면의 exact tuple·asset·catalog identity. 과거 4dede50의 기존 runtime·기기 reuse. `catalogPin`, `invalidCatalog`, `capturedReuse`, `renamedDevice` 자동 검사 | d4628c9의 실제 runtime 설치 성공은 없다. 새 6e19a33 CLI의 성공은 별도 기록이다. 새 GUI 결과는 미확인이다. |
| AC2 이름 충돌·생성 identity·실제 상태 | `nameCollision`, `creationSelection`, `approvedCreation` 자동 검사. 과거 후보와 새 6e19a33 CLI의 실제 UDID·Shutdown 결과는 각 기록에 고정 | d4628c9 취소 실행은 새 기기 0개다. 새 GUI 생성 결과는 아직 미확인이다. |
| AC3 수동 Xcode·계정·라이선스·전역 선택 | 취소 후 exact runtime 수동 안내·기존 자원 보존. GUI의 전역 선택 관측. 과거 잘못된 child Xcode 경로와 수동 안내 | 계정이 원인이라는 증거는 없다. 로그인·라이선스·관리자 자동 승인은 수행하지 않았다. |
| AC4 CLI·GUI 실패·취소·재실행·보존 | d4628c9 양쪽 설치 시도 취소130·manual-only 재검사·보존·정상 종료. `runtimeRecovery`, `creationRecovery`, stale·lease fixture. 과거 후보의 실제 journal 쓰기 실패·복구 이력 | payload가 증가하는 중간 다운로드 취소는 inconclusive다. 수동 복구·자동 재시도 성공은 없다. 실제 Mac doctor 실패와 VM 결과를 구분한다. |
| AC5 / #199 AC02·AC03·AC06 | 아래 구분과 원본 manifest로 연결한다. fixture·문서 PASS를 실제 설치로 바꾸지 않는다. | 새 GUI와 최종 lifecycle, 최종 문서의 독립 리뷰·필수 CI·사람 승인·병합·main CI가 남았다. |

| #199 조건 | 현재 연결 | 미확인 범위 |
| --- | --- | --- |
| AC02 준비 | 실제 기존 자원 reuse 이력, exact 설치 계획·승인, d4628c9 취소 결과와 남은 수동 단계. 새 6e19a33 CLI의 설치·생성 성공은 별도 기록 | 새 GUI 결과와 최종 lifecycle |
| AC03 복구·조건 변경·보존 | 실제 취소130·journal 보존·manual-only 재검사와 named 자원 비교. 공통 stale·충돌·실패 fixture | 중간 payload 취소·전체 전송, 실제 unresolved 상태의 수동 복구 완료·자동 재시도 성공 |
| AC06 VM과 실제 Mac | 보존 기준 VM clone, 서로 다른 Xcode tuple과 별도 실행 identity. 실제 Mac sandbox doctor 실패 이력. 새 baseline의 CLI 성공·보존 범위는 별도 기록 | VM 성공을 실제 Mac 결과로 일반화하지 않는다. 새 GUI·VM 마감은 미확인이다. |

표의 미확인 범위를 모두 새 필수 실측으로 추가하지 않는다.
각 조건의 공통 fixture·실제 위험 경계·성공 설치 요구를 구분해서 최종 판정한다.

## 원본 재검증

CLI 최종 INDEX의 내부 221개와 외부 근거 91개를 bytes·mode·SHA256으로 확인했다.
GUI 최종 INDEX의 내부 193개와 외부 진단 28개도 확인했다.
CLI export 185개·18223201B와 GUI export 55개·5722131B를 별도로 확인했다.
CLI stage1 원본 archive의 파일 55개·6203122B도 저장된 receipt와 bytes·mode를 대조했다.
준비 INDEX 18개·9개와 새 preflight export 102개·8365106B를 확인했다.
불일치는 0개다. 이 수치는 서로 겹치므로 고유 파일 수로 합산하지 않는다.
GUI 원본 화면 11·16·17을 직접 읽었다. 공개 JSON은 화면 identity만 담는다.
원본 receipt와 실패 이력을 수정하지 않았다.

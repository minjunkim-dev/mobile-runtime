# #206 6e19a33 실제 CLI runtime 설치·Simulator 생성

새 검증 입력의 CLI가 `succeeded / exit 0`을 반환했다.
승인한 `ios.runtime.install`과 `ios.simulator.create`를 모두 완료했다.
별도 native inventory에서 정확한 runtime과 새 소유 Simulator를 확인했다.
후속 [GUI 기록](actual-gui-6e19a33-resume.md)은 별도 device set의 생성·재검사·보존과 GUI·VM 정상 종료를 연결한다.
환경 준비 성공을 앱 build·install·launch·첫 화면 성공으로 표시하지 않는다.

[공개 JSON](actual-cli-6e19a33-resume.json)은 제한 원본을 identity와 hash로 연결한다.
[과거 d4628c9 취소 기록](actual-runtime-d4628c9.md)의 `inconclusive` 결과는 그대로 유지한다.
새 성공은 별도 baseline·Xcode tuple의 별도 operation이다. 과거 journal의 복구 성공이 아니다.
개인 절대경로와 환경값은 별칭으로 바꿨다. raw 로그·Terminal 이력·화면은 공개하지 않았다.

## 고정 입력과 승인

| 항목 | 값 |
| --- | --- |
| 제품 source | `6e19a3329e0f983bcfda29c82f35f7ba489957b8` |
| source base | `3211df5ac08168bcd3b7848f13c37ff40c7cd185` |
| CLI SHA256 | `0323e9ab6bb6551887004afdf4a5995e8e4d7e0d173d69fd0e17bddb4e6eef36` |
| 프로젝트 | Food Truck `3954a769e99f3cc53297d94f2b960ceb2665b3d6`, tracked 553개, scheme `Food Truck` |
| 선택 Xcode | `27.1/27A9275` |
| 준비 입력 | 별도 보존 baseline clone. 준비 뒤 iOS runtime 0개, 소유 device set 기기 0개 |
| 승인 | `928507946c7ea83273d8c1c40051a300d3edf1d42dcd3a4839c9050559c7f226`, repository trust false |

runtime은 `iOS 27.0 / 24A434 / arm64`다.
asset ID는 `93b56b3a-f17c-5f56-937e-b66a83688c43`이다.
catalog 크기는 8053150208B다. catalog SHA256은 아래와 같다.

```text
aa2e0518b95223f8de060d00c29cdefcca54389d9250f369521f60428b5ae322
```

[Apple catalog](https://devimages-cdn.apple.com/downloads/xcode/simulators/index2.dvtdownloadableindex)의 SHA는 metadata identity다.
payload checksum은 공개되지 않았다. 선택한 Xcode가 Apple 관리 설치를 수행했다.
준비 단계의 runtime 제거·누락 actor 한계는 [입력 기록](actual-runtime-d4628c9.md#진단과-후속-입력의-한계)에 남겼다.
그 준비를 Runstir의 설치 결과로 세지 않는다.

## 실제 결과

| 항목 | 관측 |
| --- | --- |
| 실제 CLI | PID `1549`, exit `0`, 924.697초, signal 0회, 관측 deadline 미도달 |
| operation | `E5974EF3-D9C4-4BD0-BB49-2E5D821206A8`, `succeeded`, completed 2개, manual 0개, remaining 0개, changedFiles `[]` |
| runtime | `com.apple.CoreSimulator.SimRuntime.iOS-27-0`, `27.0/24A434/arm64`, available, origin `installed` |
| Simulator | `A1737367-A44D-4996-B5E7-F72561FACB1B`, `iPhone 18 Pro - Runstir - iOS 27.0`, type `com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro`, `Shutdown`, available, origin `created` |
| 설치 후 계획 | `e67e4d209bd7a0bc6e08b1a041dda29cdfdccbd1db93999dea05ddf610ae567c`, iOS `succeeded` |

승인 ID와 결과의 재관측 plan ID를 구분한다.
완료 뒤 계획은 설치된 runtime과 새 기기의 관측 identity를 담는다.
결과 ID가 바뀐 사실을 stale 승인으로 다른 mutation을 실행했다는 뜻으로 해석하지 않는다.
제품은 준비 완료와 앱 build·launch의 별도 검증을 명시했다.
Simulator를 boot하거나 앱을 실행하지 않았다.

## 독립 native·보존 비교

operation 출력만으로 성공을 판정하지 않았다.
export한 전후 native inventory를 다시 비교했다.

1. 기존 runtime record 3개가 설치 뒤에도 전체 record와 같다.
2. 정확한 iOS `27.0/24A434/arm64` available record가 1개 추가됐다.
3. 기본 device set의 기기 2개는 UDID·이름·type·runtime·state가 같다.
4. 소유 device set은 0개에서 정확한 새 UDID 1개가 됐다.
5. source·SDK·도구·후보·GuestAgent PATH·Xcode 선택·Xcode version의 snapshot 8개가 같다.

source 비교는 원본과 새 clone 각각 tracked 553개와 index·stage·flags·상태의 기록 범위를 포함한다.
같은 snapshot 8개는 설치 뒤와 최종 CLI after 단계에서도 같다.
설치 harness의 검사 16개와 최종 CLI after 검사 12개는 모두 true다.
관측한 소유 child 잔여는 0개다. journal entry·stage 잔여도 없다.
이는 미관측 daemon·reparented child 전체의 부재를 입증하지 않는다.

선택한 admin HOME에서 다음 root의 metadata가 바뀌었다.

- `Library/Caches`
- `Library/Developer/Xcode`
- `Library/Developer/CoreSimulator/Devices`

변경 actor는 unknown이다. 기본 기기 2개의 identity·state 보존과 root mtime 동일성을 구분한다.
전체 HOME·cache·임시 파일·VM disk bytes의 보존으로 확대하지 않는다.

## 설치와 네트워크 전송의 증거 구분

실제 Xcode 설치 완료와 exact native runtime availability를 확인했다.
소유 Xcode writable 파일의 payload 성장은 관측하지 못했다.
payload의 전체 네트워크 전송과 bytes·checksum은 독립 입증하지 못했다.
이 한계를 다운로드 실패 또는 설치 실패로 바꾸지 않는다.
반대로 설치 성공을 전체 payload 전송을 관측했다는 주장으로 확대하지 않는다.
Apple daemon의 request·started·초기 progress 메시지도 전체 전송 완료를 뜻하지 않는다.

## AC 연결과 남은 gate

| 조건 | 이 CLI가 추가한 근거 | 남은 범위 |
| --- | --- | --- |
| #206 AC1 | exact plan 승인 뒤 실제 runtime 설치. native OS build·architecture·availability 대조. 후속 GUI의 같은 runtime reuse | catalog SHA와 payload checksum을 구분한다. GUI reuse는 새 runtime 설치가 아니다. |
| #206 AC2 | 새 소유 기기의 actual UDID·type·runtime·Shutdown 상태와 기존 기본 기기 2개의 identity·state 보존 | 이름 충돌 분기는 공통 fixture다. 기존 기기를 덮어쓰는 실험은 추가하지 않았다. |
| #206 AC3 | repository trust false, 고정 Xcode 선택·version snapshot 보존. 계정·라이선스·관리자 자동 행동 없음 | 전체 전역 preference 불변이나 실제 계정 상태를 주장하지 않는다. |
| #206 AC4 | 별도 runtime 없는 입력의 설치·생성 성공. 과거 CLI·GUI 취소130·manual 재검사와 후속 GUI 생성·재검사·보존·정상 종료를 함께 연결 | 과거 중간 payload 취소는 여전히 inconclusive다. 과거 unresolved journal의 복구 성공을 주장하지 않는다. |
| #206 AC5 / #199 AC02·AC03·AC06 | 실제 설치·생성, 승인 범위, 보존 비교와 VM tuple을 연결한다. fixture를 실제 설치로 대체하지 않았다. | 통합 문서의 독립 리뷰·최종 head 필수 CI·사람 승인·병합·main CI를 남긴다. 실제 Mac 결과로 일반화하지 않는다. |

새 GUI의 최종 export·native 비교·GUI exit `0`·VM stop과 boot 프로세스 exit `0`은 별도 GUI 기록의 원본을 따른다.
이 기록은 티켓 완료·출시 완료를 선언하지 않는다.

## 원본 확인

export INDEX의 244개·90680502B를 bytes·mode·SHA256으로 다시 확인했다.
불일치는 0개다. 선택한 공개 receipt 참조도 같은 원본 hash를 사용한다.
INDEX SHA256은 `4db4f572c02410a7b1d593eccbe402fca1800640fd23a9546c90437c30f5e0b5`다.
문서 작업에서 VM·UI·프로세스 signal·제품 source·Tests·build·원본 receipt를 변경하지 않았다.

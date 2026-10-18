# #206 실제 CLI와 VM GUI 준비

이 문서는 `4dede50` 후보의 과거 검증 기록이다.
기존 runtime 재사용과 Simulator 생성 결과를 새 runtime 설치 성공으로 옮기지 않는다.
후속 `d4628c9`의 설치 시도 취소와 새 `6e19a33` 검증 입력은 [별도 기록](actual-runtime-d4628c9.md)에 있다.

## 고정 입력

제품 source는 `4dede50eeca35ad59307c779160bf988a6e4bee1`이다.
Food Truck source는 `3954a769e99f3cc53297d94f2b960ceb2665b3d6`이다.
검증용 복제본은 tracked 파일 553개와 `ios.scheme: Food Truck` 선택을 고정했다.
VM은 보존한 기준 VM의 기존 복제본만 사용했다.
환경은 macOS `27.0.1/26A434`, arm64, Xcode `27.0/27A266a`다.
기존 iOS runtime `27.0/24A434/arm64`를 재사용했다.

| 실행 파일 | SHA-256 | 구분 |
| --- | --- | --- |
| CLI R1 | `fbec4f5b7962e36f64fb510260b2e68c11b3d299908889f588c4b3278b9c8d9b` | 실제 CLI 준비 |
| GUI R1 원본 | `9a07c76a8c0158e470aeec4552e24012488b3be3095c194e0f6357882d22746c` | 원본 보존 |
| VM 검증용 GUI | `39ab0d48aaa1b61f65f3271c56a2c3e11fd1ed2c7498d0f16a0d8352a0fc2c46` | 전용 bundle ID와 ad hoc 서명 |

검증용 GUI는 원본 app의 복사본이다. resource bundle을 표준 `Contents/Resources`에 배치했다.
전용 bundle ID를 사용했다. strict 서명 검사는 exit `0`이다.
이는 Developer ID·공증·Gatekeeper 배포 승인을 입증하지 않는다.

## 실제 결과

| 경로 | 관측 결과 | 근거 범위 |
| --- | --- | --- |
| CLI R1 승인 | `succeeded / exit 0`, 20.671초 | 기존 Simulator `503455A6-9D97-4021-AAA1-9981B5BC4C38` 재사용. 새 생성 0개 |
| GUI 잘못된 child `DEVELOPER_DIR` | `waiting-manual / exit 1` | 경로 오류를 표시했다. 전역 선택을 변경하지 않았다 |
| GUI 올바른 child 경로 | `succeeded / exit 0` | `84F9BF04-373C-468A-AF21-2317EB9B0EC7` 생성. 최종 상태 `Shutdown` |
| GUI 준비 재검사 취소 | `cancelled / exit 130` | 완료한 의존성과 cache 보존 안내를 표시했다 |
| GUI 재검사 후 재승인 | `succeeded / exit 0` | 같은 UDID와 완료 자원을 재사용했다. device 목록이 같았다 |
| GUI 실제 파일 쓰기 오류 | `failed / exit 2` | 새 소유 recovery journal만 mode `0500`으로 두었다. stock 제품과 시스템 명령을 사용했다. 실제 오류는 `NSCocoaErrorDomain 513`이다 |
| GUI 권한 복구 후 재시도 | `succeeded / exit 0` | journal만 `0700`으로 복구했다. 새 소유 set에서 `295F66E0-5526-4A87-879F-492868EC19CA`를 생성했다. 최종 상태 `Shutdown` |

파일 쓰기 오류가 난 set에는 권한 복구 직전 기기가 0개였다.
복구 전후의 argv·권한·기기 목록을 별도 receipt에 보존했다.
GUI는 준비 성공과 앱 빌드·실행의 별도 검증을 화면에 표시했다.
이 GUI 검증에서 앱 빌드·앱 실행·Simulator boot는 수행하지 않았다.
세 GUI process는 메뉴의 정상 종료로 모두 exit `0`을 회수했다.
소유 Tart VM의 정상 stop과 run process도 각각 exit `0`이다.

## 보존 검사

새 GUI 검증 구간에서 다음 비교가 모두 일치했다.

| 대상 | 비교 범위 |
| --- | --- |
| 원본 source와 검증용 source | 각각 tracked 553개 bytes·mode, HEAD, raw index, stage, flags, 선택 파일 |
| 원본 GUI와 검증용 GUI | 선택한 app 파일 전체 bytes·mode |
| 기존 CLI 생성 Simulator | 선택한 기존 Simulator subtree의 regular 파일 bytes·mode |
| 기본 device set과 runtime | `simctl list ... -j`의 전체 JSON |
| 기준 VM·#203 VM·#205 VM | 작은 metadata 파일의 전체 SHA와 VM disk stat |

기본 device set의 기존 CLI 생성 기기를 변경하지 않았다.
새 GUI 기기 두 개는 각각 새 소유 device set에 남겼다.
모든 HOME·cache bytes나 VM disk 전체 bytes의 보존으로 확대하지 않는다.
기존 CLI 구간의 raw source index 불일치는 기존 R1 기록에 그대로 남긴다.
새 GUI 구간의 index 일치는 그 이전 구간을 소급 입증하지 않는다.

## 실제 Mac 경로와 실패 이력

실제 Mac에서는 검증용 sandbox가 Xcode의 DerivedData·SwiftPM cache 쓰기를 차단했다.
doctor가 setup 전에 실패했다. 이를 host GUI 준비 성공으로 세지 않는다.
초기 host 입력의 잘못된 `FoodTruck` scheme도 실패 이력으로 보존했다.
VM 입력은 원본의 올바른 `Food Truck` scheme을 사용했다.
전역 Xcode 선택이나 기존 SDK를 수정해서 host 실패를 우회하지 않았다.

Tart 화면이 가려진 구간에는 흰 캡처를 반환했다.
흰 캡처와 확대 전환 캡처를 보존했다. 해당 캡처는 결과 근거에서 제외한다.
사용자가 VM 창을 표시한 뒤 재시도 성공 화면을 직접 확인했다.

기존 CLI의 runtime export는 외부 기록기 exit와 실제 child exit `70`을 구분한다.
관측한 Apple-signed Restore DMG는 `8,067,000,161` bytes다.
SHA-256은 `5136453f500b73dc3518f262d8a51e4be0c136e38a550998febf7759de6ba0fd`다.
catalog의 `8,053,150,208` bytes와 다른 표현이다. catalog 원본 다운로드 checksum으로 치환하지 않는다.
새 runtime의 네트워크 다운로드·설치 성공은 이 기록의 결론이 아니다.

## 선택한 비공개 근거

전체 command·process exit·화면 원본은 비공개 검증 경로에 보존한다.
공개 문서는 개인 host 경로나 원본 로그를 포함하지 않는다.

| 근거 | 크기 | SHA-256 |
| --- | --- | --- |
| GUI handoff v1 | 4793 bytes | `ca7cdead50877a1f15fb738cfb77706055d51e50c6998124f93afadbf150fab6` |
| 선택한 private index v1 | 157개 파일 | `0b6ec295752d54fc04126abf48f30e119b490f9096f3c5ca24955e6000d93866` |
| guest 최종 보존 감사 | 945843 bytes | `2ec5ceb7f9c014f8f8096eb57be48f8133440fad96de255734578b03f4946fac` |

private index에는 실제 화면 원본 10개가 포함된다.
제품 전체 최종 리뷰·원격 필수 CI·병합·main CI는 아직 이 기록의 완료 범위가 아니다.

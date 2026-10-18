# #206 source·공식 metadata 관측

상태: `d4628c9`의 CLI·GUI에서 runtime 설치 시도 취소 `130`과 exact runtime 수동 재검사를 확인했다.
payload 성장·네트워크 전송·runtime 설치 성공은 그 실행에서 입증하지 못했다.
최신 [CLI·GUI 취소와 새 검증 입력](actual-runtime-d4628c9.md)은 이 한계를 보존한다.
`6e19a33`·Xcode `27.1`의 [새 CLI 검증](actual-cli-6e19a33-resume.md)은 실제 runtime 설치·Simulator 생성 `succeeded / exit 0`을 확인했다.
새 GUI 결과와 VM 정상 종료는 아직 미확인이다.
이전 [VM GUI 기록](actual-vm-gui.md)은 `4dede50`의 기존 runtime 재사용·기기 생성 이력이다. 새 runtime 설치 성공 근거가 아니다.
아래 초기 source 단계의 미검증 기록은 당시 상태다.
고정 시작 source: `1b55a8899aea36c77443469dabf64647add27294`.
공유 설치 API: `0e54bb1c7db760427d369119afdef92df3701298`.

## 공식 metadata 읽기

2026-10-16에 공식 문서·metadata와 설치된 Xcode의 help만 읽었다.
runtime payload를 다운로드하지 않았다. 기존 runtime·Simulator와 전역 Xcode 선택을 변경하지 않았다.

| 관측 | 결과 | 입증하지 않는 범위 |
| --- | --- | --- |
| Apple runtime catalog | 572907 bytes, SHA-256 `aa2e0518b95223f8de060d00c29cdefcca54389d9250f369521f60428b5ae322` | payload bytes·checksum |
| catalog의 정식 iOS 27.0 | build `24A434`, `arm64`, asset `93b56b3a-f17c-5f56-937e-b66a83688c43` | 설치 결과·기존 기기 보존 |
| catalog의 크기 | 8053150208 bytes | 실제 수신 크기 |
| Apple Components 문서 metadata | SHA-256 `1205306f8cf84854ed140f46d520828a90e400772c1b972e359b33830ce9871b` | 실제 다운로드 접근·계정·권한 |
| MobileAsset catalog 별도 접근 | HTTP 403 | 계정이 반드시 필요하다는 원인 확정 |
| `xcodebuild -help` | OS version·architecture 다운로드, 별도 import 옵션 관측 | 특정 asset UUID나 payload bytes의 원자적 고정 |
| `simctl help runtime` | add의 staging·verification·mount 설명 관측 | 실제 signature 검증·설치 |

원문 출처는 [Apple Components 문서](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components)와
[Apple runtime catalog](https://devimages-cdn.apple.com/downloads/xcode/simulators/index2.dvtdownloadableindex)다.
공개 자료에는 전체 원본 로그와 사용자 경로를 넣지 않았다.

## source 검사와 실패 이력

공유 API·기존 SDK 준비·설치 검사는 24 tests/3 suites PASS다.
이는 SDK나 iOS runtime의 실제 설치가 아니다.

기존 public `PreparationExecution`은 Simulator 생성 계획을 제공하지 않았다.
먼저 이 행동을 기대하는 검사에서 RED 1건을 확인했다.
provider 고정 시점에는 공통 실행기 결합을 남겼다. 그 연결 전의 integration RED를 보존한다.

새 selector 검사의 초기 기대값은 같은 세대에서 Pro를 우선했다.
기존 selector는 단순 모델을 우선한다. 새 검사의 잘못된 기대값을 정정했다.
기존 selector는 바꾸지 않았다.

provider 행동 검사에서는 `Runstir iPhone …` 이름의 생성 기기를 기존 selector가 재사용하지 못했다.
이 RED를 확인한 뒤 생성 이름을 `iPhone … - Runstir - iOS …`로 고쳤다.
최종 Swift Werror compile과 선택한 provider·parser·기존 SDK 검사 35 tests/5 suites는 PASS다.
이 수치는 전체 Swift suite나 공통 setup 연결 성공이 아니다.
공통 연결 전 integration RED와 실제 준비 미검증 상태를 구분한다.

## 공통 source 연결 검사

정확한 프로젝트 도구 활성화 source `7fac827f7b086ef754d37c71da94946247aa2e0a`를 결합했다.
결합 직후에도 기존 public 검사에서 `ios.simulator.create` 계획 누락 RED를 재현했다.
이후 같은 `PreparationExecution` interface에 iOS action과 관측 자원을 연결했다.
공통 실행기는 runtime·device set·관측한 기존 device의 `resourceKeys` 전체를 잠근다.
성공·실패·취소 결과는 실제 또는 `unknown` 자원을 보존한다. 취소 exit code는 `130`이다.
새로 관측한 나머지 action은 새 plan-id로 다시 승인해야 한다.
과거 JSON plan에서 새 optional 자원 필드가 없어도 decode할 수 있다.

첫 전체 검사는 새 simctl 관측의 fixture 응답 누락으로 실패했다.
기존 Preparation·native iOS fixture에 build·architecture·device type 관측을 추가했다.
기존 assertion은 유지했다. iOS 공통 연결·복구·새 승인과 기존 준비 회귀 46 tests/4 suites가 Werror로 통과했다.
수정 뒤 전체 Swift suite도 Werror로 677 tests/83 suites가 통과했다.
이 검사는 fake process와 소유 임시 fixture를 사용했다. 실제 runtime 다운로드나 Simulator 생성이 아니다.

## 남은 실제 게이트

`4dede50`의 CLI R1은 기존 runtime을 재사용했다. 같은 후보의 VM GUI는 실제 생성·취소·파일 쓰기 실패·재시도·재사용을 확인했다.
`d4628c9`의 별도 CLI·GUI는 runtime 설치 시도를 취소했다. 재검사는 journal을 보존하고 수동 복구만 안내했다.
실제 Mac의 sandbox doctor 실패·VM 결과·새 baseline의 Xcode `27.1` 검증을 구분한다.
새 CLI는 exact runtime 설치·새 UDID의 Shutdown 상태·선택 자원 보존을 확인했다.
새 GUI 결과와 최종 GUI·VM 정상 종료는 아직 미확인이다.
[#206 및 #199 AC02·AC03·AC06 근거표](actual-runtime-d4628c9.md#ac별-근거)를 읽는다.
최종 문서에 대한 독립 리뷰·최종 head 필수 CI·위험별 승인·병합·main CI도 남겼다.
필수 실제 조건을 fixture·문서 PASS로 대신하지 않는다. #206은 완료 상태가 아니다.

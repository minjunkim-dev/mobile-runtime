# #206 source75 CLI 실제 설치·생성 증거

source `75baf9d66592bc20e0c5644ff161ec77686a6c6d`의 CLI setup이 실제 exit 0으로 끝났다.
이 기록은 빈 private device set에서 runtime 설치와 새 Simulator 생성을 검증한 CLI case만 다룬다.

| 항목 | 관측 결과 |
|---|---|
| CLI | SHA256 `f3359a8b11dce06c348d449ab55f05b3f23748d4ccc1827757bbf960fe4dccd6` |
| 승인 | 정확한 plan `2da0d0c69891d2d3d8289d700ab00910ebf634d421e514481e374da332ec974b`; trustRepository=false |
| 실제 종료 | PID 1740, exit 0, 929.335774898529초, signal 0, deadline 미도달 |
| 완료 step | ios.runtime.install, ios.simulator.create |
| runtime | iOS 27.0 / 24A434 / arm64, origin=installed, native available |
| Simulator | iPhone 18 Pro - Runstir - iOS 27.0, UDID `6FFD2226-0C32-4228-8757-95C8B5B5B35E`, origin=created, Shutdown |

CLI 검증 항목 대응은 다음과 같다.

| 검증 항목 | 증거 범위 |
|---|---|
| 정확한 계획 승인 | 고정 raw plan과 실제 명령의 plan ID가 같다. repository trust는 false다. |
| 정확한 runtime 설치 | 완료 resource와 native inventory가 iOS 27.0/24A434/arm64를 확인했다. |
| 새 기기 생성 | private set은 0개에서 정확히 1개가 됐다. native UDID·type·name·Shutdown 상태가 맞다. |
| 지정 입력 보존 | 설치 결과 18개 검사와 후속 named 비교 14개가 모두 통과했다. |
| 자연 종료 | actual exit 0, 남은 owned process 0, signal 0을 확인했다. |

원본·복사 source, SDK·도구·candidate, 전역 입력·Xcode, 기존 runtime·기기와 보호 root의 지정 비교가 통과했다.
cache metadata 변경은 `Library/Developer/CoreSimulator/Devices` 1개 항목이다.
변경 주체는 입증하지 못했다.
전체 HOME/cache/VM disk 보존은 주장하지 않는다.

export 290개 파일의 bytes·SHA256과 raw tar의 guest mode를 다시 비교했다.
불일치는 0이다.
파일 합계는 61,554,050 B다.
raw tar는 290개 receipt와 INDEX.json으로 구성된다.
최소 receipt pin은 JSON 기록에 있다.
raw 환경·process dump·진단 로그는 공개 기록에 복사하지 않았다.

downloadGrowthObserved=false와 networkTransferVerified=false를 유지한다.
별도 Root native 관측은 승인한 Apple asset의 다운로드 시작과 첫 progress event만 확인했다.
전체 전송·payload checksum·OS daemon의 전체 파일 활동을 입증하지 않는다.

source75의 로컬 locked-dependencies/Werror 707 tests·85 suites PASS는 별도 고정 보고서의 결과다.
보고서 SHA256은 `517ff559db75a7c3abf35c95704cb4f1deacfa7a5ffd1f559864e58eda36bbe0`다.
이는 현재 head의 remote CI 결과가 아니다.

기존 private 기기 복구 후 재사용 경로는 이번 빈 set case의 직접 실측 범위가 아니다.
역사 d4628c9·6e19a33 결과와 한계는 각 source에 그대로 남긴다.
기존 FoodTruck historical object 누락 한계도 유지한다.
원래 Tart boot의 actual exit는 UNKNOWN이다.
source75 GUI·정상 VM stop·앱 build/launch·현재 head CI·최종 review·merge/main CI·release는 이 CLI 기록으로 완료 처리하지 않는다.

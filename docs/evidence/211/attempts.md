# #211 시도 이력

V4의 source는 `8862bcad5c003514cee73c41debe65b9301edf1e`다.
이전 candidate의 실제 결과는 그 candidate의 이력으로만 사용한다.
원본 명령·결과·stdout·stderr는 private custody에 남긴다.
[명령 목록](commands.json)과 [원본 SHA256 목록](private-evidence-index.json)을 함께 확인한다.

| 구간 | source | 관측과 처리 |
| --- | --- | --- |
| V1 입력 오류 | `6754c92ff5236de8039173e65e10bb0e71b50ac7` | doctor에 지원하지 않는 `--progress-json`을 전달해서 exit 64. 호출 오류로 분류했다. |
| V1 candidate 포장 오류 | V1 실행 파일 | sibling SwiftPM resource bundle 누락으로 exit -5. AndroidKit·Core resource bundle을 로컬 candidate에 복사했다. 실행 파일 SHA256은 바뀌지 않았다. 제품 성공으로 계산하지 않았다. |
| V1 경로·guard | V1 | 초기 검사와 build 실패를 보존했다. scoped temporary 접근을 준비한 doctor 재시도는 exit 0이었다. guard 수정은 제품 코드 수정과 구분했다. |
| V1 NIA model | V1 | Isolated Projects와 Configuration Cache 조건 충돌로 model 평가 실패. 공통 probe/build 인자를 고친 V2에서 doctor exit 0. |
| V2 | `de99bcad1b2cc171d6a37e832914f2a475c13aaf` | RunLogs 원자 저장 temporary 경로의 guard 거부로 up 실패. 이후 Emulator crash DB 경로도 거부됐다. 소유 HOME/temporary 접근 준비 후 Todo up exit 0. |
| V2 GUI 재실행 | V2 | Cmd-Q 직후 CUA 관측에서 별도 소유 GUI 재실행을 관측했다. 이 재실행의 환경은 unknown이다. 소유 PID만 SIGTERM했다. 정상 Cmd-Q 종료로 바꾸지 않았다. |
| V3 | `baea26fae0ed6b8fddc216c0e0511339cc133796` | native 입력 경로 표시와 정상 소유 Emulator down 뒤 claim 정리를 포함했다. Todo cancel 130·up 0·첫 화면·down 0을 관측했다. V4 화면 근거로 재사용하지 않는다. |
| V3 NIA 선택 | V3 | 복수 variant에서 선택 누락과 잘못된 variant를 차단했다. 소유 clone의 untracked `mobile.yml`만 임시 변경했다. 정본 설정 SHA256 복구를 확인했다. tracked source 변경은 없었다. |
| V4 Todo GUI guard | V4 | build 취소 130 뒤 첫 up은 claim 저장 NSCocoaError 513/NSPOSIX 1로 exit 2. 구체 temporary 경로는 직접 관측하지 못했다. CFBundleName 관련 경로 추정은 가설로 남겼다. scoped guard 재시작 뒤 GUI up/down 0. |
| V4 Todo 충돌 | V4 | CLI 활성 중 GUI up 1, GUI 활성 중 CLI up 1. 기존 앱 PID 4712·4961을 각각 보존했다. |
| V4 NIA 취소 | V4 | CLI build SIGINT 후 exit 130. 다음 build는 exit 0/69.262s. 완료 단계와 취소 결과를 남겼다. |
| V4 NIA 알림 | V4 | 최초 up 0/60.699s. 알림 창 때문에 첫 화면 통과 아님. Android API 두 명령으로 소유 AVD 알림을 거부 상태로 준비했다. UI 클릭은 수행하지 않았다. |
| V4 NIA 재시도 | V4 | 알림 준비 뒤 up 1/98.255s. validate/build/device/install 완료 뒤 launch 미완료. rollback의 소유 자원 재시도 안내를 보존했다. 후속 cold boot 실행은 별도로 기록한다. |

알림 준비 뒤 launch는 30초 timeout으로 실패했다.
후속 observer 일곱 개는 모두 exit 1이었다.
기기를 찾지 못했으므로 유효한 첫 화면 PNG를 만들지 못했다.
빈 PNG와 traceback을 성공 캡처로 계산하지 않았다.
안전 필터 excerpt에는 context restore 오류 12297과 temporary crash DB 쓰기 거부가 있다.
이 오류와 launch 실패의 인과관계는 미확정이다.
Emulator auth 줄의 원문은 수집하거나 공개하지 않는다.

원본 active-run의 소유 PID 49852와 serial `emulator-5554`를 확인했다.
범위를 한정한 native `ps`는 exit 1과 빈 stdout·stderr를 반환했다.
guard가 이 `ps` 실행을 제한했으므로 같은 V4 stock `down`만 guard 밖에서 한 번 실행했다.
이 예외는 소유 자원 cleanup에만 적용했다.
제품과 guard source를 바꾸지 않았다.
나머지 실제 제품 흐름은 guard 안에서 실행했다.
down은 exit 0/0.104s와 `ownedRuntimeStopped=true`를 반환했다.
소유 active-run과 일치하는 claim 부재를 확인했다.

그 뒤 소유 AVD config만 수동으로 바꿨다.
`fastboot.forceColdBoot=yes`와 `fastboot.forceFastBoot=no`를 설정했다.
원래 config bytes의 SHA256을 보존했다.
cold boot 재시도는 up exit 0/98.686s였다.
후속 settled PNG에서 관심사 선택 카드가 가림없이 보였다.
이 화면의 package·설치 APK와 built APK의 동일성을 연결했다.
최종 down은 별도 receipt에 기록한다.
이 성공을 이전 실패의 원인 확정으로 해석하지 않는다.

## 회귀 수정과 자동 검사

| 결함 | RED | GREEN와 경계 |
| --- | --- | --- |
| native Android 진단 경로가 RN의 `android/`로 표시됨 | `runstir211-input-path-red02.log`: native 경로 assertion 9개 실패, RN 경로 통과 | `8b2f588dddbe28dbeae75fe9c63b77f28b37f6bb`; 관련 Werror 39 tests/3 suites. native root 표시만 고쳤다. RN 경로와 실제 argv는 유지했다. |
| 소유 Emulator 정상 down 뒤 claim 잔존 | `runstir211-owned-down-claim-red02.log`: down pass·Emulator stopped 뒤 다른 project가 offline unknown에서 차단됨 | fixture `5d5e749b70457e2f07fed646ae8094373620609e`; parent의 CoreLease/Workflow 수정과 합쳐 관련 36 tests/3 suites 통과. fixture commit 단독 성공을 주장하지 않는다. |
| 이미 종료된 소유 Emulator down 뒤 claim 잔존 | `runstir211-already-stopped-red02.log`: 필수 5 case에서 7 issues | `270fa34620ec67ca3132acc79aae7a7be446cb46`; 관련 84 tests/9 suites, 전체 Werror 622 tests/75 suites 통과. |

이미 종료된 소유 runtime은 optional `ownedRuntimeStopped`로 전달한다.
recorded serial이 ADB 목록에 없음을 확인한다.
`ps -p PID -o pid=`의 exit 1과 빈 stdout·stderr로 PID 부재를 확인한다.
`kill -0` nonzero만으로 부재를 판정하지 않는다.
reused·nil PID·빈 serial·EPERM·도구 오류에서는 record와 claim을 보존한다.
legacy iOS·RN의 optional nil JSON key는 생략한다.

최초 test compile 오류와 DTO 전달 누락을 발견한 중간 GREEN 시도도 private log에 남아 있다.
최종 통과 기록으로 이 실패 기록을 덮지 않았다.
위 자동 검사는 실제 앱 화면이나 전체 자원 보존의 증거가 아니다.

Emulator guard 실패 excerpt는 auth 줄을 제외한 뒤 수집했다.
따라서 제외 전 원본 전체 log의 SHA256은 수집하지 못했다.
수집한 excerpt SHA256만 기록했다.
이 한계를 새 원본을 만들어서 없애지 않는다.

## NIA GUI down과 외장 SSD 분리

NIA GUI up과 가림없는 첫 화면은 분리 전에 확인했다.
최초 GUI down은 exit 1이었다.
앱은 종료했다.
제품은 소유 Emulator가 아직 실행 중이라고 보고했다.
최초 검증 guard는 native `ps`를 제한했다.
따라서 소유 record와 claim을 보존했다.

그 뒤 외장 SSD가 분리됐다.
사용자가 SSD를 다시 연결했다.
재연결 뒤 source HEAD와 공개 초안 12파일의 원래 manifest를 대조했다.
HEAD는 `8862bcad5c003514cee73c41debe65b9301edf1e`였다.
공개 초안 bytes는 모두 일치했다.
이 비교는 분리 구간 전체의 자원 보존 증거가 아니다.

재연결 뒤 PID 14767의 native `ps`는 exit 1과 빈 stdout·stderr를 반환했다.
GUI PID 29210과 ADB PID 88450도 native 관측에서 없었다.
GUI·ADB manager는 offline 경로 생성 실패 traceback과 exit 1로 종료했다.
manager의 종료 코드로 원래 child의 종료 코드를 정하지 않는다.
원래 child의 종료 코드는 `unknown`이다.
정상 종료를 주장하지 않는다.

parent는 정확한 `/bin/ps`에만 `(with no-sandbox)`를 적용한 새 검증 profile을 만들었다.
GUI 전체의 sandbox를 해제하지 않았다.
새 profile SHA256은 `360a6771bd62c269318991c350fba77a16a9df1f6f11b9eace0c70f5d7ae4173`이다.
같은 PID의 old profile probe는 exit 71과 EPERM이었다.
새 profile probe는 native와 같은 exit 1·빈 stdout·stderr였다.
허용 범위 밖 소유 protected control 쓰기는 exit 1이었다.
parent는 control bytes 보존도 확인했다.
control의 기대 literal SHA256과 after SHA256은 `ed5795a0b60255d38d9a7fcca255cc969e6dc2a20795087d9e021a0277183499`로 같다.
41 bytes의 보존을 [canonical receipt](cleanup-and-preservation-v4.json)에 연결했다.
새 profile에서 같은 candidate GUI의 down만 재시도했다.
이 down은 exit 0이었다.
Emulator 항목은 이미 종료된 소유 runtime으로 표시했다.
재시작한 GUI와 ADB manager는 각각 exit 0이었다.
원래 child의 unknown 종료 코드는 유지한다.
제품 source·SDK·기기 runtime 설치는 바꾸지 않는다.
전역 전체 `ps` 원문과 hash는 공개하지 않는다.
Emulator auth 행의 원문과 hash도 공개하지 않는다.

최종 native 관측에서 재시작한 GUI·ADB와 원래 Qemu의 PID가 없었다.
port 5045·5554·5555 listener도 없었다.
이는 관측 시점의 부재 증거다.
원래 child의 unknown exit status나 분리 gap을 없애지 않는다.

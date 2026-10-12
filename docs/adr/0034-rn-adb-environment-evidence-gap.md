# ADR-0034: 과거 환경 기록의 공백과 향후 ADB 환경을 구분한다

- 상태: 채택 — 문서와 source-only helper 준비에 한정
- 날짜: 2026-10-12
- 관련: #212 · ADR-0020 · ADR-0033

## 결정과 범위

과거 원본 launch의 HOME·ADB endpoint·key 선택은 기존 원본 launch 기록으로만 판정한다. 원본 환경을 수집하지 않았으므로 현재 판정은 `UNKNOWN`이다. 미수집은 환경변수 부재의 증거가 아니다. 현재 shell·reviewer HOME·향후 기록으로 과거 기록을 보충하지 않는다. 원본 receipt와 실패 증거를 보존한다.

향후 환경은 별도 새 실행 입력이다. 사용자는 Q1·Q2·Q3에서 아래 선언과 메모리 기록 계약을 확정했다. 사용자는 이 정책 문서와 source-only helper 및 검사 파일의 저장을 허용했다. 실제 환경 수집·환경 적용·resource 조회·GUI/ADB 시작은 허용하지 않았다. 실제 resource predicate와 실행 권한은 그대로 유지한다.

## 두 호출에 한정한 향후 선언

`SELECTED_ADB`는 기존 selected SDK 경로 `/Volumes/P41_USB4/Developer/sdk/android/platform-tools/adb`를 뜻한다. 다음 두 호출에만 선언을 연결한다.

| 역할 | argv |
|---|---|
| `foreground-server` | `[SELECTED_ADB, "-L", "tcp:localhost:5037", "server", "nodaemon"]` |
| `devices-client` | `[SELECTED_ADB, "devices"]` |

| 환경변수 | 선언 상태 | 선언값 |
|---|---|---|
| `HOME` | `VALUE` | `/Users/swifty` |
| `ADB_SERVER_SOCKET` | `VALUE` | `tcp:localhost:5037` |
| `ANDROID_ADB_SERVER_ADDRESS` | `ABSENT` | 없음 |
| `ANDROID_ADB_SERVER_PORT` | `ABSENT` | 없음 |
| `ADB_VENDOR_KEYS` | `ABSENT` | 없음 |

`ABSENT`는 환경변수 미설정이다. 빈 문자열이나 미수집을 뜻하지 않는다. 다른 환경변수는 변경하지 않는 계약으로 둔다. 현재 다른 환경변수의 보존을 검증했다는 뜻은 아니다. 두 호출의 argv를 유지한다. 다른 client·Emulator·baseline consumer·전역 환경으로 자동 확대하지 않는다.

`/Users/swifty`는 기존 reviewer metadata에 있는 경로를 새 입력으로 선택한 값이다. 과거 원본 HOME이나 현재 유효 HOME의 증거가 아니다. 설치·새 HOME directory·key 복사·생성·rotation·known-host 변경을 허용하지 않는다. ADR-0033의 원본 HOME 보존 조건을 실제 경로에서 이 선언으로 자동 교체하지 않는다. 실제 조건 변경에는 별도 결정과 새 실행이 필요하다.

## 향후 메모리 기록 계약

각 기록은 실행 ID·호출 ID·역할, 정확한 argv와 binary identity, 위 다섯 환경변수의 상태를 연결한다. 각 상태는 `UNRECORDED`·`ABSENT`·`EMPTY`·`VALUE` 중 하나다. `UNRECORDED`는 미수집이며 판정은 `UNKNOWN`이다. `EMPTY`는 수집한 빈 문자열이다. 전체 환경과 key 내용은 기록하지 않는다.

선언값·launcher 전달값·실제 수신 증거는 별도 단계다. 전달 dictionary의 선언만으로 실제 수신을 입증하지 않는다. 전달·수신 증거가 없으면 `UNKNOWN`이다. 기록은 해당 새 실행에만 귀속한다. 과거 환경과 같았다는 증거로 사용하지 않는다. 저장·수집 위치나 실제 collector·adapter를 이 정책으로 자동 승인하지 않는다.

## 조건부 source 계산과 미해결 항목

보존된 AOSP source pin은 `fb529d52f4485c1fdbe6208f20af6578493e1ca7`이다. `client/commandline.cpp:1593–1597,1614–1642`에서 server의 `-L`과 옵션 없는 client의 명시 `ADB_SERVER_SOCKET`은 선언대로 전달된다는 조건에서 `tcp:localhost:5037` 문자열을 선택한다. endpoint 환경변수 세 개를 모두 제거하면 client 문자열은 `tcp:5037`이다. 두 문자열의 실제 동작을 같다고 가정하지 않는다.

`adb_utils.cpp:289–290,310–319`와 `client/auth.cpp:207–237`, `client/adb_wifi.cpp:100–120`은 선언된 HOME에서 `.android/adbkey`와 `.android/adb_known_hosts.pb`를 선택하는 조건부 근거다. vendor key 부재는 user key load를 제거하지 않는다. 기존 `.pub` 파일을 auth가 읽는다고 단정하지 않는다. 파일 존재만으로 key 유효성이나 device trust를 입증하지 않는다.

설치 binary와 전체 source/build의 대응, 실제 환경 수신, directory·key·known-host 유효성, transport 접촉, shared write, client 자동 start/kill race와 cleanup 소유권은 미확인이다. 이 선언과 모델 성공은 실제 compatibility·readiness·lease·첫 화면 PASS가 아니다. ADR-0020의 필수 실패·UNKNOWN STOP과 ADR-0033의 실제 보호 조건을 유지한다. #212의 두 표본 양플랫폼 첫 화면과 각 독립 fresh 검증은 계속 미완료다.

## source-only helper

[`rn_adb_environment.py`](../../scripts/source-only/rn_adb_environment.py)는 명시적으로 전달한 합성 데이터만 처리한다. 실제 환경·파일·계정·process·socket을 읽지 않는다. import·실행 adapter·collector·환경 주입·network·persistent write 경로가 없다. 합성 ID와 binary identity는 `model://`에 한정한다. model match와 actual 판정을 구분한다. actual authority와 readiness는 항상 false이며 lease는 없다.

[`test_rn_adb_environment.py`](../../scripts/source-only/test_rn_adb_environment.py)는 두 역할, 네 환경 상태, 누락·추가 필드·잘못된 identity·선언 불일치·합성 입력 변경 격리를 검사한다. 검사 과정은 실제 resource를 조회하지 않는다. 로컬 검사는 repository root에서 `python3 -B scripts/source-only/test_rn_adb_environment.py`로 수행한다. 이것은 모델 검사 명령이며 ADB 실행 명령이 아니다.

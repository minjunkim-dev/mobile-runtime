# #214 시도 03: 원래 native NetNewsWire 앱의 첫 화면 보완

관측일은 2026-10-16, Asia/Seoul이다.
Runstir를 실행하지 않았다. `xcodebuild`를 다시 실행하지 않았다.
시도 02의 원래 native `.app`을 보존된 경로에서 재사용했다.

## 고정 입력과 경계

- source: `aea7795bcc0698ced6f28eba53da886eb6217e64`.
- scheme/configuration: `NetNewsWire-iOS` / `Debug`의 시도 02 산출물.
- native app ID: `org.runstir.baseline214.NetNewsWire.iOS-DEBUG`.
- #210 app ID: `com.ranchero.NetNewsWire.iOS-DEBUG`. 두 app ID는 다르다.
- 실행파일 SHA와 bundle metadata·파일 수·크기가 시도 02 기록과 같다.
- 시도 02에는 전체 bundle 파일 manifest가 없다. 전체 resource byte의 역사적 동일성은 미확인이다.
- 이번 시도의 전체 170개 파일 manifest는 전후 같다.
- 기존 own Simulator와 앱 데이터를 유지했다. 새 사용자 데이터의 최초 실행은 아니다.
- Xcode·runtime 원본 배포 checksum은 `unknown`이다.

`OWN_SIMULATOR`와 `ORIGINAL_NATIVE214_APP`은 제한 원본에 실제 값이 있다.
공개 문서에서는 이 별칭으로 기기 identity와 개인 경로를 가린다.
`results.json`은 각 원본 command receipt의 SHA256과 정규화 argv를 기록한다.
명령의 인자 구조는 유지했다. 값만 별칭으로 바꿨다.

## 실제 순서

1. 실행 중인 native 도구와 전체 Simulator 상태를 읽었다.
2. 기존 기기의 43개 앱 전체 metadata와 source·index·lock·artifact를 고정했다.
3. 전용 Simulator만 시작했다.
4. 원래 native 앱을 한 번 설치했다. 설치 완료를 기다렸다.
5. 원래 app ID를 한 번 실행했다.
6. CUA로 Feeds 화면과 팝업 부재를 확인했다. 원본 이미지(JPEG)와 AX를 저장했다.
7. 설치된 앱의 실행파일 SHA와 실행 중인 PID를 확인했다.
8. 전용 앱만 종료했다. 전용 Simulator만 종료했다.
9. 같은 자원 목록을 다시 읽었다. 전용 앱 PID 부재도 확인했다.

```sh
SIMCTL=/Applications/Xcode.app/Contents/Developer/usr/bin/simctl
"$SIMCTL" boot "$OWN_SIMULATOR"
"$SIMCTL" bootstatus "$OWN_SIMULATOR" -b
"$SIMCTL" install "$OWN_SIMULATOR" "$ORIGINAL_NATIVE214_APP"
"$SIMCTL" launch "$OWN_SIMULATOR" org.runstir.baseline214.NetNewsWire.iOS-DEBUG
"$SIMCTL" get_app_container "$OWN_SIMULATOR" org.runstir.baseline214.NetNewsWire.iOS-DEBUG app
"$SIMCTL" terminate "$OWN_SIMULATOR" org.runstir.baseline214.NetNewsWire.iOS-DEBUG
"$SIMCTL" shutdown "$OWN_SIMULATOR"
```

native child 환경에는 `PATH`, `HOME`, `TMPDIR`, `LANG` 중 존재하는 값만 전달했다.
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`를 명시했다.
전역 선택과 PATH는 바꾸지 않았다. 의존성을 fetch하거나 lock을 갱신하지 않았다.
다른 작업의 generic Simulator 빌드는 변경하지 않았다.
coordinator는 기기와 쓰기 대상이 겹치지 않음을 확인했다.

## 첫 화면과 알림 상태

Feeds와 Smart Feeds, Today, All Unread, Starred, 기본 공개 feed 목록이 보인다.
알림 팝업은 나타나지 않았다. 이번 시도에서 권한 선택을 하지 않았다.
이전 권한 선택 완료와 현재 authorization enum은 `unknown`이다.
#210의 알림 거부는 다른 app ID에 해당한다.
시도 02의 팝업 이미지와 선택 미확인 기록을 보존했다.
이번 화면은 이전 tap 성공을 소급해서 입증하지 않는다.
화면의 `Updating…`은 feed 갱신 완료를 뜻하지 않는다.

## 보존 범위

15:45:11.103120~15:46:58.425088 UTC의 좁은 실행 구간을 비교했다.
기존 43개 앱의 전체 반환 metadata와 container 경로가 같다.
모든 Simulator의 state·name·type·availability·runtime 비교 결과도 같다.
source 1,352개 파일, index, lock, 4개 package pin과 원래 artifact를 보존했다.
앱 사용자 데이터 전체 byte와 구간 밖 변경은 검증하지 않았다.
전용 앱 종료와 전용 Simulator 종료는 모두 exit 0이다.
최종 전용 상태는 `Shutdown`이다. 기존 기기는 `Booted`다.
GUI/iOS lease를 반환했다.

초기 inventory 파서는 simctl의 OpenStep plist를 읽지 못했다.
원본을 보존했다. `plutil` 변환으로 파서를 교정했다.
기기 시작 전의 기록 오류이며 앱 실행 실패가 아니다.

가림 없는 첫 화면은 `pass`다. 전체 baseline은 `inconclusive`다.
#214를 완료로 표시하지 않았다. Apple 로그인 요청 철회 상태를 유지했다.

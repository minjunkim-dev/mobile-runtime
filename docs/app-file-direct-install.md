# 소스 없는 Simulator·Emulator 앱 파일 실행

관련 구현 티켓은 [#218](https://github.com/minjunkim-dev/mobile-runtime/issues/218)이다.
수용 기준은 [로컬 앱 설치 계약](./local-app-installation-contract.md)을 따른다.
이 문서는 명령과 구현 경계를 설명한다. 실제 설치·화면·데이터 보존 검증의 결과표가 아니다.

## 입력과 명령

이 경로는 iOS Simulator `.app` 디렉터리와 Android Emulator의 단일 `.apk`를 받는다.
프로젝트 소스와 계정은 필요하지 않다. 소스 빌드와 환경 준비를 시작하지 않는다.
iOS 실기기·IPA는 #219다. 목록·보유 버전·설치 이력은 #220이다. 앱 콘솔은 #221이다.
해당 형식과 기능은 이 경로에 추가하지 않는다.

```sh
mobile app inspect /path/Local.app --json
mobile app run /path/Local.app --device SIMULATOR-UDID --plan --json
mobile app run /path/Local.app --device SIMULATOR-UDID --approve EXACT-PLAN-ID --non-interactive --json --progress-json

mobile app inspect /path/Local.apk --json
mobile app run /path/Local.apk --device avd:EXISTING-AVD --plan --json
mobile app run /path/Local.apk --device avd:EXISTING-AVD --approve EXACT-PLAN-ID --non-interactive --json
```

`--device`에는 현재 후보의 고정 ID를 사용한다. 기기를 자동 선택하거나 전환하지 않는다.
가상 기기는 먼저 부팅하고 준비한다. 종료된 Simulator는 수동 준비 필요로 표시한다.
Android 후보는 현재 연결된 Emulator다. 실제 기기와 새 AVD 생성은 이 경로에 포함하지 않는다.
기기 준비 상태·OS·architecture 호환 조건을 확인하지 못하면 설치하지 않는다.

iOS는 기존 Xcode 선택과 `DEVELOPER_DIR` 계약을 따른다.
같은 고정 Xcode의 devices·runtimes inventory를 runtime identifier로 정확히 연결한다.
기기의 사용 가능·Booted 상태와 runtime의 architecture capability를 구분한다.
runtime identifier·build·available과 `supportedArchitectures`의 출처를 계획과 CLI·GUI에 보존한다.
이는 실제 기기 CPU 측정이 아니다. Simulator 안의 `uname` 실행은 필요하지 않다.
native macOS arm64와 앱·runtime의 공통 arm64 slice가 있어야 한다. universal 입력도 이 조건을 따른다.
x86 전용·Rosetta 의존 경로와 누락·중복·불명확한 runtime capability는 판정 불가로 중단한다.
runtime identity·build·capability·준비 상태가 승인 뒤 바뀌면 설치 전에 중단하고 다시 검사한다.
Android는 절대 경로 `ANDROID_HOME`과 설치된 `platform-tools/adb`·`build-tools/aapt2`·`apksigner`가 필요하다.
`JAVA_HOME`에는 이미 설치한 JDK를 지정한다. 서명 검사에는 그 JDK만 사용한다.
프로젝트 인식 Java shim과 환경의 Java agent 옵션을 실행하지 않는다.
`ANDROID_SDK_ROOT`가 다르면 중단한다. 프로젝트가 없으므로 `local.properties`를 추측하지 않는다.
설치된 build-tools 중 가장 높은 정상 버전의 aapt2 경로를 계획에 고정한다.
SDK 설치·라이선스 동의·설정 변경은 하지 않는다.

터미널 대화 모드는 현재 계획과 경고를 표시한 뒤 정확한 승인 문자열을 요구한다.
`--json`, `--progress-json`, `--non-interactive`에서는 묻지 않는다.
승인 없이 실행하면 `needs-approval`을 반환한다.
`--plan`과 `--approve`는 함께 사용할 수 없다.
이전 빌드는 별도 경고를 표시한다. `--approve DOWNGRADE:EXACT-PLAN-ID`로 그 경고를 확인한다.
이는 플랫폼의 이전 버전 거부를 우회하는 옵션이 아니다.

## 검사와 승인 경계

CLI와 GUI는 `AppFileExecution`을 호출한다.
파일 metadata에는 플랫폼, 앱 ID, 표시 정보, 빌드, 최소 OS, architecture와 확인 가능한 설치 조건이 있다.
필수 정보가 없으면 중단한다. 선택적 이름·표시 버전이 없으면 확인 불가로 남긴다.
사용자 파일의 제작 출처와 안전성을 추정하지 않는다.

`.app`의 Info.plist와 모든 실행 architecture의 Mach-O platform/minimum OS를 확인한다.
`lipo`와 `otool`은 metadata를 읽는다. bundle 안의 실행 파일과 스크립트는 실행하지 않는다.
외부로 나가는 link, 절대 link, dangling link와 특수 파일을 거부한다.
APK는 기존 Android badging parser를 재사용한다. split APK와 필수 정보 불명은 거부한다.
compiled manifest의 split 요구도 확인한다. 단독 base APK가 추가 split을 요구하면 중단한다.
`apksigner verify --verbose --print-certs`로 선택한 APK의 서명과 인증서 식별값을 검사한다.
설치된 SDK의 Java 조건이 없으면 수동 조치와 다시 확인을 안내한다. JDK를 설치하거나 선택하지 않는다.
검사 명령은 [공식 apksigner 문서](https://developer.android.com/tools/apksigner)의 verify 경로를 따른다.
기존 앱과의 서명자 호환성의 최종 수락은 플랫폼 설치 결과로 구분한다. 재서명하지 않는다.

계획은 원본의 canonical 경로·물리 파일 식별·SHA-256, 앱 정보, 기기 identity·준비 상태·도구 경로,
현재 설치 정보와 경고를 포함한다. 변경되면 새 승인이 필요하다.
내용 식별값은 파일 제작자의 신뢰나 안전성을 증명하지 않는다.
APK의 `sha256`은 파일 바이트의 SHA-256이다.
`.app`의 `sha256-tree-v1`은 정렬한 상대 경로·파일 종류·권한·크기·link 대상·파일 바이트를 구분해 해시한다.
bundle digest와 단일 파일 checksum을 같은 알고리즘 이름으로 표시하지 않는다.

승인 뒤 작업 전용 임시 디렉터리에 입력을 복사한다. 원본을 이동하거나 변경하지 않는다.
사본의 전체 내용과 metadata가 승인한 값과 같은지 검사한다.
설치 직전에 원본·기기·기존 앱·공통 자원 소유권을 다시 검사한다.
설치기는 이 작업 전용 사본만 읽는다. 나중의 원본 변경이 설치 입력을 바꾸지 못하게 한다.
사본 복사가 안전하게 돌아온 뒤 취소를 처리한다. 사본은 해당 작업이 끝날 때만 정리한다.
기존 앱·데이터·다른 작업의 파일은 정리하지 않는다.

파일 lease는 canonical 파일 경로와 volume·inode identity를 함께 잠근다.
symlink와 hardlink 별칭은 같은 창과 실제 파일 lease를 사용한다.
같은 경로의 atomic 교체도 동시에 실행하지 않는다.
창을 재사용할 때 현재 경로의 실제 파일 identity를 다시 읽는다.
별도 복사본은 내용이 같아도 합치지 않는다.
기기·앱 lease와 실행 claim은 프로젝트 흐름과 같은 `ResourceLeases`를 사용한다.
다른 작업의 실행 중·확인 불가 claim은 소유 작업과 이유를 표시하고 보존한다.

## 설치와 결과

iOS는 `simctl install`을 사용한다. Android는 `adb install -r`을 사용한다.
자동 uninstall, clear-data, 삭제 후 재시도, 강제 종료와 개발 서버 연결은 하지 않는다.
현재 앱 ID와 빌드의 설치 관측이 성공해야 실행을 요청한다.
이 관측은 설치된 payload 전체 hash나 표본 데이터 보존의 증명이 아니다.

JSON은 기존 `schemaVersion: 1`, `toolVersion`, `command`와 공통 encoder를 사용한다.
사람용 CLI 출력은 제어문자를 `\u{001B}`처럼 표시한다.
`--verbose` 도구 로그도 마지막 출력 경계에서 같은 규칙을 적용한다.
logger가 붙인 마지막 줄바꿈 하나만 유지한다. 실제 도구 argv는 바꾸지 않는다.
파일 metadata·승인 hash·JSON 값은 원본을 유지한다.
빌드 비교는 숫자 구간과 iOS의 `d`·`a`·`b`·`fc` suffix를 포함한다.
정식 build는 같은 숫자 구간의 prerelease build 뒤에 온다.
`downgrade`는 확인한 이전 빌드를 뜻한다. `buildOrderUnknown`은 비교 불가를 뜻한다.
두 경우 모두 별도 `DOWNGRADE:` 위험 승인을 요구한다.
GUI도 두 경우에 위험 확인을 요구한다. 비교 불가를 안전한 upgrade로 처리하지 않는다.
`operation`은 다음 값을 별도로 제공한다.

| 값 | 의미 |
| --- | --- |
| `installation` | 요청 전·설치 요청·설치 관측·확인 불가 |
| `installed` | 현재 앱 설치 metadata의 재관측 |
| `launch` | 요청 전·요청·플랫폼 요청 수락 |
| `running` | 실제 process 관측·중지·확인 불가 |
| `firstScreen` | 항상 `unverified`. 실제 화면 증거는 별도다. |
| `externalServer` | 확인 불가. Runstir가 서버를 만들거나 연결하지 않았다. |

실패·취소 뒤에는 가능한 범위에서 설치 상태를 다시 관측한다.
재관측이 실패하면 확인 불가로 남긴다. 설치와 데이터를 삭제하지 않는다.
설치 요청 후 결과를 확인하지 못한 device reservation도 보존한다.
다음 실행은 현재 상태로 새 계획을 만든다. 파일·기기·교체 내용이 바뀌면 다시 승인한다.

## GUI와 취소

시작 화면의 `앱 파일 열기…`로 진입한다. 파일 선택은 검사만 시작한다.
각 실제 경로의 창이 기기 선택과 계획·이전 빌드 경고·명시적 승인을 표시한다.
기존 프로젝트 창과 파일 창은 같은 `GUIOperationSession` 취소 완료 경계를 사용한다.
한 창을 취소해도 다른 창의 작업을 취소하지 않는다.
창 닫기는 작업 계속 또는 취소 후 닫기를 선택하게 한다.
전체 종료는 진행 중인 작업을 표시한다. 새 작업을 막고 모든 취소 처리가 끝날 때까지 기다린다.
완료한 모바일 앱과 가상 기기를 창 닫기와 GUI 종료로 중단하지 않는다.

## 완료 판정에 필요한 실제 검증

fixture 테스트는 parser·승인·충돌·실패 경계만 확인한다.
실제 SDK 설치·가상 기기 실행·표본 데이터 보존의 증거로 사용하지 않는다.
#218의 기존 수용 기준을 모두 유지한다.

1. 같은 파일과 기기 입력으로 CLI와 GUI의 파일 확인·계획·승인·설치·실행 요청·첫 화면을 확인한다.
2. 실제 Simulator `.app`와 Emulator APK를 각각 확인한다. 파일·내용 식별·기기·OS·architecture·도구를 고정한다.
3. 같은 앱의 표본 데이터를 넣고 교체·이전 버전 거부·재시도 뒤 데이터 보존을 관측한다.
4. 부적합·필수 정보 불명·파일 변경·설치 실패·취소·연결 해제 뒤 상태와 재승인을 확인한다.
5. 파일과 프로젝트의 독립 실행과 기기 충돌을 확인한다. 기존 자원과 다른 작업의 보존을 확인한다.
6. 파일별 창 재사용·별도 창·키보드·포커스·VoiceOver·창 닫기·전체 종료를 실제 GUI에서 확인한다.
7. #199 AC12·AC13·AC14에 증거를 연결한다. 서명·공증·배포는 전체 개발·테스트 뒤 마지막 단계로 유지한다.

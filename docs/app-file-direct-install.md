# 소스 없는 Simulator·Emulator 앱 파일 실행

관련 구현 티켓은 [#218](https://github.com/minjunkim-dev/mobile-runtime/issues/218)이다.
수용 기준은 [로컬 앱 설치 계약](./local-app-installation-contract.md)을 따른다.
이 문서는 명령과 구현 경계를 설명한다. 실제 설치·화면·데이터 보존 검증의 결과표가 아니다.

## 입력과 명령

이 경로는 iOS Simulator `.app` 디렉터리와 Android Emulator의 단일 `.apk`를 받는다.
iOS 실기기용 Development·Ad Hoc `.app`은 아래 [iOS 실기기 `.app`](#ios-실기기-app)의 같은 경로를 쓴다(#219).
실기기용 `.ipa`는 [IPA](#ipa)에서 안전하게 추출한 `.app`을 같은 경로로 보낸다(#220).
프로젝트 소스와 계정은 필요하지 않다. 소스 빌드와 환경 준비를 시작하지 않는다.
AAB·split APK 묶음·범용 압축 파일, 앱 목록·보유 버전·설치 이력과 앱 콘솔은 이 경로에 추가하지 않는다.

```sh
mobile app inspect /path/Local.app --json
mobile app run /path/Local.app --platform ios --device SIMULATOR-UDID --plan --json
mobile app run /path/Local.app --device SIMULATOR-UDID --approve EXACT-PLAN-ID --non-interactive --json --progress-json

mobile app inspect /path/Local.apk --json
mobile app run /path/Local.apk --platform android --device avd:EXISTING-AVD --plan --json  # 꺼진 AVD는 승인 뒤 부팅
mobile app run /path/Local.apk --device avd:EXISTING-AVD --approve EXACT-PLAN-ID --non-interactive --json
```

`inspect`와 `run`의 `--platform ios|android`는 선택 사항이다. 생략하면 검사한 파일의 플랫폼을 사용한다.
명시한 플랫폼이 검사한 파일과 다르면 계획·설치·실행 전에 중단한다. 기존 승인은 불일치를 허용하지 않는다.
`--device`에는 현재 후보의 고정 ID를 사용한다. 기기를 자동 선택하거나 전환하지 않는다.
꺼진 Simulator와 실행하지 않은 AVD도 고를 수 있다. 아래 [꺼진 가상 기기 부팅](#꺼진-가상-기기-부팅)을 따른다([ADR-0043](./adr/0043-app-file-boots-selected-virtual-device.md)).
Android 후보는 현재 연결된 Emulator와 설치된 AVD다. 실제 기기와 새 AVD 생성은 이 경로에 포함하지 않는다.
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

## 꺼진 가상 기기 부팅

후보는 `boot: required`로 "꺼짐 · 승인 후 Runstir가 부팅"을 표시한다.
iOS는 `Shutdown`·사용 가능이고 runtime capability를 읽을 수 있는 Simulator다.
Android는 `emulator -list-avds`의 AVD 중 실행 중인 Emulator가 없고 `config.ini`·system image·API·ABI가 있는 것이다.
실행 중인 Emulator의 AVD 이름을 하나라도 읽지 못하면 부팅 후보를 내지 않는다.
`Booting` 같은 다른 상태와 runtime·image가 없는 기기는 수동 준비 필요다. runtime·AVD 생성과 image 다운로드는 하지 않는다.

계획의 기존 앱은 `unobserved`다. `BOOT:` 경고가 부팅과 계속 실행을 알린다. `inspect`·`--plan`·승인 없는 실행은 부팅하지 않는다.
승인 뒤 기기 lease 안에서 파일 사본과 기기 상태를 다시 확인하고 그 기기만 부팅한다.
부팅 직전 기기를 다시 읽는다. 더는 꺼져 있지 않으면 부팅하지 않고 `deviceBoot`도 남기지 않는다.
iOS는 `up`과 같은 headless `simctl bootstatus <UDID> -b`를 실행한다. Simulator.app을 열지 않는다.
Android는 `up`과 같은 `emulator -avd <name>`을 분리 실행하고 같은 준비 판정으로 최대 300초 기다린다.
준비된 AVD는 Runstir가 시작한 launcher가 살아 있을 때만 인정한다. launcher가 끝나면 즉시 실패한다.
AVD 목록을 읽지 못하면 부팅 후보만 빠지고 실행 중인 Emulator는 그대로 쓸 수 있다.
부팅 뒤 이름·OS·runtime identity와 호환성을 다시 확인한다. 기존 앱이 없을 때만 승인한 설치를 계속한다.
앱이 있거나 확인 불가면 설치하지 않는다. 부팅한 기기로 만든 교체 계획을 다시 승인받는다.

결과의 `deviceBoot`는 Runstir가 시작한 기기의 `requested`·`started`·`unconfirmed`와 UDID 또는 serial·launcher PID·Emulator log를 기록한다.
Runstir는 부팅한 기기를 계속 실행 상태로 둔다. 나중에 종료하지 않는다. 필요 없으면 사용자가 직접 종료한다.
iOS `down`도 Simulator를 끄지 않는다(ADR-0007). Android `down`은 프로젝트 active run의 Emulator만 끈다(ADR-0013).
이미 실행 중인 기기는 부팅하지 않고 쓴다. 다른 기기를 부팅·전환·종료하지 않는다.
부팅 중 실패·취소하면 `unconfirmed`로 기록하고 기기 상태를 별도 작업에서 다시 관측한다. 설치하지 않고 기기를 끄지 않는다.

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

실패·취소 뒤에는 가능한 범위에서 설치 상태를 다시 관측한다. 취소된 작업은 새 도구를 시작하지 못하므로 이 관측은 취소를 물려받지 않는 별도 작업에서 한다.
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
완료한 모바일 앱과 가상 기기를 창 닫기와 GUI 종료로 중단하지 않는다. Runstir가 부팅한 기기도 같다.

## iOS 실기기 `.app`

관련 구현 티켓은 [#219](https://github.com/minjunkim-dev/mobile-runtime/issues/219)다.
Info.plist의 `CFBundleSupportedPlatforms`가 `iPhoneOS`인 `.app`은 실기기 provider로 보낸다.
명령·계획·승인·파일 lease·작업 전용 사본·교체/이전 빌드·충돌·결과 형식은 위 경로와 같다.

```sh
mobile app inspect /path/Device.app --device DEVICE-UDID --json
mobile app run /path/Device.app --device DEVICE-UDID --plan --json
mobile app run /path/Device.app --device DEVICE-UDID --approve EXACT-PLAN-ID --non-interactive --json
```

파일 검사는 Simulator와 같은 Info.plist·Mach-O 규칙을 쓴다. platform은 `iPhoneOS`와 Mach-O platform 2다.
`embedded.mobileprovision`은 `security cms -D`로 읽는다. 서명은 `codesign --verify --deep --strict -R=anchor apple generic`로 확인한다. profile CMS 서명 자체의 최종 확인은 설치 결과다.
서명 leaf 인증서를 추출해 profile의 `DeveloperCertificates`에 있는지 SHA-256으로 비교한다.
`get-task-allow`가 참이면 Development, 아니면 Ad Hoc이다.
모든 기기를 허용하는 Enterprise profile, 기기 목록이 없는 App Store profile, profile 없는 `.app`은 검사에서 중단한다.
profile의 UDID 목록은 JSON과 사람용 출력에 넣지 않는다. 개수와 선택 기기의 포함 여부만 보고한다.

기기는 고정한 Xcode의 `devicectl list devices`에서 `reality: physical`, `platform: iOS`만 후보로 쓴다.
`--device`는 UDID다. 선택한 기기만 `devicectl device info details`로 현재 상태를 읽는다.
이 조회가 실패하면 연결 조건을 `unreachable`로 기록한다. 다른 기기로 바꾸지 않는다.
선택하지 않은 기기와 페어링되지 않은 기기는 연락하지 않는다. pairing 요청을 만들지 않기 위해서다.
목록의 유휴 연결은 준비 여부 판정에 쓰지 않는다.
architecture는 CoreDevice의 `supportedCPUTypes` capability다. 기기 CPU 측정이 아니다.

선택 기기가 있으면 `operation.prerequisites`에 아래 조건을 `satisfied`·`unsatisfied`·`unknown`으로 기록한다.
충족하지 않은 조건은 `observed`와 수동 `action`을 가진다. 하나라도 충족하지 않으면 계획을 만들지 않는다.
조치 뒤 같은 `inspect` 명령이 다시 확인이다. 승인 뒤 설치 직전에도 같은 검사를 다시 한다.

| id | 확인 |
| --- | --- |
| `signature` | strict 서명 검증, 서명 team과 profile team, 서명 인증서의 profile 포함 |
| `profile-app-id` | profile의 application-identifier와 앱 ID |
| `profile-expiration` | profile 만료 시각 |
| `profile-device` | 선택 UDID의 profile 포함 |
| `os` | 앱 최소 iOS와 기기 iOS |
| `architecture` | 앱 slice와 기기 CPU capability |
| `trust` | CoreDevice pairing |
| `developer-mode` | Developer Mode |
| `connection` | 선택 기기의 현재 연결 |

Runstir는 기기 등록·profile 생성·재서명·계정 입력·pairing 변경·Developer Mode 변경을 하지 않는다.
기기를 계정에 등록해도 기존 앱 파일은 바뀌지 않는다. 그 기기를 포함한 profile로 다시 서명·내보내야 한다.
이 조건 검사는 사전 검사다. 최종 수락은 `devicectl device install app`의 결과다.
설치 관측은 `devicectl device info apps --include-all-apps --bundle-id`의 build다.
실행 요청은 `devicectl device process launch`다. 기존 실행 종료 옵션을 쓰지 않는다.
실행 관측은 `devicectl device info processes`에서 설치 위치 바로 아래 실행 파일의 process다.
`/private/var`와 `/var` 표기를 같은 위치로 비교한다. 비교할 수 없는 위치는 중지가 아니라 확인 불가다.
실패·취소 뒤 설치 상태 재관측은 위 경로와 같다. 연결이 끊기면 확인 불가로 남긴다.

## IPA

관련 구현 티켓은 [#220](https://github.com/minjunkim-dev/mobile-runtime/issues/220)이다.
`.ipa`는 실기기 provider만 쓴다. 명령은 위 `.app`과 같다. 내용 식별값은 IPA 파일 바이트의 `sha256`이다.

```sh
mobile app inspect /path/Device.ipa --device DEVICE-UDID --json
mobile app run /path/Device.ipa --device DEVICE-UDID --approve EXACT-PLAN-ID --non-interactive --json
```

압축을 풀기 전에 central directory의 모든 entry를 검사한다. 이 검사에서 부적합하면 아무것도 쓰지 않고 이유를 표시한다.
크기·CRC 불일치는 추출 중에, 실제 link 해석의 탈출·dangling은 추출 직후에 발견한다. 그때도 작업 소유 위치 밖에는 쓰지 않고 그 위치를 지운다.

- 절대경로, `..`·`.`·빈 경로 구성요소, 역슬래시, `:`, 제어문자, UTF-8이 아니거나 앞에 byte-order mark가 있는 이름, 1,024바이트·64단계를 넘는 경로
- 대소문자만 다른 두 번째 `payload` 폴더
- 같은 이름과 대소문자·Unicode 정규화만 다른 이름, 파일·링크 아래의 entry
- 일반 파일·디렉터리·symlink가 아닌 entry, 암호화, stored·deflate 이외의 압축
- `Payload` 바로 아래가 `.app` 디렉터리 하나가 아닌 구조(없음·복수·다른 파일)
- ZIP64·분할 archive, local header와 central directory의 이름·방식·CRC·크기 불일치, 서로 겹치는 entry 데이터
- 자원 한도: entry 100,000개, central directory 64 MiB, 풀린 크기 합계 8 GiB, 임시 volume 여유 공간

추출은 작업 소유 임시 디렉터리(0700)에서 한다. `Payload/<이름>.app` 아래만 푼다. 그 밖의 entry는 검사만 하고 풀지 않는다.
디렉터리는 한 단계씩 만들고 경로에 이미 파일·link가 있으면 중단한다. volume이 같게 보는 이름의 충돌도 이렇게 막는다.
파일은 새로 만든다(`O_EXCL`·`O_NOFOLLOW`). 선언한 크기를 넘는 출력은 즉시 중단하고 크기와 CRC를 확인한다.
권한은 Unix·macOS에서 만든 entry의 rwx 비트를 보존한다. 권한이 없는 entry는 파일 0644, 디렉터리 0755다. setuid·setgid·sticky는 제거한다. 읽기와 정리를 위해 파일에는 소유자 읽기·쓰기, 디렉터리에는 소유자 rwx를 더한다.
symlink는 파일을 모두 쓴 뒤 만든다. 대상은 상대 경로이고 앱 안에 머물러야 한다.
추출한 `.app`은 위 `.app`과 같은 외부·절대·dangling link와 특수 파일 검사를 다시 통과해야 한다.

inspect는 IPA를 임시 위치에 풀어 metadata와 9개 조건을 읽고 그 위치를 지운다.
승인 뒤 실행은 IPA를 작업 전용 stage에 복사하고 승인한 SHA-256과 비교한다. 그 사본에서 다시 풀어 metadata를 비교하고 그 `.app`만 설치한다.
서명 검사(`codesign --verify --deep`)는 bundle 전체를 읽으므로 inspect도 전체를 푼다. 한 번의 `app run`은 최초 검사, 설치 직전 원본 재검사, stage 사본에서 세 번 푼다.
원본 IPA는 바꾸지 않는다. 재서명·기기 등록·계정 입력을 하지 않는다. 성공·실패·취소 모두 이 작업이 만든 임시 위치만 지운다.
안전 parser fixture는 실제 Development·Ad Hoc IPA의 설치 증거가 아니다.

## 완료 판정에 필요한 실제 검증

fixture 테스트는 parser·승인·충돌·실패 경계만 확인한다.
실제 SDK 설치·가상 기기 실행·표본 데이터 보존의 증거로 사용하지 않는다.
#218의 기존 수용 기준을 모두 유지한다.

1. 같은 파일과 기기 입력으로 CLI와 GUI의 파일 확인·계획·승인·설치·실행 요청·첫 화면을 확인한다.
2. 실제 Simulator `.app`와 Emulator APK를 각각 확인한다. 파일·내용 식별·기기·OS·architecture·도구를 고정한다.
   #219는 대표 iOS 실기기의 Development 또는 Ad Hoc `.app`을 같은 기준으로 확인한다. 미충족 조건의 거부와 다시 확인,
   선택 기기 조회가 미신뢰 기기에 pairing을 요청하는지도 기록한다. 전체 framework 실기기 행렬은 추가하지 않는다.
   #220은 실제 Development·Ad Hoc `.ipa`에서 추출한 앱의 서명 보존·확인·승인·설치·실행·첫 화면과 교체·취소 뒤 임시 위치 정리를 확인한다.
   안전 parser fixture의 부적합 archive 거부와 실제 IPA 설치 결과를 구분해 기록한다.
3. 같은 앱의 표본 데이터를 넣고 교체·이전 버전 거부·재시도 뒤 데이터 보존을 관측한다.
4. 부적합·필수 정보 불명·파일 변경·설치 실패·취소·연결 해제 뒤 상태와 재승인을 확인한다.
5. 파일과 프로젝트의 독립 실행과 기기 충돌을 확인한다. 기존 자원과 다른 작업의 보존을 확인한다.
6. 파일별 창 재사용·별도 창·키보드·포커스·VoiceOver·창 닫기·전체 종료를 실제 GUI에서 확인한다.
7. #199 AC12·AC13·AC14에 증거를 연결한다. 서명·공증·배포는 전체 개발·테스트 뒤 마지막 단계로 유지한다.

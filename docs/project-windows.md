# 프로젝트 창과 독립 개발 연결

관련: #217, #199 AC07·AC09. 기준 main: `b2e18620490fdf3aac9ca36e66d5138214d0f5a6`.

## 사용하는 계약

GUI는 기존 `AppDelegate.windows[FolderIdentity]`를 사용한다.
폴더 이름이나 Git 공통 저장소 경로로 창을 합치지 않는다.
선택·진행 task·event·결과는 창별 `InspectionView` state다.
작업은 공통 `WorkflowExecution`을 사용한다. CLI와 GUI가 같은 lease와 상태를 읽는다.
workspace의 변경 lease는 workspace 폴더에 걸린다. 서로 다른 worktree는 별도 폴더다.

React Native GUI의 `Metro port`와 CLI build/up의 `--port`는 같은 `WorkflowInput.port`다.
기본값은 8081이다. 두 독립 작업에는 서로 다른 포트와 기기를 선택한다.
`--port 8081`도 명시적 입력이다. 기존 Gradle `reactNativeDevServerPort=8097`이나
iOS 앱의 `RCT_jsLocation` 값이 있어도 8081을 start·build·launch에 전달한다.
port를 생략한 경우만 기존 native 인자를 유지한다. 명시적 8081에도 전달 지원 검사를 적용한다.
포트가 이미 사용 중이면 소유 작업과 이유를 표시한다. 자동 전환이나 종료는 없다.
native iOS·native Android는 이 개발 서버 입력을 소비하지 않는다. 명시하면 중단한다.
Flutter iOS up도 같은 `WorkflowInput.port`를 소비한다. Flutter의 VM service와
RN의 Metro는 다른 개발 연결이다. Flutter는 생략 시 사용 가능한 포트를 선택한다.
Flutter build/down은 명시적 port를 거부한다. GUI Flutter build/down은 port를 전달하지 않는다.
두 port 필드나 별도 parser를 만들지 않는다.

통합 검토 기준은 #207 `47509165a12bd1ea0dafad495e01ba1ee1f4df3a`와
#208 `7d3c02723d725f26b17e24403730d49cef8e4121`이다.
#207과 현재 변경 파일의 교집합은 없다. #208과의 교집합은 아래와 같다.

| 기존 파일 | 통합할 hunk |
| --- | --- |
| `Core/Up/Stage.swift` | RN `MetroProcess.port`와 Flutter `UpContext` 확장을 함께 유지 |
| `Core/Up/WorkflowOperation.swift` | `port`는 한 필드만 유지. Flutter entrypoint·service URI 추가 유지 |
| `EnvironmentKit/WorkflowExecution.swift` | `WorkflowInput.port`는 한 입력만 유지. RN/Flutter의 provider별 validation·port lease·factory 연결을 모두 유지 |
| `RunstirGUI/RunstirApp.swift` | 하나의 `port @State`와 parser 사용. RN Metro/Flutter VM service 표시와 entrypoint·scheme·device 흐름 유지 |
| `SimulatorKit/BuildStage.swift` | RN `RCT_METRO_PORT`와 Flutter build environment를 framework별로 적용 |
| `SimulatorKit/IOSUpStages.swift` | RN `metroPort`와 Flutter `flutterPort`를 같은 factory에 각각 전달 |
| `SimulatorKit/LaunchStage.swift` | RN launch argument·readiness port와 Flutter launch·service 관측·취소 동작을 함께 유지 |
| `mobile/WorkflowOptions.swift` | `--port`를 하나만 등록. Flutter entrypoint와 provider별 help·입력 전달 유지 |

RN custom port는 `react-native start` script와 설치된 native port 입력을 확인한다.
지원 근거가 없는 wrapper/custom 경로는 변경 전에 설명하고 중단한다.
프로젝트·lockfile·전역 설정·지속 앱 preference를 자동으로 바꾸지 않는다.
선택 포트의 build·launch·reverse·probe·cleanup 연결은 ADR-0042를 따른다.
선택 포트 기록은 iOS·Android별로 분리한다. 한 폴더의 다른 플랫폼 실행이
기존 플랫폼의 down 입력을 바꾸지 않는다. 기록 오류는 해당 플랫폼을 차단한다.

## 자동 검증 범위

| 요구 | 자동 근거 | 실제 검증 잔여 |
| --- | --- | --- |
| 일반 폴더·symlink·worktree identity | 기존 FolderIdentity fixture와 같은 repo marker의 두 폴더 fixture | 일반 폴더·alias 재열기와 별도 GUI 창 관측 |
| 같은 폴더 직렬화·독립 작업 병렬 | 실제 async build gate 중 alias 충돌, 다른 폴더 완료, event operation id·로그 경로 분리 | 두 독립 repo와 같은 repo의 실제 두 worktree 실행 |
| 포트 전달 | iOS build setting·launch argument·JSON, Android Gradle native input·reverse·launch-ready, 선택 endpoint의 probe·down | 선택 포트·listener·앱 요청·첫 화면을 같은 실행에서 확인 |
| 충돌·부분 실패 | 공통 port lease, 기록 오류·symlink·write 실패·이전 port 변경 거부, Metro bind 실패 후 기록 보존 | 실제 CLI·GUI 교차 프로세스 충돌과 기존 자원 보존 |
| 산출물·로그·상태 | 기존 RunLogs 경로와 provider product, 독립 event/result 검사 | 실제 Xcode/Gradle 산출물·앱·로그의 독립 identity |

이 표는 #217 AC를 완료로 표시하지 않는다. 실제 GUI 창·동시 앱·첫 화면은 아직 미검증이다.
창 닫기·앱 종료 정책은 #218의 별도 범위다.

로컬 검사는 기존 `/usr/bin/swift`와 `/usr/bin/python3`를 사용했다.
private HOME·CFFIXED_USER_HOME·TMPDIR·SwiftPM cache/config/security 경로를 사용했다.
기존 checkout의 locked dependencies를 복사했다. 자동 도구 설치·keychain·netrc는 사용하지 않았다.
`RUNSTIR_SIMULATOR_SMOKE_APP`은 전달하지 않았다.
최종 전체 `swift test -Xswiftc -warnings-as-errors`는 794개를 통과했다.
SimulatorKit 123개·EnvironmentKit 209개·Core 381개·AndroidKit 81개다.
source-only 검사는 61개를 통과했다. CLI `up --help`는 port 옵션을 표시했다.
CLI의 숫자가 아닌 port 입력은 usage exit 64로 중단했다.
Android launch-ready의 8081 잔존 질의는 8097 fixture에서 실패한 뒤 수정했다.
컴파일·fixture 준비 오류와 모든 실패 로그는 최종 성공 로그와 별도로 보존했다.
Spec 리뷰의 명시적 8081 누락을 RED 회귀로 재현했다.
8081·8097의 start·native build·launch 전달과 nil 입력의 기존 인자 보존을 확인했다.
원래 프로젝트에 선언한 Android 포트 8097은 수정하지 않았다.
명시적 8081의 미지원 native 입력은 CLI JSON에서 변경 단계 없이 중단했다.
전체 검사 부하에서 독립 build fixture의 5초 gate가 만료한 로그도 보존했다.
gate 한도를 30초로 바꿨다. 독립 작업 선행 완료·원작업 성공·timeout 부재 검사는 유지했다.

## RN 입력 원문 확인

준비된 원본은 읽기만 수행했다. source·SDK·Pods를 실행하거나 수정하지 않았다.
이 경로는 지원 성공 표본이나 archive provenance 증거가 아니다.

| 입력 | source SHA | 관측 |
| --- | --- | --- |
| RN 최소 역할 생성 앱 | `b62e3a4d5e7cfc05d7d948a5a4e30f0cc6a82bb4` | RN 0.87.1, start=`react-native start`, 기존 untracked `ios/RunstirBaselineRN.xcworkspace/`, React-Core-prebuilt |
| BlueWallet | `69adb1555038c8b2385952edd0404d2e1ecd7ca7` | tracked clean, RN 0.85.3, start=`react-native start` |

| 파일 SHA-256 | RN 0.87.1 | RN 0.85.3 |
| --- | --- | --- |
| `React-Core.podspec` | `dac625d28190d986319bc1241f20698feddf1fe546c4cf63762aa2ce3d28c3bb` | `240b6b4df47e980d38c3ac4ca0f1fbcf56816866e3a06d4d5fdf9cd5544f75f5` |
| `AgpConfiguratorUtils.kt` | `a4bd2483f21b31ccf09db2a1a08896aafa1cc64ab1812c1aed244347f9aa1f83` | `3db99fbea567e6a582c8d88f64642e1a0be24a51b74f6acfece047ba72b9e23c` |

RN 0.87.1 `RCTBundleURLProvider.mm` SHA-256은
`fbe72a474fd22a9f558f80266630f3865be0f85a2395b7a085c282379c523703`다.
이 원문은 `RCT_jsLocation`의 `NSUserDefaults` 값과 host:port URL 소비를 보여 준다.
Apple의 argument domain 계약은 실행 인자가 저장된 preference보다 먼저 적용되고
실행 후 사라지는 경로를 제공한다. 실제 iOS 앱의 요청 포트 검증은 별도다.

## 실제 실행 준비

1. 원본을 보존하고 실행 전용 fresh clone 두 개를 만든다.
2. Runstir source·binary·SDK·앱 source·의존성·기기·포트·산출물 identity를 고정한다.
3. root의 자원 일정에 따라 두 작업에 서로 다른 기기와 포트를 예약한다.
4. CLI·GUI로 독립 repo와 같은 repo의 worktree 조합을 실행한다.
5. 포트와 앱 요청·첫 화면·로그·산출물·기존 자원 보존을 같은 시도에 기록한다.

실패·inconclusive·취소는 별도 시도로 보존한다. 원본 환경을 수정하거나 실패를 fixture 성공으로 대체하지 않는다.
기존 수용 기준은 유지한다. 배포 서명·공증·업로드·공개는 수행하지 않는다.


## 실제 폴더 identity와 기존 실행 호환 경계

새 log·install.json·Android active-run/lock·선택 port는 기존 RunLogs의
folder-<volume>-<file> child를 공유한다. volume·file은 FolderIdentity의 값이다.
실제 owned temp FNV collision 입력으로 로그·설치 기록·port·Android record/lock 분리를 검사한다.
CLI/GUI는 같은 WorkflowExecution과 lease를 유지한다. 검사는 실제 병렬 앱·첫 화면의 근거가 아니다.

base-MAIN의 검증된 legacy Android down은 원래 경로의 lock과 cleanup을 사용한다.
legacy iOS install은 같은 reservation book의 confirmed owner project·device·appID가 필요하다.
legacy port 파일은 base-MAIN에 없었다. 이전 미병합 개발 head의 FNV-only port 파일은
소유권 미확인으로 보존·차단한다. 자동 이관과 값 복제는 하지 않는다.

### main65의 #208 통합

통합한 main은 `65e14c4e32dda320f2fda7fb0c5156eee437139e`다.
main의 #208 산출물은 `aacd2482925ea51a29a26059fff1ff7c45ad8beb`과 같은 tree다.
RunLogs의 folder identity namespace를 유지한다. InstallRecord.read의 throws를 새 fixture에 전파한다.
FlutterIOSWorkflow.swift의 profile 생성은 기존 best-effort logs.write를 유지한다.
profile UUID·기존 sandbox와 보호 입력 검사·stage guard·concrete destination 계약을 보존한다.
공통 CLI/GUI down은 같은 lease book과 선택 app의 owner project를 AppTeardown에 전달한다.
Flutter의 native 입력과 RN의 selected port를 framework별로 유지한다.
위 자동 검증 수치와 9fcc의 실제 실행 기록은 통합 전 근거다.
통합 source의 host 검증은 별도 receipt로 기록한다. 통합 source의 실제 VM·기기·GUI 실행은 별도다.

기존 runtime02의 c008 DerivedData 모델과 query packet은 과거 probe 기록으로만 보존한다.
새 namespace의 getter 실측이나 실행 계획으로 재사용하지 않는다. 이 수정으로 candidate를
새로 복사하거나 실제 query·build·VM·기기·GUI 실행을 하지 않았다.

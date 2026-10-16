# 시도 04의 plain native 명령과 준비

정확한 인자 순서는 [commands.json](commands.json)에 기록했다.
개인 경로와 기기 identity는 별칭으로 바꿨다.
각 `privateCommandReceiptSHA256`은 원본 receipt와 연결된다.
원본 wrapper가 기록한 `rawCommandSHA256`도 그대로 남겼다.
별칭을 실제 private 값으로 대응하기 전에는 복사 실행할 명령이 아니다.

## 입력과 실행 경계

1. 원래 고정 source에서 `git clone --local --no-hardlinks --no-checkout`과 정확한 detached checkout으로 native 2개와 fresh Runstir 2개를 만들었다.
2. [tuple](tuple.json)의 source·선택·source/index/stage/flags를 고정했다.
3. Apple prepin `93ad655b95b357fa489c92d49fa0ad0e7e6a55ba4cf70c8be25df31f9f1eac70`을 참조했다.
4. 첫 build 전에 OS·arch·own device·native argv·환경·own DD/SPM/cache를 pretuple로 저장했다.
5. default device set에 새 own Simulator 1대만 만들었다. 기존 기기는 read-only 관측만 했다.

## Native build와 원본 선언

Food는 `-project 'Food Truck.xcodeproj' -scheme 'Food Truck' -configuration Debug -sdk iphonesimulator`를 사용했다.
NNW는 `-project NetNewsWire.xcodeproj -scheme NetNewsWire-iOS -configuration Debug`를 사용했다.
NNW의 원래 target별 SDK 선언을 보존하려고 전역 `-sdk`를 넣지 않았다.
각 build는 own device의 명시적 destination을 사용했다.
`-derivedDataPath`, `-clonedSourcePackagesDirPath`, `-packageCachePath`는 모두 own 경로다.
다음 고정 옵션을 사용했다.

```text
-disablePackageRepositoryCache
-disableAutomaticPackageResolution
-onlyUsePackageVersionsFromResolvedFile
-skipPackageUpdates
CODE_SIGNING_ALLOWED=NO
CODE_SIGNING_REQUIRED=NO
CODE_SIGN_IDENTITY=
DEVELOPMENT_TEAM=
```

NNW에 `ORGANIZATION_IDENTIFIER`나 `DEVELOPER_ENTITLEMENTS` override를 넣지 않았다.
원래 `com.ranchero.NetNewsWire.iOS-DEBUG`를 유지했다.
source·lock을 고치거나 성공용으로 선언을 완화하지 않았다.

## NNW V1 실패와 V2 준비

V1 build는 exit65다.
첫 `Secrets.SwiftFileList`는 generated `SecretKey.swift`를 포함하지 않았다.
실패 뒤 생성 파일은 존재했다.
정확한 planning 인과는 미확정이다.
Root는 원래 tracked `buildscripts/updateSecrets.sh`의 명시 실행을 승인했다.
`/usr/bin/env -i`에서 아래 변수만 공급했다.
실제 argv는 tuple의 `manualNNWPreparation`에 있다.

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
HOME=${PRIVATE214_REPIN}/preparation-home
LANG=en_US.UTF-8
PATH=/usr/bin:/bin:/usr/sbin:/sbin
PROJECT_DIR=${PRIVATE214_REPIN}/sources/native/netnewswire
PYTHONDONTWRITEBYTECODE=1
PYTHONNOUSERSITE=1
TMPDIR=${PRIVATE214_REPIN}/tmp/
```

`MERCURY_CLIENT_ID`, `MERCURY_CLIENT_SECRET`, `FEEDLY_CLIENT_ID`, `FEEDLY_CLIENT_SECRET`, `INOREADER_APP_ID`, `INOREADER_APP_KEY`는 없었다.
그 밖의 상속 환경도 제거했다.
private key나 OAuth 값은 읽거나 공급하지 않았다.
원래 script와 template SHA, ignored 출력 SHA만 기록했다.
새 own DerivedData에서 V2 build는 exit0이다.
V2 FileList는 generated source를 포함한다.
명시 준비·새 DerivedData·Python 환경 제어가 함께 달라졌다.
단일 원인 실증으로 주장하지 않는다.

## Install·launch·화면·종료

정확한 앱 bundle 경로와 default app ID는 commands·tuple·results에서 연결한다.
모든 변경 `simctl` 명령의 대상은 own device다.
Food의 원래 PID `68644`는 외장 경로 캡처 실패 2회 뒤에도 같았다.
권한 설정을 바꾸지 않고 승인된 내부 staging으로 캡처했다.
NNW V2의 3초 검정 화면과 V3의 10초/30초 popup 화면을 보존했다.
V3에는 build/install을 반복하지 않았다.
notification followup도 같은 설치 artifact를 한 번 launch했다.
PID는 `49586`이다.
같은 PID에서 최종 PNG를 1회 캡처했다.
Root가 가림없는 Device Hub 화면과 최종 PNG를 직접 확인했다.
이후 own app terminate·PID 부재·own Simulator shutdown을 회수했다.

Root의 앱 화면·알림 버튼·권한 입력은 0회다.
Root는 Device Hub의 sidebar와 선택 row만 이동하고 원래 상태로 복귀했다.
popup 재표시 부재의 원인과 authorization enum은 unknown이다.

시각·실제 대기·종료 코드·명령 SHA는 [commands.json](commands.json)과 [results.json](results.json)에 있다.
정규화한 명령 결과 발췌는 [native-command-excerpt.log](native-command-excerpt.log)다.
전체 원본 로그와 개인 경로는 공개하지 않는다.

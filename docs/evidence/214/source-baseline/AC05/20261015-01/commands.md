# #214 실행 명령과 준비 경계

`PRIVATE214`는 이 시도의 제한 접근 원본 디렉터리다.
`OWN_UDID`는 `tuple.json`의 `deviceIdentitySHA256`과 연결한 실제 전용 기기다.
실제 경로, UDID, 앱 PID와 전체 로그는 제한 접근 원본에 보관한다.
아래 경로·기기 변수는 공개 비식별 표기다.
원본 실행에서는 각각 실제 절대경로와 UDID를 사용했다.
환경 준비와 실행은 해당 프로세스 범위에만 적용했다.

## 실행 전 확인

1. `ps -A -o pid=,comm=`으로 실행 중인 빌드·설치·기기를 확인했다.
2. `xcode-select -p`로 기존 전역 Xcode 선택을 읽었다.
3. Xcode `version.plist`, `Info.plist`, SDK·runtime·기기 metadata를 읽었다.
4. 원본 source SHA, tracked 원본 byte별 SHA-256과 index tree를 고정했다.
5. 기존 Booted 기기의 설치 앱 ID·버전·종류 목록을 정규화한 hash를 고정했다.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -version
xcodebuild -checkFirstLaunchStatus
xcrun simctl list --json devices runtimes devicetypes
xcrun simctl create Runstir214-baseline-20261015 \
  com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro \
  com.apple.CoreSimulator.SimRuntime.iOS-27-0
```

실행 컨텍스트의 `DEVELOPER_DIR`만 명시했다.
`xcode-select --switch`, 전역 PATH 변경, runtime 설치, 기존 기기 종료를 실행하지 않았다.
도구 설치나 라이선스 승인을 실행하지 않았다.
공유 자원 조정 담당자가 #214 전용 기기와 빌드 lease를 배정했다.
이 lease 중 다른 iOS baseline과 runtime 설치를 시작하지 않도록 조정했다.

## Food Truck: 시도 01

원본 단순 `Food Truck` scheme을 사용했다.
`Food Truck All` scheme을 사용하지 않았다.
외부 package가 없는 원본 `FoodTruckKit/Package.swift`를 확인했다.
원격 dependency lock은 이 표본에 적용하지 않는다.

```sh
cd "$PRIVATE214/food-truck"
xcodebuild -project 'Food Truck.xcodeproj' -scheme 'Food Truck' \
  -configuration Debug -sdk iphonesimulator \
  -destination "platform=iOS Simulator,id=$OWN_UDID" \
  -derivedDataPath "$PRIVATE214/derived-food" \
  -clonedSourcePackagesDirPath "$PRIVATE214/packages-food" \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM= build
xcrun simctl boot "$OWN_UDID"
xcrun simctl bootstatus "$OWN_UDID" -b
xcrun simctl install "$OWN_UDID" \
  "$PRIVATE214/derived-food/Build/Products/Debug-iphonesimulator/Food Truck.app"
xcrun simctl launch "$OWN_UDID" com.example.apple-samplecode.Food-Truck
xcrun simctl io "$OWN_UDID" screenshot "$PRIVATE214/food-first-screen.png"
```

빌드는 exit 0으로 끝났다. 53.839초가 걸렸다.
원본 source의 경고가 남았다. 경고를 검사 성공과 혼동하지 않는다.
앱을 설치한 뒤 실제 앱 PID와 첫 화면을 확인했다.
`Truck`, `New Orders`, `Forecast`가 표시됐다.
확인한 화면에 red box·crash 화면·빈 화면이 없었다.
이 관측은 첫 화면에만 해당한다.
기능 전체, 네트워크 서비스와 장시간 안정성을 검사하지 않았다.

## NetNewsWire: 시도 01

원본 `Package.resolved`를 유지했다.
원본 scheme pre-action과 package manifest를 실행 전에 검토했다.
pre-action의 `buildscripts/updateSecrets.sh`는 ignored `SecretKey.swift`를 생성한다.
이 파일은 tracked source가 아니다.
다음 변수 여섯 개를 자식 프로세스 환경에서 제거했다.
변수의 기존 값이나 자격을 읽어서 기록하지 않았다.

```text
MERCURY_CLIENT_ID
MERCURY_CLIENT_SECRET
FEEDLY_CLIENT_ID
FEEDLY_CLIENT_SECRET
INOREADER_APP_ID
INOREADER_APP_KEY
```

계정, Team ID, API key를 제공하지 않았다.
원본 `setup.sh`를 실행하지 않았다.
개발용 build setting은 명령에서만 전달했다.
원본 프로젝트·scheme·lock을 수정하지 않았다.

```sh
cd "$PRIVATE214/netnewswire"
xcodebuild -project NetNewsWire.xcodeproj -scheme NetNewsWire-iOS \
  -configuration Debug -sdk iphonesimulator \
  -destination "platform=iOS Simulator,id=$OWN_UDID" \
  -derivedDataPath "$PRIVATE214/derived-netnewswire" \
  -clonedSourcePackagesDirPath "$PRIVATE214/packages-netnewswire" \
  -packageCachePath "$PRIVATE214/package-cache-netnewswire" \
  -disablePackageRepositoryCache -disableAutomaticPackageResolution \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
  DEVELOPMENT_TEAM= DEVELOPER_ENTITLEMENTS=-dev \
  ORGANIZATION_IDENTIFIER=org.runstir.baseline214 build
```

시도 01은 exit 65로 끝났다. 70.949초가 걸렸다.
전역 `-sdk iphonesimulator`가 macOS target의 `SDKROOT=macosx`까지 덮었다.
macOS·iOS target이 같은 `NetNewsWire.app`을 만들려고 했다.
macOS 전용 Sparkle에 iOS Simulator library가 없다는 오류도 나왔다.
원본 CI의 iOS 명령은 `-sdk` 없이 `-destination`을 사용한다.
이 실패는 Runstir 실패가 아니다.
명령 구성 실패 이력을 보존한다.

## NetNewsWire: 시도 02

시도 01 뒤에도 원본 tracked byte가 같음을 확인했다.
전역 `-sdk`만 제거했다.
각 target의 원본 SDK 선언을 유지한다.
빌드 결과를 새 `derived-netnewswire-02`에 분리한다.
source SHA·lock·정확한 package pin·runtime·기기·설정은 유지한다.
원본 CI의 `SKIP_APP_GROUP_ACCESS` flag를 추가하지 않았다.

```sh
cd "$PRIVATE214/netnewswire"
xcodebuild -project NetNewsWire.xcodeproj -scheme NetNewsWire-iOS \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$OWN_UDID" \
  -derivedDataPath "$PRIVATE214/derived-netnewswire-02" \
  -clonedSourcePackagesDirPath "$PRIVATE214/packages-netnewswire" \
  -packageCachePath "$PRIVATE214/package-cache-netnewswire" \
  -disablePackageRepositoryCache -disableAutomaticPackageResolution \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
  DEVELOPMENT_TEAM= DEVELOPER_ENTITLEMENTS=-dev \
  ORGANIZATION_IDENTIFIER=org.runstir.baseline214 build
```

시도 02의 빌드는 exit 0으로 끝났다. 223.896초가 걸렸다.
원본 local package의 sysroot 경고를 보존했다.
앱과 extension·framework의 플랫폼 metadata는 모두 `iPhoneSimulator`였다.
설치는 긴 대기 뒤 exit 0으로 끝났다. 대기 원인은 확정하지 못했다.
설치 완료 전에 시작한 첫 launch 조회는 code 4로 끝났다.
이 호출 순서는 실행자의 오류다. 앱 실패로 분류하지 않는다.
설치 완료를 확인한 뒤 실행한 launch는 exit 0으로 끝났다.

```sh
xcrun simctl install "$OWN_UDID" \
  "$PRIVATE214/derived-netnewswire-02/Build/Products/Debug-iphonesimulator/NetNewsWire.app"
# Wait for installation to finish successfully before launching.
xcrun simctl launch "$OWN_UDID" org.runstir.baseline214.NetNewsWire.iOS-DEBUG
xcrun simctl io "$OWN_UDID" screenshot "$PRIVATE214/netnewswire-first-screen.png"
```

앱 PID와 실제 `Feeds` 화면을 확인했다.
시스템 알림 권한 팝업이 화면 일부를 가렸다.
전용 기기를 선택한 임시 XcodeBuildMCP profile로 화면을 읽었다.
`허용 안 함`에 대한 semantic tap을 실행했다.
도구는 성공을 보고했다. 새 PNG에는 팝업이 남았다.
따라서 권한 선택 완료와 가림 없는 첫 화면은 미확인이다.
권한을 우회하는 플래그나 source 변경을 추가하지 않았다.

관측 뒤 임시 UI profile 값을 지웠다. 원래 global profile을 복원했다.
프로젝트 파일에 UI 도구 설정을 저장하지 않았다.

```sh
xcrun simctl shutdown "$OWN_UDID"
```

전용 기기의 종료는 exit 0으로 끝났다.
최종 `device.plist` 상태는 전용 기기 `1`과 기존 기기 `3`이다.
이는 각각 `Shutdown`과 `Booted`다.
2026-10-15 20:45:12 KST에 iOS lease를 반환했다.

## 보존 검사

tracked 원본 byte hash는 각 경로의 SHA-256을 계산한 JSON object를 사용한다.
symlink는 link target의 UTF-8 byte를 사용한다.
JSON은 `sort_keys=True`, `separators=(',', ':')`로 직렬화한다.
그 직렬화 결과의 SHA-256을 공개 manifest에 기록한다.
전후 경로별 hash도 제한 접근 원본에 보관한다.
`git status --porcelain=v1 -uno`와 index tree도 함께 비교한다.
Git status만으로 원본 raw byte 보존을 주장하지 않는다.

기존 기기 inventory는 `simctl listapps` 결과에서 앱 ID를 key로 사용한다.
`CFBundleVersion`, `CFBundleShortVersionString`, `ApplicationType`만 정규화한다.
같은 JSON 직렬화 방식으로 전후 hash를 비교한다.
이 검사는 기존 설치 앱 ID·버전·종류의 보존에 해당한다.
기존 앱의 전체 사용자 데이터 보존을 입증하지 않는다.

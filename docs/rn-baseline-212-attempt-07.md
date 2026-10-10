# RN baseline #212 attempt-07: iOS native 필수 실패

2026-10-10 기록이다. 원본 frozen 준비와 승인한 12개 generated Debug 설정 준비는 통과했다. native iOS build는 exit 65로 실패했다. Q5의 필수 실패 중단 기준을 적용했다. install·launch·Android·fresh 후속 단계를 시작하지 않았다. #212는 OPEN이다. PR #236은 미병합이다. Runstir를 실행하지 않았다. attempt-06과 이전 실패 이력을 보존했다.

## 입력과 준비 범위

실행 정책 main은 `9b9963a83e285b7dbe2e7c29d0b73d555dd6fad4`다. 원본 source는 [Mattermost `c2fe3beda22befd2178dce431793c09111ed903e`](https://github.com/mattermost/mattermost-mobile/tree/c2fe3beda22befd2178dce431793c09111ed903e)다. 새 baseline clone에서 원본 npm·hook, frozen Bundle, plain Pods, `pod install --deployment`와 tracked source 감사를 수행했다. 4216 tracked 파일의 허용한 Hermes 한 값 외 raw byte·파일 kind·Git 실행 bit·index·flags 불변 조건을 통과했다. 원본 serialized spec provenance는 unknown이다. 원본과의 차이가 경로뿐이라는 증거는 없다.

ADR-0022 범위에서 기존 11개 resource bundle과 ExpoRouter framework의 Debug `IPHONEOS_DEPLOYMENT_TARGET`만 `16.4`로 준비했다. semantic delta와 raw 변경은 각각 12개 값이다. 전체 parsed object 22792개를 역정규화한 비교와 array 순서 검사를 통과했다. Release·다른 설정·target·graph·source는 유지했다. 승인 대상 24개 xcconfig hash도 유지했다. project target 186개 중 Debug floor가 `16.4` 아래인 171개는 inventory 관측이다. 이 수를 추가 필수 실패나 추가 보정 대상으로 해석하지 않는다. sealed core self-check 56개, 별도 resource self-check 21개, 별도 post-wrapper self-check 11개는 모두 통과했다. 독립 검토도 통과했다. 이 검토를 native build PASS로 취급하지 않는다.

원본 `ios/Podfile.properties.json`의 실제 key `deploymentTarget`은 `16.4`다. generated Pods `PBXProject`의 Debug·Release도 `16.4`다. 이 Pods 선언을 앱 minimum과 같은 값으로 표시하지 않는다. 원본 `ios/Mattermost.xcodeproj/project.pbxproj`의 명시적 8개 값은 모두 `16.0`이다. 앱 project raw SHA-256 `8ed8c81f2861eec2f92c6a252edd0150ee8c0eb6a082aaf85373bbc3a28dd33f`를 유지했다. ExpoRouter는 Debug만 `16.4`로 준비했다. ExpoRouter Release는 원본 `15.1` 그대로다.

## native iOS 실패와 중단

Debug build는 `2026-10-10T23:06:22.388877+09:00`에 시작했다. `2026-10-10T23:12:01.861765+09:00`에 exit `65`로 끝났다. 실제 compile 단계에 들어갔다.

첫 compiler error는 `ios/Pods/Target Support Files/Pods-Mattermost/ExpoModulesProvider.swift:21:17`의 ExpoRouter import다. 앱 compiler는 iOS `16.0`을 대상으로 했다. 준비한 ExpoRouter Swift module은 minimum `16.4`를 요구했다. compiler가 이 차이를 거부했다. 원본 앱 project의 `16.0`을 바꾸거나 import source·build flag를 보정하지 않았다. iOS runtime 실행 실패로 분류하지 않는다. install과 launch 전 native compile 실패다.

실패 후 source 감사와 generated project 검사는 PASS다. 같은 clone의 frozen source binding, 전체 objects 역정규화 12값, prepared raw hash와 xcconfig hash를 다시 확인했다. 별도 사후 wrapper의 wrong-clone guard도 메모리 self-check에서 거부됨을 확인했다. 추가 source·target·설정 예외를 적용하지 않았다.

## archive cache와 원본 HTTP 다운로드

검증한 Hermes debug·release raw archive 두 개를 helper cache에 준비했다. debug raw archive SHA-256은 `07a69538c08ecc1569eb5e5ef1c57bae44ec38ab15b32b8a5291aa4353b90a0f`다. release raw archive는 `af777af183efde76275685216f8ec442cf163223a451a636863bcaf7afda2b0e`다. 이 재사용과 CocoaPods의 원본 source HTTP 다운로드는 별도다. CocoaPods 원본 명령은 HTTP 다운로드를 수행했다. plain Pod command는 `2026-10-10T21:31:40.378345+09:00`부터 `2026-10-10T23:05:35.869734+09:00`까지 실행했다. 전체 command 시간은 1시간 33분 55.491초다. 이 전체 시간을 순수 HTTP 전송 시간으로 단정하지 않는다.

원본 command를 중단하지 않았다. 원본 argv·source flag를 override하지 않았다. partial download를 덮어쓰지 않았다. Pods·node_modules·vendor·build·풀어 놓은 dependency 산출물은 복사하지 않았다. 공식 archive hash와 재사용 기록은 최종 manifest에 구분한다.

## 미실행과 cleanup

iOS install·launch·첫 화면, 새 Android 입력 build·install·launch·첫 화면, Mattermost fresh clone과 독립 준비, 최소 RN fresh clone과 frozen 준비는 미실행이다. partial `.app` 디렉터리 1개에는 Mattermost 실행 파일이 없다. 완성 앱 ZIP·APK·첫 화면 screenshot은 0개다. partial 디렉터리를 설치하거나 실행할 수 있는 완성 앱으로 취급하지 않는다.

cleanup은 PASS다. 초기 iOS Simulator 두 개는 Booted 상태다. 작업의 iOS 26 Simulator는 Shutdown 상태다. 기존 GUI를 보존했다. `8081` listener와 adb device, 실제 native build·Emulator·Metro process는 없다. 새 Simulator·Emulator·Metro를 시작하지 않았다. xcodebuild는 exit 65로 종료했다. 자원을 삭제하지 않았다. cleanup 관측 시각은 `2026-10-10T23:15:46.379761+09:00`이다. 원본 cleanup SHA-256은 `bbac1d20201174dfb07c64d4bd948bffd7d569ca312bb6379e9078e0324b9bd3`다. 원본 cleanup은 lease 반납 요청을 기록했다. root는 이 cleanup snapshot에 기초해 coordination 상태 `RELEASED`와 반납을 확인했다. 이 root 판정을 원본 cleanup의 필드로 취급하지 않는다.

cleanup writer는 substring 검사로 xcodebuildmcp controller를 실제 native process로 오검출했다. 이 assertion은 별도 tooling diagnostic이다. executable 경계 검사 뒤 실제 native process가 없음을 확인했다. 해당 controller 13개를 보존했다. 이 진단을 compiler 실패의 원인이나 두 번째 앱 실패로 기록하지 않는다.

## 증거와 후속 경계

[공개 manifest](evidence/212/attempt-07/manifest.json)는 최종 원본 raw identity와 비식별 요약을 구분한다. root 파일은 105개다. 공식 raw archive cache 2개를 별도 식별한다. 공개 inventory는 107개다. SHA256SUMS에는 root 파일 104개와 cache 2개인 106개 항목이 있다. SHA256SUMS 자체는 자기 index에서 제외하고 별도 hash로 고정했다. 전체 106개 항목의 원본 hash가 일치했다.

runner command result는 17개다. step·시작·종료·exit와 원본 result hash를 대조했다. 16개 command는 exit 0이었다. native iOS build 한 개는 exit 65였다. root log는 18개다. 별도 사후 audit log 1개를 runner result와 구분한다.

원본 REPORT SHA-256은 `44e241addddd72c870705c418c824700abb92a896c4daaccc50defaba5a7bd01`다. 원본 manifest는 `605385c47163892e6a48b1fadd455f0b71ca9badd4583f1f0eb83efa3068854e`다. 원본 SHA256SUMS는 `3a0a0d78b403f36be6f02f2ed8129fcc63177e9f3f8a9347bf44e8798467846f`다. source 사후 감사는 `5473978184f711020b3e745f7232326c7ab4c0a3ec67e068c74a86ea302a7b06`다. generated 사후 검사는 `a203dbd6c8e07d3ae348805b36a35e08a44bd08a804cdd0a72effc68f13339b7`다. 이 hash는 원본 로컬 byte의 identity다. 공개 문서와 공개 manifest의 byte를 식별하는 hash가 아니다.

raw 자료는 `<LOCAL_VALIDATION_ROOT>/attempt-07-exporouter-debug`에 보존한다. raw 실패 log·process text·메모리 dump·helper는 공개하지 않는다. 공개 요약에 host 절대 경로·기기 UUID·private 환경값을 넣지 않는다. 원본 raw hash를 치환한 공개 파일의 hash로 쓰지 않는다. 공개 요약은 원본 byte 감사의 대체 증거가 아니다.

OSS 양플랫폼 known-good과 두 표본의 fresh 인계는 미완료다. 이전 최소 RN 양플랫폼 PASS를 이 실패로 대체하지 않는다. 실제 Runstir CLI·GUI, 준비 재생성 유지, 공동 여섯 조합과 출시 gate는 후속 범위다. 새 source·target·flag 예외에는 별도 결정이 필요하다.

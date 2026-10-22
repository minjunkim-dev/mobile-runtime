# RN baseline #212 attempt-08: native 성공 뒤 Metro 실패

2026-10-11 부분 결과다. Mattermost의 native iOS build와 설치는 exit 0이다. 원본 Metro는 Watchman permission 오류로 exit 1이다. 첫 화면 검증은 시작하지 않았다. Metro 실패를 확인한 뒤 launch 요청을 실행한 작성자의 Q5 순서 오류도 보존한다. launch exit 0은 앱 생존이나 첫 화면 PASS를 입증하지 않는다. #212는 OPEN이다. PR #236은 미병합이다. 실제 Runstir를 사용하지 않았다.

## 고정 입력과 mixed 12개 준비

원본 [Mattermost source](https://github.com/mattermost/mattermost-mobile/tree/c2fe3beda22befd2178dce431793c09111ed903e)는 `c2fe3beda22befd2178dce431793c09111ed903e`다. [ADR-0023](https://github.com/minjunkim-dev/mobile-runtime/blob/4f2d585da92c60df86000a5ce75faf4693bb69b5/docs/adr/0023-mattermost-exporouter-app-floor-preparation.md)의 정책 main `4f2d585da92c60df86000a5ce75faf4693bb69b5`를 적용했다. 새 clone의 원본 npm·hook, frozen Bundle, plain Pods와 마지막 `pod install --deployment`는 PASS다. 원본 도구 선언을 유지했다. Node `24.15.0`, npm `11.12.1`, Ruby `3.2.11`, Bundler `2.5.11`, CocoaPods `1.16.1`, xcodeproj `1.27.0`, RN `0.83.9`, Expo `55.0.23`, ExpoRouter `55.0.14`를 사용했다.

허용한 변경은 resource bundle 11개 Debug `16.4`와 ExpoRouter Debug `16.0`을 합한 mixed 12개 값이다. ExpoRouter Release `15.1`, 원본 앱의 명시적 8개 값 `16.0`, Pods `deploymentTarget` 선언 `16.4`는 유지했다. 앱 minimum과 Pods 선언을 같은 값으로 표시하지 않는다. 앱 project raw SHA-256은 `8ed8c81f2861eec2f92c6a252edd0150ee8c0eb6a082aaf85373bbc3a28dd33f`다.

4216 tracked 파일의 허용한 Hermes 한 값 외 raw byte·kind·Git 실행 mode·index·flags 감사는 PASS다. 전체 object 22792개, configuration-list owner 187개, scoped xcconfig 24개와 raw/inverse exact 12 비교 및 same-clone frozen binding도 PASS다. 메모리 검사 93개와 독립 검토 material finding 0개를 기록했다. generated·prerequisite·resource·post-wrapper 검사는 각각 34·27·21·11개다. native 뒤와 Metro 실패 뒤 source/generated 사후 감사도 PASS다.

Hermes checksum은 원본 `28814c9c9296d16aef26cb514de5378d18885e44`에서 `210827e9b6969083de6f54ce755d508a5722868b`로 준비했다. 이 한 값만 정규화하면 lock 전체 byte가 원본과 같다. 준비 Podfile.lock SHA-256은 `a8d27643b80fddb08818cdf2df4eaf5a601debf6c89e4d0ce8661771b4def6d9`다. 원본 serialized spec provenance는 unknown이다. 원본과의 차이가 경로뿐이라는 증거는 없다.

## 실제 iOS 단계와 Q5 순서 오류

| 단계 | 시작 → 종료, KST | 원본 결과 | 증거 경계 |
|---|---|---|---|
| native build | 00:15:28.254396 → 00:20:46.510169 | exit 0, BUILD SUCCEEDED | 빌드 성공 |
| 전용 Simulator boot·bootstatus | 00:21:42.360032 → 00:21:49.696261 | 각각 exit 0 | 기존 사용자 Simulator와 구분 |
| install | 00:22:06.887517 → 00:22:10.113233 | exit 0 | 설치 성공 |
| 원본 Metro | 00:22:17.590518 → 00:22:24.755059 | exit 1 | Watchman permission 필수 실패 |
| 실패 확인 뒤 launch 요청 | 00:22:28.216411 → 00:22:28.533233 | exit 0, PID 반환 | Q5 순서 오류. 생존·첫 화면 미검증 |
| terminate | 00:22:52.899486 → 00:22:53.082046 | exit 3, found nothing to terminate | 앱 종료 원인 unknown |
| 작업 앱 uninstall | 00:23:04.921396 → 00:23:05.107436 | exit 0 | 이번 작업의 설치 앱 정리 |
| 전용 Simulator shutdown | 00:23:05.550545 → 00:23:08.714361 | exit 0 | 이번 작업의 전용 기기 정리 |

native 로그에서 ExpoRouter와 Mattermost Swift compiler target은 모두 `arm64-apple-ios16.0-simulator`다. 실제 실행 대상은 iOS `26.0 (23A343)`이며 SDK는 `27.0`이다. build 로그의 compile 항목은 3321개다. native error는 0개다. 이 결과로 iOS 16.0 기기 지원이나 Release 성공을 추론하지 않는다.

원본 Metro 명령은 `mise exec node@24.15.0 -- ./node_modules/.bin/react-native start --host 127.0.0.1`이다. Watchman `2026.09.21.00`은 새 clone open에 `Operation not permitted`를 반환했다. Metro는 자동 node-crawler retry 뒤 fb-watchman 오류로 종료했다. 정확한 permission 원인은 unknown이다. TCC·credential 원인으로 단정하지 않는다. source·Watchman 설정·flag·전역 권한 보정을 적용하지 않았다.

작성자가 log 확인, 막힌 status 요청과 launch를 한 tool batch에 묶었다. Metro 실패 인식 뒤 launch가 호출됐다. 이 Q5 순서 오류를 정상 절차나 PASS로 바꾸지 않는다. launch 요청의 exit 0과 반환 PID만 관측했다. 앱 생존과 첫 화면은 입증하지 못했다. terminate가 found nothing을 반환한 이유와 앱 종료 원인은 unknown이다. Watchman 오류와 앱 종료의 인과관계도 확인하지 않았다.

status curl 요청은 context-mode hook에서 redirect됐다. 실제 runner receipt와 HTTP status 응답은 없다. status PASS를 주장하지 않는다. 원본 hook 진단은 로컬 raw packet에 보존한다. 첫 화면 검증은 NOT_STARTED다. Android와 Mattermost fresh 및 최소 RN fresh dependency 준비도 NOT_STARTED다.

## 산출물과 cleanup

이미 빌드한 Mattermost.app에서 ZIP 1개를 내보냈다. 새 build·설치·실행을 추가하지 않았다. 앱은 파일 207개, 총 164870716 byte이며 primary 실행 파일이 존재한다. ZIP은 `mattermost-ios-simulator.app.zip`, 48261208 byte다. SHA-256은 `54f330fad4b08317774c30f556ef29f0296f9a43562b753a9444561e2a7d6890`다. APK와 첫 화면 PNG는 0개다. 이 ZIP은 native 산출물 증거다. known-good이나 첫 화면 증거가 아니다. ZIP은 공개 자료로 복사하지 않았다.

공식 Hermes raw archive 2개만 cache로 재사용했다. Pods·node_modules·vendor·build·풀어 놓은 dependency 디렉터리는 복사하지 않았다. 원본 source command와 flag를 유지했다. active partial을 중단하거나 덮어쓰지 않았다. 이번 CocoaPods 로그는 원본 URL과 Hermes 설치를 기록한다. 별도 실제 HTTP 전송은 관측하지 못했다. 자동 tool cache 동작도 측정하지 않았다. attempt-07의 HTTP 전송 관측을 이번 attempt로 옮기지 않는다.

00:23:23.921279 KST의 cleanup snapshot은 PASS다. Metro는 exit 1로 종료했다. 이번 작업의 설치 앱을 uninstall했고 전용 iOS 26 Simulator를 shutdown했다. 초기 Booted Simulator 두 개와 기존 GUI를 보존했다. `8081`은 비어 있고 adb device와 실제 native/Emulator process는 없다. 비소유 Watchman과 Java process 4개를 중지하지 않았다. 전역 SDK·runtime·AVD·PATH·default 선택·권한과 다른 사용자 앱 데이터를 변경하지 않았다.

최초 `root-lease.json`의 granted 상태와 hash는 그대로다. `lease-return-requested.json`은 작성자의 반납 요청이다. `root-release-message-receipt.json`은 root canonical RELEASED 확인이다. 세 증거를 구분한다. 추가 actual 실행은 허용하지 않는다.

## 공개 증거와 남은 범위

[공개 manifest](evidence/212/attempt-08/manifest.json)는 원본 raw identity와 비식별 요약을 구분한다. root 파일은 SHA256SUMS를 포함해 128개다. 공식 archive cache 2개를 더한 inventory는 130개다. SHA256SUMS에는 root 파일 127개와 cache 2개인 129개 항목이 있다. SHA256SUMS 자체는 자기 index에서 제외하고 별도 hash로 고정한다. runner result와 log는 각각 26개다. 총 raw `.log`도 26개다. 추가 non-runner log는 없다. 24개 command는 exit 0, Metro는 exit 1, terminate는 exit 3이다. 모든 result의 step·시간·exit·argv·cwd를 원본 요약과 대조했다. 전체 raw inventory의 size·hash도 일치했다.

원본 REPORT SHA-256은 `09edc1452c09d766080e79d6009b1e6bcd380a53f6b418180a4f3ff1e6556988`다. 원본 manifest는 `f9cb28a7f232b0f876880e802ecb3e4472a2b71a53afb88b1caf92c0f16a12d8`다. 원본 SHA256SUMS는 `72b8e335c131ea342325b51d38b9b48a86ff3e52d7613ed5f4e785f71fc5ab1b`다. 최종 source 사후 감사는 `e142e2bf614403b41b8324e2f859f85bbb88b22970e5e4248f01c392c457d8f7`다. generated 사후 검사는 `d485d73f2446f5d32ed2841578a88059b4b9968fd45928b0e671200439ec2b47`다. 원본 cleanup은 `85db064e839cdd8b2e06334db780dae06cb83f6a03c16c4eb4ac26750ec9ba04`다. 이 hash는 공개 치환 파일의 byte를 식별하지 않는다.

raw 자료는 `<LOCAL_VALIDATION_ROOT>/attempt-08-exporouter-debug-16`에 보존한다. raw log·process text·메모리 dump·helper·private 환경값·host 절대 경로·기기 UUID는 공개하지 않는다. 원본 raw hash를 공개 요약의 hash로 제시하지 않는다. 공개 요약은 원본 byte 감사의 대체 증거가 아니다.

기존 attempt-06·07과 최소 RN 양플랫폼 PASS를 보존한다. 이번 준비 입력의 Android와 독립 fresh 인계는 시작하지 않았다. 과거 Android 성공을 이번 입력에 승계하지 않는다. fresh 후보 SHA를 실제 checkout으로 표시하지 않는다. OSS 양플랫폼 known-good과 #212 AC는 미완료다. 실제 Runstir CLI·GUI, 준비 재생성 유지, 공동 여섯 조합과 출시는 후속 범위다.

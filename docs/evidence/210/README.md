# #210 native iOS 실제 실행 기록

제품 source는 `cf384de1019f52341a731ce3d0f9e837a84c5696`이다.
이 디렉터리의 추가는 제품 source를 바꾸지 않는다.
정확한 입력, 결과, SHA256은 [receipt](native-ios-receipt.json)에 기록했다.
개인 경로와 기기 식별자는 별칭으로 표시했다.
원본 명령, JSON, 진행 이벤트, build 로그, AX, 보존 비교는 비공개로 보관했다.
receipt는 비공개 파일의 SHA256을 기록한다.

## 고정한 표본

| 항목 | Food Truck | NetNewsWire |
|---|---|---|
| source | `3954a769e99f3cc53297d94f2b960ceb2665b3d6` | `aea7795bcc0698ced6f28eba53da886eb6217e64` |
| 컨테이너 | `Food Truck.xcodeproj` | `NetNewsWire.xcodeproj` |
| scheme | `Food Truck` | `NetNewsWire-iOS` |
| configuration | `Debug` | `Debug` |
| 측정한 deployment target | `16.4` | `17.0` |
| tracked 파일 | 553 | 1352 |

macOS 27.0.1 arm64, Xcode 27.0 (27A266a), SDK 27.0을 사용했다.
소유한 iPhone 18 Pro Simulator의 iOS 27.0 (24A434)을 사용했다.
공유 기기와 SDK/runtime 설치는 실행 범위에 넣지 않았다.
두 source의 프로젝트 script 실행을 명시적으로 신뢰했다.
최종 CLI와 GUI 실행 프로세스에는 최소 환경만 전달했다.

## 실제 결과

두 표본의 CLI 단독 `build`가 성공했다.
완료 단계는 `validate`, `build`다.
단독 `build`는 기기에 설치하거나 앱을 실행하지 않았다.

두 표본의 CLI `up`이 성공했다.
완료 단계는 `validate`, `device`, `build`, `install`, `launch`다.
CUA로 Truck과 Feeds 화면을 확인했다.
NNW 알림 팝업에서 `허용 안 함`을 눌렀다.
팝업이 사라진 Feeds 화면을 별도로 확인했다.
두 표본의 CLI `down`이 기록한 앱을 종료했다.

같은 source, scheme, configuration, 기기로 GUI `up`과 `down`을 실행했다.
GUI에서 저장소 script 신뢰와 기기를 명시적으로 선택했다.
GUI가 실행한 두 앱의 실제 화면을 확인했다.
아래 PNG는 Device Hub 창의 원본 캡처다.
다른 기기의 이름을 숨긴 창에서 캡처했다.
이미지 내용은 편집하지 않았다.

| 진입 | Food Truck | NetNewsWire |
|---|---|---|
| CLI | [Truck](food-cli-first-screen.png) | [Feeds](netnewswire-cli-first-screen.png) |
| GUI | [Truck](food-gui-first-screen.png) | [Feeds](netnewswire-gui-first-screen.png) |

GUI doctor에서 공통 Xcode 요구 문구를 확인했다.
공백이 있는 프로젝트의 안내 명령도 확인했다.
명령은 `xcodebuild -list -project 'Food Truck.xcodeproj'`였다.
이전 GUI 시도의 일부 AX 파일은 전체 화면이 아닌 no-change diff다.
그 시도의 실제 CUA 관측과 normalized 기록을 보존했다.
후속 보존 검증의 GUI 기록은 전체 AX를 저장했다.

## 준비 조건과 실패 이력

NNW는 #214에서 준비한 정확한 SPM checkout과 lockfile을 사용했다.
표본별 DerivedData의 전용 cache에 복사했다.
artifact cache의 절대 경로만 옮겼다.
SPM 자동 resolution과 자동 갱신을 허용하지 않았다.
Simulator build는 `CODE_SIGNING_ALLOWED=NO`를 사용했다.

첫 NNW doctor의 `xcodebuild -list`는 120초 timeout이었다.
Runstir는 이를 `unknown`과 exit 2로 반환했다.
같은 argv, cwd, 환경의 진단 명령은 1.040초에 성공했다.
한 번 허용한 CLI 재시도는 2.233초에 성공했다.
첫 timeout의 원인은 확인하지 못했다.
timeout을 늘리지 않았다.

첫 NNW build는 `SecretKey`를 찾지 못해 실패했다.
프로젝트 script는 ignored `SecretKey.swift`를 생성했다.
처음 확인한 컴파일 입력 목록에는 해당 파일이 없었다.
같은 명령의 재시도는 생성 파일을 포함했고 성공했다.
설정과 resolution 제한을 완화하지 않았다.
첫 build 전 생성 파일의 존재 여부는 측정하지 않았다.

고정한 `SecretKey.swift.gyb`는 `os.urandom(64)` salt를 사용한다.
따라서 같은 입력으로 build해도 생성 파일 hash가 달라질 수 있다.
생성 script와 template의 hash를 고정했다.
6개 secret 환경 입력을 전달하지 않았다.
각 보존 검증의 생성 파일 hash를 별도로 기록했다.
생성 파일 내용은 공개하지 않는다.

추가 build/device 선택자가 있는 `down`은 변경 전에 거절됐다.
선택자를 뺀 `down`은 성공했다.
Mac 잠금으로 막힌 GUI 작업은 사람이 잠금을 해제한 뒤 재개했다.
모든 실패와 중단 시도는 성공 기록과 분리했다.

## 보존 확인

두 표본의 tracked 파일 bytes, index, source SHA는 같다.
NNW lockfile도 같다.
ignored 생성 파일의 변경을 tracked 파일 보존으로 숨기지 않았다.

긴 전체 관측 구간에서는 기존 기기의 앱 43개 중 한 앱의 container 경로 4개가 바뀌었다.
변경 주체와 원인은 확인하지 못했다.
해당 앱을 복구하거나 변경하지 않았다.
이 구간의 앱 목록 전체가 같다고 주장하지 않는다.

별도로 새 기준 목록을 잡았다.
Food CLI, NNW CLI, Food GUI, NNW GUI를 각각 한 번 실행하고 종료했다.
각 case의 직전·직후 기존 앱 43개 목록은 같다.
각 case의 다른 Simulator 상태도 같다.
NNW CLI 직후와 Food GUI 실행 직전 사이의 준비 구간에서는 기존 앱 한 개의 경로 4개가 다시 바뀌었다.
관측 시각은 KST 23:47:48.394부터 23:49:27.726까지다.
변경 주체와 원인은 `unknown`이다.
네 case 전체를 묶은 구간의 앱 목록이 같다고 주장하지 않는다.
추가 재실행과 타인 앱 복구는 하지 않았다.
소유 기기의 예상 boot 변화는 별도로 기록했다.
최종 소유 앱은 종료됐다.
소유 GUI도 종료됐다.
소유 Simulator만 `Shutdown`으로 돌렸다.

## 검증 범위

제품 source에서 Swift Werror 570개와 세 CLI executable contract 검사가 통과했다.
공백, 작은따옴표, 명령 치환 문자열의 shell 인자 회귀는 RED 후 GREEN을 확인했다.
fixture 검증과 위 실제 실행 기록은 별도 증거다.
#214의 Runstir 없는 baseline을 #210 실행 성공으로 대체하지 않았다.
이전 제품 head의 실행 기록도 최종 제품 증거와 분리했다.

원본 Xcode/runtime 배포 파일의 checksum은 `unknown`이다.
Sparkle ZIP 원본 bytes는 보관하지 않아 checksum을 확인하지 못했다.
공식 선언 checksum과 추출 tree hash를 ZIP 원본 checksum으로 대체하지 않는다.
준비되지 않은 의존성의 설치와 cold build는 검증하지 않았다.
실기기, provisioning, release 서명, 공증, Gatekeeper는 검증하지 않았다.
실제 Simulator에서의 취소는 검증하지 않았다.
Flutter와 native Android 실행은 후속 티켓 범위다.
최종 evidence commit의 독립 리뷰, 필수 CI, broad 변경의 사람 승인, 병합, main CI는 별도 gate다.

---
status: accepted
---

# ADR-0046: #212 RN baseline은 준비 guard 대신 원본 명령의 직접 실행 기록으로 판정한다

사용자는 2026-10-22에 이 결정을 확정했다. #212 baseline에만 적용한다.

## 배경

attempt-09부터 attempt-20까지 12번의 실행은 모두 Pods·native 전에 멈췄다. attempt-09는 원본 frozen Bundle의 Bundler lookup, attempt-12는 하네스가 정한 installer 인자 순서였다. 나머지 10번은 앱이나 원본 도구가 아니라 준비용 guard·observer·caller 조건에서 멈췄다. 그 사이 ADR-0025부터 ADR-0034까지 진단 범위와 실행 권한 조건만 늘었다. 수용 기준의 첫 화면과 fresh 인계는 진전하지 않았다.

## 결정

#212 baseline의 실제 실행 조건에서 아래를 대체한다.

- ADR-0024의 외부 helper 독립 검토, 단독 lease, observer receipt 조건.
- ADR-0026부터 ADR-0034의 mise·plugin·STATE metadata·Ruby observer·errno·Pod CWD·lifecycle field·asset identity·GUI/ADB resource·ADB 환경 선언과 그 STOP 조건.

이 결정으로 다음을 유지한다.

- 최소 RN source `b62e3a4d5e7cfc05d7d948a5a4e30f0cc6a82bb4`와 세 lock, Mattermost source `c2fe3beda22befd2178dce431793c09111ed903e`와 원본 lock.
- 표본별 선언 도구 버전(Node·Ruby·Bundler·CocoaPods·JDK)과 원본 명령. 최소 RN의 Bundler `2.5.22`는 ADR-0025대로 clone 전용 GEM_HOME에 공식 gem을 설치해 쓴다.
- Mattermost에만 ADR-0020의 Hermes checksum 한 값과 ADR-0021·ADR-0023의 Debug 12개 값 준비. 그 밖의 source·lock·graph·flag를 바꾸지 않는다.
- ADR-0024의 내장 Data volume 경로, 원본 Metro를 native 전에 확인하는 순서, Watchman을 끄지 않는 조건.
- 실패와 교체 이유의 보존. baseline 실패를 Runstir 실패로 분류하지 않는다. 앱 준비·빌드·설치·실행에 Runstir를 쓰지 않는다.

## 기록과 판정

각 단계는 실제 명령, 종료 코드, 원본 로그, 실제 host tuple을 기록한다. host tuple은 관측한 값을 그대로 적는다. 이전 기록과 다른 값(예: Xcode 버전)은 차이로 남기고 이전 성공에 승계하지 않는다.

첫 화면은 기기 화면 캡처와 앱 process 생존으로 판정한다. launch 요청 exit `0`이나 Metro banner만으로 판정하지 않는다.

원본 명령이 실패하면 그 표본의 후속 단계를 중단하고 실패를 기록한다. 이 ADR 밖의 우회(source patch, lock 재생성, 버전 변경, flag 추가)는 하지 않는다.

fresh clone은 두 표본의 양플랫폼 첫 화면 뒤 원본 명령으로 독립 준비한다. baseline 산출물을 복사하지 않는다.

## 경계

### 2026-10-23 Simulator 로컬 서명 승인

사용자는 남은 검증을 계속하라고 승인하면서 Simulator 전용 로컬 ad-hoc 서명 변경을 허용했다. Mattermost의 `CODE_SIGNING_ALLOWED=NO` 산출물은 설치됐지만 Keychain entitlement 없이 첫 실행에서 중단됐다. iOS Simulator Debug 빌드에 한해 Xcode가 로컬 서명과 Simulator entitlement를 생성하도록 `CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`를 사용한다. Apple 계정·유료 멤버십·인증서·provisioning profile이나 `-allowProvisioningUpdates`는 사용하지 않는다. 원본 앱 entitlement와 source는 수정하지 않는다. 실제 기기 서명·공증·배포 후보의 순서는 바꾸지 않는다.

기존 앱 사본에 원본 entitlement를 펼쳐 수동으로 ad-hoc 서명한 진단은 설치 후 AMFI의 restricted-entitlements 거부로 실패했다. 이를 첫 화면 성공이나 Xcode 빌드 결과로 취급하지 않는다. Xcode의 Simulator 빌드 결과와 실제 첫 화면을 별도로 확인한다.

전용 private device set의 Simulator는 Xcode 목적지 목록에 나오지 않는다. 이 경우 호스트와 같은 arm64의 generic iOS Simulator 대상으로 빌드하고, 설치·실행은 소유한 private set의 UDID를 명시한다. 다른 세션 기기를 빌드 대상으로 선택하거나 부팅하지 않는다. 이 목적지·architecture 선택도 실제 명령에 기록한다.

이 결정은 baseline 기록 방식만 바꾼다. Runstir 제품 정책, 실제 Runstir CLI·GUI 검증, 공동 출시 gate는 바꾸지 않는다. 이전 attempt 기록과 ADR 본문은 그대로 보존한다.

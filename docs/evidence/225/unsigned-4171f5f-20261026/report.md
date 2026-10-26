alpha.14의 RN 최소 앱·Mattermost, iOS·Android, CLI·GUI 8개 경로에서 올바른 앱 첫 화면과 정상 종료를 확인했습니다.

후보는 `4436d17033b2ed4ebff74769a46b67d9689593c7536e85f5b1433b370df14752`, 제품 source는 `4171f5f132a611c73d785f28b424c46e65b7f4d5`입니다. CLI·GUI 실행 파일과 후보 metadata의 SHA-256은 처음과 같으며 제품 코드는 수정하지 않았습니다.

| 플랫폼·앱 | CLI | GUI | 의존성 준비 |
| --- | --- | --- | --- |
| iOS 최소 앱, RN 0.87.1 | 첫 화면·down 확인 | 첫 화면·down 확인 | 각 fresh clone에서 setup, 부분 완료와 생성 파일 보호 확인 |
| iOS Mattermost, RN 0.83.9 | 첫 화면·down 확인 | 첫 화면·down 확인 | 원 CI 명령으로 각각 준비, 승인된 Hermes checksum 1값·생성 Pods Debug 12값 보정 후 명시적 준비 선택 |
| Android 최소 앱, RN 0.87.1 | 첫 화면·down 확인 | 첫 화면·down 확인 | 각 fresh clone에서 setup, 도구 조건 변경 중단과 재계획 확인 |
| Android Mattermost, RN 0.83.9 | 첫 화면·down 확인 | 첫 화면·down 확인 | 원 CI 명령으로 각각 준비한 의존성을 명시적으로 사용 |

각 행은 별도 Git clone입니다. 기존 node_modules·Pods·빌드 산출물을 복사하지 않았습니다. 기존 SDK·도구와 프로젝트별 npm·Gradle cache는 재사용했으므로 호스트 검증을 cold-cache 설치로 세지 않습니다. iOS 대상은 고정 iOS 26.0 Simulator, Android는 API 37 arm64 Emulator입니다. Android Emulator는 사용자 포커스를 지키도록 stock SDK의 `-no-window`로 시작했습니다. Android 최소 앱의 기존 `ACCESS_LOCAL_NETWORK` 허용 상태를 두 소유 AVD에서 읽기 전용으로 확인했으며 이번 작업에서 새 권한을 부여하지 않았습니다.

Mattermost는 서버 연결 화면의 2.44.0, build 814를 확인했습니다. 일부 화면에는 미응답 알림 권한 창이 겹쳐 있으며 권한 선택과 로그인은 진행하지 않았습니다. GUI 기능 확인은 접근성 트리와 SDK 관측, 모바일 앱의 원본 PNG로 수행했습니다. Runstir 창의 시각 배치나 VoiceOver 낭독 완료 판정으로 확대하지 않습니다.

첫 iOS 최소 앱 CLI 실행은 exit 0이었지만 실제 redbox였습니다. 검증 환경에 `WATCHMAN_SOCK`만 지정하고 전용 daemon을 시작하지 않은 수집기 누락을 확인했습니다. 전용 Watchman을 시작한 같은 후보의 재시도에서 bundle HTTP 200과 RN 0.87.1·Hermes 첫 화면을 확인했습니다. 첫 실패와 PNG도 보존했습니다. Android의 빈 AVD 이름 응답은 성공으로 세지 않았습니다. stock SDK가 요구하는 기존 소유 Emulator console 정보를 새 HOME에만 임시 사본으로 제공한 뒤 정확한 AVD 이름 응답과 정상 실행을 확인했습니다.

도구 없는 Tart clone에서는 원본 baseline VM을 보존한 채 공식 Mise·Node 22.23.2, Mattermost용 Node 24.15.0·Ruby 3.2.11을 실제 설치했습니다. 수동 JDK·SDK·의존성 단계가 남아 결과는 부분 완료입니다. 반복 계획은 완료한 도구 설치를 다시 요구하지 않았습니다. guest의 `kern.hv_support=0`이므로 Android 실제 실행은 호스트 결과로만 판단합니다.

실제 Node 다운로드 취소는 130/cancelled, 다운로드 자식 전송 실패는 1/failed였습니다. 별도 fresh clone의 같은 설치 목적지 요청도 기존 작업을 중단하지 않고 거부했습니다. 미완료 설치와 scratch가 정리되고 완료한 도구가 보존됐으며 정상 재시도로 복구됐습니다. 실제 npm ci 취소 뒤에는 미완료 표식이 남았고 이전 승인은 거부됐습니다. 새 계획으로 재실행해 표식이 제거되고 Node·Pods 준비가 완료되는 것까지 확인했습니다. iOS xcodebuild와 Android assembleDebug 도중 취소도 130/cancelled로 끝났으며 관측한 자식 PID가 모두 사라지고 정상 재빌드가 성공했습니다.

실제 Bundler 설치 자식을 중단한 결과는 1/failed였고 완료된 Node 의존성과 소스는 유지됐습니다. 새 계획으로 Bundler를 설치한 뒤 bundle check가 성공했습니다. 이후 Pods가 만든 새 파일 두 개로 보호 중단한 결과를 보존하고, 파일 검토와 재계획을 거친 반복 실행도 추가 변경 없이 부분 완료로 끝났습니다. 실제 pod install 도중 취소는 130/cancelled였고 완료된 Bundle·Node 표본과 소스를 보존했습니다. Pods 복구 뒤 lock과 Manifest가 일치했으며 양 플랫폼 빌드도 다시 성공했습니다.

이 보강 검사들의 첫 시도는 큰 iOS 빌드와 겹친 Gradle 사전 검사 90초 제한에서 끝나 의도한 단계에 도달하지 못했습니다. 당시 loadavg 80.40, swap 사용량 10.4GB를 기록했습니다. GUI와 기기를 종료한 순차 재검증에서는 사전 검사와 의도한 실패·취소·복구가 완료됐습니다. 부하와 공유 cache 경합의 기여도는 분리해 확정하지 않았으며, 첫 두 시도를 실패·판정 불가 이력으로 보존합니다. 높은 부하에서 병렬 준비 성능이 보장된다는 판정은 하지 않습니다.

AC02는 도구 재사용·cold VM 설치·부분 완료·수동 준비, AC03은 실패·취소·동시 목적지·조건 변경·소스 보호·재시도, AC04는 각 frontend의 doctor·계획·독립 build·up·down, AC05는 8개 fresh clone 첫 화면, AC06은 호스트 가속 실행과 baseline 보존 clone VM의 준비 경로에 연결합니다. AC15의 같은 후보 연결과 AC17의 실패 이력 보존을 유지합니다. 전체 공동 게이트와 서명·공증·공개 완료 판정은 별도로 남습니다.

직접 시작한 GUI·앱·Metro·Emulator·Simulator·Watchman·VM은 정상 종료했습니다. 기존 global Watchman과 다른 작업의 프로세스·worktree는 보존했습니다. 임시 console 사본 4개를 제거하고 원래 정보는 보존했습니다. 소유 adb 서버 2개는 연결된 기기가 없고 실제 실행 image가 지정한 SDK와 일치함을 확인한 뒤 정상 종료했습니다. 첫 정리 검사에서 argv의 단축 이름을 경로로 오인한 수집기 assert도 별도 보존했습니다. 완료된 cache·빌드 출력과 제한 증거는 유지합니다. 실기기 설치·실행, Apple 유료 계정 준비, 서명·공증·배포는 진행하지 않았습니다.

큰 입력 JSON은 원시 bytes의 checksum으로 보관하며, 추적 원본·index·flags와 허용한 Mattermost 보정의 의미는 별도 실행 검사로 대조했습니다. 원시 참조 무결성을 모든 JSON 의미의 자동 검증으로 확대하지 않습니다. 현재 기본 mobile runtime root는 실제 폴더입니다. 이번 실행 초기에 옛 SSD symlink는 없었고 후보가 폴더를 생성했으므로 임시 복구나 링크 복원은 수행하지 않았습니다.

로컬 전체 Swift 테스트 1,166개와 증거 검사기 회귀 테스트 17개가 통과했습니다. 중첩 helper 실행 두 개는 Swift 총수에 중복 합산하지 않았습니다. 정본 참조 무결성은 verified이며 전체 공동 게이트는 나머지 필수 요구 미검증과 unsigned 제한으로 blocked입니다.

이 정본은 #225의 RN 범위 18개 요구를 pass로 기록합니다. 기존 후보·입력 연결 pass 1개를 포함한 현재 결과는 pass 19개, unverified 35개입니다. 다른 프레임워크와 공통 게이트의 미검증, unsigned 배포 제한으로 공동 출시 판정은 blocked입니다. #224의 최초 결과와 첫 RN redbox·보강 검사 판정 불가 이력을 보존합니다. AC15 전체나 AC17 전체의 완료로 확대하지 않습니다.

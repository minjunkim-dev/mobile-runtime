alpha.15의 Flutter 최소 앱·LocalSend, iOS·Android, CLI·GUI 8개 경로에서 올바른 앱 첫 화면과 정상 종료를 확인했습니다. 이 문서는 #226의 실제 실행·경계·보존 검증을 기록합니다. 최종 head의 독립 리뷰·CI와 병합 상태는 PR·이슈에 별도로 기록합니다.

후보는 `be9251f8488e34acb0072b106c4fd2843c1ad8a82581a911b5082dc00106f54a`, 제품 source는 `a2cb48c23835f2f03d2dfb8655c9bd4b625bab09`입니다. CLI·GUI 실행 파일과 후보 metadata의 SHA-256은 시작과 재개 때 고정값과 같았으며 제품 코드는 수정하지 않았습니다. alpha.14 결과는 승계하지 않았습니다.

| 플랫폼·앱 | CLI | GUI | 준비 |
| --- | --- | --- | --- |
| iOS 최소 앱 | 첫 화면·getVM·down 확인 | 첫 화면·getVM·down 확인 (macOS 27.2) | setup이 Java 설치 뒤 재계획, locked 정렬 뒤 부분 완료. 생성 입력은 원래 명령으로 준비 |
| iOS LocalSend | 첫 화면·getVM·down 확인 | 첫 화면·getVM·down 확인 (macOS 27.2) | 위와 같고 Pods 포함. 명시적 준비 선택, Cargokit build tool은 사람이 준비 |
| Android 최소 앱 | 첫 화면·getVM·down 확인 | 첫 화면·getVM·down 확인 | locked 정렬 뒤 부분 완료, 생성 입력은 원래 명령으로 준비 |
| Android LocalSend | 첫 화면·getVM·down 확인 | 첫 화면·getVM·down 확인 | 명시적 준비 선택, Rust는 고정 offline toolchain |

각 행은 alpha.15용 별도 full Git clone입니다. 의존성·빌드 산출물을 복사하지 않았고 일치하는 SDK·도구·cache는 재사용했으므로 cold-cache 결과로 세지 않습니다. 원래 도구만 쓴 별도 clone 4개에서 같은 표본의 설치·실행·첫 화면 기준선을 다시 확인했습니다. Android 기준선은 새 작업 소유 AVD를 썼습니다. 기존 기준선 AVD의 앱 서명이 달라 교체하려면 데이터를 지워야 했기 때문입니다.

input 7(LocalSend Android GUI)에서 #346 수정을 실제 GUI로 확인했습니다. 미리 준비한 의존성 선택을 끈 환경 확인은 계약대로 오류를 냈고, 켜자 오류 0개와 기기 목록이 나타났으며 build·up·첫 화면·getVM·down이 완료됐습니다. CLI doctor는 ADR-0048대로 이 선택이 없으므로 같은 입력에서 오류와 #348 안내를 냅니다.

GUI의 Android build가 끝나면 기기 선택 칸이 비고 비활성화되는 결함을 input 6·7에서 재현해 #353으로 분리했습니다. build 결과의 빈 기기 목록이 GUI 목록을 덮어씁니다. 숨은 선택값은 남아 실행은 정상 완료됐으며 고치지 않았습니다.

LocalSend iOS는 CLI·GUI 모두 Runstir build가 Rust Cargokit 단계에서 멈췄습니다. 빌드가 네트워크를 막아 build tool이 pub.dev에 닿지 못했기 때문입니다. 원래 Cargokit 스크립트로 build tool을 준비한 뒤 다시 빌드했으며 alpha.14와 같은 사람 준비 경계로 분류합니다.

실제 위험 경계를 다시 실행했습니다. Android build의 Gradle 진입 뒤 SIGINT는 130/cancelled였고 자식과 비공개 실행 폴더가 사라졌으며 같은 입력 재빌드가 성공했습니다. 빈 HOME의 Flutter SDK 다운로드 취소는 130, 다운로드 자식 종료는 1/failed였고 미완료 설치가 남지 않았습니다. 다른 clone의 같은 설치 대상 요청은 거부되고 기존 작업은 SDK 하나를 끝까지 설치했습니다. 설치된 SDK는 다음 계획에서 다운로드·쓰기 없이 재사용됐습니다. pub workspace 멤버의 stray lock은 Android·iOS 모두 migration으로 계획되고 build·up이 단계 시작 전에 거부됐습니다. 계획 뒤 pubspec·.fvmrc 변경은 옛 승인을 거부했고 validate 중 Gradle 입력 변경은 Gradle 전에 중단됐습니다. 제품은 수집기가 일부러 바꾼 입력을 되돌리지 않았고, 그 외 경계에서는 추적 source·index·flags가 보존됐습니다.

보존한 도구 없는 기준 VM의 새 clone에서 후보 CLI의 doctor·setup이 Mise 2026.10.7, Temurin 17.0.18+8, Flutter 3.41.9를 실제 설치하고 수동 항목을 남긴 부분 완료로 끝났습니다. 반복 계획은 도구를 다시 설치하지 않았고 원 기준 VM metadata는 바뀌지 않았습니다. guest의 kern.hv_support가 0이므로 Android 실행은 호스트 결과로만 판단합니다.

GUI input 2·3은 호스트가 macOS 27.0에서 27.2(26B123)로 업데이트된 뒤 실행했습니다. Xcode 27.1, iOS 27.0 runtime, 대상 Simulator, 후보 실행 파일은 같았습니다. 두 경로의 준비 항목·수동 경계·결과는 macOS 27.0의 CLI input 0·1과 같아 OS 차이에 따른 결과 차이를 관측하지 못했습니다. 다만 iOS의 CLI·GUI 비교는 OS가 다른 두 시점의 비교입니다.

수집 오류와 판정 불가를 제품 실패와 분리해 보존했습니다. 첫 GUI 제어 승인 거부, 새 HOME의 Emulator console 인증 사본 누락, 기존 기준선 AVD의 서명 불일치, launcher 명령 실패, 수집기가 만든 mobile.yml의 Simulator UDID 값(GUI 기기 선택으로 해소), zsh 인수 결합, 재사용 관측기의 잘못된 가정, 사용자 중단 뒤 재개가 여기에 해당합니다. 제한 원본의 개발 연결 URI 토큰은 getVM 확인 뒤 봉인 전에 제자리에서 가렸습니다.

AC02는 준비·재사용·부분 완료·수동 준비, AC03은 취소·실패·동시 대상·migration·조건 변경·소스 보호, AC04는 같은 입력의 CLI·GUI 결과, AC05는 8개 fresh clone 첫 화면, AC06은 실제 Mac 기존 환경과 기준 VM clone 준비 경로에 연결합니다. AC15의 같은 후보 연결과 AC17의 실패 이력 보존을 유지합니다. 전체 공동 게이트와 서명·공증·공개 판정은 별도로 남습니다.

이 정본은 #226의 Flutter 범위 17개 요구를 pass로 기록합니다(AC05 경로 8개, AC02·AC03 각 2개, AC04 4개, AC06 1개). 기존 후보·입력 연결 pass 1개를 포함한 현재 결과는 pass 18개, unverified 35개입니다. 다른 프레임워크·공통 게이트의 미검증과 unsigned 배포 제한으로 공동 출시 판정은 blocked입니다. #224의 최초 결과와 이번 판정 불가 이력을 보존하며 AC15·AC17 전체 완료로 확대하지 않습니다.

## 재수집 (2026-10-31)

#354 병합 뒤, 첫 정본에서 미검증으로 남긴 세 항목을 같은 alpha.15와 같은 입력으로 다시 실행해 수집했습니다. 호스트는 macOS 27.2입니다.

- 8개 경로 모두 up, getVM=VM, 올바른 첫 화면, down을 다시 확인했고, down 직후 수집기가 해당 VM 서비스 포트의 LISTEN이 없고 TCP 연결이 거부되는 것을 기록했습니다.
- input 3(LocalSend iOS GUI)은 build 전후 앱 번들의 컨테이너 inode·Info.plist 시각·실행 파일 SHA가 같았고, up 뒤에는 컨테이너와 Info.plist 시각이 바뀌었습니다. build가 설치하지 않았음을 직접 관측했습니다. input 2·6·7 GUI도 build 전후 설치 상태가 같았습니다.
- 도구 없는 VM clone 안의 후보 실행 파일은 하나이고 SHA-256이 고정값과 같았으며, 전송 archive SHA도 manifest와 같았습니다. 같은 실행 파일로 doctor를 다시 실행했고 원 기준 VM metadata는 바뀌지 않았습니다.
- LocalSend iOS CLI의 첫 재실행은 호스트 재시작으로 Cargokit build tool이 사라져 같은 사람 준비 경계에서 멈췄고, 다시 준비한 뒤 통과했습니다.
- input 7 down 직후 Android가 앱 자체의 JobScheduler 작업으로 화면 없는 프로세스를 다시 띄운 것을 ActivityManager 로그로 기록했습니다. Runstir가 실행한 앱 프로세스는 force-stop으로 종료됐고 VM 서비스 포트는 닫혔습니다.

첫 정본의 결과는 `results-r1.json`으로 보존하고 해당 시도는 새 시도로 대체했습니다. 개발 연결 토큰은 getVM 확인 뒤 봉인 전에 다시 가렸습니다.

alpha.15의 네이티브 iOS 최소 앱 Food Truck과 OSS 앱 NetNewsWire를 CLI·GUI 4개 경로에서 실행해 올바른 첫 화면과 정상 종료를 확인했습니다. 이 문서는 #227의 실제 실행·경계·보존 검증을 기록합니다. 최종 head의 독립 리뷰·CI와 병합 상태는 PR·이슈에 별도로 기록합니다.

후보는 `be9251f8488e34acb0072b106c4fd2843c1ad8a82581a911b5082dc00106f54a`, 제품 source는 `a2cb48c23835f2f03d2dfb8655c9bd4b625bab09`입니다. CLI·GUI 실행 파일과 후보 metadata의 SHA-256은 시작 때 고정값과 같았으며 제품 코드는 수정하지 않았습니다. 이전 후보의 네이티브 iOS 결과는 승계하지 않았습니다. 호스트는 macOS 27.2(26B123), Xcode 27.1(27A9275), iOS 27.0 runtime, iPhone 18 Pro Simulator입니다.

| 앱 | CLI | GUI | 준비 |
| --- | --- | --- | --- |
| Food Truck | Truck·New Orders·Forecast 첫 화면, down 뒤 앱 PID 부재 | 같은 첫 화면, 종료 완료, PID 부재 | setup은 설치할 도구 없이 수동 항목 3개(scheme 측정·runtime) |
| NetNewsWire | Feeds·Smart Feeds 첫 화면, 알림 권한 요청 겹침, down 뒤 PID 부재 | 같은 첫 화면, 종료 완료, PID 부재 | 위와 같고, 생성 파일 `SecretKey.swift`는 원래 스크립트로 사람이 준비 |

각 행은 alpha.15용 별도 full Git clone이고 HOME·TMPDIR을 새로 만들었습니다. 의존성·빌드 산출물을 복사하지 않았습니다. Xcode·runtime·고정 Simulator는 기존 것을 썼으므로 cold-cache 결과로 세지 않습니다. 고정 Simulator 두 대는 이전 후보 실행으로 앱 데이터가 남아 있어 새 기기 데이터의 첫 실행 결과가 아닙니다. Runstir 없이 원래 xcodebuild·simctl만 쓴 별도 clone 2개와 새 작업 소유 Simulator에서 같은 두 앱의 build·설치·실행·첫 화면 기준선을 다시 확인했습니다.

NetNewsWire의 새 clone은 CLI·GUI 모두 첫 Runstir build가 `cannot find 'SecretKey' in scope`로 실패했습니다. 저장소의 생성 파일이 build 계획 시점에 없어서 생기는 원래 프로젝트의 순서 문제이며, 기준선 기록(#214)에도 같은 실패가 있습니다. 서비스 자격 변수 없이 원래 `buildscripts/updateSecrets.sh`를 실행한 뒤 다시 빌드해 통과했습니다. 사람 준비 경계로 분류합니다.

doctor는 scheme을 지정해도 일반 검사 `simulator.runtime`이 `unknown`이라 전체 결과가 `unknown`이었습니다. 같은 결과의 `project.native-ios`는 선택한 scheme을 측정해 통과했고, up도 작업은 `succeeded`인데 최상위 status는 `unknown`이었습니다. 실패로 바꾸거나 통과로 올리지 않고 원시값을 보존했으며 #357로 분리했습니다. setup 계획은 CLI·GUI 모두 설치 항목 없이 같은 수동 항목 3개를 냈고, 승인하면 아무것도 바꾸지 않고 직접 준비가 필요한 상태(waiting-manual)로 끝났습니다.

GUI에서 build가 실패하거나 취소되면 선택 칸 아래에 작업 안내가 "선택 항목을 확인하지 못했습니다"라는 문구로 표시되는 결함을 재현해 #358로 분리했습니다. #353과 같은 코드 줄에서 나옵니다. 선택값과 실행 결과에는 영향이 없었으며 고치지 않았습니다.

실제 위험 경계를 실행했습니다. CLI up의 xcodebuild 중 SIGINT는 130/cancelled였고 xcodebuild·SWBBuildService 자식이 남지 않았으며 같은 입력의 up이 다시 성공했습니다. GUI build 중 작업 취소는 "빌드: 취소됨"으로 끝났고 xcodebuild가 사라졌습니다. 같은 Simulator에 두 clone이 동시에 up하면 뒤 요청은 기존 작업과 프로젝트를 밝히며 단계 시작 전에 거부됐고 앞 작업은 성공했습니다. 없는 scheme의 build는 변경 전에 실패했습니다. GUI의 build 전후 설치된 앱의 컨테이너 inode·Info.plist 시각·실행 파일 SHA가 같아 build가 설치하지 않았음을 직접 관측했고, up 뒤에는 바뀌었습니다. 모든 경로에서 추적 source·index·flags가 보존됐습니다.

#226이 남긴 도구 없는 기준 VM의 clone에서 upstream을 새로 clone해 후보 CLI로 doctor·setup·build·up·down을 실행했습니다. 이 VM에는 Homebrew·mise·Java가 없고 Xcode 27.1과 iOS runtime이 있습니다. 결과는 호스트와 같았고, setup은 아무것도 설치하지 않았으며, guest Simulator에서 Food Truck 첫 화면과 down을 확인했습니다. guest의 kern.hv_support는 0이지만 iOS Simulator는 실행됐습니다. 원 기준 VM metadata는 바뀌지 않았습니다. 이 clone은 #226의 setup 설치물을 담고 있으나 새 HOME과 시스템 PATH만 썼습니다.

수동 Xcode·라이선스 단계는 호스트에서 변경 없이 다시 검사했습니다. 첫 실행 상태와 라이선스 확인이 모두 0으로 끝났고 doctor도 Xcode 초기 설정 완료로 보고했습니다. 라이선스 미동의나 첫 실행 미완료 상태는 관리자 변경이 필요해 만들지 않았으므로 그 경로는 미검증으로 남깁니다. Xcode가 없는 환경의 경로도 기준 VM에 Xcode가 있어 관측하지 않았습니다.

수집 오류와 판정 불가를 제품 실패와 분리해 보존했습니다. 첫 GUI 제어 승인 거부, CLI down에 build·기기 선택자를 넘긴 수집기 인수 오류(제품은 변경 없이 거부), 호스트 clone 사슬의 오래된 이력 객체 누락으로 VM 전송용 bundle을 만들지 못한 일(작업 트리 bytes는 고정값과 같음)이 여기에 해당합니다.

AC02는 준비 계획·승인·수동 항목·사람 준비, AC03은 취소·실패·동시 대상·소스 보호, AC04는 같은 입력의 CLI·GUI 결과와 build의 설치 없음, AC05는 4개 fresh clone 첫 화면과 원본 기준선, AC06은 실제 Mac 기존 환경 반복과 기준 VM clone 경로에 연결합니다. AC15의 같은 후보 연결과 AC17의 실패 이력 보존을 유지합니다. 전체 공동 게이트와 서명·공증·공개 판정은 별도로 남습니다.

이 정본은 #226 정본 위에 #227의 네이티브 iOS 범위 11개 요구를 pass로 더합니다(AC05 경로 4개, AC02·AC03·AC04 각 2개, AC06 1개). 현재 결과는 pass 29개, unverified 31개입니다. 다른 프레임워크·공통 게이트의 미검증과 unsigned 배포 제한으로 공동 출시 판정은 blocked입니다. #226까지의 결과와 이력을 그대로 보존하며 AC15·AC17 전체 완료로 확대하지 않습니다.

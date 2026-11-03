alpha.17 공동 후보로 #230의 병렬 실행·취소·접근성 게이트를 실제 GUI와 CLI로 돌렸습니다. 네이티브 iOS(Food Truck·NetNewsWire)로 독립 repo 두 창의 병렬 빌드, 같은 repo 두 worktree 병렬 build, CLI·GUI 교차 충돌, 창 닫기·개별 취소·전체 종료를 확인했습니다. 경로 별칭, Android GUI 행, 실제 VoiceOver 낭독은 확인하지 못했습니다. 이 문서는 #230의 alpha.17 실제 관측을 기록합니다. 최종 head의 독립 리뷰·CI와 병합 상태는 PR·이슈에 별도로 기록합니다.

후보는 `5b987003fb2b89a2c7bf75087512d135c0d9b63f47a38dd0b4a518ce4e7b532e`, 제품 source는 `595210e8d3e6249b879388005a318543c0ce778a`입니다(#224 alpha.17 고정). CLI·GUI 실행 파일의 SHA-256은 실행 때마다 고정값과 같았고 GUI 첫 창은 버전 0.1.0-alpha.17이었습니다. 제품 코드는 바꾸지 않았고 이전 후보 결과를 승계하지 않았습니다. 호스트는 macOS 27.2 arm64, Xcode 27.2(27B52), iOS 27.0 Simulator입니다. GUI는 두 번 실행했습니다(11:17~11:43 KST, 13:22~13:31 KST). 실행 전에 검사 조건 문서를 따로 만들지 않았고, 이 보고서와 원시 기록이 조건과 결과를 함께 담습니다.

| 기준 | 관측 | 결과 |
| --- | --- | --- |
| AC07 창·worktree | 한 GUI에서 독립 repo 두 창의 빌드가 함께 돌고 둘 다 완료. 같은 repo 두 worktree의 CLI build 동시 성공. 빌드 로그가 폴더 identity별로 분리. 경로 별칭·일반 폴더는 미기록 | pass(미검증 항목 있음) |
| AC08 교차 충돌 | GUI가 실행한 앱이 있는 기기로 보낸 다른 clone의 CLI up이 변경 전 거부, 소유 프로젝트·operation·PID 표시 | pass |
| AC10 창 닫기·개별 취소 | 완료 창 닫기 뒤 앱 유지, 작업 중 창 닫기 대화상자, 빌드 작업 취소와 실행(up) 취소 뒤 자식·프로젝트 경로 프로세스 부재, 선택 유지, 다른 앱 유지 | pass |
| AC10 전체 종료 | 작업 계속은 두 작업 유지. 모두 취소 후 종료는 GUI 종료와 xcodebuild 정리, 그러나 actool이 최대 약 108초 남음 | inconclusive |
| AC11 키보드·VoiceOver | 키보드로 프로젝트 열기·메뉴 선택·대화상자 기본 버튼. Tab 포커스와 실제 낭독은 미수집 | unverified |
| #228 GUI 4행 | 다른 프로젝트 Emulator 점유로 Android GUI 미실행 | unverified |

**독립 repo 두 창.** 두 번째 GUI 실행에서 Cmd+O와 폴더 경로 입력으로 Food Truck과 NetNewsWire를 각각 창으로 열고, Scheme(Food Truck, NetNewsWire-iOS)과 서로 다른 소유 Simulator(Runstir224_Native_iOS_2ce1, Runstir224_native-flutter-gui_2ce1)를 골랐습니다. 두 창의 빌드를 연달아 누르자 2초 간격 프로세스 기록에서 두 프로젝트의 xcodebuild가 04:25:11Z부터 04:25:57Z까지 함께 돌았습니다. 두 창 모두 "빌드: 완료"였고 빌드 로그는 각각 BUILD SUCCEEDED(13:25:55, 13:26:37 KST)로 끝났습니다. 빌드 뒤에도 두 창의 기기·Scheme 선택이 그대로였습니다. 첫 GUI 실행에서는 Food Truck 실행(up)이 끝나 Simulator에 Truck 첫 화면이 뜬 뒤 NetNewsWire 작업을 시작해, 그 회차는 동시 진행이 아니었습니다. 네 프로젝트의 빌드 로그는 프로젝트 폴더 identity마다 따로 생겼습니다. 경로 별칭(ft-alias, ft-wt1로 가는 symlink)을 열었을 때 기존 ft-wt1 창이 앞으로 오는 것을 수집 도구 화면에서 보았지만 원시 기록을 남기지 않았고, 재확인은 사용자 화면 사용과 겹쳐 중단해 미검증으로 둡니다. 일반 폴더(ft-plain)는 실행하지 않았습니다.

**같은 repo 두 worktree.** 새 local clone ft-wt1과 그 git worktree ft-wt2에서 CLI build를 같은 시각에 시작해 서로 다른 Simulator 대상으로 130초·139초에 모두 succeeded였습니다(validate·device·build 완료).

**교차 프로세스 충돌.** GUI가 실행한 Food Truck(PID 76202)이 Native_iOS_2ce1에서 도는 동안 Food Truck CLI clone의 `up`을 같은 기기로 보내자 19.7초 만에 변경 전 거부됐습니다. 오류는 앱이 다른 프로젝트의 up operation으로 아직 실행 중이라며 경로·operation·PID를 밝히고, 다른 자원을 고르거나 소유 작업을 명시적으로 멈추라고 안내했습니다. 아무것도 전환·중지·대기·삭제하지 않았다고 알렸고 앱은 같은 PID로 남았습니다. 이후 같은 프로젝트의 CLI `down`이 GUI가 띄운 앱을 stopped로 정리했습니다.

**창 닫기와 개별 취소.** 첫 GUI 실행에서 실행(up)을 마친 Food Truck 창을 닫아도 앱은 같은 PID로 계속 실행됐습니다. 빌드 작업 중인 NetNewsWire 창을 닫으려 하자 현재 상태(build: running)와 "작업 계속"·"취소 후 닫기"의 뜻, 완료한 앱·기기는 창을 닫아도 종료하지 않는다는 설명이 나왔고, 기본 버튼 작업 계속(Return)으로 창과 빌드가 그대로 남았습니다. 이어 그 빌드 작업을 취소하자 "빌드: 취소됨 / 취소됨: operation cancelled"로 끝났고 GUI 직속 자식과 기록한 xcodebuild PID가 없었습니다. 이 회차는 프로젝트 경로의 손자 도구를 검사하지 않았습니다. 두 번째 GUI 실행에서는 NetNewsWire 실행(up)을 빌드 단계(xcodebuild build와 swift-frontend 진행 중, 기기 단계에서 Simulator 부팅)에서 취소했습니다. 결과는 "실행: 취소됨"이었고, 2초 간격 기록에서 xcodebuild는 2초 안에, 프로젝트 경로의 swift-frontend는 약 5초 안에 사라졌으며 이후 80초간 프로젝트 경로 프로세스가 없었습니다. 두 취소 모두 기기·Scheme 선택이 유지됐고 "선택 항목을 확인하지 못했습니다" 문구가 없었습니다(#358). 다른 창이 띄운 Food Truck은 계속 실행됐습니다. 완료된 기기 단계의 Simulator 부팅은 그대로 남았고, 이후 CLI `down`은 설치 기록이 없어 앱 중지를 건너뛰었으며 수집기가 Simulator를 껐습니다. "취소 후 닫기" 버튼 자체는 누르지 않았습니다.

**전체 종료.** 첫 GUI 실행에서 NetNewsWire 빌드(앞서 취소한 뒤 다시 시작해 02:42:11Z에 BUILD SUCCEEDED)와 ft-wt1 validate가 도는 중 Cmd+Q는 두 창과 단계를 나열하며 "작업 계속"·"모두 취소 후 종료"를 냈고, 작업 계속(Return)으로 두 작업이 계속됐습니다. 다시 Cmd+Q를 했을 때는 NetNewsWire가 이미 끝나 ft-wt1 build 1개만 남아 있었습니다. 모두 취소 후 종료를 누르자 GUI가 약 02:42:27Z에 종료됐고 직속 xcodebuild가 사라졌습니다. 그러나 02:42:28Z 표본에는 ft-wt1 경로의 프로세스 12개(actool 포함)가 남아 있었고, `actool`은 xcodebuild 프로세스 그룹 밖(부모 launchd)에서 02:42:48Z에도 살아 있다가 02:44:15Z 전에 스스로 끝났습니다(잔류 21초 이상, 최대 약 108초). 제품이 기다려야 하는 도구 범위인지는 판정하지 않고 inconclusive로 남깁니다. 실행을 마친 Food Truck 앱은 종료 뒤에도 실행 중이었습니다. 두 번째 GUI 실행은 작업이 없을 때 메뉴의 Runstir 종료로 끝냈습니다.

**키보드와 VoiceOver.** 프로젝트 열기(Cmd+O, 폴더 이동, Return 두 번), 열린 메뉴의 화살표·Return 선택, 대화상자 기본 버튼의 Return, Cmd+`의 창 전환을 실제로 확인했습니다. 호스트의 키보드 탐색 설정이 꺼져 있어(AppleKeyboardUIMode 0) Tab으로 팝업 버튼에 가는 경로는 확인하지 않았고 시스템 설정은 바꾸지 않았습니다. VoiceOver는 켰지만(첫 실행 안내는 사용자가 "VoiceOver 사용"을 누름) 캡션 창이 화면 수집 도구에서 가려졌고, VoiceOver를 AppleScript로 읽는 설정 변경은 보안 약화로 거부되어 실제 낭독 문구를 수집하지 못했습니다. VoiceOver는 원래대로 껐고 VoiceOver 유틸리티 설정은 바꾸지 않았습니다. 선택·승인·수동 대기·실패 화면의 낭독과 포커스는 미검증입니다.

**Android와 #228 GUI 행.** 다른 프로젝트의 Emulator(Smallnext35, 이후 sn348·sn361)가 같은 adb 포트 범위에 떠 있어, 소유 AVD Runstir225_gui35 부팅 전 수집기 검사가 adb 5092 namespace에서 그 Emulator를 보고 멈췄습니다. 남의 Emulator는 끄지 않았습니다. 따라서 #228의 Todo·NIA GUI 첫 화면(AC05 GUI 2개), CLI·GUI 비교(AC04 2개), Android build 뒤 기기 칸 유지(#353)는 이번에도 확인하지 못했습니다. iOS에서는 빌드 뒤 기기 칸 유지와 취소 뒤 #358 문구 없음을 확인했습니다.

수집 오류와 호스트 조건은 제품 실패와 분리해 보존했습니다. 첫 CLI 병렬 up은 수집기가 `--scheme`을 빠뜨려 제품이 변경 전 선택을 요구했습니다. 다음 두 번의 CLI 병렬 up은 호스트 load average가 109~196일 때 제품이 xcodebuild 목록·설정 조회의 120초 제한에서 실패했습니다(completed 없음, 기기 Shutdown 유지). 같은 xcodebuild 목록 조회가 제품 밖에서도 4초~1044초로 흔들려 호스트 정지로 분류했습니다. GUI 실행 동안에도 load average는 50~250이었습니다. 수집기 셸의 평범한 `adb devices`가 기본 adb 서버를 한 번 띄워 남의 Emulator를 보았고 즉시 종료했습니다. 첫 GUI 실행 시도에서는 GUI 조작 권한이 거부되어 조작 없이 종료했습니다. 두 번째 GUI 실행 중 다른 앱이 앞으로 와 키 입력이 두 번 멈췄고, 파일 선택 창은 다른 프로세스라 조작할 수 없어 취소했습니다.

정리 뒤 후보 프로세스가 없었고, 사용한 세 Simulator는 Shutdown이며, 입력 HOME에 claim·reservation 파일과 Emulator console 인증 사본이 없었습니다. 고정 입력 여섯과 새 worktree 둘의 추적 source·index·flags가 보존됐습니다. 다른 AVD(cli37·gui37)의 alpha.14 RN claim 2개는 범위 밖이라 그대로 두었습니다.

AC07·AC08·AC10·AC11은 위 표로 연결합니다. AC09(개발 포트 전달)와 AC14(앱 교체·데이터 보존과 병렬 파일+프로젝트)는 이번에 실행하지 않아 미검증입니다. AC15의 같은 후보 연결과 AC17의 실패 이력 보존을 유지합니다(#228 결과는 `results-228.json`, #224 결과는 `results-224.json`). 이 정본은 #228 alpha.17 정본 위에 #230 범위를 더합니다.

현재 결과는 pass 11개, fail 0개, inconclusive 1개, unverified 44개입니다. #228(pass 8)에 AC07·AC08·AC10 창 닫기·개별 취소 3개가 pass로 더해졌고, AC10 전체 종료가 inconclusive, AC11과 #228 GUI 4행이 unverified입니다. 남은 미검증은 실제 VoiceOver 낭독, 키보드 탐색을 켠 Tab 포커스, 승인·수동 대기·실패 화면의 접근성, 경로 별칭의 기존 창 재사용 기록, 일반 폴더 병렬, 두 작업이 모두 도는 상태의 모두 취소 후 종료와 손자 도구 잔류 판정, 취소 후 닫기 경로, RN·Flutter 개발 포트 전달(AC09), 작업 폴더·설치 목적지·포트 충돌과 stale 소유권(AC08 나머지), 앱 교체·데이터(AC14), Android GUI 4행과 #353입니다. unsigned 배포 제한도 있어 공동 출시 판정은 blocked입니다.

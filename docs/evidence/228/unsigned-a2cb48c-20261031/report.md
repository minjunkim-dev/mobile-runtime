alpha.15의 네이티브 Android 최소 앱 Todo와 OSS 앱 Now in Android(NIA)를 CLI·GUI 4개 경로에서 실행해 올바른 첫 화면과 정상 종료를 확인했습니다. 이 문서는 #228의 실제 실행·경계·보존 검증을 기록합니다. 최종 head의 독립 리뷰·CI와 병합 상태는 PR·이슈에 별도로 기록합니다.

후보는 `be9251f8488e34acb0072b106c4fd2843c1ad8a82581a911b5082dc00106f54a`, 제품 source는 `a2cb48c23835f2f03d2dfb8655c9bd4b625bab09`입니다. CLI·GUI 실행 파일과 후보 metadata의 SHA-256은 시작 때 고정값과 같았으며 제품 코드는 수정하지 않았습니다. 이전 후보의 네이티브 Android 결과는 승계하지 않았습니다. 호스트는 macOS 27.2(26B123) arm64, Emulator 37.1.11, API35 Google APIs arm64 r9 image, 고정 AVD `Runstir225_cli35`·`Runstir225_gui35`입니다.

| 앱 | CLI | GUI | 준비 |
| --- | --- | --- | --- |
| Todo `:app/debug` | "You have no tasks!" 첫 화면, down 뒤 앱 PID 부재 | 같은 첫 화면, 종료 완료, PID 부재 | 설치 항목 없는 계획 승인 → 완료. 빈 SDK root 경로는 부분 완료 뒤 #360 실패 |
| NIA `:app/demoDebug` | For you 관심 주제 첫 화면, down 뒤 5초간 PID 부재 | 같은 첫 화면, 종료 완료, PID 부재 | CLI는 `mobile.yml`로 모듈·변형 선택 뒤 설치 항목 없이 완료. GUI 준비 계획은 화면 선택을 쓰지 않음(#362) |

각 행은 alpha.15용 별도 full Git clone이고 HOME·TMPDIR을 새로 만들었습니다. 의존성·빌드 산출물을 복사하지 않았습니다. JDK·SDK·Gradle user home·고정 AVD는 기존 것을 썼으므로 cold-cache 결과로 세지 않습니다. 고정 AVD는 이전 후보 실행의 앱 데이터가 남아 있어 새 기기 데이터의 첫 실행이 아닙니다. 4개 경로는 소유 AVD를 `-no-window`로 미리 부팅한 조건이며 제품 cold boot 증거가 아닙니다. 별도로 Runstir가 새로 만든 AVD를 Runstir `up`이 직접 켜고 Todo 첫 화면을 띄운 뒤 `down`이 그 Emulator를 종료한 경로를 확인했습니다. Runstir 없이 원래 Gradle·avdmanager·emulator·adb만 쓴 별도 clone 2개와 새 작업 소유 AVD에서 두 앱의 build·설치·실행·첫 화면 기준선을 다시 확인했습니다. 새 기기 데이터라 NIA 첫 화면 위에 OS 알림 권한 요청이 겹쳤습니다.

doctor는 Todo·NIA 모두 빌드 전 ABI를 알 수 없어 `android.avd`가 unknown이고 전체 결과도 unknown입니다. up의 최상위 status도 같은 이유로 unknown이었고 작업은 succeeded였습니다. NIA는 application module이 둘(`:app`, `:app-nia-catalog`)이라 기본 doctor가 warning·모듈 선택 요구를 냈습니다. CLI doctor·setup에는 `--module`이 없어 제품 안내대로 추적되지 않는 `mobile.yml`에 `android.module: ":app"`, `android.variant: "demoDebug"`를 쓴 뒤 다시 실행했습니다. GUI는 모듈·변형 선택 칸을 썼고 환경 확인·build·up은 그 선택을 따랐지만, 준비 계획은 화면 선택을 쓰지 않고 `mobile.yml`을 요구했습니다(#362).

GUI에서 Android build가 끝나면 기기 선택 칸이 비고 비활성화되는 결함(#353)과, 취소 뒤 선택 칸 아래 "선택 항목을 확인하지 못했습니다" 안내가 뜨는 결함(#358)을 다시 재현했습니다. 숨은 선택값이 남아 NIA 실행은 정상 완료됐습니다.

준비 경계를 실제로 실행했습니다. 빈 소유 SDK root와 AVD home의 새 clone에서 setup 계획은 정확한 SDK package 6개(build-tools 34.0.0, cmdline-tools 23.0, emulator, platform-tools, platforms;android-35, API35 image)와 이후 AVD 생성을 냈습니다. 라이선스 기록 없이 승인하면 아무것도 내려받지 않고 waiting-manual로 끝났고 Runstir는 라이선스 동의 명령을 실행하지 않았습니다. 사람 단계로 기존 검증 SDK에 이미 있는 `android-sdk-license` 기록(같은 hash)을 그대로 재사용했습니다. 새 동의는 하지 않았습니다(#204와 같은 절차). 새 계획은 image의 `android-sdk-arm-dbt-license`만 수동으로 남겼습니다. 다운로드 중 SIGINT는 130/cancelled였고 자식과 미완료 stage가 남지 않았습니다. 다시 승인하자 build-tools 34.0.0이 설치됐고, 그 사이 다른 clone이 같은 SDK root를 승인하자 destination lease로 단계 전에 거부됐습니다. 그러나 다음 cmdline-tools 23.0은 커밋 직전 재검사에서 "Approved installation identity is no longer available before commit"로 실패했고, 경합 없는 재승인에서도 같았습니다. Runstir의 자기 stage가 `cmdline-tools/` 아래에 생겨 도구 탐색에 잡히는 것으로 보이며 #360으로 분리했습니다. 완료한 build-tools는 보존됐고 stage는 정리됐습니다. 이 결함 때문에 빈 SDK root에서 Todo 실행까지의 준비는 완료되지 않았으므로 해당 AC02 요구를 fail로 기록합니다.

기존 SDK(cmdline-tools 21.0 재사용)와 빈 AVD home에서는 setup이 pixel_7·API35 image의 새 AVD 생성만 계획했고, 승인 뒤 AVD를 만들었습니다. 생성 전후 SDK root에 새로 쓰인 파일은 없었습니다. 재계획은 그 AVD를 reused로 보고했습니다. 같은 AVD에서 첫 up은 수집기가 켜 둔 다른 Emulator(console 인증 사본 없음)의 identity를 읽지 못해 단계 중 거부됐고, 그 Emulator를 끈 뒤 Runstir가 AVD를 직접 켜서 Todo 첫 화면을 띄웠습니다.

실행 경계도 확인했습니다. CLI NIA up의 Gradle 단계 중 SIGINT는 130/cancelled였고 Gradle 자식이 남지 않았으며 같은 입력의 up이 다시 성공했습니다. GUI Todo build 중 작업 취소는 "빌드: 취소됨"으로 끝났고 Gradle 자식이 사라졌습니다. 같은 AVD에 두 clone이 동시에 up하면 뒤 요청은 기존 up 작업과 프로젝트를 밝히며 단계 시작 전에 거부됐고 앞 작업은 성공했습니다. 없는 variant의 build는 변경 전에 `android.target` 미준비로 실패했습니다. GUI build 전후 Emulator에 설치된 앱의 codePath·lastUpdateTime이 같아 build가 설치하지 않았음을 직접 관측했고, up 뒤에는 바뀌었습니다. 모든 경로에서 추적 source·index·flags가 보존됐습니다.

active-run 경계에서 #226이 두 고정 AVD에 남긴 LocalSend 앱 claim을 만났습니다. Emulator가 꺼진 상태의 Todo up은 claim을 관측할 수 없어 단계 전에 거부됐습니다(정상 보호). Emulator를 켜자 LocalSend가 자체 RebootReceiver로 다시 실행돼 Todo GUI up이 거부됐습니다. 안내대로 소유 프로젝트(#226 GUI LocalSend)에서 down을 실행했지만 "no Android active run recorded"로 아무것도 하지 않았고 claim도 남았습니다. 사람이 그 소유 테스트 앱만 force-stop한 뒤 up이 성공했습니다. Runstir 명령만으로는 복구되지 않아 #361로 분리했고 claim 파일은 손대지 않고 보존했습니다. NIA down 뒤 5초간 앱 PID가 다시 나타나지 않았습니다.

AC06은 실제 Mac의 Android 가속(HVF, doctor `android.emulator.acceleration` pass)과 기존 환경 반복으로 확인했습니다. 보존 기준 VM은 guest의 kern.hv_support가 0이라 Android 실행이 불가능하며, 이번에는 VM 준비 경로를 실행하지 않았습니다.

Android 실기기는 미검증입니다(AC19). Emulator 성공이나 클라우드 실행을 로컬 USB/RSA 검증으로 바꾸지 않았습니다.

수집 오류와 판정 불가를 제품 실패와 분리해 보존했습니다. doctor에 `--module`을 넘긴 수집기 인수 오류(exit 64), 기준선 monkey 실행 명령 실패(같은 AVD를 다시 켜 `am start`로 재실행), 첫 NIA 화면 캡처가 로딩 중이었던 일(UI 텍스트는 첫 화면, 다시 캡처), GUI 제어 중 다른 앱이 앞으로 나온 일이 여기에 해당합니다. Emulator console 인증 사본은 #226과 같은 수집기 전제로 입력 HOME에 복사했다가 정리 때 지웠습니다.

AC02는 준비 계획·라이선스 대기·재사용·부분 완료·AVD 생성, AC03은 취소·동시 대상·잘못된 variant·active-run 보호·소스 보호, AC04는 같은 입력의 CLI·GUI 결과와 build의 설치 없음, AC05는 4개 fresh clone 첫 화면과 원본 기준선, AC06은 실제 Mac 가속과 기존 환경 반복에 연결합니다. AC15의 같은 후보 연결과 AC17의 실패 이력 보존을 유지합니다. 전체 공동 게이트와 서명·공증·공개 판정은 별도로 남습니다.

이 정본은 #227 정본 위에 #228의 네이티브 Android 범위를 더합니다. AC05 경로 4개와 AC02(NIA)·AC03 2개·AC04 2개·AC06 1개는 pass, AC02(Todo, 빈 SDK root 준비)는 #360으로 fail입니다. 현재 결과는 pass 39개, fail 1개, unverified 27개입니다. 다른 프레임워크·공통 게이트의 미검증과 unsigned 배포 제한으로 공동 출시 판정은 blocked입니다. #227까지의 결과와 이력을 그대로 보존하며 AC15·AC17 전체 완료로 확대하지 않습니다.

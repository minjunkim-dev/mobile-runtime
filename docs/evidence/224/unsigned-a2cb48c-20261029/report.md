# alpha.15 unsigned 공동 후보와 고정 입력

#346·#344 수정과 main의 후보 제작기가 병합된 main `a2cb48c23835f2f03d2dfb8655c9bd4b625bab09`에서 새 후보 `0.1.0-alpha.15`를 만들었다. CLI와 GUI가 같은 제품 버전 `0.1.0-alpha.15`를 보고한다. #224의 후보·입력 연결을 기록하며 #225~230의 실제 기능 게이트는 미완료다. AC17의 원본 참조와 실패 이력을 함께 보존한다.

| 항목 | 고정값 |
| --- | --- |
| candidate ID / CANDIDATE.json SHA-256 | `be9251f8488e34acb0072b106c4fd2843c1ad8a82581a911b5082dc00106f54a` |
| 공통 Core identity | `bf807301aa668bcdc79b7f12c035418d0d174af68362b1621ef51b5783cbd9f6` |
| CLI archive SHA-256 | `d3481b344e76aa66e574fbf1a675973200080ab08a0c444153b3a1645e7e8644` |
| GUI DMG SHA-256 | `3dba8b3868a4f6df277edea581adf7c23230db4c6a9ecaecd23836e7a96d4759` |
| Homebrew formula SHA-256 | `bbd8652f6ff6ce18be3b6ffbc2b18da819ee7b2fbd9842021a528177f7b0463e` |
| 입력 index SHA-256 | `7ceb9eaf71b358cb61b12bbbeb2a02b1144780b8062d8cd1653058c58991c0eb` |

main의 `scripts/package-release.sh`로 한 번의 disposable release build를 실행해 CLI·GUI와 Core 객체 48개를 만들었다. 제작기는 빌드 폴더를 지운 뒤 archive smoke와 `scripts/verify-candidate.sh`를 실행했고 모두 통과했다. 두 배포 파일의 BUILD metadata와 resource bytes가 일치하고 GUI bundle에는 CLI가 없다. DMG는 읽기 전용으로 마운트해 앱을 복사한 뒤 분리했다. formula는 구문만 검사했으며 실제 Homebrew 설치는 하지 않았다. `CANDIDATE.json`의 `ciRun`은 로컬 제작이라 `null`이다.

Source main CI [40892947080](https://github.com/minjunkim-dev/mobile-runtime/actions/runs/40892947080)와 CodeQL [40892946868](https://github.com/minjunkim-dev/mobile-runtime/actions/runs/40892946868)은 exact SHA의 모든 job이 성공했다. CI는 1차 시도에서 macOS runner를 할당받지 못해 취소됐고, 2차 시도에서 부하 중 `ProcessRunnerTests`의 5초 timeout 하나가 실패했다. 두 실패의 기록을 보존했고, 이 tree는 CI를 통과한 PR #351 최종 head와 같다. alpha.14 source 이후 병합된 제품 변경은 다음과 같다. 각 PR은 별도 컨텍스트의 리뷰와 최종 head CI를 거쳐 병합됐다.

| PR | 제목 | merge |
| --- | --- | --- |
| #347 | fix: GUI 환경 확인에 미리 준비한 의존성 선택 전달 (#346, #345) | `a65d91b` |
| #348 | fix: doctor의 Flutter Android 준비 실패에 미리 준비한 의존성 안내 추가 | `1720d88` |
| #350 | feat: 같은 source의 unsigned CLI·GUI 후보 제작과 검사 (#222) | `200be0f` |
| #351 | perf: Flutter Android 보호 검사에서 SDK 재해시 대신 메타데이터 비교 (#344) | `a2cb48c` |

## 여섯 조합의 입력

조합·표본·runtime은 alpha.14와 같다(tuples.json). 기존 baseline과 별도인 checkout 24개를 재사용했다. alpha.14가 이 입력에서 이미 실행됐으므로 Runstir 상태와 빌드 출력이 남아 있을 수 있다. 새 clone이나 cold setup 성공으로 세지 않는다.

현재 입력의 추적 항목 26,954개는 alpha.14 descriptor의 원래 값과 일치한다. 파일 bytes·종류·실행 비트와 gitlink OID·디렉터리 내용, HEAD와 추적 목록을 비교했고 index/flags digest도 alpha.14와 같다. 도구 버전 12개와 선택 SDK 파일 15개를 다시 확인했다. Simulator의 이름·runtime·사용 가능 상태와 AVD config를 조회했으며 기기를 부팅하거나 설치하지 않았다. SDK·HOME·cache 전체 재hash나 새 runtime boot 성공은 주장하지 않는다.

**고정 전 정리:** 고정 SDK의 `platform-tools/adb`는 #226 alpha.14 게이트(2026-10-27)가 설치한 `adb devices` 필터 wrapper로 바뀌어 있었다. 사용자 승인 뒤 wrapper를 제한 보관소에 보존하고 원본(`adb.real`, 고정 SHA와 같음)을 `adb`로 되돌렸다. 이전 게이트가 남긴 headless Emulator 2개(cli35·gui35)도 사용자 승인 뒤 종료했다. 정상 종료 신호에 응답하지 않아 보조 프로세스는 강제 종료했고, 두 AVD에 `hardware-qemu.ini.lock`이 남아 있다. 정리 후 도구·SDK 파일·AVD config 재확인은 alpha.14 고정값과 모두 같다. 입력에 쓰지 않는 Simulator 3개는 alpha.14 이후 삭제됐다.

## 판정과 다음 게이트

새 후보 결과는 AC15 후보·입력 연결 한 행만 pass이고 나머지 43행은 unverified다. AC15 전체나 실제 앱 첫 화면·취소·접근성을 통과한 판정은 아니다. 원본은 명시한 제한 보관소에 hash로 연결하며 큰 raw 입력의 참조 무결성과 JSON 의미 검증을 구분한다. alpha.14의 성공·실패·UNKNOWN은 기존 보고서에 보존하고 이번 결과로 이월하지 않았다.

#220의 Ad Hoc은 사용자 결정대로 마지막 유료 계정 단계에 보류한다. Development 경로로 대체하지 않는다. #221의 실제 VoiceOver·키보드·시각 배치 검증은 #230과 함께 남아 있다. 이 미검증 상태로 티켓을 닫거나 전체 출시를 승인하지 않는다. Android 실기기는 AC19의 미검증 범위를 유지한다.

현재 호스트 기본 임시 mobile 경로는 기존 SSD symlink이며 후보가 안전 검사에서 거부한다. 이 작업은 링크와 전역 설정을 변경하지 않았다.

signing=unsigned, notarization=not-requested, distributionReady=false다. 바이너리 업로드·태그·공식 공개는 수행하지 않았다. #225~230 실제 기능 게이트를 마친 뒤 #222 서명·공증 → #231 → #232 → #233 순서를 유지한다. 후보나 입력이 바뀌면 새 시도와 영향 재검증을 기록하며 같은 버전 파일을 덮어쓰지 않는다.

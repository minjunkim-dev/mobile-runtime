# alpha.17 unsigned 공동 후보와 고정 입력

#370·#373 수정(PR #371·#372·#375)과 GUI 결과 표시(#376)·iOS doctor(#379) 수정이 병합된 main `595210e8d3e6249b879388005a318543c0ce778a`에서 새 후보 `0.1.0-alpha.17`를 만들었다. CLI와 GUI가 같은 제품 버전 `0.1.0-alpha.17`를 보고한다. #224의 후보·입력 연결을 기록하며 #225~230의 실제 기능 게이트는 미완료다. AC17의 원본 참조와 실패 이력을 함께 보존한다.

| 항목 | 고정값 |
| --- | --- |
| candidate ID / CANDIDATE.json SHA-256 | `5b987003fb2b89a2c7bf75087512d135c0d9b63f47a38dd0b4a518ce4e7b532e` |
| 공통 Core identity | `5ec808d5845c4a6605f2f2f3867d4c3b6ffa864f593a6aeeab56a0ffd8b869ad` |
| CLI archive SHA-256 | `7c28933038fef1e2f8100b655753d1dd76f8e516c76a8d4588259a71e6a1f509` |
| GUI DMG SHA-256 | `9e243ffa3dbe0b66da705bc3d2d4eb54e8f0843ea8fb27aafe02e34d78710732` |
| Homebrew formula SHA-256 | `e6521f9f79be7e827b1f147bfc2756978bfe6a26b668c2fe23c1a62076a74a69` |
| 입력 index SHA-256 | `32901bad7e68216cc8c9fde948b433964f7bda1fcc15196f29022d951e901900` |

main의 `scripts/package-release.sh`로 한 번의 disposable release build를 실행해 CLI·GUI와 Core 객체 48개를 만들었다. 제작기는 빌드 폴더를 지운 뒤 archive smoke와 `scripts/verify-candidate.sh`를 실행했고 모두 통과했다. 두 배포 파일의 BUILD metadata와 resource bytes가 일치하고 GUI bundle에는 CLI가 없다. DMG는 읽기 전용으로 마운트해 앱을 복사한 뒤 분리했다. formula는 구문만 검사했으며 실제 Homebrew 설치는 하지 않았다. `CANDIDATE.json`의 `ciRun`은 로컬 제작이라 `null`이다.

Source main CI [41441316045](https://github.com/minjunkim-dev/mobile-runtime/actions/runs/41441316045)와 CodeQL [41441316084](https://github.com/minjunkim-dev/mobile-runtime/actions/runs/41441316084)은 exact SHA의 모든 job이 첫 시도에서 성공했다. alpha.16 source 이후 병합된 제품 변경은 다음과 같다. 각 PR 본문의 리뷰 기록과 최종 head의 필수 CI 성공을 제한 원본 `source-prs`에 보존했다. #379 본문에는 같은 컨텍스트의 code-review 기록만 있고 별도 컨텍스트 리뷰 기록이 없다. broad 변경으로 사람 승인이 필요하다고 적혀 있으며 저장소 소유자 계정이 병합했다. 이 차이를 고치지 않고 기록한다. #379는 iOS doctor 변경이라 #228 Android 범위와 겹치지 않는다. 같은 기간의 증거 문서(#374)는 배포 파일에 들어가지 않으므로 표에서 뺐다.

| PR | 제목 | merge |
| --- | --- | --- |
| #371 | fix: Android down이 pidof 응답을 한 관측으로 읽고 다른 앱 claim을 바로 알린다 (#370) | `137ea4d` |
| #372 | fix: 보존한 Android claim 안내가 다음 down이 실제로 하는 일만 말한다 | `3557996` |
| #375 | fix: 빌드 중 취소된 Android up이 기기 reservation을 남기지 않고 남은 reservation 거부가 복구 경로를 안내한다 (#373) | `11cab95` |
| #376 | fix: GUI build·up 결과가 기기·대상 목록과 선택 안내를 덮어쓰지 않는다 (#221, #353, #358) | `49366f7` |
| #379 | fix: 네이티브 iOS doctor가 선택한 scheme에서 측정한 deployment target으로 simulator.runtime을 판정한다 (#357) | `595210e` |

## 여섯 조합의 입력

조합·표본·runtime은 alpha.16과 같다(tuples.json). 기존 baseline과 별도인 checkout 24개를 재사용했다. alpha.14와 alpha.15가 이 입력에서 이미 실행됐으므로 Runstir 상태와 빌드 출력이 남아 있을 수 있다(alpha.16의 #228 게이트는 별도 clone을 썼다). 새 clone이나 cold setup 성공으로 세지 않는다.

현재 입력의 추적 항목 26,954개는 alpha.16 descriptor의 원래 값 및 승인된 차이와 일치한다. 파일 bytes·종류·실행 비트와 gitlink OID·디렉터리 내용, HEAD와 추적 목록을 비교했고 index/flags digest도 alpha.16과 같다. 도구 버전 12개와 선택 SDK 파일 15개를 다시 확인했다. alpha.16 이후 이 작업 밖에서 Xcode가 27.1(27A9275)에서 27.2(27B52)로 바뀌었고 iOS Simulator SDK도 27.2가 됐다. 후보는 이 Xcode로 만들었다. alpha.17의 iOS 게이트는 Xcode 27.2에서 실행해야 하며 27.1의 이전 iOS 결과를 이월하지 않는다. 나머지 도구와 SDK 파일, Simulator의 이름·runtime·사용 가능 상태, AVD config 4개는 alpha.16과 같다. Simulator 하나(iPhone 18 Pro)는 이 작업 밖에서 켜져 있었고 건드리지 않았다. 기기를 부팅하거나 설치하지 않았다. SDK·HOME·cache 전체 재hash나 새 runtime boot 성공은 주장하지 않는다.

## 판정과 다음 게이트

새 후보 결과는 AC15 후보·입력 연결 한 행만 pass이고 나머지 43행은 unverified다. AC15 전체나 실제 앱 첫 화면·취소·접근성을 통과한 판정은 아니다. 원본은 명시한 제한 보관소에 hash로 연결하며 큰 raw 입력의 참조 무결성과 JSON 의미 검증을 구분한다. alpha.16의 후보 고정과 #228 네이티브 Android 결과는 제한 원본에 이전 보고서로 연결했고, #225~#227 결과는 저장소의 기존 증거에 남는다. 이번 결과로 이월하지 않았다.

#220의 Ad Hoc은 사용자 결정대로 마지막 유료 계정 단계에 보류한다. Development 경로로 대체하지 않는다. #221의 실제 VoiceOver·키보드·시각 배치 검증은 #230과 함께 남아 있다. Android 실기기는 AC19의 미검증 범위를 유지한다.

signing=unsigned, notarization=not-requested, distributionReady=false다. 바이너리 업로드·태그·공식 공개는 수행하지 않았다. 후보나 입력이 바뀌면 새 시도와 영향 재검증을 기록하며 같은 버전 파일을 덮어쓰지 않는다.

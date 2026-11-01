# alpha.16 unsigned 공동 후보와 고정 입력

#360·#361·#362·#366 수정이 병합된 main `2961d4763f443566fbf7ef68e6158e4d321b53d0`에서 새 후보 `0.1.0-alpha.16`를 만들었다. CLI와 GUI가 같은 제품 버전 `0.1.0-alpha.16`를 보고한다. #224의 후보·입력 연결을 기록하며 #225~230의 실제 기능 게이트는 미완료다. AC17의 원본 참조와 실패 이력을 함께 보존한다.

| 항목 | 고정값 |
| --- | --- |
| candidate ID / CANDIDATE.json SHA-256 | `b3b699aa016349afba9ada38c14f80ae4a2263d137b7eeaa95f384880bcfb9d1` |
| 공통 Core identity | `000bca52abf6fa34868ae03b06d1c488f46639a52019ac2fd3219a9a0a9d9a1b` |
| CLI archive SHA-256 | `3711a8e51215ff1e670226a14206010f36dc4c47cdc02180ec6a10d7cc2e47d8` |
| GUI DMG SHA-256 | `a0b703a8642eff50bd9eec6d0310fabef3ee88660d64b89a366b80b4706b680d` |
| Homebrew formula SHA-256 | `114117eecffc5fb2dcddc92e94e9a452a90f6e80d540578c582821e7290fd8ab` |
| 입력 index SHA-256 | `cc06a068a537c274473c9e50afa6dd5fd8ef56ae809d78c0b76675efc6793fec` |

main의 `scripts/package-release.sh`로 한 번의 disposable release build를 실행해 CLI·GUI와 Core 객체 48개를 만들었다. 제작기는 빌드 폴더를 지운 뒤 archive smoke와 `scripts/verify-candidate.sh`를 실행했고 모두 통과했다. 두 배포 파일의 BUILD metadata와 resource bytes가 일치하고 GUI bundle에는 CLI가 없다. DMG는 읽기 전용으로 마운트해 앱을 복사한 뒤 분리했다. formula는 구문만 검사했으며 실제 Homebrew 설치는 하지 않았다. `CANDIDATE.json`의 `ciRun`은 로컬 제작이라 `null`이다.

Source main CI [41312082987](https://github.com/minjunkim-dev/mobile-runtime/actions/runs/41312082987)와 CodeQL [41312082996](https://github.com/minjunkim-dev/mobile-runtime/actions/runs/41312082996)은 exact SHA의 모든 job이 첫 시도에서 성공했다. alpha.15 source 이후 병합된 제품 변경은 다음과 같다. 각 PR 본문의 별도 컨텍스트 리뷰 기록과 최종 head의 필수 CI 성공을 제한 원본 `source-prs`에 보존했다. 같은 기간의 증거 문서(#352·#354·#355·#359·#363)와 테스트 대기 시간만 바꾼 #356은 배포 파일에 들어가지 않으므로 표에서 뺐다. #370(down 뒤 `pidof` 해석 통일)은 아직 열려 있어 이 후보에 들어가지 않았다(사용자 결정).

| PR | 제목 | merge |
| --- | --- | --- |
| #364 | fix: Android AVD manager 탐색이 Runstir 설치 stage를 도구로 잡지 않게 한다 (#360) | `57f53f9` |
| #365 | fix: 준비 계획이 Android 모듈·빌드 변형 선택을 쓰게 한다 (#362) | `7c2e92c` |
| #367 | fix: Android 대상 선택 근거가 명시 선택을 mobile.yml과 구분한다 (#366) | `7d02f1a` |
| #368 | fix: Android down이 중지를 확인한 앱의 claim을 해제하고 남은 claim도 정리한다 (#361) | `2961d47` |
| #369 | fix: 콜론 없는 Android 모듈 표기도 같은 setup plan-id를 낸다 (#362 후속) | `fcb5ce4` |

## 여섯 조합의 입력

조합·표본·runtime은 alpha.15와 같다(tuples.json). 기존 baseline과 별도인 checkout 24개를 재사용했다. alpha.14와 alpha.15가 이 입력에서 이미 실행됐으므로 Runstir 상태와 빌드 출력이 남아 있을 수 있다. 새 clone이나 cold setup 성공으로 세지 않는다.

현재 입력의 추적 항목 26,954개는 alpha.15 descriptor의 원래 값 및 승인된 차이와 일치한다. 파일 bytes·종류·실행 비트와 gitlink OID·디렉터리 내용, HEAD와 추적 목록을 비교했고 index/flags digest도 alpha.15와 같다. 도구 버전 12개와 선택 SDK 파일 15개를 다시 확인했다. `emulator -accel-check`의 출력만 호스트 OS 표시가 27.0에서 27.2로 바뀌었고 HVF 결과는 같다. #225~#228 alpha.15 게이트가 이미 macOS 27.2에서 실행됐으며 도구 변경이 아니다. Simulator의 이름·runtime·사용 가능 상태와 AVD config 4개도 alpha.15와 같다. Simulator 하나(iPhone 18 Pro)는 이 작업 밖에서 켜져 있었고 건드리지 않았다. 기기를 부팅하거나 설치하지 않았다. SDK·HOME·cache 전체 재hash나 새 runtime boot 성공은 주장하지 않는다.

## 판정과 다음 게이트

새 후보 결과는 AC15 후보·입력 연결 한 행만 pass이고 나머지 43행은 unverified다. AC15 전체나 실제 앱 첫 화면·취소·접근성을 통과한 판정은 아니다. 원본은 명시한 제한 보관소에 hash로 연결하며 큰 raw 입력의 참조 무결성과 JSON 의미 검증을 구분한다. alpha.15의 후보 고정과 #228 네이티브 Android 결과는 제한 원본에 이전 보고서로 연결했고, #225~#227 결과는 저장소의 기존 증거에 남는다. 이번 결과로 이월하지 않았다.

#220의 Ad Hoc은 사용자 결정대로 마지막 유료 계정 단계에 보류한다. Development 경로로 대체하지 않는다. #221의 실제 VoiceOver·키보드·시각 배치 검증은 #230과 함께 남아 있다. Android 실기기는 AC19의 미검증 범위를 유지한다.

signing=unsigned, notarization=not-requested, distributionReady=false다. 바이너리 업로드·태그·공식 공개는 수행하지 않았다. 후보나 입력이 바뀌면 새 시도와 영향 재검증을 기록하며 같은 버전 파일을 덮어쓰지 않는다.

# #204 실제 CLI·GUI 준비 흐름 실측

`70cb2877b259690832cec686e925087ddb1c1d01`의 실제 CLI와 GUI에서 수동 대기, 취소, 통제 권한 오류, 부분 완료, 재확인, 남은 package 설치를 확인했다. API harness로 대체하지 않았다.

| 사례 | CLI | GUI |
|---|---|---|
| license 부족 clone의 exact plan 승인 | waiting-manual / 1, 설치 0 | waiting-manual / 1, 설치 0 |
| 정상 payload 다운로드 중 취소 | 실제 TTY Ctrl-C, cancelled / 130 | CUA 작업 취소, cancelled / 130 |
| 소유 regular payload.zip의 통제 chmod000 | failed / 2 | failed / 2, permission denied |
| platform parent0555에서 가능한 package 설치 | build-tools 완료, partial / 1 | build-tools 완료, partial / 1 |
| parent0755 원복 후 이전 승인 | needs-approval / 1, 설치 0 | needs-approval / 1, 설치 0 |
| 남은 plan 재확인과 exact 승인 | platform35만 완료 | platform35만 완료 |
| 최종 SDK package | 둘 다 reuse, install 0 | 둘 다 reuse, install 0 |

최종 `partial / 1`은 AVD 사전 ABI 근거가 없어 남긴 manual 단계다. VM, ADB server, Emulator server, Android app build/install/launch는 실행하지 않았다. 공식 `emulator -accel-check` 읽기 probe만 소유 SDK에서 실행했다. 새 license는 수락하지 않았다. 설치 clone은 전체 SDK COW 복제가 보존한 기존 record를 사용했다. license 부족 관측 clone은 별도로 분리했다.

## 증거와 입력

- [고정 source·tuple·공식 archive pin·clone·lease](inputs.json)
- [실제 CLI JSON·NDJSON·TTY 핵심 결과](cli-results.json)
- [CUA 실제 GUI 관측](gui-results.json)
- [보존 감사와 명시한 한계](preservation.json), [snapshot 파일·해시 연결](preservation-receipt-index.json)
- [정상 debug bundle 구성과 전후 해시](packaging.json)
- [실패·중단 이력과 unknown](attempts.json)
- [private 원본 receipt 해시](private-receipts.json), [공개 사본 checksum](checksums.json)

GUI는 소유 `Runstir204Validation.app`만 사용했다. bundle ID는 `dev.runstir.gui.validation204`다. 원래 compiled binary와 최종 실행 binary의 전체 SHA는 다르다. task-local ad-hoc bundle signing이 signature를 바꿨다. Mach-O material section 40개의 bytes와 resource bytes는 같다. 이는 같은70cb compiled code의 debug packaging 증거다. Developer ID, 공증, Gatekeeper 통과를 입증하지 않는다.

첫 GUI는 원래 bundle ID를 사용했다. NSOpenPanel 뒤 공유 plist mtime 변화가 관측됐다. 즉시 중지했다. 원인을 확정하지 않았다. 원래 bytes를 수집하지 않아 자동 복원하지 않았다. 전용 ID 이후에는 새 preference만 생겼다. 기존 plist의 새 baseline hash와 mtime는 끝까지 같았다. 이 사실로 최초 변경 이력을 지우지 않는다. lookup 중 생성된 추가 소유 idle process도 별도로 기록했다. SIGTERM 뒤 부재를 확인했다. 그 process의 환경·guard·exit code는 unknown이다. 전체 기간 GUI PID가 하나였다고 주장하지 않는다. setup 실행은 순서대로 수행했다.

원본 SDK124,165개, 원본 cache26,229개, 전역 `.android`13개의 관측 lstat 항목은 전후에 같다. 인증 token은 stat만 비교했다. 기존 lease989개는 hash/stat가 같다. 새 작업의 정확 lock5개만 생겼다. 세 source의119 tracked bytes/modes와 staged entries/flags는 같다. `before`라는 source snapshot은 첫 payload 설치 전 수집했다. 최초 CLI license 관측은 그 전에 실행했다. 이를 전체 session 시작 전 snapshot이라고 부르지 않는다. CLI·GUI의 먼저 완료한171파일도 bytes/modes가 같다. 감사 helper의 `git status` 뒤 소유 source의 raw index bytes가 바뀌었다. raw index 불변은 입증하지 않는다. 첫 audit의 unversioned JSON은 두 번째 audit가 덮어썼다. 첫 tool output은 대화 기록에 남아 있다. 별도 correction이 이 한계를 기록한다. 이후 source 감사 Git 명령은 `GIT_OPTIONAL_LOCKS=0`을 사용한다. 원본 SDK/cache의 전체 bytes와 전체 HOME 불변도 입증하지 않는다. Foundation ephemeral T, 전용 preference, 소유 번들의 정상 LaunchServices 등록은 별도 OS 운영 범위다.

## 공개 사본 규칙

이 디렉터리는 사용자 이름, 호스트 경로를 별칭으로 바꾼 핵심 발췌다. 전체 raw log와 원본 command/env/helper는 소유 private prefix에 보존했다. 공개 helper와 공개 command는 원본 byte가 같다고 주장하지 않는다. `private-receipts.json`의 SHA는 private 원본을 가리킨다. `checksums.json`의 SHA는 현재 공개 사본을 가리킨다. `/OWNED_ROOT`, `/USER_HOME`, `/JDK17_HOME`, `/ORIGINAL_SDK`, `/ORIGINAL_GRADLE_CACHE`, `/WORKTREE`, `/EPHEMERAL_T`와 `VALIDATION_USER`는 실제 경로·사용자 값이 아니다. helper를 실행하려면 작업 소유 입력으로 별칭을 바꿔야 한다. lease의 해시 파일명과 plan ID는 실제 관측값이다. 비식별 경로 문자열에서 이를 재계산한 값은 아니다.

소유 guard는 소유 root, 정확 `.lock` literal, Foundation ephemeral T와 `/dev/null`, `/dev/tty`만 허용했다. HOME 전체 쓰기 예외를 넣지 않았다. GUI OS 서비스가 처리하는 preference는 process file-write guard만으로 보호된다고 주장하지 않는다.

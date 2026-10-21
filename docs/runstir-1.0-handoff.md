# Runstir 1.0 개발·테스트 인계 — 2026-10-21

사용자가 Codex 작업을 여기까지 정리하고 Claude로 이어가도록 요청했다. 새 기능과 실제 기기 검증은 시작하지 않고 진행 중이던 검사를 마감했다. 이 문서는 시점별 인계 기록이며, 티켓의 수용 기준을 대체하지 않는다.

## 정본과 순서

- 제품 목적은 앱 개발자가 `git clone → mobile up`으로 환경을 준비하고 앱을 실행하도록 돕는 오픈소스다. 팀 서비스·계정·유료 가입을 개발의 전제로 추가하지 않는다.
- [명세: Runstir CLI·GUI 공동 1.0.0](https://github.com/minjunkim-dev/mobile-runtime/issues/199)의 수용 기준 19개와 승인된 선행 관계를 유지한다. 기존 티켓을 재사용한다.
- 기존 [Wayfinder: Runstir GUI와 개발 편의 기능의 후속 확장](https://github.com/minjunkim-dev/mobile-runtime/issues/186)이 결정 지도다. 계획의 fog와 이미 정한 계약을 구분하며 새 지도를 만들지 않는다.
- 개발·baseline·실제 기능 검증 → unsigned 공동 후보 고정 → 실제 기능 게이트 → 최종 서명·공증 후보 → 배포 파일 검증 → 동일 후보 판정 → 공동 공개 순서다. [후보 제작](https://github.com/minjunkim-dev/mobile-runtime/issues/222)과 [후보 제작 PR](https://github.com/minjunkim-dev/mobile-runtime/pull/284)은 마지막 단계까지 보류한다. Developer ID·공증 profile 준비 요청도 재개하지 않는다. 원래 iOS 실기기 검증에 필요한 개발 서명 입력은 별개다.
- 실제 검증은 fixture·소스 리뷰·CI로 대신하지 않는다. broad 변경은 필요한 실제 검증과 최종 head의 독립 리뷰·필수 CI를 마친 뒤 그 head의 사람 승인을 받고 병합한다. 병합 후 main CI를 따로 확인한다.

## 인계 시점의 코드

기준 main은 `65e14c4e32dda320f2fda7fb0c5156eee437139e`다. 그 커밋의 [push CI](https://github.com/minjunkim-dev/mobile-runtime/actions/runs/39349394670)와 [push CodeQL](https://github.com/minjunkim-dev/mobile-runtime/actions/runs/39349394689)은 성공했다. 아래 개발 PR은 모두 Draft·OPEN이며 main에 병합하지 않았다.

| 기존 작업 | 최종 개발 head | 완료한 근거 | 다음 실제 검증 |
| --- | --- | --- | --- |
| [Flutter Android 확인·빌드·실행·종료](https://github.com/minjunkim-dev/mobile-runtime/issues/209) · [구현 PR](https://github.com/minjunkim-dev/mobile-runtime/pull/309) | `94ce5e6c221e97e03e80c1821b07c1938678562c` | native Werror 전체 963 tests/102 suites, 독립 Standards·Spec·Security 잔여 P0/P1/P2=0, [필수 CI 5개](https://github.com/minjunkim-dev/mobile-runtime/actions/runs/39605624095), [CodeQL 분석 4개](https://github.com/minjunkim-dev/mobile-runtime/actions/runs/39605623804), 아래 실제 Build06 | 현재 제품 코드의 Up·Down·첫 화면·GUI와 나머지 수용 기준 |
| [프로젝트·워크트리별 창과 독립 실행 자원](https://github.com/minjunkim-dev/mobile-runtime/issues/217) · [구현 PR](https://github.com/minjunkim-dev/mobile-runtime/pull/308) | `6fff7e38766129336a942cf7f67fca1554f6ee0b` | 별도 3종 소스 리뷰, [CI](https://github.com/minjunkim-dev/mobile-runtime/actions/runs/39356974220)·[CodeQL](https://github.com/minjunkim-dev/mobile-runtime/actions/runs/39356974173), 현재 GUI의 일반 폴더/별칭 재사용·실제 두 worktree 창/포트 입력 유지·정상 종료 | 현재 head의 RN 병렬 CLI·GUI 실행과 자원 충돌. 과거 `9fcc` 실측을 현재 head 완료로 승계하지 않는다. 로컬 full 실패 5건과 후속 1건의 원인은 UNKNOWN이다. |
| [Simulator .app·Emulator APK 직접 설치·실행](https://github.com/minjunkim-dev/mobile-runtime/issues/218) · [구현 PR](https://github.com/minjunkim-dev/mobile-runtime/pull/310) | `a49e33cf708c9d3df022c1a2e1eceba3f01e7b12` | [CI](https://github.com/minjunkim-dev/mobile-runtime/actions/runs/39435137794)·[CodeQL](https://github.com/minjunkim-dev/mobile-runtime/actions/runs/39435137893), 기존 iOS·Android 정상 설치/첫 화면/표본 보존과 Android 실패·취소·연결 해제·파일 변경·같은 store 충돌 | iOS 진행 중 연결 해제와 iOS 파일 작업 대 프로젝트 작업의 같은 store 실제 충돌. 기존 iOS 정상·취소·파일 변경 증거는 재사용한다. 모든 부정 사례를 CLI·GUI 각각 반복하는 조건은 추가하지 않는다. |

이 세 PR에는 최종 head의 사람 병합 승인이 없다. 로컬 full 실패 원인과 실제 수용 기준 미완료를 그대로 남긴다. 이번 인계 문서가 main에 들어가도 개발 PR들의 base 변경 영향은 재개 시 확인해야 한다.

## Flutter Android Build06

실제 제한 profile의 중첩 sandbox가 `sandbox_apply: Operation not permitted`·exit71로 실패했다. Runstir owner가 Gradle와 Dart를 각각 한 번만 sandbox에서 시작하도록 수정했다. private Unix socket에 UID·실행별 인증을 적용하고, owner가 실행 파일·snapshot·cwd·환경·정책을 고정한다. stdout/stderr bytes·종료 상태를 전달한다. 취소한 SDK task가 종료될 때까지 기다린 뒤 lease를 해제한다. 별도 배포 helper나 전역 설정을 추가하지 않았다.

- 실제 후보 source: `abe71f51f28722ac708f0c213f115fc8738e8d4e`. 최종 `94ce5e6`과 차이는 `Tests/CoreTests/ProcessRunnerTests.swift` 하나뿐이다. 제품 코드는 같다.
- `94ce5e6`은 CI에서 실패한 테스트의 임의 3초 polling을 실제 callback 이벤트 대기로 바꿨다. 기존 file gate·정확한 bytes·종료 전 전달·exit7·tail·5초 명령 timeout은 유지했다. 이전 실패 이력은 지우지 않는다.
- CLI: 12,430,008B, SHA-256 `414b537a94a2e47e7f3d622aeafa01610a2e9020caca27a7f0e9247bc83b30fb`.
- GUI: 11,155,880B, SHA-256 `265bab4f5e517c0e24a3d0b7f5b5ae243c6677abb39026e16d745c8ea9c4ae19`.
- 실제 `mobile build --platform android --module :app --variant debug --entrypoint lib/main.dart`의 원 wait는 **0**, 783.237906초다. workflow `2e1dc6b84d8c4c6aa6b7d7cfab578d33`, operation `2A5A8270-0618-4A10-8F48-CEFFFF034876`, 시작/종료 UTC `13:00:09.695319`/`13:13:12.936924`.
- 공통 JSON은 `pass`, `validate` 167799ms·`android.build` 204422ms, 앱 ID `dev.runstir.runstir_flutter_minimal`이다. 원본 추적 67개 파일의 내용·크기는 전후 일치했다. 전체 HOME/cache 보존이나 APK 독립 검사를 뜻하지 않는다.
- `RUSAGE_CHILDREN.ru_maxrss` 1,772,896,256B는 해당 관측 범위의 값이다. 전체 호스트·SDK의 peak 상한으로 사용하지 않는다.
- 새 후보의 Up·Down·첫 화면·GUI는 아직 실행하지 않았다. 이 성공으로 해당 조건을 체크하지 않는다.

## 로컬 재개 위치와 원시 근거

소스 worktree는 `/Volumes/P41_USB4/Developer/worktrees/codex/goal209-main65-integration/MobileEnvironment`, 로컬 branch는 `codex/209-main65-integration`, 원격 PR branch는 `codex/goal209-flutter-android`다. 인계 시 clean이며 HEAD는 위 `94ce5e6`이다. 다른 작업의 worktree와 원본 checkout을 덮어쓰지 않는다.

- 현재 상태 정본: `/Users/swifty/Documents/Codex/2026-10-19/runstir-199-resequence-apply/CURRENT-ACTUAL-STATUS.md`.
- Build05 실패·profile 대조·Build06 성공과 원 로그: `/Users/swifty/Documents/Codex/2026-10-20/goal209-647b-android-actual-01/RESULT.md`, `mobile-build-06-controller.log`, `sibling-native-full-suite.log`.
- host 후보: `/Volumes/P41_USB4/Developer/validation/goal209-runtime-20261020/sourceabe71f5-release-candidate-01`.
- 원본 입력 기준: `/Volumes/P41_USB4/Developer/validation/goal209-runtime-20261020/actual-sdk-plan-01/READ-ONLY-INPUTS.json`. 오래된 inventory 전체를 현재 상태의 증명으로 사용하지 않는다.
- guest 작업 root: `/Users/admin/runstir-209-647b-android-20261021`. 후보는 `candidate-abe71f5-release`, 원 stdout/stderr는 `output/mobile-build-06.stdout`·`.stderr`에 보존했다. 고정 실행 환경은 host controller 로그와 실제 검증 폴더에서 확인한다. 실행 시 전역 HOME·SDK·PATH를 바꾸지 않는다.
- 창 검증: `/Users/swifty/Documents/Codex/2026-10-20/goal217-6fff-background-actual-01`.
- 직접 설치 결과: `/Users/swifty/Documents/Codex/2026-10-20/goal218-a49-ios-stale-approval-01/RESULT.md`. 기존 독립 실제 감사는 `goal218-a49-gui-actual-audit-01/REPORT.md`와 `goal218-a49-postgui-readonly-actual-audit-01/REPORT.md`다. 두 감사 폴더는 같은 날짜 root 아래에 있다.

`TART_HOME=/Volumes/P41_USB4/Tart`, `TART_NO_AUTO_PRUNE=1`을 유지한다. 소유 Android VM `runstir-goal218-android-clean-20261021`은 정상 guest shutdown을 요청했고, 원 Tart 실행 workflow `63f337fce5ef4f1c83366b729da66b91`의 wait **0**과 inventory **stopped**를 확인했다. 강제 종료는 하지 않았다. 해당 Tart root의 VM 15개는 모두 stopped다. VM 파일과 기존 입력은 보존한다. 과거 SSD 단절 구간의 프로세스 종료 코드 UNKNOWN은 이 정상 종료로 덮지 않는다.

호스트의 focus·TCC·서명 설정은 변경하지 않았다. 향후 GUI도 사용자의 메인 포커스를 가져오지 않는다. 기존 helper는 오래된 PID·source·허가 파일에 고정돼 있으므로 그대로 재사용하지 않는다. 이번 VM에서는 guest IP의 TCP5900 RFB banner와 guest emulator 가속 검사 exit0만 확인했다. Emulator boot·GUI 동작의 증거는 아니다. 지정 SDK의 `system-images/*/*/*/package.xml` 표본은 비어 있었고 `cmdline-tools/latest/bin/avdmanager`는 없었다. versioned 경로까지 확인한 것은 아니다.

## Claude에서 이어갈 순서

1. 이 문서와 현재 상태 정본, 해당 티켓·PR을 읽고 `origin/main`·PR head·필수 CI를 다시 조회한다. worktree의 기존 변경과 실행 중인 프로세스 소유권을 먼저 확인한다.
2. Flutter Android의 실제 Up·Down·첫 화면·GUI가 다음 검증 경계다. Build06과 기존 정상 근거는 재사용한다. 부팅/이미지/AVD가 필요하면 기존 입력을 조사한 뒤 소유 사본에서 준비한다. 기존 호스트 SDK나 VM 원본을 바꾸지 않는다.
3. 독립 자원을 사용할 수 있으면 기존 창/병렬 실행과 직접 설치의 남은 경계를 병렬로 진행한다. 같은 기기·SDK 쓰기·iOS runtime 설치와 실제 iOS 실행·같은 파일 소유권은 겹치지 않는다.
4. [RN baseline](https://github.com/minjunkim-dev/mobile-runtime/issues/212)은 기존 [부분 증거 PR](https://github.com/minjunkim-dev/mobile-runtime/pull/236)과 MinimalRN·Mattermost 입력을 유지한다. 서로 다른 실제 RN baseline 요구를 같은 Minimal 앱의 두 복사본으로 대체하지 않는다.
5. 이후 기존 iOS 실기기 직접 설치·IPA·GUI 취소/접근성 티켓과 공동 후보 게이트를 native 선행 관계대로 이어간다. 서명·공증·실제 배포는 여전히 마지막이다.
6. 변경이 생긴 PR은 최종 head의 영향 검증·독립 리뷰·필수 CI를 갱신한다. broad 변경의 정확한 head 승인과 main CI 성공까지 구분해 기록한다. 완전한 수용 기준 충족 전 티켓을 닫지 않는다.

임시 검사기가 폴더 nlink·runtime lastUsage·공식 데이터 경로 이동·JSON 숫자 표현 차이를 손상으로 오판한 이력이 있다. 정상 메타데이터 변화는 실패로 만들지 않는다. 공식 경로에서 관련 데이터 bytes를 확인하고, 제품 실패·수집기 실패·UNKNOWN을 구분한다. 새 임시 스크립트 사본·해시 목록·내부 실행 허가 파일을 반복 생성하지 않는다.

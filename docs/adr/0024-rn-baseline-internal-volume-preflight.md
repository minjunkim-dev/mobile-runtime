---
status: accepted
---

# ADR-0024: RN baseline을 내장 경로에서 독립 준비하고 Metro를 먼저 확인한다

사용자는 2026-10-11에 새 범위와 실행 조건을 확정했다. 정책을 main에 반영하고 helper를 독립 검토한다. 새 단독 lease 뒤에만 실제 실행을 재개한다. [ADR-0023](0023-mattermost-exporouter-app-floor-preparation.md)의 attempt-08 실패와 원본 packet을 보존한다.

## 확인한 실패

attempt-08은 원본 Mattermost `c2fe3beda22befd2178dce431793c09111ed903e`에서 frozen Pods와 source 감사를 통과했다. 생성 resource bundle 11개 Debug `16.4`와 ExpoRouter Debug `16.0`의 정확한 12개 값을 준비했다. 실제 iOS native build와 install은 성공했다. 실제 ExpoRouter와 Mattermost Swift compiler target은 모두 `arm64-apple-ios16.0-simulator`다.

원본 Metro는 외장 검증 clone을 여는 Watchman 오류 `Operation not permitted`로 exit `1`이었다. 기존 Watchman daemon의 저장된 로그에서도 같은 clone의 `watch-project` 요청이 두 번 실패했다. 원본 `.watchmanconfig`는 이미 존재하며 내용은 `{}`다. daemon과 clone의 UID는 같다. 조사한 clone과 직전 부모 폴더의 POSIX mode는 `0755`다. 이것만으로 전체 접근 권한을 증명하지 않는다.

macOS의 Files and folders 보호에는 removable volume이 포함된다. [Apple의 접근 제어 문서](https://support.apple.com/en-euro/guide/security/secddd1d86a6/web)가 이를 설명한다. 이번 실패가 TCC, ACL, daemon 실행 문맥 또는 다른 원인 때문인지는 확인하지 않았다. 외장 경로가 단독 원인이라고 단정하지 않는다. [Watchman troubleshooting](https://facebook.github.io/watchman/docs/troubleshooting)의 일반 복구 안내도 이 실패 원인을 확정하지 않는다.

Metro 실패를 확인한 뒤 launch를 호출한 순서 오류도 있었다. launch 요청은 exit `0`이었다. 뒤의 terminate는 exit `3`이며 `found nothing to terminate`였다. 앱 생존과 첫 화면을 확인하지 못했다. 앱 종료 원인을 Metro 오류로 단정하지 않는다. status curl 호출은 도구 hook에 redirect되어 실제 runner receipt가 없었다. status 성공으로 판정하지 않는다.

후속 첫 화면·Android·Mattermost fresh·최소 RN fresh 준비를 중단했다. source와 generated project 사후 감사가 통과했다. 우리 앱을 제거했다. 전용 Simulator를 종료했다. 기존 Simulator 2개와 GUI 및 비소유 Watchman daemon을 보존했다. 단독 lease를 반환했다.

## 결정

최소 RN과 Mattermost의 baseline 및 각각의 fresh clone을 같은 host의 **내장 Data volume에 있는 검증 경로**에서 독립 준비한다. 이전 외장 clone이나 준비 입력을 이동하거나 이어 쓰지 않는다. 실제 경로는 승인된 외부 PLAN에 고정한다. 시작 전에 canonical path와 filesystem device를 다시 측정한다. 외장 경로로 해석되는 symlink나 보호 위치인 Documents·Desktop·Downloads 아래 경로를 거부한다. 이 검사는 Watchman 접근 성공을 보장하지 않는다.

최소 RN source는 `b62e3a4d5e7cfc05d7d948a5a4e30f0cc6a82bb4`로 유지한다. 기존 세 lock과 표본별 선언 tuple도 유지한다. 기존 최소 Android 첫 화면은 외부 `no-watchman-config.cjs`의 `resolver.useWatchman=false` 조건에서 확인했다. attempt-02 iOS Metro의 정확한 argv와 watcher 조건은 저장 증거로 확정하지 못했다. 기존 attempt-02 성공은 과거 조건의 증거다. 새 내장 경로와 원본 Metro 조건의 성공으로 승계하지 않는다. 최소 RN도 원본 Metro로 새 baseline의 양플랫폼 첫 화면을 확인한다.

원본 source, 표본별 선언 버전, tool·SDK·runtime·기기 tuple을 유지한다. Mattermost에만 [ADR-0020](0020-rn-baseline-prepared-input.md)의 clone별 Hermes 한 값과 [ADR-0021](0021-mattermost-generated-pods-preparation.md)·ADR-0023의 mixed 12개 Debug 준비 조건을 유지한다. 최소 RN에는 Mattermost 예외를 적용하지 않는다. source와 dependency graph 및 Metro config·argv·환경 flag를 바꾸지 않는다. Watchman을 끄거나 다른 버전으로 바꾸지 않는다. global daemon·watch state·TCC·ACL·POSIX 권한·전역 도구 선택을 변경하지 않는다. 다른 작업의 자원도 보존한다.

각 표본의 원본 npm와 hook 및 source 감사 뒤 **원본 Metro의 짧은 readiness 확인을 frozen Pods와 native build보다 먼저 수행**한다. 원본 Metro 명령은 유지한다. 독립 readiness 확인은 앱 실행이 아니며 baseline 완료 증거도 아니다. 우리 Metro만 종료한 뒤 같은 clone의 frozen Bundle·Pods와 native 검증을 진행한다. Mattermost에만 정확한 12개 값 준비를 적용한다. actual install·launch 직전에 원본 Metro를 다시 시작하고 readiness를 다시 확인한다.

readiness 확인은 실제 process와 오류 로그 및 자신의 port 소유권과 실제 HTTP status response를 확인한다. status 확인 command·result·body/hash를 원본 receipt로 기록한다. source와 argv를 바꾸지 않는 관측 helper만 사용한다. 관측 실행이 hook에 redirect되거나 receipt가 없으면 `unknown`으로 중단한다. banner나 launch 요청 exit `0`만으로 성공을 판정하지 않는다. readiness 통과도 JS bundle 제공과 앱 첫 화면을 증명하지 않는다.

Metro 시작·실패 확인·readiness·install·launch를 종속 순서로 실행한다. 이 작업을 병렬 batch에 묶지 않는다. Metro process가 종료되거나 필수 오류가 있으면 launch를 호출하지 않는다. launch 직전 process 상태를 다시 확인한다. 새 외부 helper/계획의 메모리 검사에서 captured Metro 실패·상태 응답 부재·다른 port owner·중간 process 종료가 후속 launch를 차단하는지 확인한다. 실제 실패와 관측 도구 실패를 구분한다. 원본 attempt-08 순서 오류를 수정한 이력으로 덮어쓰지 않는다.

## 새 실행 조건

1. 확정한 경로·순서·감사·중단 조건을 정책과 외부 PLAN에 고정한다. 정책을 main에 반영한다. 외부 helper와 PLAN을 독립 검토한다. 새 단독 lease 뒤에만 실행한다.
2. 실제 내장 경로와 남은 공간을 측정한다. 같은 volume의 시작 여유 공간은 최소 `20 GiB`다. 설치와 build 및 fresh 준비 직전에 최소 `10 GiB`를 다시 확인한다. attempt-08에서 측정한 node_modules `1.163 GiB`, vendor `0.023 GiB`, Pods `0.830 GiB`, derived data `6.494 GiB`는 과거 사용량이다. 새 사용량 보장은 아니다. 기준 미달이면 정리하거나 경로를 바꾸지 않고 중단한다.
3. 각 표본의 새 clone에서 원본 source와 npm/hook을 감사한다. 원본 Metro의 초기 readiness를 확인한다. 실패하면 모든 후속 실행을 중단한다. 성공이면 우리 Metro만 종료한다. 같은 clone의 frozen Bundle·Pods를 준비한다. Mattermost에만 clone별 실제 spec과 lock의 Hermes 한 값을 독립 연결한다. 마지막 frozen 성공 뒤 mixed 12개 값과 source·전체 raw/object 역치환·모든 owner·scoped xcconfig를 감사한다. 최소 RN의 lock과 source는 원본 그대로 감사한다.
4. 자원 현재 상태를 다시 확인한다. 최소 RN과 Mattermost 각각의 새 baseline에서 원본 iOS build·install·launch·첫 화면과 Android build·install·launch·첫 화면을 직렬 검증한다. 종속 실행 guard와 source·generated 사후 감사를 적용한다. 두 표본의 양플랫폼 필수 성공 뒤 각각의 fresh clone을 원본 명령으로 독립 준비한다. 준비 산출물 복사를 금지한다. 검증한 공식 raw archive만 ADR-0020의 origin/hash/use 조건으로 재사용한다.
5. 추가 필수 실패·허용 밖 차이·관측 `unknown`이면 모든 후속 실제 실행을 중단한다. 우리 소유 자원만 정리한다. 실패 기록과 최초 receipt 및 이전 packet을 보존한다. 다른 경로·권한·source·target·flag·도구 조건을 바꾸려면 별도 결정과 새 실행이 필요하다.

## 판정과 경계

이 경로는 외장 접근 차이를 한 변수로 줄여 확인하는 새 조건이다. 해결을 보장하지 않는다. 준비 입력의 baseline 결과만 판정한다. iOS native build와 install 성공은 앱 첫 화면 성공이 아니다. #212는 최소 RN과 실제 OSS 각각의 양플랫폼 첫 화면 및 독립 fresh 인계가 모두 있어야 완료한다.

실제 Runstir의 npm/Pods 재생성이 수동 보정을 유지하는지는 미확정이다. 실제 Runstir CLI·GUI와 공동 여섯 조합 및 출시 gate는 후속 검증이다. 기존 native 성공을 새 경로의 성공으로 승계하지 않는다.

Watchman 접근 권한 준비를 검토하는 대안도 있다. 이번 결정은 비소유 daemon과 global 권한을 변경하지 않고 새 독립 검증 경로와 실행 순서만 정한다. 정책의 main 반영과 helper 독립 검토 및 새 단독 lease 전에는 새 Metro 또는 clone·의존성·native·기기 실행을 시작하지 않는다.

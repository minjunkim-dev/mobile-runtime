# #212 attempt-20 — Ruby 준비 전 mise identity guard의 필수 STOP

검증일: 2026-10-12, Asia/Seoul. 상태: **부분 검증. 원본 identity guard의 필수 STOP.**

[요약](./rn-baseline-212.md)과 [공개 manifest](./evidence/212/attempt-20/manifest.json)를 함께 읽는다.
현재 정책은 [ADR-0031](https://github.com/minjunkim-dev/mobile-runtime/blob/8fd534d5c9cd61dd9d02fd7dc939cefea43d5d5c/docs/adr/0031-rn-observer-loop-lifecycle-diagnostics.md)이다.
정책 main은 `8fd534d5c9cd61dd9d02fd7dc939cefea43d5d5c`다.
[PR251](https://github.com/minjunkim-dev/mobile-runtime/pull/251) reviewed head는 `10b839fb352e59d88e4ebe46d2c9143f7f8405cf`다.
[CI38144494118](https://github.com/minjunkim-dev/mobile-runtime/actions/runs/38144494118) 네 job은 terminal SUCCESS다.
ADR-0031은 기존 error record의 diagnostic field 세 개만 추가한다.
원본 query·poll·clock·order·sleep·FFI·errno·판정과 필수 STOP을 유지한다.

최소 source는 `b62e3a4d5e7cfc05d7d948a5a4e30f0cc6a82bb4`다.
Mattermost 선언 입력은 `c2fe3beda22befd2178dce431793c09111ed903e`다.
새 최소 source를 내장 독립 경로에 clone했다. Mattermost clone은 시작하지 않았다.
과거 node_modules·vendor·Pods·build를 복사하지 않았다.
minimum에는 Mattermost checksum·생성 target 예외를 적용하지 않았다.
원본 source·version·plugin·argv·env·query·sampling·delay·guard를 바꾸지 않았다.

1. 봉인 firstcaller의 tuple unpack과 원본 path/공간 guard를 통과했다.
2. 당시 resource guard를 통과했다. 최소 clone·checkout·원본 npm runner3개는 exit0/guardPASS였다.
3. strict55/세 lock을 통과했다. 호출 전에 resolved interpreter·exact absolute E20 audit argv·caller cwd를 기록했다.
4. 원본 early Metro의 실제 HTTP200/body와 소유 process·port readiness를 통과했다.
5. 소유 Metro를 Ruby 준비 전에 종료했다.
6. Ruby 준비 context 전 compound identity assertion이 실패했다. frozen 준비 outer helper는 exit1이었다.
7. 모든 후속 실제 실행을 중단했다. 원본 source 사후 strict 감사를 수행했다.
8. 소유 자원이 남지 않았음을 확인했다. 추가 cleanup command는0개였다. 권한을 반환했다.

## 최초 실패와 관측 경계

원본 assertion은 선택 mise 파일의 존재·nonsymlink·digest equality를 한 식에서 검사한다.
후속 읽기 facts는 regular file·nonsymlink와 canonical 경로 일치를 확인했다.
후속 읽기 facts는 당시 기대 hash와 실제 hash가 달랐음을 확인했다.
이는 정확한 실패 operand를 같은 순간에 원자적으로 관측한 증거가 아니다.
변경 actor/time/how/version은 UNKNOWN이다.
`ORIGINAL_MISE_IDENTITY_DIGEST_MISMATCH`는 작성자가 분류한 파생 고정 진단이다.
원본 exception 본문이 아니다. 공개 자료에는 원본 예외·argv·env 본문을 넣지 않는다.
helper exit1과 원본 Ruby command 미시작을 구분한다.
mise/Ruby probe·공식 gem 다운로드·installer·activation·frozen Bundle·Pods는 시작하지 않았다.
observer에도 도달하지 않았다. actual Ruby receipt·관측·context는 모두0개다.
ADR-0031의 실제 세 diagnostic field와 errno는 NOT_MEASURED다.
새 tool identity를 자동 채택하거나 복구·설치·실행하지 않았다.

| 당시 읽기 사실 | 값 |
| --- | --- |
| 기대 mise SHA-256 | `d225d1c8ef2934a86be93692a19365fb1df1cd6958a0af7b85909514e0c608a7` |
| 실제 mise SHA-256 | `f5171e341518a57e8c4e9280e28443e35d66212c51164c83be76794e0a78b014` |
| 실제 byte | 127277984 |
| 실제 file kind | regular, nonsymlink |
| canonical 경로 | 동일 |
| 실제 version command 출력 | 미측정 |
| 변경 actor/time/how | UNKNOWN |

## 별도 공식 출처 조사

root의 별도 읽기 조사는 당시 실제 hash와 byte 크기가 공식 jdx/mise의 `v2026.10.7` macos-arm64 raw asset과 같음을 확인했다.
근거는 [공식 release](https://github.com/jdx/mise/releases/tag/v2026.10.7)와 [공식 release API](https://api.github.com/repos/jdx/mise/releases/tags/v2026.10.7)다.
이 조사는 실행·다운로드·설치를 하지 않았다.
이는 asset byte의 출처 대응이다. 실제 version command 출력이나 runtime 효과의 증거가 아니다.
이 조사는 변경 actor/time/how를 확인하지 않는다.
이 조사는 새 identity 채택이나 재실행 권한을 부여하지 않는다.
원본 raw firstseal100개는 이 후속 조사로 수정하지 않았다.

## 수치와 감사

원본 run_step command3개는 ordinary/exit0/guardPASS다.
Metro start/observe/stop과 path/resource guard는 이3개와 별개다.
Ruby receipt0개, actual observations0개, Ruby context0개다.
source-only memory2863개는 기존2674개와 lifecycle189개다. syntax33개는 PASS다.
helper map46/index47/source-only inventory48을 봉인했다.
PLAN의 과거 E18 alias 두 개는 E20 identity로만 정정했다.
초기 PLAN/batch/index 세 파일을 별도 보존했다. 다른45개 바이트와 production code는 불변이다.
source-only 검사는 실제 baseline 성공이나 세 diagnostic field의 actual 검증이 아니다.

사후 strict55/세 lock과 raw/index/flags/kind/Git mode 감사는 PASS다.
source 변경은0개다. 원본 lock hash는 공개 manifest에 연결한다.
shared/host/metadata 초기 snapshot은 NOT_STARTED다.
그 사후 불변 PASS나 일시 write 부재를 주장하지 않는다.
installer·activation·Bundle·plain/deployment Pod·native·기기·install·launch·첫 화면·Android·Mattermost·두 fresh는 미시작이다.
두 baseline의 네 첫 화면과 각 fresh 인계는 미완료다.
PNG·APK·앱 ZIP는0개다.

## 자원 상태와 권한 반환

소유 Metro를 Ruby 준비 전에 종료했다.
추가 소유 cleanup command는0개다. 기기 boot·앱 설치·adb reverse·native 실행은0개다.
worker의 마지막 resource PASS는 외장 evidence 볼륨 부재 전 snapshot이다.
이를 현재 root resource 증거로 승계하지 않는다.
이후 외장 볼륨이 접근 불가 상태가 됐다.
최초 root 응답에는 parse:false만 남았다. 최초 resource 시도의 실행 command count는 NOT_CONFIRMED다.
별도 후속 explicit cwd ENOENT와 볼륨 부재 확인을 구분한다.
확인된 후속 spawn 거부는 원본 command 실패가 아니다.
root는 행정상 실제 권한을 취소했다.
볼륨 복구 뒤 별도 qualified canonical release를 기록했다.
원본 grant와 반환 전 cleanup의 rootReleaseConfirmed=false는 당시 상태로 유지한다.
현재 lease는 RELEASED다. 실제 owner는 없다. E20 grant를 재사용하지 않는다.

복구 후 root의 read-only4개 명령은 Simulator·dedicated·Watchman·Metro·native predicate가 true였다.
historical GUI와 ADB predicate는 false였다.
기존 ADB server를 증명하지 못해 adb devices를 호출하지 않았다.
현재 전체 resource preservation PASS를 주장하지 않는다.
외부 변경 actor/time을 추론하지 않는다.
권한 취소는 현재 자원 predicate 통과와 별개다.

원본 resource helper 완료 뒤 undefined sessionId store 오류를 별도 진단으로 보존했다.
원본 helper writer 실패나 실제 command 재실행이 아니다.
후속 index 빈 행과 읽기 집계 변수 오류도 별도로 보존했다.
읽기 분석 정정은 파일·helper·원본 command·입력 조건을 바꾸지 않았다.
source-only 최초 null/int fixture 정정도 실제 앱 실패와 구분한다.

## 원본 packet과 공개 검토

원본 recursive packet은100개다. index99개와 base evidence97개를 포함한다.
전체 크기는1616206B다. log14개와 recursive bytecode0개다.
공개 manifest는 원본100개 모두의 hash·byte 크기를 연결한다.
원본 raw hash와 비식별 공개 JSON hash는 다르다.
원본 absolute path·PID·session·argv·env·예외 본문은 공개하지 않는다.
이전 attempt12–19 봉인 whole1188/index1180과 core의 읽기 대조는 hash mismatch0이다.
이전 공개 이력도 보존한다.

| 원본 파일 | SHA-256 | byte |
| --- | --- | --- |
| REPORT.md | `66c5806ac1095ef3d350e10d86b1dd9677ac9961f3855d3df391da9e557dde21` | 6725 |
| manifest.json | `36bb3eaf768d08a5d09c1d9b8b62ec1e9d146f73b351f9329d947b5938e7e652` | 24838 |
| SHA256SUMS | `cadc0c1bdb8f4c8ab0040314adfc8ab92877516d5f41e64d29ff81c8c161e811` | 9519 |
| 최초 helper log | `3f126e37d20409fc0c9201f46aca5eec8d641024b9bc0761332b6375691a4e84` | 1647 |
| qualified root release | `6c0be7efca504a8fd9d7ba70b28c0593082ca31acdcbe08bfea350397f3073c1` | 3600 |

원본 packet은 두 독립 검토에서 material finding0을 확인했다.
공개 문서는 두 독립 검토에서 material finding0을 확인했다. publicationReady=true다.
새 공개 head·CI는 CI_PENDING이다.
다음은 원본 identity와 자원 증거를 유지한 읽기 조사와 공개 검토다.
새 actual 권한과 새 tool identity 채택은 승인하지 않았다.
실제 Runstir는 NOT_AUTHORIZED다.
#212/PR236은 OPEN으로 유지한다. 종료 참조를 추가하지 않는다.
PR236을 병합하지 않는다.

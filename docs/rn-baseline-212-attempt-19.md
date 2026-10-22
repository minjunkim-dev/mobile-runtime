# #212 attempt-19 — Bundle observer의 executable 반환 zero

검증일: 2026-10-11, Asia/Seoul. 상태: **부분 검증. observer guard의 필수 STOP.**

[요약](./rn-baseline-212.md)과 [공개 manifest](./evidence/212/attempt-19/manifest.json)를 함께 읽는다.
현재 정책은 [ADR-0030](https://github.com/minjunkim-dev/mobile-runtime/blob/6712c42f4927b972d712fb9ac4e507826a291cc6/docs/adr/0030-rn-pod-runtime-cwd-boundary.md)이다.
정책 main은 `6712c42f4927b972d712fb9ac4e507826a291cc6`다.
[PR250](https://github.com/minjunkim-dev/mobile-runtime/pull/250) reviewed head는 `f07cf4ec226ec2afa0a3279093887116824d7452`다.
[CI38138333654](https://github.com/minjunkim-dev/mobile-runtime/actions/runs/38138333654) 네 job은 terminal SUCCESS다.
사용자 범위 승인 origin은 PR249다. PR250은 stack instrumentation 의무가 없음을 명료화했다.
새 query·instrumentation·실행 조건을 추가하지 않았다.

최소 source는 `b62e3a4d5e7cfc05d7d948a5a4e30f0cc6a82bb4`다.
Mattermost 선언 입력은 `c2fe3beda22befd2178dce431793c09111ed903e`다.
최소 source를 새 내장 독립 clone했다. Mattermost clone은 시작하지 않았다.
과거 node_modules·vendor·Pods·build를 복사하지 않았다.
minimum에 Mattermost checksum·생성 target 예외를 적용하지 않았다.
원본 source·version·plugin·argv·env·query·loop·FFI·errno·sampling·delay·guard를 유지했다.

1. 봉인된 first caller의 tuple unpack 정정을 실행했다. 원본 path/공간 guard와 outer result 작성을 통과했다.
2. 최신 resource guard를 통과했다. 최소 clone·checkout·원본 npm runner3개가 exit0/guardPASS다.
3. strict55/세 lock을 통과했다. 원본 Metro 호출 전에 resolved interpreter·exact absolute audit argv·caller cwd를 기록했다.
4. 원본 early Metro의 실제 HTTP200/body와 own process·port readiness를 통과했다. 소유 Metro를 Ruby 전에 종료했다.
5. 원본 mise 선택·Ruby facts·공식 gem spec·clone-local Bundler installer·activation·frozen 선택·selected-environment probe를 통과했다.
6. 원본 frozen Bundle install이 exit0을 기록했다. observer guard가 false를 기록했다. frozen outer helper가 exit1을 기록했다.
7. 모든 후속 실제 실행을 중단했다. 시작한 context의 사후 감사만 수행했다.
8. 소유 실행 자원이 남아 있지 않음을 확인했다. 초기 grant를 유지하고 별도 root release를 받았다.

원본 frozen Bundle install은 exit0이다. observer530관측과 읽기오류1개로 준비 guard는 false다. 고정 stage는 executable-launcher-image-zero다. errorCode는 EXECUTABLE_RETURN_ZERO다. 실패 errno enum은 ESRCH다. 정확한 동적 원인은 unknown이다.
이 값은 실패 분기의 실제 고정 진단이다.
ESRCH enum 관측을 종료 race·권한 문제·원인 해결로 단정하지 않는다.
원본 tool 성공과 관측 guard 실패를 별도로 보존했다.
원본 helper나 관측 판정을 완화하지 않았다.

| 원본 Ruby receipt | actualObservations | readOnlyObservationErrors |
| --- | --- | --- |
| Bundle install | 530 | 1 |
| Bundler installer | 18 | 0 |
| Bundler activation | 3 | 0 |
| raw gem spec | 8 | 0 |
| Ruby facts | 3 | 0 |
| 합계 | 562 | 1 |

원본 run_step command11개는 모두 exit0이다. guard는10PASS/1FAIL이다.
Metro start/observe/stop과 path/resource guard는 이11개와 별개다.
첫 Bundle result의 started→finished 파생 구간은28.370324초다.
이 구간은 관측과 사후 처리를 포함한다. 순수 tool 실행 시간으로 표현하지 않는다.
source-only memory2674개와 syntax32개는 PASS다.
helper map63개/index64개/source-only inventory65개를 봉인했다.
독립 helper 검토는 material finding0이다. 이는 실제 baseline 성공을 뜻하지 않는다.

gem-actual·Pod deployment·native·기기·install·launch·첫 화면·Android·Mattermost·두 fresh는 미시작이다. 새 Pod CWD 범위는 실제 검증하지 않았다. 같은 attempt에서 helper·argv·query·sampling·delay·조건을 바꾸거나 재실행하지 않았다.
원본 두 baseline의 네 첫 화면은 아직 충족하지 못했다.
새 Pod CWD metadata는 시작하지 않았다.
원본 source와 세 lock을 변경하지 않았다.
minimum의 새로운 checksum 재생성이나 생성 target 보정은 없다.

strict55/세 lock과 metadata·host·shared·private 사후 감사는 PASS다. source와 공유 변경은0개다. 소유 Metro는 Ruby 전에 종료했다. 추가 cleanup command는0개다. worker와 root의 마지막 resource 검사는 PASS다. 별도 root receipt가 lease RELEASED를 확정했다. 공유 snapshot 최종 equality는 일시 write 부재를 증명하지 않는다.
원본 plugin의 내부 reshim 횟수와 각 exit는 미측정이다.
Pod runtime PKG_CONFIG_PATH도 미측정이다.
기존 Simulator 두 개와 GUI·Watchman·비소유 process·AVD data를 보존했다.
새 최소 source root의 존재는 정상 준비 결과다.
prelease root 부재를 cleanup 요구로 승계하지 않는다.
cleanup의 rootReleaseConfirmed=false는 반환 전 상태다.
별도 root RELEASED receipt가 나중 상태를 연결한다. 초기 grant를 덮지 않았다.

읽기 filename 조회와 이전 list형 file map을 mapping으로 가정한 parser 오류를 별도 보존했다.
첫 count 조회에서 관측 list를 scalar처럼 출력한 작성자 실수도 기록했다.
이후 집계는 원본 actualObservations list의 길이를 직접 계산했다.
공개 자료에는 원본 관측·argv·env·예외 본문을 넣지 않는다.
이 읽기 진단 오류는 원본 tool 실패·source 변경·actual 재시도가 아니다.
최초 result/log/guard 판정을 유지했다.
index에는 마지막 blankline1개가 있다.
첫 읽기 validator는 blankline을 entry로 가정했다. blankline을 제외해 읽기만 정정했다.
index192개 hash 검증은 통과했다. 최초 봉인 바이트는 바꾸지 않았다.

원본 recursive packet은193개다. index는192개이고 base evidence는190개다.
전체 크기는55752069B다. log20개와 recursive bytecode10개를 포함했다.
PNG·APK·ZIP은0개다.
공개 manifest는 원본193개 모두의 hash·byte 크기를 연결한다.
원본 raw의 hash와 비식별 공개 JSON의 hash는 다르다.
원본 absolute path·PID·session·argv·env·예외 본문은 공개하지 않는다.
이전 attempt12–18 packet과 공개 이력을 보존했다. 이전 attempt12–18의 mapped 검증은992개다. 이 수치는 attempt12 base116개를 포함한다. 이전 전체 packet은995개이고 index는988개다. attempt12 전체는119개다.

| 원본 파일 | SHA-256 | byte |
| --- | --- | --- |
| REPORT.md | `1006ae795ee9fcedfd673beef1979fd5c054f9c59af861ee285722a70baca4d0` | 6706 |
| manifest.json | `7fc867699cb7a03b0a76b47864ce719efaf165eeeaf6e158418b4666c78bd733` | 43304 |
| SHA256SUMS | `db4485efb5f49b3900bf6d2ebf8c3d3ab73f8386867120b58ebf7ed8448b8e33` | 21100 |
| 첫 Bundle result | `87ad8ecd3c44b524dc9c2612cf0a959562f2b833625a6f3b3a46f70244ff56a8` | 1431600 |
| 원본 Bundle log | `32c2542b3c67d8b6864045a74e4706e0c8bc33efb34706f54b468df2e6e66a4c` | 3464 |
| root release receipt | `2be5e61ca61059d6349ff8e9a3b9724a88ea198fffb620a5d21961d482ced8c8` | 5057 |

원본 packet과 공개 문서는 각각 두 독립 검토에서 material finding0을 확인했다. publicationReady=true다. 새 공개 head·CI는 CI_PENDING이다.
다음은 원본 call-site와 ABI 및 저장된 관측의 읽기 조사다. 추가 attempt와 새 조건·guard 완화는 승인하지 않았다. 새 actual 권한은 없다. 실제 Runstir는 NOT_AUTHORIZED다.
#212/PR236은 OPEN으로 유지한다. 종료 참조를 추가하지 않는다.
PR236을 병합하지 않는다.


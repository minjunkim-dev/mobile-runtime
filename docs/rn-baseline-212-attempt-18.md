# #212 attempt-18 — caller tuple receipt 작성 오류

검증일: 2026-10-11, Asia/Seoul. 상태: **부분 검증. caller 구현 오류로 필수 STOP.**

[요약](./rn-baseline-212.md)과 [공개 manifest](./evidence/212/attempt-18/manifest.json)를 함께 읽는다.
현재 정책은 [ADR-0030](https://github.com/minjunkim-dev/mobile-runtime/blob/6712c42f4927b972d712fb9ac4e507826a291cc6/docs/adr/0030-rn-pod-runtime-cwd-boundary.md)이다.
정책 main은 `6712c42f4927b972d712fb9ac4e507826a291cc6`다.
[PR250](https://github.com/minjunkim-dev/mobile-runtime/pull/250)의 reviewed head는 `f07cf4ec226ec2afa0a3279093887116824d7452`다.
[CI38138333654](https://github.com/minjunkim-dev/mobile-runtime/actions/runs/38138333654) 네 job은 SUCCESS다.
사용자 범위 승인 origin은 PR249다. PR250은 stack instrumentation 의무가 없음을 명료화했다. 새 query나 실행 조건을 추가하지 않았다.

최소 입력 SHA는 `b62e3a4d5e7cfc05d7d948a5a4e30f0cc6a82bb4`다.
Mattermost 입력 SHA는 `c2fe3beda22befd2178dce431793c09111ed903e`다.
두 SHA는 선언 입력이다. 실제 clone·checkout은 시작하지 않았다.
원본 source·버전·plugin·argv·env·query·sampling·delay·순서와 기존 예외 범위를 유지했다.

1. require_lease가 현재 권한을 확인했다.
2. 원본 path/공간 guard가 exit0/PASS를 기록했다.
3. caller의 receipt writer가 tuple 반환을 mapping으로 읽었다. caller가 TypeError로 exit1을 기록했다.
4. 모든 후속 실제 실행을 중단했다. 같은 attempt의 helper·조건을 수정하거나 재실행하지 않았다.
5. 소유 실행 자원이 없음을 기록했다. 마지막 읽기 resource snapshot을 보존했다.
6. 원본 grant를 유지했다. 별도 root release receipt로 실제 권한을 반환했다.

원본 path/공간 guard는 exit0/PASS다. 이후 작성자 caller가 require_lease()의 tuple 반환을 mapping으로 읽어 receipt 작성 중 TypeError를 냈다. caller exit1과 원본 guard 결과를 구분한다. 같은 attempt에서 수정하거나 재실행하지 않았다.
이는 source·제품·Metro·Ruby·원본 tool 실패가 아니다.
고정 producer는 lease와 receipt digest의 tuple을 반환한다.
caller는 그 tuple을 mapping으로 읽었다. 진단은 첫 caller source와 producer 계약의 읽기 대조다.
원본 guard command와 순서는 바꾸지 않았다.

첫 outer result는 작성되지 않았다.
호출 전 interpreter·argv receipt도 저장되지 않았다.
요청 interpreter alias만 보존했다. 실제 resolved token의 최초 관측을 주장하지 않는다.
실패 뒤 복사한 caller source는 호출 전 receipt가 아니다.

새 source root는 부재다. clone·npm·Metro·Ruby·Bundler·Pods·native·설치·launch·첫 화면·Android·Mattermost·fresh는 모두 미시작이다. source/metadata/host/shared Ruby context 사후 감사도 미시작이다. errno와 새 Pod CWD 판정의 실제 효과는 미측정이다.
새 clone이 없으므로 strict55/세 lock의 실제 사후 PASS를 주장하지 않는다.
이전 source·lock·실패 증거를 새 실행 성공으로 승계하지 않는다.
source-only memory2656개와 syntax31개는 PASS다.
helper map60개/index61개/source-only inventory62개를 고정했다.
독립 helper 검토는 material finding0이다. 이는 실제 baseline 호환성을 입증하지 않는다.
exact6 Pod recipes와 네 clone 역할의 새 판정도 실제 실행하지 않았다.
기존 executable query와 errno 실패 enum은 이번 시도에서 관측하지 않았다.

소유 실행 자원과 cleanup command는 각각0개다. worker의 마지막 읽기 resource snapshot은 PASS다. root의 나중 snapshot은 비소유 native process2개를 보았다. 이를 보존했다. root의 나중 native-free/global-resource PASS를 주장하지 않는다. 별도 root receipt가 lease RELEASED를 확정했다.
worker snapshot과 root의 나중 snapshot은 시점이 다르다.
비소유 native process는 caller 오류의 원인으로 판정하지 않았다.
초기 Simulator 두 개와 기존 GUI·Watchman·AVD data를 보존했다.
공유 상태의 일시 write 부재를 주장하지 않는다.
새 lease에는 fresh native-free preflight가 필요하다.
cleanup의 반환 전 상태와 나중 root RELEASED receipt는 별도로 보존했다.

| 항목 | 수치 또는 상태 |
| --- | --- |
| 원본 helper subprocess | 2개, path guard와 마지막 읽기 resource guard 모두 exit0 |
| caller 최초 결과 | exit1, receipt writer TypeError |
| 앱 준비 run_step command / Ruby receipt / 관측 | 0 / 0 / 0 |
| 소유 자원 / cleanup command | 0 / 0 |
| recursive packet / index / base | 80 / 79 / 77 |
| 전체 packet byte | 734626 |
| log / bytecode | 3 / 0 |
| PNG / APK / ZIP | 0 / 0 / 0 |

공개 manifest는 원본80개 모두의 SHA-256과 byte 크기를 연결한다.
원본 raw의 hash와 비식별 공개 JSON의 hash는 다르다.
원본 경로·PID·session·argv·env·예외 본문은 공개하지 않는다.
이전 attempt12–17의 봉인 packet은 유지했다.

| 원본 파일 | SHA-256 | byte |
| --- | --- | --- |
| REPORT.md | `911c1ca38e084b2f70c3987ebe6ed9e0cb3cac6872041d6e079344110b096937` | 5056 |
| manifest.json | `b513687ead8f307b95d0bdb8238b76956cc104b9b6f90dd3a2e6bbf2edade793` | 18351 |
| SHA256SUMS | `506bebb833715f301efa64e60628c8360c67b7424ac71093634428c877a02b0f` | 7482 |
| root-release-message-receipt.json | `b7c80f310e4430279d13b8b18fe74a3e46cd86ff2be185dc090fbd8f5abff56f` | 4773 |

원본 packet과 공개 문서는 각각 두 독립 검토에서 material finding0을 확인했다. publicationReady=true다. 새 공개 head·CI는 CI_PENDING이다.
다음 attempt19는 같은 ADR-0030 조건을 유지한 caller tuple unpack 정정의 source-only 준비다. artifact ID는 미확정이다. 새 독립 검토와 fresh resource preflight 및 root lease를 받기 전 실제 실행은 금지한다. 입력 정책을 넓히지 않는다. 성공을 보장하지 않는다.
#212와 PR236은 OPEN으로 유지한다. 종료 참조를 추가하지 않는다.
실제 Runstir는 NOT_AUTHORIZED다. PR236 병합을 승인하지 않는다.


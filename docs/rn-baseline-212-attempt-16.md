# attempt-16: early Metro 호출자의 audit 경로 guard에서 중단

검증일: 2026-10-11, Asia/Seoul. 상태: **부분 검증. #212 미완료.**

[ADR-0029](https://github.com/minjunkim-dev/mobile-runtime/blob/ad301bbe77a5245fbc04ccd26a82e1c96616dddc/docs/adr/0029-rn-observer-executable-errno.md)는 기존 executable query 직전 errno0 초기화와 실패 직후 errno1회 읽기 및 고정 enum만 추가했다. 정책 main은 ad301bbe77a5245fbc04ccd26a82e1c96616dddc다. PR248 exact head a57a3573a426c000c9df8e30c89a4cc5db5612a7의 CI38129147071 네 job은 SUCCESS다. 두 helper 독립 검토는 material0이다. 메모리1,808개와 syntax28개는 실제 baseline 성공이 아니다.

| 단계 | 실제 결과 |
| --- | --- |
| 최소 b62 새 clone·checkout·원본 npm ci | runner3개 모두 exit0·guard3PASS |
| source·원본 lock | strict55개·세 lock·index·kind·Git 실행 mode PASS |
| early Metro helper | caller audit 경로 guard에서 exit1 |
| 원본 Metro·HTTP readiness | NOT_STARTED |
| Ruby·새 errno 실제 관측 | NOT_STARTED·Ruby receipt0개 |
| metadata·host·shared Ruby context와 사후 snapshot | NOT_STARTED |
| Bundler·Pods·native·기기·첫 화면·Android·Mattermost·두 fresh | NOT_STARTED |

호출자가 audit 인자에 상대 basename을 전달했다. subprocess cwd를 따로 지정하지 않았다. 따라서 제품 worktree cwd에서 경로를 해석했다. metro_guard.py:136의 audit parent 검증이 실패했다. 원본 Metro Popen 이전에 중단했다. 소유 Metro record와 Metro log는 없다. 이 실패는 source·제품·원본 Metro 실행 실패가 아니다. 같은 attempt에서 retry·helper·argv·조건을 바꾸지 않았다.

최초 outer log626B와 required-helper-failure.json을 보존했다. caller-invocation-diagnostic.json은 호출 위치와 인자 경계를 연결한다. 첫 child executable 절대 token을 최초 Popen event로 관측하지 않았다. 요청 alias python3와 sys.executable 표현을 구분한다. 사후 현재 interpreter 읽기를 최초 관측으로 승계하지 않는다. 실제 경로·PID·환경·argv 본문과 예외 원문은 공개하지 않는다.

strict 사후 감사는 tracked55개·원본 세 lock·index·kind·Git 실행 mode PASS다. 변경은0개다. minimum에 Mattermost checksum·target 예외를 적용하지 않았다. Ruby context와 metadata/host/shared snapshot은 시작하지 않았다. 해당 사후 snapshot PASS나 일시 shared write 부재를 주장하지 않는다. 이전 attempt15의 Ruby·metadata 성공을 승계하지 않는다. errno는 NOT_MEASURED다. 이전 query 오류의 원인은 이번 시도에서 조사하지 않았다.

소유한 Metro·기기·앱·reverse·Emulator·Gradle/native는 없다. 종료·삭제할 소유 실행 자원도 없다. 전용 iOS26은 Shutdown이다. 기존 두 Simulator·GUI·Watchman·비소유 Java와 AVD 데이터를 보존했다. 최종 resource 조회는 PASS다. 전역 선택·권한·daemon을 바꾸지 않았다. root는2026-10-11T10:07:58Z에 별도 receipt로 RELEASED를 확정했다. 초기 grant·readiness false·cleanup의 반환 전 상태·RETURN_REQUESTED를 보존했다. 현재 실제 권한은 없다.

root의 최초 preflight는 비소유 Java4개를 native로 분류했다. sealed native_rows 조건으로 읽기 분류를 정정했다. root release의 최초 filename lookup 진단도 별도로 보존했다. 두 이력은 source/tool 조건 변경이나 앱 실패가 아니다.

[공개 manifest](./evidence/212/attempt-16/manifest.json)는 원본 전체97개 파일의 hash와 size만 연결한다. base94개와 core3개다. index는 자기 파일을 제외한96개다. log10개와 생성 bytecode3개를 포함한다. runner result와 runner log는 각각3개다. Metro log·Ruby receipt·PNG·app ZIP·APK는0개다. 원본 hash와 공개 비식별 byte의 hash를 구분한다.

| 원본 core | SHA256 |
| --- | --- |
| REPORT.md | 3d94f63afc65a3734f9bffd3d9b7a9d2a4108cae204c5ccbe1edec827e2c1427 |
| manifest.json | 3c3246cb3cc8a2eeb31f8fcc3f6b7fa0547735bb0b2201e8d95a516adc61aa59 |
| SHA256SUMS | e754c4cac71f7652d2409c610a43a54e7ab7e3d255a80b63ecfee409d3f55f8c |
| 최초 outer log | ebc30e6107a26966d28613940a7b1aa6e8e4e379cb5f8996701974b9ca38166b |
| root release receipt | 415845e301b06f3ce716b999f36c7434d976c485bd38bebfb0cf7cb0a2f27f53 |

원본 helper55개/index56개와 이전 attempt15·14·13·12 packet 및 공개 이력은 불변이다. 원본 packet은 두 독립 검토에서 material finding0을 확인했다. 공개 문서는 두 독립 검토에서 material finding0을 확인했다. publicationReady=true다. 새 공개 head·CI는 CI_PENDING이다.

다음 routine attempt17은 caller의 absolute audit 인자만 정정하는 source-only 준비다. 입력 정책을 바꾸지 않는다. 새 정책 승인은 필요하지 않다. 실제 검토·preflight·새 lease 전에는 actual 권한이 없다. 원인 해결이나 성공을 보장하지 않는다. #212와 PR236은 OPEN이다. 종료 참조를 추가하지 않는다. PR236을 병합하지 않는다. 실제 Runstir는 NOT_AUTHORIZED다.

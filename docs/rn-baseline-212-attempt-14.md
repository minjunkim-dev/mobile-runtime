# attempt-14: frozen Bundle 성공 후 observer UNKNOWN으로 중단

검증일: 2026-10-11, Asia/Seoul. 상태: **부분 검증. #212 미완료.**

[ADR-0028](https://github.com/minjunkim-dev/mobile-runtime/blob/9e121a5ae9bf5a099698805361856d54e9e4b409/docs/adr/0028-rn-bundler-norc-argument-order.md)의 입력을 유지했다. 정책 CI38121517167의 네 job과 두 helper 독립 검토를 통과했다. 최소 b62를 새 내장 경로에 독립 clone했다. helper의 frozen 선택 receipt producer 한 곳과 log reader 한 곳의 ID만 정정했다. 최초 선택 receipt와 새 frozen 선택 receipt를 각각 보존했다. source·version·환경·원본 명령·순서·observer query/sampling/delay·판정은 유지했다.

| 단계 | 실제 결과 |
| --- | --- |
| 최소 clone·checkout·원본 npm ci | exit0·strict55/원본 세 lock PASS |
| 원본 early Metro | 실제 HTTP200·응답 hash·own process/port·생존·source/fatal guard PASS |
| 최초 mise 선택·Ruby facts·공식 raw gem/spec | exit0·준비 guard PASS |
| installer·Bundler2.5.22 activation·bootstrap | PASS |
| 새 frozen 선택·selected-environment probe | exit0·준비 guard PASS |
| 원본 frozen Bundle install | exit0·observer·준비 guard PASS |
| gem-actual 원본 명령 | exit0·CocoaPods1.15.2/xcodeproj1.25.1 출력 |
| gem-actual observer | 저장된 관측83개·읽기 오류1개·passed=false |
| 준비 helper | guard FAIL·outer exit1·필수 STOP |
| Bundle exec 내부환경·Pods·native·기기·첫 화면·Android·Mattermost·두 fresh | NOT_STARTED |

원본 runner12개의 command exit는 모두0이다. 준비 guard11개는 PASS다. gem-actual guard 한 개는 FAIL이다. 출력 버전은 실제 consumer context의 검증 PASS를 대신하지 않는다. frozen Bundle 성공은 Pod deployment와 앱 첫 화면 성공이 아니다.

gem-actual runner 구간은 17:30:13.596472부터 17:30:33.016841까지다. 이 구간은 사후 감사를 포함한다. observer는 `stage=executable`, `errorCode=EXECUTABLE_UNKNOWN`, `type=RuntimeError`를 기록했다. 원본 tool exit0과 observer false를 분리한다. 정확한 하위 원인은 unknown이다. process 종료나 race를 원인으로 단정하지 않는다. 최초 terminal 오류 응답과 result/log를 보존했다. 같은 attempt에서 helper·ID·원본 명령·flags·observer·조건을 바꾸거나 재시도하지 않았다.

전체 Ruby consumer actualObservations는554개다. Bundle444/install16/activation2/spec7/facts2/gem-actual83이다. gem-actual 오류는1개다. 다른 consumer 오류는0개다. 관측 과정의 runtime ENV·plugin 효과·각 reshim 효과는 미측정이다. 원본 command exit0만으로 observer UNKNOWN을 통과시키지 않았다.

최초 파생 집계는 존재하지 않는 `rubyConsumer.observations`를 읽었다. 빈 배열 기본값으로 count0을 기록했다. 원본 result의 정확한 필드는 `rubyConsumer.actualObservations`이며83개다. 최초 잘못된 파생 진단과 반납 요청 byte는 그대로 보존했다. 별도 `observer-count-correction.json`이 원본 result hash·정정83·총554·STOP 불변을 연결한다. 이 공개 문서와 manifest는 정확한 필드를 사용한다. 원본 result/log/helper와 판정은 바꾸지 않았다.

root의 최초 읽기 분석은 과거 failure filename을 가정해 FileNotFoundError였다. 실제 filename을 확인한 뒤 fresh 자원 검사를 다시 통과했다. 독립 집계의 nullable observer 처리 오류도 분석 코드에서만 정정했다. 이 읽기 진단 오류는 원본 tool/source 변경이나 앱 실패가 아니다.

사후 strict source 감사는 tracked55개·원본 세 lock·index·flags·kind·Git 실행 mode PASS다. 최소에 Mattermost checksum·generated target 예외를 적용하지 않았다. metadata·host canonical/type/mode/byte와 shared 최종 감사는 PASS다. shared changedPaths는0개다. 원본 plugin과 private output scope도 PASS다. 최종 snapshot은 일시적인 shared write 부재와 OS 격리를 증명하지 않는다. marker의 실효 권한 동등성도 미측정이다.

소유한 early Metro group만 종료했다. 앱·native·Simulator boot·Emulator·reverse·Gradle은 미시작이다. 전용 iOS26은 Shutdown이다. 초기 Simulator 두 개와 기존 GUI·Watchman을 보존했다. 최종8081 free·기존ADB empty·native/Emulator0을 확인했다. source와 준비 output 및 기존 AVD 데이터·정의·runtime을 보존했다. 전역 도구 선택·권한·daemon을 바꾸지 않았다.

초기 grant·readiness false·cleanup 반납 요청 상태를 보존했다. root는 2026-10-11T08:34:05.074419+00:00에 별도 receipt로 RELEASED를 확정했다. 현재 actual 권한은 없다.

[공개 manifest](./evidence/212/attempt-14/manifest.json)는 원본 전체178개 파일의 hash와 size만 연결한다. base175개와 core3개다. index는 자기 파일을 제외한177개다. 생성 Python bytecode10개도 포함했다. runner result12개·runner log12개·Metro log1개다. PNG·app ZIP·APK는0개다. 공식 raw gem1개는 앱 산출물이 아니다. 원본 hash는 공개 비식별 byte의 hash가 아니다. 실제 경로·PID·session·환경과 argv 본문은 공개하지 않는다.

| 원본 core | SHA256 |
| --- | --- |
| REPORT.md | `0e7f8ac72b327d90534adb059d76fea284be518327c40bc943418e0f9def57af` |
| manifest.json | `90dede433143900d0bf9a09f51bdb8e90167c2d9480fe456b8aea712c33a375a` |
| SHA256SUMS | `672a1c95a27d8e3f985305996932481fb9996f9d6c9f1b786c5682105c8c319b` |
| count correction sidecar | `2b346e2f4f2e614d45c88eea2574440fb95733c23ae871a46fae5ba9442b6a28` |
| root release receipt | `f833f041c8d38d51238f554d06cb2fac00d0360539c881019cc904dea0efbcb2` |

source-only 메모리1150개와 syntax26개는 PASS다. helper map49개/index50개는 불변이다. 원본 attempt13·12 packet과 공개 이력을 유지했다. 원본 packet의 두 독립 검토는 material finding0이다. 공개 문서의 두 독립 검토는 material finding0이다. publicationReady=true다. 새 공개 head·CI 결과는 PR236 본문과 공개 checkpoint 댓글에 기록한다.

다음 attempt15는 기존 ADR-0028의 고정 비식별 진단 범위에서 source-only로 준비 중이다. 원인을 해결했거나 성공을 보장한다고 주장하지 않는다. 두 최종 독립 검토·최신 preflight·새 root lease 전 actual은 금지다. #212와 PR236은 OPEN이다. 종료 참조를 추가하지 않는다. PR236을 병합하지 않는다. 실제 Runstir는 NOT_AUTHORIZED다. 공동 게이트는 후속 티켓이다.

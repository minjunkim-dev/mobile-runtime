# attempt-15: Bundle exit0 뒤 launcher-image-zero 관측 오류로 중단

검증일: 2026-10-11, Asia/Seoul. 상태: **부분 검증. #212 미완료.**

[ADR-0028](https://github.com/minjunkim-dev/mobile-runtime/blob/9e121a5ae9bf5a099698805361856d54e9e4b409/docs/adr/0028-rn-bundler-norc-argument-order.md)의 입력을 유지했다. 정책 CI38121517167 네 job은 SUCCESS다. 두 helper 독립 검토는 material finding0이다. 메모리1,236개와 syntax27개 및 authority probe4개를 통과했다. 최소 b62를 새 내장 경로에 독립 clone했다. 이전 clone·node_modules·vendor·Pods·build를 복사하지 않았다.

observer는 기존 executable query 네 call-site의 고정 tag를 구분했다. 같은 proc_pidpath 반환값을 한 번 저장했다. 기존 실패 경계에서 zero/negative 고정 stage/errorCode만 구분했다. errno와 추가 query를 조회하지 않았다. 원본 argv/env·source·version·plugin·순서·FFI·query 횟수·sampling·delay·PASS/STOP 판정은 유지했다. 새 입력 예외를 추가하지 않았다.

| 단계 | 실제 결과 |
| --- | --- |
| 최소 clone·checkout·원본 npm ci | exit0·strict55/원본 세 lock PASS |
| 원본 early Metro | 실제 HTTP200·응답 hash·own process/port·생존·source/fatal guard PASS |
| 최초 mise 선택·Ruby facts·공식 raw gem/spec | exit0·준비 guard PASS |
| installer·Bundler2.5.22 activation·bootstrap | PASS |
| 새 frozen 선택·selected-environment probe | exit0·준비 guard PASS |
| 원본 frozen Bundle install command | exit0 |
| 같은 Bundle observer | 실제 관측551개·읽기 오류1개·passed=false |
| 준비 helper | guard FAIL·outer exit1·필수 STOP |
| gem-actual·Bundle exec 내부환경·Pods·native·기기·첫 화면·Android·Mattermost·두 fresh | NOT_STARTED |

원본 runner11개의 command exit는 모두0이다. 준비 guard10개는 PASS다. Bundle guard 한 개는 FAIL이다. 원본 Bundle command 성공은 observer·Pod deployment·앱 첫 화면 성공이 아니다.

Bundle runner 구간은 18:07:57.649565부터 18:08:24.865386까지다. 이 구간은 사후 감사를 포함한다. observer는 `stage=executable-launcher-image-zero`, `errorCode=EXECUTABLE_RETURN_ZERO`, `type=RuntimeError`를 기록했다. 기존 launcher-image query의 반환값0을 구분했다. 실제 반환값0의 원인은 unknown이다. 종료 race·권한·TCC·프로세스 부재를 원인으로 단정하지 않는다. 원본 tool exit0과 observer false를 구분한다. 같은 attempt에서 재시도·helper·ID·argv/env·flags·observer·조건을 바꾸지 않았다.

실제 Ruby consumer receipt는5개다. 정확한 `rubyConsumer.actualObservations` 필드를 직접 대조했다.

| consumer | 실제 관측 | 오류 |
| --- | ---: | ---: |
| 원본 Ruby facts | 3 | 0 |
| 공식 raw gem spec | 8 | 0 |
| installer | 17 | 0 |
| activation | 3 | 0 |
| frozen Bundle install | 551 | 1 |
| 합계 | 582 | 1 |

gem-actual은 미시작이다. attempt14의 여섯 consumer receipt와 버전 출력을 승계하지 않는다. 이전 attempt14의 최초 count0과 정정 sidecar는 이전 이력으로 보존한다. 이번 원본 count는551/582다. 관측 과정의 runtime ENV·PKG_CONFIG_PATH·원본 plugin 효과·각 reshim 효과는 미측정이다.

사후 strict source 감사는 tracked55개·원본 세 lock·index·flags·kind·Git 실행 mode PASS다. 최소 앱에 Mattermost checksum·generated target 예외를 적용하지 않았다. metadata·host canonical/type/mode/byte와 shared 최종 감사는 PASS다. shared changedPaths는0개다. 원본 plugin과 private output scope도 PASS다. 최종 snapshot은 일시 shared write 부재와 OS 격리를 증명하지 않는다. marker의 실효 권한 동등성도 미측정이다.

소유한 early Metro group은 Ruby 준비 전에 종료했다. 앱·native·Simulator boot·Emulator·reverse·Gradle은 미시작이다. 전용 iOS26은 Shutdown이다. 기존 두 Simulator와 GUI·Watchman을 보존했다. 최종8081 free·기존ADB empty·native/Emulator0을 확인했다. source와 준비 output 및 기존 AVD 데이터·정의·runtime을 보존했다. 전역 도구 선택·권한·daemon을 바꾸지 않았다.

초기 grant·readiness false·cleanup과 RETURN_REQUESTED를 보존했다. root는 2026-10-11T09:12:47.585567+00:00에 별도 receipt로 RELEASED를 확정했다. 현재 actual 권한은 없다. root의 최초 읽기 분석은 과거 final-resource.json filename을 가정해 FileNotFoundError였다. 실제 final-resource-preflight.json을 확인한 뒤 fresh 자원 검사를 다시 수행했다. 이 읽기 분석 오류는 원본 tool/source 변경이나 앱 실패가 아니다.

[공개 manifest](./evidence/212/attempt-15/manifest.json)는 원본 전체171개 파일의 hash와 size만 연결한다. base168개와 core3개다. index는 자기 파일을 제외한170개다. 생성 Python bytecode9개도 포함했다. runner result11개·runner log11개·Metro log1개·최상위 준비 log2개다. 총 log는14개다. PNG·app ZIP·APK는0개다. 공식 raw gem1개는 앱 산출물이 아니다. 원본 hash와 공개 비식별 byte의 hash를 구분한다. 실제 경로·식별자·환경과 argv 본문 및 예외 원문은 공개하지 않는다.

| 원본 core | SHA256 |
| --- | --- |
| REPORT.md | `731929421a9bc197f420191a71e0dcd12b70850ee673bc06d912a8d794d3b827` |
| manifest.json | `3a4e59606337cde8e7fb5b8d6a2af11ebbc1511877f67dee5cc87ed4afb36a56` |
| SHA256SUMS | `e7dedf512edb267a9dce1578def4ebaefe809c9e6d539ca07f6ed461ba5df4b5` |
| 원본 Bundle result | `01a52ec60d8158535d550a21d0c49bbf91380accff23485ea9a2a1c854c4ec44` |
| root release receipt | `6c7bb411962e35677521a7f320f1cbafa1c4d09e1feab1ea0c18cbb2c9f5637c` |

helper map51개/index52개와 원본 attempt14·13·12 packet 및 공개 이력을 유지했다. 원본 packet과 공개 문서는 각각 두 독립 검토에서 material finding0을 확인했다. publicationReady=true다. 새 공개 head·CI는 대기한다.

ADR-0029는 proposal이며 사용자 Q1을 기다린다. 정책 main 채택과 attempt16 actual 권한은 없다. 원인 해결이나 성공 보장이 아니다. #212와 PR236은 OPEN이다. 종료 참조를 추가하지 않는다. PR236을 병합하지 않는다. 실제 Runstir는 NOT_AUTHORIZED다. 공동 게이트는 후속 티켓이다.

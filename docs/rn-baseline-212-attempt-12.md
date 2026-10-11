# attempt-12: 원본 metadata 감사 통과 후 Bundler installer 중단

검증일: 2026-10-11, Asia/Seoul. 상태: **부분 검증. #212 미완료.**

[ADR-0027](https://github.com/minjunkim-dev/mobile-runtime/blob/81f25a513fef92be75c09c8d3f0b567ded3f4d8c/docs/adr/0027-rn-mise-state-metadata-links.md) main과 helper 독립 검토 뒤 새 단독 lease로 실행했다. 최소 b62를 새 내장 경로에 독립 clone했다. Mattermost와 두 fresh clone은 생성하지 않았다. 원본 packet과 이전 시도를 보존했다.

| 단계 | 실제 결과 |
| --- | --- |
| clone·checkout·원본 npm ci | exit0, strict55·원본 세 lock PASS |
| 원본 early Metro | actual HTTP200·응답·own process/port PASS 뒤 소유자 종료 |
| 원본 mise 선택 | exit0·guardPASS |
| metadata 사후 감사 | 승인 STATE 링크5개·host/shared/source PASS |
| 실제 원본 Ruby facts·prefix/pkgconfig | exit0·observerPASS |
| 공식 Bundler2.5.22 metadata·archive·spec | PASS |
| clone별 gem installer | 원본 exit1·observerFAIL |
| activation·frozen Bundle·Pods·native·기기·Android·Mattermost·fresh | NOT_STARTED |

최초 installer 로그는 `ERROR:  Invalid option: --norc. See 'gem --help'.`다. Ruby facts는 Ruby3.4.11과 RubyGems3.6.9를 기록했다. 승인한 요청 argv를 바꾸거나 재시도하지 않았다. 최소 installer의 핵심 argv는 아래와 같다. 정확한 환경 prefix와 전체 요청 배열은 [manifest](./evidence/212/attempt-12/manifest.json)에 비식별화했다.

```sh
env GEM_HOME=<CLONE_BOOTSTRAP> GEM_PATH=<CLONE_BOOTSTRAP>:<SAME_RUBY_DEFAULT_DIR> \
  <ORIGINAL_RUBY_ROOT>/bin/gem --norc install --local <VERIFIED_RAW_GEM> \
  --install-dir <CLONE_BOOTSTRAP> --no-document
```

runner는 15:58:09.731222부터 15:58:30.706359까지를 기록했다. 이 구간은 사후 감사 시간을 포함한다. installer command exit1와 observer 최종 FAIL을 분리한다. observer는 실제 원본 Ruby executable의 관측3개와 `RuntimeError: actual process identity/context observation incomplete` 한 개를 기록했다. 원본 catch는 exception의 세부 message를 저장하지 않았다. 정확한 query/predicate는 unknown이다. 관측 오류가 installer 실패를 유발했다고 주장하지 않는다. 관측 process argv 원문을 저장하지 않았다.

metadata 링크는 clone config2개·host config2개·기존 shared home marker1개를 참조한다. host canonical/type/mode/byte와 source/shared 사후 감사는 PASS다. private marker의 실효 권한 동등성은 미측정이다. 원본 plugin1과 strict55·세 lock·index·flags·kind·Git 실행 mode는 불변이다. 같은 Ruby repository·installer·launcher·user gems의 최종 snapshot도 같다. 이 결과는 일시적 공유 write 부재와 OS 격리를 증명하지 않는다. runtime ENV·plugin 효과·각 reshim 효과도 미측정이다.

별도 사후 출력 wrapper가 tuple에 `.get`을 호출하여 AttributeError를 냈다. 감사는 이미 PASS 파일을 썼다. 이 출력 오류를 source/shared 실패나 원본 앱 실패로 분류하지 않는다. 감사와 consumer를 재실행하지 않았다. release SHA 문장을 추가하려던 두 core 파일은 root 지시로 최초 봉인 byte에 복구했다. 최초 REPORT·manifest·index와 모든 receipt/helper hash를 다시 확인했다.

early Metro만 소유자 process group 종료로 정리했다. 앱·Emulator·reverse·Gradle·native는 미시작이다. 전용 iOS26은 Shutdown을 유지했다. 초기 Simulator2개와 기존 GUI·Watchman을 보존했다. 최종 port8081 free·기존ADB empty·native/Emulator0을 확인했다. root가 별도 receipt로 lease RELEASED를 확정했다. 초기 grant/readiness/cleanup false를 덮어쓰지 않았다.

원본 packet은 index118개와 index 포함119개다. runner result7개·runner log7개·Metro log1개를 구분한다. PNG·app ZIP·APK는0개다. raw gem1개는 앱 산출물이 아니다. 공개 manifest의 원본 SHA는 비식별 공개 byte의 SHA가 아니다.

| 원본 core | SHA256 |
| --- | --- |
| REPORT.md | `158f281deba9d5425c074daa5ab28ff1cfab58e1949c66f49217780b9330849e` |
| manifest.json | `cdca036ab34c539e46cc10b9ccf4cf9a6969322a1842598080fad1b6781c038b` |
| SHA256SUMS | `f8070767ff9739f5a188d7a0a8fc5e41aeffa3b150187b5f58031b3c9aab7240` |
| root release receipt | `70f95ec966106b64f0172256fa05468601adc73605a4ab6340ca82070f22746d` |

source-only 메모리792개와 syntax23개는 PASS다. helper43개/index44개는 불변이다. 이 검사는 실제 양플랫폼 첫 화면과 fresh 인계를 대체하지 않는다. 공개 초안의 독립 검토는 진행 중이다. publicationReady=false다.

다음 조건은 최소 gem installer 두 token 위치정정 정책검토와 observer 비식별 진단이다. ADR-0028은 미확정이다. 새 정책·새 실행 lease 전에는 추가 actual을 수행하지 않는다. #212와 PR236은 OPEN이다. 종료 참조를 추가하지 않는다. 실제 Runstir 실행과 공동 게이트는 후속 티켓이다.

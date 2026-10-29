# attempt-13: Bundler 준비 성공 후 helper receipt 중복으로 중단

검증일: 2026-10-11, Asia/Seoul. 상태: **부분 검증. #212 미완료.**

[ADR-0028](https://github.com/minjunkim-dev/mobile-runtime/blob/9e121a5ae9bf5a099698805361856d54e9e4b409/docs/adr/0028-rn-bundler-norc-argument-order.md)을 적용했다. 정책 CI `38121517167`의 네 job과 두 독립 helper 검토를 통과했다. 새 단독 lease에서 최소 `b62e3a4d5e7cfc05d7d948a5a4e30f0cc6a82bb4`를 새 내장 경로에 독립 clone했다. 이전 packet과 공개 이력을 보존했다.

| 단계 | 실제 결과 |
| --- | --- |
| clone·checkout·원본 npm ci | runner 세 개 exit0·strict55·원본 세 lock PASS |
| 원본 early Metro | 실제 HTTP200·응답·own process/port·생존·fatal log guard PASS |
| 최초 원본 mise 선택 | exit0·guard PASS |
| metadata·host·shared 감사 | PASS |
| 원본 Ruby facts·prefix/pkgconfig | Ruby3.4.11·RubyGems3.6.9·exit0·observer PASS |
| 공식 Bundler2.5.22 metadata·raw gem·spec | PASS |
| 위치를 정정한 원본 installer | exit0·observer PASS·guard PASS |
| Bundler activation | 2.5.22·exit0·observer PASS·guard PASS |
| bootstrap receipt | passed=true |
| 두 번째 선택 전 helper receipt 기록 | 중복 label로 outer helper exit1 |
| 두 번째 선택 실제 consumer·frozen Bundle·Pods·native·기기·Android·Mattermost·fresh | NOT_STARTED |

최소 installer의 `install`과 `--norc` 두 token 위치만 교환했다. 나머지 원본 argv·source·version·환경·plugin을 유지했다. 전체 승인 요청 배열은 [공개 manifest](./evidence/212/attempt-13/manifest.json)에 placeholder로 기록했다.

```sh
env GEM_HOME=<CLONE_BOOTSTRAP> GEM_PATH=<CLONE_BOOTSTRAP>:<SAME_RUBY_DEFAULT_DIR> \
  <ORIGINAL_RUBY_ROOT>/bin/gem install --norc --local <VERIFIED_RAW_GEM> \
  --install-dir <CLONE_BOOTSTRAP> --no-document
```

installer runner 구간은 16:48:37.287657부터 16:48:56.957180까지다. activation runner 구간은 16:49:18.354512부터 16:49:37.508999까지다. 두 구간은 사후 감사 시간을 포함한다. 실제 Ruby 관측은 installer18개와 activation2개다. 전체 Ruby consumer 관측28개의 오류는0개다. 요청 argv와 실제 PID·executable 및 exec-image 초기 선택 환경을 구분했다. 관측 process argv 원문을 저장하지 않았다. runtime ENV·PKG_CONFIG_PATH·plugin 효과·각 reshim 효과는 미측정이다.

최초 필수 실패는 `HELPER_RECEIPT_COLLISION`이다. `bundler_bootstrap.py:173`이 만든 최초 선택 label을 `prepare_frozen_stage.py:44`가 다시 사용했다. `run_step.py:81`의 before-consumer 감사가 `ruby_preparation.py:220`의 `assert not out.exists()`에서 중단했다. 중복 label은 `minimal-baseline-mise-effective-selection`이다. 최초 선택 receipt는 그대로 남았다. 두 번째 원본 선택 명령과 새 result/log는 생성되지 않았다. runner result8개는 모두 exit0이다. outer helper session은 exit1이다. 이 오류를 원본 mise·Ruby·Bundle·Pod 실패로 분류하지 않는다. outer 실패의 정확한 시각은 별도 stage wrapper에 기록하지 않았다. 최초 오류 출력은 원본 terminal 응답에 남았다. 새 진단에는 고정 cause와 source 위치만 저장했다.

같은 attempt의 label·helper·argv·조건을 바꾸거나 재시도하지 않았다. frozen Bundle·Pods·native와 설치·실행·첫 화면 및 Android·Mattermost·두 fresh는 미시작이다. 최소에 Mattermost checksum·generated target 예외를 적용하지 않았다.

사후 strict source 감사는 tracked55개·세 lock·index·flags·파일 종류·Git 실행 mode PASS다. metadata·host canonical/type/mode/byte와 shared 최종 감사는 PASS다. shared changedPaths는0개다. 원본 plugin identity도 같다. 이 결과는 일시적인 공유 write 부재와 OS 격리를 증명하지 않는다. marker의 실효 권한 동등성은 미측정이다.

root의 초기 preflight는 ADB `ps comm` basename 판별에서 false였다. 후속 읽기 전용 `lsof txt`가 승인 ADB executable의 canonical 경로를 확인했다. 최종 preflight는 PASS다. 기존 ADB server에만 devices 조회를 수행했다. server 시작·교체는 없었다. 초기 진단과 최종 proof를 모두 보존했다.

소유한 early Metro process group만 종료했다. 앱·Emulator·reverse·Gradle·native는 미시작이다. 전용 iOS26은 Shutdown을 유지했다. 초기 Simulator 두 개와 기존 GUI·Watchman을 보존했다. 최종 port8081 free·기존 ADB empty·native/Emulator0을 확인했다. source와 AVD 데이터를 보존했다. root가 별도 receipt로 lease RELEASED를 확정했다. 초기 grant·readiness false·cleanup 반납 요청 상태는 그대로 남겼다. 현재 actual 권한은 없다.

원본 packet은 전체133개와 index132개다. [공개 manifest](./evidence/212/attempt-13/manifest.json)는 base130개와 core3개의 원본 hash·size를 모두 연결한다. runner result8개·runner log8개·Metro log1개를 구분한다. PNG·app ZIP·APK는0개다. 공식 raw gem1개는 앱 산출물이 아니다. 공개 파일은 비식별한 별도 byte다. 원본 hash를 공개 byte의 hash로 표시하지 않는다.

| 원본 core | SHA256 |
| --- | --- |
| REPORT.md | `aec5750d16b371aadf399cb014a48a5de8157666a2fc7e68bf3d6500c5380f66` |
| manifest.json | `8fa419a1a5342976c23f72b61c1ff01aee29d31177749233cd4b9aabf950a2fe` |
| SHA256SUMS | `70f84633aed6103c5dd8b0e2f5980f5e9b63b209034e3aac8f9b1bd1b0171ddc` |
| root release receipt | `c5f3ba88c52c1f9c59f4edb2113ba59a6bd6bb091c92a35269c44156a5e82921` |

source-only 메모리817개와 syntax24개는 PASS다. helper map46개/index47개는 불변이다. 원본 packet의 두 독립 검토는 material finding0이다. 공개 문서의 두 독립 검토도 material finding0이다. publicationReady=true다.

다음은 원본 조건을 유지하는 routine helper receipt-ID 정정이다. 별도 source-only attempt14에서 producer 한 곳과 read 한 곳을 정정한다. 새 입력 정책 예외는 없다. 최종 독립 검토·최신 resource preflight·새 root lease 전에는 actual을 수행하지 않는다. 새 head와 CI는 PENDING이다. #212와 PR236은 OPEN이다. 종료 참조를 추가하지 않는다. 실제 Runstir는 NOT_AUTHORIZED다. 공동 게이트는 후속 티켓이다.

# #212 attempt-11: 원본 mise 선택 뒤 private STATE guard 중단

2026-10-11 KST. **부분 증거다. #212를 닫지 않는다.** 새 최소 b62의 원본 clone·npm·early Metro 검사는 통과했다. 원본 mise 선택 명령은 exit `0`이었다. private STATE의 symlink 5개로 사후 guard가 중단했다. 공유 경로와 source는 최종 불변이었다. 실제 Ruby facts·공식 gem·frozen Bundle·Pods·native·기기·Mattermost·fresh는 미시작이다.

[공개 manifest](./evidence/212/attempt-11/manifest.json)는 비공개 원본 packet 102개 파일의 상대 경로·크기·SHA256을 연결한다. 개인 경로·process 식별자·실제 symlink target·원본 로그 내용은 공개하지 않는다. 공개 bytes는 원본 manifest와 다르다. 종료 참조를 추가하지 않는다.

## 고정 입력과 정책

[ADR-0026](https://github.com/minjunkim-dev/mobile-runtime/blob/24c3189997316fced36b77cb1af261318ebb4696/docs/adr/0026-rn-original-plugin-preparation.md)은 두 표본의 원본 Ruby와 plugin identity를 유지한다. clone별 private DATA·CACHE·STATE·TMP·SHIMS와 원본 shared installs lookup을 Ruby 준비 consumer에만 적용한다. 기존 npm/hook 분리와 원본 Metro/native 명령을 유지한다. 최소 표본에만 Bundler `2.5.22` bootstrap을 적용한다.

[PR #245](https://github.com/minjunkim-dev/mobile-runtime/pull/245)는 main `24c3189997316fced36b77cb1af261318ebb4696`에 병합됐다. exact head `aad9f47f9a0fe2bff5bf77eb81153f1c5087787f`의 CI `38099391787` 네 job은 PASS다. 정책 채택과 실제 baseline 결과는 별개다.

| 입력 | 실제 상태 |
| --- | --- |
| 최소 source | `b62e3a4d5e7cfc05d7d948a5a4e30f0cc6a82bb4`, 새 독립 clone checkout PASS |
| Mattermost source | `c2fe3beda22befd2178dce431793c09111ed903e`를 설정했다. 이번 clone은 미생성이다. |
| 두 fresh | 위 두 SHA를 설정했다. 두 clone은 미생성이다. |
| 경로 | 새 내장 Data 경로다. 시작 path/resource guard PASS다. 여유 공간 `38,853,124,096` bytes로 20 GiB 조건을 통과했다. |
| 최소 source 감사 | 원본 tracked 55개 raw bytes·index·hidden flags·file kind·Git 실행 mode와 원본 세 lock을 유지했다. |
| 예외 | Mattermost Hermes 한 값과 generated mixed Debug 12값 예외를 최소 표본에 적용하지 않았다. |

원본 `package-lock.json` SHA256은 `3478830fc86d9d1ae7cd46ae129eec9c4915b0ec4e2df247e2cb62b136caeee0`다. `Gemfile.lock`은 `3679d60340d049c31b74052580c64ab26b3e6fa611f332c1407121dfc3c791eb`다. `ios/Podfile.lock`은 `cec099ee896ed83dd780bd8da0a03e840c3ba6a0803f90c0bbfcd04efaf17d56`다.

## 실행과 최초 필수 실패

새 단독 lease `rn-212-attempt11-adr0026-20261011`을 배정했다. 실제 Runstir CLI/GUI는 이번 권한에 포함하지 않았다.

| 단계 | 실제 결과 |
| --- | --- |
| 새 clone·checkout | runner 2개 exit `0`, b62 source 감사 PASS |
| 원본 `mise exec node@22.23.2 -- npm ci` | runner exit `0`, strict source 사후 감사 PASS |
| 원본 early Metro | `env -u BASELINE_APP_ROOT mise exec node@22.23.2 -- npm start`. actual HTTP `200`, body `packager-status:running`, own process·listener와 전후 생존 및 source binding PASS |
| own Metro 종료 | 검증한 own process group만 종료했다. listener 부재를 확인했다. |
| 공유 snapshot·원본 plugin identity | 첫 Ruby 준비 probe 전에 snapshot을 고정했다. regular 1,553 bytes의 원본 plugin 1개를 확인했다. |
| 원본 mise 선택 명령 | `10:19:11.704311~10:19:31.450064 KST`, runner의 원본 command exit `0`. Python launcher lookup PASS |
| 사후 private output guard | `privateOutputScopePassed=false`, runner guard FAIL. 상위 bootstrap/frozen orchestration exit `1`로 중단 |

HTTP body의 원본 SHA256은 `ed71e52f066b30c279378b7933ec895ee558e0899131124296dec5bec2995cef`다. HTTP·own record·log와 source binding을 공개 manifest의 raw hash에 연결한다. 원본 Metro config와 Watchman 조건을 유지했다. readiness PASS는 앱 첫 화면 성공이 아니다.

선택 명령은 private mise 환경 여섯 개와 원본 Ruby `3.4.11`·Node `22.23.2` 선택으로 Python observer를 실행했다. Python은 원본 Ruby/gem/bundle/Node launcher 경로를 확인했다. 실제 Ruby facts/prefix/pkgconfig probe는 아직 시작하지 않았다. 이 경로 lookup을 실제 Ruby activation으로 표현하지 않는다. 별도 Node/npm version probe도 수행하지 않았다.

사후 private snapshot에는 STATE의 `tracked-configs` symlink 4개와 `trusted-configs` symlink 1개가 있었다. 원본 mise가 이 reference를 생성했다. target은 clone 입력과 기존 사용자/config reference다. exact lstat/type/link target/canonical path는 비공개 read-only receipt에 보존했다.

helper `ruby_preparation.py:81–82`는 원본 mise를 가리키는 `data/shims` symlink만 허용했다. STATE symlink를 거부했다. guard error는 `shared/plugin/private audit failed`다. 명령 exit `0`과 prepared-input guard FAIL을 분리한다. 이 결과는 tool 부재·원본 frozen Bundle 실패·source 변경·앱 build 실패가 아니다. symlink의 정책 해석은 이번 측정으로 확정하지 않는다.

runner result 4개에서 원본 command는 모두 exit `0`이다. selection의 사후 guard만 FAIL이다. 상위 orchestration exit `1`은 tool 결합 출력에서 확인했다. 별도 outer timestamp와 stdout/stderr 원본 파일은 저장하지 않았다. runner log 4개와 Metro log 1개를 합해 log는 5개다.

## source·공유 감사와 미시작 경계

source의 초기·npm 뒤·selection 전후·최종 strict 감사가 PASS다. tracked 55개와 원본 세 lock이 불변이다. 원본 plugin SHA256은 `6cedbcf33ae6de36e2569a3a181735031e05e1e5c52745d0d725d8b665f0ac5c`다. 사후 plugin identity도 같았다.

공유 snapshot의 `changedSharedPaths`는 빈 배열이다. 공유 경로의 최종 raw bytes·file kind·link·mode는 원본 snapshot과 같았다. **이 snapshot은 일시적 공유 write 부재나 OS 쓰기 격리를 증명하지 않는다.** 실제 runtime ENV·plugin loading 효과와 각 reshim의 횟수/exit도 미측정이다.

필수 실패 뒤 재시도하지 않았다. source·helper·설정·plugin·symlink와 원본 argv를 변경하지 않았다. actual Ruby consumer 관측, 공식 gem metadata/archive/spec/installer/activation, frozen Bundle/Pod deployment는 미시작이다. 최소 양플랫폼 native/install/launch/firstscreen과 Mattermost 및 두 fresh도 미시작이다. PNG·APK·app ZIP은 0개다. 과거 성공을 이번 시도의 성공으로 승계하지 않는다.

source-only helper 메모리 검사 667개와 Python syntax 21개는 PASS다. 봉인 map은 36개다. batch 한 개를 포함한 helper index는 37개다. actual 종료 뒤 이 36개 hash의 불일치는 0개였다. v1 source-only archive 18개를 보존했다. source-only 검사는 실제 설치·native compatibility 증거가 아니다. 독립 helper 검토와 실제 lease 채택 receipt도 원본 packet에 보존했다.

## cleanup과 lease

최종 resource 관측 시각은 `10:19:50.559709 KST`다. 초기 Simulator 2개는 Booted다. 전용 iOS26은 Shutdown이다. 기존 GUI와 Watchman을 보존했다. 8081 listener는 없다. 기존 adb5037 server를 읽은 뒤 빈 device 목록을 확인했다. actual native/Emulator process는 0개다.

이번 시도에서 앱 install·Simulator boot·Emulator·adb reverse·Gradle을 시작하지 않았다. own Metro는 Ruby 준비 전에 이미 종료했다. 기존 앱이나 비소유 process를 종료하지 않았다. source 사후 감사와 resource cleanup은 PASS다.

최초 grant의 bytes와 cleanup의 초기 `rootReleaseConfirmed=false`를 이력으로 유지했다. 반환 요청 뒤 root는 `2026-10-11 01:20:56 UTC`에 별도 receipt로 `RELEASED`를 확정했다. 그 SHA256은 `5b656a433d0a4eec6a1f03f0bd03def59c7d9e24f48e3d07b05c6c53557b34e3`다. 추가 실제 권한은 없다.

## 원본 packet

| 원본 | bytes | SHA256 |
| --- | --- | --- |
| REPORT.md | 3316 | `816d9e00373962a2810ac6d4ff4b0ba81296e303c9715d7befa1773cb6536eef` |
| manifest.json | 3767 | `b65eb166072478a1b725b710396c99ee38e2f168d62d026904e932b8ea31ca5b` |
| SHA256SUMS | 10246 | `bbbce379965d08060e1c665d52ff7969f4381bd820f84be71e8d6329c77b42e2` |

checksum index 101개 항목과 자기 index까지 포함한 packet 102개 파일의 크기/hash를 연결했다. 확인한 hash 불일치는 0개다. bytecode를 제외했다. 원본 index와 raw draft 및 과거 attempt 자료는 수정하지 않았다. 공개 문서와 manifest 및 PR body는 commit/push 전에 root와 두 독립 검토를 받는다.

새 최소+OSS의 양플랫폼 첫 화면과 각각의 독립 fresh 준비·인계가 남아 있다. 실제 Runstir reproducer와 prepared input 보존 검증은 후속 gate다.

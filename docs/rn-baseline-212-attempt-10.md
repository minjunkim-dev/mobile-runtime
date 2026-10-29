# #212 attempt-10: clone-local Bundler 앞의 plugin guard 중단

2026-10-11 KST. **부분 증거다. #212를 닫지 않는다.** 최소 b62의 새 내장 clone·원본 npm·원본 Metro 실제 HTTP 검사는 통과했다. 원본 Ruby의 `$LOAD_PATH`에서 plugin 파일 1개를 찾았다. 승인한 plugin 거부 guard가 설치 전에 중단했다. 공식 gem 다운로드·설치·activation·원본 frozen Bundle·Pods·native·기기·Mattermost·fresh는 미시작이다.

[공개 manifest](./evidence/212/attempt-10/manifest.json)는 비공개 원본 packet 123개 파일의 상대 경로·크기·SHA256을 연결한다. 개인 경로와 원본 로그 내용은 공개하지 않는다. 공개 manifest의 bytes는 원본 manifest와 다르다.

## 고정 입력과 권한

[ADR-0025](https://github.com/minjunkim-dev/mobile-runtime/blob/5cd6ed8535cbdb76cba187ab9cc060c9812c109f/docs/adr/0025-rn-clone-local-declared-bundler.md)의 Q1 답변은 `초안범위 확정`이다. [PR #244](https://github.com/minjunkim-dev/mobile-runtime/pull/244)는 main `5cd6ed8535cbdb76cba187ab9cc060c9812c109f`에 병합됐다. exact head `2edc1dde77ab4b69fcff677a756b20ecd40315c5`의 CI `38072851577` 네 job은 PASS다. 이 정책은 최소 표본의 원본 Bundler `2.5.22`를 clone별로 준비하도록 허용했다. 같은 Ruby의 default repository 읽기는 허용했다. plugin 입력은 거부했다. global plugin·Ruby·mise·shim·권한 변경은 허용하지 않았다.

| 입력 | 값과 실제 상태 |
| --- | --- |
| 최소 source | `b62e3a4d5e7cfc05d7d948a5a4e30f0cc6a82bb4`, 새 독립 baseline clone checkout PASS |
| Mattermost source | `c2fe3beda22befd2178dce431793c09111ed903e`, 이번 baseline clone 미생성 |
| fresh source | 위 두 SHA를 설정했다. 두 fresh clone은 미생성이다. 설정 SHA를 실제 checkout으로 표현하지 않는다. |
| source/output | 새 내장 Data volume 경로. symlink·보호 위치·외장 경로 없음. root preflight의 여유 공간 `36,961,214,464` bytes로 시작 20 GiB 조건 PASS |
| source 예외 | 최소 b62는 tracked 55개 파일과 원본 세 lock을 strict하게 유지한다. Mattermost Hermes 한 값과 mixed Debug 12값 예외를 최소 표본에 적용하지 않았다. |

원본 `package-lock.json` SHA256은 `3478830fc86d9d1ae7cd46ae129eec9c4915b0ec4e2df247e2cb62b136caeee0`다. `Gemfile.lock`은 `3679d60340d049c31b74052580c64ab26b3e6fa611f332c1407121dfc3c791eb`다. `ios/Podfile.lock`은 `cec099ee896ed83dd780bd8da0a03e840c3ba6a0803f90c0bbfcd04efaf17d56`다.

## 실제 실행

새 lease `rn-212-attempt10-adr0025-20261011`은 실행 worker 한 명만 사용했다. 다른 agent는 실제 Simulator·Emulator·Metro·native를 실행하지 않았다. root의 새 preflight와 helper 독립 검토 뒤에 시작했다. 실제 Runstir CLI/GUI는 이번 권한에 포함하지 않았다.

| 단계 | 결과 |
| --- | --- |
| 새 최소 clone·checkout | runner 2개 exit `0`. b62와 strict source 감사 PASS |
| 원본 `mise exec node@22.23.2 -- npm ci` | runner exit `0`. strict 사후 감사 PASS |
| 원본 early Metro | `env -u BASELINE_APP_ROOT mise exec node@22.23.2 -- npm start`. own launcher PID와 descendant port owner 및 source binding을 확인했다. 실제 HTTP `200`, body `packager-status:running`, process 전후 생존, fatal 로그 부재 PASS. 원본 process 식별자는 비공개 packet에 보존했다. |
| own Metro 종료 | 검증한 own process group에만 SIGTERM. listener 부재와 resource guard PASS |
| Ruby facts와 bootstrap guard | Ruby facts runner exit `0`. `prepare_frozen_stage.py minimal-baseline` orchestration은 `bundler_bootstrap.py:160` assertion에서 별도 exit `1` |

HTTP body 원본 SHA256은 `ed71e52f066b30c279378b7933ec895ee558e0899131124296dec5bec2995cef`다. readiness의 실제 receipt와 HTTP/body/log/own record 및 source binding은 공개 manifest의 원본 hash와 연결한다. 원본 Metro config와 Watchman 조건은 유지했다. 이 결과는 앱 첫 화면 검증이 아니다.

Ruby facts에서 `Ruby 3.4.11`, `RubyGems 3.6.9`, 같은 Ruby의 executable/default directory를 실제 관측했다. `GEM_HOME`은 해당 clone의 `vendor/bundle/tool-bootstrap` 경로다. `GEM_PATH`는 이 경로와 같은 Ruby의 default repository 두 개다. trailing separator와 user/foreign clone 경로는 없다. 이 facts는 Bundler activation이나 version 검증이 아니다. Node `22.23.2`는 원본 argv의 선택이다. 이번 중단 실행에서 별도 Node/npm version probe는 수행하지 않았다. 과거 SDK·native·기기 tuple 측정을 이번 실행의 성공으로 승계하지 않는다.

## 실패 원인과 미시작 경계

`RUBYOPT`, `RUBYLIB`, `RUBYGEMS_GEMDEPS`의 비어 있지 않은 입력은 모두 없었다. 초기 scan은 plugin 0개였다. Ruby가 보고한 `$LOAD_PATH`를 추가한 scan은 `lib/ruby/site_ruby/rubygems_plugin.rb` 1개를 찾았다. 이 파일은 1,553 bytes다. SHA256은 `6cedbcf33ae6de36e2569a3a181735031e05e1e5c52745d0d725d8b665f0ac5c`다. 승인한 `input_environment_allowed` predicate는 plugin 목록이 비어 있어야 통과한다. 알려진 plugin 존재를 확인하고 중단했다.

정적 source는 `PKG_CONFIG_PATH` prefix 추가와 install/uninstall/Bundler install의 `mise reshim` hook을 선언한다. 이번 Ruby facts에서 plugin이 실제 로드됐는지와 runtime 효과는 측정하지 않았다. installer를 호출하지 않았다. 전체 host를 검색하지 않았다. 이 실패를 tool 부재나 원본 frozen Bundle 실패로 분류하지 않는다.

공식 gem metadata와 archive 다운로드, raw gem spec 검사, clone-local 설치, Bundler activation, shared repository before/after snapshot, 선택된 frozen 환경 검사, 원본 Bundle/Pod 명령은 모두 미시작이다. iOS native·install·launch·첫 화면과 Android·Mattermost baseline 및 두 fresh도 미시작이다. plugin 삭제·허용·차단 wrapper·자동 환경 unset·version/flag 변경과 재시도는 수행하지 않았다.

runner result/log는 4쌍이며 모두 exit `0`이다. outer frozen orchestration exit `1`은 별도다. top-level log는 runner 4개, 원본 Metro 1개, 저장한 outer traceback 1개로 총 6개다. outer traceback은 tool의 결합 출력을 보존했다. helper는 outer 시작/종료 timestamp와 stdout/stderr 분리를 보존하지 않았다. Ruby runner receipt의 정확한 argv/cwd/time/exit는 보존했다. PNG·APK·app ZIP과 실제 첫 화면은 0개다.

## 감사와 helper 이력

초기·npm 뒤·bootstrap 직전·필수 중단 뒤 strict source 감사 네 개가 모두 PASS다. tracked 55개 raw bytes, index, hidden flags, file kind, Git 실행 mode와 세 lock을 보존했다. source/output을 다른 clone에서 복사하지 않았다. shared repository snapshot 단계에 도달하지 않았으므로 전체 shared bytes의 전후 불변을 실측했다고 주장하지 않는다.

helper 작성자의 메모리 검사 432개와 Python syntax 21개가 PASS다. v1 독립 bootstrap 검사 165개는 기존 core bytes와 연결한다. v2 두 검토자는 남은 material finding 0개를 보고했다. resource 검토자는 새 71개, 변경 영향 151개, public CLI integration 12개를 확인했다. 두 번째 검토자는 새 71개와 core/명령 불변을 확인했다. 중복 검사를 새로운 합산 총계로 표현하지 않는다. 메모리 검사는 실제 설치와 native 성공 증거가 아니다.

v1의 Android boot 뒤 empty preflight P2를 source-only 단계에서 수정했다. boot/Metro 시작 전 empty guard를 유지했다. boot 뒤에는 root lease, 실제 Popen event/hash, PID/start, 승인 argv, AVD/serial과 immutable record를 연결한다. Android consumer는 현재 own state와 Metro readiness를 확인한 뒤에만 operation을 호출한다. 실제 Android boot에는 도달하지 않았다. 과거 전체 launcher argv/PID receipt는 없다. 새 lease는 문서화한 software/headless/metrics/crash/snapshot 조건의 exact argv를 고정했다. 과거 전체 argv와의 동일성을 입증했다고 주장하지 않는다.

root grant의 literal `helperHashes` map은 38개다. source-only index는 이 38개와 finished batch 및 readiness-v2를 합한 40개다. root grant는 이 index의 SHA256도 연결한다. 원본 manifest의 `initialGrantHelperHashes40Unchanged`는 seal coverage를 가리킨다. dictionary 항목 수가 40개라는 뜻으로 사용하지 않는다.

초기 readiness false와 v1 archive 36개 및 source-only v2 index 40개를 보존했다. source-only 검사 교정과 root의 archive index 파일명 오류를 기록했다. root pre-lease observer의 namespace 오류와 실제 호출 전 code replacement 불일치도 보존했다. helper와 실행 조건은 바꾸지 않았다. 이 관측 도구 오류를 앱/source 실패로 분류하지 않는다.

## 정리와 lease 반환

최종 자원 관측 시각은 `03:14:39 KST`다. 기존 Simulator 2개는 Booted 상태를 유지했다. 전용 iOS26 Simulator는 Shutdown 상태를 유지했다. 기존 GUI와 Watchman을 보존했다. 원본 process 식별자는 비공개 packet에 보존했다. 8081 listener가 없었다. 기존 adb5037 server를 확인한 뒤 device 목록이 비어 있음을 확인했다. native/Emulator process는 0개다.

이번 실행에서 앱·Simulator·Emulator·Gradle·adb reverse를 시작하지 않았다. own Metro는 bootstrap 전에 이미 종료했다. 추가 앱 삭제와 기기 종료는 필요하지 않았다. cleanup과 strict 사후 감사는 PASS다. 사용자 source와 global plugin·도구 선택·SDK·runtime·권한을 보정하지 않았다.

초기 grant는 `granted` bytes를 그대로 보존했다. cleanup 당시 `rootReleaseConfirmed=false`도 역사로 유지했다. 반환 요청 뒤 root는 별도 `root-release-message-receipt.json`으로 `RELEASED`를 확정했다. SHA256은 `c47f3927ba09cee036027d26af80cd340bc07320b65bb4492445cd3992979883`다. 추가 실제 실행 권한은 없다. 새 plugin 조건은 별도 결정과 새 실행이 필요하다.

## 원본 packet 무결성

| 원본 | bytes | SHA256 |
| --- | --- | --- |
| REPORT.md | 3,617 | `135d2b6e8961e53d755fabcb24f416c00be7109c5971538ac76b4b7813686d3a` |
| manifest.json | 12,198 | `aab9d0d26353c64807b3007b37f146920fa6ff8c2f846ee77d814178d355ea55` |
| SHA256SUMS | 12,524 | `0499018278e3eadbef18e1fbe505d26654e93d3ba60c4e4ec5be706bd2421f92` |

index 122개 항목과 index 포함 123개 파일의 크기/hash가 모두 일치한다. 논리 inventory는 top-level 83개, v1 archive 37개(index 포함), pre-root-release core 3개다. bytecode와 `.DS_Store`는 제외한다. pre-root-release core도 별도 보존했다. 이전 attempt-05~09 index는 67·88·106·129·109개로 그대로다. 원본 packet은 공개 문서 작성 전에 고정했다. 이후 수정하지 않았다. 독립 raw 검토의 material finding은 0개다.

최소와 OSS의 새 양플랫폼 native·install·launch·첫 화면 및 각 독립 fresh 인계가 남아 있다. 실제 Runstir CLI/GUI reproducer와 Mattermost 준비 보정 유지 검증도 남아 있다.

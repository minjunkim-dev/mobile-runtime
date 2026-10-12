# ADR-0032: RN 준비 입력의 mise identity를 공식 raw asset으로 고정한다

## 상태

채택. 사용자는 2026-10-12에 아래 최소 identity 범위와 source-only 준비 조건을 확정했다. 실제 실행 권한은 없다. 이 결정은 [ADR-0026](0026-rn-original-plugin-preparation.md)의 기존 mise identity 한 개를 부분 재결정한다. [ADR-0027](0027-rn-mise-state-metadata-links.md)의 metadata 범위와 [ADR-0031](0031-rn-observer-loop-lifecycle-diagnostics.md)의 세 진단 field 및 모든 원래 guard는 유지한다. 범위는 새 identity 채택과 정책·helper의 source-only 준비뿐이다. 이 범위 확정으로 실제 실행을 재개하지 않는다.

## 배경과 필수 STOP

attempt-20은 원본 source clone과 npm 준비 및 최소 source 55개·세 lock 감사와 early Metro HTTP 및 소유 Metro 정리를 통과했다. 다음 `prepare_frozen_stage`의 outer helper는 exit `1`이었다. 원본 `ruby_preparation.begin`의 190행 identity assertion에서 중단했다. Ruby consumer와 mise context는 생성하지 않았다. 후속 Ruby 준비·Pods·native·device·Mattermost·독립 fresh는 시작하지 않았다. 원본 실패와 packet은 보존한다. 이전 성공과 source-only memory 및 CI는 이 필수 STOP을 상쇄하지 않는다.

해당 원본 assertion은 `MISE.is_file() and not MISE.is_symlink() and digest(MISE.read_bytes()) == MISE_SHA`다. E19와 E20의 `begin` 전체 AST와 mise 경로 및 SHA 상수와 frozen caller AST는 같다. 새 observer 진단에 도달하기 전에 실패했다. E20 caller 회귀나 새 observer query가 이 실패를 만들었다는 source 근거는 없다.

승인한 SHA는 `d225d1c8ef2934a86be93692a19365fb1df1cd6958a0af7b85909514e0c608a7`이다. 실패 뒤 읽기 캡처의 실제 SHA는 `f5171e341518a57e8c4e9280e28443e35d66212c51164c83be76794e0a78b014`다. 크기는 `127277984` bytes다. 캡처는 같은 canonical 경로의 regular file과 non-symlink를 확인했다. 파일 bytes가 승인한 identity와 다르다.

190행은 세 조건을 결합한 assertion이다. 실패한 개별 short-circuit operand를 원자적으로 기록하지 않았다. 사후 파일 캡처는 실패 당시 상태와 같은 원자적 snapshot이 아니다. 따라서 변경 주체와 시점 및 실패 중 파일 교체 여부를 확정하지 않는다. SHA mismatch가 사후 읽기에서 확인됐다는 사실과 원본 assertion 실패를 구분한다. 같은 경로의 업데이트·재설치·교체와 같은 version의 내용 변경 또는 검사 사이 상태 변화는 가설이다. 실제 원인은 미확정이다.

제한한 local binary 위치 세 후보를 읽었다. 승인한 `d225…` copy는 찾지 못했다. 이 결과는 허용한 위치 안의 결과다. 전체 host의 부재를 증명하지 않는다. 별도 Homebrew binary는 다른 SHA였다. Homebrew binary로 자동 교체하거나 경로를 다시 선택하지 않는다.

## 확인한 공식 identity와 한계

[공식 release API](https://api.github.com/repos/jdx/mise/releases/tags/v2026.10.7)의 raw asset `mise-v2026.10.7-macos-arm64`는 SHA-256 `f5171e341518a57e8c4e9280e28443e35d66212c51164c83be76794e0a78b014`와 size `127277984`를 게시한다. 현재 선택 파일의 읽기 SHA와 크기가 이 두 값과 exact다. archive SHA를 내부 binary SHA로 사용하지 않았다. 이 조사에서 asset binary를 다운로드하거나 실행하지 않았다. [공식 release](https://github.com/jdx/mise/releases/tag/v2026.10.7)와 [raw asset pointer](https://github.com/jdx/mise/releases/download/v2026.10.7/mise-v2026.10.7-macos-arm64)를 구분한다.

공식 tag object `dd2b17c346d1165fb7374c0eb5c6400c7326b7f7`은 commit `4599c53b4286ff101de876f8122feec0797b48b2`를 가리킨다. [pinned Cargo.toml:19–21](https://github.com/jdx/mise/blob/4599c53b4286ff101de876f8122feec0797b48b2/Cargo.toml#L19-L21)은 package version `2026.10.7`을 선언한다. [pinned version.rs:8–20](https://github.com/jdx/mise/blob/4599c53b4286ff101de876f8122feec0797b48b2/src/version.rs#L8-L20)은 `cfg!(debug_assertions)`일 때 `-DEBUG` suffix를 붙인다.

현재 파일의 정적 Mach-O 정보는 arm64 executable이다. 내장 code signature 구조가 있다. signature 검증은 수행하지 않았다. 내장 strings에 `2026.10.7-DEBUG` 후보가 있다. 내장 후보만으로 runtime version 출력이나 DEBUG 실행 profile을 확정하지 않는다. 공식 raw asset의 게시 digest 대응은 확인했다. 설치 주체·설치 방법·변경 시점과 실제 version 출력은 미확정이다. 별도 SHASUMS256.txt와 signature의 독립 검증도 이 조사에서 완료하지 않았다.

ADR-0026의 `2026.10.1-DEBUG` 후보와 `d225…`는 당시 원본 identity 증거다. ADR-0026과 ADR-0027의 `v2026.10.1` source pointer도 당시 정적 근거다. 이 결정으로 과거 기록을 새 version으로 고치지 않는다. 이전 DEBUG binary와 tagged source의 전체 동일성은 미확정이었다. 그 미확정을 새 공식 asset의 runtime 동등성으로 승계하지 않는다. 새 package version을 이유로 metadata·trust·shared lookup의 실제 동작이 같다고 주장하지 않는다.

## 확정한 최소 준비 입력 범위

대상 표본은 최소 RN `b62e3a4d5e7cfc05d7d948a5a4e30f0cc6a82bb4`와 Mattermost `c2fe3beda22befd2178dce431793c09111ed903e`다. baseline과 각 독립 fresh의 네 clone 역할을 유지한다. 새 설치나 새 경로 선택 없이 현재 canonical mise 파일의 아래 identity 한 개만 부분 재결정한다.

| 항목 | 확정한 값 또는 조건 |
| --- | --- |
| 기존 identity | `d225d1c8ef2934a86be93692a19365fb1df1cd6958a0af7b85909514e0c608a7` |
| 새 identity | `f5171e341518a57e8c4e9280e28443e35d66212c51164c83be76794e0a78b014` |
| 공식 raw asset | `v2026.10.7`의 `mise-v2026.10.7-macos-arm64` |
| 확인한 파일 크기 | `127277984` bytes |
| 선택 경로 | 기존 canonical mise 파일 경로를 유지한다. 공개 문서에는 역할만 기록한다. |
| 파일 조건 | 기존 regular file·non-symlink·canonical 경로·정확한 SHA 검사를 유지한다. |
| 실제 version 출력과 DEBUG profile | 미측정으로 유지한다. 새 version query나 version 통과 guard를 추가하지 않는다. |

이는 원래 tool identity 조건의 변경이다. ADR-0031의 세 진단 field 승인에 자동 포함하지 않는다. 사용자 결정 없이 `MISE_SHA`를 새 값으로 바꾸거나 현재 attempt를 재개하지 않는다. 새 mismatch와 unknown은 계속 STOP이다. 다른 SHA나 version을 자동 허용하지 않는다.

## 정확한 helper 도달 범위

E20의 source-only map 46개를 조사했다. production의 기존 `MISE_SHA` literal은 `ruby_preparation.py:10` 한 곳이다. `PLAN.md:156`도 같은 승인 digest를 설명한다. `ruby-preparation-memory-selfcheck.py`는 공통 상수를 사용해 context를 만든다. 별도 `d225…` fixture literal은 없다. E20 helper에는 `MISE_VERSION`과 `2026.10.1` literal version guard 및 mise version query argv가 없다.

semantic production 변경 범위는 `MISE_SHA` 상수 한 곳뿐이다. 다음 공통 producer와 guard는 변경하지 않는다.

1. `prepare_frozen_stage`의 네 clone과 최소만 사용하는 `bundler_bootstrap`의 두 clone은 원래 `begin`을 호출한다. 원래 caller·argv·환경·cwd·순서를 유지한다.
2. `begin`은 원래 파일 identity assertion을 유지한다. 새 준비에서는 새 identity를 새 context의 `miseSha256`에 기록한다. 이전 context나 receipt를 새 identity로 다시 라벨링하지 않는다.
3. `context_matches`는 공통 상수와 context digest의 exact equality를 유지한다. observer의 `receipt_passes`와 `run_step`의 downstream authorization은 같은 판정을 소비한다.
4. bootstrap prerequisite·consumer와 prefix receipt 및 generated Pods prerequisite와 Pod cwd metadata도 같은 공통 receipt 판정을 소비한다. 이 consumer에 통과 예외를 만들지 않는다.
5. 공유 snapshot에는 원래 mise 파일이 명시돼 있다. `check_shared`는 원래 before/current snapshot equality를 유지한다. 선택 binary가 준비 중 다시 바뀌면 원래 공유 감사와 unknown STOP을 유지한다.

정책·PLAN·provenance 및 authority 문서 hash와 main·CI·helper map·batch·index·review·preflight binding은 새 결정에 맞춰 다시 봉인해야 한다. 이는 원본 consumer 명령과 guard를 바꾸는 권한이 아니다. 기존 memory fixture는 새 공통 상수를 소비하도록 연결한다. 새 identity positive와 이전 digest 및 altered digest 거부를 source-only seam에서 확인한다. E20 원본 helper·packet·PLAN·초기 봉인과 정정 봉인을 모두 보존한다.

## 유지하는 조건

표본별 원본 Node·Ruby·Bundler·CocoaPods·Gradle 및 native 선언 버전을 유지한다. 원본 Ruby plugin과 global config·tools 선택 및 clone별 private 환경과 shared read-only fallback을 유지한다. source·lock·graph와 원본 hook 및 recipe를 유지한다. 최소 source 55개·세 lock과 Mattermost Hermes 한 값 및 generated mixed Debug 12값과 원본 app·Release 보존 조건을 유지한다.

원본 argv·환경·cwd·명령 순서와 여섯 Pod recipe 및 own launcher 조건을 유지한다. executable·identity·ancestry·환경·cwd query와 FFI·ABI·errno·sampling·sleep·delay를 유지한다. ADR-0031의 세 진단 field와 기존 오류 목록·predicate 및 모든 필수 STOP을 유지한다. 추가 syscall·poll·clock·retry·오류 무시와 source patch를 허용하지 않는다.

새 identity 채택 과정에서 mise install·download·self-update·전역 파일 변경·global shim 변경·새 plugin 설치·추가 trust를 수행하지 않는다. 현재 파일이 확정한 identity와 달라졌으면 자동 복구나 재다운로드 없이 STOP한다. shared·host·metadata 감사 범위를 넓히거나 기존 unknown을 통과시키지 않는다. 새 공식 배포물의 선택이 기존 recipe 안에서 허용 밖 metadata나 shared write를 만들면 그대로 STOP한다.

## 현재 자원 조건과 실제 권한의 경계

이 결정의 초안 작성 시 Root의 최신 읽기 관측은 원래 보존 대상 GUI의 부재와 ADB listener의 부재를 기록했다. Root의 원래 fresh resource preflight 전체 판정은 false다. 두 관측을 같은 실패 원인으로 분류하지 않는다. 이 결정의 작성자는 실제 resource를 다시 조회하지 않았다. 해당 현재 자원 상태는 mise identity 대응과 별개다.

이 결정은 원래 resource predicate를 바꾸지 않는다. 이전 GUI·ADB·Simulator·Emulator·Metro snapshot을 현재 snapshot으로 자동 rebasing하지 않는다. 새 GUI를 띄우거나 ADB daemon을 시작해 이전 snapshot을 복구하지 않는다. 기존 소유자와 foreign resource 보존 조건을 바꾸지 않는다. 현재 snapshot의 다른 상태를 새 허용값으로 helper에 넣지 않는다.

새 helper 준비가 완료돼도 실제 실행 권한은 없다. 원래 fresh resource predicate와 최신 preflight 및 새 단독 lease는 별도의 실제 실행 필수 조건이다. 현재 false 판정이 남으면 실제 실행을 계속 중단한다. 자원 조건을 바꾸려면 구체적 범위와 증거를 가진 별도 정책 결정이 필요하다. 새 identity 승인으로 그 결정을 대신하지 않는다. 다음 실제 제안이 성공할 것이라고 약속하지 않는다.

## source-only 준비와 이후 gate

1. E20 실패 checkpoint를 먼저 보존하고 공개한다. 사용자는 독립 검토한 초안의 범위를 확정했다. 같은 attempt에서 pin을 바꾸거나 재시도하지 않는다.
2. 확정한 새 정책을 main에 반영한다. 기존 ADR-0026·0027의 역사 증거와 미확정을 유지한다. 필요한 frontier 참조만 접합한다.
3. 새 source-only helper·PLAN·source/output root와 authority binding을 고정한다. 실제 source clone·mise·Ruby·npm·Pods·Metro·native·기기를 실행하지 않는다. 새 실제 grant나 resource lease를 만들지 않는다.
4. source와 AST로 상수 한 곳의 identity 변경과 공통 producer·receipt·guard 접합을 독립 검토한다. 나머지 source·version·plugin·환경·argv·query·관측·순서·guard가 같은지 확인한다. memory에서는 실제 entrypoint와 persistent write를 거부한다.
5. 새 identity positive와 이전 identity·unknown·altered digest 거부 및 shared drift STOP을 확인한다. 현재 정책과 helper·PLAN·map·batch·index·review·preflight의 exact binding을 확인한다. source-only PASS를 실제 준비나 첫 화면 PASS로 쓰지 않는다.
6. 실제 재개는 이 범위 확정과 분리한다. 원래 fresh resource 조건과 최신 preflight 및 새 단독 lease를 충족해야 한다. 자원 조건을 변경해야 하면 별도 결정 전까지 중단한다. 그 경계를 통과하는 별도 실제 제안에서도 두 새 baseline의 iOS·Android 첫 화면 네 개 뒤 각 독립 fresh를 검증하는 기존 계약을 유지한다.

[ADR-0020](0020-rn-baseline-prepared-input.md)의 원본 failure 보존과 허용 밖 입력 변경 STOP을 유지한다. 정책·문서·memory·CI는 실제 frozen·native·첫 화면·fresh 성공을 증명하지 않는다. 실제 Runstir CLI·GUI gate는 후속이다. #212와 PR #236은 열린 상태를 유지한다.

## 확정한 답

후속 [ADR-0033](0033-rn-gui-adb-resource-preparation.md)은 GUI 상태와 ADB phase별 receipt·ownership·STOP·CLEANUP_PENDING 계약의 문서 및 source-only memory 모델 준비만 채택한다. 실제 resource state 적용·startup·snapshot·hostwrite·재개와 원본 resource predicate 변경은 포함하지 않는다. 이 결정의 실제 권한 경계와 미해결 frontier는 그대로 유지한다.

사용자는 현재 같은 canonical mise 경로의 identity를 공식 `v2026.10.7` raw macos-arm64 asset과 exact인 `f517…`으로 고정하고 새 정책·helper의 source-only 준비만 진행하는 최소 범위를 확정했다. 새 설치와 경로 변경 및 actual 재개 권한은 포함하지 않는다. 원래 resource 조건 변경은 별도 결정으로 남긴다. 기존 failure와 모든 guard 및 unknown STOP을 유지한다.

---
status: accepted
---

# ADR-0027: 원본 mise가 생성하는 제한된 STATE metadata link를 준비 입력으로 허용한다

사용자는 2026-10-11에 아래 추가 준비 범위와 새 실행 조건을 확정했다. [ADR-0026](0026-rn-original-plugin-preparation.md)의 private symlink와 trust 기록 경계만 아래 범위에서 다시 결정한다. 정책 main 반영과 helper 독립 검토 및 새 단독 lease 전에는 실제 실행하지 않는다. attempt-11의 실패를 사후 PASS로 바꾸지 않는다.

## 확인한 사실

attempt-11의 최소 표본 `b62e3a4d5e7cfc05d7d948a5a4e30f0cc6a82bb4`는 새 clone, 원본 npm, strict tracked55/세 lock 감사와 원본 Metro HTTP200을 통과했다. 원본 mise 선택 명령은 exit0였다. 사후 private output guard가 STATE symlink5개를 거부했다. Ruby facts, Bundler bootstrap, frozen Bundle, Pods, native, Mattermost와 두 fresh는 미시작이다. 공유 경로의 최종 변경은0이었다. lease는 RELEASED다.

symlink4개는 `tracked-configs`에 있다. 대상은 해당 clone의 원본 `package.json`과 `Gemfile`, 기존 host의 `package.json`과 global mise `config.toml`이다. 나머지1개는 `trusted-configs`의 기존 host home target 기록이다. 사전 shared snapshot에도 같은 trust marker의 basename, target, mode가 있었다. private state에는 새 authorization record가 생겼다. 실효 authorization의 완전한 동일성은 측정하지 않았다.

고정 Mattermost `c2fe3beda22befd2178dce431793c09111ed903e`의 기존 baseline에서 `package.json`, `Gemfile`, `.ruby-version`, `.node-version`, `.nvmrc` checkout bytes와 pinned Git blob이 일치했다. `.tool-versions`와 `.mise.toml`은 원본에 없다. 이 확인은 새 Mattermost baseline 또는 fresh 준비 성공 증거가 아니다.

공식 tagged `v2026.10.1` source에서 tracked link는 config 경로를 기록한다. 소비자는 `read_link`로 원본 경로를 얻는다. trusted link는 설치 경로 alias가 아니지만 `is_trusted`가 authorization 판정에 사용한다. tagged source의 `Exec`는 implicit trust 대상이다. 실제 선택한 DEBUG binary의 정확한 내부 분기와 tagged source의 완전한 동일성은 미확정이다. [tracking.rs](https://github.com/jdx/mise/blob/v2026.10.1/src/config/tracking.rs), [config parsing](https://github.com/jdx/mise/blob/v2026.10.1/src/config/mod.rs#L3403), [trust check와 생성](https://github.com/jdx/mise/blob/v2026.10.1/src/config/config_file/mod.rs#L483), [implicit trust](https://github.com/jdx/mise/blob/v2026.10.1/src/cli/mod.rs#L452).

## 결정

두 표본의 새 baseline과 독립 fresh에서 원본 mise가 자동 생성하는 다음 STATE metadata link만 허용한다. helper가 link를 직접 생성하거나 이전 state를 복사하지 않는다. 원본 source, 도구 버전, plugin, config 선택과 명령 순서는 유지한다. 새로운 CLI trust 명령은 허용하지 않는다.

`<CLONE>`은 해당 고정 SHA의 독립 clone이다. `<PRIVATE>`는 그 clone의 원본 ignore 범위 안에 있는 `vendor/bundle/mise-preparation`이다. `<HOST_HOME>`은 기존 canonical host home이다. 실제 host 경로와 marker 식별자는 비공개 receipt에서 고정한다.

| 생성 위치 | 허용 target | 필수 대응 |
| --- | --- | --- |
| `<PRIVATE>/state/tracked-configs/<entry>` | 최소: `<CLONE>/package.json`, `<CLONE>/Gemfile` | 해당 SHA의 원본 regular file과 source 감사 |
| 같은 위치 | Mattermost: `<CLONE>/package.json`, `<CLONE>/Gemfile`, `<CLONE>/.ruby-version`, `<CLONE>/.node-version`, `<CLONE>/.nvmrc` | 해당 SHA의 원본 regular file과 source 감사 |
| 같은 위치 | 기존 `<HOST_HOME>/package.json`, 기존 global mise `config.toml` | 최초 probe 전 고정한 정확한 canonical regular file과 byte/type/mode |
| `<PRIVATE>/state/trusted-configs/<marker>` | 기존 `<HOST_HOME>` 하나 | 최초 probe 전 shared에 존재한 동일 basename/target/mode의 trust marker와 정확한 canonical directory |

표는 허용 상한이다. 모든 후보 link가 생성되어야 한다고 요구하지 않는다. 각 link entry는 해당 STATE 하위의 직접 자식이어야 한다. duplicate target, 다른 target, dangling link, 간접 symlink 경로와 설명할 수 없는 entry를 허용하지 않는다. 허용 target 목록과 원본 대응을 최초 mise probe 전에 clone별 receipt로 고정한다. 예상 밖 link가 나오면 중단한다.

trusted link는 새 private authorization record로 식별한다. 기존 shared marker와 대응된다고 해서 실효 authorization의 완전한 동일성을 주장하지 않는다. 기존 home marker만으로 모든 하위 clone의 trust를 입증했다고 주장하지 않는다. 이번 결정은 위 정확한 record의 자동 생성을 허용한다. 새로운 trust target, 별도 trust CLI 명령과 global trust 변경은 허용하지 않는다.

`.monorepo`, `.hash`, ignored trust state와 같은 추가 authorization metadata는 이 허용에 포함하지 않는다. 위 정확한 record 밖의 authorization state가 생기거나 바뀌면 중단한다. 일반 private regular file 허용으로 이 경계를 우회하지 않는다.

## 유지하는 경계

1. private root와 DATA/CACHE/STATE/TMP/SHIMS는 canonical 독립 경로로 유지한다. 경로 자체와 조상 경로를 symlink로 만들지 않는다. 다른 clone 또는 shared 설치 root를 primary에 연결하지 않는다.
2. metadata link 허용을 tool 설치, install store, plugin, download, shim 또는 command wrapper의 symlink 허용으로 확대하지 않는다. 기존 설치 산출물과 private state를 복사하지 않는다.
3. helper는 metadata 감사에서 `lstat`과 `readlink`를 사용한다. source와 host target은 읽기 감사만 수행한다. helper가 target에 쓰거나 link를 제거·교체하지 않는다. 원본 mise의 metadata 생성은 원본 명령 실행으로 식별한다. 모든 소비자의 일시적 write-through 부재를 주장하지 않는다.
4. ADR-0026의 원본 Ruby/plugin, six-env 선택, shared lookup, 실제 prefix/pkgconfig proof와 consumer 관측 경계를 유지한다. 최소만 ADR-0025 Bundler bootstrap을 사용한다. Mattermost의 기존 Hermes 한 값과 mixed12 준비 범위는 유지한다.
5. 원본 Node/npm/Metro/native/기기 조건을 유지한다. 추가 도구 설치, plugin 설치, migration, update와 source·lock·버전 변경을 허용하지 않는다.

## 감사와 새 실행 조건

최초 mise·Ruby probe 전에 기존 shared snapshot과 host target receipt를 고정한다. 기존 marker는 이미 있어야 한다. 최소 두 원본 파일과 Mattermost 다섯 원본 파일은 해당 clone의 pinned source 감사에 연결한다. host file은 실제 canonical path, byte hash, kind와 mode를 기록한다. host home directory는 canonical path, kind와 mode만 기록한다. home 전체 내용의 불변을 요구하거나 주장하지 않는다.

각 승인 Ruby 준비 consumer의 전후 감사에서 shared 경로와 허용 host file의 byte/type/mode를 비교한다. metadata link의 entry 위치, 실제 target, canonical target, type와 mode를 기록한다. private의 나머지 출력과 기존 설치·plugin·shim·wrapper·cache·state·config의 감사도 유지한다. shared 최종 snapshot 불변은 일시적 쓰기 부재나 OS 쓰기 격리를 증명하지 않는다.

정책 main 반영, 전체 helper 독립 검토와 새 root preflight 및 단독 lease 뒤 새 실행을 시작한다. 이전 attempt의 clone, private state, node_modules, vendor/bundle, Pods와 build를 재사용하지 않는다. 원본 raw download의 기존 검증된 재사용 정책만 유지한다. 두 새 baseline의 iOS·Android 네 첫 화면을 먼저 확인한다. 이후 각 독립 fresh를 준비한다. 실제 Runstir 검증은 후속 gate다.

필수 실패, unknown, 미허용 target, 원본 대응 누락, host/shared 변경이나 새로운 trust target이 나오면 모든 후속 실제 실행을 중단한다. 최초 receipt를 보존하고 소유자 cleanup만 수행한다. link나 helper를 바꿔 같은 실행을 재개하지 않는다. 조건 변경에는 별도 결정과 새 실행이 필요하다. [ADR-0020](0020-rn-baseline-prepared-input.md).

## 미확정과 범위 확정

현재 미확정 항목은 두 표본에서의 실제 Ruby 선택, observer 호환성, plugin 효과, Pod runtime 환경과 각 내부 reshim exit다. private authorization record의 실효 범위가 기존 실행과 완전히 같은지도 미측정이다. 이 결정은 메모리·문서·CI 통과를 실제 baseline 성공으로 바꾸지 않는다.

사용자는 위 정확한 STATE metadata link와 기존 trust target의 자동 생성 record 범위 및 새 실행 조건을 확정했다.

확정한 범위에서 원본 mise 동작을 유지하고 최소·Mattermost의 두 baseline과 독립 fresh를 다시 확인한다. 이 확정만으로 실제 실행을 시작하지 않는다. 정책 main 반영과 helper 검토 및 새 lease가 필요하다.

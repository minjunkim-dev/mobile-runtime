---
status: accepted
---

# ADR-0026: 원본 Ruby plugin을 유지하고 mise 준비 경로를 clone별로 분리한다

사용자는 2026-10-11에 아래 추가 준비 범위와 새 실행 조건을 확정했다. [ADR-0025](0025-rn-clone-local-declared-bundler.md)의 plugin 입력 거부 조건과 mise 환경 유지 조건을 아래 범위에만 다시 결정한다. 나머지 준비 조건과 필수 실패 중단 조건은 유지한다. 정책 main 반영과 helper 독립 검토 뒤 새 단독 lease로만 실행한다. 범위 확정은 설치 또는 baseline 성공 증거가 아니다.

## 확인한 사실

[attempt-10](https://github.com/minjunkim-dev/mobile-runtime/blob/55bdbae541191b4412c13f7dd4dcb03d58e8dae8/docs/rn-baseline-212-attempt-10.md)은 최소 표본의 원본 clone·npm·Metro HTTP 200을 통과했다. Ruby LOAD_PATH에서 plugin 하나를 발견했다. 입력 guard가 거부했다. gem 다운로드·설치·activation·frozen Bundle·Pods·native는 시작하지 않았다. lease는 RELEASED다.

최소 표본의 Ruby `3.4.11`과 Mattermost의 Ruby `3.2.11`에서 같은 원본 plugin을 읽었다. 설치 root에 대한 상대 경로는 `lib/ruby/site_ruby/rubygems_plugin.rb`다. 각 파일은 regular file이며 1553 bytes다. SHA-256은 `6cedbcf33ae6de36e2569a3a181735031e05e1e5c52745d0d725d8b665f0ac5c`다. plugin은 Ruby prefix의 `lib/pkgconfig`를 `PKG_CONFIG_PATH`에 추가한다. gem 설치와 Bundler install 경로에서 plain `mise reshim`을 호출한다. plugin은 그 exit를 검사하지 않는다. [mise Ruby 문서](https://mise.jdx.dev/lang/ruby.html)

선택 PATH의 기존 mise binary는 정적 bytes SHA-256 `d225d1c8ef2934a86be93692a19365fb1df1cd6958a0af7b85909514e0c608a7`다. bytes에 `2026.10.1-DEBUG`와 shared lookup symbols가 있다. 실행 버전과 tagged source의 완전한 동일성은 확인하지 않았다. 별도 Homebrew binary로 교체하지 않는다. 기존 mise plugins 디렉터리는 없었다. 제한된 config 조사에서 global config의 `[env]`는 없었다. 이는 host 전체 입력 부재 증거가 아니다.

`MISE_SHIMS_DIR` 하나로는 command wrapper·cache lock·config tracking의 쓰기를 분리하지 못한다. 기존 설치 root를 writable primary `MISE_INSTALLS_DIR`로 지정하면 legacy metadata migration이 발생할 수 있다. 기존 plugins root에서도 삭제 경로가 있다. 이 결정은 그 경로를 사용하지 않는다. 공식 `MISE_SHARED_INSTALL_DIRS`는 기존 설치를 읽기 전용 fallback으로 찾는다. v2026.10.1의 shared scan은 primary migration과 분리된다. [공식 설정](https://mise.jdx.dev/configuration/settings.html#shared-install-dirs), [고정 설정 source](https://github.com/jdx/mise/blob/v2026.10.1/settings.toml#L2705), [고정 설치 scan source](https://github.com/jdx/mise/blob/v2026.10.1/src/toolset/install_state.rs#L363)

## 확정 범위

최소 고정 SHA `b62e3a4d5e7cfc05d7d948a5a4e30f0cc6a82bb4`와 Mattermost 고정 SHA `c2fe3beda22befd2178dce431793c09111ed903e`의 새 baseline과 각 독립 fresh에 적용한다. 각 표본의 원본 Ruby 버전과 원본 plugin 한 개를 유지한다. plugin path·type·hash가 다르거나 추가 plugin이 있으면 중단한다. 원본 plugin의 pkg-config 동작을 보존한다. loader 차단·method override·plugin source 수정·자동 unset은 허용하지 않는다.

각 clone의 원본 ignore 범위 안에 `vendor/bundle/mise-preparation`을 독립 준비한다. 원본 ignore가 이 경로를 제외하는지 먼저 확인한다. canonical 내장 경로를 사용한다. 다른 clone·공유 경로와 겹치거나 symlink로 연결하지 않는다. 이전 설치 산출물과 private mise 디렉터리를 복사하지 않는다. 기존 tools 설치를 복사하거나 private DATA에 symlink로 이식하지 않는다.

다음 환경 선택은 해당 clone의 승인된 Ruby 준비 entrypoint에만 전달한다. 기존 npm/hook 분리 준비 절차도 유지한다. shell profile이나 global config에 저장하지 않는다. 값의 `<PRIVATE>`는 해당 clone의 `vendor/bundle/mise-preparation`이다.

| 변수 | 값 |
| --- | --- |
| `MISE_DATA_DIR` | `<PRIVATE>/data` |
| `MISE_CACHE_DIR` | `<PRIVATE>/cache` |
| `MISE_STATE_DIR` | `<PRIVATE>/state` |
| `MISE_TMP_DIR` | `<PRIVATE>/tmp` |
| `MISE_SHIMS_DIR` | `<PRIVATE>/data/shims` |
| `MISE_SHARED_INSTALL_DIRS` | 최초 receipt로 고정한 기존 mise installs root 하나 |

private primary installs·install store·plugins·downloads와 command wrapper는 private DATA의 기본 경로를 사용한다. 기존 설치 root를 primary로 연결하지 않는다. 추가 DIR·log·config·system·shared override와 backend script 입력을 감사한다. 위 선택과 충돌하거나 쓰기 경로를 설명할 수 없는 입력은 중단한다. global config와 원본 tools 선택은 유지한다. 새 mise tool 설치·plugin 설치·migration·update·trust 추가를 허용하지 않는다. 기존 global shim·wrapper·cache·state와 설치·config 경로의 변경도 허용하지 않는다. [공식 경로 문서](https://mise.jdx.dev/directories.html), [고정 환경 source](https://github.com/jdx/mise/blob/v2026.10.1/crates/mise-util/src/env.rs)

기존 mise binary와 원본 Ruby·gem·bundle launcher를 유지한다. private shim이나 bootstrap bin을 PATH 앞에 추가하지 않는다. 원본 명령의 explicit 도구 버전과 실제 executable·Ruby prefix·default gem repository를 연결한다. shared fallback이 같은 실제 도구를 선택하지 못하면 중단한다. 최신 버전 선택이나 다른 binary로 보완하지 않는다.

최소 표본의 Bundler `2.5.22` 독립 bootstrap과 공식 raw gem은 ADR-0025를 그대로 따른다. Mattermost에 bootstrap 예외를 추가하지 않는다. 같은 clone의 bootstrap installer·activation 검사·원본 frozen Bundle·원본 `bundle exec pod install --deployment`에 같은 mise 선택 환경을 전달한다. Mattermost의 기존 승인된 hook 분리 절차에서 실행하는 Bundle install·`bundle exec ruby`·plain exec Pod도 전파 대상이다. 각 entrypoint와 exec Ruby·Pod child의 실효 경로를 확인한다. 원본 pre/postinstall 전체의 새 실행이나 hook source·승인한 argv·순서 변경을 추가하지 않는다. Bundler가 내부에서 변경하는 GEM_HOME·GEM_PATH·PATH·RUBYOPT는 원본 동작으로 구분한다. Ruby prefix의 원본 pkg-config 경로도 확인한다. Metro·native·기기 명령에는 새 mise 환경을 전달하지 않는다.

## 감사와 새 실행

1. 범위를 확정하고 정책을 main에 반영한다. 외부 PLAN과 helper를 독립 검토한다. 두 Ruby/plugin, clone 경로 분리, shared lookup, 추가 override 거부, 모든 consumer 전파와 실패 차단을 확인한다. 새 단독 lease 전에는 실제 clone·gem 다운로드·설치·mise 실행·Metro·native·기기를 시작하지 않는다.
2. 새 lease에서 최초 mise·Ruby probe 전에 기존 설치·plugin·shim·wrapper·cache·state·config의 사전 감사 범위를 receipt로 고정한다. 기존 binary hash와 실행 identity를 연결한다. private 경로와 shared lookup의 실효 값을 확인한다. 원본 도구 executable과 config 선택을 비교한다. 다른 shared root 또는 system root의 도구를 선택하면 중단한다. 새 state 때문에 trust 또는 설치 상태를 확인할 수 없어도 중단한다. 사전 검사가 불명확하거나 다른 설치가 필요하면 준비 명령 전에 중단한다.
3. 원본 Ruby 준비 명령의 exit를 판정한다. 각 단계 전후에 source와 locks 및 공유 경로의 byte·type·link·mode 상태를 비교한다. private mise 산출물을 기록한다. 공유 경로의 차이와 허용 밖 산출물 또는 실효 선택 관측 `unknown`이면 모든 후속 실제 실행을 중단한다. 원본 plugin 내부 reshim의 각 exit와 호출 횟수는 미측정으로 기록한다. 별도 reshim 재실행으로 대체하지 않는다. 소비자 exit 0을 내부 hook 성공으로 표현하지 않는다. 사전·사후 감사는 최종 상태 불변 증거다. 잠시 썼다가 복원한 모든 write의 부재나 OS sandbox 격리를 주장하지 않는다.
4. 두 표본을 각각 새 내장 clone에서 시작한다. 원본 npm/hook과 early Metro를 유지한다. 최소 source 55개와 세 lock은 유지한다. Mattermost에는 ADR-0020·0021·0023의 기존 준비 범위만 적용한다. 각 표본의 iOS·Android build·install·launch·첫 화면을 직렬 확인한다. 네 baseline 첫 화면을 확인한 뒤 각 fresh를 독립 준비한다. 과거 실행 성공을 새 조건으로 승계하지 않는다.
5. 필수 소비자 실패·허용 밖 변경·필수 관측 `unknown`이면 중단한다. 우리 소유 자원만 정리한다. 최초 receipt와 실패 및 사후 source 감사를 보존한다. 다른 도구·버전·환경·source·target·flag 조건은 별도 결정과 새 실행이 필요하다.

설정 source와 정적 binary 문자열은 실제 지원 또는 격리 효과의 성공 증거가 아니다. snapshot은 filesystem write 추적이 아니다. 이 정책은 clone별 경로 선택과 최종 공유 상태 불변을 검증한다. 설치·frozen·native·첫 화면·fresh와 실제 Runstir CLI·GUI의 성공은 별도 실행 증거가 필요하다.

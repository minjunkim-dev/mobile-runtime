---
status: accepted
---

# ADR-0025: 최소 RN의 원본 Bundler를 clone별로 독립 준비한다

사용자는 2026-10-11에 추가 도구 준비 범위와 새 실행 조건을 확정했다. [ADR-0024](0024-rn-baseline-internal-volume-preflight.md)의 실패 중단과 별도 결정 조건을 유지한다. 정책 main 반영과 helper 독립 검토 뒤 새 단독 lease로만 새 실행을 시작한다. 범위 확정은 설치 또는 baseline 성공 증거가 아니다.

## 확인한 실패

attempt-09의 새 내장 최소 RN clone은 원본 source 55개와 세 lock을 보존했다. clone·checkout·npm 준비를 통과했다. 원본 Metro는 실제 HTTP `200`과 own process·port 검사에 통과했다. 첫 화면 증거는 아니다. 이후 원본 frozen `bundle _2.5.22_ install` 명령이 `can't find gem bundler (= 2.5.22) with executable bundle`로 exit `1`이었다. Pods와 native 및 기기 실행은 시작하지 않았다. 사후 source 감사와 cleanup을 통과했다. 단독 lease를 반납했다.

읽기 진단에서 선택한 Ruby 설치의 default gemspec은 Bundler `2.6.9`였다. 과거 최소 clone vendor에는 `2.5.22` gemspec이 있었다. 새 clone에는 해당 vendor specifications 폴더가 없었다. 전체 host를 검색하지 않았다. 정확한 명령의 activation 실패를 확인한 것이며 host 전체의 `2.5.22` 부재를 주장하지 않는다. 과거 vendor를 복사하거나 도구를 설치하거나 명령을 재시도하지 않았다.

최소 RN 고정 source `b62e3a4d5e7cfc05d7d948a5a4e30f0cc6a82bb4`의 `Gemfile.lock`은 `BUNDLED WITH 2.5.22`를 선언한다. 원본 `.gitignore`는 `/vendor/bundle/`을 제외한다. [RubyGems의 고정 버전](https://rubygems.org/gems/bundler/versions/2.5.22)과 [공식 metadata API](https://rubygems.org/api/v2/rubygems/bundler/versions/2.5.22.json)는 이 버전을 제공한다. 확인한 metadata는 platform `ruby`, Ruby `>= 3.0.0`, RubyGems `>= 3.2.3`, runtime dependency 0개를 선언한다.

공식 archive URL은 `https://rubygems.org/gems/bundler-2.5.22.gem`이다. metadata가 선언한 SHA-256은 `763f30d598ee58742eea29285875435ea722218d4df149de35bce37c02ce968e`다. 현재는 metadata만 읽었다. archive bytes의 다운로드·hash 확인·설치·실행은 하지 않았다.

## 확정 범위

최소 RN의 새 baseline과 독립 fresh에만 **원본 선언 Bundler `2.5.22`의 clone별 설치**를 허용한다. Ruby 선택 `3.4.11`, 원본 source·세 lock·의존성 버전·graph는 유지한다. Mattermost에는 이 설치 정책을 자동 적용하지 않는다. 최소 RN에 Mattermost의 Hermes checksum 또는 generated target 예외를 적용하지 않는다.

각 새 최소 clone의 canonical `vendor/bundle/tool-bootstrap`에 공식 gem을 독립 설치한다. 이 폴더는 원본 ignore 범위 안의 준비 산출물이다. 과거 clone과 다른 baseline 또는 fresh의 설치 산출물을 복사하지 않는다. global/user gem repository를 수정하지 않는다. Bundler·RubyGems·Ruby 업데이트와 최신 버전 선택을 금지한다.

외부 PLAN은 clone별 bootstrap 경로, 같은 선택 Ruby의 `Gem.default_dir`, installer와 launcher의 실제 경로를 고정한다. source 경로에는 ADR-0024의 내장 volume·canonical path·보호 위치 거부와 공간 기준을 적용한다. baseline과 fresh의 bootstrap은 서로 다른 경로여야 한다.

공식 raw gem archive만 cache에서 재사용할 수 있다. archive의 origin URL·metadata·실제 bytes SHA-256·크기·clone별 사용 receipt를 연결한다. 기존 cache를 덮어쓰지 않는다. URL 변경과 비공식 origin 또는 hash·version·platform·dependency 불일치 및 관측 `unknown`이면 중단한다. Ruby metadata의 요구 조건도 실제 선택 도구와 비교한다. 검증한 raw archive를 다시 설치하는 것은 설치된 gem 폴더 복사와 다르다.

[RubyGems install 문서](https://guides.rubygems.org/command-reference/#gem-install)의 `--local`, `--install-dir`, `--no-document`로 설치 범위를 제한한다. 선택 Ruby의 기존 gem installer에 `gem --norc install --local <VERIFIED_ARCHIVE> --install-dir <CLONE_BOOTSTRAP> --no-document`를 전달한다. `--norc`는 system·user·환경 gem 설정의 추가 argv와 repository 변경을 차단한다. 이 flag는 bootstrap installer에만 추가한다. `--norc`는 plugin loading을 차단하지 않는다. `RUBYOPT`·`RUBYLIB`·`RUBYGEMS_GEMDEPS`와 허용 gem 경로의 plugin 입력을 사전에 감사한다. 정책 밖 입력이나 관측 불명은 자동 수정하거나 unset하지 않고 중단한다. `--force`, `--ignore-dependencies`, update 및 원격 의존성 설치로 실패를 우회하지 않는다.

새로 허용하는 환경 선택은 최소 RN의 Ruby 준비 명령에 한정한다. `GEM_HOME`은 해당 clone의 bootstrap이다. `GEM_PATH`는 해당 bootstrap과 같은 Ruby의 `Gem.default_dir`만 포함한다. trailing path separator와 user·다른 clone의 gem path를 허용하지 않는다. 원본 `bundle _2.5.22_ install`, `BUNDLE_FROZEN=true`, clone별 원본 `BUNDLE_PATH` 및 Pods의 frozen 원본 명령을 유지한다. 같은 clone의 후속 `bundle exec pod`에도 이 선택을 연결한다. 원본 Metro·native 명령·전역 PATH·mise·Xcode·권한·Watchman 설정은 바꾸지 않는다.

기존 Ruby의 `bundle` launcher를 유지한다. bootstrap의 `bin`을 PATH 앞에 추가하지 않는다. 같은 Ruby의 `Gem.default_dir`은 공유 repository다. 이 경로의 읽기 허용을 전역 gem 혼입 부재로 표현하지 않는다. 선택 Ruby·launcher와 실제 `Gem.path`, Bundler version·`full_gem_path`·`loaded_from`을 연결한다. installer 전후에 공유 repository의 불변을 확인한다. `bundle exec` 내부에서 Bundler가 dependency `BUNDLE_PATH`로 `GEM_HOME`을 바꾸고 `GEM_PATH`를 비우는 동작은 원본 동작이다. 외부 launcher 선택과 내부 dependency 환경을 별도로 감사한다.

## 새 실행과 감사 조건

1. 범위를 확정하고 정책을 main에 반영한다. 외부 PLAN과 helper를 독립 검토한다. 공식 archive 불일치, 다른 clone 경로, 잘못된 Bundler 버전, source 차이 및 mandatory failure 차단을 메모리에서 확인한다. 실제 설치·activation과 frozen 실행의 성공은 이 검토와 별도다. 새 단독 lease 전에는 clone·archive 다운로드·gem 설치·Metro·native·기기를 실행하지 않는다.
2. 두 표본을 모두 새 내장 clone에서 다시 시작한다. 원본 source와 npm/hook 및 원본 early Metro를 먼저 검사한다. 최소 RN의 early Metro 성공 뒤에만 해당 clone의 독립 Bundler를 준비한다. 설치·activation receipt에 Ruby와 RubyGems 버전, installer·launcher 경로, `Bundler::VERSION`과 loaded gem 경로 및 archive 연결을 기록한다. Bundler가 정확히 `2.5.22`이며 해당 clone bootstrap에서 로딩됐는지 확인한다.
3. 설치 전후와 frozen Bundle·Pods 전후에 최소 RN의 55개 tracked byte·type·Git 실행 mode·index·flags 및 세 lock을 원본과 비교한다. bootstrap 이외의 새 도구 설치를 허용하지 않는다. 원본 frozen 명령 실패나 다른 checksum 변경이 필요하면 중단한다. 실패를 앱 native 실패로 확대하지 않는다.
4. Mattermost에는 ADR-0020·0021·0023의 기존 Hermes 한 값과 mixed Debug 12값 및 ADR-0024를 그대로 적용한다. 새 baseline에서 각 표본의 iOS·Android native build·install·launch·첫 화면을 직렬 확인한다. 네 첫 화면 성공 뒤에만 두 표본의 fresh를 독립 준비한다. 최소 fresh도 공식 raw gem으로 Bundler를 새로 설치한다. attempt-09 Metro, attempt-08 native 및 과거 첫 화면을 새 성공으로 승계하지 않는다.
5. 필수 실패·허용 밖 변경·관측 `unknown`이면 모든 후속 실제 실행을 중단한다. 우리 소유 자원만 정리한다. 실패와 source 사후 감사 및 최초 receipt를 보존한다. 다른 도구·버전·환경·source·target·flag 조건은 별도 결정과 새 실행이 필요하다.

## 대안과 경계

host에 Bundler를 global 설치하면 clone별 독립 준비와 다른 작업의 도구 조건을 함께 바꾼다. 과거 vendor 복사는 fresh 독립 준비를 입증하지 못한다. 원본 lock의 Bundler 버전을 바꾸면 고정 입력을 바꾼다. 이 결정은 원본 선언 버전을 유지하면서 설치 산출물과 선택 환경을 clone에 제한한다.

설치 성공은 frozen Bundle·Pods 성공이 아니다. frozen 준비 성공은 native 또는 첫 화면 성공이 아니다. 추가 checksum 실패의 발생 여부는 미검증이다. #212는 두 표본의 양플랫폼 첫 화면과 각각의 독립 fresh 인계가 필요하다. 실제 Runstir가 이 준비를 재현하고 Mattermost 보정을 유지하는지는 후속 결정과 실제 CLI·GUI 검증 대상이다.

# ADR-0028: 최소 RN Bundler installer의 --norc 위치를 정정한다

## 상태

채택. 사용자는 2026-10-11에 최소 정정 범위와 새 실행 조건을 확정했다. 정책 main 반영과 helper 독립 검토 및 새 단독 lease 전에는 실제 실행 권한이 없다.

## 확인한 실패

attempt-12는 새 최소 RN clone에서 원본 source 55개와 세 lock을 보존했다. 원본 npm 준비와 early Metro의 실제 HTTP readiness를 통과했다. 최초 mise 선택과 ADR-0027 metadata 감사도 통과했다. 원본 Ruby bootstrap facts와 공식 Bundler archive의 gem spec consumer는 exit `0`과 guard PASS였다. 실제 Ruby prefix와 `lib/pkgconfig` 경로를 같은 clone의 consumer receipt에 연결했다.

이후 최소 Bundler installer는 원본 argv의 `gem --norc install` 순서에서 exit `1`이었다. 로그는 `ERROR:  Invalid option: --norc. See 'gem --help'.`이다. activation, frozen Bundle, Pods, native build, 두 플랫폼 첫 화면, Mattermost와 fresh는 시작하지 않았다. 같은 attempt에서 flag와 helper를 수정하거나 재시도하지 않았다.

installer의 observer는 조건에 맞는 관측 세 개와 별도 `RuntimeError` 한 개를 기록했다. 실제 실패 syscall과 분기는 기록하지 않아 원인은 unknown이다. 짧은 process 종료 중 관측 race는 가능한 설명이다. 실제 원인으로 확정하지 않는다. installer exit `1`과 observer 실패를 별도로 보존한다.

최종 source·lock·metadata·host·shared와 같은 Ruby repository의 사후 감사는 PASS였다. 소유 Metro를 정리했다. root는 기존 Simulator 두 개, 전용 Simulator Shutdown, GUI, Watchman, 빈 Metro 포트와 기존 빈 ADB 상태를 확인하고 lease를 RELEASED로 기록했다. 성공한 준비 단계는 native 또는 baseline 성공 증거가 아니다.

## 확인한 source

선택한 원본 Ruby `3.4.11`의 설치 source는 RubyGems `3.6.9`를 선언한다. 원본 `bin/gem`은 argv를 `GemRunner`에 전달한다. 설치 source의 `Gem::ConfigFile`은 전체 argv에서 `--norc`를 확인해 system·user·환경 설정의 병합을 생략한다. 이 flag를 argv에서 제거하지 않는다. `Gem::CommandManager`는 첫 token이 `--norc`이면 확인한 오류와 exit `1`을 발생시킨다. 첫 token이 `install`이면 install command를 선택한다. 공통 option parser가 뒤의 `--norc`를 처리한다.

공식 [RubyGems v3.6.9 ConfigFile](https://github.com/rubygems/rubygems/blob/v3.6.9/lib/rubygems/config_file.rb), [CommandManager](https://github.com/rubygems/rubygems/blob/v3.6.9/lib/rubygems/command_manager.rb)와 [Command](https://github.com/rubygems/rubygems/blob/v3.6.9/lib/rubygems/command.rb)도 이 경계를 보여 준다. 같은 version 문자열만으로 설치 source 전체와 공식 tag의 byte 동일성을 주장하지 않는다.

`--norc`는 plugin loading을 차단하지 않는다. 설정 파일의 읽기 자체를 차단하는 flag로 표현하지 않는다. 원본 plugin과 관련 준비 조건은 ADR-0026과 ADR-0027을 유지한다.

## 결정한 최소 정정 범위

최소 RN의 새 baseline과 독립 fresh에서 Bundler bootstrap installer의 `install`과 `--norc` 위치만 교환한다.

```text
기존: <ORIGINAL_GEM> --norc install --local <VERIFIED_ARCHIVE> --install-dir <CLONE_BOOTSTRAP> --no-document
정정: <ORIGINAL_GEM> install --norc --local <VERIFIED_ARCHIVE> --install-dir <CLONE_BOOTSTRAP> --no-document
```

ADR-0025의 installer 예시와 새 helper·PLAN·exact argv 검사를 같은 정정 순서로 맞춘다. 원본 Ruby·RubyGems·Bundler 버전, installer·launcher, 공식 archive, 설치 목적지, 나머지 flag, clone별 mise 환경 여섯 값과 `GEM_HOME`·`GEM_PATH`를 유지한다. 원본 source·lock·plugin·frozen 명령과 Mattermost 준비 범위를 유지한다. global 설치, update, flag 제거, 다른 launcher 또는 retry 우회로 확대하지 않는다.

observer의 필수 판정과 unknown STOP을 유지한다. 새 helper는 기존 관측 지점에 고정된 비식별 stage·errorCode를 기록할 수 있다. raw argv·환경·예외 원문을 추가 저장하지 않는다. 관측 query·sampling·delay·통과 조건을 바꾸지 않는다. 이 진단은 실제 race 원인 확정이나 실패 상쇄가 아니다.

[ADR-0029](0029-rn-observer-executable-errno.md)는 기존 executable 조회의 함수·prototype·errno 설정을 유지한 private errno copy 초기화·실패 직후 읽기·고정 enum 기록만 별도로 허용한다. 나머지 관측 조건과 필수 STOP 및 새 실행 조건은 유지한다.

## 새 실행 조건

1. 확정한 정책을 main에 반영한다. 문서와 새 helper를 독립 검토한다. 최초 attempt-12 receipt와 공개 실패 증거를 변경하지 않는다.
2. 새 source/output root와 고정 helper·정책 hash를 준비한다. root의 최신 preflight와 새 단독 lease를 받는다. 이전 lease와 prepared clone을 재사용하지 않는다.
3. 두 표본의 새 baseline을 독립 준비한다. 원본 source·early Metro·metadata·host·shared 감사와 최소 Bundler 설치·activation·frozen 검사를 유지한다. 두 표본의 iOS·Android 첫 화면 네 개를 확인한 뒤 각각의 독립 fresh를 준비한다.
4. 필수 실패, unknown, 허용 밖 변경이나 추가 authorization 상태가 나오면 후속 실행을 중단한다. 소유 자원만 정리한다. 최초 receipt와 사후 감사를 보존한다. 다른 조건은 별도 결정과 새 실행이 필요하다.

## 미검증 범위

정정 순서의 실제 installer 성공은 미검증이다. observer의 실제 오류 원인도 unknown이다. 실제 metadata 생성의 전체 실효 trust 동일성, runtime Ruby 환경과 plugin·내부 reshim 효과, frozen·Pods·native와 baseline/fresh 성공은 이 정적 조사로 입증하지 않는다. 실제 Runstir의 준비 재현과 Mattermost 보정 유지는 후속 gate다. #212와 PR #236은 열린 상태로 유지한다.

## 확정한 답

사용자는 위의 installer 두 token 위치 정정과 비식별 진단 범위 및 새 실행 조건을 확정했다. 관측과 실패 STOP을 완화하지 않는다.

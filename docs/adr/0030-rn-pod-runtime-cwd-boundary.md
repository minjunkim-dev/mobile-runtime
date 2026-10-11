# ADR-0030: 고정한 원본 Pod consumer의 runtime cwd 경계를 제한한다

## 상태

채택. 사용자는 2026-10-11에 아래 범위와 새 실행 조건을 명시 확정했다. 정책 main 반영과 새 helper 독립 검토 및 새 단독 lease 전에는 실제 실행 권한이 없다. 이 결정은 아래 고정한 원본 Pod 호출 여섯 개의 own launcher에 대한 runtime cwd 판정과 제한된 cache metadata 감사를 새 조건으로 채택한다. [ADR-0020](0020-rn-baseline-prepared-input.md)의 조건 변경 절차를 따른다. [ADR-0028](0028-rn-bundler-norc-argument-order.md)과 [ADR-0029](0029-rn-observer-executable-errno.md)의 진단 허용만으로 이 판정 변경을 승인했다고 해석하지 않는다.

## 확인한 실패

attempt-17의 최소 RN 원본 Pod deployment 명령은 exit `0`이었다. observer는 실제 관측 7,712개를 기록했다. 7,216개는 모든 조건을 충족했다. 496개는 cwd 일치 조건만 충족하지 못했다. 관측 오류는 0개였다. 다른 관측 조건에는 실패가 없었다. observer와 preparation guard는 false였다. outer helper는 필수 STOP을 유지했다.

원본 result는 20,737,158 bytes다. SHA-256은 `3ee1fd2776d07abe87a0b75adf6344481edb592385e314443dba759fa2e61bba`다. 현재 `ruby_consumer_observer.py:170`은 `actualCwd == requestedCwd == event.cwd`를 요구한다. `receipt_passes`는 모든 관측의 일치를 요구한다. 성공한 관측이나 원본 exit 0으로 실패한 관측을 상쇄하지 않는다.

496개는 모두 own launcher의 관측이었다. descendant 관측에는 이 실패가 없었다. 다음 경로 역할을 구분했다. 공개 문서에는 실제 host 경로와 PID를 기록하지 않는다.

| 현재 cwd 역할 | 관측 수 | 서로 다른 cwd 수 |
| --- | ---: | ---: |
| 같은 source clone의 React Native subtree | 92 | 6 |
| 기존 HOME CocoaPods cache의 `Pods/External/<package>/<slug>` | 404 | 2 |
| private 준비 경로, system tmp, 그 밖의 HOME 경로 | 0 | 0 |

source의 55개 파일과 세 lock에 대한 사후 감사는 PASS였다. consumer 전후 공유 경로 감사도 PASS였다. 공유 경로 변경 목록은 비어 있었다. 이것은 cwd 조건 실패와 별도 결과다. snapshot으로 모든 filesystem write의 부재를 증명하지 않는다.

필수 STOP 뒤 native·기기·Android·Mattermost·fresh 검증은 시작하지 않았다. root는 lease 반납을 확인했다. 원본 result·log·helper와 실패 판정을 보존한다. 새 조건이나 후속 실행으로 attempt-17을 사후 PASS로 바꾸지 않는다. 이 실패를 앱 native 실패나 Runstir 실패로 분류하지 않는다.

## 원본 source 대응과 한계

최소 표본에서 읽은 CocoaPods `1.15.2`의 source는 cwd 이동을 수행한다. 아래 표의 hash는 해당 로컬 원본 파일의 bytes를 식별한다. 공식 version source 링크는 source 대응을 설명한다.

| 원본 파일과 공식 source | 확인한 지점 | 로컬 원본 SHA-256 |
| --- | --- | --- |
| [config.rb](https://github.com/CocoaPods/CocoaPods/blob/1.15.2/lib/cocoapods/config.rb#L23) | 23의 기본 cache 경로. 119–120의 `CP_CACHE_DIR` 적용 | `9213f9002f16869b7fc1c6c7fb87ced2333effadcab9c23fdb89e61001da34d8` |
| [specification.rb](https://github.com/CocoaPods/Core/blob/1.15.2/lib/cocoapods-core/specification.rb#L747) | 747–753의 podspec parent `Dir.chdir`. 845의 podspec 평가 | `a4bcca7dd6d9bb7ade9634c31392bb2abb2b2f2bb86264e3a344f2beeebac43b` |
| [downloader/cache.rb](https://github.com/CocoaPods/CocoaPods/blob/1.15.2/lib/cocoapods/downloader/cache.rb#L184) | 184–185의 destination. 243–245와 282–289의 cache 준비 연결 | `6d6db9a66391fa7610794c6616b6bab6291d466c6524ae2acc89f292e8062de9` |
| [pod_source_preparer.rb](https://github.com/CocoaPods/CocoaPods/blob/1.15.2/lib/cocoapods/installer/pod_source_preparer.rb#L57) | 57–60의 prepare command와 `Dir.chdir(path)` | `5b49b1c8b96a44e5acfb6aa0a9ab7d9628771dc6d40361e2d628b807e6dd7a1c` |
| [downloader/request.rb](https://github.com/CocoaPods/CocoaPods/blob/1.15.2/lib/cocoapods/downloader/request.rb#L61) | 61–68의 `External/<package>/<slug>` 생성 | `5f2fd0d39859917ac520524a472f78bf52e69e91d6b1faa17069916950ad879a` |

이 source는 관측한 cwd 역할에 대응하는 실행 경로를 제공한다. 각 관측 시점의 Ruby stack은 확보하지 않았다. 따라서 496개 관측을 특정 함수 호출과 동적으로 접합했다고 주장하지 않는다. cache cwd만으로 실제 cache write와 전체 쓰기 격리를 증명하지 않는다.

원본 404개 관측의 cache 경계는 CocoaPods 기본 HOME cache 경로와 부합한다. 이것은 실제 runtime config 또는 환경 선택값의 증거가 아니다. 이 결정은 해당 고정 경계 안의 관측 cwd만 판정한다. 새 Ruby 반사 명령이나 추가 kernel 환경 조회로 runtime cache 설정을 증명하지 않는다.

Mattermost의 [고정 source Gemfile](https://github.com/mattermost/mattermost-mobile/blob/c2fe3beda22befd2178dce431793c09111ed903e/Gemfile#L3)은 CocoaPods `1.16.1`을 선언한다. 같은 SHA의 [원본 Gemfile.lock](https://github.com/mattermost/mattermost-mobile/blob/c2fe3beda22befd2178dce431793c09111ed903e/Gemfile.lock#L30)은 CocoaPods와 cocoapods-core `1.16.1`을 고정한다. 이 선언은 실제 source 대응과 실행 성공의 증거가 아니다.

공식 CocoaPods `1.16.1` tagged source에도 같은 cwd 이동 경로가 있다. [Core specification.rb:747–753](https://github.com/CocoaPods/Core/blob/1.16.1/lib/cocoapods-core/specification.rb#L747)은 podspec parent에서 평가한다. [pod_source_preparer.rb:57–60](https://github.com/CocoaPods/CocoaPods/blob/1.16.1/lib/cocoapods/installer/pod_source_preparer.rb#L57)은 prepare command를 수행할 때 `Dir.chdir(path)`를 사용한다. [cache.rb:282–288](https://github.com/CocoaPods/CocoaPods/blob/1.16.1/lib/cocoapods/downloader/cache.rb#L282)은 cache destination의 준비를 연결한다. [request.rb:61–68](https://github.com/CocoaPods/CocoaPods/blob/1.16.1/lib/cocoapods/downloader/request.rb#L61)은 External slug를 생성한다. GitHub API의 원본 bytes에서 config·Core specification·preparer·request의 hash는 위 `1.15.2` 파일과 각각 같다. `1.16.1` cache.rb의 hash는 `2355e0003a9e370b3ea0987c302bfe2b7b39749c569e7c4eba4db2da02306756`이다. 이 source 경로는 deployment에만 제한되지 않는다.

현재 `prepare_frozen_stage.py:69–73`의 Mattermost recipe는 clone별 `CP_CACHE_DIR`를 지정한다. 원본 plain `pod install`을 먼저 수행한다. 그 뒤 원본 deployment를 수행한다. deployment만 허용하면 선행 plain Pod의 같은 cwd 판정은 여전히 실패할 수 있다. 따라서 아래의 정확한 원본 plain Pod 두 호출도 대상에 포함한다. 새 명령이나 재시도를 추가하지 않는다. Mattermost의 실제 cwd가 이 경계에 맞는지는 미검증이다. 해당 실행의 Ruby stack 및 설치 source와 공식 version source의 전체 대응도 새 준비에서 확인해야 한다. 허용 밖 관측이면 필수 실패로 중단한다. 최소 `1.15.2`의 실제 실행 결과를 Mattermost 성공으로 승계하지 않는다.

## 확정한 최소 판정 범위

대상 source는 최소 RN `b62e3a4d5e7cfc05d7d948a5a4e30f0cc6a82bb4`와 Mattermost `c2fe3beda22befd2178dce431793c09111ed903e`다. 두 새 baseline과 각 독립 fresh에만 적용한다. 표본별 원본 Ruby·Bundler·CocoaPods 버전과 plugin 및 환경을 유지한다.

대상은 네 clone 역할의 다음 원본 recipe 호출 여섯 개뿐이다. 표의 명령은 종류를 설명한다. 실행 권한은 sealed PLAN의 전체 원본 argv와 환경 및 clone별 receipt로 고정한다.

| clone 역할 | 원본 Pod 호출 | 호출 수 |
| --- | --- | ---: |
| 최소 baseline | `bundle exec pod install --deployment` | 1 |
| 최소 fresh | `bundle exec pod install --deployment` | 1 |
| Mattermost baseline | `bundle exec pod install` 뒤 `bundle exec pod install --deployment` | 2 |
| Mattermost fresh | `bundle exec pod install` 뒤 `bundle exec pod install --deployment` | 2 |

다음 조건을 모두 만족한 관측에만 cwd 예외를 적용한다.

1. 위 여섯 recipe 호출 중 해당 clone의 정확한 원본 consumer다. 승인한 전체 argv와 hash가 일치해야 한다. Mattermost의 원본 `CP_CACHE_DIR`와 기존 준비 환경 prefix도 포함한다. 단순 label, token 포함 여부나 `--deployment` suffix만으로 대상을 선택하지 않는다. clone 역할·source·consumer receipt를 함께 연결한다.
2. requested launch cwd는 원본 recipe의 같은 clone `ios` 디렉터리다. `requestedCwd == event.cwd`는 유지한다. 실제 명령의 cwd를 바꾸지 않는다.
3. 관측한 PID는 기존 launcher PID와 같다. 기존 시작 identity·executable·환경·ancestry·시간 조건도 모두 충족한다. descendant에는 이 예외를 적용하지 않는다.
4. 현재 cwd는 기존 exact launch cwd이거나 다음 두 경계 중 하나에 속해야 한다. 같은 clone의 canonical subtree 또는 해당 clone에 사전 고정한 원본 CocoaPods cache의 `Pods/External/<package>/<slug>`다. cache 쪽은 이 네 component와 같은 directory 깊이만 허용한다. `<package>`와 `<slug>`는 비어 있지 않은 단일 component여야 한다. `.`와 `..` 또는 경로 구분자를 포함한 component는 거부한다. cache의 다른 하위 디렉터리와 `Pods/Release`를 자동 허용하지 않는다.
5. 경계와 관측 cwd의 canonical 대응 및 directory type을 확인해야 한다. symlink·alias·다른 clone·경계 밖 이동이나 필수 증거 unknown이면 STOP한다. 허용 밖 cwd를 requested cwd로 치환하거나 관측에서 제거하지 않는다.

이 여섯 호출 밖의 plain Pod와 deployment에는 이 예외를 적용하지 않는다. Bundle install·bootstrap·activation·gem facts·exec Ruby와 다른 Ruby consumer는 기존 exact cwd 조건을 유지한다. 모든 descendant도 exact cwd 조건을 유지한다. 다른 실행에서 새로운 cwd 역할을 관측하면 실패를 보존한다. 실제 명령·환경을 자동 변경하거나 이번 경계를 추가로 넓히지 않는다.

## 구현 선택과 metadata 감사 경계

최소 구현 선택은 기존 관측값을 입력으로 받는 pure cwd predicate다. 기존 `run_step.clone_key(cwd)`의 clone 연결과 frozen stage의 exact consumer recipe를 접합한다. 기존 event의 전체 requested argv hash와 clone/source identity로 대상을 고정한다. 기존 launcher identity를 사용해 own launcher만 선택한다. 새로운 label만으로 권한을 만들지 않는다.

기존 `cwd(pid)` 조회가 기록한 현재 경로를 사용한다. process cwd·PID·환경·생존·identity query를 추가하지 않는다. 사전 고정하고 metadata로 확인한 canonical 경계에는 `pathlib.PurePosixPath.is_relative_to`로 containment를 판정한다. 문자열 prefix 비교를 사용하지 않는다. 이 pure API만으로 symlink 안전을 증명했다고 주장하지 않는다.

기존 filesystem 감사의 `Path.resolve`, `lstat` 및 directory·link 기록 방식을 제한된 경계에 재사용한다. 이 cache metadata 감사는 새로운 승인 범위다. 각 대상 consumer 전에 clone별 source root와 허용할 cache root 및 기존 ancestor component의 canonical path·type·link 상태를 고정한다. 없던 cache descendant는 부재 상태로 기록한다. consumer 뒤에는 실제 관측에 등장한 경로의 component를 같은 경계 안에서 감사한다. 사전 존재한 component의 canonical 대응을 유지해야 한다. 새 descendant도 regular directory로 대응해야 한다. symlink 또는 root 밖 canonical 이동과 설명할 수 없는 type이면 STOP한다. 사전 감사 실패나 필수 canonical 대응 불명도 명령 전에 STOP한다.

Mattermost의 최초 plain Pod 전에 원본 recipe의 clone별 cache root가 없을 수 있다. 이 경우 정확한 계획 경로와 no-alias 기존 ancestor를 먼저 고정한다. 없는 component는 부재로 기록한다. 임의 다른 경로를 후보로 선택하지 않는다. 같은 planned root의 생성은 원본 CocoaPods에 맡긴다. helper의 mkdir, 환경 추가나 명령 순서 변경을 허용하지 않는다. [CocoaPods 1.16.1의 cache_root source:94–96](https://github.com/CocoaPods/CocoaPods/blob/1.16.1/lib/cocoapods/config.rb#L94)는 경로가 없을 때 `mkpath`를 수행한다. 이 source만으로 실제 생성과 canonical 대응을 보장하지 않는다.

plain Pod 뒤에는 고정 경로의 실제 directory type과 canonical 대응 및 component를 확인한다. 기존 ancestor 상태가 바뀌거나 새 component가 alias·symlink이면 STOP한다. root가 여전히 없거나 증거가 불명이면 STOP한다. 이 사후 receipt를 같은 clone의 deployment 사전 감사와 연결한다. deployment는 기존 cache root를 다시 확인한 뒤 수행한다. baseline과 fresh는 각각 이 순서를 독립 수행한다. 최소의 기존 HOME cache root는 deployment 전에 존재와 canonical 대응을 확인한다. 이 최소 경계의 부재를 새로운 cache 위치나 자동 생성 명령으로 보완하지 않는다.

최소의 고정 cache root는 원본 attempt-17 관측이 소속한 기존 HOME CocoaPods cache 경계 하나다. 새 준비 때 그 canonical identity를 다시 고정한다. Mattermost는 기존 recipe의 clone별 `CP_CACHE_DIR` 경계 하나를 고정한다. baseline과 fresh의 source 및 private cache identity를 구분한다. 최소의 원본 공유 cache 경계 재사용 여부는 명시한다. 이전 clone의 산출물을 복사하지 않는다. 환경 override 부재나 runtime config 선택을 입증했다고 주장하지 않는다. 고정 경계 밖 관측이면 원본 설정의 의도를 추측하지 않고 STOP한다.

감사는 이 경계와 관측 component만 다룬다. HOME 전체나 임의 tmp를 허용하거나 전수 조사하지 않는다. 기존 shared tool·plugin·mise 상태 감사는 그대로 유지한다. cache cwd 허용은 공유 tool 쓰기 권한이나 source·lock 수정 권한이 아니다. consumer 전후 snapshot은 최종 metadata 상태 증거다. 모든 중간 symlink 변경·write의 부재 또는 원자적 격리를 보장하지 않는다. 이 한계로 필수 canonical 대응을 확인할 수 없으면 unknown STOP을 유지한다.

## 유지하는 조건과 검증 한계

기존 query·PID identity·executable·환경·ancestry·시간 판정을 유지한다. query 순서와 횟수·sampling·sleep·delay·poll 및 errno 관측을 유지한다. 오류 목록은 0개여야 한다. 한 관측이라도 허용 밖이거나 unknown이면 receipt를 거부한다. 원본 exit와 관측·metadata·source·shared 감사가 모두 충족해야 후속 실행으로 진행한다.

이 변경은 current cwd의 통과 판정을 제한적으로 바꾼다. routine receipt ID 정정이나 진단 추가로 분류하지 않는다. metadata 감사와 pure predicate에는 작업이 추가된다. 시간 overhead 0이나 scheduling 영향 없음은 주장하지 않는다. errno·cwd snapshot으로 실제 원인을 완전히 규명하거나 새 baseline 통과를 보장하지 않는다.

원본 source·lock·graph·선언 버전과 준비 환경을 유지한다. 최소 source 55개와 세 lock을 유지한다. Mattermost는 기존 Hermes 한 값과 generated mixed Debug 12값만 허용한다. 원본 앱과 Release 값 보존 조건도 유지한다. [ADR-0026](0026-rn-original-plugin-preparation.md)의 원본 plugin 및 clone별 준비 환경과 [ADR-0027](0027-rn-mise-state-metadata-links.md)의 exact metadata 조건을 확대하지 않는다. 원본 명령의 argv·cwd·순서·횟수·recipe도 유지한다.

## 새 실행 조건

1. 확정한 정책을 main에 반영한다. 새 cwd 판정과 제한된 cache metadata 감사 범위를 명시한다. 원본 attempt-17과 과거 packet의 bytes 및 실패 판정을 보존한다.
2. 새 helper·PLAN·source/output root와 정책 hash를 고정한다. 원본 recipe 호출 여섯 개·own launcher·clone별 canonical 경계·metadata receipt 연결을 독립 검토한다. memory에서는 네 clone 역할과 전체 argv의 분리, 정상 exact cwd, 허용 clone subtree와 External 깊이, 다른 consumer와 descendant 거부를 검증한다. Mattermost의 기존 ancestor 및 cache 부재 기록과 원본 생성 뒤 사후 감사의 연결도 검증한다. alias·symlink·`..`·형제 root·Release·unknown·receipt 불일치의 거부도 검증한다. 범위 밖 query·명령·환경·sampling·delay·guard 변경은 거부한다.
3. root의 최신 preflight와 새 단독 lease 뒤 두 새 baseline을 독립 준비한다. 이전 lease·clone·private state·node_modules·vendor/bundle·Pods·build를 승계하지 않는다. 기존에 검증한 공식 raw archive의 캐시 재사용 조건만 유지한다. 원본 early Metro와 source·lock·shared 및 metadata 감사를 수행한다.
4. 원본 frozen Bundle과 대상 Pod 호출의 종료 상태 및 새 관측 조건을 각각 확인한다. 두 표본의 iOS·Android build·install·launch·첫 화면 네 개를 직렬 검증한다. 네 baseline 첫 화면 뒤 각 독립 fresh에서 같은 준비와 frozen 검사를 수행한다. 과거 성공을 새 조건의 PASS로 승계하지 않는다.
5. 필수 consumer 실패·관측 오류·허용 밖 cwd·canonical 대응 불명·source 또는 shared 변경이면 모든 후속 실제 실행을 중단한다. 소유 자원만 정리한다. 최초 receipt와 사후 감사를 보존한다. 같은 attempt에서 경계를 바꿔 재개하지 않는다. 다른 조건에는 별도 결정과 새 실행이 필요하다.

이 정책의 채택 자체로 helper 구현이나 실제 실행을 수행하지 않는다. 정책 main 반영 뒤 새 helper 구현과 독립 검토를 수행한다. 실제 실행은 새 단독 lease 뒤에만 수행한다. 문서·memory·CI 성공은 실제 frozen·native·첫 화면·fresh 성공 증거가 아니다. 실제 Runstir CLI·GUI 재현은 후속 gate다. #212와 PR #236은 열린 상태를 유지한다. 원본 비공개 증거와 공개 비식별 표현의 hash를 구분한다.

## 확정한 답

사용자는 네 clone 역할의 정확한 원본 Pod recipe 호출 여섯 개의 own launcher에 한해 위의 같은 clone subtree와 고정 CocoaPods cache External 경계를 확정했다. 최소의 deployment 두 호출과 Mattermost의 선행 plain Pod 및 deployment 네 호출만 포함한다. 표본별 원본 cache root와 argv·환경·순서를 유지한다. 제한된 metadata 사전·사후 감사와 Mattermost의 계획된 cache 부재 기록 및 원본 생성 뒤 검증도 함께 확정했다. 두 새 baseline과 각 독립 fresh 및 새 단독 lease를 요구한다. 다른 Ruby consumer와 모든 descendant의 exact cwd 및 모든 unknown STOP을 유지한다. 정책 main 반영과 새 helper 독립 검토 및 새 단독 lease 전에는 실제 실행을 재개하지 않는다.

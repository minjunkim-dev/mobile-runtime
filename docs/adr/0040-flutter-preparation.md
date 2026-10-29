# ADR-0040: Flutter SDK와 Dart workspace를 같은 승인 계획에 연결한다

날짜: 2026-10-16
상태: SDK·locked 정렬·공통 pipeline을 구현했다. 실제 측정·독립 리뷰·최종 head 승인은 별도 gate다.
관련: #199 AC02·AC03, #205, ADR-0035, ADR-0036

## 선언과 기존 SDK

`FlutterProject`는 앱의 Dart·Flutter constraint와 exact manager pin을 읽는다.
`.fvmrc`, `.flutter-version`, `.tool-versions`, `mise.toml`, `.mise.toml`을 사용한다.
같은 manager는 가장 가까운 선언을 따른다. 서로 다른 manager의 exact pin은 같아야 한다.
상위 탐색은 해당 Git root에서 끝난다. 전역 설정을 프로젝트 pin으로 가져오지 않는다.
지원하지 않는 Flutter TOML 형태와 mutable alias는 수동 처리 대상으로 남긴다.
Dart constraint에 npm의 partial·x-range·tilde 의미를 적용하지 않는다.
entrypoint는 선택한 앱 안의 실제 Dart 파일이어야 한다.
공통 `ProjectInspectionInput.entrypoint`와 CLI `setup --entrypoint`로 전달한다.
생략하면 `lib/main.dart`다. 변경한 entrypoint와 그 파일은 새 승인 조건이다.
Flutter가 아닌 앱에 명시 entrypoint를 주면 도구 호출 전에 거부한다.

`FlutterPreparation`은 SDK를 확인하려고 `bin/flutter`를 실행하지 않는다.
이 wrapper는 bootstrap·다운로드·cache 갱신을 수행할 수 있다.
기존 version JSON, bundled Dart version, arm64 Mach-O identity와 준비된 tools snapshot을 읽는다.
기존 SDK fingerprint에는 이 입력과 Dart 실행 파일·wrapper bytes가 들어간다.
각 파일의 순서·size·SHA256을 구분해서 묶는다. 파일 경계가 바뀐 입력을 같은 fingerprint로 취급하지 않는다.
이 fingerprint는 SDK 배포 archive의 checksum이나 전체 SDK 무결성 증명과 다르다.
기존 SDK의 version·revision·Dart가 공식 정식 arm64 release와 맞고 프로젝트 constraint를 만족하면 재사용한다.
실행할 SDK의 발견 출처도 보존한다. `FLUTTER_ROOT`·`PATH`의 명시 선택과 Runstir 관리 설치를 실행 후보로 사용한다.
자동 `.fvm/flutter_sdk`에서만 발견한 SDK는 metadata가 일치해도 Dart를 실행하지 않는다.
그 경우 SDK·workspace를 미확인 수동 단계로 남긴다. 신뢰하는 SDK를 명시한 뒤 다시 계획한다.
프로젝트 constraint를 만족하는 명시 SDK를 자동 FVM 후보보다 우선한다. exact pin이 없으면 다른 호환 version도 우선 선택 대상이다.
metadata와 Mach-O header는 archive 인증 근거가 아니다.
다른 기존 SDK를 제거하거나 그 SDK에서 bootstrap하지 않는다.

## 정확한 공식 설치 입력

[공식 macOS release metadata](https://storage.googleapis.com/flutter_infra_release/releases/releases_macos.json)를 사용한다.
version·stable channel·arm64·bundled Dart exact·framework revision·archive path·SHA256을 결합한다.
정확한 공식 archive의 HEAD로 size를 확인한다. metadata 전체 SHA256도 계획에 넣는다.
중복 release, 잘못된 channel·architecture, 불명확한 Dart·archive·size는 설치를 차단한다.
현재 remote latest는 선택하지 않는다.
정확한 프로젝트 pin을 우선한다. pin이 없고 기존 적합 SDK도 없으면 고정 후보 `3.41.9`만 검토한다.
이 후보는 bundled Dart `3.11.5`다. 프로젝트 constraint가 거부하면 수동 대기로 남긴다.

새 SDK는 Runstir 소유 root의 `versions/<version>-arm64-<revision-prefix>`에 나란히 설치한다.
기존 destination은 불완전해도 덮어쓰지 않는다. 전역 PATH와 SDK 선택을 바꾸지 않는다.
공통 `InstallationMetadata`·`InstallationAction`·`InstallationExecution.installZIP`을 재사용한다.
별도 installer·승인 체계를 만들지 않는다.
공통 ZIP 경계가 size·checksum·path·link·stage·취소·원자적 commit을 처리한다.
provider는 추출한 `flutter/`의 Flutter·Dart·revision과 필수 실행 파일을 확인한다.
관리 versions의 숨은 임시 stage는 기존 SDK로 재사용하지 않는다.
공통 runner는 실행 직전·lease 후·최종 commit 전의 source와 승인 조건을 재관측한다.
SDK 설치 뒤 처음 해석할 workspace나 Android 요구가 추가되면 새 계획을 승인해야 한다.
SDK 설치를 의존성 정렬이나 앱 실행 완료로 표시하지 않는다.

## Dart workspace와 locked alignment

[Dart의 workspace resolver](https://dart.dev/tools/pub/workspaces)를 정본으로 사용한다.
`dart pub --suppress-analytics workspace list --json`을 호출한다.
선택한 bundled Dart 실행 파일을 직접 사용한다. cwd는 선택한 Flutter 앱이다.
resolver의 canonical path로 앱 root와 dependency workspace root를 분리한다.
glob이나 nested workspace 규칙을 Runstir에서 다시 구현하지 않는다.
`pubspec_overrides.yaml`의 resolution·workspace·dependency override도 Pub의 해석을 따른다.
workspace 각 package의 Dart·Flutter constraint를 확인한다.
workspace를 이탈한 path와 선택 앱을 포함하지 않은 결과는 사용하지 않는다.

Pub은 workspace member와 그 중간 ancestor의 stray lock·package_config 파일을 삭제할 수 있다.
이 파일이 있으면 정렬을 계획하지 않는다. 경로를 표시하고 수동으로 정리하도록 안내한다.
workspace root의 기존 `pubspec.lock`이 없을 때도 수동 대기로 남긴다.
Runstir는 lockfile을 만들거나 버전을 upgrade하지 않는다.

정렬 명령은 [bundled Dart의 `pub get --enforce-lockfile`](https://dart.dev/tools/pub/cmd/pub-get)이다.
Flutter도 [같은 bundled Dart와 `FLUTTER_ROOT`를 사용한다](https://github.com/flutter/flutter/blob/3.41.9/packages/flutter_tools/lib/src/dart/pub.dart).
정렬 cwd는 resolver가 확인한 workspace root다.
child의 `FLUTTER_ROOT`와 Runstir 소유 `PUB_CACHE`만 명시한다.
기존 전역 Pub cache와 SDK를 bootstrap 대상으로 쓰지 않는다.
workspace와 해당 cache의 lease를 같이 사용한다.
cache나 Pub 생성 경로가 다른 tree로 연결되는 symlink면 정렬을 차단한다.
기존 링크와 외부 파일을 보존하고 별도 실제 경로를 수동으로 준비하도록 안내한다.
명령·workspace·cache·SDK fingerprint는 공통 실행 조건 재확인에 연결한다.
inherited environment와 비밀값을 Codable plan이나 로그에 복사하지 않는다.
raw YAML·도구 진단도 공개 manual 문장에 넣지 않는다.

공통 `PreparationRunner`로 정확한 dependency command를 실행한다.
실행 전후의 예상 밖 source·lockfile 변경을 보고한다. 파일을 자동 복원하지 않는다.
실패·취소 후 완료한 SDK와 cache를 일괄 삭제하지 않는다.
다음 계획은 현재 설치와 남은 작업을 다시 확인한다.

## 양쪽 플랫폼의 실제 준비 항목

플랫폼 선택으로 Flutter 준비 범위를 한쪽으로 줄이지 않는다.
iOS·Android host, 선택 SDK의 debug engine marker, generated native 입력을 각각 확인한다.
host source가 없으면 migration 안내를 만든다. `flutter create`는 실행하지 않는다.
iOS `Generated.xcconfig`는 선택 SDK·앱·entrypoint를 가리켜야 한다.
Android `local.properties`는 선택한 Flutter SDK를 가리켜야 한다.
plugin metadata는 SDK version과 현재 package_config의 package path와 맞아야 한다.
Pub이 생성한 `package_graph.json`에서 선택 앱의 전이 dependency와 해당 앱의 dev dependency를 읽는다.
현재 package pubspec의 이름·직접 dependency key가 graph와 같아야 한다.
다른 workspace 앱과 의존 package의 dev dependency를 선택 앱의 plugin으로 합산하지 않는다.
단순 modern plugin은 현재 플랫폼의 전체 name·canonical path·native build·shared Darwin 근거를 대조한다.
누락된 일부 목록을 전체 목록으로 재사용하지 않는다.
공식 SDK는 plugin이 없으면 `.flutter-plugins-dependencies`를 삭제한다.
따라서 reachable plugin이 없음을 확인했을 때 metadata 부재를 허용한다.
읽을 수 없는 graph·pubspec과 legacy·federated resolver 의미는 수동 경계다.
이 검사는 Flutter의 plugin resolver나 native 생성기를 실행하거나 다시 구현하지 않는다.
이미 유효한 입력은 `reuse`다. 실제로 부족하거나 오래된 입력만 수동 단계로 남긴다.
engine marker와 derived path 검사는 native build나 첫 화면 도달을 입증하지 않는다.
호스트 도구·Android SDK·iOS 자원·Pods의 준비는 해당 공통 provider와 함께 판정한다.
Android derived 입력이 없거나 stale이면 이전 Flutter SDK로 Gradle을 먼저 실행하지 않는다.
공통 WorkflowContext에는 검증한 도구와 Flutter child environment만 주입한다.
Flutter identity는 React Native package·RNGP·node_modules를 요구하지 않는다.
Flutter Pods는 기존 Podfile.lock과 frozen 명령을 요구한다.
기존 React Native의 선언된 custom Pod 명령은 유지한다.
Gemfile이 있으면 Gemfile.lock·검증한 Ruby/Bundler·기존 Bundle destination도 요구한다.
Flutter의 bundled CocoaPods 버전과 Bundle destination은 실행 없이 수동 단계로 남긴다.
계획 검사에서 `bundle exec`와 Ruby의 Bundler probe로 프로젝트 Gemfile을 평가하지 않는다.
정적 lock·Manifest 일치만으로 bundled Pods를 준비 완료로 표시하지 않는다.
Dart 뒤 generated 입력이나 선언 조건이 바뀌면 다음 Pod 명령을 시작하지 않는다.

direct Dart 정렬은 Flutter 고유 native 생성·plugin 후처리 완료를 뜻하지 않는다.
별도 Pub cache로 정렬한 뒤 package path가 바뀌면 plugin metadata가 stale해질 수 있다.
이 경우 실제 stale 입력을 표시한다. 이를 정상 준비 완료로 숨기지 않는다.
SDK wrapper나 snapshot을 실행해 기존 SDK를 갱신하는 우회는 하지 않는다.
#199 §5와 #205 AC2에 따라 native source·lock 변경이 필요한 migration은 수동 단계다.
기존 `.ios`·`.android` generated module host도 자동으로 app host에 재연결하지 않는다.
해당 경로와 module 준비의 수동 경계를 표시한다. 기존 파일을 보존한다.

## 준비된 Flutter Android 실행

Android 실행은 검증한 SDK capability의 private copy와 stock Gradle settings를 사용한다.
Gradle의 첫 model 조회부터 원본 SDK·source·lockfile과 private 실행 입력의 쓰기를 차단한다.
tool activation과 mise를 구성한 뒤 최종 host 경계에서 parent sandbox를 한 번 적용한다.
macOS는 제한된 sandbox 안에서 새 sandbox 적용을 거부한다.
따라서 Gradle launcher는 같은 Runstir 실행 파일의 private child client를 호출한다.
Runstir owner는 Dart를 Gradle의 sibling으로 시작하고 child sandbox를 한 번 적용한다.
실행 파일·snapshot·cwd·환경·정책은 owner가 고정한다. client는 크기를 제한한 argv만 전달한다.
private root의 Unix socket은 같은 UID와 실행별 인증값을 검사한다.
인증값은 private 환경으로 전달한다. argv·공개 로그·계획에 기록하지 않는다.
stdout·stderr·종료 상태를 전달한다. 연결 해제와 owner 취소는 해당 SDK 작업을 취소한다.
child는 network와 승인 범위 밖 쓰기를 계속 거부한다.
선택한 앱의 `build`, `.dart_tool/flutter_build`와 검증한 dependency workspace의
`.dart_tool/hooks_runner`만 native build 산출물·Dart hook cache 쓰기 경로로 사용한다.
각 경로의 alias·보호 입력과의 겹침을 private view 생성 전에 거부한다. lock·package config/graph·source·SDK의 쓰기 거부는 유지한다.
private view는 작업이 끝나거나 실패·취소되면 지운다. 남은 Gradle 후손은 지운 경로를 다시 만들 수 없다. 두 sandbox 정책이 root 자체의 쓰기를 거부한다.
그러나 남은 후손은 root 안의 쓰기 예외 경로에는 계속 쓸 수 있다. 그래서 하위 폴더를 보호 입력이나 `$HOME`을 가리키는 링크로 바꿔치기할 수 있다. sandbox 밖의 Runstir가 경로로 지우면 root 밖 파일을 지울 수 있다.
따라서 root 아래 경로를 다시 풀지 않는다. 링크를 따르지 않고 연 directory descriptor로만 내려간다(`openat` `O_NOFOLLOW`, `unlinkat`). 링크와 파일은 항목 자체만 지운다. 다른 device로는 들어가지 않는다. root는 device·inode가 기록과 같을 때만 지운다.
재귀하지 않고 명시적 stack으로 내려간다. 후손이 만든 깊은 트리가 작업 스레드의 stack을 넘기지 않게 하기 위해서다. 단계마다 descriptor 하나를 쓰므로, descriptor 한도를 넘는 깊이는 지우지 못하고 root를 남긴 채 로그를 남긴다.
CLI는 SIGINT·SIGTERM·SIGHUP을 취소로 바꾼다. 취소한 작업이 아직 풀리지 않은 채 프로세스가 끝나면 남은 root를 종료 처리기에서 지운다. GUI 종료도 같다.
SIGKILL과 강제 종료는 root를 남길 수 있다.
후손이 아직 쓰고 있으면 삭제는 몇 번 다시 시도한다. 그래도 실패한 root는 종료 처리기가 한 번 더 지운다. 프로세스가 끝난 뒤에도 후손이 쓰고 있으면 root가 남을 수 있다.
명령이 실패한 뒤 보호 검사도 실패하면 그 기록은 root 밖 `~/Library/Logs/dev.runstir/flutter-protection`에 남긴다. root와 함께 지워지지 않게 하기 위해서다. 취소로 중단된 보호 검사는 입력이 바뀐 근거가 아니므로 기록하지 않는다. 취소 중에는 SDK 비교의 첫 취소 확인에서 검사가 멈추므로, 그 전에 확인하는 root identity 변경만 기록될 수 있다.
같은 APFS volume에서는 SDK 파일을 clone한다. 다른 volume에서는 검증한 byte copy를 사용한다.
root는 `RUNSTIR_SCRATCH_DIR`, 연결된 `$DEVSSD_ROOT/scratch`, `TMPDIR` 순서로 고른다.
후보는 이 사용자가 소유하고 group·other가 쓸 수 없는 기존 디렉터리여야 한다. 그래야 다른 사용자가 지운 root 경로를 다시 만들 수 없다. 상위 경로에 symlink가 있어도 안 된다. 조건에 맞지 않으면 `TMPDIR`를 쓴다.
ownership을 무시하는 volume(`Owners: Disabled`)에서는 이 보장이 약하다. 그 volume의 보호 입력도 같은 한계를 가진다.

### SDK 변경 감지 (#344, 2026-10-29 사용자 결정)

원본 SDK와 private copy의 전체 내용은 view 준비 중에 한 번씩만 해시한다. clone한 copy는 snapshot 비교에서 한 번 읽는다. 다른 volume의 byte copy는 복사하면서 원본을 한 번 더 읽는다. SDK fingerprint의 몇 개 파일은 기존대로 다시 읽는다.
해시 전에 각 트리의 metadata snapshot을 남긴다. 파일·link는 device·inode·uid·mode·link 수·size·mtime·ctime(ns)을, directory는 device·inode·uid·mode를 기록한다. 항목 추가·삭제는 경로 목록으로 비교한다.
그 뒤의 모든 보호 검사(view 준비 중 재확인, host 명령 앞뒤, Gradle 앞뒤, Dart child 시작)는 이 metadata를 비교한다. 3.9 GB SDK를 다시 읽지 않는다.
APFS에서는 내용 쓰기·교체·권한·xattr 변경과 hard link 추가가 ctime을 ns 단위로 바꾼다. 권한 없는 프로세스는 ctime을 되돌릴 수 없다. 해시 중에 바뀐 파일도 metadata 비교에서 드러난다.
APFS가 아닌 volume(exFAT·네트워크·HFS+ 등)에서는 같은 크기로 다시 쓰고 시각을 되돌린 파일을 metadata로 구분할 수 없다. 그 트리는 기존처럼 검사마다 내용을 비교한다.
한계: sandbox 밖의 같은 UID 프로세스가 공유 쓰기 mmap으로 바꾼 byte는 그 프로세스가 `msync`·`munmap`하거나 끝나기 전까지 mtime·ctime에 나타나지 않는다(APFS에서 확인). 매핑을 유지하는 동안의 보호 검사는 이 변경을 놓친다. root 권한이나 시스템 시계 조작은 원래 이 경계 밖이다.
기존 검사도 시점 표본이었다. 검사 사이에 바꿨다 되돌린 변경은 원래 감지하지 못했다. 사용자는 이 한계를 보고 실행 비용 대신 metadata 비교를 선택했다. 변경 전 alpha.14 측정에서 이 재해시가 Gradle 전 약 270초, setup 742초 대부분을 차지했다.
반대로 `touch`처럼 내용이 같아도 ctime이 바뀌는 외부 조작은 이제 변경으로 판정한다. 보호 입력을 보존하고 다시 실행한다.
예외로 원본 SDK의 `bin/cache/lockfile`·`engine.stamp`·`engine.realm`은 내용과 identity로 비교한다. 같은 SDK로 IDE나 터미널에서 `flutter`를 실행하면 `Cache.lock()`과 `update_engine_version.sh`가 매번 이 파일들을 같은 내용으로 다시 써서 ctime을 바꾸기 때문이다.
source·lockfile·생성 metadata 같은 다른 보호 입력은 계속 내용으로 비교한다.

이 실행 구조의 테스트는 실제 앱 Build·Up·Down·첫 화면 검증을 대신하지 않는다.

## 검증 경계

행동 검사는 작업 소유 fixture와 정상 ZIP을 사용한다.
기존 SDK 재사용, exact install 계획, workspace·pin·entrypoint, generated 입력의 양쪽 판정,
정상 ZIP commit·재사용, 다운로드 실패·취소·완료 설치 보존을 확인한다.
이 fixture는 실제 Flutter 2 GB archive의 다운로드·SDK 설치나 CLI·GUI·기기 성공 증거가 아니다.
실제 도구 없는 환경과 기존 환경의 CLI·GUI 측정은 별도 lease와 보존 감사 뒤 수행한다.

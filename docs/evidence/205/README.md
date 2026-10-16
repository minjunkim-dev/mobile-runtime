# #205 Flutter 준비 구현의 검증 범위

이 기록은 provider와 공통 setup 결합 및 작업 소유 fixture의 결과다.
CLI 검증은 작업 소유 합성 도구 fixture다.
실제 Flutter SDK 설치·정렬과 VM·GUI·기기 실행은 이 기록에 없다.
#205 전체 완료나 #199 AC02·AC03 통과를 선언하지 않는다.

## 입력과 계약

[ADR-0040](../../adr/0040-flutter-preparation.md)은 선언·SDK·workspace·공통 승인 경계를 설명한다.
공식 macOS metadata는 2026-10-16에 read-only로 다시 읽었다.
관측 bytes는 `377935`다. SHA256은 아래와 같다.

```text
be26ba7041e985325ac4dad55f795bbf51fb636da23e1ae41876223ebd51fc84
```

고정 후보는 Flutter `3.41.9`, stable arm64, Dart `3.11.5`다.
framework revision은 `00b0c91f06209d9e4a41f71b7a512d6eb3b9c694`다.
archive는 [공식 ZIP](https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_3.41.9-stable.zip)이다.
provider SHA256은 `d692b030a63466c44d6b2bc88583380371ecbe328f22cc4057835f59739821a1`이다.
같은 날 archive HEAD는 HTTP `200`, Content-Length `2147160009`를 반환했다.
HEAD의 body는 읽지 않았다. [official-release.json](./official-release.json)에 연결했다.
이 표는 실제 payload를 새로 다운로드하거나 설치했다는 뜻이 아니다.
다른 exact pin은 공식 metadata에서 그 version·arm64·Dart를 다시 확인해야 한다.

## 행동 검증

| 범위 | 실제 호출과 관측 | 한계 |
| --- | --- | --- |
| 초기 공통 surface RED | `PreparationExecution.run(planOnly:true)`에서 SDK reuse·locked alignment 항목 부재를 확인 | 공통 pipeline 연결 전의 RED다 |
| Core 선언 | 상위 exact manager pin·가까운 선언 우선·unsupported TOML·entrypoint·Dart constraint를 확인 | 실제 manager 실행이 아니다 |
| provider | 기존 SDK 파일을 읽고 workspace runner 응답·명령·cwd·child policy·파일 보존을 확인 | SDK 실행은 fake다 |
| 양플랫폼 | 유효 generated 입력은 두 플랫폼 reuse다. stale Android 입력은 Android만 수동이다 | engine marker·path 확인은 native build 성공이 아니다 |
| 설치 | 정상 합성 ZIP을 실제 unzip하고 공통 원자적 commit으로 설치한다. 재계획은 그 SDK를 재사용한다 | 공식 Flutter payload 설치가 아니다 |
| 실패·취소 | fake downloader 실패와 cancellation을 전달한다. 기존 SDK·lock·완료 설치와 소유 scratch 정리를 확인한다 | 실제 네트워크 장애를 발생시킨 결과가 아니다 |
| 비식별 오류 | raw YAML·도구 오류에 fixture marker를 넣고 공개 step에 노출되지 않는지 검사한다 | 실제 자격을 사용하지 않는다 |
| cache·생성 경로 | 외부 tree로 연결된 cache·Pub 생성 경로를 수동 단계로 막고 기존 링크를 보존한다 | 작업 소유 임시 tree만 사용한다 |
| SDK fingerprint | 두 파일의 bytes 경계 변경을 별도 입력으로 구분한다 | 전체 SDK archive 무결성 증명은 아니다 |

모듈 tests는 `FlutterProjectTests`, `FlutterProviderTests`, `FlutterInstallationTests`다.
공유 설치 회귀는 `InstallationExecutionTests`, `InstallationActionContractTests`다.
`FlutterPreparationTests`는 초기 surface RED를 GREEN으로 바꿨다.
초기 통합 checkpoint는 관련 suite 57개와 전체 Swift 717개를 compiler warnings-as-errors로 통과했다.
최종 제품 source는 `9d2d1770b380811b54704dab04ee83b834218fed`다.
이 source에서 전체 Swift 723개가 같은 Werror 명령으로 통과했다.
같은 제품 build에서 doctor·workflow·setup CLI fixture 3개도 순서대로 통과했다.
setup fixture는 plan·approval·trust·stale·partial·failure·cancel·TTY·JSON·NDJSON을 확인한다.
잘못된 Flutter 선언은 host/tool probe 전에 두 플랫폼 migration 계획으로 반환한다.
공통 surface는 다음 항목을 fixture로 검증한다.

- SDK reuse와 두 플랫폼 계획을 연결한다.
- 정확 declaration·entrypoint와 resolver workspace를 승인 입력으로 묶는다.
- workspace folder와 소유 Pub cache의 충돌을 실행 전에 거부한다.
- locked Dart 정렬은 정확한 cwd·child environment를 사용한다.
- 취소는 exit 130이다. 완료 cache와 기존 SDK를 보존한다.
- source·lock 변경을 보고한다. 파일을 자동 복원하지 않는다.
- frozen Pods는 기존 lock과 검증한 Ruby·CocoaPods를 요구한다.
- Bundle 정렬은 BUNDLE_FROZEN과 기존 destination을 유지한다.
- Dart 정렬 후 generated 입력이 바뀌면 Pods를 시작하지 않는다.
- 정상 합성 SDK ZIP 설치 뒤 처음 나타난 align을 remaining으로 남긴다. 새 plan-id 승인이 필요하다.
- commit 전 임시 `.runstir-stage-*`는 기존 SDK 후보에서 제외한다.

첫 SDK 설치 회귀는 임시 stage를 기존 SDK로 오인하는 결함을 확인했다.
이 결함을 고친 뒤 같은 회귀가 통과했다.
resource root의 directory URL hint도 명시적으로 고정했다.
이 정규화를 stage 오인의 직접 원인으로 기록하지 않는다.

## 명시 entrypoint

`ProjectInspectionInput.entrypoint`는 기본 nil이다. 기존 caller는 기존 `lib/main.dart` 의미를 유지한다.
CLI `setup --entrypoint lib/other.dart`는 선택한 앱 안의 기존 Dart 파일을 받는다.
그 파일·generated 입력 근거·plan-id를 함께 바꾼다. 이전 승인은 실행하지 않는다.
Flutter가 아닌 앱은 도구 호출 전에 거부한다. 경로 이탈은 migration 단계다.

공통 API 행동 RED는 entrypoint를 무시한 7개 expectation이었다.
연결 후 같은 행동과 non-Flutter 거부가 통과했다.
실제 CLI owned-tool fixture도 plan-id·stale 승인·경로 이탈·source 불변을 확인했다.
이 CLI fixture는 공식 Flutter SDK를 실행하지 않았다.

## 기존 동작과 iOS setup 상태 회귀

Flutter의 frozen Pod 명령 제한을 기존 React Native custom Pod 명령에 적용한 회귀를 확인했다.
공개 plan 행동 RED 1개를 고정했다. 제한을 Flutter에만 적용한 뒤 GREEN을 확인했다.
기존 React Native의 선언된 `yarn run pod-install` 명령은 유지한다.

native iOS provider가 정확 deployment와 compatible runtime을 확인한 경우를 별도로 검사한다.
provider가 같은 runtime ID의 build·version·arm64·available 재사용 근거를 반환해야 한다.
이 경우에만 Matrix의 불명확 runtime 요구와 reason·source가 같은 setup unknown을 대체한다.
일반 doctor의 `simulator.runtime` unknown은 그대로 유지한다.
전용 fixture는 6개 expectation의 RED를 고정한 뒤 GREEN을 확인했다.
build·architecture·deployment가 없는 세 대조 사례는 계속 수동 대기로 남는다.
이 결과는 실제 Simulator 생성이나 부팅 측정이 아니다.

검증 명령은 아래와 같다. CLI fixture는 공식 Flutter SDK를 실행하지 않는다.

```sh
swift test --skip-update -Xswiftc -warnings-as-errors
python3 -I scripts/verify-doctor-input.py .build/debug/mobile
python3 -I scripts/verify-workflow-input.py .build/debug/mobile
python3 -I scripts/verify-setup-input.py .build/debug/mobile
```

## plugin metadata 판정 교정

`ae62d0e3`의 판정은 두 방향의 결함을 포함했다.
plugin 없는 정상 앱에서 공식 SDK가 삭제한 metadata 파일을 필수로 요구했다.
반대로 native plugin이 있는 앱에서는 일부 row만 맞아도 전체 목록으로 재사용했다.
행동 RED 4개는 18개 expectation에서 실패했다.
같은 행동은 수정 후 통과했다.
추가 closure·불명·identity 대조를 포함한 관련 Flutter 테스트 39개도 Werror로 통과했다.
수정 제품 source는 `e2211c9345eab564dc5f71b2dcec8bddb4ddefd4`다.
이 source에서 전체 Swift 730개가 Werror로 통과했다.
같은 제품 build의 doctor·workflow·setup CLI fixture 3개도 순서대로 통과했다.

공식 `3.41.9` source를 배포 ZIP에서 읽었다.
`flutter_plugins.dart:106–141`은 선택 앱의 전이 package를 확인한다.
같은 파일의 `204–212`는 plugin이 없으면 metadata를 삭제한다.
`package_graph.dart:17–71`은 선택 앱의 dev dependency만 closure에 넣는다.
`flutter_plugins.dart:350–369`는 name·path·native build·shared Darwin을 기록한다.
원본 ZIP의 bytes와 checksum은 바꾸지 않았다.

새 검사는 resolved package graph와 현재 pubspec의 이름·직접 dependency key를 대조한다.
다른 workspace 앱과 의존 package의 dev dependency는 제외한다.
필수 row 누락·부분 목록·중복·다른 path·native build 불일치는 수동 단계다.
불명확한 package 입력과 legacy·federated 선언도 구체적인 수동 안내로 남긴다.
공식 plugin resolver를 실행하거나 native 파일을 생성하지 않는다.
이미 잠긴 Yams를 EnvironmentKit target에서 직접 재사용한다.
새 외부 dependency나 version·lock 변경은 없다.

old actual 후보는 계획 실행 전에 중지했다.
새 소유 VM의 clone·부팅·환경 관측·후보 전송까지만 수행했다.
제품 CLI·setup plan·SDK payload 설치·Dart 정렬·GUI·기기 실행은 0회다.
소유 VM은 정상 종료했다. 중단 전 감사에서 원본 VM 세 개의 config·manifest·NVRAM hash와 disk stat은 같았다.
외장 SSD 재연결 후에는 VM의 stopped 상태를 다시 확인했다.
이후의 전체 VM disk bytes와 전송 뒤 guest 파일 hash는 수집하지 않았다.
이 기록은 수정 후보의 실제 준비 성공 근거가 아니다.

## 수동 경계와 남은 gate

#199 §5는 migration이나 source·lock 변경이 필요한 준비를 중단하고 수동 방법을 안내하도록 정한다.
#205 AC2도 native migration의 중단과 수동 안내를 요구한다.
이에 따라 직접 Dart locked 정렬을 native generated 준비 완료로 표시하지 않는다.
실제 누락·stale generated 입력과 debug engine marker를 플랫폼별 수동 단계로 남긴다.
기존 `.ios`·`.android` generated module host가 있으면 그 경로를 표시한다.
자동 app-host 라우팅·module 재생성은 수행하지 않는다.

공식 tools snapshot의 추가 bootstrap·SDK cache 쓰기를 source로 조사했다.
SDK ZIP의 snapshot·engine cache와 tools package_config 부재도 읽기로 대조했다.
새 snapshot·bootstrap·sandbox native 생성 기능은 이번 구현 범위에서 제외했다.
보류한 실험 source와 source-only 제안은 private 조사 기록으로 보존했다.
제품 tree에는 해당 기능을 넣지 않았다.

#205 실제 도구 없는 환경과 기존 환경의 설치·실패·취소·재실행·CLI·GUI 측정은 별도 gate다.
전체 AC 완료는 fixture만으로 선언하지 않는다.
별도 컨텍스트 리뷰·필수 CI·위험별 승인·병합·main CI도 별도 gate다.

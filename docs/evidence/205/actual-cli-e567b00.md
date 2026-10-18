# #205 e567b00 실제 CLI 검증

공식 Flutter SDK 설치와 해당 operation의 locked Dart 정렬을 확인했다.
설치 operation은 Flutter SDK·mise·Java 3개를 완료했다.
정렬 재시도 operation은 `dependencies.flutter`를 완료했다.
두 결과는 수동 항목 3개를 남겨 `partial / exit 1`이다.
전체 ready나 앱 build/run 성공을 뜻하지 않는다.
GUI의 별도 실제 설치·취소·재시도와 정상 종료는 [GUI 기록](actual-gui-e567b00.md)에 연결했다.
#205 완료를 선언하지 않는다.

정확한 plan ID·공식 pin·선택한 원본 참조는 [curated JSON](actual-cli-e567b00.json)에 있다.
원본은 그대로 보존했다. 공개 파일은 개인 경로를 별칭으로 바꾼 요약이다.
정규화한 명령을 원본 bytes와 같다고 주장하지 않는다.

## 고정 source와 후보

| 대상 | 고정 값 |
| --- | --- |
| base | `3211df5ac08168bcd3b7848f13c37ff40c7cd185` |
| 실측 source | `e567b001a07cba6560a182ae47497de6009e1e80` |
| source tree | `1c0880339b8a910c712167a7ab58f9a7abae49ba` |
| 전체 30파일 canonical diff | 336302B, SHA256 `3e79c8473f0c0157354bb9879efe54190f40bd8f4fbc823d6d9796d38aa10a42` |
| CLI 실행 파일 | SHA256 `d2edef3e33e34c509be1d80894181e71f25c411975162812f3eec4696eba720c` |
| minimal source | `66732bc18ed28d9eed71336b4a2b018e09ad20b9`, tracked 67개 |

source·Tests·Package blob은 이전 `de7696e`와 같다.
CLI 13파일도 이름 정규화 뒤 bytes·mode·SHA256이 같다.
후보는 CLI 13파일과 GUI 15파일을 포함한다.
새 GUI bundle ID와 local ad hoc 서명은 packaging 차이다.
compiled GUI의 UUID와 TEXT section 27개는 같다.
이 동일성을 새 GUI 실행 근거로 사용하지 않는다.
Developer ID·공증·Gatekeeper 검증도 아니다.

동일 source의 기존 Werror 원본 로그에서 763 tests/90 suites PASS를 확인했다.
GUI build와 doctor·workflow·setup CLI fixture 3개도 exit `0`이다.
이 문서 작업에서 검사나 build를 다시 실행하지 않았다.
로컬 검사는 원격 필수 `CI`나 실제 준비 측정을 대체하지 않는다.

## 입력과 승인

minimal source를 새 소유 경로에 `--no-hardlinks`로 복제했다.
선언은 Dart `^3.11.5`다. exact Flutter manager pin은 없다.
entrypoint는 `lib/main.dart`다. dependency workspace는 이 앱 1개다.
새 child HOME·tmp·Pub cache·tool store를 사용했다.
기존 SDK는 읽기 전용 재사용 계획으로 먼저 확인했다.

| 승인한 설치 | 버전 | 공식 payload bytes | SHA256 |
| --- | --- | ---: | --- |
| Flutter | `3.41.9`, Dart `3.11.5`, stable arm64 | 2147160009 | `d692b030a63466c44d6b2bc88583380371ecbe328f22cc4057835f59739821a1` |
| mise | `2026.10.7` | 127277984 | `f5171e341518a57e8c4e9280e28443e35d66212c51164c83be76794e0a78b014` |
| Java | `Temurin 17.0.18+8` | 185658966 | `d81de06d938384fe76c4aa3c13395933aa11e2d19b0428743f810db06b05e312` |

Flutter revision은 `00b0c91f06209d9e4a41f71b7a512d6eb3b9c694`다.
[공식 ZIP](https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_3.41.9-stable.zip)과 metadata SHA256을 계획에 고정했다.
표의 크기는 승인한 provider pin이다. 별도 수신 archive snapshot 크기로 바꾸지 않는다.
선택한 원본 묶음에는 다운로드 완료 archive의 독립 hash 재측정이 없다.
제품의 exact size/checksum 검사와 설치 완료 결과를 기록한다.

SDK 설치의 repository trust는 false다.
Dart 정렬에는 exact plan 승인과 별도 repository trust true를 사용했다.
`bin/flutter`, tools snapshot, native generation·migration은 실행하지 않았다.

정규화한 핵심 명령은 아래와 같다.
별칭은 표시용이다. plan ID는 실제 원본 경로와 관측 입력으로 계산했다.

```text
<CLI> setup --project <SOURCE> --platform ios --non-interactive --json --progress-json --plan
<CLI> setup --project <SOURCE> --platform ios --non-interactive --json --progress-json --approve <EXACT_PLAN_ID>
<CLI> setup --project <SOURCE> --platform ios --non-interactive --json --progress-json --approve <EXACT_ALIGN_PLAN_ID> --trust-repository
<NEW_SDK>/bin/cache/dart-sdk/bin/dart pub --suppress-analytics get --enforce-lockfile
```

마지막 child의 cwd는 resolver가 확인한 `<SOURCE>`다.
`FLUTTER_ROOT`와 `PUB_CACHE`는 소유 SDK·cache를 가리킨다.
CLI에서 `--platform ios`를 선택해도 Flutter 계획은 iOS·Android 항목을 모두 반환했다.

## 실제 순서와 결과

| 순서 | 관측 |
| --- | --- |
| 04 기존 SDK 계획 | 기존 SDK reuse. locked align과 mise·Java 설치를 제안했다. |
| 06 새 SDK 계획 | Flutter·mise·Java install 3개. exact plan `551fbb40…`를 별도로 승인했다. |
| 07 다운로드 중 취소 | payload 1846177792B → 1851322368B 증가. Root가 exact CLI identity를 확인한 뒤 SIGINT 1회. 제품 `cancelled / exit 130`. 관측 child 잔여 0개. |
| 09 재계획 | 남은 Flutter·mise·Java install을 다시 제안했다. 새 exact 승인을 받았다. |
| 10 설치 재시도 | 393.743초. Flutter·mise·Java completed. `partial / exit 1`. 새 SDK 설치 뒤의 align은 남은 계획으로 반환했다. |
| 14 정렬 취소 | v2 observer가 정확 bundled Dart child를 확인했다. SIGINT 1회. `cancelled / exit 130`. 관측 child 잔여 0개. |
| 16 재계획 | 남은 locked align 하나를 새 plan ID로 승인했다. |
| 17 정렬 재시도 | 9.080초. `dependencies.flutter` completed. `partial / exit 1`. 수동 항목 3개 잔여. 관측 child 잔여 0개. |
| 20 새 재검사 | SDK reuse. locked align과 같은 수동 항목 3개. `needs-approval / exit 0`. |

설치 재시도의 `exit 1`은 전체 준비의 부분 완료다.
설치 3개와 정렬 completed를 실제 실패로 바꾸어 해석하지 않는다.
다운로드 취소는 실제 네트워크 장애를 만든 사례가 아니다.

### 원본 취소 관측과 v2

07 원본의 `SIGINTSent:false`, `cancelObserved:false`를 그대로 보존했다.
원본 observer는 `ps`의 bare `curl` argv0를 인식하지 못했다.
Root의 보완 관측은 kernel `/usr/bin/curl`, 소유 관계와 payload 증가를 확인했다.
Root는 정확한 소유 CLI PID 하나에 SIGINT를 보냈다.
그 원본과 제품 exit `130`을 함께 연결한다.
원본 false flag를 true로 바꾸지 않았다.

v2는 bare 이름 또는 정확한 절대 경로의 `curl`·`dart` argv0를 허용한다.
kernel·공식 URL·소유 관계·payload 증가·locked command 검사는 유지했다.
v2 순수 검사는 과거 실행의 성공 근거가 아니다.
14번 실제 정렬 취소에서만 `cancelObserved:true`, `SIGINTSent:true`, exit `130`을 새로 확인했다.
제품 source는 이 harness 교정으로 바뀌지 않았다.

### 반복 정렬은 새 operation의 승인 대상이다

17번 completed는 그 operation의 locked get 성공이다.
현재 계약에는 영속 정렬 완료 receipt의 재사용이 없다.
별도 source·명세 검토도 새 operation마다 안전한 locked get을 제안하는 동작을 확인했다.
20번의 align 재제안을 앞선 정렬 실패나 전체 준비 성공으로 해석하지 않는다.
재검사 plan ID는 아래와 같다.

```text
9b586624c7d631d182a15eae29653e392a21ee639b997b9252bb5afea53c4e98
```

## 수동 항목과 보존 범위

최종 CLI의 수동 항목은 정확히 3개다.

| ID | 남은 조건 |
| --- | --- |
| `android.flutter.generated` | `local.properties`가 선택 Flutter SDK를 식별하지 않는다. |
| `ios.flutter.generated` | `Generated.xcconfig`가 선택 SDK·앱·entrypoint를 식별하지 않는다. |
| `ios.simulator.runtime` | 선택 Flutter 앱 scheme의 deployment target 측정이 필요하다. |

두 플랫폼 상태는 모두 `waiting-manual`이다.
locked Dart 정렬만으로 native 준비가 완료되었다고 표시하지 않았다.
수동 안내에 따라 native source나 lockfile을 자동 변경하지 않았다.

최종 named 보존 검사 12개는 모두 true다.
tracked source 67개 bytes·mode, HEAD, raw index·stage·flags·status가 같다.
기존 SDK는 21990 entries/17918 regular files/4118754054B다.
그 SDK의 전후 bytes·mode·regular SHA256 census가 같다.
새 managed SDK도 설치 후 11번과 최종 18번 census가 같다.
새 소유 `.dart_tool` 출력과 원래 tracked source를 구분한다.
소유 stage 잔여는 0개다. 제안한 lease 파일 4개는 모두 unheld다.

`Library/Caches` root mtime은 바뀌었다.
변경 actor와 원인은 unknown이다.
전체 HOME·cache bytes와 native T 쓰기 전체를 불변이라고 주장하지 않는다.
관측 child 부재도 미관측·reparented child 전체의 부재로 확대하지 않는다.
이 CLI 감사 시점에는 같은 VM의 GUI 작업을 이어갔다.
뒤의 GUI 종료 영수증에서 실제 GUI child exit `0`, 정상 VM stop `0`, 원 boot exit `0`을 확인했다.
그 lifecycle과 보존 기준 VM 7개의 비교 범위는 [GUI 기록](actual-gui-e567b00.md#보존과-정상-종료)에 있다.

## 남은 AC 근거

| 조건 | 현재 근거 | 남은 근거·한계 |
| --- | --- | --- |
| AC1 공식 SDK·선언·재사용 | 공식 pin, 적합 기존 SDK reuse, 새 SDK 설치, 기존 SDK 보존 | 다른 version·충돌 선언 처리는 source/fixture 근거다. 실제 SDK 교체 측정은 없다. |
| AC2 workspace·entrypoint·migration | 실제 resolver workspace와 bundled Dart locked get, native 수동 안내 | native generation·module host 생성·migration 완료는 주장하지 않는다. |
| AC3 CLI·GUI 양플랫폼 상태·재승인 | CLI의 양쪽 항목·completed·partial·manual3, 설치 후 새 align 승인. GUI의 양쪽 항목·partial·completed SDK·새 align 승인 대기는 별도 기록 | 실제 Android provider 추가 요구로 생긴 재승인은 이 CLI 묶음에 없다. 조건부 자동 검사와 실제 SDK 뒤 새 align 승인을 구분한다. |
| AC4 SDK 성공과 실행 구분·실패·취소·재실행 | 다운로드 증가/취소130/설치 재시도와 Dart 취소130/재시도 완료 | 실패 분기는 공통 fixture 근거다. #199 Testing Decisions에 따라 실제 설치·취소와 함께 연결한다. fake 실패를 실제 네트워크 실패로 승격하지 않는다. |
| AC5 / #199 AC02·AC03 | exact 승인·별도 trust·선택 자원 보존과 수동 경계 | 전체 완료, 최종 독립 증거 리뷰·필수 CI·위험별 승인·병합·main CI는 별도 gate다. |

GUI의 trust false SDK 설치를 별도 원본·화면으로 확인했다.
[GUI 기록](actual-gui-e567b00.md)은 새 계획·남은 항목·보존·정상 종료를 연결한다.
GUI에서 locked Dart 정렬은 실행하지 않았다.

## 원본 mapping

공개 JSON은 기존 방식처럼 evidence bundle ID·상대 receipt 경로·bytes·mode·SHA256을 연결한다.
개인 host·guest 절대경로와 전체 raw log를 복사하지 않았다.

| 선택한 비공개 근거 | SHA256 |
| --- | --- |
| CLI actual HANDOFF | `0c02dc4c3d0b65e8721aa5738c28774ce23babe5c9824d55f2d5eb7770b1bb77` |
| CLI actual AUDIT | `5abdbeeb22b2e2c22dd2dce967fb3d42e6708cce65e3c127156543f0636a266f` |
| CLI actual INDEX | `b91b75ced97aee04592d5bcf39d7dba87160fa7802fde382b504a8e57f2455b5` |
| main3211 integration HANDOFF | `c15d8948c15e85d47a06bcfb3b4d4735566111e1b5d8a4ae94cefb06bfe5cb2f` |
| main3211 integration INDEX | `9475c2ab3cd23c27b591b9c431ea29abed4597fad96df8d7b2e745c1c3b1e6e6` |
| 정렬 재검사 계약 검토 | `a8b34c7990a5db947427a0a160a39f26903dc83550684ed91cfbb4b04ff9d8ec` |

CLI INDEX 108항목, export 원본 95개, integration INDEX 38항목의 bytes·mode·SHA256을 이 문서 작업에서 다시 확인했다.
불일치는 0개다. 이 수치는 서로 겹치므로 고유 파일 수로 합산하지 않는다.
기존 immutable HANDOFF/AUDIT/INDEX를 수정하지 않았다.

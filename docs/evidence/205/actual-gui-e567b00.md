# #205 e567b00 실제 GUI 검증과 AC 연결

GUI에서 공식 Flutter SDK 다운로드를 취소했다. 재검사 후 같은 exact 계획을 다시 승인했다.
재시도는 `flutter.sdk`를 완료했다. 결과는 `partial / exit 1`이다.
iOS·Android는 모두 `needs-approval`을 표시했다. 새 locked Dart 정렬은 실행하지 않았다.
SDK 준비 성공과 전체 준비 완료·앱 build/run 성공을 구분한다.
최종 독립 리뷰·필수 CI·사람 승인·병합·main CI는 이 문서의 완료 주장이 아니다.

[공개 JSON](actual-gui-e567b00.json)은 원본 receipt와 화면의 bytes·mode·SHA256을 연결한다.
[CLI 기록](actual-cli-e567b00.md)은 같은 후보의 SDK 설치와 실제 Dart 정렬 취소·재시도를 연결한다.
원본 화면에는 개인 경로와 배경 Terminal 이력이 있다. 화면은 제한 원본으로 보존했다.
공개 문서에는 필요한 화면 관측과 원본 identity만 기록했다.

## 후보와 승인 경계

실측 source는 `e567b001a07cba6560a182ae47497de6009e1e80`이다.
source tree는 `1c0880339b8a910c712167a7ab58f9a7abae49ba`다.
GUI bundle ID는 `dev.runstir.validation205.flutter.e567b00`이다.
실제 GUI 실행 파일의 SHA256은 아래와 같다.

```text
87cabaacde34c42476540281c515f610a07e598d5edecdf1d6826159481e7544
```

minimal source `66732bc18ed28d9eed71336b4a2b018e09ad20b9`의 새 clone을 사용했다.
tracked 파일은 67개다. hardlink를 공유하지 않았다.
GUI 전용 HOME·tmp·Pub cache·SDK 목적지를 사용했다.
mise `2026.10.7`과 Java `Temurin 17.0.18+8`은 앞선 CLI 설치를 재사용했다.
실제 GUI child의 kernel path·binary SHA256과 명시한 환경값 20개를 관측했다.
원본 환경값을 공개하지 않았다.

GUI에서 iOS를 선택해도 Flutter 준비 대상은 `ios, android`였다.
repository trust는 false다. 자동 승인 범위는 `flutter.sdk` 하나다.
공식 Flutter `3.41.9`·Dart `3.11.5`·stable arm64를 확인했다.
revision은 `00b0c91f06209d9e4a41f71b7a512d6eb3b9c694`다.
[공식 ZIP](https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_3.41.9-stable.zip)의 승인 입력은 2147160009B다.
SHA256은 `d692b030a63466c44d6b2bc88583380371ecbe328f22cc4057835f59739821a1`이다.
목적지는 `<GUI_HOME>/Library/Application Support/dev.runstir/flutter/versions/3.41.9-arm64-00b0c91f0620`다.
별칭은 표시용이다. 실제 plan ID는 원본의 정확한 경로와 관측 입력으로 계산했다.

## 실제 GUI 순서

| 단계 | 관측 | 근거 ID |
| --- | --- | --- |
| 계획 확인 | 공식 SDK·Dart·checksum·목적지·resource key와 수동 단계를 표시했다. 자동 SDK 설치만 승인했다. | `screen12`, `screen14`, `screen15`, `plan-approval` |
| 다운로드 | 실제 GUI child 아래의 kernel `/usr/bin/curl`이 exact 공식 URL과 소유 payload 경로를 사용했다. Root 종료 영수증은 payload 증가를 기록했다. | `download-observation`, `cleanup-receipt` |
| 취소 | GUI 작업 취소 1회 뒤 `cancelled / exit 130`을 표시했다. 관측 child 잔여는 0개다. SDK는 설치 전 상태였다. | `screen17`, `cancel-observation`, `cleanup-receipt` |
| 재검사·재승인 | SDK가 여전히 필요했다. 새 검사의 plan ID는 원래 ID와 같았다. 같은 SDK 범위만 다시 승인했다. | `screen18`, `retry-approval` |
| 재시도 | GUI는 `running`과 작업 취소 버튼을 표시했다. | `screen19` |
| 결과 | `partial / exit 1`, 완료한 변경 `flutter.sdk`, 양쪽 플랫폼 `needs-approval`, 남은 항목 4개를 표시했다. | `screen21`, `SDK-after`, `final-after` |

처음 승인한 plan ID는 아래와 같다.

```text
9160b68734e04d1776446bed1046d63dc2dff670c34f2d17c2d1cee8db1b7dac
```

SDK 설치 뒤 GUI가 표시한 새 plan ID는 아래와 같다.

```text
7f809ad8b953081754f8b649715380175988e0f8463ab667e51c5324b8ef17cc
```

남은 항목은 `dependencies.flutter`, `android.flutter.generated`, `ios.flutter.generated`, `ios.simulator.runtime`이다.
`dependencies.flutter`는 새 승인과 별도 repository trust가 필요한 정렬이다.
나머지 3개는 native 입력·선택 scheme deployment 확인의 수동 경계다.
GUI는 SDK 설치 승인을 새 정렬 승인으로 확장하지 않았다.
이 실행은 실제 Android provider의 새 요구가 발생한 사례가 아니다.
조건부 Android 재승인 자동 검사와 이 실제 재계획을 구분한다.

`partial / exit 1`은 SDK 설치 실패를 뜻하지 않는다.
공통 설치 결과와 새 GUI SDK census가 SDK 설치를 입증한다.
새 SDK는 21990 entries·17918 regular files·4118754054B다.
제품의 exact size/checksum 검사와 완료 결과를 기록했다.
다운로드 완료 ZIP을 별도 snapshot으로 보존해 독립 checksum을 다시 측정한 증거는 없다.

## 보존과 정상 종료

최종 named 보존 검사 8개와 tracked 검사 6개를 원본끼리 다시 비교했다.
모두 같다. 기존 SDK·CLI SDK·기존 source·선택 root·전역 PATH·launchctl PATH·전역 Xcode 선택·기존 lease 기록을 비교했다.
GUI source의 HEAD·tracked 67개 bytes/mode·index·stage·flags·status가 같다.
기존 SDK와 CLI SDK의 전체 relative entry census도 같다.
각 SDK는 21990 entries·17918 regular files·4118754054B다.

사용한 lease 파일 2개는 unheld다. 정렬용으로 제안한 세 번째 lease 파일은 없다.
소유 stage 잔여는 0개다. GUI 정렬을 시작하지 않았다.
GUI 메뉴로 정상 종료했다. launcher는 실제 GUI child exit `0`을 기록했다.
종료 뒤 현재·과거 관측 child 잔여는 0개다.
그 뒤 정상 VM stop과 원 boot process의 exit `0`을 각각 수집했다.
보존 기준 VM 7개의 전후 metadata SHA와 disk stat은 timestamp를 제외하고 같다.
이는 VM disk 전체 bytes의 동일성 증명이 아니다.

선택한 `Library/Caches` root stat은 바뀌었다. 변경 actor는 unknown이다.
전체 HOME·cache bytes와 native 임시 경로의 전체 쓰기 집합은 입증하지 않았다.
관측 child 부재를 미관측·reparented child 전체의 부재로 확대하지 않는다.
export 41개는 harness 입력·상태 원본이다. 제품 HOME journal은 export하지 않았다.
따라서 GUI operation 결과는 화면과 설치 census로 연결한다. 미수집 journal로 연결하지 않는다.

## AC별 근거

[현재 #205](https://github.com/minjunkim-dev/mobile-runtime/issues/205)와 [#199 Testing Decisions](https://github.com/minjunkim-dev/mobile-runtime/issues/199)를 읽었다.
공통 실패·조건 변경 분기는 fixture로 검증한다. 실제 설치·다운로드·위험 경계 흐름은 별도 실측으로 연결한다.
도구별·표면별 인위적 실패의 전체 조합을 새 필수 matrix로 만들지 않는다.

| #205 조건 | 실제 근거 | 자동 검사·경계 |
| --- | --- | --- |
| AC1 공식 SDK·선언·재사용 | CLI의 적합 기존 SDK reuse, 별도 목적지의 실제 SDK 설치, GUI의 같은 공식 pin 설치, 기존 SDK 보존 | `FlutterProviderTests.officialIdentity`, `declarationProvenance`, `projectPinWins`, `sideBySidePlan`과 `FlutterProjectTests.conflictingPins`. 다른 version을 실제로 교체한 측정은 아니다. |
| AC2 workspace·entrypoint·migration | CLI의 실제 resolver workspace·entrypoint·locked Dart 정렬. 양쪽 surface의 stale native 입력과 수동 안내 | `workspaceIdentity`, `entrypointScope`, `workspaceMigration`, `generatedModuleHosts`, `publicEntrypoint`. native 생성·migration 완료나 앱 실행을 주장하지 않는다. |
| AC3 양플랫폼 상태·부분 완료·재승인 | CLI·GUI가 양쪽 항목·completed·partial·수동 단계를 표시했다. SDK 뒤 새 align plan을 반환했다. CLI는 새 exact 승인으로 align을 실행했다. GUI는 align 승인 대기에서 끝났다. | `FlutterPreparationTests.compatibleSDK`, `newlyDiscoveredAlignmentNeedsApproval`, `approvalInputs`과 공통 stale 승인 검사. 실제 Android 추가 요구 변경은 이 VM에서 측정하지 않았다. |
| AC4 SDK 성공·실패·취소·재실행 구분 | CLI 다운로드 취소130·SDK 재시도 완료·Dart 정렬 취소130·재시도 완료. GUI 다운로드 취소130·재검사·재승인·SDK 재시도 완료 | `FlutterInstallationTests.failureAndCancellation`, `completedInstallSurvivesCancellation`, `FlutterPreparationTests.lockedAlignmentAndCancellation`. 통제한 fake 실패를 실제 네트워크 장애로 표시하지 않는다. |
| AC5 / #199 AC02·AC03 연결 | 승인 버전·목적지, 기존 SDK 재사용과 나란히 설치, 실제 양플랫폼 결과, 완료 설치·tracked·선택 자원 보존을 위 기록으로 연결했다. | 실제 CLI·GUI 흐름을 fixture로 대체하지 않았다. 최종 독립 리뷰·필수 CI·위험별 최종 head 승인·병합·main CI는 별도 gate다. 전체 출시 AC 통과를 주장하지 않는다. |

동일 source의 기존 integration 기록은 Werror 763 tests/90 suites와 GUI build·CLI fixture 3개의 exit `0`을 담는다.
이 문서 작업은 검사·build를 다시 실행하지 않았다. 원격 필수 CI run도 아직 연결하지 않았다.
조건부 Android 추가 요구·stale 승인 경계는 최종 독립 리뷰와 필수 CI에서 해당 행동 검사의 커버리지를 확인해야 한다.

## 원본 검증

GUI export INDEX의 41개·29854894B를 bytes·mode·SHA256으로 다시 확인했다.
GUI 입력 INDEX 9개, CLI INDEX 108개, CLI export 95개도 다시 확인했다.
불일치는 0개다. 겹치는 원본을 고유 파일 수로 합산하지 않는다.
7개 화면 원본을 직접 읽었다. 화면 identity는 공개 JSON에 고정했다.
기존 immutable 원본과 Terminal 이력은 수정하지 않았다.
문서 갱신은 제품 source·Tests·VM·UI·네트워크 설치·프로세스 signal·원격 상태를 변경하지 않았다.

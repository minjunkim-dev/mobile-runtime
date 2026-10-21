# #205 FB CLI·GUI 준비 실측

두 surface는 승인한 `ios.simulator.create`와 `dependencies.flutter`를 완료했다. 제품 결과는 모두 `partial / exit 1`이다. 원본 strict 보존 검사는 **FAIL**이다. 이 결과는 전체 환경 준비나 #205 완료 판정이 아니다.

[구조화 결과와 전체 원본 pin](actual-supported-fb9167b.json): `35941B / aed2c8848a9c019350ed3f985f9e44d1d3920a39432ede5f8c1b8e7664d42721`. 이 문서의 자기 SHA는 기록하지 않는다. 후속 README와 manifest는 별도로 동결한다.

## 고정 범위

- 측정 source: `fb9167b1f0589645b3ccbdd8b26b0f67d5e00a70`. Tree: `bfae13ffa33713d2e7553008679d2949ca148fe8`.
- CLI SHA256: `0ac19e44192b8513e66247feac6a791d90e4027982d3980c2408d93ddcb3340a`.
- GUI SHA256: `327b574db2689cf41fe30a505c41eb8a94ae410d173772da0b5a9feb6621827b`.
- 입력은 source `66732bc18ed28d9eed71336b4a2b018e09ad20b9`의 별도 소유 clone이다. 각 clone은 tracked67개다. workspace는 package1개다. entrypoint는 `lib/main.dart`다.
- 기존에 수동 준비한 Flutter3.41.9/Dart3.11.5 SDK를 재사용했다. SDK census는 각 21,994 rows다. 새 24ee SDK CLI의 21,990 rows와 구분한다. Xcode27.1/27A9275와 iOS27.1/24A94425/arm64의 private iPhone Duo를 사용했다.
- 이 component는 SDK installer 실행이 아니다. 기기를 생성했으며 부팅이나 앱 build/install/launch를 입증하지 않는다.

## 실제 결과

| surface | 승인·실행·재검사 | 결과 |
| --- | --- | --- |
| CLI | plan `65b169e2…`; 정확한 plan·resource4개·repository trust를 승인했다. native product PID1502/exit1이다. private create child2023과 locked Dart child2074를 관측했다. | completed 두 action, changedFiles `[]`, Android manual9개다. 같은 private Duo `9F1BBDDD-22C8-4E71-B384-4F4377E791EA`를 재사용했다. 다음 plan `3ddd4811…`은 미승인이다. |
| GUI | 화면의 plan `67f15544…`와 두 action을 검토했다. repository trust를 별도로 선택했다. | 화면은 completed 두 action과 partial/exit1을 표시했다. private Duo `A69BE241-B687-4BDA-AAED-4B3A51BDEDF1`는 Shutdown이다. 다음 plan `2ba4c821…`은 미승인이다. GUI child2604는 정상 exit0으로 종료했다. |

CLI plan은 iOS18개와 Android19개 check를 표시한다. GUI도 양쪽 항목과 부분 완료·수동 단계를 표시한다. Android wrapper와 정확한 Gradle model 부족은 수동으로 남았다. native source 생성이나 migration은 실행하지 않았다. 새 미승인 plan은 실제 stale 승인 거부를 측정한 증거가 아니다.

GUI 화면·private device after를 결합해 operation 완료를 기록했다. GUI serialized full plan과 모든 짧은 Dart/native child의 원시 추적은 없다. GUI process exit0과 operation exit1을 구분한다. 관측하지 않은 child까지 없었다고 주장하지 않는다. VM 정상 종료는 이 component 기록의 범위가 아니다.

## 보존 FAIL과 미확인

1. CLI·GUI after의 `defaultInventory=false`와 native after exit1을 그대로 유지한다. source tracked67·HEAD/index/stage/flags/status, 명명한 SDK/JDK/Pub-cache/protected roots·PATH·Xcode 비교와 reviewed lease4개 해제는 별도로 통과했다.
2. GUI의 기존 global device lastUsedAt만 `10:09:33Z→10:34:50Z`로 바뀌었다. actor는 UNKNOWN이다. CLI 재검사에서 확인한 좁은 query-child 시각 근거를 GUI에 적용하지 않는다.
3. 선택 cache directory mtime 변화의 actor는 UNKNOWN이다. 전체 HOME/cache 불변은 미증명이다. 명명한 SDK/cache census 동일성으로 이를 대체하지 않는다.
4. 제품 화면 PNG16개는 JSON의 비공개 경로 alias·bytes·SHA로만 연결한다. 새 이미지를 공개 tree에 넣지 않았다. screenshot13과14는 같은 `134549B / 2987969833a6b7631640597e7fda6a0be1092d4d34e633ca199c0919c233968c`다. 두 번의 독립 관측으로 세지 않는다.

JSON은 CLI export31개/44,218,683B와 GUI export25개/53,073,710B의 전체 member pin을 포함한다. 각 decoded 원본의 bytes·SHA를 index와 직접 대조했다. 원래 mode와 host 저장 mode를 구분한다. raw base64·source/cache 내용·자격값·인증 화면은 넣지 않았다. 기존 독립 Security 보고서는 각 FB 원본의 material finding0을 기록한다. 이 판정은 strict FAIL을 PASS로 바꾸거나 이 최종 문서 head를 승인하지 않는다.

## 24ee와 연결하는 범위

후속 product `24ee6e9752e1f39ac6a999113743e054082fed48`는 FB 대비 설치 guard3줄과 test57줄을 추가했다. SDK 최종 inspection의 await 뒤 최초 source snapshot을 다시 비교한다. Duo·Dart 성공 경로에 mutation을 추가하지 않는다. 의미 있는 RED2개 기대→GREEN과 전체779 Werror 검증은 fixture다. source별 영향 분석과 원본 review pin은 JSON에 연결했다.

FB actual의 source와 binary는 FB로 유지한다. 이를 exact24ee Duo·Dart actual로 표시하지 않는다. [24ee SDK CLI 실측](sdk-cli-24ee6e9.md)은 다른 소유 root와 binary의 증거다. 두 component를 최종 AC에 결합하는 판단은 final-head 독립 리뷰에서 한다.

#205 AC1·2는 SDK reuse·declaration/workspace/entrypoint·수동 migration 경계에 연결한다. AC3은 CLI·GUI의 양플랫폼 partial/manual 표시에 연결한다. AC4는 실제 locked Dart 정렬과 SDK installer/app 실행의 구분에 연결한다. AC5와 부모 AC02·AC03에는 실제 승인·실행·재검사·선택 보존과 원본 FAIL을 함께 연결한다.

SDK GUI·current stale-selector·최종 공개 manifest·whole-head 독립 리뷰·필수 CI·최종 head 사람 승인·병합·main CI·issue 종료는 별도 미완료 gate다. [old121 실패](native-compatibility-121f0db/README.md)와 e567 실제 이력도 보존한다.

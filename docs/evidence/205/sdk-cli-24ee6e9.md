# #205 24ee SDK CLI 실측

공식 Flutter SDK의 실제 다운로드 취소와 재시도 설치를 확인했다. 재시도 제품 결과는 `partial / exit 1`, completed는 `flutter.sdk` 하나다. 설치 후 계획은 같은 SDK를 재사용했다. strict 보존 검사는 **FAIL**이다. 전체 환경 준비나 #205 완료를 뜻하지 않는다.

[구조화 결과와 원본50개 pin](sdk-cli-24ee6e9.json): `27028B / d03a9907322f56ddd43d4677af3a31e4fab801818fd3e9a08aef81abac883cef`. 이 문서의 자기 SHA는 기록하지 않는다. 최종 README와 manifest는 별도 동결 대상이다.

## 입력과 승인

- 제품 source `24ee6e9752e1f39ac6a999113743e054082fed48`, tree `4bd46b907b9d43dfee68207358515a88e9028c82`다. CLI binary SHA256은 `e29f2db3fc2a8a7edc44ced5d6a9cb65852a8dd15096a908229b9e8ec4abcc81`이다.
- 별도 소유 SDK CLI root는 시작 시 SDK가 없었다. 공식 Flutter3.41.9/stable arm64, Dart3.11.5, framework revision `00b0c91f06209d9e4a41f71b7a512d6eb3b9c694`를 승인했다.
- 공식 ZIP은 `2147160009B / d692b030a63466c44d6b2bc88583380371ecbe328f22cc4057835f59739821a1`이다. [공식 ZIP URL](https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_3.41.9-stable.zip)과 metadata SHA는 JSON에 연결했다.
- 자동 action은 `flutter.sdk/install` 하나다. resource key는2개다. repository trust는 false다. Dart 정렬이나 native 준비는 승인하지 않았다.

## 실제 순서

| 단계 | 실제 관측 | 판정 범위 |
| --- | --- | --- |
| 취소 | product3974/native130, state cancelled다. 공식 payload curl4160과 크기 `77824→2519040B`를 관측한 뒤 정확한 제품 PID에 SIGINT를 보냈다. completed/changedFiles `[]`와 관측 잔여 child `[]`다. | 실제 다운로드 중 취소다. transport exit0을 제품 exit130과 구분한다. |
| 새 승인·재시도 | 새로 검사한 plan `668fac7221070d938fccecbe1164d11b122daf8c46f898dd4ca0b597416b4f7e`의 SDK action만 승인했다. product4275/native1, state partial, completed `[flutter.sdk]`다. operation error는 없다. | SDK 설치 완료다. 전체 준비 완료나 앱 실패로 표시하지 않는다. |
| 설치 후 재검사 | product exit0이다. 양쪽 SDK check가 reuse다. SDK 자동 설치는 다시 제안하지 않았다. 다음 plan은 `faf5660f31c9b30966c4931693f4f1849a6fd08e457e91aab16650e20fe16418`이다. | 새 `dependencies.flutter` 정렬은 미승인·미실행이다. 승인 범위를 자동 확장하지 않았다. |
| strict after/export | after28218/native1이다. export31561/native0이다. 두 lease는 unheld며 소유 stage는 없다. | export 성공은 보존 PASS가 아니다. 원본 FAIL을 그대로 보존했다. |

설치 metadata의 Flutter3.41.9/Dart3.11.5와 regular Dart executable bytes를 확인했다. SDK census는21,990 rows다. SHA256은 `e8fef0699a9944f66487f8e49e2862c8512081f2692f90e96460afc01db6c1ce`다. 이는 공식 Flutter bootstrap·compiler matrix·앱 build/run 실행의 증거가 아니다. product의 size/checksum 검증과 별도로 완료 ZIP을 보관해 독립 재해시했다는 주장도 하지 않는다.

## strict FAIL과 Root 보완 관측

`sourceFull=false`, `defaultInventory=false`다. 나머지8개 명명한 보존 항목은 true다. selected cache stat도 같다. 전체 HOME/cache 불변은 미증명이다.

Root의 native36199/exit0 보완 관측은 기존 tracked67·HEAD/index/stage/flags/status가 모두 같고 source file content/mode 변화가 `[]`임을 확인했다. full source rows는140→142다. Xcode project `xcshareddata` 부모 directory size가128→160으로 바뀌었다. `swiftpm`과 `configuration` directory가 추가됐다. `swiftpm`에는 `configuration`만 있다. `configuration`은 비어 있다. 추가 regular/link file은0개다. directory actor는 UNKNOWN이다. global 기존 device lastUsedAt의 `10:34:50Z→11:11:18Z` 변화 actor도 UNKNOWN이다. directory를 삭제하거나 baseline을 정상값으로 바꾸지 않았다.

Root guest review는 `2645B / c5fa7261e66d207b9585bccd28b4e9e42b90727fd6e7bc0dfaebdf77b96b11fa`다. 이를 담은 host stdout은 `3005B / 0f2b47ba4d1f559f1118fbbd9e90cce09438855240ed219e22326ec093e68748`다. JSON은 이 관측의 command/pid/exit/streams·script pin을 연결한다. 이 Root 관측과 별도로 새 SDK actual의 독립 Security 보고서를 확인했다. 보고서는 `15875B / f0c52cbdd7d550b9871d2c917c151259fa7b39185d17312e7406e7f152b927c9`다. 경로와 pin은 JSON에 연결했다. 확정 material finding0이며 strict FAIL2개와 actor UNKNOWN2개를 유지한다. 같은 모델의 별도 맥락이다. 검토자가 decoder 작성자이므로 decoder 자체의 새 독립 인증은 주장하지 않는다. 최종 문서 head의 독립 승인도 아니다.

JSON은 export50개/62,285,647B의 전체 decoded 원본을 index와 bytes·SHA로 대조한 pin 목록을 포함한다. index는 `10118B / a7dcbc4cfa876a838ff482aee8c99b096b5c33dafc0cc01ac7dc0e626c5c00a6`이다. raw export stdout은 `83055693B / 420e52d756b169cb863e5ad3d52ce130a8212acb5dd2063bb72fab5f60078bf5`다. 원본 mode와 host 저장 mode를 구분한다. 원본 base64나 SDK/source/cache 내용·자격값은 공개하지 않는다.

## source와 AC 범위

[FB CLI·GUI Duo·Dart component](actual-supported-fb9167b.md)는 `fb9167b1f0589645b3ccbdd8b26b0f67d5e00a70`로 측정했다. 후속24ee의 product3줄/test57줄은 SDK 최종 inspection 뒤 source 재검사를 강화한다. 이 guard의 RED→GREEN·전체779 Werror는 fixture다. 실제 네트워크 오류 행렬로 표시하지 않는다. FB actual을 exact24ee Duo·Dart actual로 재표시하지 않는다.

이 SDK CLI 결과는 #205 AC1의 공식 입력·설치·재사용, AC3의 SDK-only 승인과 다음 operation 미승인, AC4의 다운로드 취소·재시도와 앱 실행 구분에 연결한다. AC2의 workspace/entrypoint·native 수동 경계와 양 surface의 Dart 정렬은 FB component와 source tests로 별도 연결한다. AC5 및 부모 AC02·AC03에는 위 실제 순서와 strict FAIL/UNKNOWN을 함께 제시한다.

SDK GUI·current stale-selector·최종 공개 manifest·최종 whole-head 독립 리뷰·필수 CI·최종 head 사람 승인·병합·main CI·issue 종료는 별도 미완료 gate다. 기존 e567/old121 이력을 유지한다. 이 네 새 문서는 #205 완료 증거 전체가 아니다.

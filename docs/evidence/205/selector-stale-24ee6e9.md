# #205 24ee stale 승인 거부 실측

지원하는 Android selector 선언을 추가한 뒤 이전 준비 plan 승인이 거부됐다. 제품5883은 native/JSON exit1과 `needs-approval`을 반환했다. 새 plan B는 승인하지 않았다. 마지막 strict 보존 검사는 **FAIL**이다. #205 전체 완료 판정이 아니다.

[구조화 결과와 전체 원본29개 pin](selector-stale-24ee6e9.json): `25058B / 10c4f1d79ea30fcdead6285d6ec0d5e67abd55c2495ecac940fed44c7d8e14d7`. 이 문서의 자기 SHA는 기록하지 않는다. README와 manifest는 별도로 동결한다.

## 고정 범위와 입력

제품 source는 `24ee6e9752e1f39ac6a999113743e054082fed48`다. Tree는 `4bd46b907b9d43dfee68207358515a88e9028c82`다. CLI SHA256은 `e29f2db3fc2a8a7edc44ced5d6a9cb65852a8dd15096a908229b9e8ec4abcc81`이다. [SDK CLI 실측](sdk-cli-24ee6e9.md)을 마친 별도 소유 root를 재사용했다. 기존 SDK21990 rows와 census `e8fef0699a9944f66487f8e49e2862c8512081f2692f90e96460afc01db6c1ce`를 보존했다.

원래 없던 `mobile.yml`에 다음 선언만 추가했다. bytes26, mode0600, SHA256은 `b9bcbe5225b34a9e7b6b65d5bd529fa413ef24df42d84eb921b4078fb0393b62`다.

```yaml
android:
  variant: debug
```

기존 implicit debug를 explicit debug로 선언한 입력 변화다. 실제 Gradle model에서 effective variant나 추가 SDK 요구를 발견한 증거가 아니다. Android package 설치도 실행하지 않았다. 선언은 의도한 검증 입력으로 남겼다. 자동 복원하지 않았다.

## 실제 순서

| 단계 | 실제 native product 결과 | 의미 |
| --- | --- | --- |
| plan A | PID5769/exit0. ID `faf5660f31c9b30966c4931693f4f1849a6fd08e457e91aab16650e20fe16418` | SDK를 재사용하는 실제 새 계획이다. |
| A 반복 | PID5824/exit0. 전체 plan이 A와 같다. | 조건이 안정된 기준을 확인했다. |
| 선언 추가 뒤 old A 승인 | PID5883/exit1, JSON1, needs-approval | `Plan conditions changed. No preparation changes started.` completed/changedFiles `[]`. running preparation stage event는0개다. |
| 새 plan B | PID5937/exit0. ID `df9efc652b4929a4d4cadf54603b625c5c768ad5c7d1939b61126f0c2660d4f5` | 거부 결과의 B와 전체 plan이 같다. B는 미승인이다. |
| strict after / export | Root probe70906/exit1. export78216/exit0. | Root exit1은 마지막 strict global inventory 실패다. 제품의 의도한 stale 거부 exit1과 구분한다. |

계획 차이는 새 config digest·plan identity와 config-derived display3개다. `ios.config.values`의 출처/표시 대상이 `no mobile.yml→mobile.yml`로 바뀌었다. iOS와 Android에는 정확한 config syntax reuse 표시가 추가됐다. 실행 steps·commands·환경·destination·artifact·native 요청은 그대로다. repository trust는 false다. 새 승인을 자동으로 부여하지 않았다.

거부 호출의 progress는 operation-level started→finished다. preparation stage running은 없다. 이 결과는 native inspection query가 전혀 없었다는 뜻이 아니다.

## 보존 FAIL과 정확한 비교

12개 named check 중11개는 true다. `defaultInventory=false`는 그대로다. 기존 global device의 lastUsedAt 한 leaf가 `11:11:18Z→11:25:55Z`로 바뀌었다. actor는 UNKNOWN이다. 다른 native inventory 차이나 actor 확정을 주장하지 않는다.

tracked67의 bytes/mode와 HEAD/index/stage/flags는 같다. raw Git status는 `""→"?? mobile.yml\n"`로 바뀌었다. 이를 동일하다고 정규화하지 않는다. full source142→143 rows의 차이는 새 `mobile.yml` 한 row다. 나머지 row는 같다. SDK와 SDK identity·JDK·candidate·protected roots·선택 cache stat·PATH·Xcode·lease/device-set 비교도 그대로다. 전체 HOME/cache/VM이나 미관측 child 보존은 입증하지 않았다. 이전 SDK 구간의 strict FAIL과 directory/global actor UNKNOWN도 해결로 바꾸지 않는다.

## 원본과 도구 이력

raw export는 `91753475B / b66e8783e84935a52cde9c90364b98776f08450f69d2b0138fa167b158a0c969`다. 원본29개 합계는68,811,680B다. 모든 member를 in-memory strict base64로 읽고 size·full SHA를 대조했다. decoded host 파일을 새로 만들지 않았다. JSON은 모든 원본 member의 이름·bytes·original mode·SHA와 host command/pid/exit/stream pin을 담는다. raw base64·SDK/source/cache 내용·자격값·인증 화면은 공개하지 않는다.

V1 probe는 VM에 전송하거나 실행하지 않았다. pre-use 검토는 stage event key와 A/B config 표시 비교의 두 결함을 확인했다. v2 SHA256은 `4f5cfa82353fbd6a4ebf5a28344e7b0dbc3657508670d81b49d721b44961a148`이다. pure RED62861/native1은52 tests의2 failures/1 error다. 두 교정 뒤 GREEN65215/native0의52 tests가 통과했다. 권한·profile·환경 경계는 넓히지 않았다. 이 검사는 synthetic이며 실제 제품 실행을 대체하지 않는다.

Root의 첫 host 분석에서 atime을 포함한 whole-stat assertion이 실패했다. 후속 frozen identity와 full raw SHA 검증은 통과했다. 이는 도구 분석 이력이다. 위 제품 native 결과나 실행 횟수에 합치지 않는다.

독립 Security 보고서는 `13664B / 2353247fd1cf0226d753d3254517d5fdc9f2138a2446713771bef513a18143d3`다. 경로와 pin은 JSON에 연결했다. 확정 material finding0이다. 원본 strict defaultInventory FAIL과 timestamp actor UNKNOWN은 유지한다. 같은 모델의 별도 맥락이다. 원본29개·native receipts·frozen29 pin·V2 diff와 RED/GREEN 및 실제 A/B·config·선택 보존을 검증했다. 이전 SDK decoder는 이번 selector export 검증에 쓰지 않았다. 읽기 구간의 identity/full SHA 불변은 atime을 제외한 비교다. 이는 과거 전체 불변이나 최종 문서 head 승인으로 확대하지 않는다. 이 결과는 #205 AC3과 부모 AC03의 좁은 stale 승인 거부 증거다. SDK GUI·최종 공개 문서/manifest·whole-head 독립 리뷰·필수 CI·최종 head 사람 승인·병합·main CI·issue 종료는 별도 gate다.

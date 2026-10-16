# #203 7b58ed5 실제 GUI 검증

2026-10-16에 GUI에서 현재 계획을 승인했다.
Java·Node·Ruby 설치 3개를 완료했다.
setup 결과는 `partial`, exit `1`이다.
iOS와 Android는 `waiting-manual`이다.
SDK·Gradle·React Native dependency 수동 작업은 수행하지 않았다.
이 기록으로 앱 실행이나 #203 전체 완료를 판정하지 않는다.

[curated JSON](actual-gui-7b58ed5.json)은 pin과 선택한 private receipt 참조를 담는다.
원본 payload와 원본 전체 로그는 공개하지 않는다.

## 후보와 승인

- source HEAD: `7b58ed51a7bc8dff84979fd505e189e053024f33`
- base: `ebccdd3beef05ba60f0069281ea0637af3cfb8e1`
- 34파일 canonical diff SHA256: `f75100b1429c1af6f3e2f6b2146bce3ec9e0bda6704f9e045b4f530d24e6a6b1`
- 실행한 signed GUI SHA256: `d046c5e5fc10e79975a5854bfc763ba166dadac33336d1173e6fa7ee03216468`
- 같은 환경의 mirror CLI SHA256: `4bf9740ee1c042cc3478547afca023554d0312cb395f73ef2ce387f6d6cfa79e`

실측 source는 clean이었다.
GUI는 계획 목록에 고정 높이를 주는 후속 수정을 포함한다.
GUI 15파일과 함께 전송한 CLI 13파일의 host·guest bytes와 mode를 대조했다.
ad hoc 서명과 strict 검증을 통과했다.
이 서명은 배포 서명이나 공증 근거가 아니다.

Root가 이전 `7b58ed5` 검사 기록의 `command.json`에서 과거 후보 base 필드를 발견했다.
실제 HEAD·tree·명령·로그는 `7b58ed5` 기록이다.
잘못된 base 필드가 있는 원본도 보존한다.
이전 677개 테스트·81개 suite는 `7b58ed5` 구현 검증 근거다.
이를 최종 main 통합 HEAD의 고정 base 검증으로 주장하지 않는다.
최종 통합 HEAD의 Werror·GUI build·CLI3 검증은 별도 Root 작업이다.
이 문서의 source base와 diff pin은 별도 source-isolation receipt에서 가져왔다.

입력은 tracked 파일 8개와 `.git`을 복사한 소유 프로젝트다.
hardlink는 없다.
소유한 HOME·tmp를 재사용했다.
tool-store는 설치 전에 비어 있었다.
기존 mise `2026.10.7`을 PATH에서 읽기 전용으로 재사용했다.
저장소 스크립트 신뢰는 꺼 두었다.
승인한 PLAN ID는 `fb1a8f533dc6a363e32a5a354c848f2a709f6f7d6ef2a4b84ba8b5b8492c9fd6`이다.
승인 대상은 새 store의 Java·Node·Ruby 3개다.
3개는 store root의 resourceKey 하나를 공유한다.

| 공식 archive | 버전 | bytes |
| --- | --- | ---: |
| Temurin JDK | `17.0.18+8` | 185658966 |
| Node | `22.23.2` | 50068815 |
| Ruby | `3.2.2` | 39479292 |

archive 3개의 실제 다운로드 bytes와 보존 복사본 SHA256이 공식 pin과 같았다.
관측한 curl identity 17개는 모두 stock `/usr/bin/curl` 경로와 SHA256이 같았다.
0.2초 간격으로 관측했다.
관측하지 못한 짧은 process 전이는 입증하지 않는다.
설치된 정확한 실행 파일 3개의 version 조회는 모두 exit `0`이다.
새 tool tree 3개는 기존 동일 pin tree와 bytes·mode·symlink target이 같았다.

## 설치 결과와 재검사

| 관측 | 결과 |
| --- | --- |
| GUI 승인·설치 | `partial / exit 1`. 완료한 변경은 `tools.java`, `tools.node`, `tools.ruby`다. |
| GUI 읽기 전용 재검사 | `needs-approval / exit 0`. 추가 승인은 하지 않았다. |
| 같은 env7의 CLI PLAN 1회 | `needs-approval / exit 0`. 수동 단계 12개. installation metadata 0개. 도구 설치 단계 0개. |

재검사 PLAN ID는 `1e8ce8fe1d66e0ec677225e40b8a09b724a7befa77f1884003cce1e5ccebbbdf`다.
Root가 화면과 CLI JSON의 실제 ID 일치를 확인했다.
앞선 전달 문자열에서 `b` 하나를 빠뜨렸다.
그 63문자 문자열과 비교한 raw `sameAsPrevious=false`는 보존했다.
이 전사 오류를 설치 대상 변경이나 제품 불일치로 분류하지 않는다.

GUI의 원래 stdout·stderr는 각각 0B다.
GUI 반환 JSON과 GUI 단계 NDJSON은 캡처하지 못했다.
화면 결과, watcher 관측, filesystem 감사와 version 조회는 서로 다른 근거다.
추가 CLI PLAN의 JSON·progress 로그는 GUI 원본 로그가 아니다.

## 보존 범위와 시각

fresh before34는 UTC `10:39:02` 기록이다.
full after03는 UTC `11:05:22` 기록이다.
source8·index·flags·config, 기존 후보, readonly mise, 기존 tool tree,
기존 CLI 완료 store, 보존 archive, PATH와 system binary를 포함한 17항목이 같았다.
GUI env7도 같았다.
기존 Java·Node·Ruby tree entry는 각각 543·5865·16721개다.
기존 CLI 완료 store entry는 23149개다.
이 full tree 보존 범위는 after03까지다.

host 감사는 UTC `11:01:09`와 `11:05:29` 기록을 비교했다.
기존 CLI 원본188파일과 후보98파일의 SHA256·bytes·mode가 같았다.
보호 VM 6개는 stopped였다.
작은 metadata 전체 SHA256과 disk stat이 같았다.
전체 disk bytes는 hash하지 않았다.

선택한 HOME 항목에서는 새 GUI preference 파일만 달랐다.
변경 actor와 원인은 미확인이다.
`Library/Caches` root stat은 before34와 같았다.
전체 HOME·cache bytes 보존으로 판정하지 않는다.

추가 CLI PLAN 전후에는 source8·index·stage·flags와 새 bin3 SHA를 따로 대조했다.
그 결과가 같았다.
UTC `11:12:35` 최종 idle 검사에서 GUI 자식·이전 관측 소유 process·stage는 0개다.
정확한 lease 파일 2개는 각각 0B다.
`lsof`는 열린 핸들을 찾지 못했다.
advisory lock 가용성은 검사하지 않았다.

## 화면과 이전 CLI의 관계

- [47: Java·Node artifact 계획](gui-7b58ed5/47-fullscreen-plan.png)
- [48: Node·Ruby artifact 계획](gui-7b58ed5/48-plan-artifact-node-ruby.png)
- [51: GUI partial 결과와 완료 3개](gui-7b58ed5/51-gui-install-result.png)
- [54: GUI 읽기 전용 재검사](gui-7b58ed5/54-gui-reinspection-fullscreen.png)

PNG는 Root가 보존한 원본이다.
표시된 `admin` 경로는 검증 VM의 synthetic 경로다.
공개 JSON의 개인·private 경로는 alias로 정규화했다.

[이전 실제 CLI](actual-cli-b6329329.md)의 실행 파일 SHA256은 `23bcc69031678029a62c7618bde9fca00d81ace1d77ddfc0072011f09447a1aa`다.
이번 mirror CLI의 bytes는 그 실행 파일과 다르다.
두 source 사이의 `Sources`·package 입력 차이는 GUI 파일 하나다.
이를 byte가 같은 rebuild나 이전 CLI 실측의 대체로 주장하지 않는다.
기존 CLI 취소·실패·미확인 기록과 그 한계를 보존한다.
Root의 후속 종료·VM lifecycle 결과는 이 문서의 측정 범위 밖이다.

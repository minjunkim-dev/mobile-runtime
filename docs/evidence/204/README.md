# #204: 소유 SDK prefix의 승인 설치 실측

To-do의 부족한 SDK package 두 개를 실제 Google archive로 설치했다.
공개 `PreparationExecution.run`과 소유 `ResourceLeases`를 사용했다.
최종 code `73f20f95ba6073c313c4570550e638af51285275`의 공개 API 계획과 실제 CLI 계획은 SDK 설치 단계 0개와 요구 blocker 0개를 반환했다.

## 입력과 결과

- [고정 입력과 archive pin](inputs.json)
- [결과와 시도별 product 상태](results.json)
- [실제 최종 CLI 계획](actual-cli-plan.json)
- [시도 이력](attempts.md)
- [실행한 소유 harness](harness.swift), [컴파일 명령 생성기](compile-harness.py), [실행 기록기](run-harness.py), [쓰기 guard](owned-writes.sb)
- [로컬 검사 명령과 결과](local-checks.json), [저장 파일 checksum](checksums.json)
- [소유 경로에 보존한 원본 receipt의 해시](private-receipts.json)

소스는 `android/architecture-samples`의 `ee66e1526b84c026615df032c705842b7d2a521f`다.
실제 tuple은 Gradle 8.11.1, AGP 8.7.3, daemon JDK 17.0.19, compile SDK 35, Build Tools 34.0.0이다.
SDK와 기존 작업 소유 Gradle cache는 APFS `cp -cR`로 복제했다.
공유 원본에 설치하지 않았다. 전역 PATH나 도구를 변경하지 않았다.

Build Tools 설치는 `0b0cd7d642e4595b8c46888bf3751df9f092cb0e`에서 측정했다.
그 뒤 두 번째 payload 전에 통제한 실패를 넣었다. 첫 package를 보존했다.
새 계획은 platform 35 하나만 제시했다. 이전 계획 승인은 `needs-approval`로 거부했다.
같은 SDK root의 소유 lease 충돌도 다운로드 전에 중단했다.
`a50d6528dfc49bd6fb5199e2140adb0587eeeb97`에서 남은 platform을 설치했다.
SDK 준비 뒤에도 AVD와 guard 아래의 workspace 수동 단계가 남아 결과는 `partial`이었다.

기존 license hash `24333f8a63b6825ea9c5514f83c2829b004d1fee`를 재사용했다.
새 license를 수락하거나 record를 추가하지 않았다.
공식 `sdkmanager --licenses` 대조에는 `n`만 입력했다. record bytes는 그대로였다.
원격 XML license의 raw SHA-1을 사용한 초기 판단은 잘못이었다.
공식 JAXB `TrimStringAdapter`를 확인하고 정규화 규칙을 수정했다.

## 보존과 한계

소스의 tracked 파일 119개 bytes·mode·index flags가 전후에 같았다. 최종 소스는 고정 SHA와 일치했다.
먼저 설치한 Build Tools의 171개 파일 bytes·mode도 후속 실패와 재실행 뒤에 같았다.
원본 SDK 124,166개, 복제 원본 cache 26,230개, 전역 `.android` 14개의 `lstat` 메타데이터가 전후에 같았다.
전역 Emulator console token의 `stat`도 같았다. key/token 내용과 해시는 읽지 않았다.
원본 SDK/cache 전체 bytes 비교는 수집하지 않았다. 전체 HOME 불변도 입증하지 않았다.
guard는 이 작업과 하위 프로세스의 파일 쓰기를 소유 prefix와 `/dev/null`, `/dev/tty`로 제한했다.

597개 Swift 검사를 warnings-as-errors로 통과했다. doctor/workflow/setup executable fixture 검사도 통과했다.
fixture 결과는 실제 SDK 설치 결과와 별개다.
실제 CLI는 계획만 실행했다. 설치는 공개 API를 호출한 소유 harness에서 측정했다.
GUI 설치 조작, 도구가 없는 VM, 앱 build/install/launch/첫 화면은 이 실측의 근거가 아니다.
서로 다른 source에서 측정한 취소·설치·최종 계획을 하나의 source 실측으로 합치지 않는다.
독립 리뷰, 원격 CI, main 병합과 main CI는 상위 작업에서 별도로 확인한다.

# ADR-0039: 승인한 프로젝트 도구 준비

- 상태: Proposed (#203 source/fixture 구현)
- 날짜: 2026-10-16
- 근거: [#199](https://github.com/minjunkim-dev/mobile-runtime/issues/199), [#203](https://github.com/minjunkim-dev/mobile-runtime/issues/203)

## 문맥

프로젝트 도구가 없으면 의존성 검사부터 실행할 수 없다.
이 실패가 도구 설치 계획과 승인 실행을 막으면 준비를 시작할 수 없다.
manager의 install 명령은 승인 목록에 없는 payload나 source build를 실행할 수 있다.
전역 선택을 바꾸면 다른 프로젝트의 도구도 바뀐다.

## 결정

기존 공유 준비 계획, 승인, 재확인, lease와 `InstallationAction`을 사용한다.
도구 provider가 새 승인 실행부를 만들지 않는다.
doctor/build/up은 관측만 한다.
down은 도구 준비를 요구하지 않는다.

Tier 1 exact 선언을 정본으로 사용한다.
서로 다른 선언을 임의로 고르지 않는다.
범위는 적합한 현재 실행 파일을 우선 재사용한다.
없으면 명시한 exact 고정 후보를 검사한다.
후보는 Node `22.23.2`, Ruby `3.2.2`, Temurin `17.0.18+8`이다.
후보를 실제 VM 검증 완료로 부르지 않는다.
JDK 21 요구에 JDK 17을 제안하지 않는다.
Java의 새 설치는 기존 AGP/Gradle/JDK 표에서 호환을 확인해야 한다.
해결할 수 없는 선언이나 호환 입력은 수동 단계로 남긴다.
정본 파일은 수정하지 않는다.

지원하는 현재 manager와 정확한 도구를 재사용한다.
manager가 없으면 정확한 mise bootstrap을 계획에 제안한다.
다른 manager의 숨은 install, default packages와 Ruby compile은 실행하지 않는다.
새 payload는 공식 metadata의 URL, 크기와 SHA256으로 계획에 고정한다.
승인 조건이 바뀌면 새 계획을 요구한다.
공유 cache를 쓰거나 되돌리지 않는다.
임시 다운로드·추출 위치는 승인한 저장소 아래에 표시한다.

새 archive는 기존 버전 옆에 설치한다.
TAR의 경로, 링크와 entry 종류를 추출 전에 검사한다.
선택한 package 밖의 링크를 거절한다.
실제 stage의 architecture, minimum macOS와 linked library를 검사한다.
빌드 runner의 OS 이름을 minimum macOS로 사용하지 않는다.
최종 목적지가 생기면 덮어쓰지 않는다.
완료한 설치와 기존 버전을 삭제하지 않는다.

기존 JDK는 Java properties collector를 재사용한다.
version, runtime build, vendor, architecture와 실제 home 실행 파일을 확인한다.
banner만으로 vendor를 추측하지 않는다.
적합한 기존 Zulu를 재사용할 수 있다.
새 Zulu 설치와 자동 vendor 교체는 추가하지 않는다.
새 설치의 Java 배포는 명시한 exact Temurin으로 제한한다.

설치 action이 있는 동안 그 도구가 필요한 프로젝트 검사를 뒤로 미룬다.
완료 후 새로 관측한 SDK나 의존성 변경은 다음 계획에서 승인한다.
manual 단계만 있다는 이유로 기존 SDK 검사를 지우지 않는다.
프로젝트 child command에만 정확한 실행 파일, PATH와 JAVA_HOME을 적용한다.
전역 PATH, 사용자 shell과 기존 manager 선택을 수정하지 않는다.
미충족 `tools.*` 요구는 build/up의 변경 전에 차단한다.

## 결과와 검증 경계

설치 중 실패와 취소는 기존 공유 결과 계약을 유지한다.
완료한 도구는 재사용하고 남은 계획을 다시 만든다.
fixture는 실패, 취소, partial, stale approval, 재시도와 실제 child process 경계를 검사한다.
이 검사는 실제 tool archive 설치, VM, GUI나 기기의 근거가 아니다.
실제 배포 payload와 양 surface 검증은 별도 게이트다.
[증거 묶음](../evidence/203/README.md)에 그 범위를 기록한다.

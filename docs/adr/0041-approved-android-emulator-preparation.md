# ADR-0041: 승인한 Android system image와 새 AVD를 준비한다

날짜: 2026-10-19
상태: provider 구현. 실제 CLI·GUI 설치·생성 검증은 별도다.
관련: #207, #204, #199, ADR-0009, ADR-0013, ADR-0035

## 범위

`build/up`의 자동 provisioning 금지를 유지한다.
`PreparationExecution`이 승인·재검사·lease·취소·완료 기록을 담당한다.
Android provider는 image와 AVD의 정확한 입력과 실행 동작만 제공한다.
CLI와 GUI는 같은 계획과 결과를 사용한다.

기존 적합 AVD를 먼저 재사용한다.
`android.avd` 선언, 호환되는 실행 중 기기, 단일 설치 기기의 선택 순서를 유지한다.
복수 후보는 선택을 요구한다. 부적합한 선언 기기를 다른 기기로 바꾸지 않는다.
기존 기기의 API가 35가 아니어도 프로젝트의 minSdk·ABI를 만족하면 재사용한다.

새 설치의 고정 검증 후보는 Google APIs API35 `arm64-v8a` image와 `pixel_7` profile이다.
API35를 프로젝트에 강제하지 않는다.
프로젝트의 minSdk·ABI가 이 후보와 맞지 않으면 수동 단계로 남긴다.
후보 선택은 일반 지원 범위나 실제 실행 성공을 뜻하지 않는다.
생성 도구가 없으면 exact `cmdline-tools;23.0`을 제안한다.
기존 적합 Command-Line Tools를 먼저 재사용한다. `latest` alias를 새로 설치하지 않는다.

## metadata와 승인

기존 SDK 도구는 공식 `repository2-3.xml`을 사용한다.
Google APIs image는 공식 `sys-img2-4.xml`만 사용한다.
구형 schema로 자동 전환하지 않는다.
API·tag·ABI가 package path와 다르거나 Emulator 최소 revision이 없으면 설치 후보에서 제외한다.
공식 metadata SHA-256과 archive URL·size·SHA-1·revision·license identity를 승인에 묶는다.
공식 SHA-1을 공급자의 SHA-256 서명으로 표현하지 않는다.

설치된 image·Emulator·생성 도구의 라이선스 기록을 따로 확인한다.
계획 승인은 라이선스 동의나 관리자 권한을 대신하지 않는다.
Runstir는 라이선스 동의 명령이나 `sudo`를 실행하지 않는다.
설치된 Emulator가 image의 최소 revision보다 낮아도 기존 설치를 교체하지 않는다.

image나 생성 도구가 없으면 기존 ZIP 설치기로 먼저 설치한다.
그 뒤 실제 설치 revision과 profile을 읽은 새 생성 계획을 반환한다.
AVD 생성에는 이 새 계획의 승인이 필요하다.
이전 archive 설치 승인을 새 기기 생성 승인으로 확대하지 않는다.

AVD 생성 계획은 이름·AVD home·SDK root·image package/revision·설치 metadata digest,
profile ID/digest·생성 도구 경로/revision·Emulator revision·공식 dependency metadata digest를 고정한다.
profile 조회도 전용 임시 Android user/AVD home을 사용한다.
생성 때와 같은 내장 profile을 읽는다. 사용자 profile override를 생성 identity로 섞지 않는다.
설치 metadata digest는 `source.properties`와 `package.xml`의 내용 식별값이다.
이미 설치된 `system.img` 전체의 checksum이나 archive provenance를 증명하지 않는다.

## 생성과 보존

설치는 기존 SDK root destination lease를 사용한다.
AVD 생성은 SDK root·AVD home destination lease와 `device:android:avd:<name>` lease를 함께 사용한다.
외부 Android Studio나 수동 도구는 Runstir lease를 따르지 않는다.
실제 검증은 별도의 중앙 자원 일정도 지킨다.

`avdmanager create avd`에 정확한 package·ABI·device profile·새 이름·전용 staging 경로를 전달한다.
`--force`를 사용하지 않는다. 생성 후 boot하지 않는다.
staging의 Android user/AVD home은 이번 작업만 소유한다.
생성 결과의 이름·profile·ABI·image 경로와 파일 형식을 확인한다.
`.ini`와 `.avd`를 각각 독점 rename으로 commit한다.
기존 파일·불완전한 디렉터리·dangling link도 덮어쓰지 않는다.

두 rename은 하나의 원자적 transaction이 아니다.
디렉터리 commit 뒤 등록이 실패하면 생성한 디렉터리를 보존한다.
실패·취소 뒤 확인한 자원을 `androidResources`로 보고한다.
불완전한 상태는 `incomplete`, 소유·완료를 확인하지 못한 결과는 `unknown`이다.
다음 계획도 이 경로를 보존하고 수동 복구를 안내한다.
SDK·AVD 일괄 삭제나 source 자동 복원을 하지 않는다.

source 감사는 정확한 새 `.ini`·`.avd`와 provider가 만든 staging 경로만 제외한다.
AVD home이나 SDK root 전체를 감사에서 제외하지 않는다.
기존 iOS `resources` JSON은 유지한다. Android 결과는 optional `androidResources`에 추가한다.

## 검증 경계

parser·생성·공통 setup 검사는 `FakeProcessRunner`, `FixtureRepo`, 합성 ZIP을 사용한다.
승인 전 무변경, 오래된 승인, profile 변경, lease 충돌, 실패·취소·재실행,
source 변경, 이름 충돌과 부분 자원 보존을 검사한다.
실제 Google payload·AVD·GUI·앱 실행 성공의 증거로 사용하지 않는다.

고정 API35 r9 archive의 128KiB suffix HTTP Range 관측에서는 ZIP64 locator가 없었다.
이 관측으로 SafeZIP 제한을 완화하지 않는다.
범위 조회는 전체 checksum이나 설치 성공의 증거가 아니다.
실제 host의 가속 사전 검사와 남은 AC02·AC03·AC06 경계는 [#207 근거](../evidence/207/README.md)에 기록한다.

공식 근거:

- [Android system-image metadata](https://dl.google.com/android/repository/sys-img/google_apis/sys-img2-4.xml)
- [avdmanager 계약](https://developer.android.com/tools/avdmanager)
- [AVD profile 선택과 생성 구현](https://android.googlesource.com/platform/tools/base/+/mirror-goog-studio-master-dev/sdklib/src/main/java/com/android/sdklib/tool/AvdManagerCli.java)
- [Android Emulator 가속 조건](https://developer.android.com/studio/run/emulator-acceleration)

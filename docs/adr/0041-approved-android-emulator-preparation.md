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
설치용 local metadata는 `common:repository`에 common/02 namespace를 명시한다.
system-image 원격 root에 이 namespace가 없어도 유효한 XML을 생성한다.
원격 license ID와 본문 hash는 유지한다. license alias나 새 동의 기록을 만들지 않는다.

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
생성 때와 같은 SDK profile을 읽는다. 사용자 profile override를 생성 identity로 섞지 않는다.
`list device`의 표시문만으로 hardware와 boot properties를 고정하지 않는다.
`profileSHA256`은 선택 표시문과 실제 생성 payload의 digest를 함께 고정한다.
생성 payload는 launcher, `avdmanager-classpath.jar`, Manifest Class-Path의 도달 가능한 JAR이다.
SDK의 `extras/<vendor>/<item>`과 `system-images/<api>/<tag>/<abi>`에서는
`devices.xml`, `source.properties`, `package.xml`만 읽는다.
이 catalog는 내장 profile을 덮어쓸 수 있으므로 선택 metadata도 고정한다.
image payload, 다른 도구와 인증 파일은 이 digest에 넣지 않는다.
Java가 무시하는 누락된 전이 JAR 참조는 부재 상태로 고정한다.
그 파일이 나중에 생기면 새 승인을 요구한다.
Manifest continuation을 처리한다. URI·상위 경로·link·불명확한 root classpath는 차단한다.
JAR은 최대128개다. 전체 파일은 최대512개이며 내용은 합계256MiB 이하이다.
개별 JAR은64MiB, catalog·launcher는2MiB, Manifest 출력은64KiB 이하이다.
계획·승인 재검사·생성 직전·등록 직전에 payload를 다시 확인한다.
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
profile 조회와 생성 child는 절대 경로 `/usr/bin/sandbox-exec`를 거친다.
SBPL `deny file-write*`가 canonical SDK subtree의 쓰기를 하위 JVM까지 차단한다.
SDK와 AVD/임시 경로가 겹치거나 경로의 symlink alias가 모호하면 실행하지 않는다.
SDK 밖의 소유한 Android home과 AVD staging만 전달한다.
staging을 만들기 전에 이 경계를 확인한다.
command의 환경·작업 경로·timeout·출력 방식을 유지한다.
SBPL 문자열의 quote와 backslash를 escape한다. 제어 문자가 있는 경로는 거부한다.
보호 기능을 사용할 수 없으면 수동 단계로 남긴다. 보호 없는 child로 재시도하지 않는다.
이 보호는 SDK 쓰기 차단이다. 모든 host 파일의 쓰기를 격리했다는 주장이 아니다.
생성 결과의 이름·profile·ABI·image 경로와 파일 형식을 확인한다.
공식 새 생성의 `config.ini`에는 `AvdId`가 없을 수 있다.
이 키가 없으면 pointer·이름·나머지 identity로 확인한다.
이 키가 있으면 승인한 이름과 같아야 한다.
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
OS sandbox 검사는 별도 소유 fixture의 SDK·AVD·HOME·임시 경로만 사용한다.
하위 process의 SDK 쓰기 거부와 AVD/임시 파일 쓰기 허용을 직접 확인한다.
실제 SDK catalog 소비와 AVD 생성은 새 검증 tuple에서 따로 확인한다.

고정 API35 r9 archive의 128KiB suffix HTTP Range 관측에서는 ZIP64 locator가 없었다.
이 관측으로 SafeZIP 제한을 완화하지 않는다.
범위 조회는 전체 checksum이나 설치 성공의 증거가 아니다.
실제 host의 가속 사전 검사와 남은 AC02·AC03·AC06 경계는 [#207 근거](../evidence/207/README.md)에 기록한다.

공식 근거:

- [Android system-image metadata](https://dl.google.com/android/repository/sys-img/google_apis/sys-img2-4.xml)
- [avdmanager 계약](https://developer.android.com/tools/avdmanager)
- [AVD profile 선택과 생성 구현](https://android.googlesource.com/platform/tools/base/+/mirror-goog-studio-master-dev/sdklib/src/main/java/com/android/sdklib/tool/AvdManagerCli.java)
- [고정 CLI source의 표시문과 실제 hardware/boot properties](https://android.googlesource.com/platform/tools/base/+/6bbb16186fa0087f54b6857e1e0aa88d115ab537/sdklib/src/main/java/com/android/sdklib/tool/AvdManagerCli.java)
- [고정 DeviceManager의 catalog 우선순위](https://android.googlesource.com/platform/tools/base/+/6bbb16186fa0087f54b6857e1e0aa88d115ab537/sdklib/src/main/java/com/android/sdklib/devices/DeviceManager.java)
- [고정 AvdManager의 새 생성 config](https://android.googlesource.com/platform/tools/base/+/6bbb16186fa0087f54b6857e1e0aa88d115ab537/sdklib/src/main/java/com/android/sdklib/internal/avd/AvdManager.java)
- [Android Emulator 가속 조건](https://developer.android.com/studio/run/emulator-acceleration)

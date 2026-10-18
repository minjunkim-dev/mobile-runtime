# #207 구현과 검증 경계

기준 source: `c73155c856162d31c15d6c300f0ec1dc8b54d5ff`.
구현 브랜치: `codex/207-emulator-preparation`.

## 자동 행동 검사

`AndroidEmulatorPreparationTests`는 공식 schema·package/detail 일치·Emulator dependency를 검사한다.
`AndroidAVDInstallationTests`는 실제 fixture 파일과 fake 생성 명령으로 이름 충돌·실패·취소·보존을 검사한다.
`AndroidEmulatorSetupTests`는 공개 `PreparationExecution.run`으로 승인·재검사·lease·단계별 재승인·source 보존을 검사한다.
같은 interface가 CLI와 GUI에 사용된다. 이 검사로 실제 CLI·GUI 조작 성공을 주장하지 않는다.
기존 Android SDK·InstallationAction·ZIP 설치·공통 준비 검사를 함께 실행한다.

실행 결과와 격리 조건은 `automatic-checks.json`에 기록한다.
새 검사는 lease를 전용 fixture 경로로 직접 주입한다.

초기 관련 검사에는 HOME/CFFIXED_USER_HOME 격리가 없었다.
일부 기존 검사는 `ResourceLeases.user` 기본값을 사용한다.
이 초기 실행의 host cache 파일 접근·변경은 전후 감사하지 않았다.
기존 host lease/cache 파일을 삭제하거나 복구하지 않았다.
전체 HOME/cache 보존은 미검증이다.

이후 검사 전에 전용 HOME/CFFIXED_USER_HOME으로 Foundation home과
`ResourceLeases.user.directory`가 전용 경로를 가리키는지 실제 테스트 프로세스에서 확인했다.
SwiftPM scratch/cache/config/security, module cache, TMPDIR도 전용 경로를 사용한다.
이 격리 확인은 초기 실행의 미확인 상태를 소급 보완하지 않는다.

독립 Spec 수정 검사에서 환경 `TMPDIR`과 실제 Foundation 임시 경로를 따로 확인했다.
환경 `TMPDIR`은 전용 경로였다.
Foundation `FileManager.temporaryDirectory`는 macOS의 `/var/folders/.../T`였다.
기존 `FixtureRepo`와 profile 조회는 이 경로 아래 자기 소유 UUID 디렉터리에 썼다.
이를 전용 `TMPDIR` 아래 쓰기로 표현하지 않는다.
임시 UUID 디렉터리의 소유 cleanup 외에 다른 host 임시 파일·lease/cache를 정리하지 않았다.

## 독립 Spec 수정

공식 새 생성 source 형태로 fake 생성 fixture를 바꿨다.
`config.ini`에 `AvdId`가 없는 정상 생성을 수용한다.
키가 있으면 불일치를 거부한다. pointer·이름·image·ABI·profile 검증은 유지한다.
기존 필수 키 조건에서 생성 검사가 실패한 red 로그를 보존했다.

표시문이 같아도 hardware 또는 boot properties payload가 바뀌면 기존 승인을 거부한다.
생성 중 payload 변경은 등록 전에 실패한다.
정확한 launcher·Manifest classpath closure·SDK catalog metadata를 `profileSHA256`에 묶었다.
Manifest continuation·전이 참조·부재 참조·경로와 link·파일 수와 bytes 한도를 검사한다.
image payload와 관련 없는 tool bytes는 이 fingerprint에 넣지 않는 회귀도 검사한다.

분리된 cmdline-tools21의 JAR을 read-only로 조사했다.
Manifest closure에는 존재하는 JAR75개와 누락된 전이 참조6개가 있었다.
존재하는 JAR의 합계는35,810,425 bytes였다.
이 조사는 SDK 파일 읽기다. SDK 도구나 생성 명령의 실행 증거가 아니다.

## missing adb 수정

호환 AVD가 둘 이상이고 `android.avd` 선언이 없는 회귀를 확인했다.
Platform-Tools가 없으면 `adb devices` 실행 오류 때문에 설치 계획을 반환하지 못했다.
공개 `PreparationExecution.run` red 검사는 plan 부재·설치 단계 부재·조기 adb 호출을 재현했다.
red 로그 SHA-256은 `395ba09a68650eaff1a954f043b018c878eb429393807f217a88bf623c7bbdbc`다.

Platform-Tools의 기존 package 관측이 준비 상태일 때만 실행 중 AVD를 조회한다.
복수 후보의 실행 상태를 조회하기 전에 runtime tools 준비 계획을 먼저 반환한다.
설치나 수동 조치 뒤 다시 계획을 생성한다.
없는 package의 설치 계획과 불완전한 기존 package 보존을 검사했다.
도구가 준비되면 복수 후보의 선택 요구와 호환 실행 중 AVD 우선순위를 유지한다.
합성 SDK·AVD fixture 검사다. 실제 SDK 설치나 AVD 실행 증거가 아니다.

## 실제 catalog 결함과 쓰기 예방

기존 source `82202ccc`의 실제 image 설치 stage는 성공했다.
새 AVD 계획이 남아 operation은 `partial`, exit는1이었다.
이를 다운로드 실패로 계산하지 않는다.
이 stage는 승인한 archive의 size·SHA-1 검사를 통과한 설치 경로다.
원본 ZIP staging은 installer가 정리했다. 별도 독립 rehash는 수행하지 않았다.
로컬 `Pkg.Revision=9`와 `system.img`의3,891,265,536 bytes는 별도 내용 관측이다.
이 로컬 파일의 독립 checksum은 측정하지 않았다.
후속 profile 조회 전후에 catalog payload digest가 달라졌다.
그 뒤 image `package.xml`은 `license-241123C`와 빈 license 본문을 가리켰다.
실제 rewrite 전 bytes와 전체 SDK 변경 범위는 캡처하지 못했다.
tainted image와 metadata를 원복하거나 삭제하지 않았다.
새 license 동의나 alias 기록을 만들지 않았다. AVD는0개였다.
private receipt는 `state/cli-image-license-defect-v1.json`이다.
그 SHA-256은 `093d59bdc524577b16d7b98eda83398835790df5f0bcc1cc57c43e09b622e6e0`다.

local metadata 생성 코드가 미정의 `common` prefix를 사용하는 경로를 확인했다.
namespace-aware XML parser는 수정 전 오류201로 실패했다.
common/02 namespace를 명시한 뒤 같은 검사가 통과했다.
원래 license ID·본문 hash를 유지한다.

두 `avdmanager` 호출에 selected SDK 쓰기 차단을 적용했다.
실제 OS sandbox 검사는 전용 소유 fixture의 SDK·AVD·HOME·임시 경로만 사용했다.
하위 process의 SDK 파일 쓰기를 거부했다. 기존 bytes는 유지됐다.
소유한 AVD·임시 파일 쓰기는 성공했다.
quote·backslash 경로, command 필드 보존, timeout·실행 중 취소도 검사했다.
fake runner 검사로 profile 조회와 AVD 생성 양쪽의 보호 연결을 확인했다.
SDK/AVD 겹침은 host staging 파일을 만들기 전에 거부했다.
이 OS 검사는 실제 Android SDK 설치·AVD 생성의 대체 증거가 아니다.
수정 뒤 새 SDK tuple의 실제 재검증은 아직 수행하지 않았다.

## 제한적 공식 archive 관측

[archive-range.json](archive-range.json)은 공식 r9 image의 suffix 최대128KiB 관측이다.
서버의 HTTP206과 Content-Range를 확인했다.
ZIP64 locator가 없었고 central directory의 29 entries를 범위 안에서 읽었다.
이 결과는 SafeZIP 형식 선택을 위한 입력이다.
전체 archive checksum·압축 해제·설치 성공은 미검증이다.

## 실제 host 가속 사전 검사

root 작업자가 분리 복제한 Emulator `37.1.11`로 `-accel-check`를 한 번 실행했다.
host는 macOS `27.0.1`, `arm64`다.
종료 코드는 0이다. 출력은 다음과 같다.

```text
accel:
0
Hypervisor.Framework OS X Version 27.0
accel
```

private receipt는 검증 root의 `state/accel-check-v1.json`에 있다.
공개 기록은 [acceleration-preflight.json](acceleration-preflight.json)에 둔다.
이 결과는 Emulator가 보고한 가속 필요조건의 availability다.
AVD boot·실제 앱·VM 성공을 뜻하지 않는다.
[공식 검사 방법](https://developer.android.com/studio/run/emulator-acceleration)을 사용했다.

## 수용 기준

| 기준 | 현재 근거 | 남은 실제 검증 |
| --- | --- | --- |
| AC02 | exact archive 계획, 기존 AVD 우선, API35 비강제, image 설치 뒤 별도 생성 승인 행동 검사 | 실제 Google image 설치와 CLI·GUI 생성·재사용 |
| AC03 | 오래된 승인, profile 변경, SDK/AVD/device lease, source 변경, 실패·취소·재실행·부분 자원 보존 행동 검사 | 실제 다운로드·생성 실패/취소와 CLI·GUI 전후 보존 감사 |
| AC06 | 실제 Mac의 `-accel-check` reported availability | 같은 전용 tuple의 실제 Emulator boot와 준비 결과. VM 결과와 분리 |

Developer ID·공증·배포·전체 #199 완료는 이 기록의 범위 밖이다.
실제 SDK 설치·AVD 생성·boot·GUI 결과는 아직 미검증이다.
공용 SDK에 대한 이 구현 작업자의 writer 실행은 없다.

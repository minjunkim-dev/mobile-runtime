# ADR-0029: RN observer의 executable 조회 실패 errno를 비식별 관측한다

## 상태

채택. 사용자는 2026-10-11에 아래 최소 관측 범위와 새 실행 조건을 확정했다. 이 결정은 [ADR-0028](0028-rn-bundler-norc-argument-order.md)의 고정 stage·errorCode 진단 범위를 확장한다. 정책 main 반영과 새 helper 독립 검토 및 새 단독 lease 전에는 실제 실행 권한이 없다.

## 확인한 실패와 미확정 원인

attempt-15의 최소 RN 원본 Bundle install은 exit `0`이었다. 해당 consumer는 실제 관측 551개와 executable 조회 오류 한 개를 기록했다. stage는 `executable-launcher-image-zero`다. errorCode는 `EXECUTABLE_RETURN_ZERO`다. observer guard는 false였고 outer helper는 exit `1`로 중단했다. 전체 실제 관측 집계는 582개다. 성공한 관측은 오류 한 개를 상쇄하지 않는다.

현재 monitor는 시작 identity를 확보한 뒤 `proc.poll() is None`인 loop에서 launcher executable을 조회한다. poll과 조회는 원자적으로 실행되지 않는다. 해당 조회가 실패하면 같은 loop의 후속 identity 검사에 도달하지 않는다. 이 진단은 `proc_pidpath` 반환값이 0이었다는 사실만 구분한다. process 종료, exec 전환, PID 재사용이나 권한 문제를 실제 원인으로 확정하지 않는다.

필수 STOP 뒤 후속 준비와 native 및 기기 검증은 시작하지 않았다. lease는 RELEASED다. 최초 result와 오류 및 사후 감사와 cleanup을 보존한다. 새 정책이나 후속 결과로 attempt-15를 사후 PASS로 바꾸지 않는다.

## 확인한 공식 source와 적용 한계

[Python 3.14.8 ctypes 문서](https://docs.python.org/3.14/library/ctypes.html#ctypes.get_errno)는 thread별 private errno copy의 읽기를 설명한다. [set_errno](https://docs.python.org/3.14/library/ctypes.html#ctypes.set_errno)는 이 copy를 설정한다. [CDLL의 use_errno](https://docs.python.org/3.14/library/ctypes.html#ctypes.CDLL)는 외부 함수 호출 전후에 실제 errno와 private copy를 교환하는 기존 동작을 설명한다.

현재 observer의 libproc용 `CDLL`에는 이미 `use_errno=True`가 있다. 기존 `lib.proc_pidpath` 함수 객체와 prototype 및 errno 설정을 그대로 유지한다. 새 wrapper를 만들거나 FFI 설정을 바꿀 필요가 없다. 다른 libproc 함수와 기존 libSystem 함수의 wrapper·errno 설정·호출도 변경하지 않는다. 다른 함수의 errno를 새로 읽거나 초기화하지 않는다. 이 문서 확인은 설치 Python 또는 libproc binary의 전체 source 동일성 증거가 아니다.

[Apple의 고정 XNU libproc.c source](https://github.com/apple-oss-distributions/xnu/blob/94d3b452840153a99b38a3a9659680b2a006908e/libsyscall/wrappers/libproc/libproc.c#L264)의 `proc_pidpath`는 작은 버퍼에서 ENOMEM을 설정하고 0을 반환한다. 큰 버퍼에서는 EOVERFLOW를 설정하고 0을 반환한다. 내부 조회가 -1이면 0을 반환한다. 내부 조회가 -1이 아니어도 경로 길이가 0이면 반환값은 0이다. 반환값 0은 한 원인을 고유하게 식별하지 않는다.

이 고정 공개 source와 설치된 macOS 27의 libproc binary가 같은지는 미확인이다. errno enum은 이번 호출이 제공한 추가 진단이다. enum 이름만으로 process 종료나 권한 문제의 정확한 원인과 발생 시점을 확정하지 않는다. ESRCH 등 아래 enum이 모든 설치 환경에서 같은 분기에 발생한다고 보장하지 않는다.

## 확정한 최소 관측 범위

대상은 최소 RN 고정 source `b62e3a4d5e7cfc05d7d948a5a4e30f0cc6a82bb4`와 Mattermost 고정 source `c2fe3beda22befd2178dce431793c09111ed903e`의 두 새 baseline과 각 독립 fresh다. 원본 Ruby·RubyGems·Bundler·Pods 버전과 원본 plugin 및 도구 선택을 유지한다. 최소만 독립 Bundler bootstrap을 수행하는 기존 범위를 유지한다.

기존 executable 조회 네 지점에만 적용한다.

- `consumer-image-before`
- `consumer-image-after`
- `launcher-image`
- `descendant-image`

각 지점의 기존 `proc_pidpath` 함수 객체·prototype·errno 설정과 인자·횟수·순서 및 표준 C ABI를 유지한다. 반환형 `c_int`와 인자형 `c_int, c_void_p, c_uint32`를 유지한다. 원본 4096-byte 버퍼를 유지한다. 조회 symbol과 library를 바꾸지 않는다. 다른 함수의 errno 동작을 확대하지 않는다.

호출과 진단 순서는 다음으로 제한한다.

1. 기존 준비와 버퍼 생성 및 함수의 prototype 설정을 유지한다. 기존 조회 직전에 같은 observer thread의 `ctypes.set_errno(0)`으로 private copy를 초기화한다. 반환한 이전 errno 값은 저장하지 않는다.
2. 원래 지점에서 원래 인자로 `proc_pidpath`를 한 번 호출한다.
3. 반환값이 `<=0`이면 다른 C 호출 전에 `ctypes.get_errno()`로 그 호출 뒤의 private copy를 한 번 읽는다. 분류 전까지 다른 errno 사용 함수나 process 조회를 끼우지 않는다. 읽은 정수는 분류용 로컬 값으로만 사용한다.
4. 기존 고정 call-site stage와 ZERO·NEGATIVE errorCode를 유지한다. 추가 errno 진단은 아래 고정 enum 하나로만 기록한다. raw errno 정수·PID·path·argv·환경·예외 원문을 저장하지 않는다.
5. 기존 오류를 다시 발생시킨다. errno가 0이거나 알려진 enum이거나 OTHER_ERRNO여도 기존 필수 STOP을 유지한다. errno 초기화·읽기·분류가 불명하면 기존 unknown 실패로 중단한다.

| 읽은 private errno | 기록할 enum |
| --- | --- |
| 0 | `ERRNO_UNSET` |
| `errno.ESRCH` | `ESRCH` |
| `errno.EACCES` | `EACCES` |
| `errno.EPERM` | `EPERM` |
| `errno.ENOMEM` | `ENOMEM` |
| `errno.EOVERFLOW` | `EOVERFLOW` |
| `errno.EINVAL` | `EINVAL` |
| 그 밖의 정수 | `OTHER_ERRNO` |

`ERRNO_UNSET`은 초기화 뒤에도 errno copy가 0인 사실만 뜻한다. 성공이나 무해한 race로 분류하지 않는다. 알려진 상수의 제공 또는 분류가 불명하면 값을 추측하지 않는다. `OTHER_ERRNO`에는 raw 정수나 이름을 덧붙이지 않는다.

반환값이 `>0`이면 errno를 오류 판정에 사용하지 않는다. 정상 경로의 기존 return과 후속 검사를 유지한다. 새 진단으로 정상 호출에 새로운 실패 판정을 만들거나 실패 호출을 성공으로 바꾸지 않는다.

## 유지하는 조건과 금지하는 확대

원본 source·lock·의존성 graph와 선언 버전을 유지한다. 원본 plugin과 clone별 준비 환경 및 공유 경로 감사 범위를 유지한다. 최소의 원본 source 55개와 세 lock을 유지한다. Mattermost의 허용한 Hermes 한 값과 generated mixed Debug 12값 및 원본 앱·Release 값 보존 조건을 유지한다. 원본 명령·argv·환경·recipe·observer identity 검사와 필수 판정을 유지한다.

새 process 조회 자체는 추가하지 않는다. 기존 FFI errno 보존 설정을 유지한다. private copy 초기화·읽기와 고정 enum 기록은 새로운 관측 조건이다. ADR-0028의 관측 불변 범위에 자동 포함하지 않는다. 사용자는 이 추가 관측 범위를 별도로 확정했다.

오류 무시, race 재분류, retry, 추가 생존·identity syscall과 관측 query 변경을 허용하지 않는다. sleep·delay·sampling·poll 순서·통과 조건을 바꾸지 않는다. 과거 성공 관측이나 exit 0으로 오류를 상쇄하지 않는다. 실제 errno에 따라 명령이나 환경을 자동 변경하지 않는다.

private copy 초기화·읽기와 고정 enum 기록에는 실행 작업이 추가된다. 시간 overhead가 0이라고 주장하지 않는다. scheduling과 관측 시점에 미치는 실제 영향은 미측정이다. 이 관측은 root cause fix도 baseline 통과 보장도 아니다.

## 새 실행과 검토 조건

1. 확정한 정책을 main에 반영한다. 기존 accepted 정책과 CONTEXT의 연결을 정정한다. 최초 attempt-15와 과거 실패 packet의 bytes를 보존한다.
2. 새 helper·PLAN과 정책 hash 및 source/output root를 고정한다. 네 call-site의 동일 인자·횟수·순서·ABI·버퍼를 독립 검토한다. memory에서 enum 분류와 private copy 초기화·읽기 순서, privacy-negative 및 기존 unknown STOP을 검증한다. 범위 밖 query·sampling·delay·guard 변경을 거부한다.
3. root의 최신 preflight와 새 단독 lease 뒤 두 새 baseline을 독립 준비한다. 이전 clone·private state·node_modules·vendor/bundle·Pods·build와 이전 lease를 승계하지 않는다. 기존 검증된 공식 raw archive 재사용 조건만 유지한다.
4. 원본 source·early Metro·metadata·host·shared 감사와 최소 Bundler 설치·activation·frozen 및 두 표본의 원본 Pods 준비 조건을 유지한다. 두 표본의 iOS·Android build·install·launch·첫 화면 네 개를 직렬 검증한다. 네 baseline 첫 화면을 확인한 뒤 각 독립 fresh를 준비한다.
5. 필수 소비자 실패, 관측 unknown, errno 조회 실패나 허용 밖 변경이면 모든 후속 실제 실행을 중단한다. 소유 자원만 정리한다. 최초 receipt와 실패 및 사후 감사를 보존한다. 같은 attempt에서 진단이나 조건을 수정해 재개하지 않는다. 다른 조건에는 별도 결정과 새 실행이 필요하다.

실제 helper 구현과 실행은 이 정책의 채택 자체로 수행하지 않는다. 문서·memory·CI 통과는 실제 설치·frozen·native·첫 화면·fresh 성공 증거가 아니다. 실제 Runstir CLI·GUI 재현과 Mattermost 보정 유지 검증은 후속 gate다. #212와 PR #236은 열린 상태를 유지한다.

## 확정한 답

사용자는 위의 기존 executable 조회를 유지한 private errno copy 초기화·실패 직후 읽기·고정 enum 진단 범위와 새 실행 조건을 확정했다. 필수 관측과 실패 STOP을 완화하지 않는다.


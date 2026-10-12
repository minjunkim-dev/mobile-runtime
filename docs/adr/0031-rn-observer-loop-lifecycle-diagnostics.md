# ADR-0031: RN observer 오류에 기존 loop의 lifecycle 진단을 연결한다

## 상태

채택. 사용자는 2026-10-11에 아래 세 진단 field와 새 실행 조건을 확정했다. 정책 main 반영과 새 helper 독립 검토 및 새 단독 lease 전에는 실제 실행 권한이 없다. 이 결정은 [ADR-0028](0028-rn-bundler-norc-argument-order.md)과 [ADR-0029](0029-rn-observer-executable-errno.md)의 비식별 진단 범위를 추가로 결정한다. 기존 오류 STOP과 [ADR-0030](0030-rn-pod-runtime-cwd-boundary.md)의 준비 입력 조건은 유지한다. 정책 main 반영 및 새 helper 독립 검토와 새 단독 lease 전에는 실제 실행을 재개하지 않는다.

## 배경과 미확정 원인

attempt-19 실행 소유자의 현재 보고에서 최소 RN의 원본 Bundle install은 exit `0`이다. 해당 consumer는 조건에 맞는 관측 530개와 오류 한 개를 기록했다. 오류의 stage는 `executable-launcher-image-zero`다. errorCode는 `EXECUTABLE_RETURN_ZERO`다. private errno enum은 `ESRCH`다. observer는 false였고 필수 STOP을 유지했다. 성공 관측과 원본 exit `0`은 오류를 상쇄하지 않는다.

해당 오류에는 loop ordinal과 오류 시점의 관측 누적 개수가 없다. 다음 기존 loop-head poll 결과와의 연결도 없다. 오류 발생 시각도 없다. 이 사실만으로 정상 종료 직후의 race나 실행 중 상태 변화를 확정할 수 없다. attempt-19의 최종 raw packet은 봉인했다. 독립 검토 두 개를 완료했다. SHA256SUMS의 nonempty entry는 192개다. raw recursive 파일은 193개다. 빈 줄 한 개는 entry로 세지 않는다. 원본 REPORT.md SHA256은 `1006ae795ee9fcedfd673beef1979fd5c054f9c59af861ee285722a70baca4d0`이다. 원본 manifest.json SHA256은 `7fc867699cb7a03b0a76b47864ce719efaf165eeeaf6e158418b4666c78bd733`이다. 원본 SHA256SUMS SHA256은 `db4485efb5f49b3900bf6d2ebf8c3d3ab73f8386867120b58ebf7ed8448b8e33`이다. 공개 checkpoint exact head는 `211081e70ada56e703f6d3dead2cc2a4a61c9f48`이다. root는 이 head의 [CI run38143563456](https://github.com/minjunkim-dev/mobile-runtime/actions/runs/38143563456) 네 job의 terminal SUCCESS를 확인했다. 공개 판정과 실패 경계는 [#212 checkpoint](https://github.com/minjunkim-dev/mobile-runtime/issues/212#issuecomment-6109599119)에 기록했다. 이 결정은 원본 packet의 bytes와 필수 STOP을 바꾸지 않는다. 후속 준비와 native 및 첫 화면 성공을 주장하지 않는다.

현재 observer의 `monitor`는 기존 `proc.poll() is None` loop-head 뒤 launcher executable을 조회한다. 두 호출은 원자적이지 않다. executable 조회와 기존 관측이 실패하면 기존 catch가 오류를 목록에 추가한다. 기존 sleep 뒤 다음 loop-head poll로 이동한다. 오류가 있어도 이 기존 loop의 관측 흐름은 명령 종료까지 이어질 수 있다. 명령 종료 뒤의 필수 판정은 오류 목록이 비어 있어야 한다. 후속 consumer는 이 판정을 통과해야 한다. 새 진단은 이 흐름과 판정을 바꾸지 않는다.

## 확인한 primary source와 한계

[Apple pinned libproc.c:264–282](https://github.com/apple-oss-distributions/xnu/blob/94d3b452840153a99b38a3a9659680b2a006908e/libsyscall/wrappers/libproc/libproc.c#L264-L282)는 `proc_pidpath`의 반환 경계를 보여 준다. 이 raw source의 SHA256은 `a88b32765494884425d2a628d4696ff0985e31315720dc2af444f164c9a89b00`이다. 내부 query 실패는 반환값 `0`으로 나타날 수 있다. 반환값 `0` 자체는 한 원인을 고유하게 식별하지 않는다.

같은 commit의 [proc_info.c:2122–2136](https://github.com/apple-oss-distributions/xnu/blob/94d3b452840153a99b38a3a9659680b2a006908e/bsd/kern/proc_info.c#L2122-L2136)는 PID 조회 실패의 `ESRCH` 분기를 보여 준다. PIDPATHINFO는 해당 zombie lookup 허용 flavor에 포함되지 않는다. [proc_pidpathinfo:1343–1442](https://github.com/apple-oss-distributions/xnu/blob/94d3b452840153a99b38a3a9659680b2a006908e/bsd/kern/proc_info.c#L1343-L1442)에도 text vnode 부재와 vnode 조회·참조 실패 등의 `ESRCH` 분기가 있다. 이 raw source의 SHA256은 `f700edb2972d3f356e8e3af85aae8a9ec0030082b5518f92ba8e2075d760b696`이다. 따라서 `ESRCH`만으로 process 종료나 권한 문제를 확정하지 않는다.

설치 SDK `MacOSX27.0.sdk/usr/include/libproc.h:102`의 선언은 `int proc_pidpath(int pid, void *buffer, uint32_t buffersize)`다. 이 header의 SHA256은 `246d87709fc6b9157ce5cf3c475656ac48e0e1ae8bbdc46cf45acd34294448cd`이다. 기존 observer의 `c_int, c_void_p, c_uint32`와 반환형 `c_int`는 이 선언과 대응한다. `sys/proc_info.h:748–749`와 `sys/syslimits.h:103`의 크기 경계에 기존 4096-byte 버퍼가 들어간다. 정적 선언상 ABI나 버퍼 크기 불일치 근거는 찾지 못했다. 실제 binary 전체 대응을 입증하지 않는다.

[Python 3.14.8 ctypes 문서](https://docs.python.org/3.14/library/ctypes.html#ctypes.get_errno)는 `use_errno=True`의 thread별 private copy 교환을 설명한다. 기존 `set_errno(0)` → 동일 `proc_pidpath` → 실패 직후 `get_errno()` 순서는 이 계약과 대응한다. 이 결정은 errno 설정·초기화·읽기·분류를 바꾸지 않는다.

설치 libproc와 XNU binary가 위 공개 commit과 byte 단위로 대응하는지는 미확정이다. 설치 Python binary의 전체 source 대응도 미확정이다. 정적 source 대응을 실제 오류 원인의 증거로 사용하지 않는다. 정상 종료 race, 실행 중 상태 변화, ABI·errno 해석 문제의 실제 원인은 현재 미확정이다. 새 진단도 원인 확정이나 성공 보장이 아니다.

## 결정한 최소 진단 범위

대상은 최소 RN source `b62e3a4d5e7cfc05d7d948a5a4e30f0cc6a82bb4`와 Mattermost source `c2fe3beda22befd2178dce431793c09111ed903e`의 두 새 baseline과 각 독립 fresh다. 표본별 원본 Ruby·Bundler·CocoaPods 버전과 plugin 및 준비 환경을 유지한다. 최소만 독립 Bundler bootstrap을 수행하는 기존 범위도 유지한다.

기존 `monitor` loop의 catch가 만든 오류 record에 아래 세 field만 추가한다. 기존 stage·errorCode·errno enum·오류 목록과 원래 predicate를 그대로 보존한다.

| field | 기록할 값 | 의미 |
| --- | --- | --- |
| `monitorLoopOrdinal` | 1부터 시작하는 loop 본문 순서 정수 | 오류를 기록한 기존 loop 본문의 순서다. PID나 시각이 아니다. |
| `completedObservationCountAtError` | 그 catch 시점의 기존 `len(observed)` 정수 | 그 시점까지 기존 목록에 append한 완전한 관측 개수다. matching 개수나 성공 판정이 아니다. |
| `nextExistingLoopHeadPollOutcome` | `NOT_RECORDED`, `RUNNING`, `TERMINAL` | 같은 monitor의 바로 다음 기존 loop-head poll과의 연결이다. |

loop 밖 오류에는 ordinal과 누적 개수를 `null`로 기록한다. poll outcome에는 `NOT_APPLICABLE`을 기록한다. 이 구분은 launcher-start와 loop 종료 뒤 metadata 오류 등 기존 loop catch 밖의 오류에만 적용한다. 미기록 상태를 loop 밖 오류로 바꾸지 않는다.

기존 호출과 연결 순서는 다음으로 제한한다.

1. 원래 loop-head의 `proc.poll()`을 원래 지점에서 한 번 호출한다. 그 반환값을 local에 보관한다. 같은 값으로 원래 `is None` 조건을 판정한다. 새 poll을 호출하지 않는다.
2. loop 본문에 진입하면 본문 순서 local을 1 증가시킨다. 이전 loop catch의 연결 대기 오류가 있으면 이 기존 poll의 `None` 결과를 `RUNNING`으로 연결한다. 원래 executable query와 나머지 본문을 같은 순서로 실행한다.
3. 기존 catch에서 오류 record를 만들 때 현재 ordinal과 기존 관측 목록 길이를 기록한다. outcome은 `NOT_RECORDED`로 시작한다. 기존 오류 목록에 추가한 동일 record를 다음 기존 loop-head 결과의 연결 대상으로 보관한다.
4. 다음 기존 loop-head poll이 `None`이 아니면 원래 loop는 종료한다. 원래 `proc.wait()` 전에 이미 저장한 같은 poll 반환값으로 대기 record에 `TERMINAL`을 연결한다. 종료 상태를 새 query나 clock으로 읽지 않는다.
5. 연결하지 못한 오류는 `NOT_RECORDED`를 유지한다. 불명확한 field·연결·순서가 있으면 기존 unknown STOP을 유지한다. 진단 기록 실패로 원래 오류를 지우거나 완전한 진단을 추측하지 않는다.

기존 관측 목록의 순서와 각 관측의 원래 matching 판정은 그대로다. 오류 시점의 개수와 최종 목록을 비교하면 그 오류 뒤에 완전한 관측을 더 append했는지 구분할 수 있다. 어떤 관측이 matching인지는 기존 predicate로만 판정한다. count가 같다는 이유로 guard를 통과시키지 않는다.

`RUNNING`은 다음 기존 poll이 `None`을 반환했다는 뜻이다. 오류 당시 생존·start identity·실효 executable을 입증하지 않는다. `TERMINAL`은 다음 기존 poll이 종료 상태를 반환했다는 뜻이다. 오류 당시 이미 종료했거나 정상 종료 race가 원인이었다는 뜻은 아니다. 두 enum 모두 오류 시각과 인과관계를 입증하지 않는다.

## edge case와 기록 경계

- 연속 오류는 각 원래 record의 ordinal과 관측 개수 및 바로 다음 poll outcome을 독립 연결한다. 이전 오류를 덮어쓰거나 마지막 오류 하나로 합치지 않는다.
- 첫 loop 이전 launcher-start 오류는 loop 밖 record다. 다음 poll을 억지로 연결하지 않는다.
- loop 종료 뒤 metadata 오류도 loop 밖 record다. 그 전에 얻은 terminal 결과를 해당 오류의 다음 poll로 사용하지 않는다.
- 원래 early continue와 sleep을 유지한다. 새로운 finally나 분기로 추가 poll 또는 추가 wait를 호출하지 않는다.
- 다음 기존 poll이 예외를 발생시키거나 monitor가 중단되면 outcome을 추측하지 않는다. 연결 대기 record는 `NOT_RECORDED`다. 기존 예외·오류와 unknown 실패를 보존한다. 실제 poll 예외의 기존 throw와 처리 동작을 유지한다. `NOT_RECORDED`를 보존하거나 진단하려고 새 catch·finally·poll·wait를 추가하지 않는다. 기존 제어 흐름을 바꾸지 않는다.
- 같은 오류에 여러 outcome을 연결하거나 다른 monitor·consumer의 poll을 연결하면 unknown이다. 실제 PID·object identity·path를 새 진단 field로 저장하지 않는다.
- 다음 poll에 도달하지 않은 오류를 `RUNNING`이나 `TERMINAL`로 보정하지 않는다. `NOT_RECORDED`와 `NOT_APPLICABLE`은 원래 오류를 무해하게 분류하는 값이 아니다.
- 새 field는 clock·timestamp·raw PID·path·argv·환경·예외 원문을 추가 저장하지 않는다. 원래 오류 record와 원본 비공개 receipt를 보존한다. 공개 표현은 비식별 요약과 원본 hash pointer를 구분한다.

## 유지하는 조건

기존 poll과 모든 executable·identity·환경·ancestry·cwd query의 인자·횟수·순서를 유지한다. sampling·sleep·delay·원래 loop의 control flow 의미를 유지한다. FFI·ABI·4096-byte 버퍼와 ADR-0029 errno 설정·읽기·enum을 유지한다. 원본 명령·argv·환경·cwd와 recipe 순서 및 모든 guard를 유지한다. 새로운 process 생존 query나 clock, syscall, retry, stress를 추가하지 않는다. 이 세 field의 기록·연결 외 instrumentation을 추가하지 않는다.

이 기록과 연결은 새 관측 진단 조건이다. ADR-0028의 고정 stage·errorCode와 ADR-0029의 errno 진단에 자동 포함한다고 해석하지 않는다. 사용자는 이 추가 진단 범위를 확정했다. 기록에 드는 overhead가 0이라고 주장하지 않는다. scheduling과 관측 시점의 실제 영향은 미측정이다. 기존 호출 지점과 순서를 유지한다는 계약은 실제 소요 시간을 같게 만든다는 보장이 아니다.

모든 원래 오류는 계속 필수 STOP이다. `ESRCH`와 모든 errno enum에 통과 예외를 만들지 않는다. 원본 exit `0`과 matching 관측 및 다음 poll의 결과로 오류를 상쇄하지 않는다. baseline/fresh 판정과 후속 실행 조건을 완화하지 않는다.

원본 source·lock·graph·선언 버전과 plugin 및 공유 경로 감사를 유지한다. 최소의 source 55개와 세 lock을 보존한다. Mattermost의 허용된 Hermes 한 값과 generated mixed Debug 12값 및 원본 app·Release 보존 조건을 유지한다. ADR-0030의 exact 여섯 Pod recipe와 own launcher cwd 및 제한된 cache metadata 조건을 유지한다. 다른 consumer와 descendant의 원래 판정도 유지한다.

[ADR-0032](0032-rn-mise-official-asset-identity.md)은 기존 canonical mise 파일의 identity 한 개와 새 source-only 준비만 별도로 결정한다. 세 진단 field와 모든 필수 STOP은 유지한다. ADR-0032의 범위 확정은 실제 실행을 재개하는 권한이 아니다. 원래 resource 조건과 최신 preflight 및 새 단독 lease를 유지한다.

## 새 실행과 검토 조건

1. 확정한 진단 범위와 새 실행 조건을 정책 main에 반영한다. 최초 attempt-19와 이전 packet의 bytes 및 필수 STOP을 보존한다. 같은 attempt에서 새 field나 helper를 넣어 재개하지 않는다.
2. 새 helper·PLAN·정책 hash와 새 source/output root를 고정한다. source와 AST로 기존 poll·query·인자·횟수·순서·sampling·sleep·delay·FFI·errno·guard 불변을 독립 검토한다.
3. memory에서 마지막 관측 뒤 오류, 오류 뒤 기존 poll running, 오류 뒤 기존 poll terminal, 연속 오류, loop 밖 오류, early continue, metadata 오류, mock poll 예외 및 연결 미기록을 검증한다. 실제 entrypoint와 persistent write를 거부한다. privacy-negative와 원래 오류 목록·predicate 및 unknown STOP을 확인한다.
4. root의 최신 preflight와 새 단독 lease 뒤 두 새 baseline을 독립 준비한다. 이전 lease·clone·private state·node_modules·vendor/bundle·Pods·build를 승계하지 않는다. 기존에 검증한 공식 raw archive의 캐시 재사용 조건만 유지한다.
5. 원본 source·early Metro·metadata·host·shared 감사와 최소 Bundler 설치·activation·frozen 및 두 표본의 원본 Pods 준비 조건을 유지한다. 두 표본의 iOS·Android build·install·launch·첫 화면 네 개를 직렬 검증한다. 네 baseline 첫 화면 뒤 각 독립 fresh의 준비와 frozen 검사를 수행한다.
6. 필수 consumer 실패·관측 오류·연결 unknown·허용 밖 변경이면 모든 후속 실제 실행을 중단한다. 소유 자원만 정리한다. 최초 receipt와 오류 및 사후 감사를 보존한다. 다른 입력 조건에는 별도 결정과 새 실행이 필요하다.

사용자 확정은 실제 실행 성공이 아니다. 정책 채택 자체로 helper 구현이나 실제 build를 수행하지 않는다. 정책 main 반영 뒤 새 helper를 구현하고 독립 검토한다. 실제 실행은 새 단독 lease 뒤에만 수행한다. 문서·memory·CI 성공은 실제 frozen·native·첫 화면·fresh 성공 증거가 아니다. 실제 Runstir CLI·GUI 재현과 Mattermost 보정 유지 검증은 후속 gate다. #212와 PR #236은 열린 상태를 유지한다.

## 확정한 답

사용자는 위의 세 비식별 field와 바로 다음 기존 loop-head poll의 연결 및 새 실행 조건을 확정했다. 실제 오류 원인을 확정하거나 오류를 통과시키지 않는다. 기존 query와 errno 및 모든 필수 STOP을 유지한다.

# ADR-0033: RN baseline의 GUI 상태와 ADB server 준비 경계를 고정한다

## 상태

채택 — SOURCE-ONLY 범위. 사용자는 2026-10-12에 최종 초안의 source-only 범위를 확정했다. 이 결정은 [ADR-0032](0032-rn-mise-official-asset-identity.md)의 source-only 경계 뒤에 필요한 GUI·ADB 계약을 문서와 memory 모델로 준비한다. 실제 GUI·ADB state 적용·startup·snapshot·hostwrite·실제 재개와 원본 resource predicate 변경은 채택 범위 밖이다. 실제 실행 권한은 없다. 기존 파일 metadata만 읽었다. 현재 port·원본 runtime host key·GUI 상태를 fresh preflight로 다시 조회하지 않았다.

foreground ADB server는 제한된 준비 후보다. 아래 syntax의 공식 source 근거는 확인했다. 설치한 SDK binary의 전체 대응과 shared write·transport·client race 차단은 미확정이다. 따라서 이 결정을 즉시 실행 가능한 준비 계획이나 approval-ready actual 제안으로 사용하지 않는다. 미해결 frontier를 먼저 검토한다.

사용자는 2026-10-13에 Q4의 full source/build 증거 기준과 Q5의 미입증 시 중단 경로를 확정했다. 같은 날 이 정책 문서와 기존 조사 문서의 저장을 허용했다. 이 추가 범위는 실제 resource 조건 채택·준비·실행 권한을 포함하지 않는다.

## 배경과 원래 판정

E20의 저장된 reconnection resource receipt는 historical GUI 부재와 기존 ADB server 미입증을 기록했다. 전체 resource 판정은 false다. GUI의 종료 주체·시점·원인은 미확정이다. ADB listener 부재 원인도 미확정이다. `adb devices`의 실제 receipt가 없으므로 파생 `adbDevicesEmpty=false`는 기기 존재 증거가 아니다.

E20과 E21의 `resource_preflight.py`에서 `main`·`resources_known`·`adb_server_known`·`observe_owned_emulator`·`guarded_owned_operation`의 AST는 같다. `main:206–209`는 historical `lease.preserve.guiPid`를 찾아 `len(gui)==1`을 필수로 요구한다. 현재 존재하는 GUI만 선택적으로 보존하는 조건이 아니다. 새 GUI를 띄워도 historical process identity를 복원하지 않는다.

`adb_server_known:153–162`는 5037 LISTEN 결과의 adb 이름과 한 PID를 확인한다. canonical executable·start identity·client protocol compatibility는 확인하지 않는다. `resources_known:164–168`은 기존 server와 성공한 empty device 결과를 필수로 요구한다. `main:185–188`은 server 미입증이면 adb 호출 전에 STOP한다. 이것은 읽기 관측인 `adb devices`도 server를 자동 시작할 수 있기 때문이다. Android own-state guard도 같은 existing-server 조건을 소비한다.

snapshot anchor만 새 현재값으로 바꾸고 원래 predicate를 유지하면 두 부재 상태를 허용하지 못한다. GUI 부재와 ADB 초기 부재를 허용하려면 별도 predicate 결정이 필요하다. Android 완료에는 그 뒤의 제한된 server lifecycle 결정도 필요하다. E20의 원본 failure와 E21의 source-only bytes 및 역사 snapshot을 보존한다. 같은 attempt를 수정하거나 재개하지 않는다.

## 고정한 공식 source와 한계

아래 근거는 AOSP `platform/packages/modules/adb`의 commit `fb529d52f4485c1fdbe6208f20af6578493e1ca7`이다. 설치한 SDK binary와 이 source의 전체 동일성을 확인하지 않았다. 공식 source의 가능 경로를 실제 host 동작이나 원인으로 확정하지 않는다.

별도 파일 metadata 조사에서 선택한 adb는 symlink·ancestor alias가 없는 일반 파일이었다. 크기는 `18844128B`다. SHA-256은 `1811e253b21b12cbfda7201ebaf86c10e7ddcb5c606a7a81f7c82b4c429c2d3b`다. SDK의 두 metadata revision과 binary의 embedded version 후보는 모두 `37.0.1`이었다. binary를 실행하지 않았다. 조사 프로세스 HOME의 `.android`·user private key·public key는 존재했다. symlink·ancestor alias는 없었다. known-host file은 없었다. 이 HOME이 원본 runtime의 유효 HOME이라는 증거는 없다. key 유효성·vendor-key·endpoint 선택·설치 source 전체 대응·runtime 동작은 UNKNOWN이다. credential/key bytes와 환경값 원문은 출력하거나 기록하지 않았다. private metadata receipt의 SHA-256은 `c1eaeeae2bee9b93df35b0112040bb61d7690435639a9009d0334cb6b1d06096`다. 이 조사는 fresh preflight와 resource tuple 채택이 아니다.

| source | 확인한 사실 | SHA-256 |
| --- | --- | --- |
| [client/commandline.cpp:1523–1527,1593–1597,1662–1670](https://android.googlesource.com/platform/packages/modules/adb/+/fb529d52f4485c1fdbe6208f20af6578493e1ca7/client/commandline.cpp#1523) | server·nodaemon과 `-L`을 parse한다. nodaemon 분기는 `adb_server_main`을 직접 호출한다. | `a3da993989356e95f864744833bf309c2175d7a7e5110bf5d2c7e36e521ae349` |
| [client/main.cpp:86–182](https://android.googlesource.com/platform/packages/modules/adb/+/fb529d52f4485c1fdbe6208f20af6578493e1ca7/client/main.cpp#86) | foreground도 transport를 초기화한다. listener bind와 auth 초기화가 있다. SIGINT 처리도 있다. | `8ffbd78cce04df0d5d1a1fc358ce99a59c63f4dec8224d1d3090c14a240a7a1d` |
| [client/adb_client.cpp:256–340](https://android.googlesource.com/platform/packages/modules/adb/+/fb529d52f4485c1fdbe6208f20af6578493e1ca7/client/adb_client.cpp#256) | server 부재 때 launch한다. protocol mismatch 때 kill 후 launch한다. | `9f1f14d7bbad7ebb7ccbc5c92f917f0a737f37ac42c41d2c5e9ac76438ee1d7c` |
| [client/auth.cpp:63–106,207–244,415–434](https://android.googlesource.com/platform/packages/modules/adb/+/fb529d52f4485c1fdbe6208f20af6578493e1ca7/client/auth.cpp#63) | user key 부재 때 private key와 `.pub`를 쓴다. user key 뒤 vendor keys를 읽는다. | `aba13cf80b3db2998962127d687a09225cd831d3760dd55d0876b9ed5bf0ea75` |
| [adb_utils.cpp:310–319](https://android.googlesource.com/platform/packages/modules/adb/+/fb529d52f4485c1fdbe6208f20af6578493e1ca7/adb_utils.cpp#310) | 원본 home의 `.android`가 없으면 directory를 생성한다. | `747a7ceff6eedcc62b8ee9c6f962028d560f7abc4473135a032afb5c479d71a0` |
| [client/adb_wifi.cpp:104–120,169–172](https://android.googlesource.com/platform/packages/modules/adb/+/fb529d52f4485c1fdbe6208f20af6578493e1ca7/client/adb_wifi.cpp#104) | known-host file parse 실패 경로에서 해당 file을 삭제한다. known-host 조회도 이 loader를 소비한다. | `3d57dcdd3e0cd5dba9c66fb42dd962bf1bfcf48d9ad0599cbad720789da0ba4d` |
| [adb.h:71](https://android.googlesource.com/platform/packages/modules/adb/+/fb529d52f4485c1fdbe6208f20af6578493e1ca7/adb.h#71) | 이 source의 server protocol 상수는 41이다. 설치 binary의 기대값 증명은 아니다. | `448530595669e914264f314765c9d839dbc82c29e8f1e9a23b21738f23d4606a` |

`main`은 listener bind 전에 USB·mDNS·local transport 초기화를 수행한다. port bind 실패만으로 그 전의 효과가 없었다고 주장하지 않는다. default server는 외부 client가 연결할 수 있는 공유 endpoint다. foreground process 소유만으로 foreign client·device 사용 부재를 증명하지 않는다.

## full source/build 증거 기준과 중단 경로

### Q4: 확정한 증거 기준

full source/build 대응은 다음 연결을 공식 build 기록에서 직접 입증해야 한다. 각 연결의 근거·판정과 UNKNOWN을 구분한다.

| 연결 | 필요한 근거 |
| --- | --- |
| 공식 산출물의 digest와 archive ADB hash → 정확한 공식 build identity | 해당 산출물과 payload를 그 build에 연결하는 공식 기록 |
| 정확한 공식 build identity → 고정 source revision | 해당 build가 사용한 source revision을 연결하는 공식 기록 |
| 정확한 공식 build identity → dependency·toolchain·build 입력 | 해당 build의 dependency·toolchain·build 입력을 연결하는 공식 기록 |

모든 필수 연결을 입증하기 전에는 full source/build 대응을 PASS로 처리하지 않는다. version·공개 날짜·링크 후보·source 7개 hash는 이 연결을 대신하지 않는다. 특정 manifest 형식이나 bit-for-bit rebuild 방식을 새 필수 조건으로 지정하지 않는다. 기록의 형식보다 각 연결의 직접 근거를 검사한다.

현재 설치 상태와 syntax·protocol·환경·hostwrite·transport 대응 및 실제 compatibility는 기존 별도 gate를 유지한다. source/build 대응의 PASS만으로 startup·baseline 권한이나 readiness를 부여하지 않는다. [ADR-0034](0034-rn-adb-environment-evidence-gap.md)의 과거 환경 UNKNOWN과 향후 환경 기록 구분도 유지한다.

[기존 조사 문서](../research/rn-adb-existing-provenance.md)의 Q1·Q2는 공식 archive member hash와 과거 설치 hash 및 고정 source 7개 hash의 대응을 기록한다. Q3는 release notes의 한정 section에서 공개 revision과 날짜를 확인했다. 정확한 공식 build identity와 위의 source/build 입력 연결은 입증하지 못했다. full source/build 대응은 계속 UNKNOWN이다. 이 판정은 다른 공식 자료에도 근거가 없다는 결론이 아니다.

### Q5: 확정한 미입증 시 중단 경로

1. 필수 연결이 누락되거나 모호하면 UNKNOWN STOP이다. 증거가 모순되면 실패 STOP이다. 원본 실패와 과거 기록을 보존한다. 부분 PASS로 필수 UNKNOWN이나 실패를 상쇄하지 않는다.
2. URL 확대·재시도·다른 binary 설치·버전 변경·자동 복구·host write를 수행하지 않는다. 새 근거나 조건 변경에는 별도 범위 결정이 필요하다. 조건이 바뀐 실제 검증에는 [ADR-0020](0020-rn-baseline-prepared-input.md)의 새 실행 계약을 유지한다.
3. #212는 미완료다. PR #236을 병합하지 않는다. 실제 grant·fresh resource preflight·sole lease와 startup 뒤 compatibility 및 consumer 접합의 기존 gate를 유지한다.
4. 향후 실제 자원의 소유권이나 종료가 미입증이면 아래의 기존 CLEANUP_PENDING 계약을 적용한다. 자동 cleanup이나 RELEASED 판정으로 우회하지 않는다. 이번 결정은 실제 resource 상태를 판정하거나 cleanup을 실행하지 않는다.
5. 현재 source-only 경계를 유지한다. 이번 문서 저장은 추가 URL 조회·현재 SDK·HOME·key 읽기·실제 환경 수집·resource 조회·시작과 실제 준비 권한을 포함하지 않는다.

## 선택지와 추천 검토 범위

1. 원래 존재 predicate를 유지한다. 실제 준비는 STOP 상태를 유지한다. historical GUI를 다시 띄우거나 ADB daemon을 자동 복원하는 권한은 없다.
2. 새 resource 상태를 명시적으로 고정한다. GUI known-absent/known-present 조건과 ADB known-absent/known-present 조건을 나눈다. ADB 부재 분기에는 owner의 제한된 foreground 준비 후보를 추가한다. 추천 검토 범위는 이 두 번째 선택지다. 아래 frontier를 해결하기 전 actual 권한을 부여하지 않는다.

## GUI의 최소 상태 계약

새 준비의 fresh snapshot은 원래 보존 대상 GUI 역할과 canonical executable을 exact subject로 고정한다. 그 subject가 입증된 부재인지 입증된 존재인지 명시 state로 고정한다. historical PID만 null로 바꾸지 않는다. known-absent에서는 새 GUI를 시작하지 않는다. 같은 validation 중 해당 subject의 새 GUI가 나타나거나 snapshot의 범위가 불명확하면 STOP한다. known-present에서는 고정한 PID·start identity·canonical executable identity를 보존한다. 단순 PID 재사용을 같은 GUI로 받아들이지 않는다. 다른 사용자 GUI는 이 subject로 채택하거나 정리하지 않는다.

GUI snapshot은 앱 UI 성공 증거가 아니다. foreign GUI를 종료하거나 다시 실행하지 않는다. 실제 snapshot의 identity와 개인 경로는 원본 비공개 receipt에 둔다. 공개 문서에는 역할·판정·원본 hash만 둔다. source-only helper는 snapshot을 만들거나 present 값을 추정하지 않는다.

## ADB 초기 상태와 foreground 후보

### 기존 server가 있는 분기

default loopback 5037에 기존 server가 입증되면 원래 existing-server·empty-device 조건을 유지한다. 같은 canonical binary·start identity·listener identity와 client compatibility를 새 receipt에 연결해야 한다. 이름이 adb라는 사실만으로 연결하지 않는다. 연결된 foreign device와 추가 client 또는 unknown이 있으면 STOP한다. 기존 server를 소유 server로 다시 라벨링하지 않는다. 기존 server를 정리하거나 교체하지 않는다.

원본 client의 protocol mismatch는 기존 server를 kill할 수 있다. 따라서 mismatch를 확인하려고 원본 client부터 호출하지 않는다. kill·launch가 없는 제한된 smart-socket `host:version` 조회를 검토 후보로 둔다. 이 조회는 새 resource 관측 조건이다. observer의 기존 process query 변경이 아니다. 설치 client의 기대 protocol과 selected endpoint 및 해석 API의 근거가 불명확하면 STOP한다. 해당 조회의 구현과 설치 binary 대응은 아직 고정하지 않았다.

### 기존 server가 입증된 부재인 분기

5037의 known-free 결과를 fresh snapshot으로 고정한다. lsof 오류·다른 listener·상태 불명은 부재가 아니다. server 부재를 관측하려고 adb client를 호출하지 않는다. 부재를 original empty-device receipt로 바꾸지 않는다. 이 상태에서는 Android boot와 원본 adb consumer를 아직 실행하지 않는다.

별도 제한된 준비 권한의 후보 argv는 다음과 같다. `SELECTED_ADB`는 원래 선택한 SDK binary의 고정 canonical 경로와 digest다. 현재 파일이나 version을 여기서 조회하지 않았다.

```text
[SELECTED_ADB, "-L", "tcp:localhost:5037", "server", "nodaemon"]
```

정확한 argv는 loopback 5037만 요청한다. `-a`·다른 port·다른 SDK·launchd·background daemon·새 shell wrapper를 추가하지 않는다. owner는 이 foreground process를 직접 Popen하고 exact PID·start identity·executable·argv·lease·source authority·start event를 연결한다. server를 Metro process group에 넣지 않는다. 초기 bind에 실패하면 foreign server를 kill하거나 listener를 새 소유자로 채택하지 않는다. retry하지 않는다.

이 후보는 startup의 `launch_server` 경로를 우회한다. 이후 원본 client의 자동 start/kill까지 완전히 차단하는 후보는 아니다. default endpoint는 공유돼 있고 liveness 검사와 client 호출 사이 race가 남는다. selected binary와 protocol 및 endpoint가 같다는 source-only 판단을 실제 compatibility PASS로 사용하지 않는다.

### host 파일과 transport의 허용 밖 효과

최소 후보는 원본 home·key 선택·vendor key 환경을 유지한다. 새 `HOME`·`ANDROID_USER_HOME`·`ADB_VENDOR_KEYS`와 key 복사·생성을 자동 허용하지 않는다. source의 유효 home 결정과 실제 원본 준비 환경이 대응하는지 먼저 고정해야 한다. `.android`와 필요한 기존 user key 및 관련 host 파일의 존재·type·canonical 경계·유효성을 입증하지 못하면 시작하지 않는다. alias·symlink·불명 환경 입력이면 STOP한다.

host key 생성·rotation·known-host file 삭제·변경·추가 pairing·trust와 임의 shared write는 이 후보의 권한 밖이다. pinned source는 user key 부재 때 생성하고 기존 key는 load한다. malformed key를 안전한 입력으로 취급하지 않는다. malformed key를 자동 재생성한다고도 이 source 근거 없이 주장하지 않는다. known-host parse 실패 경로의 삭제를 승인하지 않는다. 현재 directory·key·known-host의 상태와 유효성은 UNKNOWN이다. 기존 keys가 있다는 사실만으로 known-host loader와 다른 write가 안전하다고 판단하지 않는다. 사전·사후 bytes가 같아도 일시 write가 없었다는 증거는 아니다. 이 감사는 관측한 변화를 검사한다. 감사에서 허용 밖 변화가 보이면 필수 STOP하고 원본 evidence를 보존한다. 이를 사후 발견으로 허용하는 성공 예외는 만들지 않는다.

USB·mDNS·network 및 emulator 탐색의 실제 범위도 고정해야 한다. 원본 server가 foreign device에 자동 접촉할 수 있다는 frontier를 유지한다. 이 제안은 임의 foreign device 접촉·authorization dialog·자동 network 연결을 승인하지 않는다. 환경 flag로 이를 막는 새로운 recipe를 임의로 만들지 않는다. 설치 source 대응과 효과의 bounded 조건이 입증되지 않으면 foreground 시작을 허가하지 않는다.

## consumer 연결과 종료 계약

원본 Android install·launch argv와 Metro 및 native recipe는 유지한다. 모든 adb consumer 직전에 현재 sole lease·server mode·effective endpoint·listener·canonical binary·PID/start identity·protocol을 연결한다. server-only 준비 단계의 기존 empty-device 조회에는 완성 own Emulator receipt를 요구하지 않는다. own Emulator receipt를 만드는 기존 조회에는 같은 lease의 provisional own-launch event를 먼저 연결한다. Android install·launch 단계에는 완성 own Emulator receipt를 먼저 연결한다. consumer 뒤에도 같은 server identity와 endpoint를 다시 연결한다. existing/owned의 준비 consumer 접합이 완료되기 전에는 `preparationReady=false`다. 기존 own Emulator·AVD·serial·readiness guard를 유지한다. 초기 known-absent와 server 준비 완료 및 Android own-state를 서로 다른 phase receipt로 기록한다. 부재를 계속 existing-server PASS로 취급하지 않는다. 이 단계 구분은 query·argv·순서를 추가하거나 변경하지 않는다.

서버의 예상치 못한 종료·교체·protocol mismatch·외부 client/device·추가 listener·unknown이면 후속 consumer를 호출하지 않는다. 원본 client 자체가 자동 start/kill한 사실이 발견되면 새 server를 채택하거나 original command exit 0으로 상쇄하지 않는다. 연결 snapshot은 중간에 잠깐 연결한 foreign client의 부재를 증명하지 않는다. 최초 실패와 사후 감사 및 lifecycle receipt를 보존한다. 추가 observer retry·query·sampling·sleep·errno 변경은 없다.

기존 server는 종료 대상이 아니다. 새 foreground server도 process 소유만으로 종료하지 않는다. 현재 같은 PID/start/executable·listener와 foreign client/device 사용 부재를 확인한 경우만 own process 종료 후보가 된다. 공식 source의 SIGINT 처리를 근거로 own PID에 제한된 SIGINT와 bounded wait를 검토한다. `adb kill-server`·전체 adb kill·global process cleanup은 금지한다. 다른 PID·대체 listener·orphan을 소유자로 추정하지 않는다.

foreign 사용·불명 identity·종료 미확인이면 자동 kill하지 않고 `CLEANUP_PENDING`으로 root에 인계한다. owner process group과 `finally`의 자동 stop으로 이 조건을 우회하지 않는다. resource가 남았는데 canonical RELEASED를 선언하지 않는다. 다른 worker에게 같은 자원을 배정하지 않는다. foreground 생성·종료와 shared before/after 및 preserved foreign resource를 원본 receipt에 연결한다. 실제 SIGINT 종료·client compatibility·cleanup은 미실행이며 PASS가 아니다.

## 아직 필요한 frontier와 별도 gate

다음은 현재 미확정이다. 문서·memory 성공으로 대체하지 않는다.

1. 원래 selected SDK binary와 pinned source의 syntax·protocol·환경·hostwrite 대응이다. binary identity와 local version 정보 및 실제 제한된 준비 evidence가 필요하다. 현재 binary를 실행하지 않았다.
2. 원본 home·keys·known-host 유효성과 USB·mDNS·network 접촉의 bounded 조건이다. 현재 파일·port·foreign client/device 상태를 읽지 않았다. host key 생성과 global write를 포함시키는 별도 예외를 만들지 않는다.
3. 자동 client start/kill의 race와 공유 endpoint의 cleanup 소유권이다. 사전 검사만으로 완전 방지를 주장하지 않는다. 제한된 관측 seam과 실패시 `CLEANUP_PENDING`의 계약을 source-only로 고정해야 한다. 필수 보호를 입증할 수 없으면 실제 준비 계획을 STOP한다.

정책·helper의 준비는 다음 순서다.

1. 원본 E20 checkpoint와 E21 source-only history를 보존한다. 독립 검토한 문서와 primary 근거를 바탕으로 사용자는 source-only 범위만 확정했다. frontier의 미해결 상태를 유지한다. 실제 resource 조건 채택·실제 실행은 없다.
2. 확정한 source-only 정책을 main에 반영한다. 실제 GUI 상태 적용과 ADB 제한 준비·관측·허용 write 및 cleanup은 구체적 근거와 별도 사용자 결정을 요구한다. 해결하지 않은 위험을 묵시적 권한으로 포함하지 않는다.
3. 새 source-only helper·PLAN·resource tuple 모델·phase schema와 policy/hash/map/index/batch/review/preflight authority를 고정한다. GUI 부재/존재, ADB 부재/존재, protocol·foreign·identity mismatch와 cleanup pending을 memory에서 검사한다. 실제 process·socket·FFI·network와 persistent write를 거부한다.
4. 두 독립 review 뒤에도 실제 권한은 자동 발생하지 않는다. root의 별도 제한된 준비 grant와 fresh resource preflight 및 sole lease가 필요하다. 그 권한의 명령·대상·write 경계·owner·종료 조건을 정확히 고정한다. 허용한 fresh 읽기 증거로 safe initial host 조건과 selected client compatibility의 필수 근거를 확인하지 못하면 startup grant를 발급하지 않는다. startup 후 실제 compatibility와 consumer 접합을 확인하기 전에는 baseline grant를 발급하지 않는다. 포트가 free이거나 key가 있다고 추정하지 않는다.
5. 제한 준비를 실제로 검증한 후 새 baseline actual grant와 fresh preflight를 별도로 고정한다. 두 새 baseline의 iOS·Android 첫 화면 네 개 뒤 각 독립 fresh를 검증하는 기존 계약을 유지한다. 이전 성공과 clone·private state·node_modules·vendor·Pods·build 및 lease를 승계하지 않는다.
6. consumer failure·관측 오류·허용 밖 변화·unknown이면 필수 STOP한다. foreign resource를 보존한다. own cleanup이 입증되지 않으면 pending으로 유지한다. 정책·CI·source-only·server readiness는 첫 화면 PASS가 아니다.

[ADR-0020](0020-rn-baseline-prepared-input.md)의 원본 입력·failure 보존과 [ADR-0031](0031-rn-observer-loop-lifecycle-diagnostics.md)의 진단 및 모든 원래 오류 STOP을 유지한다. mise identity 채택은 resource 조건의 채택이나 실제 준비 권한이 아니다. 실제 Runstir CLI·GUI gate는 후속이다. #212와 PR #236은 열린 상태를 유지한다.

## 확정한 source-only 범위

사용자는 GUI의 known-present/known-absent 계약과 ADB의 phase별 receipt·ownership·STOP·CLEANUP_PENDING 계약을 문서와 source-only memory 모델로 준비하는 범위만 확정했다. 채택 상태는 이 source-only 범위에만 적용한다. 이 범위는 GUI·ADB 시작, 새 실제 snapshot, host key·known-host write, runtime 조건의 실제 적용, 실제 재개를 포함하지 않는다. 원본 resource predicate는 실제 경로에서 계속 유지한다. 위의 hostwrite·transport·protocol·race frontier와 설치 binary 대응은 미해결이다. 실제 제한 준비 제안은 이 frontier의 구체적 근거와 별도 범위 결정이 필요하다. source-only 범위 확정으로 실제 제한 준비 권한을 대신하지 않는다.

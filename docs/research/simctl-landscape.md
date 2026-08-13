# simctl/CoreSimulator 제어 지형 조사 (SpikeIOS 준비)

- Issue: #6
- 작성일: 2026-08-13
- 검증 환경: macOS (Darwin 25.6), **Xcode 26.6 (17F113)**, iOS 26.5 runtime (23F77). 아래 "실측"으로 표기된 출력은 이 맥에서 실제로 실행해 확인한 것.

## TL;DR — spike에 치명적인 함정 3개

1. **`simctl boot`는 부팅 완료를 기다리지 않는다.** boot 리턴 직후 install/launch 하면 간헐 실패. 반드시 `xcrun simctl bootstatus <udid> -b`로 부팅 완료를 블로킹 대기할 것 (boot 자체도 `-b`가 해줌). 단독으로 쓰면 안전한 유일한 대기 수단이고, appium도 결국 이 방식 + 자체 타임아웃(기본 120s)으로 수렴했다.
2. **모든 simctl 호출은 "선택된 Xcode"(`xcode-select`/`DEVELOPER_DIR`)에 결박된다.** Xcode가 여러 개면 device/runtime 목록·생성 가능 조합이 Xcode마다 다르고, 선택된 Xcode와 다른 CoreSimulatorService가 이미 떠 있으면 버전 불일치 오류가 난다. 툴은 시작 시 `xcode-select -p`를 읽어 로그에 남기고, 모든 하위 프로세스에 `DEVELOPER_DIR`를 명시적으로 고정해야 한다.
3. **runtime은 Xcode 번들이 아니라 시스템 전역 상태이며, 조용히 깨진다.** Xcode 15+부터 runtime은 별도 cryptex 디스크 이미지(`/Library/Developer/CoreSimulator/Volumes`, 실체는 `/System/Library/AssetsV2/...`)로 마운트되는데, macOS 업데이트·재부팅 후 "runtime is not available / runtime profile not found"로 devices가 `isAvailable: false`가 되는 사례가 반복 보고된다. 툴은 `isAvailable == true`인 device만 대상으로 삼고, unavailable은 에러 메시지에 복구 절차(`runtime scan-and-mount`, `delete unavailable`)를 안내해야 한다.

---

## 1. spike 범위 명령 레퍼런스

공통: `xcrun simctl [--set <path>] <subcommand> ...`. `<device>` 자리에는 UDID 또는 `booted`(부팅된 것 중 임의 선택 — **다중 부팅 시 어느 것이 잡힐지 보장 없음**, 툴에서는 항상 UDID 사용). 성공 시 exit 0, 실패 시 비0 + stderr 메시지. `--set`으로 device set 경로를 바꿔 격리된 시뮬레이터 풀을 만들 수 있다(테스트 격리에 유용, appium이 사용하는 기법).

### 1.1 `list` — 조회

```
xcrun simctl list [-j | --json] [-v] [devices|devicetypes|runtimes|pairs] [<search term>|available]
```

- `--json` 지원. `simctl list --json`은 `devices`/`runtimes`/`devicetypes`/`pairs` 네 키를 모두 담은 단일 객체.
- `devices --json` 구조 (실측, Xcode 26.6):

```json
{
  "devices" : {
    "com.apple.CoreSimulator.SimRuntime.iOS-26-5" : [
      {
        "lastBootedAt" : "2026-08-11T05:21:34Z",
        "dataPath" : "~/Library/Developer/CoreSimulator/Devices/<UDID>/data",
        "dataPathSize" : 5251244032,
        "logPath" : "~/Library/Logs/CoreSimulator/<UDID>",
        "udid" : "61DECACB-...",
        "isAvailable" : true,
        "deviceTypeIdentifier" : "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro",
        "state" : "Shutdown",
        "name" : "iPhone 17 Pro - iOS 26.5"
      }
    ]
  }
}
```

  - 키는 **runtime identifier별 그룹**. `state`: `Shutdown` / `Booted` (과도기에 `Booting`, `Shutting Down`).
  - `isAvailable: false`면 `availabilityError` 필드가 추가된다(예: `"runtime profile not found"`). **파싱 시 이 두 필드를 항상 확인.**
- `runtimes --json`: `runtimes` 배열. 항목 필드(실측): `identifier`, `version`, `buildversion`, `isAvailable`, `supportedArchitectures`, `supportedDeviceTypes[]`(각각 `name`/`identifier`/`bundlePath`/`productFamily`). → **create 가능한 (devicetype, runtime) 조합의 진실원천은 `supportedDeviceTypes`.**
- `devicetypes --json`: `devicetypes` 배열 (`name`, `identifier`, `bundlePath`, `productFamily`, min/max runtime 버전).

### 1.2 `create`

```
xcrun simctl create <name> <device type id> [<runtime id>]
```

- device type은 이름(`"iPhone 17 Pro"`) 또는 identifier 둘 다 허용. runtime 생략 시 **해당 device type과 호환되는 최신 runtime 자동 선택**.
- 성공 시 stdout에 **새 UDID 한 줄만** 출력 → 그대로 캡처해서 쓰면 된다. `--json` 없음.
- 함정: 이름은 유니크 제약이 없다. 같은 이름 device 여러 개 생성 가능 → 툴 내부에서는 이름이 아니라 UDID로만 추적할 것.

### 1.3 `boot` + 부팅 완료 감지

```
xcrun simctl boot <device> [--arch=<arch>] [--disabledJob=<job>] [--enabledJob=<job>]
xcrun simctl bootstatus <device> [-bcd]
```

- `boot`는 **비동기적**: 명령이 리턴해도 SpringBoard까지 뜬 상태가 아니다. 이미 부팅된 device에 다시 boot 하면 exit 149 계열 "Unable to boot device in current state: Booted" 에러.
- `bootstatus`가 공식 대기 수단 (실측 help): "Monitors the specified device and prints boot status information **until the device finishes booting**. You can safely call this before you attempt to start booting the device."
  - `-b`: 부팅 안 되어 있으면 부팅까지 수행 → **`bootstatus <udid> -b` 한 방이 idempotent boot+wait.** 이미 Booted면 즉시 리턴.
  - `-d`: 데이터 마이그레이션 진행상황 출력(런타임 업그레이드 직후 부팅이 오래 걸리는 이유가 이것).
- 환경변수 주입: 호출 셸에 `SIMCTL_CHILD_FOO=bar`를 설정하면 시뮬레이터 안 프로세스 환경에 `FOO=bar`로 전달 (boot/launch 공통).
- bootstatus는 드물게 행업하는 사례가 보고됨(appium/appium#13317) → **툴 쪽 자체 타임아웃(120s 권장, appium 기본값)으로 감싸고 초과 시 프로세스 kill + 진단 로그**.

### 1.4 `install`

```
xcrun simctl install <device> <path>
```

- `<path>`는 **시뮬레이터용으로 빌드된 `.app` 번들 디렉터리** (`.ipa` 아님). arm64 맥에서 디바이스용(iphoneos) 빌드를 넣으면 아키텍처가 같아 설치는 되는 척하다 launch에서 죽는 케이스가 있으니, 툴에서 `Info.plist`의 플랫폼 확인 또는 launch 실패 메시지 매핑을 해두면 진단이 쉽다.
- device는 **Booted 상태여야 안정적** (Shutdown 상태 설치는 버전에 따라 동작이 달라 신뢰 불가 → spike에서는 boot 후 install로 고정).
- 출력 없음(성공 시 침묵). 실패는 exit code + stderr.

### 1.5 `launch`

```
xcrun simctl launch [-w|--wait-for-debugger] [--arch=<arch>] [--console|--console-pty]
                    [--stdout=<path>] [--stderr=<path>] [--terminate-running-process]
                    <device> <app bundle identifier> [<argv...>]
```

- 성공 시 stdout에 `<bundle id>: <pid>` 출력 → pid 파싱 가능.
- `--console`/`--console-pty`: **블로킹**하며 앱 stdout/stderr를 터미널로 스트리밍. 시그널 전달됨. `--stdout/--stderr`와 배타.
- 이미 실행 중인 앱을 다시 launch 하면 에러 → `--terminate-running-process`로 재시작 시맨틱 확보.
- 주의(help 원문): 앱 로그는 보통 stderr로 나온다. 캡처하려면 `--stderr` 쪽을 잡을 것.
- 종료는 `simctl terminate <device> <bundle id>`.

### 1.6 `io screenshot`

```
xcrun simctl io <device> screenshot [--type=png|tiff|bmp|gif|jpeg] [--display=<d>] [--mask=ignored|alpha|black] <file | ->
```

- `-` 지정 시 stdout으로 PNG 바이트 출력 (파이프 가능). 기본 png.
- device는 Booted여야 함 (실측: 미부팅 시 "No devices are booted." 에러).
- 참고로 `io recordVideo`도 동일 위치에 있으며 "Recording started"가 stderr에 찍힌 후 SIGINT로 종료하는 프로토콜.

### 1.7 `shutdown` / `delete` / `erase`

```
xcrun simctl shutdown <device>|all
xcrun simctl delete <device>...|unavailable|all
xcrun simctl erase <device>...|all
```

- `shutdown all`: 모든 부팅 device 정리(CI 클린업 정석). 이미 Shutdown이면 "current state: Shutdown" 에러(exit 149) — 툴에서는 이 에러를 무해한 것으로 처리.
- `delete unavailable`: runtime이 사라져 못 쓰게 된 device 일괄 삭제 — 상태 불일치 복구의 핵심 명령.
- `erase`는 device를 공장초기화(콘텐츠/설정 삭제). **Shutdown 상태에서만 가능.** appium/fastlane 모두 클린 상태 확보에 `shutdown` → `erase` 순서를 쓴다.

## 2. Runtime 관리 (`xcrun simctl runtime`)

```
xcrun simctl runtime add <path.dmg> [-m|--move] [-a|--async]
xcrun simctl runtime delete (<identifier>|all|--notUsedSinceDays <d>) [--dry-run] [--keep-asset]
xcrun simctl runtime unmount <identifier>
xcrun simctl runtime list [-v] [-j|--json]
xcrun simctl runtime scan-and-mount
xcrun simctl runtime match list|set [-j]
```

- `runtime list -j` (실측) — 키는 이미지 UUID:

```json
{
  "369CAC13-..." : {
    "build" : "23F77",
    "deletable" : true,
    "kind" : "Patchable Cryptex Disk Image",
    "mountPath" : "/Library/Developer/CoreSimulator/Volumes/iOS_23F77",
    "path" : "/System/Library/AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime/<hash>.asset/AssetData/Restore/094-56039-099.dmg",
    "runtimeBundlePath" : ".../Volumes/iOS_23F77/.../Runtimes/iOS 26.5.simruntime",
    "runtimeIdentifier" : "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
    "signatureState" : "Verified",
    "sizeBytes" : 8494282293,
    "state" : "Ready",
    "version" : "26.5"
  }
}
```

- **Xcode 결합 관계**: Xcode 15+는 iOS runtime을 Xcode.app에 내장하지 않고 다운로드형 디스크 이미지로 분리했다. 저장 실체는 `/System/Library/AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime/`(MobileAsset, 시스템 전역·SIP 보호), 마운트 지점은 `/Library/Developer/CoreSimulator/Volumes/<OS>_<build>`. 즉 **runtime은 머신 전역 자원이고, 어떤 runtime이 "보이는지/선호되는지"는 선택된 Xcode의 SDK↔runtime 매칭 규칙(`runtime match list`)이 결정**한다. 구식 경로 `/Library/Developer/CoreSimulator/Profiles/Runtimes`는 legacy `.simruntime` 번들용(이 맥에는 없음, 실측).
- 수동 설치 절차: developer.apple.com에서 dmg 다운로드 → `xattr -cr <dmg>`로 쿼런틴 제거(안 하면 verify 실패 사례) → `simctl runtime add <dmg>` (또는 `xcodebuild -importPlatform`). `xcodes runtimes install "iOS 17.x"`는 이 다운로드+add를 자동화한 것.
- `runtime delete`는 booted 시뮬레이터를 **먼저 shutdown시키고** 언마운트 후 삭제. `--dry-run`이 있으니 툴의 삭제 UX에 활용 가치 있음.
- `scan-and-mount`: 재부팅/업데이트 후 고아 runtime을 재발견하는 복구 명령.
- 디스크 사용량 주의: runtime 하나가 5~8GB+. CI에서 `--notUsedSinceDays`로 청소 가능.

## 3. 알려진 edge case

### 3.1 headless boot vs Simulator.app

- `simctl boot`는 **Simulator.app 없이 headless로 부팅**한다. 창이 필요하면 `open -a Simulator`(현재 device set의 booted device들을 표시)를 별도로 실행.
- 역방향 결합이 함정: Simulator.app을 **종료하면 그 안에 보이던 device들이 shutdown**된다(설정에 따라). 또 appium 문서 기준, headless 세션을 시작하면 떠 있던 Simulator UI 인스턴스가 종료될 수 있다. → 툴은 "headless가 기본, UI는 opt-in"으로 설계하고, Simulator.app의 생존을 device 생존과 동일시하지 말 것.
- headless 부팅 상태에서 `io screenshot`, `launch --console` 모두 정상 동작(프레임버퍼는 창 없이도 존재).

### 3.2 다중 Xcode / `xcode-select` / `DEVELOPER_DIR`

- `xcrun`은 `DEVELOPER_DIR` env > `xcode-select -p` 순으로 Xcode를 고른다. simctl 바이너리·CoreSimulator 프레임워크·사용 가능 devicetype/runtime 목록이 전부 여기 결박.
- CoreSimulatorService는 launchd 데몬으로 **한 번 뜨면 버전이 고정**된다. Xcode를 바꾼 직후 이전 버전 데몬이 살아 있으면 "CoreSimulatorService connection became invalid" / 버전 불일치 오류 → `killall -9 com.apple.CoreSimulator.CoreSimulatorService` (또는 `launchctl remove`) 후 재시도하면 새 버전으로 재기동.
- 툴 지침: (a) 시작 시 `xcode-select -p`와 `xcodebuild -version`을 로그, (b) 하위 프로세스에 `DEVELOPER_DIR` 명시 전달, (c) 위 connection invalid 에러를 감지하면 데몬 재시작을 복구 절차로 안내.

### 3.3 runtime 상태 불일치 (Apple Developer Forums 보고 사례)

- macOS 업데이트가 Xcode 15용 runtime을 비활성화해 "The com.apple.CoreSimulator.SimRuntime.iOS-17-2 simulator runtime is not available" 발생 (forums thread 751135). 복구: Xcode에서 재다운로드 또는 `runtime scan-and-mount`.
- runtime 파일은 존재하는데 devices가 `(unavailable, runtime profile not found)` (thread 723603) — list JSON에서 `isAvailable: false` + `availabilityError`로 나타남.
- 재부팅 후 시뮬레이터가 삭제/손상되어 보이는 사례 (thread 740632), MobileAsset 영역에 고아 runtime이 남아 SIP 때문에 수동 삭제 불가한 사례 (thread 812992) — 삭제는 반드시 `simctl runtime delete` 경유.
- 공통 복구 루틴: `shutdown all` → `delete unavailable` → `runtime scan-and-mount` → (최후) CoreSimulatorService kill. spike의 doctor 커맨드 후보.

### 3.4 기타

- `simctl` 일부 명령은 첫 실행 시 CoreSimulatorService 기동 때문에 수 초 지연될 수 있음(타임아웃 계산에 반영).
- `status_bar` 등 주변 명령은 iOS 메이저 업데이트 때 조용히 깨진 전력이 있다(iOS 17에서 수 개월 미작동, Jesse Squires 보고). spike 범위 밖 명령에 의존할 때는 버전 가드 필요.
- `runtime add`가 Security & Privacy 승인(App Management 권한)을 요구하는 환경이 있다 (forums thread 739842) — CI/헤드리스 맥에서 자동화 시 걸림돌.

## 4. 선행 도구에서 배울 것

| 도구 | 전략 | 교훈 |
|---|---|---|
| **appium-xcuitest-driver** | udid 미지정 시 create→사용→delete(일회용 디바이스), udid 지정 시 기존 상태 존중. 부팅 대기는 자체 타임아웃 120s. 별도 device set으로 격리 가능 | 일회용 디바이스 패턴이 상태 불일치를 대부분 회피한다. "빌리면 원상복구" 시맨틱. 부팅 대기엔 반드시 외부 타임아웃 |
| **fastlane** (simulator 관련 액션) | `reset_simulator` 계열: shutdown all → erase로 클린 상태 확보. UDID 기반 조작, `list --json` 파싱 | 이름이 아닌 UDID로만 디바이스 식별. 클린업을 성공 경로가 아닌 항상-실행(ensure) 경로에 배치 |
| **xcodes** (`xcodes runtimes`) | Apple 공개 인덱스에서 dmg 다운로드 → `simctl runtime add`. 다운로드 재개/체크섬 처리 | runtime 설치는 결국 simctl 위임이 정답. 쿼런틴(`xattr`)과 디스크 공간 체크를 도구가 대신 해주는 게 가치 |
| **RocketSim** | Simulator.app에 UI를 얹는 접근(스크린샷/녹화/딥링크는 simctl 호출) | 코어 조작은 전부 simctl로 가능하다는 방증. 프레임 합성 같은 부가가치만 자체 구현 |

## 5. SpikeIOS 권장 시퀀스 (결론)

```bash
export DEVELOPER_DIR="$(xcode-select -p | sed 's|/Contents/Developer||')/Contents/Developer"  # 명시 고정
xcrun simctl list --json                                   # 파싱: isAvailable==true 필터
UDID=$(xcrun simctl create "spike-ios" "iPhone 17 Pro")    # stdout == UDID
timeout 120 xcrun simctl bootstatus "$UDID" -b             # boot + 완료 대기 (idempotent)
xcrun simctl install "$UDID" ./Build/MyApp.app
xcrun simctl launch --terminate-running-process "$UDID" com.example.myapp   # stdout: "bundle: pid"
xcrun simctl io "$UDID" screenshot ./shot.png
xcrun simctl shutdown "$UDID"                              # 이미 Shutdown 에러는 무시
xcrun simctl delete "$UDID"
```

## 출처

- 실측: Xcode 26.6 (17F113) `xcrun simctl help <cmd>`, `simctl list --json`, `simctl runtime list -j` (2026-08-13, 이 문서 작성 머신)
- [Apple: Resolving "Simulator runtime is not available"](https://developer.apple.com/forums/thread/751135)
- [Apple Forums: runtime 존재하는데 unavailable (thread 723603)](https://developer.apple.com/forums/thread/723603)
- [Apple Forums: 재부팅 후 시뮬레이터 삭제/손상 (thread 740632)](https://developer.apple.com/forums/thread/740632)
- [Apple Forums: SIP 보호된 고아 runtime (thread 812992)](https://developer.apple.com/forums/thread/812992)
- [Apple Forums: runtime add의 동작 (thread 739175)](https://developer.apple.com/forums/thread/739175) / [Security & Privacy 승인 요구 (thread 739842)](https://developer.apple.com/forums/thread/739842)
- [appium-xcuitest-driver: capabilities (simulatorStartupTimeout 등)](https://github.com/appium/appium-xcuitest-driver/blob/master/docs/reference/capabilities.md) / [XCUITest driver 문서: 시뮬레이터 생명주기](https://appium.readthedocs.io/en/latest/en/drivers/ios-xcuitest/) / [bootstatus 행업 이슈 #13317](https://github.com/appium/appium/issues/13317)
- [XcodesApp: runtime 다운로드/설치 이슈 #457](https://github.com/XcodesOrg/XcodesApp/issues/457)
- [수동 runtime 설치 가이드 (xattr 쿼런틴 포함)](https://github.com/ivanopcode/devnote-xcode-manual-runtime-install)
- [Lickability: iOS 17 시뮬레이터 설치](https://lickability.com/blog/how-to-install-ios-17-simulators-in-xcode-15/)
- [Jesse Squires: simctl status_bar가 iOS 17에서 깨진 사례](https://www.jessesquires.com/blog/2024/01/04/simctl-status_bar-still-broken/)

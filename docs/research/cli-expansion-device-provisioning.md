# Simulator·Emulator 준비와 생성의 자동화 경계

조사일: 2026-10-09. 대상 host: macOS Apple Silicon.
기준 소스: `1a4ff6dc3815ab6c25df81eaef8ca37acaefe21e`.
관련 티켓: [조사: Simulator·Emulator 준비와 생성의 자동화 경계](https://github.com/minjunkim-dev/mobile-runtime/issues/180).

이 문서는 공식 기능과 관측 결과를 기록한다. Runstir의 지원 버전이나 설치 정책은 결정하지 않는다. 설치·라이선스 동의·기기 생성·부팅·삭제·앱 실행·Tart 검증은 수행하지 않았다.

## 현재 Runstir 계약

`build`와 `up`은 Xcode 및 runtime을 설치하지 않는다. 도구 활성화와 프로비저닝을 구분한다. [ADR-0009](https://github.com/minjunkim-dev/mobile-runtime/blob/1a4ff6dc3815ab6c25df81eaef8ca37acaefe21e/docs/adr/0009-activate-project-toolchains-without-provisioning.md).

iOS는 선언한 이름, 이미 부팅한 기기, 기존 iPhone 순서로 선택한다. 선언한 이름에 해당하는 기기가 없거나 runtime이 unavailable이면 구체적인 remediation을 낸다. 기기가 없으면 `simctl create`를 안내한다. 직접 생성하지 않는다. 선택 이후 명령은 UDID를 사용한다. 부팅에는 `bootstatus <UDID> -b`를 사용한다. [SimulatorSelection](https://github.com/minjunkim-dev/mobile-runtime/blob/1a4ff6dc3815ab6c25df81eaef8ca37acaefe21e/Sources/SimulatorKit/SimulatorSelection.swift), [SimctlDeviceList](https://github.com/minjunkim-dev/mobile-runtime/blob/1a4ff6dc3815ab6c25df81eaef8ca37acaefe21e/Sources/SimulatorKit/SimctlDeviceList.swift), [DeviceStage](https://github.com/minjunkim-dev/mobile-runtime/blob/1a4ff6dc3815ab6c25df81eaef8ca37acaefe21e/Sources/SimulatorKit/DeviceStage.swift).

Android는 활성 실행에 AVD 이름·serial과 자원별 소유 상태를 기록한다. 정리 전 identity를 재확인한다. 재사용 자원과 확인 불가능한 자원은 보존한다. 기존 계약은 AVD 생성·삭제와 앱 uninstall·clear-data를 수행하지 않는다. iOS에 같은 rollback 계약이 있다고 가정하지 않는다. [ADR-0013](https://github.com/minjunkim-dev/mobile-runtime/blob/1a4ff6dc3815ab6c25df81eaef8ca37acaefe21e/docs/adr/0013-android-owned-runtime-lifecycle.md).

## iOS: Xcode, runtime, 기기는 별도 자원이다

| 단계 | 공식 기능 | 관측할 대상과 경계 |
| --- | --- | --- |
| 도구 준비 | Apple은 선택한 Xcode에서 `xcodebuild -runFirstLaunch`로 `simctl` 등 필수 구성요소를 준비하도록 안내한다. | Xcode 설치와 첫 실행 준비가 끝나야 runtime 설치 경로를 사용할 수 있다. 이 조사에서는 준비 명령을 실행하지 않았다. |
| runtime 다운로드 | `xcodebuild -downloadPlatform iOS`에 `-exportPath`, `-buildVersion`, `-architectureVariant`를 지정할 수 있다. | OS 버전 요청과 아키텍처 variant를 기록할 수 있다. 기본값은 host와 Rosetta run destination에 따라 달라진다. |
| runtime 설치 | 내려받은 runtime은 `xcodebuild -importPlatform <simruntime.dmg>`로 설치할 수 있다. | 다운로드 파일과 설치된 runtime은 다르다. Apple은 Xcode Components 화면의 다운로드·설치·삭제 경로도 제공한다. |

위 세 단계의 근거: [Downloading and installing additional Xcode components](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components). CLI 기능의 존재는 임의의 Xcode·macOS·runtime 조합 성공을 보장하지 않는다.

다음 기능은 **로컬 Xcode 27.0 / build 27A266a의 읽기 전용 help**로 확인했다. 명령은 문법 기록이며 실행 절차가 아니다.

| 기능 | 확인한 문법 | identity와 부작용 경계 |
| --- | --- | --- |
| 목록 | `simctl list [-j] [devices\|devicetypes\|runtimes] [available]` | 이름과 runtime·device type 식별자를 분리해서 조회할 수 있다. 이름 검색은 부분 문자열 검색이다. |
| 생성 | `simctl create <name> <device type id> [<runtime id>]` | available device type과 runtime이 필요하다. runtime을 생략하면 device type과 호환되는 최신 runtime을 고른다. |
| 부팅 완료 | `simctl bootstatus <device> -b` | 부팅되지 않았으면 부팅한다. 부팅 완료까지 기다린다. 일반 `<device>` 인수에는 UDID를 사용할 수 있다. `booted` 별칭은 여러 기기 중 하나를 고를 수 있다. |
| 기기 삭제·초기화 | `simctl delete <device>` / `simctl erase <device>` | 삭제와 데이터 초기화는 다르다. `all`은 모든 기기에 영향을 준다. `delete unavailable`은 현재 Xcode SDK가 지원하지 않는 기기를 삭제한다. |
| runtime 관리 | `simctl runtime list -j`, `add <path>`, `delete <identifier> --dry-run` | 설치된 runtime image는 UUID로 관리한다. runtime 삭제는 해당 runtime을 쓰는 부팅 기기를 shutdown할 수 있다. SDK build와 runtime build의 mapping도 별도 조회한다. |

로컬 primary source: 2026-10-09에 `xcodebuild -version`, `xcrun simctl help`, `help list`, `help create`, `help bootstatus`, `help delete`, `help erase`, `help runtime`을 실행했다. help에 나온 `runtime add`는 검증·mount를 수행한다. `--move`는 성공 시 원본 파일도 제거한다. 이 명령은 실행하지 않았다. 기기 UDID, runtime identifier, runtime image UUID, OS 버전, SDK/runtime build는 같은 값이 아니다.

Runstir는 device type의 runtime 하한·상한을 확인해 생성 안내를 만든다. installed와 available도 구분한다. 이는 현재 코드의 조건이다. Apple의 모든 조합을 검증한 표가 아니다. [SimctlDeviceTypeList](https://github.com/minjunkim-dev/mobile-runtime/blob/1a4ff6dc3815ab6c25df81eaef8ca37acaefe21e/Sources/SimulatorKit/SimctlDeviceTypeList.swift), [SimulatorRuntimeCheck](https://github.com/minjunkim-dev/mobile-runtime/blob/1a4ff6dc3815ab6c25df81eaef8ca37acaefe21e/Sources/SimulatorKit/SimulatorRuntimeCheck.swift).

## Android: 기존 도구와 새 Android CLI를 구분한다

조사일의 공식 문서는 `sdkmanager`, `avdmanager`, `emulator`를 deprecated로 표시한다. 각각 `android sdk`와 `android emulator`를 안내한다. 기존 명령의 문서도 남아 있다. 이 사실은 Runstir가 즉시 새 CLI로 전환해야 한다는 결정이 아니다. [sdkmanager](https://developer.android.com/tools/sdkmanager), [avdmanager](https://developer.android.com/tools/avdmanager), [Emulator command line](https://developer.android.com/studio/run/emulator-commandline).

| 단계 | 기존 공식 CLI | 관측할 대상과 경계 |
| --- | --- | --- |
| 패키지 준비 | `sdkmanager --list` / `sdkmanager "<package>" --sdk_root=<path>` | 설치된 패키지와 다운로드 가능한 패키지를 구분한다. 패키지별 라이선스 동의가 필요하다. `--licenses`는 미동의 라이선스를 질문한다. |
| AVD 목록·생성 | `avdmanager list avd`, `list device`, `create avd -n <name> -k "<package>"` | 생성에는 이름과 system image package가 필요하다. `-p`는 AVD 파일 경로다. 기본 경로는 `~/.android/avd/`다. `-f`는 같은 이름의 기존 AVD를 덮어쓴다. |
| 선택·부팅 | `emulator -list-avds`, `emulator -avd <name>` | AVD 이름을 선택한다. system image는 API level·variant·architecture별 공유 파일이다. AVD의 사용자 데이터는 별도이며 재시작 후에도 남는다. |
| 삭제·초기화 | `avdmanager delete avd -n <name>`, `sdkmanager --uninstall "<package>"`, `emulator -wipe-data` | AVD 삭제, 공유 패키지 제거, 사용자 데이터 초기화는 다르다. `-wipe-data`는 설치한 앱·설정을 지운다. |

패키지와 라이선스 근거: [sdkmanager](https://developer.android.com/tools/sdkmanager). 생성·경로·덮어쓰기 근거: [avdmanager](https://developer.android.com/tools/avdmanager). 실행·데이터 근거: [Emulator command line](https://developer.android.com/studio/run/emulator-commandline).

API level만 맞추면 충분하지 않다. system image의 API는 앱의 `minSdk` 이상이어야 한다. Google APIs·Google Play 및 외부 library 요구도 별도로 맞아야 한다. 필요한 hardware feature도 AVD에 있어야 한다. [Create and manage virtual devices](https://developer.android.com/studio/run/managing-avds).

Apple Silicon의 VM acceleration에는 ARM64 host와 `arm64-v8a` system image 조합이 문서화되어 있다. macOS는 내장 `Hypervisor.Framework`를 사용한다. `emulator -accel-check`로 관측할 수 있다. Android 공식 문서는 VM 안의 가속 Emulator 실행을 제한한다. 따라서 Tart의 성공을 Android host 검증으로 일반화할 수 없다. 이 조사는 `-accel-check`나 Emulator 실행을 수행하지 않았다. [Hardware acceleration](https://developer.android.com/studio/run/emulator-acceleration).

새 Android CLI의 문서에는 다음 경로가 있다.

| 기능 | 공식 경로 | 확인한 범위 |
| --- | --- | --- |
| SDK 관리 | `android sdk [install\|list\|update\|remove]` | `--sdk`로 SDK 경로를 지정한다. `--platform=mac_arm64` 등 host 대상을 지정한다. `/` 패키지 문법과 기존 `;` 문법을 지원한다. [android sdk](https://developer.android.com/tools/agents/android-cli/commands/sdk). |
| AVD 생성 | `android emulator create [<profile>]`, `--list-profiles` | 문서의 생성 인수는 profile이다. 생략 시 `medium_phone`을 만든다. 이 페이지에는 임의 API·ABI·이름·경로 고정 옵션이 명시되지 않는다. [create](https://developer.android.com/tools/agents/android-cli/commands/emulator_create). |
| 목록·부팅·중지·삭제 | `android emulator list`, `start <device>`, `stop`, `remove` | `start`는 부팅 완료까지 기다린다. `--cold`, `--headless`가 있다. 삭제와 중지는 별도 명령이다. [android emulator](https://developer.android.com/tools/agents/android-cli/commands/emulator), [start](https://developer.android.com/tools/agents/android-cli/commands/emulator_start). |

새 CLI는 사용량 데이터를 수집한다. 공식 문서는 `--no-metrics`를 제공한다. CLI 도입 시 검토할 사실이며 이 조사에서는 설치하지 않았다. [Android CLI overview](https://developer.android.com/tools/agents/android-cli).

## 로컬 관측과 unknown

1. 로컬 Xcode help의 조합은 `27.0 / 27A266a`다. 다운로드·설치·기기 생성 성공은 검증하지 않았다. 임의의 Xcode 27.x에 같은 동작을 약속하지 않는다.
2. 로컬 Android Command-Line Tools의 `source.properties`는 `21.0`이었다. `sdkmanager --help`와 `avdmanager --help`는 현재 셸에서 `Unable to locate a Java Runtime`으로 실패했다. PATH에 명령이 존재하는 사실만으로 실행 환경 준비를 판정할 수 없다. Java 설정을 변경하지 않았다.
3. 로컬 `emulator -version`은 `37.1.11.0 / build_id 15917651`을 출력했다. `command -v android`는 경로를 반환하지 않았다. 새 Android CLI의 실제 출력·버전·자동 다운로드·라이선스 처리·재시도는 unknown이다.
4. 공식 생성 문서만으로는 새 Android CLI의 정확한 API·ABI·패키지 revision 고정, 기존 AVD 이름 충돌, 부분 생성 실패 후 복구 계약을 확정할 수 없다. 설치 없이 읽은 근거의 한계다.
5. iOS runtime 다운로드의 계정·라이선스·관리자 권한 요구는 모든 배포 경로에 대해 이 조사에서 확정하지 않았다. 중단 후 재개·캐시 재사용·원자적 rollback 및 패키지 제거의 다른 프로젝트 영향도 unknown이다.

향후 검증에는 요청한 기기 조건, 선택한 실제 identity, 설치 전후 자원 목록, exit status, 실패 출력이 필요하다. 부팅 완료와 앱 첫 화면 증거는 별도로 수집해야 한다. 이는 조사에서 드러난 검증 대상이다. 승인 단위·fallback·공유·보존·정리 정책은 결정 티켓에 남긴다.

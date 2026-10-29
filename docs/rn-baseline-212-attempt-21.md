# RN baseline attempt-21 — ADR-0046 직접 실행

상태: **두 표본의 Android 첫 화면과 iOS 빌드는 확인했다. iOS 첫 화면과 fresh 준비는 미완료다. #212 완료가 아니다.**
실행일은 2026-10-22다. [ADR-0046](./adr/0046-rn-baseline-direct-execution.md)를 적용했다. Runstir를 사용하지 않았다.

## 경로와 host tuple

검증 루트는 내장 Data volume의 `<LOCAL_VALIDATION_ROOT>/attempt-21`이다(ADR-0024). 실제 경로는 로컬 원본 증거에 보존한다.

| 항목 | 관측값 |
| --- | --- |
| macOS | `27.0.1 (26A434)` |
| Xcode | **`27.1 (27A9275)`**. 이전 attempt의 `27.0 (27A266a)`는 더 이상 설치돼 있지 않다. 차이로 기록한다. |
| iOS Simulator runtime | `26.0 (23A343)`. attempt-02의 로컬 export를 `xcodebuild -importPlatform`으로 다시 등록했다. 다운로드는 없다. |
| Android 기기 | 기존 AVD `Pixel_10_API_37_Play`, fingerprint `google/sdk_gphone64_arm64/emu64a:17/CE2A.260420.019/15611780:user/release-keys` |
| 최소 RN 도구 | Node `22.23.2`·npm `10.9.8`, Ruby `3.4.11`, Bundler `2.5.22`(clone 전용 GEM_HOME), Zulu JDK `17.0.19` |
| Mattermost 도구 | Node `24.15.0`·npm `11.12.1`, Ruby `3.2.11`, Bundler `2.5.11`, Temurin JDK `17.0.20.1+1`(mise `java@temurin-17.0.20+101` 나란히 설치) |
| Watchman | `2026.10.12.00`. 끄지 않았다. |

## source와 lock

| 표본 | source | tracked | lock SHA-256 |
| --- | --- | --- | --- |
| 최소 RN | `b62e3a4d5e7cfc05d7d948a5a4e30f0cc6a82bb4` (source bundle) | 55 | package-lock `3478830f…`, Gemfile.lock `3679d603…`, Podfile.lock `cec099ee…` — 기록과 같다 |
| Mattermost | `c2fe3beda22befd2178dce431793c09111ed903e` (공식 origin) | 4,216 파일 + submodule 1 | package-lock `c0ff8ca8…`, Gemfile.lock `aacdfd20…`, Podfile.lock `64d1d502…` — attempt-03 manifest와 같다 |

실행 뒤 최소 RN의 tracked 변경은 0이다. Mattermost의 tracked 변경은 ADR-0020이 허용한 `ios/Podfile.lock`의 `hermes-engine` checksum 한 줄뿐이다(`28814c9c…` → 이 clone 경로의 실제 값 `a2eb4d4478c5e8c7e2d75f25021407f0b9bf903b`).

## 단계별 결과

| 단계 | 최소 RN | Mattermost |
| --- | --- | --- |
| npm 준비 | `npm ci` exit 0 | 원본 `prepare-node-deps` 6단계, postinstall sounds 복사, `jetify` 모두 exit 0 |
| 원본 Metro 선확인 | `packager-status:running`, 4초, Watchman 오류 없음 | `packager-status:running`, 4초, Watchman 오류 없음 |
| frozen Bundle | exit 0 | exit 0 |
| frozen Pods | `pod install --deployment` exit 0, 86 pods, 2,168초(Maven 다운로드 지연) | 원본 exit 1(Hermes checksum 한 값) → ADR-0020 적용 뒤 exit 0, 160 pods |
| 생성 Pods 준비 | 없음 | ADR-0021·0023의 Debug 12개 값. 원래 값이 ADR 표와 모두 같았고 바뀐 줄은 12줄이다 |
| Android build | `assembleDebug` 2분 14초 성공 | `assembleDebug -PreactNativeArchitectures=arm64-v8a` 9분 29초 성공, ABI `arm64-v8a`만 |
| Android 첫 화면 | Welcome to React Native, RN `0.87.1`, Hermes `250829098.0.17`, `MainActivity` resumed | Connect to your server 폼, App Version `2.44.0 (Build 814)`, `MainActivity` resumed. 알림 권한은 Don't allow |
| iOS build | `xcodebuild` Debug, iOS 26.0 Simulator, BUILD SUCCEEDED(69초) | BUILD SUCCEEDED(11분 38초) |
| iOS install·launch·첫 화면 | install exit 0. launch가 응답하지 않아 **미확인** | **미실행** |
| fresh clone | 고정 SHA clone과 lock hash 확인. 준비는 미실행 | 고정 SHA clone과 lock hash 확인. 준비는 미실행 |

Android 첫 화면: [최소 RN](./evidence/212/attempt-21/minimal-android-first.png), [Mattermost](./evidence/212/attempt-21/mattermost-android-first.png).

| 산출물 | SHA-256 |
| --- | --- |
| 최소 RN APK | `c705ea2fae95cd4669813baff468249017caf5bb9a268f1041c053967591d794` |
| Mattermost APK (128,477,047 bytes) | `f3ada9ed82781da9db8a5573fe447c1c129396f23042a7a9abd6e6770b6799b1` |
| 최소 RN iOS 실행 파일 | `4ebe81608fea3465261d2e741adb56909d20e8e24c2436f5bccfc7543a404c1f` |
| Mattermost iOS 실행 파일 | `f7a03a00f52b3239a8d416a87b8410f0f1a12baf47c47730b31725adebb39600` |
| 최소 RN Android 첫 화면 PNG | `298c8ba512e368228b6f043c523956246cf0839e0889edbd7794f05048919f82` |
| Mattermost Android 첫 화면 PNG | `2c0880961fa12dcead52e3a4d54317c00cca1664ff7ddbd9e160b57787ad4a78` |

최소 RN Android의 첫 캡처는 JS bundle 98% 진행 화면과 시스템 Pixel Launcher의 ANR 대화상자였다. bundle 완료를 기다리고 대화상자에서 Wait를 고른 뒤 다시 캡처했다. 앱 실패로 분류하지 않는다.

## iOS 첫 화면이 미확인인 이유

최소 RN은 전용 iOS 26.0 Simulator에 설치됐고 홈 화면에 앱 아이콘이 보였다. `simctl launch`는 6분 동안 반환하지 않았다. Simulator 재부팅 뒤 다시 실행한 launch도 180초 timeout이었다. 같은 Simulator에서 내장 설정 앱 launch도 반환하지 않았다. Simulator 로그에는 앱 launch 시도가 기록되지 않았다.

같은 시각 host는 swap `59.9 / 62.5 GiB` 사용, 여유 page 약 87MB, load average 약 580이었다. 메모리는 주로 다른 작업의 node 598개·npm 298개 process가 사용했다. 전용 Simulator의 `launchd_sim`은 페이징 대기(U) 상태였다. 이 상태를 앱이나 RN 실패로 분류하지 않는다. launch 미확인이며, 성공도 실패도 아니다.

이 attempt가 만든 Metro는 종료했다. emulator는 `adb emu kill`로 정상 종료했다. 전용 Simulator의 shutdown은 같은 host 상태에서 timeout됐다.

## 실행 중 오류와 정정

- 최소 RN의 첫 frozen Bundle·Pods 호출은 하네스가 바깥 PATH를 넘겨 전역 Ruby `4.0.7`로 실행됐다. 원본 실패가 아니다. 그 산출물(`vendor/bundle/ruby/4.0.0`)을 지우고 Ruby `3.4.11`로 다시 실행했다. 원 로그는 `harness-error-ruby40-*`로 보존한다.
- 첫 Pods 재시도는 실행 환경에 `LANG`이 없어 CocoaPods가 UTF-8 오류로 멈췄다. `LANG=en_US.UTF-8`만 지정해 다시 실행했다.
- Mattermost Bundler를 clone 전용 GEM_HOME에 설치한 시도는 load-relative Ruby 3.2.11의 bin wrapper가 실패했다. attempt-03 기록의 명령(Ruby 3.2.11 기본 gem의 Bundler 2.5.11)으로 다시 실행했다.
- zsh 변수 분리 문제로 첫 adb 호출이 실행되지 않았다. 함수로 바꿔 다시 실행했다.

## 남은 일

1. host 메모리가 회복된 뒤 두 표본의 iOS install·launch·첫 화면. 빌드 산출물과 Mattermost 준비 입력은 로컬 루트에 남아 있다.
2. 두 표본의 iOS 첫 화면 뒤 각 fresh clone을 원본 명령으로 독립 준비하고 결과를 기록한다(ADR-0046).
3. #199 AC05·AC06 연결 갱신.

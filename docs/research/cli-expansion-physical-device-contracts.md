# 연결 실기기의 준비와 앱 실행 계약 조사

- 조사일: 2026-10-09
- 질문: [조사: 연결 실기기의 준비와 앱 실행 계약](https://github.com/minjunkim-dev/mobile-runtime/issues/185)
- Runstir 기준: `1a4ff6dc3815ab6c25df81eaef8ca37acaefe21e`
- 범위: macOS Apple Silicon, Xcode 27.0 이상, 연결된 iOS/Android 실기기.
- 결과 수준: 공식 문서·공식 소스·로컬 CLI help의 기능 확인. 실기기 성공 검증이 아니다.

## 핵심 사실

연결된 실기기도 앱 실행 대상이 될 수 있다. 연결 여부만으로 실행 준비를 판정할 수는 없다. iOS는 개발용 서명과 기기 승인이 추가로 필요하다. Android는 debugging 승인과 설치 가능한 APK가 필요하다. Flutter와 React Native에도 이 네이티브 조건이 적용된다. [Apple 실행·서명](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices?language=objc), [Android debug APK](https://developer.android.com/build/building-cmdline), [Flutter iOS 준비](https://docs.flutter.dev/platform-integration/ios/setup), [React Native 실기기 실행](https://reactnative.dev/docs/running-on-device)

## 발견·식별·준비 상태

| 대상 | 발견과 식별의 공식 경로 | 연결 이후에도 필요한 확인 |
|---|---|---|
| iOS 실기기 | `devicectl list devices --json-output <path>`가 CoreDevice가 아는 기기를 열거한다. Xcode 27 help의 표시 Identifier는 UDID, ECID, CoreDevice identifier 순서로 대체된다. JSON의 `identifier`는 CoreDevice identifier다. `--device`는 UDID·UUID·ECID·serial·name·DNS name을 받는다. [로컬 help](#로컬-cli-help-확인) | 페어링·Trust·잠금 해제·Developer Mode와 서명 조건은 별개다. Developer Mode 활성화에는 기기 재시작과 사람의 확인이 필요하다. [Apple Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device?language=objc), [Flutter Trust](https://docs.flutter.dev/platform-integration/ios/setup) |
| Android 실기기 | `adb devices -l`이 현재 transport의 serial·상태·설명을 제공한다. `adb -s <serial>`이 대상 transport를 지정한다. 여러 대상에서 미지정 명령은 오류다. [ADB](https://developer.android.com/tools/adb) | USB debugging을 켜야 한다. RSA 승인에는 기기 잠금 해제와 사람의 확인이 필요하다. `offline`은 미응답 상태다. `device`도 OS 부팅 완료를 보장하지 않는다. [ADB](https://developer.android.com/tools/adb) |
| Flutter 실기기 | `flutter devices`가 연결 대상을 열거한다. 공통 CLI에는 `run`, `install`, `attach`가 있다. [Flutter CLI](https://docs.flutter.dev/reference/flutter-cli) | Android 실기기와 Emulator를 별도 준비한다. iOS 실기기는 Trust·Developer Mode·certificate 준비가 필요하다. [Flutter Android](https://docs.flutter.dev/platform-integration/android/setup), [Flutter iOS](https://docs.flutter.dev/platform-integration/ios/setup) |

이름과 identity는 같은 개념이 아니다. iOS help는 이름과 여러 identifier 종류를 구별한다. Android `-l`의 model 설명도 serial 선택을 대체하지 않는다. 따라서 같은 이름의 기기를 구별할 정보는 존재한다. 이름 충돌 처리와 재연결 이후 identity 보존은 Runstir가 별도로 결정·검증해야 한다. 특히 ADB Wi-Fi 주소/port와 USB serial을 영구 동일 identity로 간주할 근거는 이번 조사에서 확보하지 않았다. [devicectl help](#로컬-cli-help-확인), [ADB 대상 선택·Wi-Fi 연결](https://developer.android.com/tools/adb)

`devicectl`은 "현재 연결된 기기만"이 아니라 CoreDevice가 아는 기기를 다룬다. 발견 목록과 현재 실행 가능 목록을 동일하게 취급할 근거는 없다. Xcode 27 help의 filter 예시는 `State = 'available'`이다. JSON readiness 필드의 완전한 판정식과 연결 해제 시점의 갱신 지연은 unknown이다. 실제 목록을 조회하지 않았다. [devicectl list help](#로컬-cli-help-확인)

## Build → install → launch → stop

다음은 도구 계약 예시다. 이 조사에서 실행하지 않았다. 경로·scheme·bundle ID·activity·variant는 프로젝트에서 확인해야 한다.

| 대상 | 공식 경로와 추가 조건 |
|---|---|
| 네이티브 iOS | `xcodebuild`는 `-project`/`-workspace`, `-scheme`, `-sdk`, `-destination`을 받는다. 실기기 destination으로 빌드한 개발용 `.app`을 `xcrun devicectl device install app --device <id> <app-path>`로 설치한다. `device process launch --device <id> <bundle-id>`로 실행한다. `device process terminate --device <id> --pid <pid>`로 종료한다. [로컬 help](#로컬-cli-help-확인) |
| 네이티브 Android | 프로젝트의 `./gradlew assembleDebug` 또는 variant별 task가 debug APK를 만든다. debug key 서명은 build가 처리한다. `adb -s <serial> install <apk>`로 설치한다. `adb -s <serial> shell am start -W -n <package/activity>`로 activity를 시작한다. `adb -s <serial> shell am force-stop <package>`로 package를 멈춘다. AAB는 직접 설치할 수 없다. [Android build](https://developer.android.com/build/building-cmdline), [ADB activity manager](https://developer.android.com/tools/adb) |
| Flutter iOS/Android | `flutter run`과 기기 지정 기능을 사용한다. iOS CoreDevice의 공식 구현은 devicectl 설치·실행과 LLDB/Xcode debugger 경로를 구별한다. debugger 없이 실행하는 경로를 debug hot reload와 동등하게 취급할 수 없다. [Flutter CLI](https://docs.flutter.dev/reference/flutter-cli), [고정 Flutter 소스](https://github.com/flutter/flutter/blob/abaf9c523780a608bd46686fd5e53740a07077f8/packages/flutter_tools/lib/src/ios/core_devices.dart) |
| React Native iOS/Android | 네이티브 build/install/launch 조건에 Metro 연결을 더한다. 공식 실기기 안내는 Android 실행에 프로젝트 `npm run android`를 사용한다. iOS는 Xcode의 대상·서명 설정을 사용한다. 구체적인 CLI flag는 프로젝트가 쓰는 CLI 버전에 따라 따로 확인해야 한다. [React Native 실기기](https://reactnative.dev/docs/running-on-device) |

### iOS 실기기와 Simulator 산출물

iOS device와 iOS Simulator는 서로 다른 build destination이다. Apple은 XCFramework를 만들 때 device와 Simulator archive를 따로 만든다. 같은 `arm64`라는 이유만으로 Simulator 산출물을 실기기에 설치할 수 있다고 판단하면 안 된다. 이는 destination과 플랫폼을 구별해야 한다는 근거이며, 이번 조사에서 앱 바이너리 설치 호환성을 실험한 결과는 아니다. [Apple multiplatform framework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle)

실기기 실행에는 Apple Account, 개발 team, bundle identifier, development provisioning profile이 필요하다. 자동 서명은 기기 등록과 profile 생성을 처리할 수 있다. `xcodebuild -allowProvisioningUpdates`는 portal에 접근하여 profiles·app IDs·certificates를 생성·수정할 수 있다. `-allowProvisioningDeviceRegistration`은 destination 기기를 portal에 등록할 수 있다. 이 두 flag는 단순 검사가 아니다. [Apple 서명](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices?language=objc), [xcodebuild help](#로컬-cli-help-확인)

## 개발 연결과 종료 자원

| 자원 | 확인한 사실 | 후속 결정·검증 경계 |
|---|---|---|
| React Native Metro | Android는 `adb -s <serial> reverse tcp:8081 tcp:8081`로 연결할 수 있다. iOS는 Mac과 기기의 네트워크 통신이 필요하다. 같은 Wi-Fi여도 peer 차단 때문에 실패할 수 있다. [React Native](https://reactnative.dev/docs/running-on-device) | 연결된 기기라는 이유만으로 Metro 도달 가능성을 보장할 수 없다. 포트·네트워크 정책과 성공 판정은 후속 결정이다. |
| Flutter debug session | Hot reload는 debug mode의 Flutter 실행 세션을 사용한다. 공식 CoreDevice 구현은 debugger 부착 실패 시 실행한 프로세스를 종료한다. shutdown hook도 해당 process를 정리한다. [Flutter hot reload](https://docs.flutter.dev/tools/hot-reload), [고정 CoreDevice 소스](https://github.com/flutter/flutter/blob/abaf9c523780a608bd46686fd5e53740a07077f8/packages/flutter_tools/lib/src/ios/core_devices.dart) | native app launch 성공만으로 VM service 연결·hot reload 성공을 선언할 수 없다. Flutter SDK·device OS·Xcode 조합의 실기기 검증이 필요하다. |
| ADB transport/server와 reverse mapping | ADB server는 여러 client가 공유한다. help는 대상별 `reverse --list`, `reverse --no-rebind`, `reverse --remove <remote>`와 전체 제거를 구분한다. [ADB](https://developer.android.com/tools/adb), [공식 adb man page](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/user/adb.1.md) | 명령이 제공하는 전체 제거와 Runstir가 소유한 자원만 정리하는 정책은 다르다. 기존 mapping·server 소유권은 Runstir가 기록·판정해야 한다. |
| iOS 실행 process와 console | Xcode 27 devicectl은 PID 종료를 제공한다. `launch --console`은 종료까지 기다린다. catchable signal을 app에 전달한다. `--terminate-existing`은 기존 instance를 종료할 수 있다. [로컬 help](#로컬-cli-help-확인) | 기존 앱 instance와 새 세션의 process를 구별해야 한다. 연결 해제로 종료 명령을 전달하지 못하면 실제 앱 종료는 unknown이다. |

## 사람 입력과 실패 경계

1. **iOS Trust·Developer Mode:** 기기 UI에서 승인한다. Developer Mode는 재시작 후 다시 확인한다. 개발 인증서 신뢰와 codesign Keychain 접근 요청도 나타날 수 있다. 이 조사는 승인하지 않았다. [Apple Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device?language=objc), [Flutter iOS](https://docs.flutter.dev/platform-integration/ios/setup)
2. **iOS 서명:** 계정·team·bundle ID·profile이 맞아야 한다. portal 변경을 허용하는지와 프로젝트 서명 설정 변경을 허용하는지는 별도 제품 결정이다. [Apple 서명](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices?language=objc), [xcodebuild help](#로컬-cli-help-확인)
3. **Android 승인:** 개발 설정과 RSA dialog를 사람이 처리한다. `unauthorized`에 연결 명령을 보내는 것만으로 RSA 승인을 대체할 수 없다. React Native 페이지의 단일 기기 안내를 ADB 다중 기기 한계로 일반화하지 않는다. ADB 공식 문서는 `-s` 다중 선택을 제공한다. [ADB 승인·선택](https://developer.android.com/tools/adb), [React Native 안내](https://reactnative.dev/docs/running-on-device)
4. **설치·실행 실패:** 발견·build·install·launch·개발 서버 연결은 각각 별도의 결과다. Android는 `device` 상태도 완전 부팅을 보장하지 않는다. iOS devicectl help의 command 지원도 서명·잠금·기기 호환 성공을 보장하지 않는다. [ADB 상태](https://developer.android.com/tools/adb), [로컬 help](#로컬-cli-help-확인)

## 로컬 CLI help 확인

2026-10-09 호스트에서 다음 **읽기 전용 명령만** 실행했다. 기기 inventory를 실행하지 않았다. 계정·credential·서명 저장소를 조회하지 않았다.

```text
xcodebuild -version
xcodebuild -help
xcrun devicectl help
xcrun devicectl help list devices
xcrun devicectl help device install app
xcrun devicectl help device process
xcrun devicectl help device process launch
xcrun devicectl help device process terminate
adb --help
```

- Xcode: `27.0`, build `27A266a`.
- ADB: `1.0.41`, Platform Tools `37.0.1-15733141`, Darwin arm64.
- devicectl help는 JSON을 versioned automation 인터페이스로 설명한다. 표준 출력은 안정성을 보장하지 않는다. Xcode 27 list help는 legacy JSON keys의 deprecated 상태를 설명한다. 정확한 필드 계약은 사용할 Xcode 버전별로 고정·검증해야 한다.
- 위 help를 통한 기능 확인에는 실제 연결·기기 준비·앱 실행 증거가 없다.

## 미확인 사항

- Xcode 27.0과 각 Flutter/React Native 버전, 실제 iOS/Android OS의 실행 성공 조합은 unknown이다. 이번 조사는 지원 matrix를 정하지 않는다.
- 잠김·미신뢰·준비 중·연결 해제 상태의 Xcode 27 JSON 샘플과 완전한 readiness 판정식은 unknown이다.
- 같은 이름·동일 기기의 USB/Wi-Fi 동시 노출·재연결의 중복 제거와 identity 지속성은 실험하지 않았다.
- 서명 불일치, entitlement, 앱 덮어쓰기·데이터 보존, OS 제한에 따른 구체적 install 오류는 실험하지 않았다. 자동 uninstall/reinstall 정책을 정하지 않는다.
- 실기기 앱 화면·Metro 연결·Flutter VM service·hot reload·종료 결과는 검증하지 않았다. Developer Mode·신뢰·서명·네트워크·기기 설정을 변경하지 않았다.

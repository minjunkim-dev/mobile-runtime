# Runstir 환경 준비

프로젝트 폴더에서 두 플랫폼을 따로 검사한다.

```bash
mobile doctor
mobile doctor --platform android
```

프로젝트 밖에서는 host 검사만 실행한다. host 검사 통과는 프로젝트 준비 완료가 아니다.
`error`가 있으면 복구 안내를 따른다. `unknown`은 근거를 확보하지 못한 상태다.
`warning`은 권고나 선언 불일치다. doctor의 통과만으로 앱의 초기 UI 도달을 보증하지 않는다.
준비를 마친 뒤 `mobile build`와 `mobile up`을 실행한다.

## 공통 준비

프로젝트 선언에 맞는 Node와 package manager를 준비한다. iOS는 프로젝트가 선언한 Ruby와
CocoaPods도 준비한다. Android는 Gradle과 AGP가 요구하는 JDK를 준비한다. 기존 도구 관리자
설정이 있으면 그 설정을 사용한다. 검사 결과의 실제 요구 버전과 복구 명령을 따른다.
Homebrew로 Runstir를 설치해도 프로젝트마다 다른 Node·Ruby·JDK 버전을 일괄 설치하지 않는다.

`host.workspace-access`는 작업 디렉터리, 프로젝트·워크스페이스 루트, 임시 로그 경로,
프로젝트 실행 환경에서 `npm config get cache`로 관측한 npm cache 경로와 Android Gradle cache
경로의 읽기·쓰기·검색 권한을 확인한다. npm cache를 관측하지 못하면 unknown으로 보고한다.
없어진 cache는 생성하지 않는다. 가장 가까운 기존 부모 디렉터리를 확인한다.
실제 쓰기나 모든 도구의 사용자 정의 cache 접근까지 보증하는 검사는 아니다.

접근을 거부한 경로를 확인한다. 사용자가 읽고 쓸 수 있는 경로를 사용한다.
macOS가 폴더 접근을 거부했다면 **시스템 설정 → 개인정보 보호 및 보안 → 파일 및 폴더**에서
Runstir를 실행한 Terminal 또는 개발 도구의 해당 폴더 접근을 허용한다.
전체 디스크 접근, 손쉬운 사용, 화면 기록 권한을 일괄 요구하지 않는다.
[Apple 폴더 접근 안내](https://support.apple.com/guide/mac-help/mchld5a35146/mac)를 따른다.

`host.storage`는 작업·cache 경로 중 여유 공간이 가장 적은 위치를 보고한다.
10 GiB 미만이면 준비 권고를 warning으로 제공한다. 10 GiB는 특정 프로젝트의 빌드 요구량이나
성공 보증이 아니다. 공간을 직접 확보한다. Runstir는 파일을 자동 삭제하지 않는다.

## iOS 준비

1. 전체 Xcode를 설치한다. 검사 결과가 선택한 Xcode 경로를 확인한다.
2. `xcode.ready`가 실패하면 안내한 Xcode를 연다. 라이선스를 검토하고 초기 설정을 마친다.
3. Xcode에서 필요한 iOS Simulator runtime을 설치한다. 사용할 Simulator를 준비한다.
4. `mobile doctor`를 다시 실행한다.

Runstir는 `xcodebuild -checkFirstLaunchStatus`만 실행한다.
`-runFirstLaunch`, 라이선스 자동 승인, Xcode 설치는 실행하지 않는다.
Xcode 선택 오류와 Simulator runtime 누락에는 기존 검사에서 복구 안내를 제공한다.

## Android 준비

1. 검사 결과에 나온 SDK root와 정확한 SDK Platform·Build Tools·NDK·CMake를 준비한다.
2. `android.sdk`의 라이선스 오류가 있으면 Android Studio의 SDK Manager에서 라이선스를 검토한다.
   설치된 `sdkmanager`를 확인한 경우에는 선택한 SDK root를 고정한 `--licenses` 명령도 제공한다.
3. 선택한 AVD와 system image를 준비한다. `android.avd`는 선택한 image의 라이선스 기록도 확인한다.
4. `mobile doctor --platform android`를 다시 실행한다.

라이선스 검사는 선택한 package의 `package.xml`과 SDK `licenses/` 기록을 읽는다.
Android repository 구현과 같은 라이선스 내용 SHA-1을 대조한다. 파일 존재만으로 통과시키지 않는다.
metadata나 기록을 읽을 수 없으면 unknown으로 보고한다. 이름만으로 승인 상태를 추측하지 않는다.
이 검사는 설치된 선택 package에 한정한다. 향후 내려받을 package의 라이선스 상태는 판단하지 않는다.
Runstir는 SDK Manager를 실행해 동의하거나 SDK package·AVD를 자동 설치하지 않는다.

근거: [Android SDK Manager](https://developer.android.com/tools/sdkmanager#accept-licenses),
[Android repository License.checkAccepted](https://android.googlesource.com/platform/tools/base/+/gradle_2.2.2/repository/src/main/java/com/android/repository/api/License.java).

## 프로젝트 의존성과 시스템 도구

`build`와 `up`은 준비한 도구로 node_modules·Bundle gems·Pods를 lockfile에 맞춘다.
누락된 시스템 도구, 설정의 trust, macOS 권한, 앱 환경값은 사람이 준비한다.
시스템 도구 설치와 권한 승인은 doctor의 복구 안내를 확인한 뒤 직접 수행한다.

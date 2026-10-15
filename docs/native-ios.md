# native iOS 프로젝트 실행

앱 루트의 `.xcodeproj` 또는 `.xcworkspace`를 선택한다.
컨테이너가 여러 개면 doctor가 보고한 `--app` id를 사용한다.
공유 app scheme을 준비한다.
scheme이 여러 개면 `--scheme` 또는 앱 루트의 `mobile.yml`로 선택한다.
Debug가 없으면 실제 configuration을 `--configuration`으로 선택한다.

```sh
mobile doctor --project /path/to/app --app App.xcworkspace --json
mobile build --project /path/to/app --app App.xcworkspace --scheme App --json
mobile up --project /path/to/app --app App.xcworkspace --scheme App --device SIMULATOR_UDID --json
mobile down --project /path/to/app --app App.xcworkspace --json
```

1. Xcode 27.0 이상과 호환 iOS Simulator runtime을 준비한다.
2. 프로젝트의 기존 절차로 잠금 SPM 의존성을 준비한다.
3. CocoaPods를 사용하면 프로젝트의 기존 명령으로 의존성을 준비한다.
4. `Podfile.lock`과 `Pods/Manifest.lock`이 일치하는 workspace를 선택한다.
5. doctor 결과와 필요한 선택을 확인한다.
6. build로 Simulator artifact를 만든다.
7. up으로 선택한 Simulator에 설치하고 실행한다.
8. down으로 이 프로젝트가 기록한 앱을 종료한다.

build는 설치하거나 실행하지 않는다.
`setup --plan`은 선택한 native iOS 컨테이너의 준비 조건을 표시한다.
setup은 native iOS 의존성을 설치하지 않는다.
native iOS는 Node와 Metro를 사용하지 않는다.
build와 up은 SPM 의존성을 자동 갱신하지 않는다.
프로젝트가 요구하는 의존성이 준비되지 않으면 Xcode 오류와 build 로그를 확인한다.
Runstir는 native iOS 프로젝트 설정과 서명을 자동 변경하지 않는다.
Simulator build는 서명을 비활성화한다.
실기기 실행과 signing/provisioning 자동 준비는 이 흐름의 범위에 없다.
down은 앱을 삭제하거나 Simulator를 종료하지 않는다.
확인할 수 없는 doctor 결과는 `unknown`으로 남는다.

CLI와 GUI는 같은 EnvironmentKit 계약을 호출한다.
공유 경계의 fixture 검증과 실제 GUI 조작은 별도 증거다.

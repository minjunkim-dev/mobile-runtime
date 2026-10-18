# ADR-0042: 작업 폴더별 개발 연결은 같은 선택 포트 입력을 사용한다

- 상태: 채택
- 날짜: 2026-10-19
- 관련: #188, #199 AC07·AC09, #216, #217, ADR-0007·0013

## 결정

`FolderIdentity`의 volume·inode가 GUI 창 identity다. 일반 폴더도 허용한다.
같은 실제 폴더의 symlink는 기존 창을 사용한다. 같은 Git 저장소의 worktree도
실제 폴더가 다르면 별도 창이다. 창별 선택·진행·결과는 기존 View state에 둔다.
공통 작업 폴더 lease가 변경 작업을 직렬화한다. GUI 전체 잠금을 추가하지 않는다.

기존 `WorkflowInput.port` 입력 이름을 CLI와 GUI가 공유한다.
React Native build/up은 명시적 1~65535 포트를 소비한다. 생략한 기본값은 8081이다.
사용 중인 포트를 임의로 바꾸거나 기존 작업을 종료하지 않는다.
선택 포트의 lease와 현재 Metro root 판정을 모두 통과해야 실행한다.

React Native의 표준 start script에 `--port`를 전달한다. npm은 `--`로 script 인자를 구분한다.
iOS는 `RCT_METRO_PORT` build setting과 `simctl launch`의
`-RCT_jsLocation localhost:<port>` argument를 사용한다. `RCTBundleURLProvider`는
이 key를 `NSUserDefaults`에서 읽는다. `NSArgumentDomain`은 실행 동안만 유지한다.
React-Core prebuilt에서는 build setting만으로 포트 변경을 입증할 수 없으므로
launch argument 경로를 함께 확인한다. 지속 앱 preference는 쓰지 않는다.

Android는 `-PreactNativeDevServerPort=<port>`를 Gradle assemble에 전달한다.
React Native Gradle plugin은 이 값을 앱의 `react_native_dev_server_port` resource로 만든다.
adb reverse와 launch-ready 확인도 같은 포트를 사용한다.
설치된 native 입력이나 표준 start script의 전달 근거가 없으면 변경 전에 중단한다.

선택 포트는 기존 `RunLogs` 아래 `metro-port-ios`·`metro-port-android`에 원자적으로 저장한다.
한 작업 폴더에서 양플랫폼 앱을 순차 실행해도 다른 플랫폼의 down 입력을 바꾸지 않는다.
Metro 시작 전에 저장 실패를 처리한다. build 실패 뒤에도 `down`은 같은 포트를 찾는다.
정확한 기록 부재만 기존 8081 경로로 처리한다. symlink·형식 오류·읽기 실패는 차단한다.
포트를 바꾸기 전에 이전 포트가 비었는지 확인한다. Android active run이 남았으면
기존 down을 먼저 요구한다. 기록은 endpoint 입력이다. PID·현재 root 판정을 대신하지 않는다.

`InstallRecord`는 install 이후에만 있다. Metro 시작 뒤 build 실패를 표현하지 못한다.
Android active run은 플랫폼 전용이다. device claim은 Metro만 남은 실행을 표현하지 못한다.
따라서 이들에 가짜 앱·기기 상태를 추가하지 않고 기존 로그 저장소에 플랫폼별 port만 저장한다.
새 registry·백그라운드 관리자·전역 설정·프로젝트 파일 변경은 추가하지 않는다.

## 근거와 검증 경계

RN 0.87.1과 0.85.3의 준비된 의존성 원문을 읽었다.
source identity와 파일 hash는 [구현 근거](../project-windows.md)에 기록한다.
Apple의 [argument domain](https://developer.apple.com/documentation/foundation/userdefaults/argumentdomain)
설명과 [Simulator launch arguments](https://developer.apple.com/videos/play/wwdc2019/418/)
설명을 사용한다.

fixture는 선택 포트·명령·공통 충돌·독립 작업 진입·로그와 event 분리를 검증한다.
fixture는 실제 앱 연결과 첫 화면을 입증하지 않는다. #217의 실제 병렬 시연과
#199 후보 전체 조합 검증은 별도 실행 증거가 필요하다. 서명·공증·배포는 마지막 단계로 유지한다.

# React Native 환경 확인

Issue #200은 React Native doctor의 공통 입력과 최소 GUI를 제공한다.
빌드·설치·실행과 첫 1.0.0 출시 게이트는 후속 티켓에서 검증한다.

## 실행

1. `swift build --force-resolved-versions`를 실행한다.
2. `mobile doctor --project <folder> --json --non-interactive`로 후보를 확인한다.
3. 필요하면 `--app <candidate-id> --platform ios|android`로 다시 검사한다.
4. GUI는 `bash scripts/run-gui.sh`로 연다.
5. GUI에서 프로젝트 폴더를 열고 앱과 플랫폼을 선택한다. `환경 확인` 또는 Command-R로 다시 검사한다.

`mobile`은 빌드한 실행 파일 경로 또는 PATH에 설치한 CLI를 뜻한다.
개발용 `.app`은 `.build/Runstir.app`에 생성한다. 서명·공증한 배포용 DMG가 아니다.

## 공통 계약

`ProjectInspectionInput`은 작업 폴더·환경·선택한 앱·플랫폼을 받는다.
`EnvironmentInspection.run`은 두 UI의 공통 진입점이다.
기존 `DoctorEngine`, `ConfigContext`, `ProjectExecutionEnvironment`와 플랫폼 검사를 사용한다.
`WorkflowContext`는 기존 CLI의 build/up/down 검사 구성도 제공한다.

프로세스의 cwd를 바꾸지 않는다. 자식 프로세스는 입력 환경과 작업 위치를 사용한다.
각 명령의 명시적 환경과 작업 위치는 공통 기본값보다 우선한다.
환경값은 JSON으로 내보내지 않는다. 검사 결과에 필요한 도구 관측값만 기존 계약으로 보고한다.

폴더 identity는 symlink를 해석한 절대경로와 volume/file identity를 보존한다.
같은 실제 폴더를 다시 열면 기존 GUI 창을 사용한다.
서로 다른 worktree 폴더는 별도 창을 사용한다.

앱 후보는 기존 React Native anchor와 선언한 workspace member에서 찾는다.
`package.json`의 workspaces 배열/객체와 `pnpm-workspace.yaml`의 packages를 읽는다.
workspace 패턴은 `*`, `**`와 `!` 제외 패턴을 지원한다.
node_modules·Pods·build·네이티브 host 트리는 별도 앱 후보로 등록하지 않는다.
선택한 폴더의 symlink 별칭은 같은 후보 identity로 처리한다.
workspace member를 탐색할 때 symlink 하위 트리는 따라가지 않는다.

후보 ID는 열었던 폴더 기준 상대경로다. 현재 앱은 `.`을 사용한다.
상위 폴더에서 찾은 anchor는 절대경로 ID를 사용한다.
ID는 결과에 제시한 작업 폴더와 함께 사용한다.
앱 루트와 선언/lockfile의 workspace 루트 identity는 별도로 보존한다.

복수 앱은 `--app`을 요구한다. 양쪽 host가 있는 앱은 `--platform`을 요구한다.
host가 하나면 해당 플랫폼을 선택한다.
managed React Native처럼 host가 없으면 명시적 플랫폼으로 기존 doctor의 unknown 검사를 실행한다.
잘못된 앱이나 존재하는 host와 맞지 않는 플랫폼은 선택 실패로 보고한다.
프로젝트 밖 doctor는 가능한 호스트 검사만 실행한다.
검사 단계는 앱 의존성이나 도구를 설치하지 않는다.

doctor는 TTY 여부와 관계없이 부족한 선택을 결과로 반환한다.
자동 iOS 기본값을 사용하던 alpha 호출은 양쪽 host가 있는 앱에 `--platform ios`를 추가한다.
이 티켓은 doctor 입력만 바꾼다. build/up/down의 입력 선택은 #201에서 구현한다.

## JSON과 종료 코드

기존 schemaVersion 1·toolVersion·command·status·checks와 Check 의미를 유지한다.
doctor 결과에 `selection`을 추가한다.
selection은 directory·candidates·selected·platform·requiredInput·error를 제공한다.
선택 부족 시에도 호스트 Check 결과를 보존한다.
Check status는 선택 완료를 뜻하지 않는다. `requiredInput`과 `error`도 확인한다.

선택 부족·선택 실패는 exit 1이다. 도구 장애는 기존 exit 2다.
선택 완료 뒤에는 기존 doctor의 exit 규칙을 사용한다.
warning/unknown만 있는 검사 결과의 exit 0은 앱 실행이나 지원 검증 성공을 뜻하지 않는다.
잘못된 인자나 읽을 수 없는 작업 폴더는 exit 64다.
JSON stdout은 최종 문서 하나다. 후보 안내와 로그는 stderr다.

## AC01·AC04 검증 경계

| 명세 항목 | #200에서 검증한 범위 | 증거 |
| --- | --- | --- |
| AC01 | RN 단일/복수 앱·양쪽 host·잘못된 선택·프로젝트 밖 doctor·실제 폴더 identity | ProjectInspectionTests, EnvironmentInspectionTests |
| AC01 | 실제 CLI help·--project·후보 JSON·비대화식 선택 부족·tracked fixture byte 보존 | scripts/verify-doctor-input.py |
| AC04 | 같은 RN/호스트 fixture 입력의 CLI·GUI 공통 결과와 기존 warning/unknown·JSON 의미 | EnvironmentInspectionTests, 기존 DoctorOutputTests |
| AC04 | 명시적 환경·작업 위치·명령별 override와 Core import 경계 | ExplicitProcessEnvironmentTests, CoreImportDisciplineTests, Linux Core compile |

2026-10-09 개발용 `.app`의 실제 GUI를 실행했다.
두 RN 앱 후보와 앱 선택 후 플랫폼 선택 요구를 화면에서 확인했다.
단일 앱의 iOS 검사 결과와 `node_modules missing` warning을 확인했다.
Command-R 재검사와 후보 Picker의 접근성 이름을 확인했다.
이 실행은 검증용 workspace에서 GUI 자체를 검사한 증거다.
실제 OSS 앱의 known-good baseline·빌드·설치·첫 화면 증거가 아니다.
전체 VoiceOver·서명/공증·Gatekeeper·DMG·여섯 조합 게이트는 후속 검증 티켓에서 확인한다.

개발용 bundle의 Core resource 누락으로 최초 프로젝트 검사 실행이 종료되었다.
`run-gui.sh`에 SwiftPM resource bundle 복사를 추가했다.
수정한 `.app`에서 프로젝트 검사를 다시 실행해 결과 표시를 확인했다.

# React Native build/up/down 입력과 결과

Issue #201은 CLI와 GUI를 `EnvironmentKit.WorkflowExecution`에 연결한다. 같은 입력은 같은 플랫폼 provider와 결과를 사용한다.

## 선택

1. `--project <path>`로 작업 폴더를 지정한다. 생략하면 현재 폴더를 사용한다.
2. 앱 후보가 여러 개이면 `--app <candidate-id>`를 지정한다.
3. 양플랫폼 앱이면 `--platform ios|android`를 지정한다. 기존 alpha의 무조건 iOS 기본값을 제거했다.
4. `up`의 기기 후보가 여러 개이면 `--device <id>`를 지정한다. iOS는 Simulator UDID다. Android는 `avd:<name>`이다.
5. 필요한 build 선택을 지정한다. iOS는 `--scheme`과 `--configuration`이다. Android는 `--module`과 `--variant`다.

앱과 플랫폼 선택은 #200의 `ProjectInspectionInput`을 사용한다. 선택이 부족하면 후보와 `operation.requiredInput`을 반환한다. 의존성 설치와 build는 시작하지 않는다. CLI는 명시적 입력을 사용한다. GUI는 같은 후보를 표시한다. `--non-interactive`는 질문을 금지한다.

명시적 선택은 `mobile.yml`보다 우선한다. 파일은 수정하지 않는다. scheme은 설정 또는 단일 후보를 사용한다. iOS configuration은 실제 존재하는 Debug만 기본값으로 사용한다. Debug가 없으면 명시적 선택을 요구한다. Android module은 설정 또는 단일 application module을 사용한다. Android variant는 기존 ADR-0015의 설정 → debug → 단일 runnable variant 규칙을 사용한다. 잘못된 후보와 다른 플랫폼의 입력은 차단한다.

workspace-only 앱은 `xcodebuild -list`에 configuration 목록이 없다. 이 경우 선택한 scheme의 `-showBuildSettings`에서 요청 configuration과 실제 `CONFIGURATION`이 일치하는지 확인한다. Xcode가 없는 configuration을 Release로 조용히 대체하면 거부한다.

## 실행

```sh
mobile build --project /path/to/app --platform ios --json
mobile up --project /path/to/app --platform ios --device <simulator-udid> --json --progress-json
mobile up --project /path/to/app --platform android --device avd:Pixel --module :app --variant debug --json --progress-json
mobile down --project /path/to/app --platform android --json --progress-json
```

`build`는 설치·launch하지 않는다. iOS build는 기기를 생략하면 generic Simulator destination을 사용한다. Simulator를 부팅하지 않는다. Android build는 APK까지 만든다. 실행 기기를 사용하지 않는다.

`up`은 기존 validate·dependencies·플랫폼 build·install·launch provider를 사용한다. 기기 identity를 실행 전에 확인한다. iOS는 DeviceStage에서 UDID와 runtime을 다시 확인한다. Android는 AVD의 실제 serial·API·ABI를 기존 provider에서 확인한다. 기존 Android 활성 실행과 다른 AVD를 요청하면 기존 활성 실행을 보존하고 down을 안내한다.

`down`은 프로젝트와 플랫폼의 기존 소유권 규칙을 사용한다. iOS는 ADR-0007을 유지한다. Android는 ADR-0013의 소유 자원만 정리한다. down은 build·device 선택을 받지 않는다. 도구가 부족하면 doctor 결과와 `docs/environment-setup.md`의 준비 절차를 안내한다. 실행 경로에서 SDK 설치·라이선스 승인·재서명을 추가하지 않았다.

## 결과와 취소

기존 schemaVersion 1의 명령별 필드를 유지한다. 최종 JSON에 `operation`을 추가한다. operation은 작업 ID·명령·상태·프로젝트 선택·실제 선택·후보·완료 단계·남은 작업·다음 행동을 담는다. 환경 변수는 내보내지 않는다.

`--json` stdout에는 최종 문서 하나만 쓴다. `--progress-json` stderr에는 NDJSON만 쓴다. 이벤트는 schemaVersion·operationId·sequence·kind·stageId·state·detail을 제공한다. 시작·진행·완료·취소를 구분한다. 사람용 note와 verbose 로그를 NDJSON에 섞지 않는다. GUI는 같은 Core 이벤트를 구독한다.

종료 코드는 정상 0, 도메인 실패·선택 부족 1, 인프라 실패 2, 인자 오류 64, 사용자 취소 130이다. CLI SIGINT/SIGTERM과 GUI 작업 취소는 실행 Task에 전달한다. 취소는 설치한 앱을 삭제하거나 프로젝트 변경을 되돌리지 않는다. 완료 단계와 남은 자원을 결과에 남긴다. Android 실패·취소 후 rollback은 기존 소유권 검증을 유지한다.

`up` 성공과 앱 PID는 실행 요청의 결과다. 첫 화면 확인과 출시 후보 게이트의 성공을 뜻하지 않는다. 여섯 조합의 실제 검증·전체 접근성·signed/notarized DMG·공동 공개는 별도 티켓의 조건을 유지한다.

## 검증 경계

AC01: 앱/플랫폼/기기/scheme/module/variant 선택과 잘못된 선택 차단을 fixture와 실제 CLI/GUI로 확인한다.

AC04: 기존 envelope·명령별 결과, JSON stdout·NDJSON stderr, 도메인/인프라/인자/취소 종료 코드를 확인한다. `scripts/verify-workflow-input.py`는 실제 바이너리에 SIGINT를 보낸다. 진행 중 Xcode probe가 멈추고 cancelled/130을 반환해야 통과한다.

실제 플랫폼 build/up/down과 화면 증거는 구현 PR에 별도 기록한다. fixture 성공을 실제 앱 실행 성공으로 기록하지 않는다.

### Issue #201 구현 검증

검증 기준은 main `23ceb59873c8610740b21853c302bc48144d1006`이다. 검증 호스트는 macOS 27.0.1 arm64다. Xcode는 27.0 (`27A266a`)이다.

| 경계 | 실행한 검증 | 결과 |
| --- | --- | --- |
| AC01 공통 선택 | `WorkflowExecutionTests`, Android target fixture | 양플랫폼·복수 기기·잘못된 scheme·다른 플랫폼 입력·없는 Debug에서 변경 전에 중단 |
| AC04 명령·스트림 | 실제 `mobile`로 `verify-workflow-input.py`, `verify-doctor-input.py` | help·parser 64·선택 1·JSON/NDJSON 상관 ID·단조 sequence·진행 중 SIGINT 130 통과 |
| 오류·취소·소유권 | Swift 테스트 504개 | 인프라 2, 완료 단계 보존, 취소한 down의 남은 unknown 항목, 다른 AVD 요청 시 기존 active run 보존 통과 |
| 빌드 호환 | Runstir GUI build, pinned Swift 6.3 Linux Core build | 통과 |
| Android CLI | FreeKiosk RN 0.82.0 `:app/debug`, `avd:Pixel_10_API_37_Play` | build/up/down 각각 succeeded/0. `com.freekiosk`, API 37 arm64-v8a, `emulator-5554`. down은 앱·reverse·Metro·소유 Emulator를 정리 |
| Android GUI | 같은 FreeKiosk와 AVD에서 빌드·실행·종료 버튼 | 각각 succeeded/0. 현재 단계와 후보 표시. 첫 화면에서 FreeKiosk `Start Configuration` 확인 |
| GUI 선택·취소 | 플랫폼 미선택, 복수 iOS 기기, 작업 취소 | needs-selection/1, Simulator UDID 후보, cancelled/130 확인 |
| iOS 실패 | FreeKiosk CLI build | 기존 Pod target 13.4가 Xcode 27에서 실패. failed/1·dependencies 완료·실제 build log 경로 반환 |
| iOS GUI | 아래 준비를 적용한 RunstirRN RN 0.82.0, RunstirRN/Debug, iPhone 18 Pro UDID | build/up/down 각각 succeeded/0. launch PID 20976. Hermes의 실제 RN 첫 화면 확인. down은 앱·Metro를 정리하고 두 기존 Simulator를 보존 |
| iOS CLI | 같은 준비 앱·UDID·scheme·configuration으로 재실행 | build/up/down 각각 succeeded/0. launch PID 28470. 실제 RN 첫 화면 확인. down은 앱·Metro를 정리 |
| workspace configuration | 실제 Xcode workspace list/settings와 selector fixture | list에 configuration이 없음 확인. 없는 configuration은 Release로 대체됨 확인. 이 대체를 차단하고 유효한 Debug는 사용 |

Android CLI operation ID는 build `55DDBAB8-AC76-478D-8ED4-2D9B9E4215AB`, up `E3838FE1-E070-4DAB-87CE-E61662193EAF`, down `93EAD44C-55CB-4352-974F-57485276AABA`다. stderr 이벤트 수는 각각 9·19·3이다. 세 실행 모두 최종 operation ID와 이벤트 ID가 일치했다. sequence는 1부터 연속했다. GUI Android launch PID는 4325였다. GUI down 뒤 Emulator와 8081 listener가 남지 않았다.

FreeKiosk 표본 commit은 `0c89e035dccdaf1a1c840a030eca30e10f23783a`다. 검증 전에 declared Gemfile을 로컬 bundle에 설치했다. Hermes는 공식 Maven의 RN 0.82.0 tarball을 React Native의 `HERMES_ENGINE_TARBALL_PATH`로 지정했다. SDK 설치·라이선스 승인·서명 변경은 하지 않았다. CocoaPods는 workspace·lockfile과 기존 Xcode project/Info.plist의 생성 설정을 변경했다. 검증 뒤 이 두 tracked 파일을 원래 commit으로 복원했다. 준비한 로컬 bundle·workspace·lockfile은 보존했다. 이 변경은 Runstir 선택 설정의 자동 생성과 다르다.

[Android GUI 첫 화면](evidence/201/android-gui.png)과 [준비한 iOS GUI 첫 화면](evidence/201/ios-gui.png)을 저장했다. 첫 화면 확인은 이 표본들의 실행 결과다.

[준비한 iOS CLI 첫 화면](evidence/201/ios-cli.png)도 저장했다. iOS CLI operation ID는 build `DCED2E0A-2F68-4F78-BBDC-8848606292C8`, up `5664463A-3F03-4548-ACE6-011D3FA4CDFE`, down `4B8DF585-7954-465B-A98C-C513BC18C27C`다. 이벤트 수는 각각 21·22·3이다. 세 실행 모두 최종 operation ID와 이벤트 ID가 일치했다. sequence는 1부터 연속했다. up은 `8C71F44D-7D37-436D-94D3-3D25DCF3FD30`과 RunstirRN/Debug를 선택했다. down 뒤 두 기존 Simulator와 Smallnext QA 프로세스를 보존했다.

iOS 성공 검증에는 `/tmp/runstir-201-ios-sample/RunstirRN`의 별도 최소 앱을 사용했다. `@react-native-community/cli@20.0.0 init RunstirRN --version 0.82.0 --skip-install`로 생성했다. npm lockfile과 declared Gemfile의 로컬 bundle을 먼저 준비했다. Ruby 3.3.12를 사용했다. 로컬 Hermes debug tarball의 SHA-256은 `f045ff745ede1fbd8df8550d3f8a04f978679d5a9829e19f053e02a715a5477b`다.

이 최소 앱에는 Xcode 27/iOS 27 준비가 필요했다. 생성한 `ios/Pods/fmt/include/fmt/base.h`에서 `FMT_USE_CONSTEVAL`을 0으로 선택하는 기존 runtime 경로를 사용했다. 기본 AppDelegate가 iOS 27에서 `___UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption_block_invoke`로 종료돼 AppDelegate.swift와 Info.plist에 UIScene을 연결했다. 이 준비는 임시 앱에만 적용했다. Runstir는 compiler flag나 앱 lifecycle을 자동 수정하지 않는다. 준비 전에는 CLI up이 launch PID를 받은 뒤 앱이 종료됐다. 이를 첫 화면 통과로 기록하지 않는다. 원본 RN 0.82.0 템플릿이 이 호스트에서 그대로 실행된다는 증거로도 사용하지 않는다.

정확성 리뷰는 공통 입력→provider, 이벤트→최종 문서, 취소→하위 Task/프로세스, active run→down 소유권을 따라 수행했다. 리뷰에서 찾은 취소 전달·AVD 보존·Debug 근거·미완료 down 항목 누락을 수정했다. 수정 후 회귀 검증을 통과했다. 이 검증은 AC05의 여섯 조합·known-good OSS 후보 게이트, VoiceOver, physical device, signed/notarized DMG, 1.0.0 공개를 증명하지 않는다.

# RN baseline #212 attempt-05: 감사 harness 중단

2026-10-10 기록이다. 원본 `pod install`은 exit 0으로 끝났다. 설치 뒤 schema 3 감사 harness가 앱 project의 POSIX 권한 `0644→0600`을 거부했다. full POSIX 권한 동일 조건은 ADR-0020의 tracked raw byte·파일 kind·Git 실행 bit·index 감사보다 넓다. 이 중단은 source 준비 실패, native build 실패 또는 Runstir 실패가 아니다. 중단 상태와 원본 증거를 보존했다. #212는 OPEN이다. known-good과 fresh 인계는 미완료다.

정책 main은 `3853cbbdc08675b7a8a658818a1cccd14004e5f3`이다. 대상은 [Mattermost 원본 source](https://github.com/mattermost/mattermost-mobile/tree/c2fe3beda22befd2178dce431793c09111ed903e) `c2fe3beda22befd2178dce431793c09111ed903e`다. [ADR-0020](https://github.com/minjunkim-dev/mobile-runtime/blob/3853cbbdc08675b7a8a658818a1cccd14004e5f3/docs/adr/0020-rn-baseline-prepared-input.md)의 Hermes 한 값 준비와 [ADR-0021](https://github.com/minjunkim-dev/mobile-runtime/blob/3853cbbdc08675b7a8a658818a1cccd14004e5f3/docs/adr/0021-mattermost-generated-pods-preparation.md)의 generated Pods 준비 조건을 사용한다. ADR-0021의 실제 11개 보정 단계에는 도달하지 않았다.

## 실행 단계

| 단계 | 관측 결과 |
|---|---|
| 새 원본 clone·checkout·initial audit | PASS |
| `npm ci --ignore-scripts`·원본 hook의 분리 실행·각 source audit | PASS |
| `BUNDLE_FROZEN=true` Bundle install·source audit | PASS |
| 원본 `bundle _2.5.11_ exec pod install` | exit 0 |
| 설치 뒤 schema 3 full lstatMode 감사 | exit 1, 앱 project 권한 `0644→0600` |
| `pod install --deployment` | 미실행 |
| generated Pods 11개 Debug `16.4` 보정·실제 적용 감사 | 미실행 |
| iOS·Android native build·install·launch·첫 화면 | 미실행 |
| 새 Android 입력 검증 | 미실행 |
| Mattermost fresh clone·독립 dependency 준비 | clone도 미생성 |
| 최소 RN fresh clone·독립 dependency 준비 | clone도 미생성 |
| 실제 Runstir gate | 미실행 |

14개 command result의 step·시작·종료·exit 값을 원본 manifest와 대조했다. 모두 일치했다. 14개 command는 모두 exit 0이었다. 뒤따른 감사 exit 1은 이 command result 14개에 포함하지 않는다. 실패한 감사는 result JSON을 남기지 않았다. `baseline-after-pod-audit.error-excerpt.txt`는 원본 tool 응답에서 옮긴 발췌다. 새 실행의 stdout이나 성공한 감사 JSON으로 취급하지 않는다.

## source와 lock 감사

원본 facts packet과 root의 독립 live 검증은 tracked blob 4216개를 대조했다. Podfile.lock 외 raw mismatch는 0개다. 파일 kind mismatch와 Git 실행 bit mismatch도 0개다. index hash는 초기 hash와 같다. 숨긴 index flag는 없다. 초기 checkout은 원본 `.gitattributes`의 `*.bat text eol=crlf` 변환과 HEAD 대응을 확인했다.

| 대상 | 설치 전 | 설치 후 | 판정 |
|---|---|---|---|
| `ios/Mattermost.xcodeproj/project.pbxproj` raw SHA-256 | `8ed8c81f2861eec2f92c6a252edd0150ee8c0eb6a082aaf85373bbc3a28dd33f` | 동일 | byte 불변 |
| 같은 파일의 kind·Git mode | regular·`100644` | 동일 | kind·Git 실행 bit 불변 |
| 같은 파일의 POSIX 권한 | `0644` | `0600` | full lstatMode guard가 거부 |
| Git index SHA-256 | `6fe8424fe66b67f5f7ab4c0ca7415b6b1615454bc3e28ec5de3d7a810371dd7a` | 동일 | index 불변 |
| `SPEC CHECKSUMS.hermes-engine` | `28814c9c9296d16aef26cb514de5378d18885e44` | `2a8d399397e7118675812e9aee40f5abf719c862` | ADR-0020의 허용한 한 값 |

Hermes 한 값만 정규화하면 Podfile.lock 전체 byte가 원본과 같다. 원본 lock SHA-256은 `64d1d50255e98c08f7722481629507a568e6f4efbce551344b658fe2d8f3ef1b`다. 준비 lock SHA-256은 `4a5e1dc8e3020c03866aa0ef71fba0e3ad491544a287120adb99e386874e99b5`다. 원본 serialized spec provenance는 unknown이다. 원본과의 차이가 경로뿐이라는 증거는 없다.

원본 xcodeproj 1.27.0의 `Project#save`는 Atomos 0.1.3의 atomic write를 사용한다. Atomos는 `Tempfile.open`과 `File.rename`을 사용한다. 이는 source 관측이다. syscall trace로 실제 writer를 확인하지 않았다. 자동 chmod·복원·source patch로 감사 실패를 감추지 않았다.

## 고정 입력과 미실행 경계

Node `24.15.0`, npm `11.12.1`, Ruby `3.2.11`, Bundler `2.5.11`, CocoaPods `1.16.1`, xcodeproj `1.27.0`, Temurin `17.0.20.1+1`, RN `0.83.9`, Expo `55.0.23`을 관측했다. 원본 properties의 React Native/Expo from-source 선택과 app minimum `16.4`를 유지했다.

Xcode `27.0 (27A266a)`와 SDK `27.0`, 설치한 iOS runtime `26.0 (23A343)`을 입력으로 유지했다. Android 입력은 기존 API `37` Google Play arm64 revision 6과 software/headless 설정이다. 앱 compileSDK `36`과 Android runtime API `37`을 구분한다. 이번 attempt에서 기기를 실행하지 않았다.

생성한 Pods project는 존재한다. helper는 메모리 self-check만 수행했다. 실제 generated project 보정을 적용하지 않았다. frozen deployment 성공, 보정 후 native 성공, Release 성공 또는 Runstir 보정 유지 성공을 주장하지 않는다. baseline과 fresh 사이에 Pods·node_modules·vendor·build 산출물을 복사하지 않았다. 이번 attempt에는 fresh clone이 없다. configured candidate SHA를 실제 fresh checkout HEAD로 기록하지 않는다.

## 진단과 cleanup

preflight가 추측한 adb 경로의 FileNotFoundError는 harness 경로 오류였다. 기존 SDK의 실제 경로를 사용하는 읽기 preflight로 정정했다. `pgrep -fl`은 xcodebuildmcp와 command text를 잘못 포함했다. executable comm 검사에서는 실제 xcodebuild·emulator·qemu가 없었다. 두 진단은 앱 실행 실패가 아니다.

cleanup은 PASS다. 기존 iOS 27 Simulator 두 개는 Booted 상태다. 이번 작업의 iOS 26 Simulator는 Shutdown 상태다. 기존 GUI를 보존했다. Metro `8081` listener, adb device, 실제 mobile build/emulator process는 없다. 이번 작업이 시작한 기기·앱·Metro·build process가 없어서 종료할 소유 자원도 없었다. 전역 PATH·Xcode 선택·SDK·runtime·AVD 데이터를 변경하지 않았다. 실행 lease를 반납했다. attempt-04와 이전 실패 증거도 보존했다.

## 증거와 공개 범위

[공개 manifest](evidence/212/attempt-05/manifest.json)는 원본 raw 파일의 이름·size·SHA-256과 실행 결과를 요약한다. 원본 artifact는 66개다. 구성은 JSON 39개, log 14개, Python 5개, Markdown 3개, lock 2개, diff 2개, text 1개다. JSON 중 command result는 14개다. 66개 artifact의 size·hash를 원본 manifest와 대조했다. 모두 일치했다. SHA256SUMS의 67개 항목도 모두 일치했다. 추가 한 항목은 원본 `manifest.json`이다.

원본 REPORT SHA-256은 `07e15861f466bfcaeef2bf2b8f385fb2c255dabfde0942cc31811e2c27e413c9`다. 원본 manifest SHA-256은 `8b175dd0d0c8fb60e06a654d3521820b5a4ba2b04dd11ce2fd232334a0e9528a`다. 이 hash는 원본 로컬 byte의 identity다. 이 공개 문서나 공개 manifest의 hash가 아니다.

raw 자료는 `<LOCAL_VALIDATION_ROOT>/attempt-05-generated-pods`에 보존한다. raw log·process text·메모리 dump·helper는 공개하지 않는다. 공개 자료에서 host 절대 경로와 사용자 기기 이름·ID를 placeholder로 처리했다. 비밀값을 공개 자료에 넣지 않았다. 공개 요약을 원본 raw byte 감사의 대체 증거로 사용하지 않는다.

다음 실행 전에 감사 harness의 정책 범위를 명시적으로 정리한다. 이 중단 attempt를 조용히 이어서 성공으로 바꾸지 않는다. #212의 최소 RN·실제 OSS 양플랫폼 baseline과 fresh 인계 요구는 유지한다. 실제 Runstir gate는 후속 티켓 범위다.

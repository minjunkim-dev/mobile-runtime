# ADR-0017: Go 게이트 표본을 Xcode 27 기준으로 다시 고정한다

> 2026-10-07: [ADR-0018](0018-use-one-xcode-27-go-sample.md)이 현재 iOS 게이트를 대체했다. 아래 후보 실패와 준비 실패 기록은 유지한다.

- 상태: 채택
- 날짜: 2026-10-06
- 관련: #156 · ADR-0008 · ADR-0012 · ADR-0016

maintainer는 Go 게이트의 host를 Xcode 27로 통일하기로 했다. 2027년에는 Xcode 27 이상이 필수가 된다. Xcode 26.x를 추가로 설치해 옛 표본을 살리는 일은 곧 버려질 검증 조합에 투자하는 일이다.

잠긴 mattermost-mobile `10207015`은 Xcode 27.0에서 `mobile` 없이도 빌드되지 않는다(#155, [up 라운드 4](../dogfooding/up-round-4.md)). Pods resource bundle target의 deployment target이 Xcode 27의 허용 범위 밖이다. ADR-0016은 tracked 파일 수정을 금지한다. 따라서 이 표본은 Xcode 27 검증 조합에서 known-good 표본이 아니다. Rainbow `29eade9a`와 Joplin `2654b336`은 Xcode 27에서 측정하지 않았다.

이 결정은 mattermost-mobile의 실패를 관측한 뒤에 나왔다. 그래서 이 ADR은 ADR-0008의 기존 게이트를 그대로 지키지 않는다. ADR-0008은 표본 변경이 필요하면 별도 게이트와 별도 결정으로 다시 열라고 정했다. 이 ADR이 그 별도 결정이다. 검증 조합과 세 SHA를 함께 바꾸는 Xcode 27 게이트를 연다. 새 후보는 baseline 측정 전에 고정한다. 새 후보의 결과를 보고 SHA를 다시 고르는 일은 허용하지 않는다.

## 결정

- Go 게이트의 검증 조합은 Xcode 27.0 / iOS 27.0 simulator runtime이다. React Native 버전은 각 표본의 선언을 따른다.
- 세 repo(mattermost-mobile, Rainbow, Joplin)와 3/3 기준은 바꾸지 않는다. ADR-0016의 사람 준비 범위와 Go round 규칙도 그대로다.
- 후보 선정 규칙: 각 repo의 default branch에서 first-parent를 따라 committer date가 `2026-10-06T00:00:00Z` 이하인 첫 commit을 고른다. repo마다 후보는 하나다.
- 아래 표의 SHA가 최종 입력이다. 실행자는 규칙을 다시 계산하지 않는다.
- 후보는 아래 baseline 절차로 확인한다. `mobile` 없이 build·install·launch·첫 화면에 도달하고 tracked 파일을 바꾸지 않아야 known-good 표본이다.
- 준비 목록에 있는 항목이 빠져 실패하면 준비 실패다. 준비를 보완하고 같은 후보로 다시 확인한다.
- 선언된 의존성·빌드 설정이 Xcode 27과 맞지 않아 실패하면 후보 실패다. 다른 commit을 찾지 않는다. 결과를 기록하고 그 repo의 처리는 maintainer가 별도 결정으로 정한다.
- 원인을 둘 중 하나로 정할 수 없으면 판정을 보류하고 maintainer에게 넘긴다.
- baseline 실패는 `mobile`의 검증 결과 `failed`나 Go blocker로 분류하지 않는다.
- 이 ADR이 고정한 SHA가 ADR-0008·ADR-0016의 잠긴 SHA를 대체한다. 옛 SHA의 실행 결과(라운드 1–4)는 새 Go round에 합산하지 않는다.

## 후보

선정 시점(2026-10-06)에 세 후보는 각 default branch의 tip이었다.

| repo | default branch | 후보 SHA | committer date | baseline |
| --- | --- | --- | --- | --- |
| `mattermost/mattermost-mobile` | `main` | `62f18af38254a9acf74390b3815c2a11852b7bc5` | 2026-10-05T11:10:40Z | 후보 실패 |
| `rainbow-me/rainbow` | `develop` | `a64ecce56fe1c41551d9eb1bf354a698114be4f0` | 2026-10-05T23:18:52Z | 준비 실패(실제 키 대기) |
| `laurent22/joplin` | `dev` | `aaa6f8e3ae206555fc5de7dbd82a8bcfe0d2d5cc` | 2026-10-05T13:09:44Z | 후보 실패 |

## baseline 절차

공통 조건: host는 macOS 27.0.1 / Xcode 27.0 (27A266a) / iOS 27.0 runtime이다. 시뮬레이터는 booted `iPhone 18 Pro`다. shell은 `mise activate zsh` 상태이고 `MISE_AUTO_INSTALL=false`다. 각 후보는 새 디렉터리에 fresh clone한다.

공통 실행 순서:

1. repo별 준비와 의존성 설치를 한다(아래 표).
2. repo별 Metro 명령을 실행한다.
3. `xcodebuild -workspace <workspace> -scheme <scheme> -configuration Debug -destination 'platform=iOS Simulator,id=<booted id>' build`를 실행한다.
4. 빌드한 `.app`을 `xcrun simctl install`로 설치하고 `xcrun simctl launch`로 실행한다.
5. 첫 화면을 확인한다. RN red box·crash·흰 화면은 실패다. 네트워크·기능 오류는 판정에 넣지 않는다.
6. `git status --porcelain`으로 tracked 파일 상태를 확인한다.

| repo | 준비 목록 | 의존성 설치 | Metro | workspace / scheme |
| --- | --- | --- | --- | --- |
| mattermost-mobile | Node 24.15.0, Ruby 3.2.11에 CocoaPods 1.16.1, Android SDK(`ANDROID_HOME`, `emulator`; repo의 solidarity가 요구) | `npm ci`(postinstall이 `pod install` 실행) | `npm start` | `ios/Mattermost.xcworkspace` / `Mattermost` |
| Rainbow | `mise trust`, Node 22·Ruby 3.4.8·Bundler 4.0.6, Corepack Yarn 4.13.0, `.env.example`을 복사한 `.env`(placeholder) | `yarn install && yarn setup`, `yarn install-bundle && yarn install-pods` | `yarn start` | `ios/Rainbow.xcworkspace` / `Rainbow` |
| Joplin | Node 22, Corepack Yarn 4.16.0, PATH의 CocoaPods 1.16.2 | root에서 `yarn install`, `packages/app-mobile/ios`에서 `pod install` | `packages/app-mobile`에서 `yarn start` | `packages/app-mobile/ios/Joplin.xcworkspace` / `Joplin` |

- 위 명령은 각 후보 SHA의 README·`readme/dev/BUILD.md`·`package.json`에서 가져왔다.
- Rainbow의 내부 전용 단계(`yarn update-env`, `rainbow-scripts`)는 외부 기여자 절차를 따라 쓰지 않는다.
- Rainbow 앱 환경값은 ADR-0016대로 placeholder로 먼저 시도한다. 첫 화면에 도달하지 못하면 maintainer가 실제 키를 준비한다. baseline과 Go round에 같은 준비 조건을 적용한다. 준비한 종류만 기록하고 값과 파일은 기록하지 않는다.

## baseline 결과 (2026-10-06–07)

세 후보 모두 known-good 표본이 아니다. Xcode 27 게이트에서 통과한 표본은 없다.

| repo | 결과 | 멈춘 단계와 원인 | tracked 파일 |
| --- | --- | --- | --- |
| mattermost-mobile | 후보 실패 | xcodebuild exit 65. Pods resource bundle target 11개의 deployment target 9.0–14.0을 Xcode 27이 error로 거부한다 | `ios/Podfile.lock` 변경. commit된 lock이 `package-lock.json`과 다르다(`react-native-network-client` 1.11.2 → 1.11.4)와 checksum |
| Rainbow | 준비 실패(실제 키 대기) | `yarn setup`의 `fetch:networks`가 `METADATA_BASE_URL`에서 network 목록을 받는다. placeholder로는 실패한다. ADR-0016에 따라 maintainer가 실제 값을 준비하면 같은 후보로 다시 확인한다. 다만 오른쪽 tracked 파일 변경 때문에 실제 값을 준비해도 known-good 표본이 될 수 없다 | postinstall이 `GoogleService-Info.plist`와 `src/graphql/config.js`를 바꾸고 `git update-index --assume-unchanged`로 `git status`에서 숨긴다 |
| Joplin | 후보 실패 | xcodebuild exit 65. Pods resource bundle target 4개의 deployment target 9.0–12.4를 Xcode 27이 error로 거부한다 | `packages/app-mobile/ios/Podfile.lock` 변경. commit된 lock이 `yarn.lock`과 다르다(`react-native-safe-area-context` 5.7.0 → 5.8.0)와 checksum |

- 두 build 실패는 같은 원인이다. CocoaPods 1.16.x가 만드는 resource bundle target은 pod 선언의 낮은 deployment target을 그대로 쓴다. Xcode 27은 15.0 미만을 error로 처리한다. 두 repo의 upstream tip은 아직 Xcode 27에 대응하지 않았다.
- tracked 파일 상태는 `git status --porcelain`과 함께 `assume-unchanged` 파일의 내용을 HEAD와 직접 비교해 확인했다. Rainbow의 변경은 `git status`에 나타나지 않는다.
- 세 repo 모두 문서화된 절차만으로 tracked 파일이 바뀐다. "tracked 파일 무변경" 조건은 이 세 repo에서 성립하지 않는다.
- Rainbow `.env`는 `.env.example`의 빈 키 18개를 placeholder로 채우고, 예시에 없는 `METADATA_BASE_URL`을 추가해 준비했다. 값과 파일은 기록하지 않는다.

사전 절차에 추가한 실행 조건(repo의 명령은 바꾸지 않았다):

- maven CDN 연결의 일부가 13–70KB/s로 느렸다. RN pod 스크립트의 curl은 다시 시도하지 않는다. 임시 `CURL_HOME`의 `.curlrc`로 저속 연결을 끊고 다시 시도하게 했다.
- 외장 SSD가 두 번 분리됐다. 이 host는 Android SDK·CocoaPods cache·DerivedData를 SSD에 둔다. Joplin은 `CP_CACHE_DIR`와 `-derivedDataPath`를 임시 경로로 지정해 실행했다.
- Joplin root에는 Node 선언이 없다. 준비 목록의 Node 22를 root에도 적용하려고 `MISE_NODE_VERSION=22`를 지정했다.

규칙에 따라 다른 commit을 찾지 않았다. 다음 처리는 maintainer가 별도 결정으로 정한다.

## 대안

- **Xcode 26.x를 추가 설치하고 옛 SHA 유지**: 기각. 2027년에 버려질 검증 조합이다.
- **실패한 mattermost-mobile만 교체**: 기각. 실패를 본 표본만 고르면 ADR-0008이 막은 사후 교체가 된다.
- **`mobile`이 deployment target을 덮어쓴다**: 기각. repo가 선언하지 않은 빌드 설정을 `mobile`이 바꾸게 된다. 그 다음 Xcode 27 비호환이 있는지도 알 수 없다.
- **후보가 실패하면 이전 commit을 차례로 시도**: 기각. 통과하는 commit을 찾을 때까지 고르는 일은 결과를 보고 표본을 고르는 일이다.

## 결과

- 현재 판정은 계속 **No-Go**다. 이 ADR은 표본을 다시 고정할 뿐 새 성공 근거를 만들지 않는다.
- baseline을 통과한 후보만 조사 실행한다.

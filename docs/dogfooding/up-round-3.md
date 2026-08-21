# Dogfooding: 프로젝트 실행 환경 / build 경계 재검증

- 날짜: 2026-08-21
- mobile: `b417b20` (`codex/project-toolchain-context`, `main` `62fd149` 기반)
- 호스트: Xcode 26.6 (17F113), iOS 26.5 simulator runtime
- 자동 설치 방지: 모든 실물 명령에 `MISE_AUTO_INSTALL=false`

## 잠긴 표본과 상태

| repo | commit | 실행 위치 | 시작 상태 |
|---|---|---|---|
| mattermost-mobile | `10207015a5023d844c65885ed134814f6c22294a` | repo root | exact commit fresh checkout, 의존성 없음 |
| Rainbow | `29eade9a97e1dd47a307aeb57772138901987d1f` | repo root | exact commit fresh checkout, 의존성 없음 |
| Joplin | `2654b33620775080d1d59c552259d41e33dad3d2` | `packages/app-mobile` | exact commit fresh checkout, workspace 의존성 없음 |

세 checkout 모두에서 `mobile doctor --json`, `mobile build --json`, `mobile up --json`을 직접 실행했다. 실행 뒤 Git 상태는 깨끗했고 workspace root에 `node_modules`가 생기지 않았다. `mise trust`·`mise install`·`mise use`, Xcode/runtime 설치, 앱 secret 생성은 실행하지 않았다.

## 결과

| repo | doctor | build | up | 프로젝트 실행 환경 |
|---|---|---|---|---|
| mattermost-mobile | `error` | `validate` 실패(3건) | `validate` 실패(3건) | 현재 PATH 선택 `pass`; Node 24.15.0 `pass` |
| Rainbow | `error` | `validate` 실패(3건) | `validate` 실패(3건) | 커밋된 mise 설정 선택 `pass`; auto-install off; Node 22.23.2 `pass` |
| Joplin | `error` | `validate` 실패(2건) | `validate` 실패(2건) | 현재 PATH 선택 `pass`; workspace root를 정확히 식별 |

실패 수는 repo별로 다음과 같다.

- mattermost-mobile: scheme 미선언, CocoaPods 실행 불가, `.ruby-version`과 현재 Ruby 불일치.
- Rainbow: scheme 미선언, Yarn 실행 불가, `.ruby-version`과 현재 Ruby 불일치. CocoaPods는 Bundler 컨텍스트에서 별도 warning으로 측정됐다.
- Joplin: scheme 미선언, Yarn 실행 불가. 의존성 remediation은 member가 아니라 workspace root의 `yarn install --frozen-lockfile`을 가리켰다.

fresh clone에서 `project.detected`가 `node_modules missing` warning이면 프로젝트 실행 환경까지 건너뛰던 순서 역전도 이 라운드에서 발견했다. `b417b20`은 실행 환경이 설치 전 먼저 검증되도록 고쳤고, 위 표는 수정 뒤의 재실행 결과다.

## 증거 경계

- 세 repo 모두 validation에서 멈췄으므로 이번 라운드에는 실물 dependency alignment, xcodebuild 성공, app install, launch 또는 UI 기능 성공 근거가 없다.
- `mobile build`의 `validate → dependencies → device → build` 구성과 Metro/install/launch/설치 기록 부재는 shared pipeline 테스트로 검증했다.
- npm/Yarn/pnpm/Bun의 lockfile 보존 명령, 기존 `node_modules` 재정렬, manifest/lockfile byte 보존, 실패 marker는 Core 테스트로 검증했다.
- 전체 결과는 macOS 405 tests / 52 suites 통과와 Linux Core build 통과다.
- Rainbow의 Firebase/ENS 접근 권한은 이 환경/validation 검증에 필요하지 않았다. 반대로 이번 결과를 Rainbow launch나 Firebase/ENS 기능 성공으로 해석할 수 없다.

## 게이트

3/3 앱 UI 게이트는 계속 `mobile up`의 launch 결과로만 판정한다. `mobile build` 성공도 UI 성공으로 승격하지 않으며, 이번 라운드는 새 launch 성공 근거를 만들지 않았으므로 ADR-0008의 **No-Go** 판정은 유지된다.

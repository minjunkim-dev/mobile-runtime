# mobile doctor 도그푸딩 후보 리서치

`mobile doctor`(RN repo를 읽어 환경 요구사항을 추론·검증하는 도구)를 실제 오픈소스 RN 앱에 돌려 유용성을 검증하기 위한 후보 선정. (조사일: 2026-08-13, GitHub API로 직접 확인)

## 선정 기준

- 실제 유지되는 **앱**일 것 (라이브러리/템플릿 제외, 최근 커밋 활성)
- `ios/` + `android/` 디렉터리가 repo에 커밋되어 있을 것 (Expo CNG로 네이티브 폴더가 없는 프로젝트 제외)
- 환경 요구사항 선언 파일(.nvmrc, Gemfile, .tool-versions, engines 등)이 다양할 것
- 빌드/셋업 문서가 있어 doctor 출력과 "정답" 비교가 가능할 것
- 후보 간 다양성: RN 버전대, 모노레포 여부, 규모, 패키지 매니저

## 후보표

| # | Repo | 활성도 (pushed / stars) | RN 버전 | 환경 선언 파일 (repo에서 확인) | 검증 난이도 | 특이점 |
|---|------|------------------------|---------|-------------------------------|------------|--------|
| 1 | [mattermost/mattermost-mobile](https://github.com/mattermost/mattermost-mobile) | 2026-08-13 / 2.7k | 0.83.9 (expo 55) | `.nvmrc`, `.node-version`, `.ruby-version`, `Gemfile`(+lock), `engines`(node `^22.11 \|\| ^24.15`, npm `^10 \|\| ^11`), fastlane | **하** | 가장 표준적인 단일 RN 앱. `.nvmrc`와 `.node-version`이 둘 다 존재 → 중복/충돌 선언 처리 검증에 유일한 케이스. npm 사용. `docs/` 포함 |
| 2 | [rainbow-me/rainbow](https://github.com/rainbow-me/rainbow) | 2026-08-13 / 4.4k | 0.81.6 (expo 54, prebuilt) | `.node-version`, `.ruby-version`, `.xcode-version`, `mise.toml`, `Gemfile`(+lock), `engines`(node >=22), `packageManager`(yarn 4.13), `.yarnrc.yml` | **중** | 환경 선언 파일이 가장 다양. `mise.toml`·`.xcode-version` 파서 검증에 유일한 케이스. yarn 4 (berry). `.env.example` 존재 |
| 3 | [laurent22/joplin](https://github.com/laurent22/joplin) | 2026-08-12 / 55.9k | 0.81.6 (app-mobile, expo 54) | `packages/app-mobile/.node-version`, `packages/app-mobile/Gemfile`, root `engines`(node >=20), `.yarnrc.yml`, `.envrc`, `devbox.json` | **중상** | yarn workspaces + lerna **모노레포**. RN 앱이 `packages/app-mobile`에 위치 → repo 루트가 아닌 서브패키지에서 요구사항을 찾아내는 능력 검증. 규모 큼 |
| 4 | [RocketChat/Rocket.Chat.ReactNative](https://github.com/RocketChat/Rocket.Chat.ReactNative) | 2026-08-12 / 2.4k | 0.81.5 (expo 54, prebuilt) | `.ruby-version`, `Gemfile`(+lock), `.bundle`, `packageManager`(pnpm 10.33), `engines`(node >=18) | **중** | **pnpm** 사용 케이스. expo 의존이지만 `ios/`·`android/` 커밋됨. `docs/` + CONTRIBUTING 있음. `engines`가 느슨(`>=18`)해서 doctor의 "선언 vs 실제" 판단력 테스트에 좋음 |
| 5 | [Expensify/App](https://github.com/Expensify/App) | 2026-08-13 / 5.0k | 0.86.0 (expo 57) | `.nvmrc`, `.ruby-version`, `.bun-version`, `.java-version`, `Gemfile`(+lock), `.bundle`, `engines`(bun 1.3.14, node 26.5.0, npm 11.17.0 — 정확 핀) | **상** | 최신 RN(0.86) + **bun** 런타임 + `.java-version` 명시 등 가장 공격적인 환경 요구. git submodule(Mobile-Expensify) 포함, 규모 매우 큼. `contributingGuides/`에 상세 셋업 문서 → 정답 비교 용이 |

## 검토 후 제외

| Repo | 제외 사유 |
|------|-----------|
| [bluesky-social/social-app](https://github.com/bluesky-social/social-app) | repo 루트에 `ios/`/`android/` 없음 — Expo CNG(prebuild) 방식 (`app.config.js`, `eas.json`만 존재). 네이티브 폴더 조건 미달 |
| [status-im/status-mobile](https://github.com/status-im/status-mobile) | **archived** (2026-07 기준). Nix 기반이라 흥미로웠으나 유지되는 앱 조건 미달 |

## 추천 3개

1. **mattermost/mattermost-mobile** — 첫 도그푸딩 대상으로 최적. 표준 단일 앱 구조라 빠르게 돌려볼 수 있고, `.nvmrc`+`.node-version`+`engines` 삼중 선언이 있어 중복 소스 병합·충돌 로직을 바로 검증할 수 있다.
2. **rainbow-me/rainbow** — 환경 선언 파일 커버리지 최대화. `mise.toml`, `.xcode-version`, yarn 4 등 다른 후보에 없는 파서 케이스를 한 repo에서 확보.
3. **laurent22/joplin** — 모노레포 케이스. doctor가 루트만 보고 끝내는지, `packages/app-mobile`까지 내려가 요구사항을 찾는지 검증하는 데 필수.

Expensify(최신 RN + bun + submodule, 난이도 상)와 Rocket.Chat(pnpm)은 위 3개 통과 후 확장 대상으로 유지.

## 데이터 출처

- 각 repo 메타데이터·루트 파일 목록·package.json: GitHub REST API (`repos/{owner}/{repo}`, `/contents`) 직접 조회, 2026-08-13

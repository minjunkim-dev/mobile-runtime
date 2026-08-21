# ADR-0008: 잠긴 세 repo 게이트를 유지하고 현재를 No-Go로 판정한다

- 상태: 채택
- 날짜: 2026-08-21
- 관련: #14(Go/No-Go 게이트), #44(up dogfooding 라운드 1) · [up 라운드 1](../dogfooding/up-round-1.md), [up 라운드 2](../dogfooding/up-round-2.md)

## 배경

#14는 정상 호스트의 fresh clone에서 `mattermost-mobile` / `rainbow` / `joplin` 세 repo 모두가 `mobile up`으로 실제 앱 UI까지 도달해야 Go라는 기준을 계획 시점에 잠갔다. `CONTEXT.md`의 **Go/No-Go 게이트**도 기준을 판정 시점이 아니라 계획 시점에 잠근다고 정의한다.

최신 `main`(`b4ddfba`)에서 dogfooding 근거를 다시 대조한 결과는 **2/3**이다.

- mattermost-mobile과 joplin은 `launch`까지 관통했다.
- rainbow는 두 라운드 모두 `build`에서 멈췄다. 이 repo는 `.env`와 `ios/debug.xcconfig`를 커밋하지 않고, postinstall은 API 키가 든 `.env`가 있을 때만 `debug.xcconfig`를 만든다. fresh clone만으로는 빌드 입력이 완성되지 않는다.
- 현재 `up`은 이 원인을 화면에서 바로 찾게 하지만, repo별 비밀값을 만들거나 입력받아 온보딩하지는 않는다.

따라서 세 선택지가 남는다: `.env`/`debug.xcconfig` 온보딩까지 지원 범위를 넓히기, fresh-clone 가능한 다른 RN 앱으로 표본 바꾸기, 잠긴 기준을 그대로 적용해 No-Go로 판정하기.

## 결정

**세 repo와 3/3 기준을 유지하고, 현재 상태를 No-Go로 판정한다.**

- `mobile`은 repo가 선언한 도구와 명령을 조율하지만, repo별 비밀값을 생성하거나 대신 입력하지 않는다. `.env`/`debug.xcconfig` 온보딩은 이번 지원 범위에 넣지 않는다.
- 검증 표본을 바꾸지 않는다. 실패를 관측한 뒤 표본을 교체하면 #14가 잠근 게이트가 다른 질문으로 바뀐다.
- No-Go는 프로젝트 중단이 아니다. 같은 표본과 기준으로 개선·재검증하는 루프를 계속하되, 3/3 실측 전에는 Go라고 부르지 않는다.

## 대안

### `.env`/`debug.xcconfig` 온보딩까지 지원한다

기각한다. repo마다 다른 비밀값의 입력·검증과 생성 훅을 `up`의 책임으로 가져오며, “Orchestrate, don't replace” 경계를 넓힌다. 빈 `.env` 복사만으로는 API 키 요구를 충족하지 못하므로 일반 해법도 아니다.

### fresh-clone 가능한 다른 RN 앱으로 검증 대상을 바꾼다

기각한다. 새 표본 자체는 유효할 수 있지만, 현재 실패를 본 뒤 교체하면 잠긴 3/3 판정의 증거가 되지 않는다. 표본 변경이 필요하면 별도 게이트와 별도 결정으로 다시 연다.

## 결과

- 현재 판정은 **No-Go**다. 성공 근거는 2/3이며 rainbow의 fresh-clone 관통은 증명되지 않았다.
- `CONTEXT.md`는 바꾸지 않는다. North Star와 Go/No-Go의 뜻은 이미 정의돼 있고, 이번 문서는 그 용어를 적용한 결정이다.
- Go로 바꾸려면 같은 세 repo의 fresh clone에서 3/3 관통을 다시 실측해야 한다.
- 지원 범위나 검증 표본을 바꾸는 후속 결정은 이 ADR을 명시적으로 다시 열거나 대체해야 한다.

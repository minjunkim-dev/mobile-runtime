---
status: accepted
date: 2026-08-21
---

# up은 launch까지 유지하고 build를 별도 명령으로 둔다

`mobile up`은 설치·launch까지 완료해 화면에 방금 빌드한 코드를 남기는 기존 계약과 세 repo 앱 UI dogfooding 게이트를 유지한다. 앱 환경값이 없어도 가능한 환경·의존성·컴파일 검증은 별도 `mobile build` 명령이 담당하며, build는 앱 산출물을 만든 뒤 설치·launch하지 않고 끝난다.

`up --no-launch` 같은 예외 플래그를 두지 않는다. `up`의 의미를 조건부로 만들지 않고, Firebase·ENS 같은 앱 환경값의 부재를 도구체인이나 컴파일 실패로 오인하지 않기 위한 결정이다.

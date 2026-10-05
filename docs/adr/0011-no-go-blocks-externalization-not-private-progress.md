# ADR-0011: No-Go는 외부화를 막고 private 진행은 막지 않는다

ADR-0008의 2/3 No-Go와 잠긴 세 repo 기준을 유지하며, 같은 세 repo의 fresh clone에서 실제 앱 UI까지 3/3 관통하기 전에는 Go 판정, 정식 이름과 public 저장소 전환, 외부 사용자 배포, 일반적인 React Native 지원 주장을 허용하지 않는다. 증거 기준은 보존하되 Rainbow의 repo별 비밀값 조건이 프로젝트 전체를 무기한 멈추지 않도록 private 구현, 내부 alpha와 dogfooding, 다음 milestone 계획은 진행할 수 있다. 지원 범위나 검증 표본을 바꾸려면 ADR-0008을 명시적으로 다시 열거나 대체한다.

> 2026-10-05: public 저장소 전환 금지는 [ADR-0014](0014-open-source-is-not-go.md)가 대체한다. Go 판정, 정식 이름, 외부 사용자 배포, 일반적인 React Native 지원 주장에 대한 제한은 유지된다.

# ADR-0016: Go 게이트는 사람이 준비한 앱 환경값을 허용하고 iOS만 판정한다

- 상태: 채택
- 날짜: 2026-10-06
- 관련: ADR-0008 (fresh clone 해석과 플랫폼 범위 보완) · ADR-0010 · ADR-0011 · ADR-0014

ADR-0008은 Rainbow가 fresh clone만으로 빌드 입력을 완성하지 못해 실패했다고 판정했다. `mobile`이 비밀값을 만들거나 입력하지 않는다는 경계만 정했고, 사람이 앱 환경값을 준비하는 일은 정하지 않았다. 이 공백을 그대로 두면 Rainbow upstream이 바뀌지 않는 한 잠긴 SHA로는 Go에 도달할 수 없고, ADR-0011의 외부화 제한이 영구 제한이 된다. 내부 alpha는 이미 maintainer가 앱 환경값을 직접 준비하는 것을 허용한다.

## 결정

- 세 repo 게이트의 fresh clone은 사람이 앱 환경값(`.env` 등)을 준비하는 것을 허용한다. `mobile`이 그 값을 만들거나 입력하거나 생성 훅을 대신 실행하는 것은 계속 허용하지 않는다.
- 세 repo, 잠긴 SHA, 3/3 기준은 바꾸지 않는다.
- 앱 환경값은 `.env.example` 같은 placeholder로 먼저 시도한다. 초기 UI에 도달하지 못하면 maintainer가 발급할 수 있는 실제 키를 쓴다.
- 사람은 repo가 선언한 도구를 host에 설치하고(선언된 Xcode 버전 포함), `mise trust` 같은 신뢰를 결정하고, untracked `mobile.yml`을 작성할 수 있다. tracked 파일은 수정하지 않는다.
- Xcode를 선언하지 않은 repo는 `mobile.yml` override로 다른 설치 Xcode를 지정할 수 있다. override 사실을 증거에 기록한다.
- 앱 UI 도달은 앱의 첫 화면 렌더링이다. RN red box, crash, 흰 화면은 실패다. 네트워크·기능 오류는 판정에 넣지 않는다.
- 3/3은 같은 `mobile` SHA, 같은 host, 한 Go round 안에서 통과해야 한다. 다른 round나 다른 SHA의 성공을 합산하지 않는다.
- ADR-0008의 게이트는 iOS `mobile up` 주장만 판정한다. Android Go 게이트가 필요하면 계획 시점에 별도로 잠근다. 세 repo의 Android 관통을 기존 게이트 조건에 더하지 않는다.
- iOS Go는 정식 이름과 외부 배포를 허용한다. 지원 주장은 통과한 검증 조합 단위로만 한다. "React Native iOS 일반 지원"은 ADR-0012의 지원 범위 근거가 생기기 전까지 주장하지 않는다. 이 항목은 ADR-0011의 Go 이후 허용 범위를 좁힌다.

## 대안

- **순수 fresh clone 유지**: 기각. 잠긴 Rainbow SHA로는 Go가 구조적으로 불가능하고, 내부 alpha 정의와 기준이 어긋난다.
- **Android 관통을 기존 게이트 조건에 추가**: 기각. 판정 뒤 기준을 넓히는 일이며 ADR-0008이 금지한 기준 변경과 같다.

## 결과

- 현재 판정은 계속 **No-Go**(2/3)다. 이 ADR은 해석을 정할 뿐 새 성공 근거를 만들지 않는다.
- Go 판정 증거에는 사람이 준비한 앱 환경값의 종류만 기록한다. 값과 파일은 기록하지 않는다.

> 2026-10-07: Go 게이트의 검증 조합(Xcode 27.0 / iOS 27.0)과 세 repo의 표본 SHA는 [ADR-0017](0017-relock-go-samples-for-xcode-27.md)이 대체한다. 세 repo와 3/3 기준은 그대로다.

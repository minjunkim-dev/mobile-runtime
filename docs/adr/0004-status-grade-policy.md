# ADR-0004: 등급은 요구의 확실성이 정하고, doctor는 선택 미확정에 error를 쓰지 않는다

- 상태: 채택
- 날짜: 2026-08-14
- 관련: #21(dogfooding), #22, #24, #28 · ADR-0003(근거 체인)

## 배경

Dogfooding(#21)에서 등급(Status) 쪽으로 세 가지가 드러났다.

1. **실행되지 않는 도구가 `unknown`으로 나간다.** mattermost-mobile은 `Gemfile.lock`에 CocoaPods 1.16.1을 잠갔고 검증 호스트에는 CocoaPods가 없다 — `pod install`이 확실히 실패하는 상태다. 그런데 `pod`가 mise shim으로 PATH에 있어서 `notOnPath`(= `error`)가 아니라 `unreadable`(= `unknown`)로 떨어졌다. 판정 등급이 실제 상태보다 약하다.

2. **요구가 있는데 Check가 아예 사라진다.** joplin의 `packages/app-mobile`에는 `Gemfile`이 있고 CocoaPods를 요구하지만 `Gemfile.lock`이 커밋돼 있지 않다. 현재 Check는 lock 유무를 조건으로 삼아 한 줄도 내지 않았다. "판단 불가는 침묵하지 않고 `unknown`으로 명시한다"는 원칙과 어긋난다.

3. **아무 문제 없는 repo가 `error`로 끝난다.** scheme이 복수인데 `ios.scheme`이 없으면 `error`인데, 검증 repo **3/3 전부**가 여기 걸렸다(scheme 3·8·3개). 앱 확장(share extension·widget·notification service)을 가진 실제 RN 앱에서 scheme 복수는 예외가 아니라 기본값에 가깝다.

여기에 ADR-0003이 하나를 더 얹었다. `node_modules` 존재를 "설치 완결"의 근거로 쓰지 않기로 하면서, `project.detected`가 무엇을 판정하는 Check인지 다시 정해야 했다.

## 결정

### 등급은 요구의 확실성이 정한다

측정에 실패했다는 **사유**가 등급을 정하는 게 아니라, 그 도구가 필요하다는 **요구가 확정됐는지**가 정한다.

- 실행했는데 버전을 얻지 못한 도구는 사용 불가로 본다. 그 도구를 프로젝트가 요구하면 `error`, 요구가 확정되지 않았으면 `unknown`이다.
- 측정 실패 사유는 reason에 **외부 도구의 원문 그대로** 남긴다. 이번 dogfooding에서 `mise ERROR No version is set for shim: pod`, `mise ERROR error parsing config file: …/mise.toml`이 그대로 실린 덕에 원인(mise shim 미설정 / `mise trust` 미실행)이 한 문장으로 특정됐다. 이 습성은 유지한다.
- **`Gemfile`만 있어도 CocoaPods의 존재 요구는 확정이다.** `gem 'cocoapods'`는 선언이지 추론이 아니다. 버전 요구(`Gemfile.lock`)와 존재 요구(`Gemfile`)를 분리해, lock이 없으면 "설치돼 있나"까지만 판정한다. 어느 쪽이든 침묵하지 않는다.

### doctor는 선택 미확정에 `error`를 쓰지 않는다

scheme 복수 + `ios.scheme` 미선언은 doctor에서 **`warning`**이다.

- doctor의 계약은 "지금 이 머신에서 이 프로젝트를 빌드할 수 있나"이고, scheme 미선택은 머신 상태가 아니라 **아직 고르지 않은 선택**이다.
- exit 1은 CI에서 실패를 뜻하므로 등급을 아껴 쓴다. 이 변경으로 검증 repo 3개의 클론 직후 실행은 warning만 남아 exit 0이 된다 — "warning/unknown만 있으면 exit 0"(#15 user story 35)과 일치한다.
- **`up`에서는 진행 불가다.** 등급 분기는 `up`의 해당 stage가 자기 판단으로 갖는다. Check는 같은 사실을 낼 뿐이고, 엔진에 호출자별 등급 매핑을 넣지 않는다 — `up`이 아직 없는 지금 그것을 만들면 쓰지 않는 추상이 남는다. `up`(#13) 구현에서 실제로 아쉬우면 그때 엔진 쪽으로 올린다.
- 앱 확장으로 보이는 scheme을 후보에서 빼는 휴리스틱은 채택하지 않는다. 추론을 늘려 미탐을 만든다.

### `project.detected`는 설치 완결을 주장하지 않는다

- 판정 대상은 "여기 React Native 프로젝트가 있다"이다. `node_modules/react-native` 하나로 "dependencies installed"를 통과시키던 미탐이 여기서 사라진다.
- 그렇다고 `node_modules` 부재가 `pass`인 것은 아니다. 의존성 없이는 빌드가 안 되는 것이 사실이므로 **`warning` + install 명령**을 유지한다. install 명령은 ADR-0003의 워크스페이스 규칙이 정한 매니저를 쓴다.
- 없앤 것은 "설치가 **완결**됐다"는 근거 없는 주장이지, "설치가 안 됐다"는 관측이 아니다.
- 락파일의 direct dependency를 표본 대조해 설치 완결을 진짜로 검증하는 방안은 채택하지 않는다. joplin처럼 워크스페이스 루트로 호이스팅되는 구조에서 새 미탐을 만든다.

## 결과

- 같은 "측정 실패"가 프로젝트에 따라 다른 등급이 된다. 등급을 읽으려면 요구가 어디서 왔는지를 함께 봐야 하고, 그 정보는 `-v`의 source에 이미 있다(ADR-0003).
- `warning`이 늘고 `error`가 준다. `error`는 "이 머신에서 지금 빌드가 실패한다"에 가깝게 좁아진다.
- doctor와 `up`의 판정이 한 지점에서 갈린다. 같은 사실에 대해 두 명령이 다른 결론을 낼 수 있다는 뜻이므로, `up` 구현 시 이 ADR을 함께 열어야 한다.

## 대안

- **측정 실패는 언제나 `unknown`(현행).** 규칙은 단순하지만, 확실히 못 쓰는 도구를 "모르겠다"로 내보내면 사용자는 무엇을 고쳐야 할지 모른다.
- **실행 실패는 언제나 미설치로 간주해 `error`.** 요구하지도 않는 도구에 대해 오탐을 만든다. `Gemfile.lock`이 CocoaPods를 잠그지 않은 프로젝트에까지 CocoaPods를 요구하게 된다.
- **scheme 복수 `error` 유지.** `mobile.yml`을 쓰게 만드는 강제력이 설계 의도였다(#11·#20). 그러나 강제 대상이 예외가 아니라 다수라면 그것은 강제가 아니라 마찰이다 — dogfooding 3/3이 그 증거다.
- **Check 결과에 상황 코드를 두고 호출자가 등급으로 매핑.** `up`이 생기면 필요할 수 있으나 지금은 사용처가 하나뿐이다.

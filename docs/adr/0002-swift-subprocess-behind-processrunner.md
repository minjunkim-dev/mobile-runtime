# ADR-0002: swift-subprocess를 채택하되 ProcessRunner 한 파일에 가둔다

- 상태: 채택
- 날짜: 2026-08-13
- 관련: #8(SpikeIOS), #9(패키지 구조), #15(Core 계약), #16(tracer bullet)

## 배경

mobile이 하는 일의 대부분은 외부 도구 호출이다 — `xcodebuild`, `xcrun simctl`, 나중에는 `node`·`pod`·`gradle`. 이 층의 품질이 도구 전체의 품질을 결정한다.

SpikeIOS(#8)에서 swift-subprocess 1.0.0을 실측했고, 결과는 양면이었다:

- **좋다**: async/await 기반 API가 깔끔하고, non-zero exit이 throw가 아니라 `terminationStatus` 검사다. simctl은 정상적으로 non-zero를 내는 경우가 많아서 이 성질이 orchestration에 정확히 맞는다.
- **얇다**: 레퍼런스가 부족해 문서보다 소스를 읽어야 했다. 제안서 시절 타입명 `CollectedResult`가 1.0에서 `ExecutionResult`로 바뀌어 있었다. 타임아웃은 아예 없다.

즉 정식 1.0 태그이긴 하나 생태계 성숙도가 낮은 의존이다. 대안인 Foundation `Process`는 async/취소 처리가 더 나쁘다.

## 결정

**swift-subprocess를 채택하되, 그 타입이 `Sources/Core/ProcessRunner.swift` 밖으로 나가지 않게 한다.**

- `ProcessCommand` / `ProcessResult` / `TerminationStatus` / `ProcessError`는 우리 타입이다. swift-subprocess의 `ExecutionResult`·`Environment`·`Arguments`·`Executable`은 이 파일 안에서만 존재한다.
- 호출자는 `ProcessRunner` 프로토콜만 본다. 테스트는 이 프로토콜을 fake로 갈아끼운다 — 도구 전체가 결정적으로 테스트되는 유일한 seam이다.
- 라이브러리에 없는 것은 우리 층에서 만든다: **타임아웃**은 Task cancel 조합(spike 검증 패턴). 취소는 자식 프로세스를 죽이지만 그 결과가 평범한 `signaled` 결과로 돌아오므로, 마감 시각이 지났다는 사실을 래치로 따로 들고 판정한다.
- **에러 2층**을 타입으로 가른다. `ProcessError`(spawn 실패·타임아웃)는 인프라 장애이고, 도메인 실패는 exit code + stderr를 해석해 만드는 `DomainError`이며 Remediation을 필드로 갖는다. 이 구분이 exit code 1과 2를 가른다(#15 user story 52).
- 계약은 **collected output만**. streaming 메서드는 넣지 않는다 — `up`의 xcodebuild가 실제로 요구할 때 추가한다.

### 후속 노트 (#13, #42)

**collected-only는 streaming에 대한 결정이다.** `spawnDetached`는 출력을 어떻게 읽느냐가 아니라 자식이 우리보다 오래 사느냐의 문제이고, Metro가 `up` 종료 후에도 살아 있어야 한다는 #13의 요구로 추가했다. **streaming 금지는 그대로다.** 구현은 Foundation `Process`이며(swift-subprocess의 API는 전부 자식을 끝까지 돌리는 형태라 detached를 낼 수 없다), 격리 원칙대로 그 사실도 `ProcessRunner.swift` 안에서 끝난다.

### 후속 노트 (#44, #56)

**"`up`의 xcodebuild가 실제로 요구할 때"가 왔다.** 위 결정이 예약해 둔 조건이 dogfooding 라운드 1(#44)에서 발동했다 — mattermost-mobile의 최초 빌드는 출력이 **약 39 MiB**(실측 40,859,199 바이트)라 4 MiB 상한을 18초 만에 넘기고, 멀쩡한 빌드가 exit 2로 죽었다. 상한을 올리는 길은 40 MiB를 문자열로 들고 있는 길이다.

그래서 collected-only를 **`build` 한 곳에서** 연다. 판단이 뒤집힌 것이 아니라 조건이 찼다.

- 축은 **출력 목적지**다. `ProcessCommand.output`이 `collected`(상한 있는 문자열) 또는 `streamed(to: 파일)` 중 하나를 든다. "무엇이 흐르는가"가 아니라 "어디로 가는가"가 축이고, 그래서 프로토콜 메서드가 늘지 않는다.
- **줄 콜백은 커맨드가 아니라 `run(_:onLine:)`의 파라미터다.** 커맨드는 로그에 찍히고 fake의 fixture 키가 되는 값이라 클로저를 품으면 안 된다. 기존 호출부는 프로토콜 확장의 `run(_)`이 그대로 받는다.
- **줄 나누기는 러너의 일이다.** 파이프는 청크로 오고 줄 중간에서 끊긴다. 호출자에게 넘기면 fake마다 같은 버그를 재현해야 한다. 파일에는 받은 바이트 그대로, 콜백에는 완전한 줄만.
- **무엇이 의미 있는 줄인가는 호출자의 일이다.** `error:` 우선은 xcodebuild에 대한 지식이지 프로세스에 대한 지식이 아니다. 러너가 그것을 알기 시작하면 다음은 gradle 필터가 들어온다.
- 두 스트림은 **한 파일에 도착 순으로** 합친다(`combinedOutput`과 같은 철학). 정확한 인터리브 순서는 보장하지 않는다.
- 로그 파일은 **성공해도 남기고 상한이 없다**. temp이고 프로젝트당 한 파일이며, 상한은 이 노트를 쓰게 만든 바로 그 사고를 다시 부른다. 경로는 실패 시 remediation에, 성공 시 `--json`의 `result.buildLog`에 실린다.
- **collected의 4 MiB 상한은 그대로 둔다.** 알려진 유일한 초과 사례가 축을 옮겼고, 남은 호출들의 실측 최대는 58 KB다. 상한을 지우면 다음 사고가 문장 대신 OOM으로 온다.
- 구현은 swift-subprocess의 `.sequence` 출력이다(1.0에 있다). `.fileDescriptor`로 커널에 직접 쓰게 하는 길은 줄을 보려면 그 파일을 다시 tail 해야 해서 부분 줄 문제를 파일 쪽에서 되풀이한다.

`spawnDetached`가 "자식이 우리보다 오래 사는가"였다면 이것은 "출력을 들고 있는가 흘려보내는가"다. 격리 원칙은 그대로 — 두 결정 다 `ProcessRunner.swift` 안에서 끝난다.

## 결과

- 의존이 바뀌거나 버려질 때 수정 범위가 한 파일이다. 이것이 미성숙한 의존을 받아들인 대가로 산 것이다.
- 대신 얇은 wrapper 하나가 영구히 존재한다. `ProcessRunner`가 단순 위임처럼 보인다는 지적은 이 ADR을 근거로 기각한다 — 위임이 목적이 아니라 격리가 목적이다.
- 플랫폼 차이도 이 파일이 흡수한다. `standardOutput`이 Darwin에서 `String?`, Linux에서 `String`인 차이가 헬퍼 하나로 여기서 끝난다(ADR-0001 참조).
- 절대경로 실행은 지원하지 않는다. `Executable.path(_:)`가 `System.FilePath`를 요구하고, 그것을 import하면 ADR-0001이 깨진다.

## 대안

- **Foundation `Process` 직접 사용.** 취소·async 처리가 나쁘고, 결국 같은 wrapper를 우리가 더 많이 써야 한다.
- **wrapper 없이 swift-subprocess를 직접 호출.** 코드는 줄지만 테스트 seam이 사라지고, 의존 교체 비용이 호출 지점 전체로 퍼진다. 미성숙한 의존에 대해 정확히 하면 안 되는 선택이다.

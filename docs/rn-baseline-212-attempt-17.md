# #212 attempt-17 — absolute Metro audit 호출

검증일: 2026-10-11, Asia/Seoul. 상태: **부분 검증. 관측 guard의 필수 STOP.**

[요약](./rn-baseline-212.md)과 [공개 manifest](./evidence/212/attempt-17/manifest.json)를 함께 읽는다.
현재 정책은 [ADR-0029](https://github.com/minjunkim-dev/mobile-runtime/blob/ad301bbe77a5245fbc04ccd26a82e1c96616dddc/docs/adr/0029-rn-observer-executable-errno.md)까지다.
정책 main은 `ad301bbe77a5245fbc04ccd26a82e1c96616dddc`다.
PR248 exact head의 CI38129147071 네 job은 SUCCESS다.
이번 routine helper 정정은 caller의 audit argument를 정확한 absolute 경로로 바꾼다. 입력 정책은 바꾸지 않는다.

최소 source는 `b62e3a4d5e7cfc05d7d948a5a4e30f0cc6a82bb4`다.
Mattermost 입력은 `c2fe3beda22befd2178dce431793c09111ed903e`다. Mattermost clone은 시작하지 않았다.
새 내장 최소 clone과 output은 독립 경로다. 이전 node_modules·vendor·Pods·build를 복사하지 않았다.
원본 source·lock·plugin·도구 버전·argv·env·query·sampling·delay·guard를 유지했다.
최소에 Mattermost checksum·생성 target 예외를 적용하지 않았다.

1. path/공간/resource guard와 최소 clone·checkout·원본 npm이 통과했다.
2. Metro helper 호출 전에 resolved interpreter token과 hash를 기록했다. `-B`와 정확한 absolute audit argument도 기록했다.
3. caller17의 actual Path.cwd 표현은 caller16의 요청 workdir 표현과 canonical 경로가 같다. 특정 다른 worktree 경로로 승계하지 않는다. source cwd와 원본 Metro argv를 변경한 뜻이 아니다.
4. 원본 early Metro helper는 exit0이다. 실제 HTTP200과 body receipt, own process·port를 확인했다. hook redirect는 false다.
5. 소유 Metro를 Ruby 준비 전에 종료했다. 기존 Watchman을 제어하지 않았다.
6. 원본 mise 선택·metadata·Ruby facts·공식 gem spec이 통과했다. clone-local installer·activation·bootstrap도 통과했다.
7. 별도 frozen 선택 producer/read 접합, 원본 Bundle, gem actual, Bundle exec 내부환경이 통과했다.
8. 원본 `pod install --deployment`는 exit0이다. observer guard는 false다. frozen 준비 helper는 exit1이다.
9. 모든 후속 실제 실행을 중단했다. 같은 attempt에서 helper·source·조건을 바꾸거나 재실행하지 않았다.

원본 runner14개는 모두 exit0이다. 준비 guard는13PASS/1FAIL이다.
Ruby receipt는8개다. 실제 관측은 총8282개다. 읽기 관측 오류는0개다.
Pod receipt는7712개 관측이다.7216개는 기존 predicate를 만족한다.
496개는 `actualCwd == requestedCwd == event.cwd` 한 항목만 다르다.
다른 predicate와 context match는 통과했다.
저장된 값의 재평가는 live query를 추가하지 않았다.
원래 CocoaPods 기능과 source/runtime code 대응은 읽기 근거다. 실제 stack의 동적 원인 proof는 아니다.
CWD 판정을 바꾸는 정책은 미확정이다. 이번 결과를 PASS로 바꾸지 않는다.

기존 executable query는 실제 observer 경로에서 실행했다. 읽기 관측 오류는0개다.
실패 반환에 대응하는 errno enum은 관측하지 않았다. get_errno 실패 분기도 이 시도에서 관측하지 않았다.
errno 효과와 과거 unknown 원인 해결을 주장하지 않는다.
원본 tool 실패, source 실패, 제품 실패, native 실행 실패와 관측 guard STOP을 구분한다.
실제 PID·절대 경로·session·환경·argv 본문·예외 원문은 공개하지 않는다.

사후 strict 감사는 tracked55개·세 lock·raw byte·index/flags·kind·Git 실행 mode PASS다.
metadata·host·shared·private 사후 감사도 PASS다. shared 변경은0개다.
최종 equality는 일시 write 부재를 증명하지 않는다. 내부 reshim 횟수와 exit도 NOT_MEASURED다.
실제 shared 감사 함수는 PASS receipt를 기록했다.
작성자 요약 wrapper는 반환 tuple을 dict로 읽어 TypeError를 냈다. 별도 진단으로 보존했다.
감사 재실행과 원본 receipt 변경은 없다.
root의 공개 CI extractor와 shared hash lookup 읽기 진단은 원본 자료에 보존했다. 실제 조건 변경이 아니다.

소유 Metro는 Ruby 준비 전에 종료했다.
Simulator/Emulator boot·앱 설치·reverse·Gradle/native는 미시작이다.
기존 두 Simulator·GUI·Watchman·비소유 process와 AVD data를 보존했다.
사후 resource 조회는 PASS다. 전역 선택·권한·daemon을 바꾸지 않았다.
root는2026-10-11T10:48:00Z에 RELEASED를 확정했다.
최초 grant와 반환 전 cleanup의 rootReleaseConfirmed=false를 보존했다. 별도 최종 receipt와 구분한다.
현재 실제 권한은 없다.

최소 iOS/Android native·install·launch·첫 화면, Mattermost baseline, 두 독립 fresh는 NOT_STARTED다.
첫 화면 PNG·앱 ZIP·APK는0개다. known-good 완성이나 fresh 인계 완료를 선언하지 않는다.
실제 Runstir 실행은 NOT_AUTHORIZED다.

[공개 manifest](./evidence/212/attempt-17/manifest.json)는 원본 전체217개 파일의 hash와 size만 연결한다.
base214개와 core3개다. index는 자기 파일을 제외한216개다.
log27개와 생성 bytecode9개를 포함한다. runner result와 runner log는 각각14개다.
원본 helper57개/index58개는 불변이다. source-only 메모리1831개와 syntax29개를 통과했다.
이전 attempt16·15·14·13·12의 전체 index 대상 byte를 재확인했다. 변경은 없다.
원본 hash와 공개 비식별 byte의 hash를 구분한다.

| 원본 core | SHA256 |
| --- | --- |
| REPORT.md | 6abff2ed7e8a0c7233d3c778035a21369841a1e16012dfb44bf71b12076bd181 |
| manifest.json | 0ffe148abbdca672c951dea057bc80c4949aa71c17d092ddcbd9424a7a395274 |
| SHA256SUMS | 2df8285e96a9c4886b5069e2f661a3c267a1f7a4bafa17578f18e1083441caf2 |
| 최초 Pod result | 3ee1fd2776d07abe87a0b75adf6344481edb592385e314443dba759fa2e61bba |
| root release receipt | b39bbe4f9b30b000551e538b43bbbcd2bf5232527cc5e2205bce29af324932bb |

원본 packet은 두 독립 검토에서 material finding0을 확인했다. 공개 문서는 두 독립 검토에서 material finding0을 확인했다. publicationReady=true다.
새 공개 head·CI는 CI_PENDING이다.
다음 ADR-0030은 proposal/USER_Q1_PENDING이다. 채택 정책이 아니다.
새 attempt artifact는 미확정이다. stage 판정 변경은 새 결정을 요구한다.
원인 해결과 성공을 보장하지 않는다.
#212와 PR236은 OPEN이다. 종료 참조를 추가하지 않는다. PR236을 병합하지 않는다.

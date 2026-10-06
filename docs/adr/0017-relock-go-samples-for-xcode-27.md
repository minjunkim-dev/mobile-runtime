# ADR-0017: Go 게이트 표본을 Xcode 27 기준으로 다시 고정한다

- 상태: 채택
- 날짜: 2026-10-06
- 관련: #156 · ADR-0008 · ADR-0012 · ADR-0016

maintainer는 Go 게이트의 host를 Xcode 27로 통일하기로 했다. 2027년에는 Xcode 27 이상이 필수가 된다. Xcode 26.x를 추가로 설치해 옛 표본을 살리는 일은 곧 버려질 검증 조합에 투자하는 일이다.

잠긴 mattermost-mobile `10207015`은 Xcode 27.0에서 `mobile` 없이도 빌드되지 않는다(#155, [up 라운드 4](../dogfooding/up-round-4.md)). Pods resource bundle target의 deployment target이 Xcode 27의 허용 범위 밖이다. ADR-0016은 tracked 파일 수정을 금지한다. 따라서 이 표본은 Xcode 27 검증 조합에서 known-good 표본이 아니다. Rainbow `29eade9a`와 Joplin `2654b336`은 Xcode 27에서 측정하지 않았다.

ADR-0008은 실패를 관측한 뒤 표본을 교체하면 게이트가 다른 질문이 된다고 보았다. ADR-0012는 known-good baseline 전의 부적격 표본은 교체할 수 있다고 정했다. 이 ADR은 두 결정을 함께 지킨다. 교체 대상을 실패한 표본 하나로 고르지 않는다. 실행 전에 정한 규칙 하나로 세 repo를 모두 다시 고정한다.

## 결정

- Go 게이트의 검증 조합은 Xcode 27.0 / iOS 27.0 simulator runtime이다. React Native 버전은 각 표본의 선언을 따른다.
- 세 repo(mattermost-mobile, Rainbow, Joplin)와 3/3 기준은 바꾸지 않는다. ADR-0016의 사람 준비 범위와 Go round 규칙도 그대로다.
- 재고정 규칙: 각 repo의 default branch에서 first-parent를 따라 committer date가 `2026-10-06T00:00:00Z` 이하인 첫 commit을 고른다. repo마다 후보는 하나다.
- 후보는 known-good baseline으로 확인한다. `mobile` 없이 repo가 문서화한 iOS 개발 절차로 build·install·launch·첫 화면에 도달하고 tracked 파일을 바꾸지 않아야 한다. 사람의 준비는 ADR-0016 범위만 허용한다.
- baseline이 host 준비 누락으로 실패하면 준비를 보완하고 같은 후보로 다시 확인한다. 후보 자체가 실패하면 다른 commit을 찾지 않는다. 결과를 기록하고 그 repo의 처리는 maintainer가 별도 결정으로 정한다.
- 이 ADR이 고정한 SHA가 ADR-0008·ADR-0016의 잠긴 SHA를 대체한다. 옛 SHA의 실행 결과(라운드 1–4)는 새 Go round에 합산하지 않는다.

## 후보 (규칙 적용 결과)

| repo | default branch | 후보 SHA | committer date | baseline |
| --- | --- | --- | --- | --- |
| `mattermost/mattermost-mobile` | `main` | `62f18af38254a9acf74390b3815c2a11852b7bc5` | 2026-10-05T11:10:40Z | 미측정 |
| `rainbow-me/rainbow` | `develop` | `a64ecce56fe1c41551d9eb1bf354a698114be4f0` | 2026-10-05T23:18:52Z | 미측정 |
| `laurent22/joplin` | `dev` | `aaa6f8e3ae206555fc5de7dbd82a8bcfe0d2d5cc` | 2026-10-05T13:09:44Z | 미측정 |

## 대안

- **Xcode 26.x를 추가 설치하고 옛 SHA 유지**: 기각. 2027년에 버려질 검증 조합이다.
- **실패한 mattermost-mobile만 교체**: 기각. 실패를 본 표본만 고르면 ADR-0008이 막은 사후 교체가 된다.
- **`mobile`이 deployment target을 덮어쓴다**: 기각. repo가 선언하지 않은 빌드 설정을 `mobile`이 바꾸게 된다. 그 다음 Xcode 27 비호환이 있는지도 알 수 없다.
- **후보가 실패하면 이전 commit을 차례로 시도**: 기각. 통과하는 commit을 찾을 때까지 고르는 일은 결과를 보고 표본을 고르는 일이다.

## 결과

- 현재 판정은 계속 **No-Go**다. 이 ADR은 표본을 다시 고정할 뿐 새 성공 근거를 만들지 않는다.
- 세 repo의 조사 실행은 새 SHA로 다시 한다.

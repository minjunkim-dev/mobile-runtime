# ADR-0005: remediation은 호스트를 측정해서 만들고, 증명하지 못한 명령은 내지 않는다

- 상태: 채택
- 날짜: 2026-08-20
- 관련: #27, #33, #36, #37 · ADR-0004(등급 정책)

---

## 배경

Dogfooding에서 같은 규칙을 세 번 어겼다.

1. #27은 Node·Ruby 버전 불일치에 `nvm use`와 `rbenv install`을 고정해, 그 도구가 없는 호스트에 실행되지 않는 명령을 냈다.
2. #33은 PATH에 있지만 버전을 못 내는 도구에 `corepack enable`, `bundle install`, `mise use ruby@…`를 붙였다. 명령은 실행돼도 관측된 실패 원인과 무관했다.
3. #36은 틀린 명령을 뺀 뒤의 빈자리를 드러냈다. rainbow에서는 mise가 trust되지 않은 설정을 거부했지만, 세 Check 모두 소유자를 말하지 않아 사용자가 `mise trust`를 복구 명령으로 얻지 못했다.

Remediation의 명령은 복붙 가능해야 한다. 실행 가능성이나 현재 실패와의 관련성을 호스트에서 확인하지 못했다면, 틀린 명령보다 명령이 없는 편이 낫다.

## 결정

### 명령은 관측된 소유자와 상태에서만 만든다

도구가 PATH에는 있지만 버전을 못 내는 `.unreadable` 분기에서 `which <executable>`를 한 번 실행한다. 결과 경로에 드러난 shim 소유자만 mise / asdf / rbenv / rvm으로 판정한다. 도구의 stderr는 소유자 판정에 쓰지 않는다.

- 소유자를 판정하지 못하면 기존의 일반 summary를 유지하고 명령을 내지 않는다.
- nvm은 shim 없이 PATH를 바꾸므로 이 측정으로 판정하지 않는다. 이는 받아들인 한계다.
- `.unreadable`이 된 기존 Check가 이 측정을 소유한다. 새 Host check나 결과를 접는 renderer 규칙은 만들지 않고 Check id 계약을 유지한다.

### mise에만 복구 명령을 낸다

mise shim이면 앵커 디렉터리, 워크스페이스 루트 순으로 `mise.toml`, `.mise.toml`, `.config/mise/config.toml`을 찾는다.

- 설정을 찾으면 `mise trust <설정 파일의 디렉터리>`를 낸다. 경로는 실행 디렉터리를 기준으로 표시한다(#35).
- 설정을 찾지 못하면 `mise doctor`를 낸다.
- `.tool-versions`는 asdf와 공유하므로 mise 소유의 근거로 쓰지 않는다.

asdf / rbenv / rvm shim이면 summary에 소유자만 넣는다. asdf에는 `doctor`가 없고 `rbenv doctor`는 코어 명령이 아니므로, 확인되지 않은 대체 명령을 만들지 않는다.

### 등급은 바꾸지 않는다

소유자를 알아냈다고 도구가 사용할 수 있게 되지는 않는다. 프로젝트 요구가 확정된 도구의 `.unreadable` 결과는 ADR-0004대로 `error`를 유지한다. 한 원인에 여러 Check가 각각 error를 내는 중복도 유지한다. 각 Check는 자기 도구의 상태를 보고하고 같은 복구 명령을 가리킨다.

## 결과

- Remediation은 설치 관례나 stderr 문구를 추측하지 않고, 실행 경로와 커밋된 설정 파일이라는 호스트 사실에서만 명령을 만든다.
- rainbow의 mise trust 실패는 각 관련 Check가 `mise trust`를 안내하고, mise 설정이 없는 mattermost-mobile은 `mise doctor`를 안내한다.
- 새 Check 없이 기존 JSON id와 등급 계약이 유지된다.

## 대안

- **버전 관리자별 일반 복구 명령을 만든다.** 관리자가 설치됐다는 사실만으로 현재 실패에 맞는 명령임을 증명할 수 없어 기각한다.
- **stderr에서 `mise trust`를 파싱한다.** 외부 도구 문구에 계약을 묶고 다른 소유자를 일반화하게 되므로 기각한다.
- **공통 원인 Check를 추가하거나 renderer에서 중복을 접는다.** 관측 사례 한 건을 위해 Check id와 등급 의미를 다시 정의해야 하므로 기각한다.

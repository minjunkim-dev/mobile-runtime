# #212 mise identity 단독 진단

검증일: 2026-10-15, Asia/Seoul.
기준 main: `af7971f68e7e9860a73824f7bf59d9b6ccc3df1e`.
범위: Ruby 준비 전 파일 identity assertion만 읽기 전용으로 재현한다.

## 결론

현재 반복 재현의 원인은 **mise 파일 bytes 변경에 따른 고정 SHA 불일치**다.
E20 helper는 이전 `d225…` identity를 요구한다.
현재 같은 선택 경로의 파일은 `f517…` identity다.
현재 파일에 E20 assertion을 적용하면 FAIL이다.
같은 파일에 이미 채택한 ADR-0032 identity를 적용하면 PASS다.
이번 명령의 내부 측정 시간은 `0.134`초다.
명령 전체는 10초 안에 종료했다.

| 분류 | 근거와 판정 |
| --- | --- |
| mise 변경 | 현재 파일 SHA가 이전 고정 SHA와 다르다. 두 번 읽은 SHA가 같다. 공식 raw asset의 SHA와 크기가 현재 파일과 같다. 현재 재현의 직접 원인이다. |
| harness 회귀 | E19·E20·E21의 `begin` 함수 AST가 같다. E20과 E21의 파일 identity 식도 같다. 이 assertion의 회귀 근거는 없다. |
| identity 정의 오류 | regular file·non-symlink·exact SHA 조건은 그대로다. ADR-0032가 새 SHA를 이미 채택했다. E20의 역사 pin과 새 준비 입력을 혼동하지 않는다. |
| RN 표본 결함 | 이 진단은 RN source나 Ruby consumer를 실행하지 않는다. 이 assertion 실패를 RN 표본 결함으로 분류할 근거는 없다. |

변경 주체·변경 시점·설치 방법은 확인하지 않았다.
현재 재현은 E20 실패 순간의 개별 short-circuit operand를 소급해서 증명하지 않는다.
[E20 공개 기록](https://github.com/minjunkim-dev/mobile-runtime/blob/4c41ea6bce70a4b897c526a9544edc5aa7a87712/docs/rn-baseline-212-attempt-20.md)의 역사 관측 한계를 유지한다.
[ADR-0032](../adr/0032-rn-mise-official-asset-identity.md)의 역사 실패와 현재 단독 재현을 구분한다.

## 단독 재현 명령

macOS에서 기존 선택 경로의 파일만 읽는다.
`<HOME>`은 출력의 개인 경로를 가린 표기다.
원본 helper를 import하지 않는다.
원본 `begin`을 호출하지 않는다.
원본 compound assertion 식만 실행한다.
`-I -S`는 `PYTHONOPTIMIZE`와 `site` 자동 로드의 영향을 배제한다.
이 옵션이 없으면 `PYTHONOPTIMIZE=1`이 두 assertion과 마지막 검증을 제거한다.
수정 전 이 환경에서 두 결과가 PASS로 출력됐고 종료 코드는 `0`이었다.
수정 후 같은 환경에서도 E20 FAIL과 ADR-0032 PASS를 확인했다.
9초 alarm은 이 단독 진단의 상한이다.
baseline의 timeout·observer·guard를 바꾸지 않는다.

```sh
python3 -I -S - <<'PY'
import hashlib, pathlib, signal, time
signal.alarm(9)
t = time.monotonic()
p = pathlib.Path.home() / '.local/bin/mise'
before = p.lstat()
observed = []
def digest(data):
    value = hashlib.sha256(data).hexdigest()
    observed.append(value)
    return value
results = []
for label, expected in (
    ('E20', 'd225d1c8ef2934a86be93692a19365fb1df1cd6958a0af7b85909514e0c608a7'),
    ('ADR0032', 'f5171e341518a57e8c4e9280e28443e35d66212c51164c83be76794e0a78b014'),
):
    try:
        assert p.is_file() and not p.is_symlink() and digest(p.read_bytes()) == expected
        passed = True
    except AssertionError:
        passed = False
    results.append(passed)
    print(f'{label} compound_assertion={"PASS" if passed else "FAIL"}')
after = p.lstat()
stable = all(getattr(before, k) == getattr(after, k) for k in ('st_dev', 'st_ino', 'st_size', 'st_mtime_ns', 'st_ctime_ns'))
print('path=<HOME>/.local/bin/mise')
print(f'is_file={p.is_file()} is_symlink={p.is_symlink()} size={after.st_size}')
print('observed_sha256=' + ','.join(dict.fromkeys(observed)))
print(f'before_after_metadata_equal={stable} both_reads_equal={len(observed) == 2 and observed[0] == observed[1]}')
print(f'elapsed_s={time.monotonic() - t:.3f}')
assert results == [False, True] and stable and len(observed) == 2 and observed[0] == observed[1]
signal.alarm(0)
PY
```

실제 redact 출력:

```text
E20 compound_assertion=FAIL
ADR0032 compound_assertion=PASS
path=<HOME>/.local/bin/mise
is_file=True is_symlink=False size=127277984
observed_sha256=f5171e341518a57e8c4e9280e28443e35d66212c51164c83be76794e0a78b014
before_after_metadata_equal=True both_reads_equal=True
elapsed_s=0.134
```

명령 종료 코드는 `0`이다.
이는 E20 FAIL과 ADR-0032 PASS의 예상 조합을 확인한 진단 성공이다.
E20 baseline의 성공을 뜻하지 않는다.
앞뒤 metadata equality는 중간 변경이 전혀 없었다는 원자적 증명이 아니다.
file kind와 digest 출력도 E20 실패 순간의 snapshot이 아니다.

## 원문 대조

외부 evidence root의 E19·E20·E21 helper를 읽었다.
각 경로는 역할 이름으로만 기록한다.
E20과 E21 helper의 SHA는 각 `finished-preparation-v2-batch.json`의 `files` 값과 일치했다.

| 입력 | SHA-256 또는 값 |
| --- | --- |
| E19 `ruby_preparation.py` | `f4bec1bc588eba3f2aea61187eda638cf55c7f88bad7e5fe245544a9b7d63032` |
| E20 `ruby_preparation.py` | `1ba56d2bdaecce6aadb4ec1ad233f0bea6e573e6767d65b1035a9de8dc44c104` |
| E21 source-only `ruby_preparation.py` | `8ae6f86a45669123d2e3717daf2a3470499b5b7c6ad452004cbecb475f9aa108` |
| 세 helper의 `begin` AST SHA | `ca0d8488b45cd860a5991bb961c99c716b37d3c3051274c819bc8290d100c003` |
| E19 실제 context의 `miseSha256` | `d225d1c8ef2934a86be93692a19365fb1df1cd6958a0af7b85909514e0c608a7` |
| E19 context 파일 SHA | `c68aa32eec4f243cea13b1370edc3a3bfbcec0be7174a59fa33dea0f21e33d27` |

AST SHA는 Python `ast.dump(node, include_attributes=False)`의 UTF-8 SHA-256이다.
E19·E20 assertion은 `ruby_preparation.py:190`에 있다.
E21 source-only assertion은 `ruby_preparation.py:191`에 있다.
E20과 E21의 전체 module AST가 같다는 주장은 하지 않는다.
차이는 `MISE_SHA`, `POLICY_MAIN`, `DOC_HASHES`, `authority_matches`, `require_lease`다.
정책 binding 변경과 identity 변경을 구분한다.

[공식 release API](https://api.github.com/repos/jdx/mise/releases/tags/v2026.10.7)를 이번 진단에서 다시 읽었다.
raw asset `mise-v2026.10.7-macos-arm64`의 게시 digest는 `sha256:f5171e341518a57e8c4e9280e28443e35d66212c51164c83be76794e0a78b014`다.
게시 크기는 `127277984` bytes다.
현재 파일의 두 값과 일치한다.
archive digest를 내부 binary digest로 사용하지 않았다.
binary를 다운로드하거나 실행하지 않았다.

## 수리 범위와 후속 조건

E20 helper와 봉인 packet을 수정할 이유는 없다.
기존 pin의 FAIL을 보존한다.
새 준비 입력에는 ADR-0032가 채택한 `f517…`와 기존 E21 source-only helper를 사용한다.
새 SHA를 이번 진단에서 자동 채택한 것은 아니다.
새 helper의 `begin`과 exact SHA guard를 완화하지 않는다.
현재 파일이 다시 달라지면 STOP한다.
다른 mise 설치나 Homebrew 경로로 대체하지 않는다.
RN 표본 수리나 표본 교체는 이 assertion의 해결 조건이 아니다.

E21 batch는 `source-only-finished`다.
`actualAuthorityGranted`, `actualRunstirAuthorized`, `rootGrantCreated`는 false다.
`I21Absent`는 true다.
이는 batch의 선언 상태다.
이번 작업은 전체 baseline attempt-21을 실행하지 않았다.
mise·Ruby·npm·Bundle·Pods·Metro·기기 명령도 실행하지 않았다.
외부 helper·binary·원본 evidence를 수정하지 않았다.

실제 baseline 재개에는 기존 fresh resource 조건과 최신 preflight 및 새 단독 lease가 필요하다.
이 진단과 문서 CI는 그 조건을 대체하지 않는다.
#212는 미완료로 유지한다.
PR #236은 병합하지 않는다.

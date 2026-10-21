# 후보 증거 검사

이 검사는 issue [#223](https://github.com/minjunkim-dev/mobile-runtime/issues/223)의 개발·테스트 증거를 연결한다.
정본은 [공동 출시 게이트 계약](../../shared-launch-gate-contract.md)과 [명세 #199](https://github.com/minjunkim-dev/mobile-runtime/issues/199)의 AC15·AC17이다.

1. [실제 unsigned 보고서](actual-179be9a/report.md)를 읽는다.
2. 담당자가 관리하는 원본 보관소를 `--private-root`에 전달한다.
3. 저장소 root에서 다음 명령을 실행한다.

```sh
python3 -I scripts/verify-release-evidence.py docs/evidence/223/actual-179be9a/manifest.json --private-root <private-root>
```

실제 원본의 무결성을 확인해도 `evidenceIntegrity=verified`, `releaseDecision=blocked`, 종료 코드 1이 예상 결과다.
서명·배포·전체 필수 행렬의 미완료를 성공으로 바꾸지 않는다. 잘못된 증거도 종료 코드 1로 차단한다. JSON의 `evidenceIntegrity`로 구분한다.
종료 코드 0은 선언한 필수 결과·후보 배포 상태·보관된 같은 source CI를 모두 통과한 actual bundle에만 사용한다. 공개나 병합을 승인하지 않는다.
fixture는 내부 판정 경로가 pass여도 항상 출시를 차단한다.

## 자료 계약

`manifest.json`의 candidate는 원본 후보 JSON과 같아야 한다. 원본 `ciRun`을 수정하지 않는다. `sourceCI`로 별도 같은 source receipt를 연결한다.
`documents`는 tuple·결과 목록·제한 원본 목록·Markdown 보고서의 SHA256을 고정한다.
제한 원본은 원본 index의 항목과 연결한다. index 전체를 따라 읽지 않는다. 제한 원본 목록에 명시한 파일만 읽는다.

검사는 상대 경로·symlink·중복 key/identity/ref·다른 후보·참조 누락·checksum 불일치를 차단한다.
JSON은 파일당 1 MiB, 깊이 32, 항목 20,000개, 문자열 16,384자로 제한한다. JSON 외 파일은 파일당 512 MiB로 제한한다. 제한 원본 총합은 2 GiB다.
파일을 실행하거나 압축을 풀거나 네트워크를 호출하지 않는다. 파일과 보고서를 쓰지 않는다. 오류에 원본 내용이나 호스트 경로를 출력하지 않는다.
인증·세션·credential·private key·환경 파일 이름은 열기 전에 거부한다. 이 이름 검사는 임의 파일에 숨긴 비밀값의 부재를 증명하지 않는다. 수집 목록과 공개 내용을 검토한다.

모든 AC01~AC19 gate와 선언한 requirement의 결과가 필요하다. terminal attempt가 pass이고 미검증 목록과 필수 unknown이 없어야 한다.
각 attempt는 `observedAt`과 비식별 `executor`를 기록한다. `observedAt`은 timezone을 포함한 ISO 8601 초 단위 시각을 쓴다. 확인하지 못한 값은 `unknown`으로 기록하며 필수 시도의 출시 판정을 차단한다.
재검증은 새 attempt identity를 쓴다. `supersedes`는 같은 requirement의 직전 attempt를 가리킨다.
이전 결과를 인계받으면 checksum을 고정한 `priorResults`를 유지한다. 검사는 해당 snapshot의 요구사항·attempt를 그대로 보존하는지 검사한다.
후보나 tuple 입력이 바뀌면 새 bundle을 만든다. 이전 bundle과 Git 기록을 보존한다.

자동 검사는 선언한 요구사항만 판정한다. AC별 세부 시나리오의 완전성·실제 관측·원본 보관 권한·화면 비식별은 독립 리뷰가 필요하다.
이미 서명됐다는 문자열이나 CI receipt만으로 실제 서명·기기·배포 검증을 대신하지 않는다.

## 회귀 검사

```sh
python3 -m unittest discover -s scripts/source-only -p test_release_evidence.py -v
python3 -m unittest discover -s scripts/source-only -p 'test_*.py'
python3 -O -m unittest discover -s scripts/source-only -p test_release_evidence.py
```

테스트는 public CLI를 subprocess로 실행한다. fixture는 임시 폴더에서 만든다. 실제 원본 검사는 위 명령으로 별도 수행한다.

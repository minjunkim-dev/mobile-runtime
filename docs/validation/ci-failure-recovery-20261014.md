# CI 실패·복구 격리 검증

검증일: 2026-10-14 KST.
이 문서는 병합하지 않는 검증 PR의 기록이다. 제품 변경이나 배포 계획이 아니다.

## 고정한 기준

- 저장소: `minjunkim-dev/mobile-runtime`.
- 기준 main SHA: `2f58a6b9ae410541fbdb3c7f5e4955f8bdb02005`.
- 결함 주입 범위: `scripts/validate-release-input.py`의 alpha 버전 형식 검사 한 줄.
- 기준 검사: 기존 Draft 입력 동작 검사 7개 통과.

## 검증 계획

1. 검증 브랜치에서 정상 alpha 버전을 잘못 거부하도록 형식 검사에 결함을 주입한다.
2. 실제 PR CI의 기존 동작 검사가 실패하는지 확인한다. 실패 run·attempt·head와 로그를 기록한다.
3. 실패를 로컬에서 재현한다. 형식 검사만 기준 main의 정상 구현으로 복구한다.
4. 같은 기존 검사와 저장소 검사를 실행한다. 테스트와 workflow는 변경하지 않는다.
5. 복구한 최종 전체 diff를 별도 Standards·Spec 컨텍스트에서 리뷰하고 필수 CI를 확인한다.

## 실제 실패와 로컬 복구

- 실패 head: `6dbcbc800d2513ac7e8b57ac802e53c2c075a557`.
- 실패 run: [38534325261](https://github.com/minjunkim-dev/mobile-runtime/actions/runs/38534325261), attempt `1`, 최종 결과 `failure`.
- `Repository hygiene`의 기존 `test_alpha_version_and_full_sha_are_accepted`에서 정상 alpha 입력이 거부됐다. 필수 집계 `CI`도 실패했다.
- CI 로그에 `ValueError: version must be an alpha version, e.g. 0.1.0-alpha.5`와 `FAILED (errors=2)`가 기록됐다.
- `gh run view 38534325261 --repo minjunkim-dev/mobile-runtime --log-failed` 출력 SHA-256: `190e88d1ddf1c714f4e15e92c6068fa5016f96f784b8e9b7058f7c2d3ccd5836`.
- 같은 기존 Draft 입력 검사로 로컬 실패를 재현했다. process exit code는 `1`이었다.
- 형식 검사의 `alpha-smoke`를 정상 `alpha`로 복구했다. 복구한 helper는 실험 기준 main과 byte가 같다.
- 같은 기존 Draft 입력 검사 7개가 로컬에서 다시 통과했다. 테스트와 workflow는 변경하지 않았다.

## 안전 범위와 현재 상태

실제 CI 실패와 로컬 재현·복구를 확인했다. 최종 독립 리뷰와 복구 head의 원격 필수 CI는 별도로 확인한다.
GitHub Release와 Draft Release를 생성하거나 배포하지 않는다.
검증 PR은 Draft 상태로 유지한다. 자동 병합을 예약하거나 PR을 병합하지 않는다.
main과 기존 CI·브랜치 보호·Bugbot 수동·Autofix·On-demand 설정을 변경하지 않는다.
최종 head의 리뷰와 원격 CI 결과는 PR Evidence와 별도 검증 보고서에 기록한다.

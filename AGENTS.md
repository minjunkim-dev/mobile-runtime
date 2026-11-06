# Runstir

프로필: 1인

Reproducible mobile development runtime. North Star: `git clone → mobile up`.

Status: iOS React Native MVP implemented. Private iOS internal-alpha execution
is specified in [issue #83](https://github.com/minjunkim-dev/mobile-runtime/issues/83),
following the closed [decision map #79](https://github.com/minjunkim-dev/mobile-runtime/issues/79).
Current decisions live in `CONTEXT.md` and `docs/adr/`.
[Wayfinder Map: MVP 스펙 (Phase 0~3)](https://github.com/minjunkim-dev/mobile-runtime/issues/1)
is the closed historical MVP map.

## Shared instructions

This file is the shared project instruction source for coding agents.
Do not maintain separate tool-specific project instruction files.
GitHub settings and the read-only audit follow `docs/REPOSITORY_SETUP.md`.

## Agent skills

### Issue tracker

GitHub Issues on `minjunkim-dev/mobile-runtime`, driven by the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical roles, each label string equal to its name. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.

### Pull requests

Follow `docs/agents/review.md` for independent review, direct fixes, final-head verification, and merge risk. Reviewers read `docs/coding-standards.md`; do not inline the standards here.

The agent merges its own easy-to-reverse pull request (`Door: 되돌리기 쉬움`) after the ticket's verification, independent review, and the required checks on the final head. `.github/repository-settings.json` records `CI` and `Review status` (`app_id` 15368, `strict: true`). Until the owner applies that record from a Mac, the enforced check is `CI`. After the apply, every pull request except a Dependabot version-only pull request also needs an owner-posted `review/independent` status, and `review/security` when the diff touches the trust boundary. The agent does not post those statuses. Hard-to-reverse (`Door: 되돌리기 어려움`) or broad-impact changes require human approval of that final head. Green CI does not replace measurements required by the ticket. `Door:` 값은 `되돌리기 쉬움` 또는 `되돌리기 어려움`이다. 옛 `양쪽 문`/`한쪽 문`과 `한쪽 문 승인: <sha>`는 deprecated이고 검사기가 같은 의미로 받는다.

### 작업 진입

작업 진입·초기 설정 확인·명세와 티켓의 통합: [개발 절차](docs/agents/development.md)를 읽습니다. 작은 수정에는 전체 명세 절차를 강제하지 않습니다.

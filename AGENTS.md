# Runstir

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

The agent merges its own two-way, narrow-impact pull request after the ticket's verification, independent review, and required `CI` check pass on the final head. One-way or broad-impact changes require human approval of that final head. Green CI does not replace measurements required by the ticket.

### 작업 진입

작업 진입·초기 설정 확인·명세와 티켓의 통합: [개발 절차](docs/agents/development.md)를 읽습니다. 작은 수정에는 전체 명세 절차를 강제하지 않습니다.

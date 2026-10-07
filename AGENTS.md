# Runstir

Reproducible mobile development runtime. North Star: `git clone → mobile up`.

Status: iOS React Native MVP implemented. Private iOS internal-alpha execution
is specified in [issue #83](https://github.com/minjunkim-dev/mobile-runtime/issues/83),
following the closed [decision map #79](https://github.com/minjunkim-dev/mobile-runtime/issues/79).
Current decisions live in `CONTEXT.md` and `docs/adr/`.
[Wayfinder Map: MVP 스펙 (Phase 0~3)](https://github.com/minjunkim-dev/mobile-runtime/issues/1)
is the closed historical MVP map.

## Agent skills

### Issue tracker

GitHub Issues on `minjunkim-dev/mobile-runtime`, driven by the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical roles, each label string equal to its name. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.

### Pull requests

The agent merges its own pull request once the ticket's verification is done (tests, review, and any measurement the ticket asks for) and the required check `CI` is green. It does not wait for a separate human approval.

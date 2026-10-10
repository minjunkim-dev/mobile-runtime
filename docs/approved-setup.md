# Approved preparation (#202)

`mobile setup` and the GUI use `PreparationExecution` in EnvironmentKit. Setup
inspects React Native iOS and Android together. `--platform` does not narrow the
preparation plan. A Flutter `pubspec.yaml` produces both platform states and an
explicit pending-provider step. Flutter provisioning is not implemented here.

## Approval and execution

1. Run `mobile setup --project PATH --plan --json`.
2. Read `plan.platforms[].checks`, `plan.steps`, and `plan.installed`.
3. Inspect the repository's dependency scripts separately.
4. Run `mobile setup --project PATH --approve PLAN_ID --trust-repository --json --progress-json`.
5. Finish reported manual steps. Inspect and approve the new plan before retrying.

The human CLI and GUI display the same observed values, required values, sources,
reuse states, change commands, and destination presence. GUI selection and the
plan button do not install dependencies. Its trust checkbox is separate from its
current-plan approval button. Licenses and administrator permissions stay manual.

The plan ID covers declarations, selected app identity, measured tool conditions and executable paths,
commands, destinations, and installed-resource presence. It excludes operation
IDs, clocks, logs, private environment files, and the process environment. A
private source snapshot detects unexpected modifications during dependency
commands. Setup reports changed paths and stops. It never restores source files.

Setup recomputes the plan before execution and after acquiring its lease. Before
each dependency command it rechecks tool versions and executable paths, Xcode selection/readiness,
project toolchain activation, dependency commands, and destination policy. A
completed locked Bundle installation may change the CocoaPods measurement; that
expected transition is excluded from later condition comparisons. Cancellation
stops new commands and preserves completed dependencies and partial-install
markers.

Existing Node and Pods alignment uses `DependenciesStage` with its setup-only
locked-alignment option. Existing build/up defaults remain unchanged. Setup
requires existing lockfiles. Bundler's own effective destination probe is the
authority. The approved `BUNDLE_PATH` policy must reproduce that destination,
including `~` expansion and Ruby's suffix. Bundle commands use `BUNDLE_FROZEN`.
Direct `pod install` and `bundle exec pod install` use `--deployment`. Unknown
destinations and source/lockfile migrations wait manually. User-declared scripts
remain separately trusted commands; their arbitrary side effects are not predicted.

The workspace identity and shared Bundle destination each have a nonblocking
process lease. Lock files live in the fixed user's cache, independent of TMPDIR.
Setup releases only its acquired leases. It never cleans another operation's
dependencies, SDKs, simulators, emulators, or runtime processes.

No TTY, `--json`, `--non-interactive`, and `--progress-json` disable input prompts.
The TTY flow requires the exact displayed plan ID and a separate `TRUST` answer.
There is no generic yes flag. JSON stdout contains one final schema-versioned
document. Progress stderr contains schema-versioned NDJSON with one operation ID
and increasing sequence numbers. Exits: 0 plan inspection or completed preparation;
1 missing approval/manual/domain failure; 2 infrastructure failure; 64 syntax;
130 cancellation. `partial` is not completed preparation.

## Verification and evidence boundary

| Acceptance | Automated evidence | Controlled local evidence |
|---|---|---|
| AC02 declarations, observations, destination, remaining/manual | `PreparationExecutionTests` checks plan-only behavior, unchanged private inputs, stale lock/destination approval, Flutter provider gaps, and dual-platform states | CLI script checks one JSON document. GUI shows observed/required/source/reuse and destination present/absent before approval. |
| AC03 cancellation, failure, retry, ownership | Fixtures check completed-resource preservation, source-change stop, tool-condition change between commands, same workspace contention, and different projects sharing one Bundle destination. Existing installations still run approved frozen alignment. | CLI script checks SIGINT, failure markers, TTY approval, and cross-process contention with different TMPDIR values. GUI reports cancelled/130 and preserves its owned dependency marker. |
| AC04 manual work and partial completion | Fixtures keep missing hosts, tool providers, licenses, trust, and migration separate. Flutter remains waiting-manual. | GUI approval without trust waits manually. Separate trust permits the owned Node alignment and reports iOS succeeded/Android waiting-manual. A changed lockfile blocks its stale approval. |

Commands: `swift test`, `swift build --product Runstir`, and
`python3 scripts/verify-setup-input.py .build/debug/mobile`. CI also runs the
existing doctor/workflow contracts and Linux Core compile.

The executable script and GUI validation use a throwaway React Native project
and a private stub PATH. Tool versions and simulator metadata come from stubs.
Only the throwaway dependency installer writes files. The GUI bundle identifier
is `dev.runstir.gui.t202`; the existing GUI and booted simulators are preserved.
These checks prove approval, display, event, exit, and ownership behavior. They do
not prove host SDK installation, a real mobile build, an app's first screen,
device accessibility, signing, or a release gate. Provider installation remains
in #203–#206; broader operation ownership remains in #216.

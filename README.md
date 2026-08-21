# mobile (working name)

Reproducible mobile development environments.

```
git clone my-app
cd my-app
mobile up
```

North Star: `git clone → mobile up`.

Status: iOS React Native MVP implemented. Current contracts and limitations live
in [CONTEXT.md](CONTEXT.md) and [the ADRs](docs/adr/); issue #1 is the closed
historical wayfinder map.

## Building

```
swift build
swift test
.build/debug/mobile doctor        # host checks; --json for machines, -v for detail
.build/debug/mobile build         # validate and compile; no Metro, install, or launch
.build/debug/mobile up            # build, install, and launch on a simulator
```

Exit codes: `0` no errors, `1` domain failure, `2` tool failure, `64` usage error.

### `build --json` and `up --json`

Machine consumers should use exit code `0`, or the absence of the top-level
`error` key, to detect success. A successful document omits `error`; it does not
emit `"error": null`. `status` describes how clean the environment is and may be
`warning` on a successful run, so do not require `status == "pass"`.

On failure, `result` may still contain device or Metro state collected before
the failure.

`Core` may not depend on Apple frameworks. Linux has none, so compiling it there
is that boundary — run `scripts/verify-core-linux.sh` (Docker) after touching
`Sources/Core`.

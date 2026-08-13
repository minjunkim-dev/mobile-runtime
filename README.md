# mobile (working name)

Reproducible mobile development environments.

```
git clone my-app
cd my-app
mobile up
```

North Star: `git clone → mobile up`.

Status: charting phase — see the wayfinder map in Issues.

## Building

```
swift build
swift test
.build/debug/mobile doctor        # host checks; --json for machines, -v for detail
```

Exit codes: `0` no errors, `1` domain failure, `2` tool failure, `64` usage error.

`Core` may not depend on Apple frameworks. Linux has none, so compiling it there
is that boundary — run `scripts/verify-core-linux.sh` (Docker) after touching
`Sources/Core`.

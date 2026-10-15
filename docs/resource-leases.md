# Shared resource leases

CLI, GUI, and separate processes use the Core `ResourceLeases`. Each command
inspects and selects first. It takes every resource it changes before the first
change.

| Key | Taken by |
|-----|----------|
| `folder:<volume>:<file>` — the real workspace folder | `setup`, `build`, `up`, `down` |
| `destination:<canonical path>` — a tool installation destination | `setup` (shared Bundle destination) |
| `device:<platform>:<identity>` — the selected execution device | `up` |
| `app:<platform>:<device>:<app id>` — the app a run replaces | named in post-run conflicts |
| `port:8081` — the development server port | `up` |

## Rules

1. Acquisition is all-or-nothing in one fixed key order. A conflict releases
   only the keys this operation took.
2. A conflict stops the operation before changes. The operation JSON carries
   `conflict` with the key, the owner (operation, command, project, pid), and the
   reason. Runstir does not switch devices, stop the other operation, or queue.
3. Each lock is a nonblocking `flock` in `~/Library/Caches/dev.runstir/leases`,
   opened close-on-exec. The kernel releases it when its process ends. A record
   left by a dead process does not block. Runstir never judges liveness by pid.
4. A held lock with a missing or unreadable record is an unknown owner. It
   blocks, and Runstir keeps the file.
5. A successful `up` records a claim on its device: the app it left running. The
   lease ends with the command; the claim does not. The next `up` of another
   project on that device observes the app again (`simctl spawn … launchctl list`
   or `adb shell pidof`). Only an observed stop removes the claim. A running or
   unobservable app blocks the device.

The Metro port after a finished run stays under `MetroVerdict`, which already
observes the occupant's project root.

## Evidence ([#216](https://github.com/minjunkim-dev/mobile-runtime/issues/216))

| Spec row | Automated | Real execution |
|----------|-----------|----------------|
| AC03 concurrent setup of one target | `PreparationExecutionTests` overlapping and shared Bundle destination | `scripts/verify-setup-input.py` runs two `mobile setup` processes with different `TMPDIR`; the second reports the first's operation and pid. Its installer is a controlled stub. Pending: real concurrent setup on one installation target |
| AC08 folder, device, destination, port, stale/unknown owner | `ResourceLeasesTests` (cross-process `flock` holder), `WorkflowExecutionTests` folder and live-app conflicts, Simulator/Android observation tests | `mobile down` against a folder held by another process reported the owner and exited 1; after that process exited it succeeded. Pending: concurrent CLI and GUI runs on real devices |

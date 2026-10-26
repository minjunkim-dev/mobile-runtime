#!/usr/bin/env python3
"""Collect process metadata for validation without command arguments or full paths."""

import json
import re
import subprocess


def main():
    try:
        result = subprocess.run(
            ["/bin/ps", "-A", "-c", "-o", "pid=,ppid=,%cpu=,%mem=,etime=,comm="],
            capture_output=True, text=True, timeout=10,
        )
        if result.returncode:
            raise ValueError("snapshot-failed")
        rows, unparsed = [], 0
        for line in result.stdout.splitlines():
            fields = line.split(maxsplit=5)
            if len(fields) != 6 or not fields[0].isdigit() or not fields[1].isdigit():
                unparsed += 1
                continue
            pid, parent, cpu, memory, elapsed, executable = fields
            if not all(re.fullmatch(r"[0-9.]+", value) for value in (cpu, memory)) \
                    or not re.fullmatch(r"[0-9:-]+", elapsed):
                unparsed += 1
                continue
            name = executable.rsplit("/", 1)[-1]
            if not re.fullmatch(r"[A-Za-z0-9_.+-]{1,128}", name):
                name = "unresolved"
            rows.append({"pid": int(pid), "parentPID": int(parent), "cpuPercent": cpu,
                         "memoryPercent": memory, "elapsed": elapsed, "executableName": name})
        print(json.dumps({"schemaVersion": 1, "processes": rows, "unparsedRows": unparsed}))
        return 0
    except (OSError, subprocess.SubprocessError, ValueError):
        print(json.dumps({"schemaVersion": 1, "error": "process-snapshot-unavailable"}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

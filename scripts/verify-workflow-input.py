#!/usr/bin/env python3
"""Verify the actual RN commands' public selection and progress contracts (AC01/AC04)."""
import json
import os
from pathlib import Path
import subprocess
import signal
import sys
import tempfile
import time

binary = str(Path(sys.argv[1]).resolve())
for command in ("build", "up", "down"):
    help_text = subprocess.run([binary, command, "--help"], capture_output=True, text=True, check=True).stdout
    for option in ("--project", "--app", "--platform", "--device", "--scheme", "--configuration", "--module", "--variant", "--non-interactive", "--progress-json", "--json"):
        assert option in help_text, (command, option)

with tempfile.TemporaryDirectory(prefix="runstir-workflow-") as temporary:
    root = Path(temporary).resolve()
    (root / ".git").mkdir()
    (root / "package.json").write_text(json.dumps({"dependencies": {"react-native": "0.81.0"}}))
    (root / "ios").mkdir()
    (root / "android").mkdir()
    before = {str(p.relative_to(root)): p.read_bytes() for p in root.rglob("*") if p.is_file()}
    for command in ("build", "up", "down"):
        result = subprocess.run([binary, command, "--project", str(root), "--json", "--progress-json", "--non-interactive", "--verbose"],
                                cwd="/", capture_output=True, text=True, timeout=30)
        assert result.returncode == 1, (command, result)
        document = json.loads(result.stdout)
        operation = document["operation"]
        assert document["schemaVersion"] == 1 and document["command"] == command
        assert operation["state"] == "needs-selection"
        assert operation["requiredInput"] == ["--platform"]
        assert operation["selection"]["selected"]["id"] == "."
        assert "environment" not in operation
        events = [json.loads(line) for line in result.stderr.splitlines()]
        assert [e["sequence"] for e in events] == list(range(1, len(events) + 1))
        assert all(e["operationId"] == operation["id"] and e["schemaVersion"] == 1 for e in events)
        assert events[0]["kind"] == "started" and events[-1]["kind"] == "finished"
        assert events[-1]["state"] == "needs-selection"
    assert before == {str(p.relative_to(root)): p.read_bytes() for p in root.rglob("*") if p.is_file()}, "selection changed project files"
    invalid = subprocess.run([binary, "up", "--platform", "invalid"], capture_output=True, text=True)
    assert invalid.returncode == 64

    tools = root / "tools"
    tools.mkdir()
    probe = tools / "xcode-select"
    probe.write_text('#!/bin/sh\nprintf ready > "$RUNSTIR_TEST_PROBE"\nexec sleep 30\n')
    probe.chmod(0o755)
    environment = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ["PATH"])
    environment.pop("DEVELOPER_DIR", None)
    ready = root / "probe-ready"
    environment["RUNSTIR_TEST_PROBE"] = str(ready)
    process = subprocess.Popen([binary, "build", "--project", str(root), "--platform", "ios", "--json", "--progress-json"],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=environment)
    started = process.stderr.readline()
    assert json.loads(started)["kind"] == "started"
    deadline = time.monotonic() + 10
    while not ready.exists() and time.monotonic() < deadline:
        time.sleep(0.01)
    assert ready.exists(), "Xcode probe did not start"
    process.send_signal(signal.SIGINT)
    try:
        stdout, stderr = process.communicate(timeout=15)
    except subprocess.TimeoutExpired:
        process.kill()
        process.communicate(timeout=5)
        raise
    assert process.returncode == 130, (process.returncode, stderr)
    document = json.loads(stdout)
    assert document["operation"]["state"] == "cancelled"
    events = [json.loads(line) for line in (started + stderr).splitlines()]
    assert events[-1]["kind"] == "cancelled"
    assert all(event["operationId"] == document["operation"]["id"] for event in events)

print("RN workflow executable help/selection/JSON/NDJSON/no-mutation/SIGINT-130: PASS")

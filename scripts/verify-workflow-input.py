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
for command in ("build", "up"):
    help_text = subprocess.run([binary, command, "--help"], capture_output=True, text=True, check=True).stdout
    assert "--prepared-dependencies" in help_text, command

with tempfile.TemporaryDirectory(prefix="runstir-app-parser-") as temporary:
    for command in ("inspect", "run"):
        help_text = subprocess.run([binary, "app", command, "--help"], capture_output=True, text=True, check=True).stdout
        assert "--platform" in help_text, command
        for platform in (None, "ios", "android", "invalid"):
            file = Path(temporary) / "Missing.app"
            arguments = [binary, "app", command, str(file), "--json", "--non-interactive"]
            if command == "run":
                arguments.append("--plan")
            if platform is not None:
                arguments += ["--platform", platform]
            result = subprocess.run(arguments, capture_output=True, text=True, timeout=10)
            if platform == "invalid":
                assert result.returncode == 64, (command, result)
                continue
            # An absent file stops before tools; the accepted option reaches the common boundary.
            assert result.returncode in (1, 2), (command, platform, result)
            document = json.loads(result.stdout)
            assert document["command"] == "app " + command
            operation = document["operation"]
            assert operation["error"] and "plan" not in operation
            assert operation["installation"] == "not-requested" and operation["launch"] == "not-requested"
    assert list(Path(temporary).iterdir()) == [], "parser inspection changed its input directory"

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

    unsupported = subprocess.run([binary, "down", "--project", str(root), "--platform", "ios",
                                  "--prepared-dependencies", "--json", "--non-interactive"],
                                 capture_output=True, text=True, timeout=10)
    assert unsupported.returncode == 1, unsupported
    unsupported_document = json.loads(unsupported.stdout)
    assert "--prepared-dependencies는 React Native build/up에서만 사용할 수 있습니다" in unsupported_document["error"]["message"]
    assert unsupported_document["operation"]["preparedDependencies"] is True

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

print("App file platform parser and RN workflow help/selection/JSON/NDJSON/no-mutation/SIGINT-130: PASS")

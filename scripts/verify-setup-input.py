#!/usr/bin/env python3
"""Exercise the executable approval boundary with owned tools and no mobile devices."""
import json
import os
import pathlib
import pty
import signal
import subprocess
import sys
import tempfile
import time

mobile = pathlib.Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix="runstir-setup-contract-") as temporary:
    root = pathlib.Path(temporary)
    tools = root / "tools"
    project = root / "project"
    tools.mkdir()
    (project / "ios" / "Example.xcodeproj").mkdir(parents=True)
    (project / "package.json").write_text('{"dependencies":{"react-native":"0.81.0"}}')
    (project / "yarn.lock").write_text("")
    (project / ".env").write_text("API_KEY=private-fixture-value")
    dispatch = tools / "dispatch"
    dispatch.write_text("""#!/usr/bin/env python3
import json, os, pathlib, sys, time
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
if name == 'xcode-select': print('/test/Xcode')
elif name == 'xcodebuild':
    if '-version' in args: print('Xcode 27.0\\nBuild version 18A100')
    elif '-list' in args: print(json.dumps({'project': {'schemes': ['Example']}}))
    elif '-checkFirstLaunchStatus' in args: pass
    else: sys.exit('Unexpected xcodebuild command')
elif name == 'xcrun':
    assert args == ['simctl', 'list', 'runtimes', '-j'], args
    print(json.dumps({'runtimes': [{'identifier': 'com.apple.CoreSimulator.SimRuntime.iOS-27-0', 'name': 'iOS 27.0', 'version': '27.0', 'isAvailable': True}]}))
elif name == 'node':
    assert args == ['--version'], args
    print('v22.14.0')
elif name == 'yarn':
    if args == ['--version']: print('1.22.22')
    elif args == ['install', '--frozen-lockfile']:
        pathlib.Path('node_modules').mkdir(exist_ok=True)
        pathlib.Path('node_modules/owned-install-marker').write_text('started')
        if os.getenv('SETUP_TEST_WAIT') == '1': time.sleep(30)
        if os.getenv('SETUP_TEST_FAIL') == '1': sys.exit(1)
    else: sys.exit('Unexpected yarn command')
else: sys.exit('Unexpected tool')
""")
    dispatch.chmod(0o755)
    for name in ("xcode-select", "xcodebuild", "xcrun", "node", "yarn"):
        (tools / name).symlink_to(dispatch)
    environment = dict(os.environ)
    for name in ("DEVELOPER_DIR", "ANDROID_HOME", "ANDROID_SDK_ROOT", "SDKROOT"):
        environment.pop(name, None)
    environment["PATH"] = str(tools) + os.pathsep + environment["PATH"]
    environment["NO_COLOR"] = "1"
    common = [str(mobile), "setup", "--project", str(project), "--json", "--progress-json"]

    def run(*arguments, expected, extra=None):
        process = subprocess.run(common + list(arguments), env=environment | (extra or {}), capture_output=True, text=True, timeout=20)
        assert process.returncode == expected, (process.returncode, process.stderr, process.stdout)
        document = json.loads(process.stdout)
        events = [json.loads(line) for line in process.stderr.splitlines()]
        assert document["command"] == "setup" and document["schemaVersion"] == 1
        assert all(event["schemaVersion"] == 1 and event["operationId"] == document["operation"]["id"] for event in events)
        assert [event["sequence"] for event in events] == list(range(1, len(events) + 1))
        assert events[-1]["state"] == document["operation"]["state"]
        assert "private-fixture-value" not in process.stdout and "/.env" not in process.stdout
        return document

    help_output = subprocess.run([str(mobile), "setup", "--help"], capture_output=True, text=True, timeout=10)
    assert help_output.returncode == 0
    for option in ("--plan", "--approve", "--trust-repository", "--non-interactive", "--progress-json"):
        assert option in help_output.stdout
    syntax = subprocess.run(common + ["--plan", "--approve", "invalid"], env=environment, capture_output=True, text=True, timeout=10)
    assert syntax.returncode == 64
    plan = run("--plan", "--platform", "ios", expected=0)
    assert [entry["platform"] for entry in plan["plan"]["platforms"]] == ["ios", "android"]
    assert not (project / "node_modules").exists()
    missing = run("--non-interactive", expected=1)
    assert missing["operation"]["state"] == "needs-approval"
    untrusted = run("--approve", plan["plan"]["id"], expected=1)
    assert untrusted["operation"]["requiredInput"] == ["--trust-repository"]
    assert not (project / "node_modules").exists()
    (project / "yarn.lock").write_text("changed lock")
    stale = run("--approve", plan["plan"]["id"], "--trust-repository", expected=1)
    assert stale["operation"]["state"] == "needs-approval"
    current = run("--plan", expected=0)
    prepared = run("--approve", current["plan"]["id"], "--trust-repository", expected=1)
    assert prepared["operation"]["state"] == "partial"
    assert prepared["operation"]["completed"] == ["dependencies.node"]
    assert (project / "node_modules" / "owned-install-marker").exists()
    assert (project / "yarn.lock").read_text() == "changed lock"
    failed_plan = run("--plan", expected=0)
    failed = run("--approve", failed_plan["plan"]["id"], "--trust-repository", expected=1, extra={"SETUP_TEST_FAIL": "1"})
    assert failed["operation"]["state"] == "failed"
    assert (project / "node_modules" / ".mobile-install.incomplete").exists()
    cancel_plan = run("--plan", expected=0)
    marker = project / "node_modules" / "owned-install-marker"
    marker.unlink()
    process = subprocess.Popen(common + ["--approve", cancel_plan["plan"]["id"], "--trust-repository"], env=environment | {"SETUP_TEST_WAIT": "1"}, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    deadline = time.monotonic() + 10
    while not marker.exists() and time.monotonic() < deadline:
        time.sleep(0.02)
    assert marker.exists(), "installer did not start"
    # TMPDIR differs across CLI/GUI processes; the same destination still has one lease.
    other_tmp = root / "other-temp"
    other_tmp.mkdir()
    concurrent_plan = run("--plan", expected=0, extra={"TMPDIR": str(other_tmp)})
    concurrent = run("--approve", concurrent_plan["plan"]["id"], "--trust-repository", expected=1,
        extra={"TMPDIR": str(other_tmp)})
    assert "Another setup" in concurrent["operation"]["error"]
    assert concurrent["operation"]["completed"] == []
    process.send_signal(signal.SIGINT)
    stdout, stderr = process.communicate(timeout=15)
    assert process.returncode == 130, (process.returncode, stdout, stderr)
    cancelled = json.loads(stdout)
    assert cancelled["operation"]["state"] == "cancelled"
    assert json.loads(stderr.splitlines()[-1])["kind"] == "cancelled"
    assert marker.exists()
    assert (project / "node_modules" / ".mobile-install.incomplete").exists()

    # A real TTY accepts only the displayed plan-id and a separate trust answer.
    master, slave = pty.openpty()
    process = subprocess.Popen([str(mobile), "setup", "--project", str(project)], env=environment,
        stdin=slave, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    os.close(slave)
    prompts = []
    for line in process.stderr:
        prompts.append(line)
        if line.startswith("Type this exact plan-id"):
            os.write(master, (line.strip().rsplit(": ", 1)[1] + "\n").encode())
        elif line.startswith("Repository trust is separate"):
            os.write(master, b"TRUST\n")
    output, _ = process.communicate(timeout=20)
    os.close(master)
    assert process.returncode == 1 and "setup: partial" in output, (output, prompts)
    assert any("Type this exact plan-id" in line for line in prompts)
    assert any("Repository trust is separate" in line for line in prompts)
print("setup executable contract PASS: plan, approval, trust, stale conditions, partial, failure, cancellation, TTY, JSON/NDJSON")

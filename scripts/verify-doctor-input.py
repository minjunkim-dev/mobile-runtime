#!/usr/bin/env python3
"""Check the actual doctor executable's selection and JSON contract (AC01/AC04)."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

binary = str(Path(sys.argv[1]).resolve())
help_result = subprocess.run([binary, "doctor", "--help"], capture_output=True, text=True, check=True)
for option in ("--project", "--app", "--platform", "--non-interactive", "--json"):
    assert option in help_result.stdout, option

with tempfile.TemporaryDirectory(prefix="runstir-doctor-") as temporary:
    root = Path(temporary).resolve()
    (root / ".git").mkdir()
    (root / "package.json").write_text(json.dumps({"workspaces": ["packages/*"]}))
    for name in ("one", "two"):
        app = root / "packages" / name
        (app / "ios").mkdir(parents=True)
        (app / "android").mkdir()
        (app / "package.json").write_text(json.dumps({"dependencies": {"react-native": "0.76.5"}}))
    before = {str(p.relative_to(root)): p.read_bytes() for p in root.rglob("*") if p.is_file()}

    def inspect(*options):
        result = subprocess.run(
            [binary, "doctor", "--project", str(root), "--json", "--non-interactive", *options],
            cwd="/", capture_output=True, text=True, timeout=90,
        )
        document = json.loads(result.stdout)
        assert document["schemaVersion"] == 1
        assert document["command"] == "doctor"
        assert "checks" in document and "status" in document
        assert "environment" not in document["selection"]
        assert not any(check["id"] == "project.detected" for check in document["checks"])
        return result, document["selection"]

    result, selection = inspect("--platform", "android")
    assert result.returncode == 1
    assert selection["requiredInput"] == ["--app"]
    assert [candidate["id"] for candidate in selection["candidates"]] == ["packages/one", "packages/two"]
    assert "selection required" in result.stderr
    result, selection = inspect("--app", "packages/one")
    assert result.returncode == 1
    assert selection["requiredInput"] == ["--platform"]
    result, selection = inspect("--app", "missing", "--platform", "android")
    assert result.returncode == 1
    assert "Invalid --app" in selection["error"]
    after = {str(p.relative_to(root)): p.read_bytes() for p in root.rglob("*") if p.is_file()}
    assert before == after, "doctor changed project files"
print("doctor executable selection/JSON/non-interactive/read-only: PASS")

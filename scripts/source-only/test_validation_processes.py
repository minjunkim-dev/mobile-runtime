"""Exercise the validation snapshot CLI without collecting command arguments."""

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "validation-processes.py"


class ValidationProcessTests(unittest.TestCase):
    def test_process_tool_failure_returns_only_a_safe_error(self):
        spec = importlib.util.spec_from_file_location("validation_processes", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        for failure in (OSError("synthetic-credential"),
                        subprocess.TimeoutExpired("synthetic-credential", 10)):
            with self.subTest(failure=type(failure).__name__), \
                    patch.object(module.subprocess, "run", side_effect=failure):
                output = io.StringIO()
                with contextlib.redirect_stdout(output):
                    self.assertEqual(module.main(), 1)
                self.assertEqual(json.loads(output.getvalue()),
                                 {"schemaVersion": 1, "error": "process-snapshot-unavailable"})

    def test_snapshot_omits_arguments_and_paths(self):
        marker = "synthetic-validation-credential-71e9"
        child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)",
                                  "--api-key", marker])
        try:
            result = subprocess.run([sys.executable, "-I", str(SCRIPT)],
                                    capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn(marker, result.stdout + result.stderr)
            self.assertNotIn("--api-key", result.stdout + result.stderr)
            rows = json.loads(result.stdout)["processes"]
            self.assertTrue(any(row["pid"] == child.pid for row in rows))
            for row in rows:
                self.assertEqual(set(row), {"pid", "parentPID", "cpuPercent", "memoryPercent",
                                            "elapsed", "executableName"})
                self.assertNotIn("/", row["executableName"])
        finally:
            child.terminate()
            child.wait(timeout=10)


if __name__ == "__main__":
    unittest.main()

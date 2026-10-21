#!/usr/bin/env python3
"""Behavior checks for the Draft Release trust boundary."""

import importlib.util
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "release_input", Path(__file__).with_name("validate-release-input.py")
)
release_input = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release_input)
SHA = "a" * 40


class ReleaseInputTests(unittest.TestCase):
    def test_alpha_version_and_full_sha_are_accepted(self):
        release_input.validate_inputs("0.1.0-alpha.5", SHA)

    def test_unsupported_versions_and_shell_text_are_rejected(self):
        for version in ["v0.1.0-alpha.5", "0.1.0", "0.1.0-beta.1", "01.1.0-alpha.5",
                        "0.1.0-alpha.5; touch /tmp/unwanted", "0.1.0-alpha.5\n"]:
            with self.subTest(version=version), self.assertRaises(ValueError):
                release_input.validate_inputs(version, SHA)

    def test_refs_abbreviated_shas_and_shell_text_are_rejected(self):
        for source in ["main", "abcdef1", "A" * 40, SHA + "\n", SHA + ";echo bad"]:
            with self.subTest(source=source), self.assertRaises(ValueError):
                release_input.validate_inputs("0.1.0-alpha.5", source)

    def test_only_successful_main_push_ci_for_the_exact_source_passes(self):
        run = {"head_sha": SHA, "head_branch": "main", "event": "push",
               "status": "completed", "conclusion": "success",
               "path": ".github/workflows/ci.yml"}
        release_input.validate_ci([run], SHA)
        for key, value in {"head_sha": "b" * 40, "head_branch": "feature",
                           "event": "pull_request", "status": "in_progress",
                           "conclusion": "failure", "path": ".github/workflows/other.yml"}.items():
            with self.subTest(field=key), self.assertRaises(ValueError):
                release_input.validate_ci([{**run, key: value}], SHA)
        with self.assertRaises(ValueError):
            release_input.validate_ci([], SHA)

    def test_existing_draft_published_release_or_tag_is_rejected(self):
        version = "0.1.0-alpha.5"
        for draft in [True, False]:
            with self.subTest(draft=draft), self.assertRaises(ValueError):
                release_input.validate_unused_version(
                    [{"tag_name": f"v{version}", "draft": draft}], [], version
                )
        with self.assertRaises(ValueError):
            release_input.validate_unused_version([], [{"ref": f"refs/tags/v{version}"}], version)
        release_input.validate_unused_version(
            [{"tag_name": "v0.1.0-alpha.4"}], [{"ref": f"refs/tags/v{version}0"}], version
        )

    def test_non_main_source_stops_before_any_github_request(self):
        with patch.object(release_input.sys, "argv", ["script", "0.1.0-alpha.5", SHA]), \
             patch.object(release_input.subprocess, "run",
                          side_effect=subprocess.CalledProcessError(1, "git")), \
             patch.object(release_input, "api") as api:
            with self.assertRaises(subprocess.CalledProcessError):
                release_input.main()
            api.assert_not_called()

    def test_api_failure_is_not_treated_as_an_unused_version(self):
        with patch.object(release_input.subprocess, "check_output",
                          side_effect=subprocess.CalledProcessError(1, "gh")):
            with self.assertRaises(subprocess.CalledProcessError):
                release_input.api("repos/example/project/releases")


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Behavior checks for the Draft Release trust boundary."""

import importlib.util
import hashlib
from pathlib import Path
import subprocess
import tarfile
import tempfile
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

    def test_candidate_rejects_mixed_source_version_and_core_build(self):
        candidate = {"productVersion": "1.0.0-alpha.1", "sourceSHA": SHA,
                     "coreBuildIdentity": "b" * 64}
        build = {"releaseVersion": "1.0.0-alpha.1", "toolVersion": "1.0.0-alpha.1",
                 "sourceRevision": SHA, "coreBuildIdentity": "b" * 64}
        release_input.validate_candidate(candidate, build, build)
        for key, value in {"releaseVersion": "1.0.0-alpha.2", "toolVersion": "0.1.0",
                           "sourceRevision": "c" * 40,
                           "coreBuildIdentity": "d" * 64}.items():
            with self.subTest(field=key), self.assertRaises(ValueError):
                release_input.validate_candidate(candidate, build, {**build, key: value})

    def test_candidate_requires_an_exact_core_build_digest(self):
        for digest in [None, "", "unknown", "b" * 63]:
            with self.subTest(digest=digest), self.assertRaises(ValueError):
                release_input.validate_candidate(
                    {"productVersion": "1.0.0-alpha.1", "sourceSHA": SHA,
                     "coreBuildIdentity": digest}, {}, {}
                )

    def test_transferred_candidate_matches_the_requested_source_and_version(self):
        version = "1.0.0-alpha.1"
        candidate = {"productVersion": version, "sourceSHA": SHA}
        for key, value in {"productVersion": "1.0.0-alpha.2", "sourceSHA": "b" * 40}.items():
            changed = {**candidate, key: value}
            release_input.validate_inputs(changed["productVersion"], changed["sourceSHA"])
            with self.subTest(field=key), self.assertRaises(ValueError):
                release_input.validate_requested_candidate(changed, version, SHA)
        release_input.validate_requested_candidate(candidate, version, SHA)

    def test_candidate_archive_rejects_escape_links_and_unexpected_roots(self):
        good = tarfile.TarInfo("runstir-1.0.0-alpha.1-macos-arm64/mobile")
        release_input.validate_candidate_archive([good], "1.0.0-alpha.1")
        for name in ["../outside", "/absolute", "other/mobile",
                     "runstir-1.0.0-alpha.1-macos-arm64/../../outside"]:
            with self.subTest(name=name), self.assertRaises(ValueError):
                release_input.validate_candidate_archive([tarfile.TarInfo(name)], "1.0.0-alpha.1")
        link = tarfile.TarInfo(good.name)
        link.type = tarfile.SYMTYPE
        link.linkname = "/outside"
        with self.assertRaises(ValueError):
            release_input.validate_candidate_archive([link], "1.0.0-alpha.1")

    def test_candidate_requires_all_artifacts_and_rejects_tampered_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            names = {"cli": "runstir-1.0.0-alpha.1-macos-arm64.tar.gz",
                     "gui": "Runstir-1.0.0-alpha.1-macos-arm64.dmg",
                     "homebrew": "runstir-candidate.rb"}
            artifacts = {}
            for kind, name in names.items():
                (root / name).write_bytes(kind.encode())
                artifacts[kind] = {"file": name, "sha256": hashlib.sha256(kind.encode()).hexdigest()}
            manifest = {"productVersion": "1.0.0-alpha.1", "sourceSHA": SHA,
                        "artifacts": artifacts}
            release_input.validate_candidate_artifacts(manifest, root)
            with self.assertRaises(ValueError):
                release_input.validate_candidate_artifacts(
                    {**manifest, "artifacts": {"cli": artifacts["cli"]}}, root)
            (root / names["homebrew"]).write_bytes(b"changed formula")
            with self.assertRaises(ValueError):
                release_input.validate_candidate_artifacts(manifest, root)


if __name__ == "__main__":
    unittest.main()

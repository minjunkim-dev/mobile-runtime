"""Exercise the release evidence CLI with bounded, isolated evidence bundles."""

import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "verify-release-evidence.py"
SOURCE = "a" * 40


def digest(data):
    return hashlib.sha256(data).hexdigest()


class ReleaseEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.public = self.root / "public"
        self.private = self.root / "private"
        self.public.mkdir()
        self.private.mkdir()
        self.candidate = {
            "schemaVersion": 1, "sourceSHA": SOURCE, "productVersion": "1.0.0-alpha.1",
            "coreBuildIdentity": "b" * 64, "ciRun": None, "signing": "developer-id",
            "notarization": "accepted", "distributionReady": True, "artifacts": {},
        }
        self.files = []
        for kind, name in [("cli", "cli.tar.gz"), ("gui", "gui.dmg"), ("homebrew", "candidate.rb")]:
            data = ("fixture " + kind).encode()
            self.candidate["artifacts"][kind] = {"file": name, "sha256": digest(data)}
            self.private_file(kind, name, data)
        self.private_file("candidate", "CANDIDATE.json", self.encode(self.candidate))
        self.candidate_id = self.files[-1]["sha256"]
        self.private_file("ci", "CI.json", self.encode({
            "headSha": SOURCE, "databaseId": 123, "name": "CI", "status": "completed",
            "conclusion": "success", "jobs": [{"name": "CI", "status": "completed", "conclusion": "success"}],
        }))
        origin = {"schemaVersion": 1, "sourceSHA": SOURCE, "files": [
            {"file": "evidence/" + e["path"], "bytes": e["bytes"], "SHA256": e["sha256"]}
            for e in self.files
        ]}
        self.private_file("origin", "EVIDENCE-INDEX.json", self.encode(origin))
        self.restricted = {
            "schemaVersion": 1,
            "storage": {"id": "local-evidence", "custodian": "release-owner", "access": "local-owner-only"},
            "files": self.files,
        }
        self.tuples = {"schemaVersion": 1, "tuples": [{
            "id": "host-tuple", "candidateID": self.candidate_id,
            "inputs": {"host": "fixture-host", "toolchain": "fixture-toolchain", "runtime": "fixture-runtime"},
        }]}
        self.results = {"schemaVersion": 1, "requirements": [], "attempts": []}
        for number in range(1, 20):
            gate = f"AC{number:02}"
            self.results["requirements"].append({
                "id": gate, "gate": gate, "tupleID": "host-tuple", "sampleID": "package", "sampleSHA": SOURCE, "frontend": "CLI",
            })
            self.results["attempts"].append({
                "id": gate + "-01", "requirementID": gate, "candidateID": self.candidate_id,
                "tupleID": "host-tuple", "sampleID": "package", "sampleSHA": SOURCE,
                "frontend": "CLI", "evidenceClass": "fixture", "expected": "declared outcome",
                "observed": "fixture outcome", "result": "pass", "evidence": ["candidate", "cli"],
                "unverified": [], "supersedes": None,
            })
        self.manifest = {
            "schemaVersion": 1, "evidenceClass": "fixture", "candidate": self.candidate,
            "candidateRef": "candidate", "originIndexes": ["origin"], "documents": {},
            "sourceCI": {"evidence": "ci", "runID": 123}, "priorResults": [],
            "publicReview": {"reviewer": "fixture-reviewer", "status": "reviewed", "scope": "text-only"},
        }
        self.report = "# Fixture evidence\n\nAC15 and AC17. Fixture evidence is not release proof.\n"
        self.write_bundle()

    @staticmethod
    def encode(value):
        return (json.dumps(value, indent=2) + "\n").encode()

    def private_file(self, ref, name, data):
        (self.private / name).write_bytes(data)
        self.files.append({"id": ref, "path": name, "bytes": len(data), "sha256": digest(data)})

    def public_file(self, name, data):
        (self.public / name).write_bytes(data)
        return {"path": name, "sha256": digest(data)}

    def write_bundle(self):
        for key, name, data in [
            ("tuples", "tuples.json", self.encode(self.tuples)),
            ("results", "results.json", self.encode(self.results)),
            ("restrictedIndex", "restricted-index.json", self.encode(self.restricted)),
            ("report", "report.md", self.report.encode()),
        ]:
            self.manifest["documents"][key] = self.public_file(name, data)
        self.public_file("manifest.json", self.encode(self.manifest))

    def run_cli(self, optimized=False):
        return subprocess.run(
            [sys.executable, "-I", *(["-O"] if optimized else []), str(SCRIPT),
             str(self.public / "manifest.json"), "--private-root", str(self.private)],
            capture_output=True, text=True, timeout=15,
        )

    def verify(self, integrity="verified", decision="blocked", optimized=False):
        result = self.run_cli(optimized)
        self.assertEqual(result.returncode, 1, result.stderr or result.stdout)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["evidenceIntegrity"], integrity)
        self.assertEqual(payload["releaseDecision"], decision)
        self.assertNotIn(str(self.root), result.stdout + result.stderr)
        return payload

    def test_complete_fixture_exercises_pass_path_without_release_promotion(self):
        payload = self.verify()
        self.assertEqual(payload["gateEvaluation"], "pass")
        self.assertIn("fixture-evidence", payload["blockers"])
        self.assertIsNone(self.candidate["ciRun"])

    def test_missing_checksum_and_foreign_candidate_are_rejected(self):
        original = copy.deepcopy(self.results)
        for change in ["missing", "checksum", "candidate"]:
            with self.subTest(change=change):
                self.results = copy.deepcopy(original)
                self.write_bundle()
                if change == "missing":
                    (self.private / "cli.tar.gz").unlink()
                elif change == "checksum":
                    (self.private / "cli.tar.gz").write_bytes(b"changed")
                else:
                    self.results["attempts"][0]["candidateID"] = "f" * 64
                    self.write_bundle()
                self.verify("invalid")
                (self.private / "cli.tar.gz").write_bytes(b"fixture cli")

    def test_required_failed_unknown_and_unverified_outcomes_block(self):
        for status in ["fail", "inconclusive", "unverified", "unknown"]:
            with self.subTest(status=status):
                self.results["attempts"][0]["result"] = status
                self.write_bundle()
                self.assertEqual(self.verify()["gateEvaluation"], "blocked")
        self.results["attempts"][0]["result"] = "pass"
        self.results["attempts"][0]["unverified"] = ["first screen not observed"]
        self.write_bundle()
        self.assertEqual(self.verify()["gateEvaluation"], "blocked")

    def test_fixture_attempt_cannot_be_relabelled_by_the_bundle(self):
        self.manifest["evidenceClass"] = "actual"
        self.write_bundle()
        self.verify("invalid")

    def test_missing_gate_duplicate_identity_and_bad_reference_are_rejected(self):
        original = copy.deepcopy(self.results)
        for change in ["gate", "duplicate", "reference", "frontend", "status"]:
            with self.subTest(change=change):
                self.results = copy.deepcopy(original)
                if change == "gate":
                    self.results["requirements"].pop()
                    self.results["attempts"].pop()
                elif change == "duplicate":
                    self.results["attempts"].append(copy.deepcopy(self.results["attempts"][0]))
                elif change == "reference":
                    self.results["attempts"][0]["evidence"] = ["absent"]
                elif change == "frontend":
                    self.results["attempts"][0]["frontend"] = "GUI"
                else:
                    self.results["attempts"][0]["result"] = "successful"
                self.write_bundle()
                self.verify("invalid")

    def test_failed_history_is_retained_and_retest_has_its_own_identity(self):
        old = copy.deepcopy(self.results)
        old["attempts"][0]["result"] = "fail"
        self.results = copy.deepcopy(old)
        retry = copy.deepcopy(old["attempts"][0])
        retry.update(id="AC01-02", result="pass", supersedes="AC01-01")
        self.results["attempts"].append(retry)
        self.manifest["priorResults"] = [self.public_file("previous.json", self.encode(old))]
        self.write_bundle()
        self.assertEqual(self.verify()["attempts"], 20)
        self.results["attempts"][0]["result"] = "pass"
        self.write_bundle()
        self.verify("invalid")
        self.results["attempts"].pop(0)
        self.write_bundle()
        self.verify("invalid")

    def test_path_escape_symlink_and_credential_paths_are_rejected_before_read(self):
        original = copy.deepcopy(self.restricted)
        for path in ["../outside", "/etc/passwd", "a/../../outside", "a\\outside", "auth/session.json", "credentials.json"]:
            with self.subTest(path=path):
                self.restricted = copy.deepcopy(original)
                self.restricted["files"][0]["path"] = path
                self.write_bundle()
                self.verify("invalid")
        self.restricted = original
        self.write_bundle()
        (self.private / "cli.tar.gz").unlink()
        (self.private / "cli.tar.gz").symlink_to(self.private / "gui.dmg")
        self.verify("invalid")
        (self.private / "cli.tar.gz").unlink()
        (self.private / "cli.tar.gz").write_bytes(b"fixture cli")
        (self.public / "results.json").unlink()
        (self.public / "results.json").symlink_to(self.public / "tuples.json")
        self.verify("invalid")

    def test_duplicate_json_oversize_and_private_public_text_are_rejected(self):
        for data in [b'{"schemaVersion":1,"schemaVersion":1}', b" " * (1024 * 1024 + 1), b'[' * 1000]:
            with self.subTest(size=len(data)):
                self.public_file("manifest.json", data)
                self.verify("invalid", optimized=True)
        for text in ["private /Users/someone/work", "private /tmp/run/user-data",
                     "AWS_SECRET_ACCESS_KEY=example", "Authorization: Bearer example-secret",
                     "-----BEGIN PRIVATE KEY-----"]:
            with self.subTest(text=text):
                self.report = "# AC15 AC17\n" + text
                self.write_bundle()
                result = self.verify("invalid")
                self.assertNotIn(text, json.dumps(result))

    def test_read_only_verification_and_optimized_checks(self):
        before = {str(p): digest(p.read_bytes()) for p in self.root.rglob("*") if p.is_file()}
        self.verify(optimized=True)
        after = {str(p): digest(p.read_bytes()) for p in self.root.rglob("*") if p.is_file()}
        self.assertEqual(before, after)

    def test_unknown_tuple_and_sample_inputs_cannot_pass_required_gates(self):
        self.tuples["tuples"][0]["inputs"]["runtime"] = "unknown"
        self.write_bundle()
        self.assertEqual(self.verify()["gateEvaluation"], "blocked")
        self.tuples["tuples"][0]["inputs"]["runtime"] = "fixture-runtime"
        self.results["attempts"][0]["sampleSHA"] = "unknown"
        self.results["requirements"][0]["sampleSHA"] = "unknown"
        self.write_bundle()
        self.assertEqual(self.verify()["gateEvaluation"], "blocked")

    def test_actual_unsigned_is_valid_evidence_but_not_release_pass(self):
        self.candidate.update(signing="unsigned", notarization="not-requested", distributionReady=False)
        candidate_data = self.encode(self.candidate)
        (self.private / "CANDIDATE.json").write_bytes(candidate_data)
        candidate_entry = next(e for e in self.files if e["id"] == "candidate")
        candidate_entry.update(sha256=digest(candidate_data), bytes=len(candidate_data))
        origin_data = self.encode({"schemaVersion": 1, "sourceSHA": SOURCE, "files": [
            {"file": "evidence/" + e["path"], "bytes": e["bytes"], "SHA256": e["sha256"]}
            for e in self.files if e["id"] != "origin"
        ]})
        (self.private / "EVIDENCE-INDEX.json").write_bytes(origin_data)
        next(e for e in self.files if e["id"] == "origin").update(sha256=digest(origin_data), bytes=len(origin_data))
        self.tuples["tuples"][0]["candidateID"] = digest(candidate_data)
        self.manifest["evidenceClass"] = "actual"
        for entry in self.results["attempts"]:
            entry.update(evidenceClass="actual", candidateID=digest(candidate_data))
        self.write_bundle()
        payload = self.verify(optimized=True)
        self.assertEqual(payload["gateEvaluation"], "pass")
        self.assertEqual(payload["blockers"], ["distribution-unverified"])
        self.assertIsNone(json.loads((self.private / "CANDIDATE.json").read_text())["ciRun"])

    def test_duplicate_private_and_public_refs_and_foreign_ci_are_rejected(self):
        original = copy.deepcopy(self.manifest)
        self.manifest["sourceCI"]["runID"] = 456
        self.write_bundle()
        self.verify("invalid")
        self.manifest = original
        self.restricted["files"].append(copy.deepcopy(self.restricted["files"][0]))
        self.write_bundle()
        self.verify("invalid")
        self.restricted["files"].pop()
        self.write_bundle()
        self.manifest["documents"]["report"] = self.manifest["documents"]["results"]
        self.public_file("manifest.json", self.encode(self.manifest))
        self.verify("invalid")

    def test_unchanged_public_checksum_and_parent_symlinks_are_required(self):
        (self.public / "results.json").write_bytes(b"{}")
        self.verify("invalid")
        self.write_bundle()
        outside = self.root / "outside"
        outside.mkdir()
        (outside / "cli.tar.gz").write_bytes(b"fixture cli")
        (self.private / "linked").symlink_to(outside, target_is_directory=True)
        self.restricted["files"][0]["path"] = "linked/cli.tar.gz"
        self.write_bundle()
        self.verify("invalid")


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Verify explicit release evidence references without executing or publishing candidates."""

import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys


JSON_LIMIT = 1024 * 1024
FILE_LIMIT = 512 * 1024 * 1024
GATES = {f"AC{number:02}" for number in range(1, 20)}
PRIVATE_NAME = re.compile(r"(?:^|[/._-])(?:auth|sessions?|credentials?|secrets?|private[-_]?key|id_rsa|id_ed25519|keychain|env)(?:$|[/._-])", re.I)
PRIVATE_TEXT = re.compile(
    r"(?<![\w:/])/(?!/)[A-Za-z0-9_.-]+|[A-Za-z]:\\|-----BEGIN [A-Z ]*PRIVATE KEY-----|"
    r"\b(?:gh[pousr]_|github_pat_|sk-proj-)[A-Za-z0-9_-]+|"
    r"\bBearer\s+\S+|\b(?:[A-Za-z0-9]+_){0,8}(?:password|token|secret|api[_-]?key|access[_-]?key)"
    r"(?:_[A-Za-z0-9]+){0,8}[\"']?\s*[:=]\s*\S+", re.I
)


def require(condition, code):
    if not condition:
        raise ValueError(code)


def fields(value, required, optional=()):
    require(isinstance(value, dict) and set(required) <= set(value)
            and set(value) <= set(required) | set(optional), "invalid-fields")


def identifier(value):
    require(isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", value), "invalid-identity")
    return value


def sha(value, size=64):
    require(isinstance(value, str) and re.fullmatch(rf"[0-9a-f]{{{size}}}", value), "invalid-digest")


def relative(value):
    require(isinstance(value, str) and 0 < len(value) <= 512
            and not any(char in value for char in "\\:\x00")
            and all(part not in ("", ".", "..") for part in value.split("/"))
            and not PRIVATE_NAME.search(value), "unsafe-path")
    return value.split("/")


def read_file(root, name, limit=FILE_LIMIT, capture=False):
    """Open each component without following links, including during path replacement."""
    parts = relative(name)
    fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        for part in parts[:-1]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = child
        child = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
        os.close(fd)
        fd = child
        info = os.fstat(fd)
        require(stat.S_ISREG(info.st_mode) and info.st_size <= limit, "invalid-file-size-or-type")
        digest, size, chunks = hashlib.sha256(), 0, []
        while True:
            data = os.read(fd, min(1024 * 1024, limit + 1 - size))
            if not data:
                break
            size += len(data)
            require(size <= limit, "invalid-file-size-or-type")
            digest.update(data)
            if capture:
                chunks.append(data)
        require(size == info.st_size, "file-changed")
        return digest.hexdigest(), size, b"".join(chunks)
    finally:
        os.close(fd)


def parse_json(data, public=False):
    def pairs(entries):
        result = {}
        for key, value in entries:
            require(key not in result, "duplicate-json-key")
            result[key] = value
        return result

    def constant(_value):
        raise ValueError("invalid-json-number")

    require(len(data) <= JSON_LIMIT, "json-too-large")
    value = json.loads(data, object_pairs_hook=pairs, parse_constant=constant)
    pending, count = [(value, 0)], 0
    while pending:
        item, depth = pending.pop()
        count += 1
        require(depth <= 32 and count <= 20000, "json-too-complex")
        if isinstance(item, dict):
            if public:
                require(not any(re.search(r"password|credential|secret|token|private.?key|api.?key|authorization|access.?key", key, re.I)
                                for key in item), "private-public-content")
            pending.extend((entry, depth + 1) for entry in item.values())
            pending.extend((key, depth + 1) for key in item)
        elif isinstance(item, list):
            pending.extend((entry, depth + 1) for entry in item)
        elif isinstance(item, str):
            require(len(item) <= 16384, "json-string-too-long")
    if public:
        require(not PRIVATE_TEXT.search(json.dumps(value)), "private-public-content")
    return value


def indexed(entries, key="id"):
    require(isinstance(entries, list) and 0 < len(entries) <= 2000, "invalid-list")
    result = {}
    for entry in entries:
        require(isinstance(entry, dict), "invalid-fields")
        identity = identifier(entry.get(key))
        require(identity not in result, "duplicate-identity")
        result[identity] = entry
    return result


def verify(manifest_path, private_root):
    require(not manifest_path.is_symlink() and not private_root.is_symlink(), "unsafe-path")
    public_root = manifest_path.parent.resolve()
    manifest = parse_json(read_file(public_root, manifest_path.name, JSON_LIMIT, True)[2], True)
    fields(manifest, ("schemaVersion", "evidenceClass", "candidate", "candidateRef", "originIndexes",
                      "documents", "sourceCI", "priorResults", "publicReview"))
    require(type(manifest["schemaVersion"]) is int and manifest["schemaVersion"] == 1
            and manifest["evidenceClass"] in ("actual", "fixture"), "invalid-schema")
    documents = manifest["documents"]
    fields(documents, ("tuples", "results", "restrictedIndex", "report"))
    seen_paths, loaded = {manifest_path.name}, {}

    def public_document(reference, text=False):
        fields(reference, ("path", "sha256"))
        relative(reference["path"])
        sha(reference["sha256"])
        require(reference["path"] not in seen_paths, "duplicate-reference")
        seen_paths.add(reference["path"])
        digest, _, data = read_file(public_root, reference["path"], JSON_LIMIT, True)
        require(digest == reference["sha256"], "checksum-mismatch")
        if text:
            value = data.decode("utf-8")
            require(not PRIVATE_TEXT.search(value), "private-public-content")
            require("AC15" in value and "AC17" in value, "report-gate-links-missing")
            return value
        return parse_json(data, True)

    for kind, reference in documents.items():
        loaded[kind] = public_document(reference, kind == "report")
    review = manifest["publicReview"]
    fields(review, ("reviewer", "status", "scope"))
    identifier(review["reviewer"])
    require(review["status"] == "reviewed" and review["scope"] == "text-only", "public-review-required")
    restricted = loaded["restrictedIndex"]
    fields(restricted, ("schemaVersion", "storage", "files"))
    fields(restricted["storage"], ("id", "custodian", "access"))
    for value in restricted["storage"].values():
        identifier(value)
    private = indexed(restricted["files"])
    private_paths = set()
    for entry in private.values():
        fields(entry, ("id", "path", "bytes", "sha256"))
        relative(entry["path"])
        sha(entry["sha256"])
        require(type(entry["bytes"]) is int and 0 <= entry["bytes"] <= FILE_LIMIT, "invalid-file-size-or-type")
        require(entry["path"] not in private_paths, "duplicate-reference")
        private_paths.add(entry["path"])
    require(sum(entry["bytes"] for entry in private.values()) <= 2 * 1024 * 1024 * 1024, "evidence-too-large")
    raw = {}
    for identity, entry in private.items():
        is_json = entry["path"].endswith(".json")
        digest, size, data = read_file(private_root, entry["path"], JSON_LIMIT if is_json else FILE_LIMIT, is_json)
        require((digest, size) == (entry["sha256"], entry["bytes"]), "checksum-mismatch")
        if is_json:
            raw[identity] = parse_json(data)
    candidate = manifest["candidate"]
    fields(candidate, ("schemaVersion", "productVersion", "sourceSHA", "coreBuildIdentity", "ciRun",
                       "signing", "notarization", "distributionReady", "artifacts"))
    sha(candidate["sourceSHA"], 40)
    sha(candidate["coreBuildIdentity"])
    identifier(candidate["productVersion"])
    require(type(candidate["schemaVersion"]) is int and candidate["schemaVersion"] == 1
            and type(candidate["distributionReady"]) is bool, "invalid-candidate")
    require((candidate["signing"], candidate["notarization"]) in
            (("unsigned", "not-requested"), ("developer-id", "accepted")), "invalid-candidate")
    require(candidate["signing"] != "unsigned" or candidate["distributionReady"] is False, "invalid-candidate")
    candidate_ref = identifier(manifest["candidateRef"])
    require(candidate_ref in raw and json.dumps(candidate, sort_keys=True)
            == json.dumps(raw[candidate_ref], sort_keys=True), "candidate-mismatch")
    candidate_id = private[candidate_ref]["sha256"]
    fields(candidate["artifacts"], ("cli", "gui", "homebrew"))
    for artifact in candidate["artifacts"].values():
        fields(artifact, ("file", "sha256"))
        relative(artifact["file"])
        sha(artifact["sha256"])
        # Artifact names are relative to CANDIDATE.json, as in the #222 candidate contract.
        path = str(Path(private[candidate_ref]["path"]).parent / artifact["file"])
        require(any(e["path"] == path and e["sha256"] == artifact["sha256"] for e in private.values()), "artifact-reference-missing")
    origins = manifest["originIndexes"]
    require(isinstance(origins, list) and 0 < len(origins) <= 32 and len(origins) == len(set(origins)), "invalid-origin-index")
    origin_files = {}
    for identity in origins:
        require(identity in raw, "missing-reference")
        origin = raw[identity]
        require(type(origin.get("schemaVersion")) is int and origin["schemaVersion"] == 1
                and origin.get("sourceSHA") == candidate["sourceSHA"], "candidate-mismatch")
        require(isinstance(origin.get("files"), list), "invalid-origin-index")
        names = set()
        for entry in origin["files"]:
            name = entry["file"]
            require(type(entry["bytes"]) is int and entry["bytes"] >= 0, "invalid-file-size-or-type")
            require(name not in names, "duplicate-reference")
            names.add(name)
            value = (entry["SHA256"], entry["bytes"])
            require(name not in origin_files or origin_files[name] == value, "conflicting-origin-index")
            origin_files[name] = value
        if "priorIndexSHA256" in origin:
            require(any(private[ref]["sha256"] == origin["priorIndexSHA256"] for ref in origins if ref != identity), "origin-history-mismatch")
    for identity, entry in private.items():
        if identity not in origins:
            require(origin_files.get("evidence/" + entry["path"]) == (entry["sha256"], entry["bytes"]), "unindexed-private-reference")
    ci = manifest["sourceCI"]
    fields(ci, ("evidence", "runID"))
    require(type(ci["runID"]) is int and ci["runID"] > 0, "invalid-ci-run")
    require(ci["evidence"] in raw, "missing-reference")
    ci_receipt = raw[ci["evidence"]]
    require(ci_receipt.get("headSha") == candidate["sourceSHA"] and type(ci_receipt.get("databaseId")) is int
            and ci_receipt["databaseId"] == ci["runID"], "candidate-mismatch")
    jobs = ci_receipt.get("jobs", [])
    ci_pass = (ci_receipt.get("name") == "CI" and ci_receipt.get("status") == "completed"
               and ci_receipt.get("conclusion") == "success" and isinstance(jobs, list) and bool(jobs)
               and any(job.get("name") == "CI" for job in jobs)
               and all(job.get("status") == "completed" and job.get("conclusion") == "success" for job in jobs))
    tuples_document, results = loaded["tuples"], loaded["results"]
    fields(tuples_document, ("schemaVersion", "tuples"))
    fields(results, ("schemaVersion", "requirements", "attempts"))
    require(all(type(document["schemaVersion"]) is int and document["schemaVersion"] == 1
                for document in (restricted, tuples_document, results)), "invalid-schema")
    tuples = indexed(tuples_document["tuples"])
    for entry in tuples.values():
        fields(entry, ("id", "candidateID", "inputs"))
        require(entry["candidateID"] == candidate_id and isinstance(entry["inputs"], dict) and bool(entry["inputs"]), "candidate-mismatch")
        require(all(isinstance(value, str) and bool(value.strip()) for value in entry["inputs"].values()), "invalid-tuple")
    requirements = indexed(results["requirements"])
    require({entry["gate"] for entry in requirements.values()} == GATES, "required-gate-missing")
    for entry in requirements.values():
        fields(entry, ("id", "gate", "tupleID", "sampleID", "sampleSHA", "frontend"))
        require(entry["tupleID"] in tuples and entry["frontend"] in ("CLI", "GUI", "shared"), "missing-reference")
        identifier(entry["sampleID"])
    attempts = indexed(results["attempts"])
    current = {}
    for identity, attempt in attempts.items():
        fields(attempt, ("id", "requirementID", "candidateID", "tupleID", "sampleID", "sampleSHA",
                         "frontend", "evidenceClass", "expected", "observed", "observedAt", "executor",
                         "result", "evidence", "unverified", "supersedes"))
        requirement = requirements.get(attempt["requirementID"])
        require(requirement is not None and attempt["candidateID"] == candidate_id, "candidate-mismatch")
        require(all(attempt[key] == requirement[key] for key in ("tupleID", "sampleID", "sampleSHA", "frontend")), "attempt-identity-mismatch")
        if attempt["sampleSHA"] != "unknown":
            sha(attempt["sampleSHA"], 40)
        require(attempt["evidenceClass"] == manifest["evidenceClass"], "fixture-promotion")
        require(attempt["result"] in ("pass", "fail", "inconclusive", "unverified", "unknown"), "invalid-result")
        require(all(isinstance(attempt[key], str) and bool(attempt[key].strip()) for key in ("expected", "observed")), "missing-observation")
        identifier(attempt["executor"])
        observed_at = attempt["observedAt"]
        require(isinstance(observed_at, str), "invalid-observation-time")
        if observed_at != "unknown":
            require(re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:Z|[+-]\d{2}:\d{2})", observed_at), "invalid-observation-time")
            datetime.fromisoformat(observed_at.replace("Z", "+00:00"))
        references = attempt["evidence"]
        require(isinstance(references, list) and bool(references) and len(references) == len(set(references))
                and all(ref in private for ref in references), "missing-reference")
        require(isinstance(attempt["unverified"], list)
                and all(isinstance(value, str) and bool(value.strip()) for value in attempt["unverified"]), "invalid-unverified")
        previous = current.get(attempt["requirementID"])
        require(attempt["supersedes"] == previous, "invalid-retest-history")
        if previous is not None:
            require(attempt["sampleSHA"] == attempts[previous]["sampleSHA"], "attempt-identity-mismatch")
        current[attempt["requirementID"]] = identity
    require(set(current) == set(requirements), "required-result-missing")
    require(isinstance(manifest["priorResults"], list) and len(manifest["priorResults"]) <= 32, "invalid-history")
    for reference in manifest["priorResults"]:
        previous = public_document(reference)
        fields(previous, ("schemaVersion", "requirements", "attempts"))
        require(type(previous["schemaVersion"]) is int and previous["schemaVersion"] == 1, "invalid-schema")
        for identity, attempt in indexed(previous["attempts"]).items():
            require(attempts.get(identity) == attempt, "history-rewritten")
        for identity, entry in indexed(previous["requirements"]).items():
            require(requirements.get(identity) == entry, "history-rewritten")
    blockers = []
    if any(attempts[identity]["result"] != "pass" or attempts[identity]["unverified"]
           or attempts[identity]["sampleSHA"] == "unknown" for identity in current.values()):
        blockers.append("required-results")
    if any(attempts[identity]["observedAt"] == "unknown" or attempts[identity]["executor"].lower() == "unknown"
           for identity in current.values()):
        blockers.append("attempt-provenance-unverified")
    if any(value.strip().lower() in ("unknown", "unverified", "inconclusive")
           for entry in tuples.values() for value in entry["inputs"].values()):
        blockers.append("tuple-inputs-unverified")
    gate_evaluation = "blocked" if blockers else "pass"
    if manifest["evidenceClass"] == "fixture":
        blockers.append("fixture-evidence")
    if candidate["signing"] != "developer-id" or candidate["notarization"] != "accepted" or not candidate["distributionReady"]:
        blockers.append("distribution-unverified")
    if not ci_pass:
        blockers.append("source-ci-unverified")
    return {"schemaVersion": 1, "evidenceIntegrity": "verified", "gateEvaluation": gate_evaluation,
            "releaseDecision": "blocked" if blockers else "pass", "blockers": blockers,
            "sourceSHA": candidate["sourceSHA"], "candidateID": candidate_id,
            "requirements": len(requirements), "attempts": len(attempts), "privateFiles": len(private),
            "coverage": "declared-requirements-only"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--private-root", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = verify(args.manifest, args.private_root)
    except (ValueError, OSError, KeyError, TypeError, AttributeError, RecursionError, OverflowError):
        # Do not echo untrusted values, credential contents, or host paths in diagnostics.
        result = {"schemaVersion": 1, "evidenceIntegrity": "invalid", "releaseDecision": "blocked",
                  "errors": ["invalid-evidence"]}
    print(json.dumps(result, sort_keys=True))
    return 0 if result["releaseDecision"] == "pass" else 1


if __name__ == "__main__":
    sys.exit(main())

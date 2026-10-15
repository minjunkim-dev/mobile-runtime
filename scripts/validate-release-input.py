#!/usr/bin/env python3
"""Reject release inputs that are not a verified, unpublished main commit."""

import json
import hashlib
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys


def validate_inputs(version, source_sha):
    number = r"(?:0|[1-9][0-9]*)"
    if not re.fullmatch(rf"{number}\.{number}\.{number}-alpha\.{number}", version):
        raise ValueError("version must be an alpha version, e.g. 0.1.0-alpha.5")
    if not re.fullmatch(r"[0-9a-f]{40}", source_sha):
        raise ValueError("source SHA must be a full lowercase 40-character commit SHA")


def validate_ci(runs, source_sha):
    if not any(
        run.get("head_sha") == source_sha
        and run.get("head_branch") == "main"
        and run.get("event") == "push"
        and run.get("status") == "completed"
        and run.get("conclusion") == "success"
        and run.get("path") == ".github/workflows/ci.yml"
        for run in runs
    ):
        raise ValueError("source SHA must have a successful main push CI run")


def validate_unused_version(releases, refs, version):
    tag = f"v{version}"
    if any(release.get("tag_name") == tag for release in releases):
        raise ValueError("version already has a release; drafts are not overwritten")
    if any(ref.get("ref") == f"refs/tags/{tag}" for ref in refs):
        raise ValueError("version already has a Git tag")


def validate_candidate(candidate, cli, gui):
    version, source = candidate.get("productVersion"), candidate.get("sourceSHA")
    if not isinstance(version, str) or not isinstance(source, str):
        raise ValueError("candidate requires a product version and source SHA")
    validate_inputs(version, source)
    core = candidate.get("coreBuildIdentity")
    if not isinstance(core, str) or not re.fullmatch(r"[0-9a-f]{64}", core):
        raise ValueError("candidate requires an exact Core build digest")
    expected = {"releaseVersion": version, "toolVersion": version,
                "sourceRevision": source, "coreBuildIdentity": core}
    for build in (cli, gui):
        if any(build.get(key) != value for key, value in expected.items()):
            raise ValueError("CLI, GUI and Core must use the same source, version and build")


def validate_candidate_archive(members, version):
    root = f"runstir-{version}-macos-arm64"
    for member in members:
        path = PurePosixPath(member.name)
        if (path.is_absolute() or ".." in path.parts or not path.parts
                or path.parts[0] != root or not (member.isfile() or member.isdir())):
            raise ValueError("candidate archive contains an unsafe or unexpected member")


def validate_candidate_artifacts(candidate, directory):
    version = candidate.get("productVersion")
    validate_inputs(version, candidate.get("sourceSHA"))
    expected = {"cli": f"runstir-{version}-macos-arm64.tar.gz",
                "gui": f"Runstir-{version}-macos-arm64.dmg",
                "homebrew": "runstir-candidate.rb"}
    artifacts = candidate.get("artifacts", {})
    if set(artifacts) != set(expected):
        raise ValueError("candidate must include CLI, GUI and Homebrew artifacts")
    for kind, name in expected.items():
        artifact = artifacts[kind]
        if artifact.get("file") != name:
            raise ValueError("unexpected candidate artifact path")
        if hashlib.sha256((Path(directory) / name).read_bytes()).hexdigest() != artifact.get("sha256"):
            raise ValueError("candidate artifact checksum mismatch")


def api(endpoint, paginate=False):
    args = ["gh", "api", endpoint]
    if paginate:
        args += ["--paginate", "--slurp"]
    return json.loads(subprocess.check_output(args, text=True))


def main():
    version, source_sha = sys.argv[1:]
    validate_inputs(version, source_sha)
    subprocess.run(
        ["git", "merge-base", "--is-ancestor", source_sha, "origin/main"], check=True
    )
    repo = os.environ["GH_REPO"]
    pages = api(
        f"repos/{repo}/actions/workflows/ci.yml/runs?head_sha={source_sha}&per_page=100",
        paginate=True,
    )
    validate_ci([run for page in pages for run in page["workflow_runs"]], source_sha)
    releases = api(f"repos/{repo}/releases?per_page=100", paginate=True)
    refs = api(f"repos/{repo}/git/matching-refs/tags/v{version}")
    validate_unused_version([release for page in releases for release in page], refs, version)
    print(f"Verified release input: {version} / {source_sha}")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error)) from error

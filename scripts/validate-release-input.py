#!/usr/bin/env python3
"""Reject release inputs that are not a verified, unpublished main commit."""

import json
import os
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

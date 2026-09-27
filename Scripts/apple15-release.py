#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
# SPDX-License-Identifier: MIT

"""Prepare and publish a compatibility tag from an exact release commit."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


SETTING = 'let isLoweredDeploymentTargetEnabled = Context.environment["GROVE_LOWERED_DEPLOYMENT_TARGETS"] '
STANDARD = SETTING + '== "1"'
LOWERED = SETTING + '!= "0"'
VERSION = re.compile(
    r"v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"
)


def compatibility_tag(tag):
    """Build metadata is deliberately unsupported: it does not distinguish SPM versions."""
    match = VERSION.fullmatch(tag)
    if not match:
        raise ValueError(f"Expected a SemVer release tag without build metadata: {tag!r}")
    prerelease = match[4]
    if prerelease and any(part.isdigit() and len(part) > 1 and part[0] == "0" for part in prerelease.split(".")):
        raise ValueError("Numeric prerelease identifiers must not have leading zeros")
    if prerelease and (prerelease == "apple15" or prerelease.startswith(("apple15-", "apple15."))):
        return None
    base = tag.split("-", 1)[0]
    return base + "-apple15" + ("-" + prerelease if prerelease else "")


def git(*args, env=None, input=None):
    return subprocess.run(
        ["git", *args], check=True, text=True, input=input, capture_output=True, env=env
    ).stdout.strip()


def patched_manifest(source):
    lines = source.splitlines()
    matches = [index for index, line in enumerate(lines) if line.startswith(SETTING)]
    if len(matches) != 1 or lines[matches[0]] not in (STANDARD, LOWERED):
        raise ValueError("Unrecognized deployment switch; review the release patch before publishing")
    return source.replace(lines[matches[0]], LOWERED, 1)


def prepare(source_tag, source_sha):
    target = compatibility_tag(source_tag)
    if target is None:
        raise ValueError("Compatibility releases cannot generate another compatibility tag")
    if not re.fullmatch(r"[0-9a-f]{40}", source_sha):
        raise ValueError("An exact 40-character release commit is required")
    if git("rev-parse", "HEAD") != source_sha or git("rev-parse", f"refs/tags/{source_tag}^{{commit}}") != source_sha:
        raise ValueError("Checkout and source tag must both match the release event commit")
    if git("status", "--porcelain", "--untracked-files=no"):
        raise ValueError("Prepare requires a clean checkout")
    if any(Path(".").glob("Package@swift-*.swift")):
        raise ValueError("Version-specific manifests require an explicit compatibility patch")
    manifest = Path("Package.swift")
    patched = patched_manifest(manifest.read_bytes().decode("utf-8"))
    # A separate index leaves the caller's index and branch untouched.
    with tempfile.TemporaryDirectory() as directory:
        env = dict(os.environ, GIT_INDEX_FILE=str(Path(directory) / "index"))
        git("read-tree", source_sha, env=env)
        blob = git("hash-object", "-w", "--stdin", input=patched)
        mode = git("ls-tree", source_sha, "--", "Package.swift").split()[0]
        git("update-index", "--add", "--cacheinfo", mode, blob, "Package.swift", env=env)
        tree = git("write-tree", env=env)
    manifest.write_bytes(patched.encode("utf-8"))
    return target, tree


def validate_defaults(dump):
    platforms = {item["platformName"]: item["version"] for item in dump["platforms"]}
    for name, version in {"ios": "15.0", "macos": "12.0", "watchos": "9.0"}.items():
        if platforms.get(name) != version:
            raise ValueError(f"Unexpected {name} floor: {platforms.get(name)!r}")
    defaults = [trait for trait in dump["traits"] if trait["name"] == "default"]
    if len(defaults) != 1 or defaults[0]["enabledTraits"]:
        raise ValueError("Compatibility releases must have an empty default trait set")


def verify_existing(ref, source_sha, tree, message):
    if git("cat-file", "-t", ref) != "tag":
        raise ValueError("Existing compatibility tag is not an annotated tag")
    commit = git("rev-parse", f"{ref}^{{commit}}")
    if (git("show", "-s", "--format=%P", commit) != source_sha
            or git("rev-parse", f"{commit}^{{tree}}") != tree
            or git("show", "-s", "--format=%B", commit) != message):
        raise ValueError("Existing compatibility tag conflicts with the expected release; refusing to replace it")


def publish(source_tag, source_sha, tree, expected_tree, target):
    if tree != expected_tree:
        raise ValueError("Publication tree differs from the tree validated by the floor builds")
    message = f"Enable Apple 15 Compatibility for {source_tag}"
    # Recheck the remote source: a moved release tag must never select new source code.
    git("fetch", "--no-tags", "origin", f"refs/tags/{source_tag}")
    if git("rev-parse", "FETCH_HEAD^{commit}") != source_sha:
        raise ValueError("The published source tag has moved")
    existing = git("ls-remote", "--refs", "origin", f"refs/tags/{target}")
    if existing:
        git("fetch", "--no-tags", "origin", f"refs/tags/{target}")
        verify_existing("FETCH_HEAD", source_sha, tree, message)
        print(f"{target} already exists and matches the validated release")
        return
    commit = git("commit-tree", tree, "-p", source_sha, input=message + "\n")
    git("tag", "-a", target, commit, "-m", message)
    verify_existing(f"refs/tags/{target}", source_sha, tree, message)
    git("push", "origin", f"refs/tags/{target}:refs/tags/{target}")
    print(f"Published {target}: {commit}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["tag", "prepare", "validate-defaults", "publish"])
    parser.add_argument("--source-tag")
    parser.add_argument("--source-sha")
    parser.add_argument("--expected-tree")
    parser.add_argument("--dump", type=Path)
    args = parser.parse_args()
    if args.command == "validate-defaults":
        if args.dump is None:
            parser.error("--dump is required")
        validate_defaults(json.loads(args.dump.read_text()))
        return
    if not args.source_tag:
        parser.error("--source-tag is required")
    if args.command == "tag":
        print(compatibility_tag(args.source_tag) or "")
        return
    if not args.source_sha or (args.command == "publish" and not args.expected_tree):
        parser.error("--source-sha is required; publish also requires --expected-tree")
    target, tree = prepare(args.source_tag, args.source_sha)
    if args.command == "publish":
        publish(args.source_tag, args.source_sha, tree, args.expected_tree, target)
    else:
        if output := os.environ.get("GITHUB_OUTPUT"):
            with open(output, "a") as file:
                file.write(f"tag={target}\ntree={tree}\n")
        print(f"{target}: {tree}")


if __name__ == "__main__":
    try:
        main()
    except ValueError as error:
        raise SystemExit(str(error)) from error
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.stderr or str(error)) from error

#!/usr/bin/env python3
"""Install the guide packages a grove-fhir release built, or compare them with packages built from source.

Building the grove-fhir implementation guides renders and link-checks thousands of pages, to produce one package.tgz
each. A release attaches those packages already. This checks each against the release's SHA256SUMS, and the release's
build provenance against the grove-fhir commit checked out, then installs it where a guide build puts it. A marker
beside it records the download, so a later build or comparison never takes it for a build; a build replaces the whole
output directory, marker included.

The validator runs offline and resolves every package dependency from its cache, which a guide build fills as it goes.
Without one, this installs the downloaded packages there, and every dependency they declare that the cache lacks, each
checked against the checksum the package registry publishes for it.

  Scripts/fetch-grove-fhir-release-packages.py --guides <grove-fhir> --release 0.8.0 --commit <sha> \\
      --fhir-home <grove-fhir>/.build/fhir-home mobile sensor healthkit
  Scripts/fetch-grove-fhir-release-packages.py --guides <grove-fhir> --release 0.8.0 --commit <sha> --compare \\
      mobile sensor healthkit
"""

# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Callable


RELEASES = "https://github.com/SchmiedmayerLab/grove-fhir/releases/download"
REGISTRY = "https://packages.fhir.org"
GROVE_PACKAGE_PREFIX = "org.grovealliance.fhir."
# validate-fhir-conformance.sh rebuilds a guide whose package carries this marker.
RELEASE_MARKER = "package.tgz.release"
DOWNLOAD_ATTEMPTS = 3

Fetch = Callable[[str], bytes]
Install = Callable[[Path], None]


class ReleaseError(RuntimeError):
    """The release's packages cannot stand in for a build of the checked-out commit."""


def fetch_url(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "grove-fhir-conformance"})
    failure: OSError | None = None
    for attempt in range(1, DOWNLOAD_ATTEMPTS + 1):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            if error.code == 404:
                raise ReleaseError(f"{url} does not exist") from error
            failure = error
        except OSError as error:
            failure = error
        if attempt < DOWNLOAD_ATTEMPTS:
            time.sleep(5 * attempt)
    raise ReleaseError(f"could not download {url}: {failure}")


def package_asset(guide: str, release: str) -> str:
    return f"{GROVE_PACKAGE_PREFIX}{guide}-{release}.tgz"


def parse_checksums(text: str) -> dict[str, str]:
    checksums: dict[str, str] = {}
    for line in text.splitlines():
        if not line.strip():
            continue
        digest, separator, name = line.partition("  ")
        if not separator or len(digest) != 64 or not name:
            raise ReleaseError(f"malformed SHA256SUMS line: {line!r}")
        checksums[name] = digest
    return checksums


def fetch_release(fetch: Fetch, release: str, commit: str, guides: list[str], directory: Path) -> dict[str, Path]:
    """Download the guides' packages into <directory>/<guide>.tgz once every check passes, keyed by guide."""
    base = f"{RELEASES}/{release}"
    checksums = parse_checksums(fetch(f"{base}/SHA256SUMS").decode("utf-8"))

    def verified(asset: str) -> bytes:
        expected = checksums.get(asset)
        if expected is None:
            raise ReleaseError(f"the grove-fhir {release} release lists no checksum for {asset}")
        data = fetch(f"{base}/{asset}")
        if hashlib.sha256(data).hexdigest() != expected:
            raise ReleaseError(f"{asset} does not match the checksum the grove-fhir {release} release lists")
        return data

    # The checksums only vouch for the bytes; the conformance checks read their catalogs from the commit checked out.
    provenance = json.loads(verified(f"build-provenance-{release}.json"))
    if provenance.get("releaseVersion") != release or provenance.get("sourceRevision") != commit:
        raise ReleaseError(
            f"the grove-fhir {release} release records version {provenance.get('releaseVersion')} built from "
            f"{provenance.get('sourceRevision')}, not {release} built from {commit}"
        )
    contents = {guide: verified(package_asset(guide, release)) for guide in guides}
    packages: dict[str, Path] = {}
    for guide, data in contents.items():
        packages[guide] = directory / f"{guide}.tgz"
        packages[guide].write_bytes(data)
    return packages


def package_manifest(package: Path) -> dict[str, Any]:
    with tarfile.open(package, "r:gz") as archive:
        member = archive.extractfile("package/package.json")
        if member is None:
            raise ReleaseError(f"{package} has no package/package.json")
        return json.load(member)


def seed_cache(fetch: Fetch, install: Install, packages: list[Path], cache: Path) -> list[str]:
    """Install the packages into the cache, then every dependency they declare that it lacks, transitively."""
    for package in packages:
        install(package)
    installed: list[str] = []
    pending = list(packages)
    seen: set[str] = set()
    with tempfile.TemporaryDirectory(prefix="grove-fhir-dependencies-") as directory:
        while pending:
            for name, version in sorted(package_manifest(pending.pop()).get("dependencies", {}).items()):
                key = f"{name}#{version}"
                if key in seen or (cache / key).is_dir():
                    continue
                seen.add(key)
                if name.startswith(GROVE_PACKAGE_PREFIX):
                    raise ReleaseError(f"{key} is not cached; install its guide together with the guides needing it")
                versions = json.loads(fetch(f"{REGISTRY}/{name}")).get("versions", {})
                expected = versions.get(version, {}).get("dist", {}).get("shasum")
                if not expected:
                    raise ReleaseError(f"{REGISTRY} publishes no checksum for {key}")
                data = fetch(f"{REGISTRY}/{name}/{version}")
                if hashlib.sha1(data).hexdigest() != expected:
                    raise ReleaseError(f"{key} does not match the checksum {REGISTRY} publishes for it")
                dependency = Path(directory) / f"{key}.tgz"
                dependency.write_bytes(data)
                install(dependency)
                installed.append(key)
                pending.append(dependency)
    return installed


def install_release(fetch: Fetch, install: Install, release: str, commit: str, guides_root: Path,
                    guides: list[str], cache: Path) -> list[str]:
    """Install the release's packages for the guides, replacing whatever is there, and seed the validator's cache."""
    with tempfile.TemporaryDirectory(prefix="grove-fhir-release-") as directory:
        downloaded = fetch_release(fetch, release, commit, guides, Path(directory))
        for guide, package in downloaded.items():
            output = guides_root / guide / "output"
            output.mkdir(parents=True, exist_ok=True)
            # The marker goes first: a package without it would pass for a build.
            (output / RELEASE_MARKER).write_text(f"{release}\n", encoding="utf-8")
            shutil.copyfile(package, output / "package.tgz")
    return seed_cache(fetch, install, [guides_root / guide / "output" / "package.tgz" for guide in guides], cache)


def compare_release(fetch: Fetch, release: str, commit: str, guides_root: Path, guides: list[str]) -> list[str]:
    """Return the guides whose built package differs from the release's in grove-fhir's semantic snapshot."""
    for guide in guides:
        output = guides_root / guide / "output"
        if (output / RELEASE_MARKER).exists():
            raise ReleaseError(f"{output / 'package.tgz'} came from the {release} release; build the guides first")
        if not (output / "package.tgz").is_file():
            raise ReleaseError(f"{output / 'package.tgz'} is missing; build the guides first")
    scripts = guides_root / "Scripts"
    differing: list[str] = []
    with tempfile.TemporaryDirectory(prefix="grove-fhir-compare-") as directory:
        staging = Path(directory)
        released = fetch_release(fetch, release, commit, guides, staging)
        for guide in guides:
            # The snapshot drops what differs between any two builds of a guide: timestamps and generated narratives.
            snapshots = {
                "release": (released[guide], staging / f"{guide}-release.json"),
                "built": (guides_root / guide / "output" / "package.tgz", staging / f"{guide}-built.json"),
            }
            for package, snapshot in snapshots.values():
                subprocess.run(
                    [sys.executable, str(scripts / "fhir_package_semantic_snapshot.py"), str(package),
                     "--output", str(snapshot)],
                    check=True,
                )
            report = staging / f"{guide}-diff.json"
            result = subprocess.run([
                sys.executable, str(scripts / "fhir_package_semantic_diff.py"),
                str(snapshots["release"][1]), str(snapshots["built"][1]),
                "--output", str(report), "--fail-on-change",
            ])
            if result.returncode not in (0, 1):
                raise ReleaseError(f"the semantic diff of the {guide} package failed")
            if result.returncode == 1:
                print(report.read_text(encoding="utf-8")[:4000], file=sys.stderr)
                differing.append(guide)
            else:
                print(f"    {guide} matches")
    return differing


def cache_installer(guides_root: Path, cache: Path) -> Install:
    script = guides_root / "Scripts" / "cache-fhir-package.cjs"

    def install(package: Path) -> None:
        subprocess.run(
            ["node", str(script), "--cache-root", str(cache), str(package)],
            check=True,
            stdout=subprocess.DEVNULL,
        )

    return install


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--guides", type=Path, required=True, help="the grove-fhir checkout")
    parser.add_argument("--release", required=True, help="the grove-fhir release tag")
    parser.add_argument("--commit", required=True, help="the grove-fhir commit checked out")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--fhir-home", type=Path, help="install into this validator home")
    mode.add_argument("--compare", action="store_true", help="compare the built packages with the release's")
    parser.add_argument("guides_to_fetch", nargs="+", metavar="guide")
    arguments = parser.parse_args(argv)
    try:
        if arguments.compare:
            differing = compare_release(
                fetch_url, arguments.release, arguments.commit, arguments.guides, arguments.guides_to_fetch
            )
            if differing:
                raise ReleaseError(
                    f"the {', '.join(differing)} package built from source differs from the grove-fhir "
                    f"{arguments.release} release"
                )
            return 0
        cache = arguments.fhir_home / ".fhir" / "packages"
        installed = install_release(
            fetch_url, cache_installer(arguments.guides, cache), arguments.release, arguments.commit,
            arguments.guides, arguments.guides_to_fetch, cache,
        )
        for key in installed:
            print(f"    cached dependency {key}")
        return 0
    except ReleaseError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

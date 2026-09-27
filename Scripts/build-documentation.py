#!/usr/bin/env python3
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#

"""Build and validate the documentation targets declared in .spi.yml."""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import sys

from build_support import run_build, run_cli, run_command


def documentation_targets(path: Path) -> list[str]:
    lines = path.read_text(encoding="utf-8").splitlines()
    for index, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("- "):
            stripped = stripped[2:].strip()
        if not stripped.startswith("documentation_targets:"):
            continue

        value = stripped.split(":", maxsplit=1)[1].strip()
        if value.startswith("[") and value.endswith("]"):
            targets = [
                target.strip().strip("'\"")
                for target in value[1:-1].split(",")
                if target.strip()
            ]
        else:
            targets = []
            parent_indent = len(line) - len(line.lstrip())
            for child in lines[index + 1:]:
                child_stripped = child.strip()
                if not child_stripped or child_stripped.startswith("#"):
                    continue
                child_indent = len(child) - len(child.lstrip())
                if child_indent <= parent_indent:
                    break
                if child_stripped.startswith("- "):
                    targets.append(child_stripped[2:].strip().strip("'\""))
        if targets:
            return targets
        break
    raise ValueError("Could not find documentation_targets in .spi.yml")


def documentation_warnings(repo: Path, log_path: Path) -> list[str]:
    repo_prefix = f"{repo.resolve()}/"
    ignored_markers = (
        f"{repo_prefix}.build/",
        f"{repo_prefix}.derivedData",
        "/SourcePackages/",
    )
    warnings = []
    for line in log_path.read_text(encoding="utf-8", errors="replace").splitlines():
        stripped = line.strip()
        # Catalog-level DocC diagnostics have no source location. Keep these even
        # when the normal repository-path filter would otherwise discard them.
        if stripped.startswith("warning: "):
            if stripped not in warnings:
                warnings.append(stripped)
            continue
        if ": warning:" not in line or repo_prefix not in line:
            continue
        if any(marker in line for marker in ignored_markers):
            continue
        # Symbol links also live in Swift comments; ordinary compiler warnings
        # in Sources are outside this documentation gate.
        if ("/Sources/" in line and ".docc/" in line) or any(
            marker in line
            for marker in (
                " doesn't exist at ",
                " is ambiguous at ",
                " isn't a disambiguation for ",
                "used to document parameter",
                "Parameter '",
                " not found in ",
            )
        ):
            warnings.append(line)
    return warnings


def find_archive(products: Path, target: str) -> Path | None:
    """Match find's directory-only search without following directory symlinks."""
    def search(directory: Path, depth: int) -> Path | None:
        if directory.name == f"{target}.doccarchive":
            return directory
        if depth == 3:
            return None
        with os.scandir(directory) as entries:
            for entry in entries:
                if entry.is_dir(follow_symlinks=False):
                    archive = search(directory / entry.name, depth + 1)
                    if archive is not None:
                        return archive
        return None

    return search(products, 0)


def remove_archive(path: Path) -> None:
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.exists():
        shutil.rmtree(path)


def main() -> int:
    os.chdir(Path(__file__).resolve().parent.parent)
    env = os.environ.copy()
    env["PWD"] = str(Path.cwd())
    runner_temp = env.get("RUNNER_TEMP")
    derived_data = env.get("DERIVED_DATA_PATH") or (
        f"{runner_temp}/grove-docs-derivedData" if runner_temp else ".derivedData-docs"
    )
    output_dir = env.get("DOC_OUTPUT_DIR") or (
        f"{runner_temp}/grove-documentation" if runner_temp else ".build/documentation"
    )
    scheme = env.get("DOC_SCHEME") or "Grove-Package"
    destination = env.get("DOC_DESTINATION") or "generic/platform=iOS Simulator"
    deployment_target = env.get("DOC_DEPLOYMENT_TARGET") or "18.0"
    log_path = Path(env.get("DOC_LOG_PATH") or f"{output_dir}/docbuild.log")
    combined_archive = env.get("COMBINED_ARCHIVE") or f"{output_dir}/Grove.doccarchive"
    static_archive = env.get("STATIC_ARCHIVE") or f"{output_dir}/Grove-static.doccarchive"
    targets = documentation_targets(Path(".spi.yml"))

    Path(output_dir).mkdir(parents=True, exist_ok=True)
    remove_archive(Path(combined_archive))
    remove_archive(Path(static_archive))
    env["GROVE_LOWERED_DEPLOYMENT_TARGETS"] = "0"
    env["GROVE_ENABLE_DEFAULT_PACKAGE_TRAITS"] = env.get("GROVE_ENABLE_DEFAULT_PACKAGE_TRAITS") or "1"
    env["GROVE_EXCLUDE_DOCC_CATALOGS"] = "0"
    env["LLVM_PROFILE_FILE"] = env.get("LLVM_PROFILE_FILE") or f"{output_dir}/default-%p.profraw"

    print(f"Building DocC documentation for scheme '{scheme}' with all default package traits enabled.", flush=True)
    # The simulator libraries and host tools need only the Apple Silicon architecture.
    status = run_build([
        "xcodebuild", "-scheme", scheme, "-destination", destination,
        "-derivedDataPath", derived_data, "-skipPackageUpdates",
        "-skipPackagePluginValidation", "-skipMacroValidation", "ARCHS=arm64",
        f"IPHONEOS_DEPLOYMENT_TARGET={deployment_target}", "docbuild",
    ], env=env, log_path=log_path)
    if status:
        print(f"Documentation build failed. The complete raw log is available at {log_path}.", file=sys.stderr)
        return 1

    warnings = documentation_warnings(Path.cwd(), log_path)
    if warnings:
        print("Documentation warnings from this repository:")
        print("\n".join(warnings))
        return 1

    archives = []
    missing_targets = []
    for target in targets:
        archive = find_archive(Path(derived_data) / "Build/Products", target)
        if archive is None:
            missing_targets.append(target)
        else:
            archives.append(str(archive))
    if missing_targets:
        print("Missing DocC archives for targets:", file=sys.stderr)
        for target in missing_targets:
            print(f"  {target}", file=sys.stderr)
        return 1

    status = run_command([
        "xcrun", "docc", "merge", *archives, "--output-path", combined_archive,
        "--synthesized-landing-page-name", "Grove", "--synthesized-landing-page-kind", "Package",
        "--synthesized-landing-page-topics-style", "compactGrid",
    ], env=env)
    if status:
        return status
    status = run_command([
        "xcrun", "docc", "process-archive", "transform-for-static-hosting", combined_archive,
        "--output-path", static_archive, "--hosting-base-path", env.get("DOC_HOSTING_BASE_PATH") or "/Grove",
    ], env=env)
    if status:
        return status
    print(f"Built combined DocC archive at {combined_archive}")
    print(f"Built static-hosting DocC archive at {static_archive}")
    return 0


if __name__ == "__main__":
    run_cli(main)

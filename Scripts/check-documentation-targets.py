#!/usr/bin/env python3
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#

"""Checks that .spi.yml documents exactly the package's library products.

A product missing from .spi.yml silently ships without documentation on the Swift Package Index, and
a stale entry fails the build there rather than here. Neither shows up in a normal build, so nothing
else would catch a drift.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def library_products() -> list[str]:
    manifest = (ROOT / "Package.swift").read_text()
    return re.findall(r'\.library\(name:\s*"([^"]+)"', manifest)


def documentation_targets() -> list[str]:
    """Reads the `documentation_targets` lists without a YAML dependency.

    Deliberately strict about the one-item-per-line shape: two entries collapsed onto a single line
    parse as one string in YAML, which is exactly the defect this started out finding.
    """
    targets: list[str] = []
    in_block = False
    for raw in (ROOT / ".spi.yml").read_text().splitlines():
        stripped = raw.strip()
        if stripped.lstrip("- ").startswith("documentation_targets:"):
            in_block = True
            continue
        if not in_block:
            continue
        if not stripped.startswith("- "):
            in_block = False
            continue
        entry = stripped[2:].strip()
        if not re.fullmatch(r"[A-Za-z0-9_]+", entry):
            print(f"error: malformed .spi.yml entry: '{raw.strip()}'", file=sys.stderr)
            sys.exit(1)
        targets.append(entry)
    return targets


def main() -> int:
    products = library_products()
    targets = documentation_targets()

    problems = []
    for duplicate in sorted({t for t in targets if targets.count(t) > 1}):
        problems.append(f"listed twice in .spi.yml: {duplicate}")
    for missing in sorted(set(products) - set(targets)):
        problems.append(f"product not documented in .spi.yml: {missing}")
    for extra in sorted(set(targets) - set(products)):
        problems.append(f".spi.yml names something that is not a library product: {extra}")

    if problems:
        for problem in problems:
            print(f"error: {problem}", file=sys.stderr)
        return 1

    print(f"ok: .spi.yml documents all {len(products)} library products")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT

"""Copy the HealthKit guide's generated Observation examples into the fixture the content corpus reads.

grove-fhir generates one example per HealthKit measurement from its catalogs. The content corpus projects each back
to the HealthKit sample it depicts and pins what Grove exports for that sample, so
Scripts/check-ig-example-containment.py can check that every generated example is contained in Grove's output. The
examples are read from the built HealthKit guide package, as the guide publishes them, without their narrative, and
written one per line, by id. The fixture is JSON Lines, like the corpus, because `.process` flattens the test
resources and every `.json` among them is taken for a golden.

Usage:
  Scripts/generate-grove-fhir-guide-example-fixtures.py --guides <grove-fhir> [--check]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import tarfile
from pathlib import Path

OUTPUT = Path("Tests/GroveHealthKitFHIRTests/Resources/GuideExamples/guide-examples-healthkit.jsonl")


def generate(guides: Path) -> str:
    generated_source = (guides / "healthkit/input/fsh/generated-measurement-profiles.fsh").read_text(encoding="utf-8")
    generated = set(re.findall(r"^Instance: (\S+)$", generated_source, re.MULTILINE))
    package = guides / "healthkit/output/package.tgz"
    if not package.exists():
        raise SystemExit(f"error: {package} is missing; build the healthkit guide first")
    examples = []
    with tarfile.open(package) as archive:
        for member in archive.getmembers():
            if not (member.isfile() and member.name.startswith("package/example/") and member.name.endswith(".json")):
                continue
            handle = archive.extractfile(member)
            if handle is None:
                continue
            resource = json.load(handle)
            if resource.get("resourceType") == "Observation" and resource.get("id") in generated:
                resource.pop("text", None)
                examples.append(resource)
    if {example["id"] for example in examples} != generated:
        missing = sorted(generated - {example["id"] for example in examples})
        raise SystemExit(f"error: the healthkit package lacks generated examples {missing}")
    examples.sort(key=lambda example: example["id"])
    return "".join(json.dumps(example, sort_keys=True, ensure_ascii=False, separators=(",", ":")) + "\n" for example in examples)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--guides", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    parser.add_argument("--check", action="store_true")
    arguments = parser.parse_args()
    generated = generate(arguments.guides)
    if arguments.check:
        actual = arguments.output.read_text(encoding="utf-8") if arguments.output.exists() else ""
        if actual != generated:
            print(f"error: {arguments.output} is not synchronized with {arguments.guides}", file=sys.stderr)
            return 1
        return 0
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(generated, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

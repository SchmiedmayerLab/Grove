#!/usr/bin/env python3
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#

"""Checks that every paired grove-fhir example is contained in the golden Grove recorded for the same input.

Each pair in PAIRS names a guide example and the golden of a case built from the values the example
states. Within the golden's Bundle, the entry of the example's resource type whose profiles include all of the
example's profiles is the counterpart, and every element the example states must appear there with the same value;
Grove may state more.

Identities cannot match byte for byte: the guide's examples are keyed under its own test key and naming systems,
and their digests have no published preimage. So both sides are compared after normalization:
- an identifier that carries a Grove identifier-role type keeps its type, and its system and value become
  placeholders;
- a reference becomes the resource type it resolves to: `Patient/HealthKitPatientExample` in the guide, the entry
  a `urn:uuid` names in Grove's Bundle, and a logical reference by its `type`, as Grove names the Patient;
- an example's `id` and narrative `text` are the guide's own and are not compared.

Arrays are compared as multisets: each example element must be contained in a distinct element of Grove's array,
in any order. Primitives compare as JSON values, so `72` and `72.0` differ, as they do on the wire.

Usage:
  Scripts/check-ig-example-containment.py --guides <grove-fhir> --component healthkit
"""

from __future__ import annotations

import argparse
import json
import sys
import tarfile
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
# Per component: the guides whose examples it checks, and each example paired with the golden of the case built
# from the values that example states. Examples of an output type that no pair names are reported, not failed.
PAIRS = {
    "healthkit": {
        "guides": ["healthkit"],
        "pairs": [
            {
                "guide": "healthkit",
                "resourceType": "Observation",
                "example": "HealthKitHeartRateObservationExample",
                "golden": "guide-example-heart-rate",
            },
        ],
    },
}
GOLDENS = {"healthkit": ROOT / "Tests/GroveHealthKitFHIRTests/Resources/Goldens"}
IDENTIFIER_ROLE_SYSTEM = "https://grovealliance.org/fhir/mobile/CodeSystem/grove-identifier-role"
# The example resource types an adapter emits as its outputs; examples of these that no pair names are reported.
OUTPUT_TYPES = {"Observation", "DocumentReference"}


def load_examples(guides: Path, guide: str) -> dict[str, dict[str, Any]]:
    """Every example resource in `guide`'s built package, keyed by `ResourceType/id`."""
    package = guides / guide / "output" / "package.tgz"
    if not package.exists():
        raise SystemExit(f"error: {package} is missing; build the {guide} guide first")
    examples: dict[str, dict[str, Any]] = {}
    with tarfile.open(package) as archive:
        for member in archive.getmembers():
            if not (member.isfile() and member.name.startswith("package/example/") and member.name.endswith(".json")):
                continue
            handle = archive.extractfile(member)
            if handle is None:
                continue
            resource = json.load(handle)
            if "resourceType" in resource and "id" in resource:
                examples[f"{resource['resourceType']}/{resource['id']}"] = resource
    return examples


def identifier_role(identifier: dict[str, Any]) -> str | None:
    """The Grove identifier role an Identifier's `type` states; `None` for anything else, a `Reference.type` included."""
    kind = identifier.get("type")
    if not isinstance(kind, dict):
        return None
    for coding in kind.get("coding", []):
        if coding.get("system") == IDENTIFIER_ROLE_SYSTEM:
            return coding.get("code")
    return None


def normalize(value: Any, resolve) -> Any:  # type: ignore[no-untyped-def]
    """`value` with identities replaced by placeholders and references by the type they resolve to."""
    if isinstance(value, list):
        return [normalize(element, resolve) for element in value]
    if not isinstance(value, dict):
        return value
    normalized = {key: normalize(element, resolve) for key, element in value.items()}
    if identifier_role(value) is not None:
        normalized["system"] = "<role system>"
        normalized["value"] = "<role value>"
    if isinstance(value.get("reference"), str):
        del normalized["reference"]
        normalized["target"] = resolve(value["reference"])
    elif isinstance(value.get("type"), str) and isinstance(value.get("identifier"), dict):
        # A logical reference names its target by business identifier, as an exchange graph names its Patient.
        del normalized["type"], normalized["identifier"]
        normalized["target"] = value["type"]
    return normalized


def contained(example: Any, grove: Any, path: str, differences: list[str]) -> bool:
    """Whether `example` is contained in `grove`, adding the first difference under each branch to `differences`."""
    if isinstance(example, dict):
        if not isinstance(grove, dict):
            differences.append(f"{path}: expected an object, Grove has {json.dumps(grove)}")
            return False
        result = True
        for key, element in example.items():
            if key not in grove:
                differences.append(f"{path}.{key}: missing from Grove's output, the example states {json.dumps(element)}")
                result = False
            elif not contained(element, grove[key], f"{path}.{key}", differences):
                result = False
        return result
    if isinstance(example, list):
        if not isinstance(grove, list):
            differences.append(f"{path}: expected an array, Grove has {json.dumps(grove)}")
            return False
        unused = list(range(len(grove)))
        result = True
        for index, element in enumerate(example):
            match = next((candidate for candidate in unused if contained(element, grove[candidate], "", [])), None)
            if match is None:
                differences.append(f"{path}[{index}]: no element of Grove's array contains {json.dumps(element)}")
                result = False
            else:
                unused.remove(match)
        return result
    if example != grove:
        differences.append(f"{path}: the example states {json.dumps(example)}, Grove {json.dumps(grove)}")
        return False
    return True


def counterpart(bundle: dict[str, Any], example: dict[str, Any]) -> dict[str, Any]:
    """The one entry resource of the example's type whose profiles include all of the example's."""
    profiles = set(example.get("meta", {}).get("profile", []))
    candidates = [
        entry["resource"]
        for entry in bundle.get("entry", [])
        if entry.get("resource", {}).get("resourceType") == example["resourceType"]
        and profiles <= set(entry["resource"].get("meta", {}).get("profile", []))
    ]
    if len(candidates) != 1:
        raise ValueError(f"{len(candidates)} entries of type {example['resourceType']} state the profiles {sorted(profiles)}")
    return candidates[0]


def check(pair: dict[str, Any], examples: dict[str, dict[str, Any]], goldens: Path) -> list[str]:
    example_key = f"{pair['resourceType']}/{pair['example']}"
    example = examples.get(example_key)
    if example is None:
        return [f"the guide has no example {example_key}"]
    golden = goldens / f"{pair['golden']}.json"
    if not golden.exists():
        return [f"Grove has no golden {golden.name}"]
    bundle = json.loads(golden.read_text(encoding="utf-8"))
    try:
        grove = counterpart(bundle, example)
    except ValueError as error:
        return [str(error)]
    entry_types = {entry.get("fullUrl"): entry.get("resource", {}).get("resourceType") for entry in bundle.get("entry", [])}
    stated = {key: value for key, value in example.items() if key not in {"id", "text"}}
    differences: list[str] = []
    contained(
        normalize(stated, lambda reference: reference.split("/", 1)[0]),
        normalize(grove, lambda reference: entry_types.get(reference, reference)),
        example["resourceType"],
        differences,
    )
    return differences


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--guides", type=Path, required=True)
    parser.add_argument("--component", required=True)
    arguments = parser.parse_args()

    component = PAIRS.get(arguments.component)
    if component is None:
        print(f"==> no IG example pairs for {arguments.component}")
        return 0
    failed = False
    for guide in component["guides"]:
        examples = load_examples(arguments.guides, guide)
        pairs = [pair for pair in component["pairs"] if pair["guide"] == guide]
        for pair in pairs:
            differences = check(pair, examples, GOLDENS[arguments.component])
            status = "contained" if not differences else "NOT contained"
            print(f"    {pair['resourceType']}/{pair['example']} in {pair['golden']}: {status}")
            for difference in differences:
                print(f"      {difference}")
            failed = failed or bool(differences)
        paired = {f"{pair['resourceType']}/{pair['example']}" for pair in pairs}
        unpaired = sorted(key for key, resource in examples.items() if resource["resourceType"] in OUTPUT_TYPES and key not in paired)
        print(f"    {guide}: {len(pairs)} paired, {len(unpaired)} output examples unpaired")
        for key in unpaired:
            print(f"      unpaired {key}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

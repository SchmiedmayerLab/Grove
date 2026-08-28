#!/usr/bin/env python3
"""Build a deterministic Grove FHIR producer manifest for emitted R4 resources."""

# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT

from __future__ import annotations

import argparse
import json
import os
import re
import tempfile
from pathlib import Path
from typing import Any


GROVE_PROFILE_ROOT = "https://grovealliance.org/fhir/"
PACKAGE_ALIAS = re.compile(r"^[a-z][a-z0-9-]*$")
PACKAGE_ID = re.compile(r"^[a-z0-9.-]+$")
VERSION = re.compile(r"^\d+\.\d+\.\d+$")


class ManifestError(ValueError):
    """A deterministic manifest-generation failure."""


def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, item in pairs:
        if key in value:
            raise ManifestError(f"duplicate JSON key: {key}")
        value[key] = item
    return value


def read_resource(path: Path) -> dict[str, Any]:
    if path.is_symlink() or not path.is_file():
        raise ManifestError(f"resource is absent or linked: {path}")
    try:
        resource = json.loads(
            path.read_text(encoding="utf-8"),
            object_pairs_hook=unique_object,
        )
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ManifestError(f"cannot read JSON resource {path}: {error}") from error
    if not isinstance(resource, dict) or not isinstance(resource.get("resourceType"), str):
        raise ManifestError(f"not a FHIR resource: {path}")
    return resource


def read_json_object(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_object)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ManifestError(f"cannot read {label} {path}: {error}") from error
    if not isinstance(value, dict):
        raise ManifestError(f"{label} must be a JSON object: {path}")
    return value


def grove_profiles(resource: dict[str, Any], path: Path) -> list[str]:
    meta = resource.get("meta")
    profiles = meta.get("profile") if isinstance(meta, dict) else None
    if not isinstance(profiles, list) or any(not isinstance(item, str) for item in profiles):
        raise ManifestError(f"resource has no valid meta.profile: {path}")
    direct = [item for item in profiles if item.startswith(GROVE_PROFILE_ROOT)]
    if not direct or len(direct) != len(set(direct)):
        raise ManifestError(f"resource needs unique direct Grove profile claims: {path}")
    return direct


def parse_packages(values: list[str], version: str) -> list[dict[str, str]]:
    packages: list[dict[str, str]] = []
    aliases: set[str] = set()
    identifiers: set[str] = set()
    for value in values:
        alias, separator, identifier = value.partition("=")
        if (
            not separator
            or not PACKAGE_ALIAS.fullmatch(alias)
            or not PACKAGE_ID.fullmatch(identifier)
        ):
            raise ManifestError(f"--package must be alias=packageId: {value!r}")
        if alias in aliases or identifier in identifiers:
            raise ManifestError("package aliases and identifiers must be unique")
        aliases.add(alias)
        identifiers.add(identifier)
        packages.append({"alias": alias, "packageId": identifier, "version": version})
    if not packages:
        raise ManifestError("at least one --package is required")
    return packages


def nested_fhir_resources(
    resource: dict[str, Any],
    pointer: str = "",
) -> list[tuple[str, dict[str, Any]]]:
    resources = [(pointer, resource)]
    if resource.get("resourceType") != "Bundle":
        return resources
    entries = resource.get("entry")
    if not isinstance(entries, list):
        return resources
    for index, entry in enumerate(entries):
        child = entry.get("resource") if isinstance(entry, dict) else None
        if not isinstance(child, dict) or not isinstance(child.get("resourceType"), str):
            continue
        child_pointer = f"{pointer}/entry/{index}/resource"
        resources.extend(nested_fhir_resources(child, child_pointer))
    return resources


def semantic_vector_bindings(
    resources: list[tuple[str, dict[str, Any]]],
    corpus_path: Path | None,
) -> list[dict[str, str]]:
    if corpus_path is None:
        return []
    corpus = read_json_object(corpus_path, "Mobile semantic-vector corpus")
    vectors = corpus.get("vectors")
    if not isinstance(vectors, list):
        raise ManifestError("Mobile semantic-vector corpus has no vectors array")
    vector_profiles: dict[str, str] = {}
    for vector in vectors:
        if not isinstance(vector, dict):
            raise ManifestError("Mobile semantic-vector corpus contains a non-object vector")
        vector_id = vector.get("id")
        profile = vector.get("profile")
        if not isinstance(vector_id, str) or not vector_id or not isinstance(profile, str) or not profile:
            raise ManifestError("Mobile semantic-vector corpus contains an invalid id or profile")
        if vector_id in vector_profiles or profile in vector_profiles.values():
            raise ManifestError("Mobile semantic-vector ids and profiles must be unique")
        vector_profiles[vector_id] = profile

    candidates: dict[str, list[tuple[str, str]]] = {vector_id: [] for vector_id in vector_profiles}
    for relative, root in resources:
        for pointer, resource in nested_fhir_resources(root):
            profiles = resource.get("meta", {}).get("profile", [])
            if not isinstance(profiles, list):
                continue
            for vector_id, profile in vector_profiles.items():
                if profile in profiles:
                    candidates[vector_id].append((relative, pointer))

    bindings: list[dict[str, str]] = []
    for vector_id, occurrences in sorted(candidates.items()):
        if not occurrences:
            continue
        named = [
            occurrence
            for occurrence in occurrences
            if Path(occurrence[0]).stem == vector_id
        ]
        if len(named) != 1:
            raise ManifestError(
                f"shared Mobile profile {vector_profiles[vector_id]} must have exactly one "
                f"binding candidate in {vector_id}.json; found {len(named)}"
            )
        relative, pointer = named[0]
        bindings.append({
            "id": vector_id,
            "path": relative,
            "resourcePointer": pointer,
        })
    return bindings


def create_manifest(
    resources_directory: Path,
    output: Path,
    packages: list[dict[str, str]],
    revision: str | None,
    version: str,
    semantic_vector_corpus: Path | None = None,
) -> dict[str, Any]:
    if resources_directory.is_symlink() or not resources_directory.is_dir():
        raise ManifestError(f"resources directory is absent or linked: {resources_directory}")
    output_resolved = output.resolve()
    entries: list[dict[str, Any]] = []
    resources: list[tuple[str, dict[str, Any]]] = []
    for path in sorted(resources_directory.rglob("*.json")):
        if path.resolve() == output_resolved:
            continue
        relative = path.relative_to(resources_directory).as_posix()
        resource = read_resource(path)
        resources.append((relative, resource))
        entries.append({
            "path": relative,
            "requiredProfiles": grove_profiles(resource, path),
        })
    if not entries:
        raise ManifestError(f"no emitted JSON resources found in {resources_directory}")

    producer = {"name": "Grove Swift", "version": version}
    if revision:
        producer["revision"] = revision
    return {
        "schemaVersion": 1,
        "fhirVersion": "4.0.1",
        "producer": producer,
        "packages": packages,
        "resources": entries,
        "semanticVectors": semantic_vector_bindings(resources, semantic_vector_corpus),
    }


def write_manifest(path: Path, manifest: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink():
        raise ManifestError(f"manifest output must not be a symlink: {path}")
    descriptor, temporary_name = tempfile.mkstemp(
        dir=path.parent,
        prefix=f".{path.name}.",
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(manifest, handle, indent=2, ensure_ascii=False)
            handle.write("\n")
        os.replace(temporary_name, path)
    except BaseException:
        Path(temporary_name).unlink(missing_ok=True)
        raise


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--resources", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--package", action="append", default=[])
    parser.add_argument("--producer-revision")
    parser.add_argument("--semantic-vector-corpus", type=Path)
    # Taken from the checked-out guides rather than hardcoded, so a release cannot leave the
    # manifest naming the previous version.
    parser.add_argument("--package-version", required=True)
    arguments = parser.parse_args(argv)
    try:
        if not VERSION.fullmatch(arguments.package_version):
            raise ManifestError(f"--package-version must be a semantic version: {arguments.package_version!r}")
        packages = parse_packages(arguments.package, arguments.package_version)
        manifest = create_manifest(
            arguments.resources.resolve(),
            arguments.output.resolve(),
            packages,
            arguments.producer_revision,
            arguments.package_version,
            arguments.semantic_vector_corpus.resolve() if arguments.semantic_vector_corpus else None,
        )
        write_manifest(arguments.output.resolve(), manifest)
    except ManifestError as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

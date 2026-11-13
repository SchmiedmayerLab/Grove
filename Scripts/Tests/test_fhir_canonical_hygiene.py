"""The metadata canonical exception does not admit other retired namespaces."""

# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
# SPDX-License-Identifier: MIT

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).parents[1] / "check-fhir-canonical-hygiene.sh"
METADATA = "https://grovealliance.org/fhir/core/StructureDefinition/metadata"


class CanonicalHygieneTests(unittest.TestCase):
    def run_scan(self, contents: str, *, missing_sources: bool = False) -> subprocess.CompletedProcess:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Scripts").mkdir()
            (root / "Tests").mkdir()
            shutil.copy2(SCRIPT, root / "Scripts" / SCRIPT.name)
            if not missing_sources:
                (root / "Sources").mkdir()
                (root / "Sources/example.swift").write_text(contents)
            return subprocess.run(["bash", str(root / "Scripts" / SCRIPT.name)], capture_output=True, text=True)

    def test_exact_metadata_uri_is_allowed_in_source_and_documentation(self):
        self.assertEqual(self.run_scan(f'let url = "{METADATA}"\nThe `{METADATA}` extension.').returncode, 0)

    def test_other_retired_uris_and_metadata_suffixes_remain_rejected(self):
        for uri in [METADATA + "/key", METADATA + "?query", METADATA.replace("https:", "http:"),
                    "https://grovealliance.org/fhir/core/StructureDefinition/other", "https://spezi.health/fhir/Observation"]:
            with self.subTest(uri=uri):
                self.assertNotEqual(self.run_scan(f'"{METADATA}" "{uri}"').returncode, 0)

    def test_failed_source_search_is_not_reported_as_clean(self):
        self.assertNotEqual(self.run_scan("", missing_sources=True).returncode, 0)

# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT

import importlib.util
import json
import pathlib
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).parents[1] / "generate-grove-fhir-semantic-vector-fixtures.py"
SPEC = importlib.util.spec_from_file_location("generate_grove_fhir_semantic_vector_fixtures", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class SemanticVectorFixtureGeneratorTests(unittest.TestCase):
    @staticmethod
    def write_corpus(directory, vectors, fhir_version="4.0.1"):
        path = pathlib.Path(directory) / "corpus.json"
        path.write_text(json.dumps({
            "fhirVersion": fhir_version,
            "vectors": vectors,
        }))
        return path

    @staticmethod
    def quantity_vector(vector_id="heart-rate"):
        return {
            "id": vector_id,
            "profile": f"https://grovealliance.org/fhir/mobile/{vector_id}",
            "code": {"system": "http://loinc.org", "code": "8867-4"},
            "effective": {"type": "dateTime", "value": "2026-08-20T08:30:00.251-07:00"},
            "result": {
                "type": "Quantity",
                "value": 72,
                "system": "http://unitsofmeasure.org",
                "code": "/min",
                "unit": "beats/minute",
            },
        }

    def test_preserves_exact_vector_values_in_typed_swift(self):
        with tempfile.TemporaryDirectory() as directory:
            corpus = self.write_corpus(directory, [self.quantity_vector()])

            generated = MODULE.generate(corpus)

            self.assertIn('effective: .dateTime("2026-08-20T08:30:00.251-07:00")', generated)
            self.assertIn('result: .quantity(value: 72)', generated)
            self.assertNotIn("Codable", generated)

    def test_rejects_duplicate_ids(self):
        with tempfile.TemporaryDirectory() as directory:
            vector = self.quantity_vector()
            corpus = self.write_corpus(directory, [vector, vector])

            with self.assertRaisesRegex(ValueError, "must be unique"):
                MODULE.generate(corpus)

    def test_rejects_non_r4_corpus(self):
        with tempfile.TemporaryDirectory() as directory:
            corpus = self.write_corpus(directory, [self.quantity_vector()], "4.3.0")

            with self.assertRaisesRegex(ValueError, "not an R4"):
                MODULE.generate(corpus)


if __name__ == "__main__":
    unittest.main()

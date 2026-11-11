# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT

import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).parents[2]
SCRIPT = (ROOT / "Scripts/validate-fhir-conformance.sh").read_text()
WORKFLOW = (ROOT / ".github/workflows/tests.yml").read_text()


def pinned(name):
    match = re.search(rf"^{name}=(\S+)$", SCRIPT, re.MULTILINE)
    assert match, f"{name} is not set in validate-fhir-conformance.sh"
    return match.group(1)


class GroveFHIRPinTests(unittest.TestCase):
    def test_the_pinned_version_names_a_full_commit(self):
        self.assertRegex(pinned("PINNED_GROVE_FHIR_VERSION"), r"^\d+\.\d+\.\d+$")
        self.assertRegex(pinned("PINNED_GROVE_FHIR_COMMIT"), r"^[0-9a-f]{40}$")

    def test_the_workflow_defaults_to_the_version_whose_commit_is_pinned(self):
        # A workflow default the script pins no commit for would skip the moved-tag check.
        input_defaults = re.findall(r"^\s+grove_fhir_ref:\n(?:\s+\w+:.*\n)*?\s+default: (\S+)$", WORKFLOW, re.MULTILINE)
        fallbacks = re.findall(r"inputs\.grove_fhir_ref \|\| '([^']+)'", WORKFLOW)

        self.assertEqual(len(input_defaults), 2)
        self.assertEqual(len(fallbacks), 1)
        self.assertEqual(set(input_defaults + fallbacks), {pinned("PINNED_GROVE_FHIR_VERSION")})


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#

"""Unit tests for Scripts/generate-ui-test-projects.py scheme / launch-argument helpers."""

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Scripts" / "generate-ui-test-projects.py"


def load_module():
    if sys.version_info < (3, 11):
        raise unittest.SkipTest("generate-ui-test-projects.py requires Python 3.11+")
    spec = importlib.util.spec_from_file_location("generate_ui_test_projects", SCRIPT)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


gen = load_module()


class ParseLaunchArgumentsTests(unittest.TestCase):
    def test_string_entries_default_to_enabled(self) -> None:
        self.assertEqual(
            gen.parse_launch_arguments("Pkg", {"launch_arguments": ["--flag", "value"]}),
            [("--flag", True), ("value", True)],
        )

    def test_table_entries_preserve_enabled_flag_and_order(self) -> None:
        self.assertEqual(
            gen.parse_launch_arguments(
                "Pkg",
                {
                    "launch_arguments": [
                        "--service-type",
                        "both",
                        {"argument": "--configuration-type", "enabled": False},
                        {"argument": "keysWithOptions", "enabled": False},
                        "--credentials",
                        "createAndSignIn",
                    ]
                },
            ),
            [
                ("--service-type", True),
                ("both", True),
                ("--configuration-type", False),
                ("keysWithOptions", False),
                ("--credentials", True),
                ("createAndSignIn", True),
            ],
        )

    def test_missing_launch_arguments_is_empty(self) -> None:
        self.assertEqual(gen.parse_launch_arguments("Pkg", {}), [])

    def test_rejects_non_array(self) -> None:
        with self.assertRaisesRegex(ValueError, "must be an array"):
            gen.parse_launch_arguments("Pkg", {"launch_arguments": "--flag"})

    def test_rejects_missing_argument_key(self) -> None:
        with self.assertRaisesRegex(ValueError, "missing `argument`"):
            gen.parse_launch_arguments("Pkg", {"launch_arguments": [{"enabled": False}]})

    def test_rejects_non_boolean_enabled(self) -> None:
        with self.assertRaisesRegex(ValueError, "enabled must be a boolean"):
            gen.parse_launch_arguments(
                "Pkg", {"launch_arguments": [{"argument": "--flag", "enabled": "YES"}]}
            )

    def test_rejects_unknown_keys(self) -> None:
        with self.assertRaisesRegex(ValueError, "unsupported keys"):
            gen.parse_launch_arguments(
                "Pkg", {"launch_arguments": [{"argument": "--flag", "extra": 1}]}
            )


class RenderSchemeTests(unittest.TestCase):
    def test_scheme_without_arguments_omits_command_line_section(self) -> None:
        scheme = gen.render_scheme([])
        self.assertIn('BlueprintIdentifier = "000000000000000100000000"', scheme)
        self.assertIn('BlueprintIdentifier = "656490953002CEA900F1D55F"', scheme)
        self.assertIn("TestAppUITests", scheme)
        self.assertNotIn("CommandLineArguments", scheme)

    def test_scheme_includes_enabled_and_disabled_arguments(self) -> None:
        scheme = gen.render_scheme(
            [("--account-storage", True), ("--testTips", False)]
        )
        self.assertIn(
            'argument = "--account-storage"\n            isEnabled = "YES"',
            scheme,
        )
        self.assertIn(
            'argument = "--testTips"\n            isEnabled = "NO"',
            scheme,
        )

    def test_scheme_xml_escapes_argument_text(self) -> None:
        scheme = gen.render_scheme([('a&b<"x">', True)])
        self.assertIn('argument = "a&amp;b&lt;&quot;x&quot;&gt;"', scheme)


if __name__ == "__main__":
    unittest.main()

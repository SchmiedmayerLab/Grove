#!/usr/bin/env python3
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT

import json
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[2]
MODULES = ["GroveQuestionnaire", "GroveQuestionnaireUI"]
LANGUAGES = ["de", "es"]
BUNDLE = re.compile(r"bundle:\s*\.module\b")
LITERAL = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
SPECIFIER = r"%(?:\d+\$)?(?:@|lld|ld|d|lf|f|llu|lu|u)"


def argument_before(source: str, index: int) -> str:
    """The call argument that precedes `bundle:` at `index`: the text back to the call's opening parenthesis."""
    depth = 0
    position = index - 1
    while position >= 0:
        character = source[position]
        if character == ")":
            depth += 1
        elif character == "(":
            if depth == 0:
                break
            depth -= 1
        position -= 1
    return source[position + 1:index]


def key_pattern(literal: str) -> re.Pattern[str]:
    """A catalogue key matching a Swift literal, each interpolation standing for one format specifier."""
    pattern = ""
    index = 0
    while index < len(literal):
        if literal.startswith("\\(", index):
            depth = 0
            end = index + 1
            while end < len(literal):
                depth += {"(": 1, ")": -1}.get(literal[end], 0)
                if depth == 0:
                    break
                end += 1
            pattern += SPECIFIER
            index = end + 1
        elif literal[index] == "\\" and index + 1 < len(literal):
            pattern += re.escape({"n": "\n", "t": "\t"}.get(literal[index + 1], literal[index + 1]))
            index += 2
        else:
            pattern += re.escape(literal[index])
            index += 1
    return re.compile(f"^{pattern}$")


def module_literals(module: str) -> dict[str, Path]:
    literals: dict[str, Path] = {}
    for path in sorted((ROOT / "Sources" / module).rglob("*.swift")):
        source = path.read_text(encoding="utf-8")
        for match in BUNDLE.finditer(source):
            for literal in LITERAL.findall(argument_before(source, match.start())):
                literals.setdefault(literal, path)
    return literals


class QuestionnaireStringCatalogueTests(unittest.TestCase):
    def test_every_module_key_is_in_its_own_catalogue_in_every_language(self) -> None:
        for module in MODULES:
            catalogue = json.loads((ROOT / "Sources" / module / "Resources" / "Localizable.xcstrings").read_text())["strings"]
            used: set[str] = set()
            for literal, path in module_literals(module).items():
                pattern = key_pattern(literal)
                keys = [key for key in catalogue if pattern.match(key)]
                self.assertTrue(keys, f"{module}: {literal!r} from {path.name} is not in its catalogue")
                for key in keys:
                    used.add(key)
                    localizations = catalogue[key].get("localizations", {})
                    for language in LANGUAGES:
                        self.assertIn(language, localizations, f"{module}: {key!r} has no {language} translation")
            unused = [
                key for key, entry in catalogue.items()
                if key not in used and entry.get("shouldTranslate", True)
            ]
            self.assertEqual(unused, [], f"{module}: its catalogue carries keys another module owns or none uses")


if __name__ == "__main__":
    unittest.main()

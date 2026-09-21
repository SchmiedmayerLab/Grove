# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
# SPDX-License-Identifier: MIT

"""Release tests use disposable repositories."""

from contextlib import contextmanager
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("apple15_release", Path(__file__).resolve().parents[1] / "apple15-release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseRulesTests(unittest.TestCase):
    def test_versions(self):
        for source, expected in {
            "0.3.0": "0.3.0-apple15",
            "v0.3.0": "v0.3.0-apple15",
            "0.3.0-beta.6": "0.3.0-apple15-beta.6",
            "1.0.0-rc-1": "1.0.0-apple15-rc-1",
            "0.3.0-apple15": None,
            "0.3.0-apple15-beta.6": None,
            "0.3.0-apple15.1": None,
        }.items():
            with self.subTest(source=source):
                self.assertEqual(release.compatibility_tag(source), expected)

    def test_invalid_versions(self):
        for tag in ("main", "0.3", "01.3.0", "0.3.0-beta.01", "0.3.0+build", "0.3.0\n", "--help"):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                release.compatibility_tag(tag)

    def test_manifest_patch(self):
        original = "// Preserve this comment\n" + release.STANDARD + "\n// And this one\n"
        expected = original.replace(release.STANDARD, release.LOWERED)
        self.assertEqual(release.patched_manifest(original), expected)
        self.assertEqual(release.patched_manifest(expected), expected)
        for source in ("", release.STANDARD + "\n" + release.STANDARD, release.SETTING + "true"):
            with self.subTest(source=source), self.assertRaises(ValueError):
                release.patched_manifest(source)

    def test_default_manifest_validation(self):
        dump = {"platforms": [{"platformName": name, "version": version} for name, version in
                              (("ios", "15.0"), ("macos", "12.0"), ("watchos", "9.0"))],
                "traits": [{"name": "default", "enabledTraits": []}]}
        release.validate_defaults(dump)
        dump["traits"][0]["enabledTraits"] = ["Textual"]
        with self.assertRaises(ValueError):
            release.validate_defaults(dump)
        dump["traits"][0]["enabledTraits"] = []
        dump["platforms"][0]["version"] = "18.0"
        with self.assertRaises(ValueError):
            release.validate_defaults(dump)


@contextmanager
def repository():
    previous = Path.cwd()
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        # Ignore personal signing, hooks, URL rewrites and Git author overrides.
        environment = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        environment.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)
        with patch.dict(os.environ, environment, clear=True):
            try:
                os.chdir(root)
                release.git("init", "--bare", "remote.git")
                release.git("init", "checkout")
                os.chdir(root / "checkout")
                release.git("config", "user.name", "Release Test")
                release.git("config", "user.email", "release@example.invalid")
                release.git("remote", "add", "origin", str(root / "remote.git"))
                Path("Package.swift").write_text(release.STANDARD + "\n")
                release.git("add", "Package.swift")
                release.git("commit", "-m", "Initial Release")
                source = release.git("rev-parse", "HEAD")
                release.git("tag", "-a", "0.3.0", "-m", "Release")
                release.git("push", "origin", "refs/tags/0.3.0")
                yield source
            finally:
                os.chdir(previous)


class PublicationTests(unittest.TestCase):
    def test_prepare_cli_outputs(self):
        with repository() as source:
            output = Path.cwd().parent / "outputs"
            with patch.dict(os.environ, {"GITHUB_OUTPUT": str(output)}):
                subprocess.run([sys.executable, spec.origin, "prepare", "--source-tag", "0.3.0",
                                "--source-sha", source], check=True, capture_output=True, text=True)
            values = dict(line.split("=", 1) for line in output.read_text().splitlines())
            self.assertEqual(values["tag"], "0.3.0-apple15")
            self.assertEqual(release.git("show", f"{values['tree']}:Package.swift"), release.LOWERED)
            self.assertEqual(release.git("rev-parse", "HEAD"), source)

    def test_publication_and_rerun(self):
        with repository() as source:
            index = release.git("write-tree")
            target, tree = release.prepare("0.3.0", source)
            self.assertEqual(release.git("write-tree"), index)
            self.assertEqual(release.git("rev-parse", "HEAD"), source)
            self.assertEqual(release.git("show", f"{source}:Package.swift"), release.STANDARD)
            release.publish("0.3.0", source, tree, tree, target)
            first = release.git("rev-parse", f"refs/tags/{target}")
            commit = release.git("rev-parse", f"{target}^{{commit}}")
            self.assertEqual(release.git("show", "-s", "--format=%P", commit), source)
            self.assertEqual(release.git("diff", "--name-only", source, commit), "Package.swift")
            self.assertNotIn("gpgsig", release.git("cat-file", "commit", commit))
            self.assertEqual(release.git("cat-file", "-t", f"refs/tags/{target}"), "tag")
            self.assertNotIn("SIGNATURE", release.git("cat-file", "tag", f"refs/tags/{target}"))
            self.assertEqual(release.git("ls-remote", "--heads", "origin"), "")
            release.git("restore", "Package.swift")
            rerun_target, rerun_tree = release.prepare("0.3.0", source)
            release.publish("0.3.0", source, rerun_tree, tree, rerun_target)
            self.assertEqual(release.git("rev-parse", f"refs/tags/{target}"), first)

    def test_conflicting_tag_is_preserved(self):
        with repository() as source:
            release.git("tag", "0.3.0-apple15")
            release.git("push", "origin", "refs/tags/0.3.0-apple15")
            target, tree = release.prepare("0.3.0", source)
            with self.assertRaisesRegex(ValueError, "annotated"):
                release.publish("0.3.0", source, tree, tree, target)
            self.assertTrue(release.git("ls-remote", "--refs", "origin", f"refs/tags/{target}").startswith(source))

    def test_wrong_validated_tree(self):
        with repository() as source:
            target, tree = release.prepare("0.3.0", source)
            with self.assertRaisesRegex(ValueError, "validated"):
                release.publish("0.3.0", source, tree, "0" * 40, target)
            self.assertEqual(release.git("ls-remote", "--refs", "origin", f"refs/tags/{target}"), "")

    def test_conflicting_annotated_tag_is_preserved(self):
        with repository() as source:
            release.git("tag", "-a", "0.3.0-apple15", "-m", "Different Release")
            release.git("push", "origin", "refs/tags/0.3.0-apple15")
            before = release.git("ls-remote", "--refs", "origin", "refs/tags/0.3.0-apple15")
            target, tree = release.prepare("0.3.0", source)
            with self.assertRaisesRegex(ValueError, "conflicts"):
                release.publish("0.3.0", source, tree, tree, target)
            self.assertEqual(release.git("ls-remote", "--refs", "origin", f"refs/tags/{target}"), before)

    def test_unsigned_matching_tag_is_accepted(self):
        with repository() as source:
            target, tree = release.prepare("0.3.0", source)
            message = "Enable Apple 15 Compatibility for 0.3.0"
            commit = release.git("commit-tree", tree, "-p", source, input=message + "\n")
            release.git("tag", "-a", target, commit, "-m", message)
            release.git("push", "origin", f"refs/tags/{target}")
            before = release.git("ls-remote", "--refs", "origin", f"refs/tags/{target}")
            release.publish("0.3.0", source, tree, tree, target)
            self.assertEqual(release.git("ls-remote", "--refs", "origin", f"refs/tags/{target}"), before)

    def test_already_lowered_source(self):
        with repository():
            Path("Package.swift").write_text(release.LOWERED + "\n")
            release.git("add", "Package.swift")
            release.git("commit", "-m", "Lower Deployment Defaults")
            source = release.git("rev-parse", "HEAD")
            release.git("tag", "0.3.1")
            release.git("push", "origin", "refs/tags/0.3.1")
            target, tree = release.prepare("0.3.1", source)
            self.assertEqual(tree, release.git("rev-parse", f"{source}^{{tree}}"))
            release.publish("0.3.1", source, tree, tree, target)
            self.assertNotEqual(release.git("rev-parse", f"{target}^{{commit}}"), source)

    def test_wrong_checkout_and_alternate_manifest(self):
        with repository() as source:
            with self.assertRaisesRegex(ValueError, "release event"):
                release.prepare("0.3.0", "0" * 40)
            Path("Package@swift-6.3.swift").write_text(release.STANDARD)
            with self.assertRaisesRegex(ValueError, "Version-specific"):
                release.prepare("0.3.0", source)

    def test_dirty_manifest_is_preserved(self):
        with repository() as source:
            edited = release.STANDARD + "\n// Local change\n"
            Path("Package.swift").write_text(edited)
            with self.assertRaisesRegex(ValueError, "clean"):
                release.prepare("0.3.0", source)
            self.assertEqual(Path("Package.swift").read_text(), edited)

    def test_moved_source_tag(self):
        with repository() as source:
            target, tree = release.prepare("0.3.0", source)
            moved = release.git("commit-tree", tree, "-p", source, input="Other Release\n")
            release.git("push", "origin", f"{moved}:refs/tags/other")
            release.git("--git-dir=../remote.git", "update-ref", "refs/tags/0.3.0", moved)
            with self.assertRaisesRegex(ValueError, "moved"):
                release.publish("0.3.0", source, tree, tree, target)


if __name__ == "__main__":
    unittest.main()

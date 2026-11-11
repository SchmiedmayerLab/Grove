# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT

import hashlib
import importlib.util
import io
import json
import pathlib
import tarfile
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).parents[1] / "fetch-grove-fhir-release-packages.py"
SPEC = importlib.util.spec_from_file_location("fetch_grove_fhir_release_packages", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

RELEASE = "0.8.0"
COMMIT = "cde0cdb92e4f63e96b463085f2a5765a77f5211f"
BASE = f"{MODULE.RELEASES}/{RELEASE}"


def package(name, version, dependencies):
    manifest = json.dumps({"name": name, "version": version, "dependencies": dependencies}).encode()
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w:gz") as archive:
        member = tarfile.TarInfo("package/package.json")
        member.size = len(manifest)
        archive.addfile(member, io.BytesIO(manifest))
    return buffer.getvalue()


class FakeNetwork:
    """A release with mobile and healthkit packages, and a registry holding one terminology package."""

    def __init__(self):
        mobile = package("org.grovealliance.fhir.mobile", RELEASE, {
            "hl7.fhir.r4.core": "4.0.1", "hl7.terminology.r4": "7.3.0",
        })
        healthkit = package("org.grovealliance.fhir.healthkit", RELEASE, {
            "hl7.fhir.r4.core": "4.0.1", "org.grovealliance.fhir.mobile": RELEASE, "hl7.terminology.r4": "7.5.0",
        })
        provenance = json.dumps({"releaseVersion": RELEASE, "sourceRevision": COMMIT}).encode()
        self.assets = {
            f"build-provenance-{RELEASE}.json": provenance,
            f"org.grovealliance.fhir.mobile-{RELEASE}.tgz": mobile,
            f"org.grovealliance.fhir.healthkit-{RELEASE}.tgz": healthkit,
        }
        self.checksums = {name: hashlib.sha256(data).hexdigest() for name, data in self.assets.items()}
        self.terminology = package("hl7.terminology.r4", "7.5.0", {"hl7.fhir.r4.core": "4.0.1"})
        self.terminology_shasum = hashlib.sha1(self.terminology).hexdigest()
        self.requested = []

    def fetch(self, url):
        self.requested.append(url)
        if url == f"{BASE}/SHA256SUMS":
            return "".join(f"{digest}  {name}\n" for name, digest in self.checksums.items()).encode()
        if url.startswith(f"{BASE}/") and url.removeprefix(f"{BASE}/") in self.assets:
            return self.assets[url.removeprefix(f"{BASE}/")]
        if url == f"{MODULE.REGISTRY}/hl7.terminology.r4":
            return json.dumps({"versions": {"7.5.0": {"dist": {"shasum": self.terminology_shasum}}}}).encode()
        if url == f"{MODULE.REGISTRY}/hl7.terminology.r4/7.5.0":
            return self.terminology
        raise MODULE.ReleaseError(f"{url} does not exist")


def cache_with(root, *keys):
    cache = root / "fhir-home" / ".fhir" / "packages"
    for key in keys:
        (cache / key).mkdir(parents=True)
    return cache


def installer(cache):
    def install(path):
        manifest = MODULE.package_manifest(path)
        (cache / f"{manifest['name']}#{manifest['version']}").mkdir(parents=True, exist_ok=True)
    return install


class InstallReleaseTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.directory.name)
        self.guides = self.root / "grove-fhir"
        self.cache = cache_with(self.root, "hl7.fhir.r4.core#4.0.1", "hl7.terminology.r4#7.3.0")
        self.network = FakeNetwork()

    def tearDown(self):
        self.directory.cleanup()

    def install(self):
        return MODULE.install_release(
            self.network.fetch, installer(self.cache), RELEASE, COMMIT, self.guides, ["mobile", "healthkit"], self.cache
        )

    def test_installs_marked_release_packages_and_caches_what_they_depend_on(self):
        installed = self.install()

        for guide in ["mobile", "healthkit"]:
            output = self.guides / guide / "output"
            self.assertEqual(
                (output / "package.tgz").read_bytes(),
                self.network.assets[f"org.grovealliance.fhir.{guide}-{RELEASE}.tgz"],
            )
            self.assertTrue((output / MODULE.RELEASE_MARKER).is_file())
        self.assertEqual(installed, ["hl7.terminology.r4#7.5.0"])
        for key in ["org.grovealliance.fhir.mobile#0.8.0", "org.grovealliance.fhir.healthkit#0.8.0"]:
            self.assertTrue((self.cache / key).is_dir(), key)

    def test_replaces_a_package_already_in_place(self):
        output = self.guides / "mobile" / "output"
        output.mkdir(parents=True)
        (output / "package.tgz").write_bytes(b"stale")

        self.install()

        self.assertEqual(
            (output / "package.tgz").read_bytes(), self.network.assets[f"org.grovealliance.fhir.mobile-{RELEASE}.tgz"]
        )

    def test_a_package_that_fails_its_checksum_installs_nothing(self):
        self.network.assets[f"org.grovealliance.fhir.healthkit-{RELEASE}.tgz"] += b"tampered"

        with self.assertRaisesRegex(MODULE.ReleaseError, "does not match the checksum"):
            self.install()

        self.assertFalse((self.guides / "mobile" / "output" / "package.tgz").exists())

    def test_a_package_the_checksums_omit_is_rejected(self):
        del self.network.checksums[f"org.grovealliance.fhir.healthkit-{RELEASE}.tgz"]

        with self.assertRaisesRegex(MODULE.ReleaseError, "lists no checksum"):
            self.install()

    def test_a_release_built_from_another_commit_is_rejected(self):
        provenance = json.dumps({"releaseVersion": RELEASE, "sourceRevision": "0" * 40}).encode()
        self.network.assets[f"build-provenance-{RELEASE}.json"] = provenance
        self.network.checksums[f"build-provenance-{RELEASE}.json"] = hashlib.sha256(provenance).hexdigest()

        with self.assertRaisesRegex(MODULE.ReleaseError, "not 0.8.0 built from"):
            self.install()

    def test_a_dependency_that_fails_the_registry_checksum_is_rejected(self):
        self.network.terminology_shasum = "0" * 40

        with self.assertRaisesRegex(MODULE.ReleaseError, "checksum https://packages.fhir.org publishes"):
            self.install()

    def test_an_uncached_grove_dependency_is_not_fetched_from_the_registry(self):
        with self.assertRaisesRegex(MODULE.ReleaseError, "org.grovealliance.fhir.mobile#0.8.0 is not cached"):
            MODULE.install_release(
                self.network.fetch, installer(self.cache), RELEASE, COMMIT, self.guides, ["healthkit"], self.cache
            )

    def test_malformed_checksums_are_rejected(self):
        with self.assertRaisesRegex(MODULE.ReleaseError, "malformed SHA256SUMS line"):
            MODULE.parse_checksums("abc package.tgz\n")


class CompareReleaseTests(unittest.TestCase):
    def test_a_package_installed_from_the_release_is_not_taken_for_a_build(self):
        with tempfile.TemporaryDirectory() as directory:
            output = pathlib.Path(directory) / "mobile" / "output"
            output.mkdir(parents=True)
            (output / "package.tgz").write_bytes(b"package")
            (output / MODULE.RELEASE_MARKER).write_text(RELEASE)
            network = FakeNetwork()

            with self.assertRaisesRegex(MODULE.ReleaseError, "came from the 0.8.0 release"):
                MODULE.compare_release(network.fetch, RELEASE, COMMIT, pathlib.Path(directory), ["mobile"])
            self.assertEqual(network.requested, [])

    def test_a_missing_build_is_reported(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(MODULE.ReleaseError, "is missing; build the guides first"):
                MODULE.compare_release(FakeNetwork().fetch, RELEASE, COMMIT, pathlib.Path(directory), ["mobile"])


if __name__ == "__main__":
    unittest.main()

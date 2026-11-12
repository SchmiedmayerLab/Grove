#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#

import datetime
import importlib.util
import pathlib
import tomllib
import unittest


SCRIPT = pathlib.Path(__file__).parents[1] / "refresh-ci-durations.py"
SPEC = importlib.util.spec_from_file_location("refresh_ci_durations", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

DETECT_END = datetime.datetime(2026, 11, 12, 10, 0, tzinfo=datetime.timezone.utc)


def job(name, labels, start, end, conclusion="success"):
    """A job as the Actions API reports it, with start and end in minutes after `detect` finished."""
    def stamp(minutes):
        return (DETECT_END + datetime.timedelta(minutes=minutes)).isoformat()

    return {"name": name, "labels": labels, "started_at": stamp(start), "completed_at": stamp(end), "conclusion": conclusion}


def run(*jobs):
    return [job(MODULE.DETECT_JOB, ["self-hosted", "macOS"], -1, 0), *jobs]


MAC = ["self-hosted", "macOS"]
GITHUB = ["macos-latest"]


class RefreshCIDurationsTests(unittest.TestCase):
    def test_job_key_drops_the_self_hosted_marker(self):
        self.assertEqual(MODULE.job_key("GroveFHIR (iOS, self-hosted)"), "GroveFHIR (iOS)")
        self.assertEqual(MODULE.job_key("GroveFHIR UI (iOS)"), "GroveFHIR UI (iOS)")

    def test_job_pool_ignores_linux(self):
        self.assertEqual(MODULE.job_pool(MAC), MODULE.SELF_HOSTED)
        self.assertEqual(MODULE.job_pool(GITHUB), MODULE.GITHUB_HOSTED)
        self.assertIsNone(MODULE.job_pool(["ubuntu-latest"]))

    def test_a_reused_runner_is_not_a_new_slot(self):
        self.assertEqual(MODULE.slot_arrivals([(0, 5), (5, 9), (2, 4)]), [0, 2])

    def test_a_slot_is_typical_when_most_runs_that_could_fill_it_got_it(self):
        runs = [(2, [1.0, 3.0]), (2, [2.0, 5.0]), (2, [3.0]), (1, [9.0])]

        # Slot 1: all four runs, median 2.5. Slot 2: two of three runs with two jobs got it, median 4.0.
        self.assertEqual(MODULE.typical_slots(runs), [2.5, 4.0])
        self.assertEqual(MODULE.typical_slots(runs[:2]), [])  # too few runs

    def test_summarize_records_successful_jobs_and_slots_per_pool(self):
        runs = [
            run(
                job("App (iOS)", GITHUB, 10, 30),
                job("App UI (iOS)", MAC, 0, 8),
                job("App (Linux)", ["ubuntu-latest"], 0, 5),
                job("Other (iOS, self-hosted)", MAC, 8, 14),
                job("Broken (iOS)", GITHUB, 10, 12, conclusion="failure"),
            )
            for _ in range(3)
        ]

        minutes, slots = MODULE.summarize(runs)

        self.assertEqual(minutes, {
            "App (iOS)": {"github-hosted": 20.0},
            "App UI (iOS)": {"self-hosted": 8.0},
            "Other (iOS)": {"self-hosted": 6.0},
        })
        self.assertEqual(slots, {"self-hosted": [0.0], "github-hosted": [10.0, 10.0]})

    def test_previous_entries_survive_only_while_their_package_exists(self):
        merged = MODULE.merge_previous(
            {"App (iOS)": {"github-hosted": 2.0}},
            {
                "App (iOS)": {"github-hosted": 9.0},
                "App (macOS)": {"github-hosted": 3.0},
                "Gone (iOS)": {"github-hosted": 4.0},
                MODULE.FHIR_CONFORMANCE_JOB: {"github-hosted": 17.0},
            },
            {"App": {}},
        )

        self.assertEqual(merged, {
            "App (iOS)": {"github-hosted": 2.0},
            "App (macOS)": {"github-hosted": 3.0},
            MODULE.FHIR_CONFORMANCE_JOB: {"github-hosted": 17.0},
        })

    def test_rendered_file_parses_back(self):
        minutes = {
            "App (iOS)": {"github-hosted": 20.0, "self-hosted": 10.0},
            "App (macOS)": {"github-hosted": 8.0},
            "App UI (iOS)": {"self-hosted": 12.5},
        }

        parsed = tomllib.loads(MODULE.render(minutes, {"self-hosted": [0.0], "github-hosted": [7.4, 12.2]}, 3, datetime.date(2026, 11, 12)))

        self.assertEqual(parsed["generated"], datetime.date(2026, 11, 12))
        self.assertEqual(parsed["self_hosted_speed"], 0.5)
        self.assertEqual(parsed["default_minutes"], 14.0)
        self.assertEqual(parsed["slots"], {"self-hosted": [0.0], "github-hosted": [7.4, 12.2]})
        self.assertEqual(parsed["minutes"], minutes)


if __name__ == "__main__":
    unittest.main()

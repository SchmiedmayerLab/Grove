#!/usr/bin/env python3
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
"""Regenerates Scripts/ci-job-durations.toml from recent successful Tests runs.

Scripts/affected-test-matrix.py reads that file to send each unpinned unit job of the Tests workflow
to the runner pool expected to finish it first. This docstring is the reference for that routing.

Runner pools
  The Tests workflow runs Apple-platform jobs on two pools:
  - Self-hosted Macs ([self-hosted, macOS]): few runners, plenty of cores, shared with other runs.
  - GitHub-hosted (macos-latest): the organization's macOS slots, shared with every other run and
    repository, often minutes away from the first free one.
  GitHub Actions cannot hand a job to whichever pool frees up first: `runs-on` labels must all match,
  and the free macos-latest runners cannot join a runner group with self-hosted runners. So
  Scripts/affected-test-matrix.py picks each job's pool when it builds the matrix.

The rule
  1. Pinned jobs keep their pool. UI tests run on the Macs unless a package drops "ui" from
     `self-hosted-ci` in packages.toml. `self-hosted-ci = ["unit", "ui"]` pins unit tests to the
     Macs (RuntimeAssertions); `github-hosted-ci = ["unit"]` pins them to GitHub-hosted. FHIR Output
     Conformance always runs GitHub-hosted, and Linux jobs always run on GitHub-hosted ubuntu.
  2. The pinned jobs take each pool's runners first, longest job first.
  3. Every other unit job, longest first, goes to the pool whose earliest-free runner would finish
     it sooner. A tie stays GitHub-hosted, which keeps the Macs free for UI tests from other runs.
  The `Compute test matrix` step logs each decision, for example
  "GroveFHIR (iOS): self-hosted, done ~36 min (vs ~36 on github-hosted)", and unit jobs on the Macs
  carry ", self-hosted" in their name. Without the durations file, every unpinned unit job runs
  GitHub-hosted.

The durations file
  [minutes]          Minutes per job and pool: the median of its 5 most recent runs, keyed by the job
                     name without ", self-hosted".
  [slots]            Minutes after `Detect affected packages` finishes at which each runner typically
                     becomes free for the run.
  self_hosted_speed  Self-hosted minutes per GitHub-hosted minute, for a job recorded on one pool only.
  default_minutes    GitHub-hosted minutes for a job with no recorded duration.
  Never edit it by hand; pin a package in packages.toml instead.

Refreshing
  Run this script and commit the regenerated file. It needs an authenticated `gh` with read access
  to the repository's Actions runs and reads the last 50 Tests runs that completed on their first
  attempt, passed or failed (--runs changes the count). A failed run still ran every job to the end,
  so its timeline is complete; only jobs that succeeded give durations. Cancelled runs and re-run
  attempts are skipped, as their timelines are cut short or split. A job's duration on each runner
  pool is the median of its 5 most recent successful runs there, so a speed-up shows after 3 runs
  while a single slow run barely moves it. A job or pool those runs did not time keeps its older
  value; the runner slots use every sampled run.
  Refresh when:
  - the Tests run's summary shows a "Runner assignment" warning: the durations are older than 60
    days, or a scheduled unit job has no recorded duration (a new package or platform);
  - a change makes a test suite much faster or slower;
  - runners are added or removed, or one pool keeps finishing long before the other.
  Review the diff before committing: [slots] shows how many runners each pool typically gives a run,
  and large jumps in [minutes] should match a known change.

When a test fails only on the Macs
  Pin the package with `github-hosted-ci = ["unit"]` in packages.toml while the test is fixed, then
  remove the pin.
"""

import argparse
import datetime
import itertools
import json
import os
import re
import statistics
import subprocess
import sys
import time

if sys.version_info < (3, 11):
    sys.exit("error: this script requires Python 3.11+ (uses tomllib)")

import tomllib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT_PATH = os.path.join(ROOT, "Scripts", "ci-job-durations.toml")

SELF_HOSTED, GITHUB_HOSTED = "self-hosted", "github-hosted"
DETECT_JOB = "Detect affected packages"
FHIR_CONFORMANCE_JOB = "FHIR Output Conformance"
# A runner slot counts as typical once this many runs had enough jobs to fill it and at least half got it.
MIN_RUNS_PER_SLOT = 3
# A job's duration is the median of its most recent runs, so a sped-up suite is routed by its new time.
SAMPLES_PER_JOB = 5
# Run conclusions whose timelines are complete: a failed run still ran every job to the end.
SAMPLED_CONCLUSIONS = {"success", "failure"}
FALLBACK_DEFAULT_MINUTES = 12.0

HEADER = """\
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
# Generated by Scripts/refresh-ci-durations.py; do not edit by hand.
# The docstring of Scripts/refresh-ci-durations.py explains how the test matrix uses this file and when
# to refresh it.
"""


def job_key(name):
    """The job's name without the runner marker the workflow appends to self-hosted unit jobs."""
    return re.sub(r", self-hosted\)$", ")", name)


def job_pool(labels):
    if "self-hosted" in labels:
        return SELF_HOSTED
    if any(label.startswith("macos") for label in labels):
        return GITHUB_HOSTED
    return None  # Linux jobs always run on GitHub-hosted ubuntu, so they are not planned.


def parse_time(value):
    return datetime.datetime.fromisoformat(value)


def minutes_between(start, end):
    return (parse_time(end) - parse_time(start)).total_seconds() / 60


def slot_arrivals(intervals):
    """Minutes at which one run's concurrency on a pool first reached 1, 2, … runners. A runner freed
    and reused at the same instant is not a new slot."""
    events = sorted([(start, 1) for start, _ in intervals] + [(end, -1) for _, end in intervals])
    arrivals, running = [], 0
    for time, delta in events:
        running += delta
        if running > len(arrivals):
            arrivals.append(time)
    return arrivals


def typical_slots(runs):
    """`runs` holds one (job count, slot arrivals) pair per run. A slot is typical when at least half
    of the runs with enough jobs to fill it got it; its time is the median arrival among those."""
    slots = []
    for level in itertools.count(1):
        eligible = [arrivals for count, arrivals in runs if count >= level]
        reached = [arrivals[level - 1] for arrivals in eligible if len(arrivals) >= level]
        if len(eligible) < MIN_RUNS_PER_SLOT or 2 * len(reached) < len(eligible):
            return sorted(slots)
        slots.append(round(statistics.median(reached), 1))


def summarize(runs_jobs):
    """Durations per job and pool plus typical slot arrivals, from each run's first-attempt jobs, newest
    run first."""
    samples = {}
    pool_runs = {SELF_HOSTED: [], GITHUB_HOSTED: []}
    for jobs in runs_jobs:
        detect = next((job for job in jobs if job["name"] == DETECT_JOB and job.get("completed_at")), None)
        intervals = {SELF_HOSTED: [], GITHUB_HOSTED: []}
        for job in jobs:
            pool = job_pool(job.get("labels", []))
            if pool is None or job["name"] == DETECT_JOB or not job.get("started_at") or not job.get("completed_at"):
                continue
            if job.get("conclusion") == "success":
                samples.setdefault(job_key(job["name"]), {}).setdefault(pool, []).append(
                    minutes_between(job["started_at"], job["completed_at"])
                )
            if detect:
                start = max(0.0, minutes_between(detect["completed_at"], job["started_at"]))
                intervals[pool].append((start, start + minutes_between(job["started_at"], job["completed_at"])))
        for pool, pool_intervals in intervals.items():
            if pool_intervals:
                pool_runs[pool].append((len(pool_intervals), slot_arrivals(pool_intervals)))
    minutes = {
        name: {pool: round(statistics.median(values[:SAMPLES_PER_JOB]), 1) for pool, values in pools.items()}
        for name, pools in samples.items()
    }
    return minutes, {pool: typical_slots(runs) for pool, runs in pool_runs.items()}


def is_unit_job(name):
    return name != FHIR_CONFORMANCE_JOB and " UI (" not in name


def merge_previous(minutes, previous, packages):
    """Keeps each previously recorded job and pool the sampled runs did not time, while its package
    exists, so a job that now always runs on one pool still has a measured time for the other."""
    merged = {name: dict(pools) for name, pools in minutes.items()}
    for name, pools in previous.items():
        if name == FHIR_CONFORMANCE_JOB or name.split(" ", 1)[0] in packages:
            for pool, value in pools.items():
                merged.setdefault(name, {}).setdefault(pool, value)
    return merged


def self_hosted_speed(minutes):
    """Median self-hosted minutes per GitHub-hosted minute over unit jobs recorded on both pools."""
    ratios = [
        pools[SELF_HOSTED] / pools[GITHUB_HOSTED]
        for name, pools in minutes.items()
        if is_unit_job(name) and SELF_HOSTED in pools and pools.get(GITHUB_HOSTED)
    ]
    return round(statistics.median(ratios), 2) if ratios else 1.0


def default_minutes(minutes):
    values = [pools[GITHUB_HOSTED] for name, pools in minutes.items() if is_unit_job(name) and GITHUB_HOSTED in pools]
    return round(statistics.median(values), 1) if values else FALLBACK_DEFAULT_MINUTES


def render(minutes, slots, sampled_runs, generated):
    def number_list(values):
        return "[" + ", ".join(f"{value:.1f}" for value in values) + "]"

    lines = [
        HEADER,
        f"generated = {generated.isoformat()}",
        f"sampled_runs = {sampled_runs}  # first-attempt Tests runs that completed, passed or failed",
        "# Self-hosted minutes per GitHub-hosted minute, over unit jobs recorded on both pools (1.0 without data).",
        f"self_hosted_speed = {self_hosted_speed(minutes)}",
        "# GitHub-hosted minutes assumed for a unit job without a recorded duration.",
        f"default_minutes = {default_minutes(minutes)}",
        "",
        "# Minutes after `Detect affected packages` finishes at which each runner typically becomes free for a run.",
        "[slots]",
        f"{GITHUB_HOSTED} = {number_list(slots[GITHUB_HOSTED])}",
        f"{SELF_HOSTED} = {number_list(slots[SELF_HOSTED])}",
        "",
        "# Median minutes per job and runner pool.",
        "[minutes]",
    ]
    for name in sorted(minutes):
        pools = ", ".join(f"{pool} = {minutes[name][pool]:.1f}" for pool in (GITHUB_HOSTED, SELF_HOSTED) if pool in minutes[name])
        lines.append(f"{json.dumps(name)} = {{ {pools} }}")
    return "\n".join(lines) + "\n"


def gh_api(path, jq=None, paginate=False, attempts=3):
    command = ["gh", "api", *(["--paginate"] if paginate else []), path, *(["--jq", jq] if jq else [])]
    for attempt in range(1, attempts + 1):
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
        if result.returncode == 0:
            return result.stdout
        if attempt < attempts:
            time.sleep(5 * attempt)  # The Actions API fails intermittently while paging long job lists.
    sys.exit(f"error: gh api {path} failed: {result.stderr.strip()}")


def recent_runs(count):
    runs = []
    for page in itertools.count(1):
        batch = json.loads(gh_api(
            f"repos/{{owner}}/{{repo}}/actions/workflows/tests.yml/runs?status=completed&per_page=100&page={page}"
        ))["workflow_runs"]
        # A failed run still ran every job to the end; a cancelled run or a re-run attempt has a cut or
        # split timeline. Durations come only from the jobs that succeeded.
        runs += [run for run in batch if run["run_attempt"] == 1 and run["conclusion"] in SAMPLED_CONCLUSIONS]
        if not batch or len(runs) >= count:
            return sorted(runs, key=lambda run: run["created_at"], reverse=True)[:count]


def run_jobs(run_id):
    output = gh_api(f"repos/{{owner}}/{{repo}}/actions/runs/{run_id}/attempts/1/jobs?per_page=100", ".jobs[]", paginate=True)
    return [json.loads(line) for line in output.splitlines() if line]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--runs", type=int, default=50, help="completed first-attempt Tests runs to sample")
    arguments = parser.parse_args()

    runs = recent_runs(arguments.runs)
    runs_jobs = []
    for index, run in enumerate(runs, 1):
        sys.stderr.write(f"\r[refresh-ci-durations] reading run {index}/{len(runs)}")
        runs_jobs.append(run_jobs(run["id"]))
    sys.stderr.write("\n")

    minutes, slots = summarize(runs_jobs)
    previous = {}
    if os.path.exists(OUTPUT_PATH):
        with open(OUTPUT_PATH, "rb") as file:
            previous = tomllib.load(file).get("minutes", {})
    with open(os.path.join(ROOT, "packages.toml"), "rb") as file:
        packages = tomllib.load(file)
    minutes = merge_previous(minutes, previous, packages)

    with open(OUTPUT_PATH, "w") as file:
        file.write(render(minutes, slots, len(runs), datetime.date.today()))
    sys.stderr.write(
        f"[refresh-ci-durations] {len(minutes)} jobs, slots {slots}; wrote {os.path.relpath(OUTPUT_PATH, ROOT)}\n"
    )


if __name__ == "__main__":
    main()

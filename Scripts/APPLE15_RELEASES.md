<!--
SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
SPDX-License-Identifier: MIT
-->

# Apple 15 Releases

Publishing a GitHub release runs `apple15-release.yml`, including releases marked as prereleases.
It creates a child commit of the released commit, changes only the deployment-default switch in `Package.swift`, and pushes an annotated tag:

| Release | Compatibility tag |
| --- | --- |
| `0.3.0` | `0.3.0-apple15` |
| `0.3.0-beta.6` | `0.3.0-apple15-beta.6` |

A leading `v` is preserved.
Build metadata (`+…`) is rejected; it does not distinguish SwiftPM versions.
The tag keeps the compatibility commit reachable, so no release branch is needed.
The workflow creates no GitHub release, and skips source releases already named `apple15`.
Pushing a Git tag alone does not run it.
GitHub's [`published` event](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#release) covers both stable releases and prereleases published from drafts.

## Setup

The publication job uses `github-actions[bot]` and the built-in `GITHUB_TOKEN` with `contents: write`.
The generated commit and tag are unsigned; no additional secrets or identity variables are needed.
Allow the workflow to create `*-apple15*` tags under the repository's tag rules.
If another workflow publishes the original GitHub release, it must use a GitHub App token or PAT: events created with `GITHUB_TOKEN` [do not start release workflows](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow#triggering-a-workflow-from-a-workflow).

Regular releases should enable the lowered configuration only when `GROVE_LOWERED_DEPLOYMENT_TARGETS` is `"1"`.
The script also accepts the current temporary lowered default without changing its tree; restore the regular default when the study moves from its branch dependency to a compatibility tag.
Other manifest formats and version-specific manifests fail for manual review.

## Validation and Recovery

Before publication, all five deployment-floor builds must pass: iOS device/simulator, macOS, and watchOS device/simulator.
The workflow separately checks that the manifest defaults to iOS 15, macOS 12 and watchOS 9 with no enabled default traits.
The existing floor script's product exclusions still apply; these builds do not establish runtime compatibility on older devices.
Run the regular release validation and downstream study tests before publishing the original release.

Rerun a failed workflow after correcting credentials or infrastructure.
A matching annotated compatibility tag is accepted without another push; a conflicting tag is never replaced.
A moved source tag or a changed validated tree also stops publication.
Fix source or manifest errors in a new release rather than moving a published tag.
Older releases without this workflow are not backfilled automatically.

Consumers must select the compatibility version exactly:

```swift
.package(url: "https://github.com/SchmiedmayerLab/Grove.git", exact: "0.3.0-apple15", traits: [])
```

The suffix is a SemVer prerelease, not an OS selector.
A range beginning at `0.3.0-apple15` can also select the regular `0.3.0` release.

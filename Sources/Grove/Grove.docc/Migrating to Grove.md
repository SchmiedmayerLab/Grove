# Migrating from Spezi to Grove

<!--

This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

Update an app built on Spezi to Grove.

## Overview

Every module and product is renamed, and a handful of identifiers that name stored data have changed with it.

Your users' data moves itself.
The migrations run once, on first launch after the update, and are covered by tests that assert nothing is lost.
What you have to change is your own source: the module names you import, and four values you may have written down somewhere.

> Tip: Update your imports first and build.
> The compiler will find almost everything.
> Then work through <doc:Migrating-to-Grove#Changes-you-have-to-make> for the handful of values it cannot see.

## Changes you have to make

### Rename your imports

`Spezi*` became `Grove*`, and `XCTSpezi*` became `XCTGrove*`.

```diff
-import Spezi
-import SpeziAccount
-import SpeziScheduler
+import Grove
+import GroveAccount
+import GroveScheduler
```

Update the product names in your `Package.swift` to match.
There are no source-compatibility typealiases — 0.2.0 is a deliberate clean break.
If you are configuring Grove for the first time, start from <doc:Initial-Setup> instead.

### Update `BGTaskSchedulerPermittedIdentifiers`

The scheduler's background-refresh identifier now derives from your app's bundle identifier rather than a fixed vendor string.
It lives in *your* `Info.plist`, which is why this one cannot be automatic.

```diff
 <key>BGTaskSchedulerPermittedIdentifiers</key>
 <array>
-    <string>edu.stanford.spezi.scheduler.notifications-scheduling</string>
+    <string>$(PRODUCT_BUNDLE_IDENTIFIER).scheduler.refresh</string>
 </array>
```

> Important: Registering a background task an app has not permitted fails silently — refresh simply stops, with nothing in the console.
> Grove therefore reads the permitted list, keeps working with the old identifier for this release, and logs the exact replacement.
> Do not rely on that indefinitely; it goes away with the transitional identifiers.

### Replace hardcoded notification identifiers

Scheduler notification identifiers, categories and threads now begin with your bundle identifier:

```diff
-edu.stanford.spezi.scheduler.notification.task.<task-id>
+<your.bundle.id>.scheduler.notification.task.<task-id>
```

If you inspect these in a `UNUserNotificationCenterDelegate`, do not compare prefixes yourself — a hand-written check silently stops matching notifications that were scheduled *before* the update and are still pending.
Use `SchedulerNotifications.isSchedulerNotification(_:)`, which accepts both:

```swift
func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
) async {
    let identifier = response.notification.request.identifier
    guard SchedulerNotifications.isSchedulerNotification(identifier) else {
        return
    }
    // …
}
```

Reading a notification's scheduled date has the same shape — `Notifications.scheduledDate(fromUserInfo:)` accepts the current key and the pre-Grove one, preferring the current.

### Replace hardcoded `Task.Category` raw values

The study task categories lost their vendor prefix:

```diff
-edu.stanford.spezi.SpeziStudy.task.informational
+informational
```

> Note: Code that uses `.informational`, `.timedWalkingTest`, `.timedRunningTest` or `.customActiveTask(_:)` needs no change — the constants are the same.
> Only a hardcoded raw string breaks.
> Rows already in the scheduler store are rewritten for you.

## What happens automatically

Everything below runs on first launch, once, and is idempotent.
There is no API to call and no flag to set.

| Your users' data | Moves from | Moves to |
| --- | --- | --- |
| Scheduler store | `Documents/edu.stanford.spezi.scheduler.storage.sqlite` | `Application Support/<bundle-id>/Scheduler/store.sqlite` |
| Study store and bundles | `Documents/edu.stanford.SpeziStudy/StudyBundles` | `Application Support/<bundle-id>/Study/` |
| Paired devices, health measurements | `Documents/edu.stanford.spezidevices.*.sqlite` | `Application Support/<bundle-id>/Devices/` |
| `LocalStorage` values | `Application Support/edu.stanford.spezi/LocalStorage` | `Application Support/<bundle-id>/LocalStorage` |
| AccessGuard passcodes | keychain service `edu.stanford.spezi.accessGuard` | keychain service `AccessGuard` |
| HealthKit and SensorKit anchors | keys prefixed `edu.stanford.Spezi.SpeziHealthKit.*` | `HealthKit.queryAnchors`, `SensorKit.queryAnchors`, … |
| Study task rows | `Task.id` and `Task.Category` carrying `edu.stanford.spezi.SpeziStudy.*` | the same rows, prefix stripped |
| Study bundles on disk | `<uuid>.spezistudybundle` | `<uuid>.studybundle` |

Those old reverse-DNS strings are exactly what a pre-0.2.0 app wrote on the device.
Grove reads each one, moves what it finds, and never writes it again.
A fresh install finds nothing at any of these locations, so every migration is a no-op and the strings never appear.

> Note: Stores move atomically.
> Files are staged beside the destination and committed with a single directory rename, and the database is always the last thing to land — so a process killed part-way leaves the original untouched and retries on the next launch.
> Nothing is deleted until its replacement is in place, and a relocation that cannot complete reports failure rather than leaving an empty store behind.

### Losing a passcode locks a user out

AccessGuard is the one migration where failure has no recovery path, so it is deliberately cautious: it enumerates the whole legacy keychain service rather than the guards your app declares — biometric fallback passcodes are not in that list — and it writes every credential to the new service before deleting any.
If the keychain is locked it defers instead of reporting "no passcode set".

## FHIR identifiers

Canonical URLs moved to the `grovealliance.org` authority:

```diff
-https://bdh.stanford.edu/fhir/defs/sourceDevice
+https://grovealliance.org/fhir/core/StructureDefinition/sourceDevice
```

Reads accept **every spelling ever published**; writes emit only the new one.
`extensions(for:)` walks the spellings canonical-first and never merges them, so a resource carrying both is read as the newer writer intended.

If an analysis pipeline is keyed on the old URLs, opt into dual-write while you migrate it:

```swift
FHIRWritePolicy.default = .canonicalAndSuperseded
```

Every resource then carries a compatibility copy under each superseded spelling.
Copies are deep, so nested extensions such as `sourceRevision/source/bundleIdentifier` are reproduced in full, and the pass is idempotent.

> Note: Dual-written extensions are duplicates, not new information.
> Anything reading through Grove already resolves both spellings and should leave this at its default of `.canonicalOnly`.

## Identifiers that keep their old spelling

Two different things are easy to confuse here, and only one of them lasts.

**Transitional — read once, then gone.** The reverse-DNS keys in the table above.
They exist only so the migrations can find your users' data.
They are never written, a fresh install never encounters them, and they are deleted outright once these migrations have shipped.

**Published — read forever.** Superseded FHIR canonical URLs under `bdh.stanford.edu`, `spezi.stanford.edu` and `spezi.health`.
These are not on your device: they are in resources this project does not own — a questionnaire authored elsewhere in 2024, an `Observation` already sitting in a research database.
Those will never be rewritten, so Grove has to keep understanding them.
A brand-new install still meets them the first time it parses an externally-authored questionnaire.

> Note: Both live in the `GroveLegacyIdentifiers` target, which is not a package product — you cannot import it, and you should not need to.
> It exists so the rest of the codebase carries no pre-Grove name, and so the transitional half can be deleted in one commit.

## Removed

- **`SpeziLLMFog`** — the fog-node inference stack, along with its Bonjour discovery.
- **Per-target `README.md`** — module documentation now lives in each target's DocC catalog.

The build scripts' `SPEZI_*` environment variables are now `GROVE_*`; this only matters if you drive them directly.

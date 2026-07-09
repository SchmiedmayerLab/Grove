<!--
This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT
-->

# Warning Follow-ups

This file tracks warnings that were intentionally not fixed during the monorepo warning cleanup because they require API migrations, dependency updates, behavior changes, or toolchain-specific decisions.

| Area | Current warning | Recommended follow-up |
| --- | --- | --- |
| `HealthKitOnFHIR` vaginal bleeding rename | The deprecated `HKCategoryValueMenstrualFlow` type was removed from local source references during warning cleanup, but the library still intentionally emits the existing menstrual-flow FHIR coding for compatibility. | Add an availability-aware migration only if the FHIR coding strategy should change. Preserve support for older deployment targets and keep emitted FHIR codings stable unless a breaking-change plan explicitly says otherwise. |
| `HealthKitOnFHIR` workout construction tests | `HKWorkout(activityType:start:end:)` is deprecated in favor of `HKWorkoutBuilder`. | Migrate the workout tests once there is a testable builder path that does not require an authenticated `HKHealthStore`, or isolate the compatibility test behind a deliberate warning policy. |
| `SpeziAccountPhoneNumbers` dependency migration | `PhoneNumberUtility()` warns because the `marmelroy/PhoneNumberKit` package has moved to `PhoneNumberKit/PhoneNumberKit`. | Migrate the package dependency URL and verify API/source compatibility for phone parsing, formatting, and country metadata. |
| `SpeziFirebaseAccount` email updates | `FirebaseAuth.User.updateEmail(to:)` is deprecated in favor of `sendEmailVerification(beforeUpdatingEmail:)`. | Decide the account UX for verification-before-update, then migrate the update flow and tests. This changes user-visible behavior and should not be a mechanical warning cleanup. |
| `SpeziAccessGuard` lifecycle handling | `LifecycleHandler` is deprecated in favor of `@Application` or SwiftUI notification handling. | Migrate the module lifecycle integration deliberately and verify app-delegate behavior. This is a framework integration change, not a warning-only edit. |
| `SpeziDevices` observation storage | `nonisolated(unsafe)` on `PairedDevices._pairedDevices` has no effect under the current Swift 6.4/Xcode 27 beta compiler. | Revisit once the observation macro/toolchain behavior is clearer. A direct change to `nonisolated` currently fails macro expansion for the mutable stored property. |
| `SpeziViews.AsyncButton` concurrency | Swift 6.4 warns about isolated task-group closures capturing generic `Label.Type`. | Refactor the debounce/action race without changing button state timing. A clean fix likely needs restructuring away from the current task-group child that mutates main-actor view state. |
| `SpeziViews.CanvasView` PencilKit tool selection | `PKToolPicker.selectedTool` is deprecated in iOS 18 in favor of `selectedToolItem`. | Migrate the drawing tool binding from `any PKTool` to an item-aware model, or add a compatibility adapter once PencilKit exposes a safe way to map arbitrary `PKTool` values back to picker items. |
| `SpeziSensorKit` anchored fetcher | The `Sample: SensorKitSampleProtocol` conformance may be isolated when passed through the async fetcher. | Audit the actor isolation of SensorKit sample protocols and fetch delegates before changing annotations. |
| Spezi dependency-resolution tests | Several tests still use deprecated `withDependencyResolution(simulateLifecycle:_:)` helpers. | Migrate those tests to the newer `SpeziTesting` APIs in a dedicated test-support cleanup. |
| SwiftPM DocC resource warnings | `swift build` reports each `.docc` catalog as an unhandled file. | Keep the catalogs available for Xcode DocC builds for now. Investigate a SwiftPM-compatible suppression only if it does not break `xcodebuild docbuild` archive generation. |
| Local DocC profiling/toolchain output | `xcodebuild docbuild` succeeded, but the local Xcode 27 beta run emitted a corrupted JSON internal error and `default.profraw` write failures. | Recheck on CI or outside the sandbox with profiling disabled. Treat this as a local Xcode/tooling artifact unless it reproduces as a documentation failure. |
| Third-party manifest warnings | `TPPDF` and `SQLite.swift` manifests warn about deprecated platform/package requirement APIs. | Track upstream releases or override dependencies only if needed. These are outside the local source tree. |

# ``GroveHealthKitFHIR``

<!--
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
-->

@Metadata {
    @TitleHeading("Producer Package")
}

Export already-fetched HealthKit samples as auditable FHIR R4 exchange graphs.

## Overview

A HealthKit sample, such as the heart rate a watch measured, becomes one immutable, self-describing FHIR Bundle called the exchange graph.
FHIR is the health-data interchange standard; a Bundle is its container for a set of resources, and an Observation is the resource that holds one measurement.
Any receiver can deduplicate, correct and retract an exchange graph without knowing that it came from HealthKit.
Grove adds what plain FHIR lacks: stable identities that never leak the HealthKit UUID, provenance saying which application assembled the graph on which device, and optional study context.
The receiver gets a graph it can store, compare byte for byte on a retry, and take back by identity.

``HealthKitFHIRExporter`` consumes `HKSample` values you already fetched; it does not request authorization, query samples, manage anchors, store FHIR or upload anything.
If you already know the pieces, jump to <doc:#Beyond-the-minimum>.

## What you need and why

Five inputs configure an exporter; everything else has a default.

### The subject pseudonym

The subject is the participant the sample belongs to.
FHIR wants every clinical resource to point at a Patient; Grove points at the deployment's pseudonym instead, so the graph carries no name and no account.
It is one `BusinessIdentifier`: an absolute URI your deployment owns as the system, and the participant's stable pseudonym as the value.
Persist the pair with the enrollment; `Subject.logical` is the default form.

### The identity scope

Every sample and every output gets an opaque identity: an HMAC of the sample's native facts under your deployment's secret key.
The same sample exported twice yields the same identifier, so a receiver deduplicates, and nobody can recover the HealthKit UUID from it.
`DeploymentIdentifierSystems.derived(root:keyID:epoch:)` derives the twelve identifier systems the protocol recommends from your deployment root, a key id and an epoch, and `OpaqueIdentityScope` holds them with the key.
Persist the key id and the epoch beside the key; rotating either changes every system with it.

### The ledger

Every export is an exchange event, and every event is immutable.
The exporter's `ExchangeProducer` numbers each event in its ledger and freezes what the event states (the instant, the application, the host and the studies) until you release the receipt the export returns.
A redelivery before the release reproduces the same bytes under the same event identifier; a new revision of the sample takes a new event.
The ledger lives in your app's `ExchangeProducer.Storage`; `GroveFHIRContract` documents the contract it must meet.

### The repository scope

Two HealthKit stores must never collide: the store on one phone and the store on another can hold the same UUID.
The repository scope is one `BusinessIdentifier` that names this installation's HealthKit store, and it enters every opaque identity.
Use a system your deployment owns and a token you persist once per installation, such as a UUID minted on first launch.

### The application

The conversion Provenance names the application that assembled the graph, so a receiver knows who to trust and which version wrote it.
`ApplicationDevice(bundle:)` reads it from your bundle.

> Note: The host defaults to `HostDevice.current()` and the export instant to now.
> The producer freezes the instant, the application, the host and the studies with each event, so a redelivery before the receipt is released rebuilds the same bytes, even after an update.

## Assemble it

Once per installation, derive the systems, create the scope and name the application.
`hmacKey` is the `SymmetricKey` you load from the keychain, `keyID` and `epoch` the values persisted beside it.

```swift
let systems = try DeploymentIdentifierSystems.derived(root: "https://study.example.org/fhir", keyID: keyID, epoch: epoch)
let identityScope = try OpaqueIdentityScope(systems: systems, keyID: keyID, epoch: epoch, key: hmacKey)
let application = try ApplicationDevice(bundle: .main)
```

Build the producer and the exporter once per configuration, and rebuild both when the participant, the studies or the application change.
`ledgerStorage` is your app's ledger storage and `installationToken` the token that names this HealthKit store.

```swift
let producer = try ExchangeProducer(
    identityScope: identityScope,
    subject: .logical(participant),
    application: application,
    storage: ledgerStorage
)
let exporter = try HealthKitFHIRExporter(
    producer: producer,
    repositoryScope: try BusinessIdentifier(system: "https://study.example.org/fhir/NamingSystem/healthkit-store", value: installationToken)
)
```

The exporter states the application that wrote a sample only for sources you classify: HealthKit does not say whether a source is an application or a device, so by default no writer is stated.
Pass the bundle identifiers you know to be applications as `options.writer = .applications(...)`, or classify each source with `.classify`; see ``HealthKitFHIRExporter/WriterPolicy``.

Export a batch and store each graph's bytes verbatim.
Release the receipt only once the stored graphs and the HealthKit anchor are durably committed; until then an exact redelivery reproduces the same events, byte for byte.

```swift
let receipt = try exporter.export(samples) { export in
    if let graph = export.graph {
        try stage(graph.json)
    }
}
try commitAnchor()
receipt.release()
```

What to persist, and why:

| Value | Why |
| --- | --- |
| The ledger storage | It numbers every event and freezes what each one states until the receipt is released. Never restore it from a backup or copy it to another installation. |
| The key id and epoch, beside the key | They select the systems every identity is minted under. |
| The installation token | It is the repository scope of every identity this store mints. |

> Important: Never change the key or the epoch without deriving new systems.
> It breaks the promise that one identifier means one thing.

## Beyond the minimum

<doc:ConfiguringTheExporter> explains every input in depth and <doc:TheExchangeGraph> what the graph contains.

A known enrollment travels as a `StudyEnrollment` in the producer's `studies`, and every graph carries its ResearchStudy, PlanDefinition and ResearchSubject entries; `Subject.bundled` adds the Patient itself.

```swift
let producer = try ExchangeProducer(
    identityScope: identityScope,
    subject: .logical(participant),
    application: application,
    studies: [enrollment],
    storage: ledgerStorage
)
```

Every disclosure in ``HealthKitFHIRExporter/Options`` defaults to omission: the UDI stays out unless `udi` is `.authorized`, a workout route needs `route` `.authorized`, and the clear HealthKit UUID needs `nativeIdentifier` to authorize a system you own.

```swift
var options = HealthKitFHIRExporter.Options()
options.udi = .authorized
let disclosing = try HealthKitFHIRExporter(producer: producer, repositoryScope: repositoryScope, options: options)
```

``HealthKitFHIRExporter/RolePolicy`` states how your application relates to the measurement: `.gatewayForOwnWrites` marks the samples it wrote in the build it runs as mediated by it, and `.gatewayApplication` names a distinct application that mediated every measurement; it travels as a second application snapshot when an Observation output names it through `observation-gatewayDevice`.
Heartbeat series, workout route, clinical record and CDA graphs state no gateway application.

Some samples keep what their graph needs outside the sample, and HealthKit makes you query it separately.
Pass them as a ``HealthKitFHIRExporter/Record`` with that companion data: an `HKElectrocardiogram` with its voltages and correlated symptoms, each symptom an event of its own; an `HKHeartbeatSeriesSample` with its ``HealthKitHeartbeat``s; an `HKWorkoutRoute` with its locations.
A clinical record and a CDA document carry their bytes in the sample, so they export as ``HealthKitFHIRExporter/Record/sample(_:)``.

```swift
let receipt = try exporter.export(records: [.electrocardiogram(ecg, voltages: voltages, symptoms: symptoms)]) { export in
    if let graph = export.graph {
        try stage(graph.json)
    }
}
```

A sample that cannot be exported is refused in place with a ``HealthKitConversionError``, and the call continues.
``HealthKitFHIRExporter/Export/warnings`` lists what a graph does not carry although its record did, each a registered `ProducerDiagnostic`; log them with that graph's event.
`mobile-omission.recording-device` means the sample's device had no per-unit token, so no recording Device was emitted; supply your own ``RecordingDeviceResolver`` through ``HealthKitFHIRExporter/RecordingDevicePolicy/custom(_:)`` when you have one.
`mobile-omission.source-offset` is located at the effective element, such as `Observation.effectiveDateTime`, that is in UTC because the sample named no time zone.
`mobile-omission.unmodeled-metadata` means the sample carried metadata outside the typed allowlist, which was left out.
An omission an option chose, such as `recordingDevice` `.omit`, is never a warning.

A retry is exact when `ExchangeGraph.isSemanticallyEqual(to:)` says so.
A deleted sample is taken back with ``HealthKitFHIRExporter/retract(_:at:receive:)``.
It needs only the deleted object's UUID and the sample type it was reported for; the source record and every output it retracts are recomputed, so nothing from the sample's export has to be kept.
HealthKit reports a deletion without its time, so a ``HealthKitFHIRExporter/Deletion`` bounds it by the `deletedAfter` the deletion handler received and the time it was reported.

```swift
guard let type = HealthKitSourceType(sampleType.hkSampleType) else {
    return // Never exported, so there is nothing to retract.
}
let deletion = HealthKitFHIRExporter.Deletion(uuid: deletedObject.uuid, sourceType: type, deletedAfter: deletedAfter, detectedAt: reportedAt)
let receipt = try exporter.retract([deletion]) { retraction in
    if let graph = retraction.graph {
        try stage(graph.json)
    }
}
```

Each deletion is reported once, as a ``HealthKitFHIRExporter/Retraction``.
A target carries the HealthKit UUID as its native record identifier only under the same `nativeIdentifier` option that disclosed it on the export.
A deletion that names no output the exporter can have emitted, such as a workout route while `route` is `.omit`, reports ``HealthKitFHIRExporter/Retraction/Outcome/nothingToRetract`` and takes no event.

`Observation.healthKitSample(syncIdentifier:)` and `ExchangeGraph.healthKitSamples()` read a graph back into HealthKit samples, syncing under the minted source-output identity.

The conformance lane in `Scripts/validate-fhir-conformance.sh` proves this adapter's output against the grove-fhir corpora and the official validator.

## Glossary

| IG term | Swift |
| --- | --- |
| Exchange event | `ExchangeEventIdentifier`, numbered by the `ExchangeProducer` |
| Exchange graph | `ExchangeGraph`, delivered as ``HealthKitFHIRExporter/Export/graph`` |
| Business identifier | `BusinessIdentifier` |
| Identifier role | `GroveIdentifierRole` on a `RoledIdentifier` |
| Opaque identity | minted by `OpaqueIdentityScope` under `DeploymentIdentifierSystems` |
| Entry-node key | `EntryNodeKey` |
| Subject | `Subject` |
| Study enrollment | `StudyEnrollment` |
| Application, host and recording device | `ApplicationDevice`, `HostDevice`, `RecordingDevice` named by a ``HealthKitFHIRExporter/RecordingDevicePolicy`` |
| Writer | ``HealthKitWriter``, answered by a ``HealthKitFHIRExporter/WriterPolicy`` |
| Retraction event and target | `RetractionEvent`, `RetractionTarget` |
| Governed source identifier | `GovernedSourceIdentifierDisclosurePolicy` |
| Producer diagnostic | `ProducerDiagnostic` from ``HealthKitConversionError/diagnostic`` or ``HealthKitFHIRExporter/Export/warnings`` |

## Topics

### Essentials

- <doc:ConfiguringTheExporter>
- <doc:TheExchangeGraph>

### Exporting

- ``HealthKitFHIRExporter``
- ``HealthKitSourceType``
- ``HealthKitHeartbeat``

### Policies

- ``HealthKitWriter``
- ``RecordingDeviceResolver``

### Refusals

- ``HealthKitConversionError``
- ``HealthKitValueFailure``
- ``HealthKitECGEvidenceFailure``
- ``HealthKitClinicalRecordFailure``
- ``HealthKitDependencyFailure``
- ``HealthKitMetadataField``

### Coverage

- ``HealthKitCatalog``
- ``HealthKitCatalogEntry``
- ``HealthKitMeasurementContract``
- ``HealthKitOutput``
- ``HealthKitUnitBinding``
- ``FieldDisposition``

### Reading observations back

- ``HealthKitSampleProjectionError``
- ``HealthKitSampleProjectionFailure``

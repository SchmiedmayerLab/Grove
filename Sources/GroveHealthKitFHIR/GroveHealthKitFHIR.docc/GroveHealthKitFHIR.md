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

Convert already-fetched HealthKit samples into auditable FHIR R4 exchange graphs.

## Overview

A HealthKit sample, such as the heart rate a watch measured, becomes one immutable, self-describing FHIR Bundle called the exchange graph.
FHIR is the health-data interchange standard; a Bundle is its container for a set of resources, and an Observation is the resource that holds one measurement.
Any receiver can deduplicate, correct and retract an exchange graph without knowing that it came from HealthKit.
Grove adds what plain FHIR lacks: stable identities that never leak the HealthKit UUID, provenance saying which application assembled the graph on which device, and optional study context.
The receiver gets a graph it can store, compare byte for byte on a retry, and take back by identity.

``HealthKitConverter`` consumes an `HKSample` you already fetched; it does not request authorization, query samples, manage anchors, store FHIR or upload anything.
If you already know the pieces, jump to <doc:#Beyond-the-minimum>.

## What you need and why

Five inputs make a context; everything else has a default.

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

### The event identifier

Every export is an exchange event, and every event is immutable.
An `ExchangeEventIdentifier` is your producer instance UUID plus a monotonic `EventSequence`.
A retry resends the same bytes under the same identifier; a new revision of the sample gets a new sequence.
Persist the producer instance once and the next sequence before you emit.

### The repository scope

Two HealthKit stores must never collide: the store on one phone and the store on another can hold the same UUID.
The repository scope is one `BusinessIdentifier` that names this installation's HealthKit store, and it enters every opaque identity.
Use a system your deployment owns and a token you persist once per installation, such as a UUID minted on first launch.

### The application

The conversion Provenance names the application that assembled the graph, so a receiver knows who to trust and which version wrote it.
`ApplicationDevice(bundle:)` reads it from your bundle.

> Note: The host defaults to `HostDevice.current()` and the conversion instant to now.
> Pass both explicitly when you replay a persisted event, so the retry rebuilds the same bytes.

## Assemble it

Once per installation, derive the systems, create the scope and name the application.
`hmacKey` is the `SymmetricKey` you load from the keychain, `keyID` and `epoch` the values persisted beside it.

```swift
let systems = try DeploymentIdentifierSystems.derived(root: "https://study.example.org/fhir", keyID: keyID, epoch: epoch)
let identityScope = try OpaqueIdentityScope(systems: systems, keyID: keyID, epoch: epoch, key: hmacKey)
let application = try ApplicationDevice(bundle: .main)
```

Per export, reserve the next sequence and create the context, using every default.
`producerInstance` is the UUID persisted with the installation, `nextSequence` the counter you durably advanced first, and `installationToken` the token that names this HealthKit store.

```swift
let event = try ExchangeEventIdentifier(system: systems.event, producerInstance: producerInstance, sequence: nextSequence)
let context = HealthKitConversionContext(event: ExchangeEventContext(
    subject: .logical(participant),
    event: event,
    identityScope: identityScope,
    repositoryScope: try BusinessIdentifier(system: "https://study.example.org/fhir/NamingSystem/healthkit-store", value: installationToken),
    application: application
))
```

Convert one sample and hand the Bundle to your uploader.

```swift
let conversion = try HealthKitConverter().convert(sample, context: context)
try upload(JSONEncoder().encode(conversion.primary.bundle))
```

What to persist, and why:

| Value | Why |
| --- | --- |
| The event sequence, before emitting | A reused sequence under different content is a conflict the receiver cannot resolve. |
| The key id and epoch, beside the key | They select the systems every identity is minted under. |
| The producer instance id | It is half of every event identifier. |
| The installation token | It is the repository scope of every identity this store mints. |

> Important: Never reuse an event sequence for different content, and never change the key or the epoch without deriving new systems.
> Both break the promise that one identifier means one thing.

## Beyond the minimum

<doc:ConfiguringAConversion> explains every input in depth and <doc:TheConversionGraph> what the graph contains.

A known enrollment travels as a `StudyEnrollment` in `studies`, and the graph carries its ResearchStudy, PlanDefinition and ResearchSubject entries; `Subject.bundled` adds the Patient itself.

```swift
let event = ExchangeEventContext(
    subject: .logical(participant),
    event: eventIdentifier,
    identityScope: identityScope,
    repositoryScope: repositoryScope,
    application: application,
    studies: [enrollment]
)
```

Every disclosure in ``HealthKitConversionOptions`` defaults to omission: the UDI stays out unless ``HealthKitUDIDisclosurePolicy/authorizedUDI`` says otherwise, a workout route needs `RouteDisclosurePolicy.authorized`, and the clear HealthKit UUID needs `GovernedSourceIdentifierDisclosurePolicy.authorized` under a system you own.

```swift
let options = HealthKitConversionOptions(udiDisclosure: .authorizedUDI)
let disclosing = HealthKitConversionContext(event: event, options: options)
```

A `RepositoryID` per `ExchangeGraphNode` in `repositoryIDs` gives a graph node the logical id your repository assigned.

`ConverterRole.gatewayApplication` names a distinct application that mediated the measurement; it travels as a second application snapshot.

``HealthKitConversion/warnings`` lists what a graph does not carry although its record did; log them with that graph's event.
``HealthKitConversionSet/warnings`` flattens them over every graph of the set, so an ECG's list includes its symptoms'.
``HealthKitConversionWarning/recordingDeviceOmitted(deviceName:)`` means the sample's device had no per-unit token, so no recording Device was emitted; supply your own ``RecordingDeviceResolver`` when you have one.
``HealthKitConversionWarning/sourceOffsetUnavailable(field:)`` names the effective element, such as `Observation.effectiveDateTime`, that is in UTC because the sample named no time zone, and its diagnostic is located there.
``HealthKitConversionWarning/unmodeledMetadataWithheld(keys:)`` names, in sorted order, the metadata keys outside the typed allowlist that were left out.

A batch supplies a context per sample, because every sample is its own event, and keeps a ``HealthKitRecordFailure`` for every sample it did not emit.

```swift
let batch = HealthKitConverter().convert(samples) { sample in
    try persistedContext(for: sample)
}
```

A retry is exact when `ExchangeGraph.isSemanticallyEqual(to:)` says so.
A deleted sample is taken back with ``HealthKitConverter/retraction(for:context:occurred:)``.
It needs only the deleted object's UUID and the sample type it was reported for; the source record and every output it retracts are recomputed, so nothing from the sample's conversion has to be kept.
`retractionContext` is a ``HealthKitConversionContext`` for the retraction's own new event, under the same identity scope, repository scope and native-identifier disclosure as the conversion.
HealthKit reports a deletion without its time, so `occurred` bounds it by the `deletedAfter` the deletion handler received and the time it was reported.

```swift
guard let type = HealthKitSourceType(sampleType.hkSampleType) else {
    return // Never converted, so there is nothing to retract.
}
let retraction = try HealthKitConverter().retraction(
    for: HealthKitSourceRecord(uuid: deletedObject.uuid, type: type),
    context: retractionContext,
    occurred: .period(start: deletedAfter, end: reportedAt)
)
```

A target carries the HealthKit UUID as its native record identifier only when the context's native-identifier disclosure authorizes it, exactly as on the conversion that emitted it.
``HealthKitConverter/retractionTargets(for:context:)`` names the targets alone.

`Observation.healthKitSample(syncIdentifier:)` and `ExchangeGraph.healthKitSamples()` read a graph back into HealthKit samples, syncing under the minted source-output identity.

The conformance lane in `Scripts/validate-fhir-conformance.sh` proves this adapter's output against the grove-fhir corpora and the official validator.

> Tip: Keep the conversion context beside the outbox entry it produced; a retry then rebuilds identical bytes without touching the clock.

## Glossary

| IG term | Swift |
| --- | --- |
| Exchange event | `ExchangeEventIdentifier` and `ExchangeEventContext` |
| Exchange graph | `ExchangeGraph`, held by ``HealthKitConversion/graph`` |
| Business identifier | `BusinessIdentifier` |
| Identifier role | `GroveIdentifierRole` on a `RoledIdentifier` |
| Opaque identity | minted by `OpaqueIdentityScope` under `DeploymentIdentifierSystems` |
| Entry-node key | `EntryNodeKey` |
| Subject | `Subject` |
| Study enrollment | `StudyEnrollment` |
| Application, host and recording device | `ApplicationDevice`, `HostDevice`, `RecordingDevice` named by a ``RecordingDeviceResolver`` |
| Writer | ``HealthKitWriter`` |
| Retraction event and target | `RetractionEvent`, `RetractionTarget` |
| Governed source identifier | `GovernedSourceIdentifierDisclosurePolicy` |
| Producer diagnostic | `ProducerDiagnostic` from ``HealthKitConversionError/diagnostic`` or ``HealthKitConversionWarning/diagnostic`` |

## Topics

### Essentials

- <doc:ConfiguringAConversion>
- <doc:TheConversionGraph>

### Conversion

- ``HealthKitConverter``
- ``HealthKitConversionContext``
- ``HealthKitConversionOptions``
- ``RecordingDeviceResolver``
- ``HealthKitLocalIdentifierResolver``
- ``HealthKitSourceType``
- ``HealthKitSourceRecord``
- ``HealthKitConversion``
- ``HealthKitConversionSet``
- ``HealthKitConversionWarning``
- ``HealthKitRecordFailure``

### Recording and clinical inputs

- ``HealthKitECGRecord``
- ``HealthKitHeartbeatSeriesRecord``
- ``HealthKitHeartbeat``
- ``HealthKitWorkoutRouteRecord``
- ``HealthKitClinicalRecord``
- ``HealthKitClinicalAttachment``

### Disclosure policies

- ``HealthKitWriter``
- ``HealthKitUDIDisclosurePolicy``

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

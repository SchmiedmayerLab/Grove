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

Export already-fetched HealthKit samples as auditable FHIR R4 exchange records.

## Overview

A HealthKit sample, such as the heart rate a watch measured, becomes one immutable, self-describing record: its outputs, the one Provenance that says how they were made, and the Devices and study context they reference.
FHIR is the health-data interchange standard; a Bundle is its container for a set of resources, and an Observation is the resource that holds one measurement.
A record travels in an exchange graph, a FHIR Bundle of any number of records that share their Devices and study context as single entries.
Any receiver can deduplicate, correct and retract a record without knowing that it came from HealthKit.
Grove adds what plain FHIR lacks: stable identities that never leak the HealthKit UUID, provenance saying which application assembled the record on which device, and optional study context.
The receiver gets a record it can store, recognize on a retry by its record version, and take back by identity.

``HealthKitFHIRExporter`` consumes `HKSample` values you already fetched; it does not request authorization, query samples, manage anchors, store FHIR or upload anything.
If you already know the pieces, jump to <doc:#Beyond-the-minimum>.

## What you need and why

Four inputs configure an exporter; everything else has a default.

### The subject pseudonym

The subject is the participant the sample belongs to.
FHIR wants every clinical resource to point at a Patient; Grove points at the deployment's pseudonym instead, so the record carries no name and no account.
It is one `BusinessIdentifier`: an absolute URI your deployment owns as the system, and the participant's stable pseudonym as the value.
Persist the pair with the enrollment; `Subject.logical` is the default form.

### The identity scope

Every sample and every output gets an opaque identity: an HMAC of the sample's native facts under your deployment's secret key.
The same sample exported twice yields the same identifier, so a receiver deduplicates, and nobody can recover the HealthKit UUID from it.
`OpaqueIdentityScope(root:keyID:epoch:key:)` derives the thirteen identifier systems the protocol recommends from your deployment root, a key id and an epoch, and holds them with the key.
Persist the key id and the epoch beside the key; rotating either changes every opaque system with it.

### The repository scope

Two HealthKit stores must never collide: the store on one phone and the store on another can hold the same UUID.
The repository scope is one `BusinessIdentifier` that names this installation's HealthKit store, and it enters every source-record and output identity.
Use a system your deployment owns and a token you persist once per installation, such as a UUID minted on first launch.

### The application

The conversion Provenance names the application that assembled the record, so a receiver knows who to trust and which version wrote it.
`ApplicationDevice(bundle:)` reads it from your bundle.

> Note: The host defaults to `HostDevice.current()` and the export instant to now.
> A record's version is a keyed digest of its outputs and its Provenance, the export instant included: the same content repeats the version, which is an exact retry, and anything else is a new version of the same source record.
> Only a holder of the identity key can recompute it; a receiver compares it.

## Assemble it

Once per installation, create the scope and name the application.
`hmacKey` is the `SymmetricKey` you load from the keychain, `keyID` and `epoch` the values persisted beside it.

```swift
let identityScope = try OpaqueIdentityScope(root: "https://study.example.org/fhir", keyID: keyID, epoch: epoch, key: hmacKey)
let application = try ApplicationDevice(bundle: .main)
```

Build the producer and the exporter once per configuration, and rebuild both when the participant, the studies or the application change.
`installationToken` is the token that names this HealthKit store.

```swift
let producer = try ExchangeProducer(
    identityScope: identityScope,
    subject: .logical(participant),
    application: application
)
let exporter = try HealthKitFHIRExporter(
    producer: producer,
    repositoryScope: try BusinessIdentifier(system: "https://study.example.org/fhir/NamingSystem/healthkit-store", value: installationToken)
)
```

The exporter states the application that wrote a sample only for sources you classify: HealthKit does not say whether a source is an application or a device, so by default no writer is stated.
Pass the bundle identifiers you know to be applications as `options.writer = .applications(...)`, or classify each source with `.classify`; see ``HealthKitFHIRExporter/WriterPolicy``.

Export each batch an anchored query delivered and stage each record's bytes verbatim.
Every input is a ``HealthKitFHIRExporter/Record``: most samples export as ``HealthKitFHIRExporter/Record/sample(_:)``, and an ECG, a heartbeat series and a workout route need the companion data HealthKit keeps outside the sample (see <doc:#Beyond-the-minimum>).
Commit the HealthKit anchor once the staged records are durably stored.

```swift
try await exporter.export(records: samples.map { .sample($0) }) { export in
    if let record = export.record {
        try stage(record.json)
    }
}
try commitAnchor()
```

`receive` is called once per record or refusal, as soon as it is ready: once for most inputs, once plus once per registered symptom for an ECG, and never for a workout route while `route` is `.omit`, which emits nothing and is not a refusal.
Exporting a sample again at another instant is a new version of the same source record, so feed the exporter from anchored queries, which deliver each sample once, not from overlapping date windows.
`export(_:at:receive:)` wraps every sample as ``HealthKitFHIRExporter/Record/sample(_:)``; it suits batches without those three kinds, as an ECG, a heartbeat series or a workout route passed that way is refused for want of its companion data, the ECG with ``HealthKitConversionError/ecgEvidence(_:)`` and the other two with ``HealthKitConversionError/platformExclusiveSourceType(_:)``.
A blood-pressure reading exports only as its `HKCorrelation`: a systolic or diastolic sample on its own is refused with ``HealthKitConversionError/componentRequiresCorrelation(_:)``.

To upload, add the staged records to an `ExchangeBundlePacker` and send the `json` of the `ExchangeGraph` that `bundle(packedAt:)` returns.
Records of one Bundle state each shared node once, and packing or repacking them changes no record.

What to persist, and why:

| Value | Why |
| --- | --- |
| The key id and epoch, beside the key | They select the systems every identity is minted under. |
| The installation token | It is the repository scope of every identity this store mints. |

> Important: Never change the key or the epoch without deriving new systems.
> It breaks the promise that one identifier means one thing.

## Beyond the minimum

<doc:ConfiguringTheExporter> explains every input in depth and <doc:TheExchangeGraph> what a record and its Bundle contain.

A known enrollment travels as a `StudyEnrollment` in the producer's `studies`, and every record carries its ResearchStudy, PlanDefinition and ResearchSubject entries; `Subject.bundled` adds the Patient itself.

```swift
let producer = try ExchangeProducer(
    identityScope: identityScope,
    subject: .logical(participant),
    application: application,
    studies: [enrollment]
)
```

Every device and source fact HealthKit supplies travels, a serial number and a name a person gave the device included: a consumer filters what it does not need, and a deployment that shares data applies its own policy to the sensitive ones.
The disclosures in ``HealthKitFHIRExporter/Options`` default to omission: a workout route needs `route` `.authorized`, and the clear HealthKit UUID needs `nativeIdentifier` to authorize a system you own.

```swift
var options = HealthKitFHIRExporter.Options()
options.route = .authorized
let disclosing = try HealthKitFHIRExporter(producer: producer, repositoryScope: repositoryScope, options: options)
```

``HealthKitFHIRExporter/RolePolicy`` states how your application relates to the measurement: `.gatewayForOwnWrites` marks the samples it wrote in the build it runs as mediated by it, and `.gatewayApplication` names a distinct application that mediated every measurement; it travels as a second application snapshot when an Observation output names it through `observation-gatewayDevice`.
Heartbeat series, workout route, clinical record and CDA records state no gateway application.

Some samples keep what their record needs outside the sample, and HealthKit makes you query it separately.
Pass them as a ``HealthKitFHIRExporter/Record`` with that companion data: an `HKElectrocardiogram` with its voltages and correlated symptoms, each symptom a record of its own; an `HKHeartbeatSeriesSample` with its ``HealthKitFHIRExporter/Record/Heartbeat``s; an `HKWorkoutRoute` with its locations.
A symptom exported with its ECG has the identities it has when a category query exports it as a plain sample, so exporting it both ways at one instant repeats one record, and at two instants states two versions of one source record. Export each symptom one way, such as with its ECG, to avoid that.
A clinical record and a CDA document carry their bytes in the sample, so they export as ``HealthKitFHIRExporter/Record/sample(_:)``.

```swift
try await exporter.export(records: [.electrocardiogram(ecg, voltages: voltages, symptoms: symptoms)]) { export in
    if let record = export.record {
        try stage(record.json)
    }
}
```

A sample that cannot be exported is refused in place with a ``HealthKitConversionError``, and the call continues.
``HealthKitFHIRExporter/Export/warnings`` lists what a record does not carry although its sample did, each a registered `ProducerDiagnostic`; log them with that record.
`mobile-omission.source-offset` is located at the effective element, such as `Observation.effectiveDateTime`, that is in UTC because the sample named no time zone; a blood-pressure correlation that names none takes the zone its systolic and diastolic members agree on.
`mobile-omission.unmodeled-metadata` is located at `HKSample.metadata`: the sample, or a correlation member, workout event or workout activity it contains, carried metadata its record does not represent.
A record represents a key only through the element the guide maps it to, on an output that has that element: a time zone on a heartbeat series is withheld, because a document has no element for it, and so is a key one source type reads stated on another.
A device key is represented only when the recording Device of an Observation states that very value: an `HKDevice` property wins over its key, so a key it replaced is withheld, and so is every device key of a sample without an `HKDevice`.
`HKMetadataKeyWasUserEntered` stated `false` is represented by omission and never reported, and a blood-pressure member's zone or manual entry that the record takes is represented as the record's own.
An omission an option chose, such as a route under `.omit`, is never a warning.
Each export keeps its own warnings; to log a batch without a line per sample, add every export to one ``HealthKitFHIRExporter/WarningReport`` and log its description once.
It names each kind with its HealthKit cause and how many samples of each type raised it.

A retry is exact when it repeats `ExchangeRecord.version`.
A deleted sample is taken back with ``HealthKitFHIRExporter/retract(_:at:receive:)``.
It needs only the deleted object's UUID and the sample type it was reported for; its one target is the source record, recomputed from them, so nothing from the sample's export has to be kept.
HealthKit reports a deletion without its time, so a ``HealthKitFHIRExporter/Deletion`` bounds it: after ``HealthKitFHIRExporter/Deletion/deletedAfter``, the instant the query that produced the previous anchor was issued, which GroveHealthKit's `HealthKitConstraint.handleDeletedObjects(_:ofType:deletedAfter:)` passes, and no later than ``HealthKitFHIRExporter/Deletion/detectedAt``, when the deletion was reported.
With a raw `HKAnchoredObjectQuery`, persist the instant you issue each query beside the anchor it returns, and pass it as `deletedAfter` for the deletions the next query reports.
`sampleType` is the `HKSampleType` the anchored query that reported the deletion ran for.

```swift
guard let type = HealthKitSourceType(sampleType) else {
    return // Never exported, so there is nothing to retract.
}
let deletion = HealthKitFHIRExporter.Deletion(uuid: deletedObject.uuid, sourceType: type, deletedAfter: deletedAfter, detectedAt: reportedAt)
try await exporter.retract([deletion]) { retraction in
    if let record = retraction.record {
        try stage(record.json)
    }
}
```

Each deletion is reported once, as a ``HealthKitFHIRExporter/Retraction``.
A retraction addresses the whole source record: a receiver suppresses every output of every version of it, one only an earlier conversion emitted included.
Its key is the source record alone, so `deletedAfter` and `detectedAt` key nothing, and the first retraction accepted wins.
The target carries the HealthKit UUID as its native record identifier only under the same `nativeIdentifier` option that disclosed it on the export.
A deletion that names no output the exporter can have emitted, such as a workout route while `route` is `.omit`, reports ``HealthKitFHIRExporter/Retraction/Outcome/nothingToRetract``.

`Observation.healthKitSample(syncIdentifier:)`, `ExchangeRecord.healthKitSamples()` and `ExchangeGraph.healthKitSamples()` read a record or a packed Bundle back into HealthKit samples, syncing under the minted source-output identity.
The projection reads an `effectiveDateTime` as an instant and an `effectivePeriod` as the sample's start and end, where the measurement's profile admits that datatype and HealthKit allows the duration, and refuses with a typed error otherwise.

The conformance lane in `Scripts/validate-fhir-conformance.sh` proves this adapter's output against the grove-fhir corpora and the official validator.

## Glossary

| IG term | Swift |
| --- | --- |
| Record | `ExchangeRecord`, delivered as ``HealthKitFHIRExporter/Export/record`` |
| Record version | `RecordVersion`, the conversion Provenance's entry key, repeated in its `grove-record-version` extension |
| Exchange graph | `ExchangeGraph`, the Bundle `ExchangeBundlePacker` packs records into |
| Business identifier | `BusinessIdentifier` |
| Identifier role | `GroveIdentifierRole` on a `RoledIdentifier` |
| Opaque identity | minted by `OpaqueIdentityScope` under `DeploymentIdentifierSystems` |
| Entry key | the `Canonicals.entryKey` extension on each Bundle entry |
| Subject | `Subject` |
| Study enrollment | `StudyEnrollment` |
| Application, host and recording device | `ApplicationDevice`, `HostDevice`, and `RecordingDevice`, whose unit a ``HealthKitFHIRExporter/UnitTokenPolicy`` picks |
| Writer | ``HealthKitFHIRExporter/WriterPolicy/Classification``, answered by a ``HealthKitFHIRExporter/WriterPolicy`` |
| Retraction and target | ``HealthKitFHIRExporter/Retraction``, whose record's Provenance target carries the `Canonicals.retractionTargetRole` extension |
| Governed source identifier | `GovernedSourceIdentifierDisclosurePolicy` |
| Producer diagnostic | `ProducerDiagnostic` from ``HealthKitConversionError/diagnostic`` or ``HealthKitFHIRExporter/Export/warnings`` |

## Topics

### Essentials

- <doc:ConfiguringTheExporter>
- <doc:TheExchangeGraph>

### Exporting

- ``HealthKitFHIRExporter``
- ``HealthKitSourceType``

### Refusals

- ``HealthKitConversionError``

### Catalog

- ``HealthKitCatalog``

### Reading observations back

- ``HealthKitSampleProjectionError``
- ``HealthKitSampleProjectionFailure``

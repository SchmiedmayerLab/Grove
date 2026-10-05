# ``GroveSensorKitFHIR``

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

Convert already-fetched SensorKit records into deterministic, conformant FHIR R4 exchange graphs.

## Overview

A SensorKit record, such as one batch of rotation-rate samples from a watch, becomes one immutable, self-describing FHIR Bundle called the exchange graph.
FHIR is the health-data interchange standard; a Bundle is its container for a set of resources, and an Observation or a DocumentReference is the resource that holds one measurement or one recording.
Any receiver can deduplicate and correct an exchange graph without knowing that it came from SensorKit.
Grove adds what plain FHIR lacks: stable identities that never leak the native record id, provenance saying which application assembled the graph on which device, and optional study context.
The receiver gets a graph it can store and compare byte for byte on a retry; SensorKit records cannot be taken back yet (<doc:#Publish-an-anchored-batch> says why).

``SensorKitFHIRExporter`` consumes typed records you already fetched; it never queries SensorKit.
If you already know the pieces, jump to <doc:#Beyond-the-minimum>.

## What you need and why

Five inputs configure an exporter, SensorKit adds two facts of its own, and everything else has a default.

### The subject pseudonym

The subject is the participant the record belongs to.
FHIR wants every clinical resource to point at a Patient; Grove points at the deployment's pseudonym instead, so the graph carries no name and no account.
It is one `BusinessIdentifier`: an absolute URI your deployment owns as the system, and the participant's stable pseudonym as the value.
Persist the pair with the enrollment; `Subject.logical` is the default form.

### The identity scope

Every record and every output gets an opaque identity: an HMAC of the record's native facts under your deployment's secret key.
The same record exported twice yields the same identifier, so a receiver deduplicates, and nobody can recover the native id from it.
`OpaqueIdentityScope(root:keyID:epoch:key:)` derives the twelve identifier systems the protocol recommends from your deployment root, a key id and an epoch, and holds them with the key.
Persist the key id and the epoch beside the key; rotating either changes every opaque system with it, while the event and entry-node systems stay with the root.

### The ledger

Every export is an exchange event, and every event is immutable.
The `ExchangeProducer` numbers the events in a ledger your app stores, and freezes the application, host and studies each one states, so a retry before the receipt is released resends the same bytes under the same identifier.
`ExchangeProducer.Storage` is the durable, transactional storage the ledger needs; `GroveFHIRContract` documents the contract it must meet.

### The repository scope

Two SensorKit stores must never collide: the store on one phone and the store on another can hold the same record id.
The repository scope is one `BusinessIdentifier` that names this installation's SensorKit store, and it enters every source-record and output identity.
Use a system your deployment owns and a token you persist once per installation, such as a UUID minted on first launch.

### The application

The conversion Provenance names the application that assembled the graph, so a receiver knows who to trust and which version wrote it.
`ApplicationDevice(bundle:)` reads it from your bundle.

### The SensorKit facts

The exporter needs the system under which the exact `SRVisit.locationId` is carried; the guide requires one your deployment owns, scoped to the deployment or the source store, on every visit that names a location.
Each export call adds two facts about the batch:

- `sourceTimeZone` is the zone every effective bound states its offset in. SensorKit reports absolute instants and no zone, so use the device's zone when you first publish the batch, `TimeZone.current`, and persist it with the batch: a redelivery states the same bounds only under the same zone.
- `recordingDevice` names the physical unit that recorded the batch. SensorKit's `BatchInfo.device` describes a model, never one unit, and the guide never lets descriptive facts stand in for a unit, so pass a `RecordingDevice` only when your deployment governs a stable token for that unit, such as one it assigned to the participant's paired watch, and persist it with the batch. Without one, the graphs name no recording Device.

> Note: The host defaults to `HostDevice.current()` and the event instant to now.
> The producer freezes the instant, the application, the host and the studies with each event, so a redelivery before the receipt is released rebuilds the same bytes, even after an update.

## Assemble it

Once per installation, create the scope and name the application.
`hmacKey` is the `SymmetricKey` you load from the keychain, `keyID` and `epoch` the values persisted beside it.

```swift
let identityScope = try OpaqueIdentityScope(root: "https://study.example.org/fhir", keyID: keyID, epoch: epoch, key: hmacKey)
let application = try ApplicationDevice(bundle: .main)
```

Build the producer and the exporter once per configuration, and rebuild both when the participant, the studies or the application change.
`ledgerStorage` is your app's ledger, and `installationToken` the token that names this SensorKit store.

```swift
let producer = try ExchangeProducer(
    identityScope: identityScope,
    subject: .logical(participant),
    application: application,
    storage: ledgerStorage
)
let exporter = try SensorKitFHIRExporter(
    producer: producer,
    repositoryScope: try BusinessIdentifier(system: "https://study.example.org/fhir/NamingSystem/sensorkit-store", value: installationToken),
    visitLocationIdentifierSystem: "https://study.example.org/fhir/NamingSystem/sensorkit-visit-location"
)
```

Export each anchored batch, store each graph's bytes verbatim, and acknowledge the batch before you release the receipt; "Publish an anchored batch" below walks through one batch.

```swift
let receipt = try exporter.export(records, sourceTimeZone: batchTimeZone) { export in
    if let graph = export.graph {
        try stage(graph.json)
    }
}
try await batch.acknowledge()
receipt.release()
```

What to persist, and why:

| Value | Why |
| --- | --- |
| The ledger storage | It numbers every event and freezes what each one states until the receipt is released. Never restore it from a backup or copy it to another installation. |
| The key id and epoch, beside the key | They select the systems every identity is minted under. |
| The installation token | It is the repository scope of every identity this store mints. |
| The batch's time zone, and its recording-device token when you pass one | A redelivery states the same graphs only with the same facts. |
| Each record's source record id and the digest of its `retryEvidence` | After the release, the id may name only the bytes first seen at its coordinate. |
| Each sidecar's bytes, at the path its graph states | The graph names the bytes by path, size and SHA-1, and never carries them. |

> Important: Never change the key or the epoch without deriving new systems.
> It breaks the promise that one identifier means one thing.

## Beyond the minimum

A known enrollment travels as a `StudyEnrollment` in the producer's `studies`, and the graph carries its ResearchStudy, PlanDefinition and ResearchSubject entries; `Subject.bundled` adds the Patient itself.

Every disclosure defaults to omission: the clear SensorKit record id needs ``SensorKitFHIRExporter/Options/nativeIdentifier`` set to `GovernedSourceIdentifierDisclosurePolicy.authorized` under a system you own, and a recording Device appears only when you name the physical unit.

```swift
var options = SensorKitFHIRExporter.Options()
options.nativeIdentifier = .authorized(system: "https://study.example.org/fhir/NamingSystem/sensorkit-record")
let disclosing = try SensorKitFHIRExporter(
    producer: producer,
    repositoryScope: repositoryScope,
    visitLocationIdentifierSystem: visitLocationSystem,
    options: options
)
let receipt = try disclosing.export(records, sourceTimeZone: batchTimeZone, recordingDevice: try RecordingDevice(stableUnitToken: watchToken)) { export in
    try handle(export)
}
```

A record that cannot be converted is reported as ``SensorKitFHIRExporter/Export/Outcome/refused(_:)`` and the export continues; its ``SensorKitConversionError/diagnostic`` is one registered producer rule.

A retry is exact when `ExchangeGraph.isSemanticallyEqual(to:)` says so.

The conformance lane in `Scripts/validate-fhir-conformance.sh` proves this adapter's output against the grove-fhir corpora and the official validator.

### Publish an anchored batch

`SensorKit.fetchAnchored(_:batchSize:)` in `GroveSensorKit` delivers each batch with its `info`, whose acquisition coordinate survives a restart, and advances its query anchor only when you call `acknowledge()`.
One batch becomes records in one of two ways:

- **One record per batch.** A tabular stream (accelerometer, ambient light, ambient pressure, heart rate, pedometer) becomes one ``SensorKitTabularRecording`` from all its samples, and a photoplethysmogram batch one ``SensorKitPreparedPPGRecording`` from `SensorKitPPGRecording(samples:).prepared()`. A rotation-rate batch becomes one ``SensorKitRotationRateRecord`` from its samples, which exposes no `retryEvidence`, so digest the samples you pass. The record's ordinal is 0.
- **One record per sample.** A visit, an on-wrist event, a device-usage report and an ECG session each become one ``SensorKitPreparedStructuredRecord``, and a wrist-temperature session one ``SensorKitTabularRecording``; each takes the zero-based position of its sample in the batch as its ordinal.

The other record cases, such as messages or phone usage, keyboard metrics, sleep sessions and a raw recording, take values you assemble; digest exactly what you pass.

``SensorKitSourceRecordID/derived(acquisitionBatch:sourceToken:deviceProductType:recordOrdinal:)`` names each record from the batch's coordinate, the stream's catalog token (`SensorKitCatalog.sourceToken(for:)`), the batch's device product type and that ordinal, never from its content.
Two guards keep one name meaning one content:

- **Your digest, across releases.** Each preparation exposes `retryEvidence`, the bytes Grove derives the record from. Digest them, persist the digest beside the record's id, and on a redelivery of the batch fail the batch when a digest differs: SensorKit may change records inside an unacknowledged boundary, and after the release only this digest stops an id from naming other content. An ECG session's evidence covers its identifier, states and waveform; its start, sampling frequency, lead and guidance enter its graph too, so digest them beside it.
- **The exporter's fingerprint, before the release.** Until the receipt is released, the ledger restates a reserved record only for the same content; other content under a reserved id becomes a new event, never a restated one.

Failing a batch means throwing before `acknowledge()`: the anchor stays, the batch is reissued after a restart under the same coordinate and ids, and the reservations it made stay for that redelivery.
A batch whose digests drifted can never be acknowledged as it was first delivered; abandon it with `SensorKit.discardPendingBatches(for:)`, which keeps the acknowledged cursor and fetches the same range again under new coordinates, so new ids.

A tabular batch, with `retryLog` standing for your app's durable store of each batch's digests and time zone, and `stageSidecar` for your upload of the bytes:

```swift
let productType = batch.info.device.productType
let recording = try SensorKitTabularRecording(samples: batch.samples, deviceProductType: productType)
let sourceRecordID = SensorKitSourceRecordID.derived(
    acquisitionBatch: batch.info.acquisitionBatch,
    sourceToken: recording.sourceToken,
    deviceProductType: productType,
    recordOrdinal: 0
)
try retryLog.verifyOrRecord(sourceRecordID, digest: SHA256.hash(data: recording.retryEvidence))
let sidecarPath = "sensorkit/\(sourceRecordID.value).\(recording.format.fileExtension)"
let record = try recording.sensorKitRecord(
    sourceRecordID: sourceRecordID,
    title: "Accelerometer",
    location: .sidecar(path: sidecarPath),
    admission: .callerAuthorizedOpaquePayload
)
let receipt = try exporter.export([record], sourceTimeZone: try retryLog.timeZone(of: batch, current: .current)) { export in
    if let graph = export.graph {
        try stageSidecar(recording.data, at: sidecarPath)
        try stage(graph.json)
    }
}
try await batch.acknowledge()
receipt.release()
```

A structured stream prepares each sample instead, such as `try SensorKitPreparedStructuredRecord(visit: sample)` with the sample's position as its ordinal; a preparation whose `nativePayload` is non-nil (a device-usage report or an ECG session) carries native bytes and takes the `sensorKitRecord(sourceRecordID:title:location:admission:)` form, every other one `sensorKitRecord(sourceRecordID:)`.
`receive` is called exactly once per record, in input order, with its graph or its refusal; a refused record is skipped, and the batch goes on.

A sidecar keeps large bytes out of the graph: the DocumentReference states the path you chose as `Attachment.url`, verbatim, with the bytes' size and SHA-1, and never fetches or carries them.
The path is a relative reference your deployment resolves, typically against the storage root you upload sidecars to, so ship the bytes there, unchanged, before the graph is acknowledged, and keep them immutable; a receiver checks what it fetched against the size and hash.
A path must be relative, with no empty, `.` or `..` segment, query or fragment.

SensorKit records cannot be retracted yet: the guide's retraction of a source record also names the device snapshots its event emitted, which are minted from that event, and the exporter takes no input that states it.

### Declare native recording bytes

Opaque native bytes can carry identifying or sensitive provider content.
Creating ``SensorKitNativeRecording`` therefore requires one explicit ``SensorRawPayloadAdmission``: caller-authorized opaque disclosure or verified sanitized input.
Grove does not inspect or sanitize those bytes, and the admission choice is never serialized.
The registered format determines the media types that the payload is allowed to use, and formats with one representation derive their media type automatically:

```swift
let recording = try SensorKitNativeRecording(
    title: "Accelerometer recording",
    format: .triaxialAccelerationSamples,
    payload: .sidecar(path: relativePath, bytes: csvData),
    admission: .callerAuthorizedOpaquePayload
)
recording.contentType // "text/csv", derived from the format registry
```

Some registry formats admit more than one exact media type.
A producer can use such a format only when its generated adapter row admits that format, and it must then supply one of the registered media types explicitly.
Construction rejects an unregistered media type and does not infer a FHIR release from payload bytes.
If the source payload already is a complete R4 `collection` Bundle, declare the registry's `fhir-collection-bundle` format; its initializer validates that envelope before conversion.

### What converts

The structured Grove FHIR mappings are rotation-rate SampledData, a hybrid ECG waveform plus its linked native recording, on-wrist state, device-usage summary plus its linked native recording, and visit summary.
Other catalog-admitted Grove SensorKit streams use an exact native RecordingDocument.
``SensorKitCatalog`` is generated from the IG and records implemented, deferred, and unavailable platform streams without claiming unsupported structure.
On iOS, typed initializers map Grove's already-fetched safe representations into these records; no initializer performs fetching.

### The source-neutral producer

``SensorConverter`` is the same exchange contract without SensorKit: it converts ``SensorRecord`` values a caller assembles from any sensor source into the identical graph shape, and imports no Apple sensor framework.
Its records carry the payload directly, as sampled data, an electrocardiogram, or a recording document.
``SensorConversionContext`` wraps an `ExchangeEventContext`, whose event identifier the caller numbers itself, and states the adapter token.
Its `sourceTimeZone` gives every effective bound the source's own offset; without one the bounds are in UTC and ``SensorConversion/warnings`` reports ``SensorConversionWarning/sourceOffsetUnavailable(field:)`` for each of them.

> Tip: Keep the conversion context beside the outbox entry it produced; a retry then rebuilds identical bytes without touching the clock.

> Note: The source-neutral producer is a candidate for removal: nothing in Grove or its known integrators converts through it.
> A source-neutral sensor adapter that is needed later returns as an exporter on the shape of ``SensorKitFHIRExporter``.

## Glossary

| IG term | Swift |
| --- | --- |
| Exchange event | `ExchangeEventIdentifier`, numbered by `ExchangeProducer` |
| Exchange graph | `ExchangeGraph`, held by ``SensorKitFHIRExporter/Export/graph`` |
| Business identifier | `BusinessIdentifier` |
| Identifier role | `GroveIdentifierRole` on a `RoledIdentifier` |
| Opaque identity | minted by `OpaqueIdentityScope` under `DeploymentIdentifierSystems` |
| Entry-node key | the `Canonicals.entryNodeKey` extension on each Bundle entry |
| Subject | `Subject` |
| Study enrollment | `StudyEnrollment` |
| Application, host and recording device | `ApplicationDevice`, `HostDevice`, `RecordingDevice` |
| Writer | the converting application, which SensorKit records as the assembler |
| Governed source identifier | `GovernedSourceIdentifierDisclosurePolicy` on ``SensorKitFHIRExporter/Options/nativeIdentifier`` |
| Producer diagnostic | `ProducerDiagnostic` from ``SensorKitConversionError/diagnostic`` |

## Topics

### Conversion

- ``SensorKitFHIRExporter``
- ``SensorKitConversionError``
- ``SensorKitRecord``
- ``SensorKitSourceRecordID``
- ``SensorKitNativeRecording``
- ``SensorRawPayloadAdmission``

### Preparing fetched batches

- ``SensorKitTabularRecording``
- ``SensorKitPreparedPPGRecording``
- ``SensorKitPreparedStructuredRecord``
- ``SensorKitRecordingLocation``

### Source-neutral conversion (candidates for removal)

- ``SensorConverter``
- ``SensorConversionContext``
- ``SensorConversion``
- ``SensorConversionWarning``
- ``SensorGraphIdentifiers``
- ``SensorBatchResult``
- ``SensorRecordFailure``
- ``SensorConversionError``
- ``SensorRecord``
- ``SensorRecordingDocument``
- ``SensorSampledDataRecord``
- ``SensorECGRecord``
- ``SensorCode``
- ``SensorRecordError``

### Recording payloads

- ``RecordingCSVReader``
- ``RecordingBinaryReader``
- ``RecordingBinaryWriter``
- ``SensorKitPPGRecording``

### Authoritative catalog

- ``SensorKitCatalog``
- ``SensorKitCatalogEntry``

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

Convert already-fetched SensorKit records into deterministic, conformant FHIR R4 exchange records.

## Overview

A SensorKit record, such as one batch of rotation-rate samples from a watch, becomes one immutable, self-describing exchange record: its FHIR outputs, the one Provenance that says how they were made, and the shared nodes they reference.
FHIR is the health-data interchange standard; an Observation or a DocumentReference is the resource that holds one measurement or one recording, and a Bundle is the container that carries them.
Records travel packed: one upload is one Bundle of many records that states each shared node once.
Any receiver can deduplicate and correct a record without knowing that it came from SensorKit.
Grove adds what plain FHIR lacks: stable identities that never leak the native record id, provenance saying which application assembled the record on which device, and optional study context.
The receiver gets records it can store and compare by version on a retry.

``SensorKitFHIRExporter`` consumes typed records you already fetched; it never queries SensorKit.
If you already know the pieces, jump to <doc:#Beyond-the-minimum>.

## What you need and why

Four inputs configure an exporter, SensorKit adds facts of its own, and everything else has a default.

### The subject pseudonym

The subject is the participant the record belongs to.
FHIR wants every clinical resource to point at a Patient; Grove points at the deployment's pseudonym instead, so the record carries no name and no account.
It is one `BusinessIdentifier`: an absolute URI your deployment owns as the system, and the participant's stable pseudonym as the value.
Persist the pair with the enrollment; `Subject.logical` is the default form.

### The identity scope

Every record and every output gets an opaque identity: an HMAC of the record's native facts under your deployment's secret key.
The same record exported twice yields the same identifier, so a receiver deduplicates, and nobody can recover the native id from it.
`OpaqueIdentityScope(root:keyID:epoch:key:)` derives the thirteen identifier systems the protocol recommends from your deployment root, a key id and an epoch, and holds them with the key.
Persist the key id and the epoch beside the key; rotating either changes every one of them.

The same key mints each record's version, a digest of its outputs and its Provenance: the conversion Provenance's entry key, which it repeats in `grove-record-version`.
The same content at the same conversion instant repeats the version, which makes a retry exact; any other content is a new version of the same source record, and a receiver keeps every version.
Only a holder of the key can recompute a version, through `ExchangeRecord.verifyVersion(in:)`.

### The repository scope

Two SensorKit stores must never collide: the store on one phone and the store on another can hold the same record id.
The repository scope is one `BusinessIdentifier` that names this installation's SensorKit store, and it enters every source-record and output identity.
Use a system your deployment owns and a token you persist once per installation, such as a UUID minted on first launch.

### The application

The conversion Provenance names the application that assembled the record, so a receiver knows who to trust and which version wrote it.
`ApplicationDevice(bundle:)` reads it from your bundle, and the application Device states its bundle identifier.

### The SensorKit facts

The exporter needs the system under which the exact `SRVisit.locationId` is carried; the guide requires one your deployment owns, scoped to the deployment or the source store, on every visit that names a location.
Each export call adds these facts about the batch:

- `sourceTimeZone` is the zone every effective bound states its offset in. SensorKit reports absolute instants and no zone, so use the device's zone when you first publish the batch, `TimeZone.current`, and persist it with the batch: a redelivery states the same bounds only under the same zone.
- `recordingDevice` is the `SRDevice` that recorded the batch, `RecordingDevice(batch.info.device)`, which every output names. It states every fact SensorKit exposes: the name, model, system name and version, and product type. `SRDevice.name` is the name a person gave the device, so keep it out of logs and upload metadata. Equal facts never prove one physical unit; set `stableUnitToken` and `tokenScope` only when your deployment governs a stable token for that unit, such as one it assigned to the participant's paired watch.
- `sourceDevices` are the peripherals that supplied the batch, `batch.info.sourceDevices.map(RecordingDevice.init)`, which SensorKit names from iOS 27. Each becomes a recording Device of its own, with its local identifier in the clear, that the Provenance's source entity names as its performer. SensorKit names them per fetch result and a record can fold several, so every record of the call states them all.
- `at` is the conversion instant. Persist it with the batch, so a redelivery repeats every record version.

> Note: The host defaults to `HostDevice.current()`.
> A rebuilt producer that states another application, host or studies gives a redelivery new versions, not exact retries.

## Assemble it

Once per installation, create the scope and name the application.
`hmacKey` is the `SymmetricKey` you load from the keychain, `keyID` and `epoch` the values persisted beside it.

```swift
let identityScope = try OpaqueIdentityScope(root: "https://study.example.org/fhir", keyID: keyID, epoch: epoch, key: hmacKey)
let application = try ApplicationDevice(bundle: .main)
```

Build the producer and the exporter once per configuration, and rebuild both when the participant, the studies or the application change.
`installationToken` is the token that names this SensorKit store.

```swift
let producer = try ExchangeProducer(
    identityScope: identityScope,
    subject: .logical(participant),
    application: application
)
let exporter = try SensorKitFHIRExporter(
    producer: producer,
    repositoryScope: try BusinessIdentifier(system: "https://study.example.org/fhir/NamingSystem/sensorkit-store", value: installationToken),
    visitLocationIdentifierSystem: "https://study.example.org/fhir/NamingSystem/sensorkit-visit-location"
)
```

Export each anchored batch, pack its records into Bundles, stage each Bundle's bytes verbatim, and acknowledge the batch; "Publish an anchored batch" below walks through one batch.

```swift
var bundles: [ExchangeGraph] = []
var packer = ExchangeBundlePacker(kind: .active)
try await exporter.export(
    records,
    sourceTimeZone: batchTimeZone,
    recordingDevice: RecordingDevice(batch.info.device),
    at: conversionInstant
) { export in
    guard let record = export.record else {
        return
    }
    if try packer.add(record) == .deferred {
        // The record belongs in the next Bundle: close this one and start that one with it.
        bundles.append(try packer.bundle(packedAt: conversionInstant))
        packer = ExchangeBundlePacker(kind: .active)
        _ = try packer.add(record)
    }
}
if packer.recordCount > 0 {
    bundles.append(try packer.bundle(packedAt: conversionInstant))
}
for bundle in bundles {
    try stage(bundle.json)
}
try await batch.acknowledge()
```

A record that would take the Bundle past a cap comes back from `add(_:)` as `deferred`, and starts the next Bundle; a fresh packer admits any one valid record.
Pack with the persisted conversion instant, so a redelivered batch stages the same bytes.

What to persist, and why:

| Value | Why |
| --- | --- |
| The key id and epoch, beside the key | They select the systems every identity is minted under. |
| The installation token | It is the repository scope of every identity this store mints. |
| The batch's time zone and conversion instant, and its recording-device token when you pass one | A redelivery repeats its record versions only with the same facts. |
| Each record's source record id and the digest of its `retryEvidence` | The id may name only the bytes first seen at its coordinate. |
| Each sidecar's bytes, at the path its record states | The record names the bytes by path, size and SHA-1, and never carries them. |

> Important: Never change the key or the epoch without deriving new systems.
> It breaks the promise that one identifier means one thing.

## Beyond the minimum

A known enrollment travels as a `StudyEnrollment` in the producer's `studies`, and the record carries its ResearchStudy, PlanDefinition and ResearchSubject entries; `Subject.bundled` adds the Patient itself.
Each Observation names the studies; a Recording Document names them only when it has no Observation, as a hybrid's document relates to exactly its Observation.

The clear SensorKit record id stays on the device by default: disclosing it needs ``SensorKitFHIRExporter/Options/nativeIdentifier`` set to `GovernedSourceIdentifierDisclosurePolicy.authorized` under a system you own.

```swift
var options = SensorKitFHIRExporter.Options()
options.nativeIdentifier = .authorized(system: "https://study.example.org/fhir/NamingSystem/sensorkit-record")
let disclosing = try SensorKitFHIRExporter(
    producer: producer,
    repositoryScope: repositoryScope,
    visitLocationIdentifierSystem: visitLocationSystem,
    options: options
)
try await disclosing.export(
    records,
    sourceTimeZone: batchTimeZone,
    recordingDevice: RecordingDevice(batch.info.device),
    sourceDevices: batch.info.sourceDevices.map(RecordingDevice.init),
    at: conversionInstant
) { export in
    try handle(export)
}
```

A record that cannot be converted is reported as ``SensorKitFHIRExporter/Export/Outcome/refused(_:)`` and the export continues; its ``SensorKitConversionError/diagnostic`` is one registered producer rule.

A retry is exact when its record's `version` repeats.

The conformance lane in `Scripts/validate-fhir-conformance.sh` proves this adapter's output against the grove-fhir corpora and the official validator.

### Publish an anchored batch

`SensorKit.fetchAnchored(_:batchSize:)` in `GroveSensorKit` delivers each batch with its `info`, whose acquisition coordinate survives a restart, and advances its query anchor only when you call `acknowledge()`.
One batch becomes records in one of two ways:

- **One record per batch.** A tabular stream (accelerometer, ambient light, ambient pressure, heart rate, pedometer) becomes one ``SensorKitTabularRecording`` from all its samples, and a photoplethysmogram batch one ``SensorKitPreparedPPGRecording`` from `SensorKitPPGRecording(samples:).prepared()`. A rotation-rate batch becomes one ``SensorKitRotationRateRecord`` from its samples, which exposes no `retryEvidence`, so digest the samples you pass. The record's ordinal is 0.
- **One record per sample.** A visit, an on-wrist event, a device-usage report and an ECG session each become one ``SensorKitPreparedStructuredRecord``, and a wrist-temperature session one ``SensorKitTabularRecording``; each takes the zero-based position of its sample in the batch as its ordinal.

The other record cases, such as messages or phone usage, keyboard metrics, sleep sessions and a raw recording, take values you assemble; digest exactly what you pass.

``SensorKitSourceRecordID/derived(acquisitionBatch:sourceToken:deviceProductType:recordOrdinal:)`` names each record from the batch's coordinate, the stream's catalog token (`SensorKitCatalog.sourceToken(for:)`), the batch's device product type and that ordinal, never from its content.
A fresh query anchor starts a random stream partition of its own, which the coordinate states, so a reinstall names no record of an earlier installation although its cursor restarts at the same place.

Your digest keeps one name meaning one content.
Each preparation exposes `retryEvidence`, the bytes Grove derives the record from.
Digest them, persist the digest beside the record's id, and on a redelivery of the batch fail the batch when a digest differs: SensorKit may change records inside an unacknowledged boundary, and only this digest stops an id from naming other content.
An ECG session's evidence covers its identifier, states and waveform; its start, sampling frequency, lead and guidance enter its record too, so digest them beside it.

Failing a batch means throwing before `acknowledge()`: the anchor stays, and the batch is reissued after a restart under the same coordinate and ids.
A batch whose digests drifted can never be acknowledged as it was first delivered; abandon it with `SensorKit.discardPendingBatches(for:)`, which keeps the acknowledged cursor and fetches the same range again under new coordinates, so new ids.

A tabular batch, with `retryLog` standing for your app's durable store of each batch's digests, time zone and conversion instant, and `stageSidecar` for your upload of the bytes:

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
// The app names the file where it writes it; the bytes are the recording's registered format.
let sidecarPath = "sensorkit/\(sourceRecordID.value).csv"
let record = try recording.sensorKitRecord(
    sourceRecordID: sourceRecordID,
    title: "Accelerometer",
    location: .sidecar(path: sidecarPath),
    admission: .callerAuthorizedOpaquePayload
)
let conversionInstant = try retryLog.conversionInstant(of: batch, current: .now)
var packer = ExchangeBundlePacker(kind: .active)
try await exporter.export(
    [record],
    sourceTimeZone: try retryLog.timeZone(of: batch, current: .current),
    recordingDevice: RecordingDevice(batch.info.device),
    at: conversionInstant
) { export in
    if let record = export.record {
        try stageSidecar(recording.data, at: sidecarPath)
        _ = try packer.add(record) // One record: an empty packer always adds it.
    }
}
try stage(packer.bundle(packedAt: conversionInstant).json)
try await batch.acknowledge()
```

A structured stream prepares each sample instead, such as `try SensorKitPreparedStructuredRecord(visit: sample)` with the sample's position as its ordinal; a preparation whose `nativePayload` is non-nil (a device-usage report or an ECG session) carries native bytes and takes the `sensorKitRecord(sourceRecordID:title:location:admission:)` form, every other one `sensorKitRecord(sourceRecordID:)`.
`receive` is called exactly once per record, in input order, with its record or its refusal; a refused record is skipped, and the batch goes on.

A sidecar keeps large bytes out of the record: the DocumentReference states the path you chose as `Attachment.url`, verbatim, with the bytes' size and SHA-1, and never fetches or carries them.
The path is a relative reference your deployment resolves, typically against the storage root you upload sidecars to, so ship the bytes there, unchanged, before the batch is acknowledged, and keep them immutable; a receiver checks what it fetched against the size and hash.
A path must be relative, with no empty, `.` or `..` segment, query or fragment.

The exporter has no retraction: it takes no input that names a record to take back.

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

## Glossary

| IG term | Swift |
| --- | --- |
| Record | `ExchangeRecord`, held by ``SensorKitFHIRExporter/Export/record`` |
| Record version | `RecordVersion`, the conversion Provenance's entry key |
| Exchange Bundle | `ExchangeGraph`, packed by `ExchangeBundlePacker` |
| Business identifier | `BusinessIdentifier` |
| Identifier role | `GroveIdentifierRole` on a `RoledIdentifier` |
| Opaque identity | minted by `OpaqueIdentityScope` under `DeploymentIdentifierSystems` |
| Entry key | the `Canonicals.entryKey` extension on each Bundle entry |
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

### Recording payloads

- ``RecordingCSVReader``
- ``RecordingBinaryReader``
- ``RecordingBinaryWriter``
- ``SensorKitPPGRecording``

### Authoritative catalog

- ``SensorKitCatalog``
- ``SensorKitCatalogEntry``

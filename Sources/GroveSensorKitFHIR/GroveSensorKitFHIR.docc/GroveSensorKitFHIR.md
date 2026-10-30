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
Any receiver can deduplicate, correct and retract an exchange graph without knowing that it came from SensorKit.
Grove adds what plain FHIR lacks: stable identities that never leak the native record id, provenance saying which application assembled the graph on which device, and optional study context.
The receiver gets a graph it can store, compare byte for byte on a retry, and take back by identity.

``SensorKitConverter`` consumes typed records you already fetched; it never queries SensorKit.
If you already know the pieces, jump to <doc:#Beyond-the-minimum>.

## What you need and why

Five inputs make the event context; SensorKit adds two facts of its own, and everything else has a default.

### The subject pseudonym

The subject is the participant the record belongs to.
FHIR wants every clinical resource to point at a Patient; Grove points at the deployment's pseudonym instead, so the graph carries no name and no account.
It is one `BusinessIdentifier`: an absolute URI your deployment owns as the system, and the participant's stable pseudonym as the value.
Persist the pair with the enrollment; `Subject.logical` is the default form.

### The identity scope

Every record and every output gets an opaque identity: an HMAC of the record's native facts under your deployment's secret key.
The same record exported twice yields the same identifier, so a receiver deduplicates, and nobody can recover the native id from it.
`DeploymentIdentifierSystems.derived(root:keyID:epoch:)` derives the twelve identifier systems the protocol recommends from your deployment root, a key id and an epoch, and `OpaqueIdentityScope` holds them with the key.
Persist the key id and the epoch beside the key; rotating either changes every system with it.

### The event identifier

Every export is an exchange event, and every event is immutable.
An `ExchangeEventIdentifier` is your producer instance UUID plus a monotonic `EventSequence`.
A retry resends the same bytes under the same identifier; a new revision of the record gets a new sequence.
Persist the producer instance once and the next sequence before you emit.

### The repository scope

Two SensorKit stores must never collide: the store on one phone and the store on another can hold the same record id.
The repository scope is one `BusinessIdentifier` that names this installation's SensorKit store, and it enters every opaque identity.
Use a system your deployment owns and a token you persist once per installation, such as a UUID minted on first launch.

### The application

The conversion Provenance names the application that assembled the graph, so a receiver knows who to trust and which version wrote it.
`ApplicationDevice(bundle:)` reads it from your bundle.

### The SensorKit facts

``SensorKitConversionContext`` adds the system under which the exact `SRVisit.locationId` is carried, and the time zone the source reported its instants in.
Both come from your deployment and the fetched batch, and both are persisted with the event.

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
`producerInstance` is the UUID persisted with the installation, `nextSequence` the counter you durably advanced first, `installationToken` the token that names this SensorKit store, and `sourceTimeZone` the zone the batch reported.

```swift
let event = try ExchangeEventIdentifier(system: systems.event, producerInstance: producerInstance, sequence: nextSequence)
let context = SensorKitConversionContext(
    event: ExchangeEventContext(
        subject: .logical(participant),
        event: event,
        identityScope: identityScope,
        repositoryScope: try BusinessIdentifier(system: "https://study.example.org/fhir/NamingSystem/sensorkit-store", value: installationToken),
        application: application
    ),
    visitLocationIdentifierSystem: "https://study.example.org/fhir/NamingSystem/sensorkit-visit-location",
    sourceTimeZone: sourceTimeZone
)
```

Convert one record and hand the Bundle to your uploader.
`recordID` is the ``SensorKitSourceRecordID`` derived from the anchored batch, and `samples` the rotation-rate samples it carried.

```swift
let record = SensorKitRotationRateRecord(sourceRecordID: recordID, samples: samples)
let conversion = try SensorKitConverter().convert(.rotationRate(record), context: context)
try upload(JSONEncoder().encode(conversion.bundle))
```

What to persist, and why:

| Value | Why |
| --- | --- |
| The event sequence, before emitting | A reused sequence under different content is a conflict the receiver cannot resolve. |
| The key id and epoch, beside the key | They select the systems every identity is minted under. |
| The producer instance id | It is half of every event identifier. |
| The installation token | It is the repository scope of every identity this store mints. |
| The source record id and its digest | A retry may reuse the id only for the same source bytes. |

> Important: Never reuse an event sequence for different content, and never change the key or the epoch without deriving new systems.
> Both break the promise that one identifier means one thing.

## Beyond the minimum

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

Every disclosure defaults to omission: the clear SensorKit record id needs `GovernedSourceIdentifierDisclosurePolicy.authorized` under a system you own, and a recording Device appears only when you name the physical unit.

```swift
let disclosing = SensorKitConversionContext(
    event: event,
    visitLocationIdentifierSystem: "https://study.example.org/fhir/NamingSystem/sensorkit-visit-location",
    sourceIdentifierDisclosurePolicy: .authorized(system: "https://study.example.org/fhir/NamingSystem/sensorkit-record"),
    recordingDevice: try RecordingDevice(stableUnitToken: watchToken),
    sourceTimeZone: sourceTimeZone
)
```

A `RepositoryID` per `ExchangeGraphNode` in `repositoryIDs` gives a graph node the logical id your repository assigned, and `ConverterRole.gatewayApplication` names a distinct application that mediated the measurement.

A batch supplies a context per record, because every record is its own event, and keeps a ``SensorKitRecordFailure`` for every record it did not emit; its ``SensorKitConversionError/diagnostic`` is one registered producer rule.

```swift
let batch = SensorKitConverter().convert(records) { record in
    try persistedContext(for: record.sourceRecordID)
}
```

A retry is exact when `ExchangeGraph.isSemanticallyEqual(to:)` says so, and earlier outputs are taken back by identity with a `RetractionEvent`.

The conformance lane in `Scripts/validate-fhir-conformance.sh` proves this adapter's output against the grove-fhir corpora and the official validator.

### Identify and acknowledge anchored batches

``SensorKitSourceRecordID`` preserves acquisition multiplicity.
Derive it from the anchored batch's persisted coordinate, sensor and device partitions, and the sample's zero-based ordinal.
Do not derive it from payload bytes: two byte-identical records acquired at different coordinates are two records.
Persist a digest of the source fields and native bytes beside the record; an exact retry must reproduce that digest before it may reuse the identifier.

```swift
for try await batch in sensorKit.fetchAnchored(sensor) {
    for (ordinal, sample) in batch.samples.enumerated() {
        let recordID = SensorKitSourceRecordID.derived(
            acquisitionBatch: batch.info.acquisitionBatch,
            sourceToken: sourceToken,
            deviceProductType: batch.info.device.productType,
            recordOrdinal: UInt64(ordinal)
        )
        let sourceDigest = try digestCanonicalSource(sample)
        try verifyRetryOrPersist(recordID, sourceDigest)

        let record = try makeRecord(sample, sourceRecordID: recordID)
        let conversion = try SensorKitConverter().convert(
            record,
            context: try persistedContext(for: recordID)
        )
        try persist(conversion.bundle)
    }

    // Advance the query cursor only after every retry-critical value and Bundle is durable.
    try await batch.acknowledge()
}
```

An unacknowledged batch is reissued after restart.
Asking for another batch first fails closed, as does acknowledging twice or acknowledging after the cursor has changed or been reset.

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
``SensorConversionContext`` wraps the same `ExchangeEventContext` and states the adapter token that the SensorKit context fixes to `sensorkit`.
Its `sourceTimeZone` gives every effective bound the source's own offset; without one the bounds are in UTC and ``SensorConversion/warnings`` reports ``SensorConversionWarning/sourceOffsetUnavailable(field:)`` for each of them.

> Tip: Keep the conversion context beside the outbox entry it produced; a retry then rebuilds identical bytes without touching the clock.

## Glossary

| IG term | Swift |
| --- | --- |
| Exchange event | `ExchangeEventIdentifier` and `ExchangeEventContext` |
| Exchange graph | `ExchangeGraph`, held by ``SensorKitConversion/graph`` |
| Business identifier | `BusinessIdentifier` |
| Identifier role | `GroveIdentifierRole` on a `RoledIdentifier` |
| Opaque identity | minted by `OpaqueIdentityScope` under `DeploymentIdentifierSystems` |
| Entry-node key | `EntryNodeKey` |
| Subject | `Subject` |
| Study enrollment | `StudyEnrollment` |
| Application, host and recording device | `ApplicationDevice`, `HostDevice`, `RecordingDevice` |
| Writer | the converting application, which SensorKit records as the assembler |
| Retraction event and target | `RetractionEvent`, `RetractionTarget` |
| Governed source identifier | `GovernedSourceIdentifierDisclosurePolicy` on ``SensorKitConversionContext/sourceIdentifierDisclosurePolicy`` |
| Producer diagnostic | `ProducerDiagnostic` from ``SensorKitConversionError/diagnostic`` |

## Topics

### Conversion

- ``SensorKitConverter``
- ``SensorKitConversionContext``
- ``SensorKitConversion``
- ``SensorKitBatchResult``
- ``SensorKitRecordFailure``
- ``SensorKitConversionError``
- ``SensorKitRecord``
- ``SensorKitSourceRecordID``
- ``SensorKitNativeRecording``
- ``SensorRawPayloadAdmission``

### Source-neutral conversion

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

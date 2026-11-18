# ``GroveFHIRContract``

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
    @TitleHeading("Producer Contract")
}

The identities, records and validated Bundles every Grove exporter shares.

## Overview

A health record on a phone, such as a heart rate a watch measured, becomes one immutable, self-describing exchange record: its outputs, the one Provenance that says how they were made, and the Devices and study context they reference.
FHIR is the health-data interchange standard; a Bundle is its container for a set of resources, and a resource is one typed record such as an Observation.
A record travels in an exchange graph, a FHIR Bundle of any number of records that share their Devices and study context as single entries.
Any receiver can deduplicate, correct and retract a record without knowing which platform produced it.
Grove adds what plain FHIR lacks: stable identities that never leak the native record id, provenance saying which application assembled the record on which device, and optional study context.
The receiver gets a record it can store, recognize on a retry by its record version, and take back by identity.

This module holds what the producers share.
`GroveHealthKitFHIR`, `GroveSensorKitFHIR` and `GroveQuestionnaireExtraction` turn HealthKit samples, SensorKit records and questionnaire responses into records with the types described here.
If you already know the pieces, jump to <doc:#Beyond-the-minimum>.

## What you need and why

Four inputs configure every exporter; everything else has a default.

### The subject pseudonym

The subject is the participant the record belongs to.
FHIR wants every clinical resource to point at a Patient; Grove points at the deployment's pseudonym instead, so the record carries no name and no account.
It is one ``BusinessIdentifier``: an absolute URI your deployment owns as the system, and the participant's stable pseudonym as the value.
Persist the pair with the enrollment; ``Subject/logical(_:)`` is the default form.

### The identity scope

Every record and every output gets an opaque identity: an HMAC of the record's native facts under your deployment's secret key.
The same record exported twice yields the same identifier, so a receiver deduplicates, and nobody can recover the native id from it.
``OpaqueIdentityScope/init(root:keyID:epoch:key:)`` derives the thirteen identifier systems the protocol recommends from your deployment root, a key id and a ``KeyEpoch``, and holds them with the key.
Persist the key id and the epoch beside the key; rotating either changes every opaque system with it.

### The repository scope

Two source stores must never collide: the HealthKit store on one phone and the one on another phone can hold the same record id.
The repository scope is one ``BusinessIdentifier`` that names the store the record came from, and it enters every source-record identity and every output identity derived from one.
Device and context snapshots leave it out: a snapshot is keyed by the subject and its own content, and a recording Device by the subject and the unit's token.
Persist it with the installation.

### The application

The conversion Provenance names the application that assembled the record, so a receiver knows who to trust and which version wrote it.
``ApplicationDevice/init(bundle:)`` reads it from your bundle.

> Note: The producer's ``HostDevice`` defaults to ``HostDevice/current(processInfo:)`` and an export's instant to now.
> A record's version is a keyed digest of its outputs and its Provenance, the export instant included: the same content repeats the version, which is an exact retry, and anything else is a new version of the same source record.

## Assemble it

Once per installation, create the scope and name the application.
`hmacKey` is the `SymmetricKey` you load from the keychain, `keyID` and `epoch` the values persisted beside it.

```swift
let identityScope = try OpaqueIdentityScope(root: "https://study.example.org/fhir", keyID: keyID, epoch: epoch, key: hmacKey)
let application = try ApplicationDevice(bundle: .main)
```

Then build the producer, and rebuild it when the participant, the studies or the application change.

```swift
let producer = try ExchangeProducer(
    identityScope: identityScope,
    subject: .logical(participant),
    application: application
)
```

The exporter for your source turns one source record into an ``ExchangeRecord``.
Stage its ``ExchangeRecord/json`` verbatim, never a re-encoding of its Bundle, and read it back with ``ExchangeRecord/init(validating:)``.
A record an exporter returns is validated already.

To upload, add the staged records to an ``ExchangeBundlePacker`` and send the ``ExchangeGraph/json`` of the ``ExchangeGraph`` that ``ExchangeBundlePacker/bundle(packedAt:transportIdentifier:)`` returns.
Records of one Bundle state each shared node once, and packing or repacking them changes no record.
Re-validation is the reader's step: a receiver, or your app reading stored bytes back to trust them again, validates them under the kind the Bundle's profile claims, and ``ExchangeGraph/records()`` splits them into their records.

```swift
let restored = try ExchangeGraph(validating: storedBytes, kind: .active)
let versions = try restored.records().map(\.version)
```

What to persist, and why:

| Value | Why |
| --- | --- |
| The key id and epoch, beside the key | They select the systems every identity is minted under. |
| The staged record bytes | A record's version covers its export instant, so converting a record again is a new version, not a retry. |

> Important: Never change the key or the epoch without deriving new systems.
> It breaks the promise that one identifier means one thing.

## Beyond the minimum

A known enrollment travels as a ``StudyEnrollment``, and every record carries its ResearchStudy, PlanDefinition and ResearchSubject entries; ``Subject/bundled(_:_:)`` adds the Patient itself.

```swift
let enrollment = try StudyEnrollment(
    study: study,
    protocolURL: FHIRPrimitive(Canonical(stringLiteral: "https://study.example.org/PlanDefinition/a")),
    protocolVersion: "1",
    enrollment: enrollmentIdentifier
)
```

Every disclosure policy defaults to omission.
``GovernedSourceIdentifierDisclosurePolicy/authorized(system:type:)`` discloses the clear native record identifier under a system you own; each adapter's exporter options state the rest, such as HealthKit's workout route.

The exporters assign no resource id.
A ``RepositoryID`` is a logical id your repository already assigned, which `GroveQuestionnaireFHIR` states on a Questionnaire or QuestionnaireResponse it builds when you pass one.

A retry is exact when its ``RecordVersion`` is the same: member order, whitespace and escaping do not matter, as a version digests the record's canonical form, but `72` and `72.0` are different content.
Only a holder of the identity key can recompute a version; a receiver compares it, and ``ExchangeRecord/verifyVersion(in:)`` recomputes it on your side.

An exporter's retraction record takes back one whole source record by its typed identity: its Provenance target names that identity, the resource type and its role (the ``Canonicals/retractionTargetRole`` extension).
A target carries the record's native record identifier (the ``Canonicals/retractionTargetNativeIdentifier`` extension) only where the governed-source-identifier policy authorizes it, and never addresses the target by it.
`Provenance.occurred` is the deletion or detection instant, or bounds on the deletion when the source states no time.
Active and retraction records never share a Bundle.

Every refusal and every warning is one ``ProducerDiagnostic`` whose code is a registered ``ExchangeGraphRule``.
The conformance lane in `Scripts/validate-fhir-conformance.sh` proves an adapter's output against the grove-fhir corpora and the official validator.

> Tip: Keep one identity scope per key epoch, and keep the epoch in the systems, so an old record stays verifiable after a rotation.

## Glossary

| IG term | Swift |
| --- | --- |
| Record | ``ExchangeRecord``, one source-record revision |
| Exchange graph | ``ExchangeGraph``, packed by ``ExchangeBundlePacker`` |
| Record version | ``RecordVersion``, repeated in the ``Canonicals/recordVersion`` extension |
| Business identifier | ``BusinessIdentifier`` |
| Identifier role | ``GroveIdentifierRole`` on a ``RoledIdentifier`` |
| Opaque identity | minted by ``OpaqueIdentityScope`` under ``DeploymentIdentifierSystems`` |
| Source-record identity | ``SourceRecordIdentity``; it names the output identities that extend it |
| Entry key | the ``Canonicals/entryKey`` extension on each Bundle entry |
| Subject | ``Subject`` and its ``Subject/identifier`` |
| Study enrollment | ``StudyEnrollment`` |
| Application, host and recording device | ``ApplicationDevice``, ``HostDevice``, ``RecordingDevice`` |
| Writer | chosen by each exporter's writer option, for HealthKit `HealthKitFHIRExporter.WriterPolicy` |
| Retraction record and target | an ``ExchangeRecord`` of kind ``ExchangeRecord/Kind/retraction``, whose Provenance target carries the ``Canonicals/retractionTargetRole`` extension |
| Governed source identifier | ``GovernedSourceIdentifierDisclosurePolicy`` |
| Producer diagnostic | ``ProducerDiagnostic`` with its ``ExchangeGraphRule`` |

## Recording bytes

``RecordingCSVWriter`` writes a tabular format of the recording-format registry, and ``RecordingCSVReader`` reads one back. A writer created for a ``RegisteredRecordingFormat`` writes exactly the format's columns and refuses a row whose field violates its column's registered value type or absence rule, before any byte of the row is written. The reader refuses the same rows, so a payload one writes the other reads. Numbers and integers use the registry's canonical lexemes, which prohibit a plus sign, an exponent, a leading integer zero, negative zero and a redundant trailing zero in a fraction, and admit a lone `.0` for an integral number.

Use ``RecordingCSVReader/Stream`` to read the same grammar in chunks without retaining every row. ``RecordingCSVReader/Limits`` bounds the bytes a reader retains, independently of the chunk size. Delivered rows remain provisional until `finish()` validates the complete payload. A syntactically valid CSV is not itself a clinical validation result: converters separately enforce their required measurements and sample counts.

``RecordingFile`` owns an immutable temporary snapshot of recording bytes. Stage one by copying a file with ``RecordingFile/stage(copying:maximumByteCount:)`` or from an asynchronous byte stream with ``RecordingFile/stage(chunks:maximumByteCount:)``; later changes to the source don't affect the snapshot, and a failure never returns a partial one. Read it in chunks of at most 64 KiB with ``RecordingFile/readChunks(_:)`` or ``RecordingFile/chunks``, where every reader has its own position and nothing is read ahead. The snapshot computes its FHIR attachment checksum while it is written. It has no filesystem name and closes with its last owner, so a durable upload queue copies its chunks into its own storage before acknowledging collection.

``RecordingCSVFileWriter`` writes the same bytes as ``RecordingCSVWriter`` directly into a recording file, retaining only the current row and a 64 KiB buffer. It checks the total, row and field sizes before it allocates a row, and an error or cancellation closes it, so it never finishes a partial recording.

``RecordingFile/zstandardCompressed()`` returns one Zstandard frame of the bytes when it is strictly smaller, and `nil` when the snapshot should be sent unchanged. ``RecordingFile/zstandardDecompressed(decompressedByteCount:maximumWindowByteCount:)`` decodes exactly one complete frame of a declared size within a history window budget; apply a decompressed byte budget before calling it. FHIR attachment size and checksum describe the original bytes, so a transport that compresses them keeps its own encoding, stored size and stored digest, and verifies the original size and digest after decompression.

These operations are synchronous disk operations and belong on a background executor.

## Inspect collection contracts

``FHIRMeasurementCatalog`` exposes the pinned guide's measurement and HealthKit inventory facts on Apple platforms and Linux. Use ``FHIRMeasurementCatalog/measurement(id:)`` to inspect a measurement's temporal shape, canonical quantity unit and components. ``FHIRMeasurementCatalog/healthKitSource(identifier:)`` keeps every declared measurement identifier and profile alternative of a row; a workout row names both its session and its segments. Apple callers pass a `HealthKitSourceType`'s `rawValue` instead of building another table of source names.

Guide admission establishes neither converter availability nor participant permission nor receiver capability: a supported row can still lack an implemented producer, and a missing value shape never admits arbitrary content. Adapters choose their own source semantics for a `dateTimeOrPeriod` contract, and receivers still validate the complete graph against its profiles. The descriptors read the generated contracts; they perform no conversion or unit arithmetic.

## Topics

### Identities

- ``IdentifierSystem``
- ``BusinessIdentifier``
- ``RoledIdentifier``
- ``GroveIdentifierRole``
- ``DeploymentIdentifierSystems``
- ``OpaqueIdentityScope``
- ``SourceRecordIdentity``
- ``KeyEpoch``
- ``RecordVersion``
- ``ExchangeIdentityError``

### The producer

- ``ExchangeProducer``
- ``ConversionFacts``

### The record's context

- ``Subject``
- ``StudyEnrollment``
- ``ApplicationDevice``
- ``HostDevice``
- ``RecordingDevice``

### Records and Bundles

- ``ExchangeRecord``
- ``ExchangeBundlePacker``
- ``ExchangeGraph``
- ``ExchangeGraphRule``
- ``ProducerDiagnostic``
- ``ExchangeGraphError``
- ``ConversionBatch``
- ``RepositoryID``

### Disclosure

- ``GovernedSourceIdentifierDisclosurePolicy``
- ``RecordingPayloadAdmission``

### Recordings

- ``RegisteredRecordingFormat``
- ``RecordingCSVWriter``
- ``RecordingCSVReader``
- ``RecordingFile``
- ``RecordingCSVFileWriter``

### Collection contracts

- ``FHIRMeasurementCatalog``
- ``FHIRMeasurementDefinition``
- ``HealthKitSourceDefinition``

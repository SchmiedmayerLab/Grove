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

The identities, event context and validated graph every Grove producer shares.

## Overview

A health record on a phone, such as a heart rate a watch measured, becomes one immutable, self-describing FHIR Bundle called the exchange graph.
FHIR is the health-data interchange standard; a Bundle is its container for a set of resources, and a resource is one typed record such as an Observation.
Any receiver can deduplicate, correct and retract an exchange graph without knowing which platform produced it.
Grove adds what plain FHIR lacks: stable identities that never leak the native record id, provenance saying which application assembled the graph on which device, and optional study context.
The receiver gets a graph it can store, compare byte for byte on a retry, and take back by identity.

This module holds what the producers share.
`GroveHealthKitFHIR`, `GroveSensorKitFHIR` and `GroveQuestionnaireExtraction` turn HealthKit samples, SensorKit records and questionnaire responses into graphs with the types described here.
If you already know the pieces, jump to <doc:#Beyond-the-minimum>.

## What you need and why

Five inputs make every exchange event; everything else has a default.

### The subject pseudonym

The subject is the participant the record belongs to.
FHIR wants every clinical resource to point at a Patient; Grove points at the deployment's pseudonym instead, so the graph carries no name and no account.
It is one ``BusinessIdentifier``: an absolute URI your deployment owns as the system, and the participant's stable pseudonym as the value.
Persist the pair with the enrollment; ``Subject/logical(_:)`` is the default form.

### The identity scope

Every record and every output gets an opaque identity: an HMAC of the record's native facts under your deployment's secret key.
The same record exported twice yields the same identifier, so a receiver deduplicates, and nobody can recover the native id from it.
``OpaqueIdentityScope/init(root:keyID:epoch:key:)`` derives the twelve identifier systems the protocol recommends from your deployment root, a key id and an epoch, and holds them with the key.
Persist the key id and the epoch beside the key; rotating either changes every opaque system with it, while the event and entry-node systems stay with the root.

### The event identifier

Every export is an exchange event, and every event is immutable.
An ``ExchangeEventIdentifier`` is your producer instance UUID plus a monotonic ``EventSequence``.
A retry resends the same bytes under the same identifier; a new revision of the record gets a new sequence.
An ``ExchangeProducer`` mints both and keeps them, with what each event states, in a ledger your app stores; <doc:ExchangeLedgerStorage> says what that storage must guarantee.
The HealthKit, SensorKit and Questionnaire exporters number every event through it.
A caller-managed converter that takes an ``ExchangeEventContext`` you build yourself, such as the source-neutral sensor converter, does not use the ledger: persist the producer instance once and durably advance the next sequence before you emit.

### The repository scope

Two source stores must never collide: the HealthKit store on one phone and the one on another phone can hold the same record id.
The repository scope is one ``BusinessIdentifier`` that names the store the record came from, and it enters every opaque identity.
Persist it with the installation.

### The application

The conversion Provenance names the application that assembled the graph, so a receiver knows who to trust and which version wrote it.
``ApplicationDevice/init(bundle:)`` reads it from your bundle.

> Note: The producer's ``HostDevice`` defaults to ``HostDevice/current(processInfo:)`` and an export's instant to now.
> The producer freezes both with each event, so a redelivery before the receipt is released rebuilds the same bytes; an ``ExchangeEventContext`` freezes nothing, so pass both explicitly when you replay a persisted event.

## Assemble it

Once per installation, create the scope and name the application.
`hmacKey` is the `SymmetricKey` you load from the keychain, `keyID` and `epoch` the values persisted beside it.

```swift
let identityScope = try OpaqueIdentityScope(root: "https://study.example.org/fhir", keyID: keyID, epoch: epoch, key: hmacKey)
let application = try ApplicationDevice(bundle: .main)
```

Then build the producer over the ledger your app stores, and rebuild it when the participant, the studies or the application change.
`ledgerStorage` conforms to ``ExchangeProducer/Storage``.

```swift
let producer = try ExchangeProducer(
    identityScope: identityScope,
    subject: .logical(participant),
    application: application,
    storage: ledgerStorage
)
```

The exporter for your source mints each event through the producer and turns one record into an ``ExchangeGraph``.
Store and upload its ``ExchangeGraph/json`` verbatim, never a re-encoding of its Bundle, and release the call's ``ExchangeProducer/Receipt`` only once those bytes and your source cursor are durably committed.
Before you trust bytes you stored or received, re-validate them.

```swift
let restored = try ExchangeGraph(validating: storedBytes, kind: .active)
precondition(restored.isSemanticallyEqual(to: graph))
```

What to persist, and why:

| Value | Why |
| --- | --- |
| The ledger | It numbers every event and freezes what each one states until the receipt is released; a reused sequence under different content is a conflict the receiver cannot resolve. |
| The producer instance and the next sequence, for an adapter that takes an ``ExchangeEventContext`` | The ledger does not number those events; advance the sequence durably before you emit, and never reuse one for different content. |
| The key id and epoch, beside the key | They select the systems every identity is minted under. |

> Important: Never restore the ledger from a backup or copy it to another installation, and never change the key or the epoch without deriving new systems.
> Each breaks the promise that one identifier means one thing.

## Beyond the minimum

A known enrollment travels as a ``StudyEnrollment``, and the graph carries its ResearchStudy, PlanDefinition and ResearchSubject entries; ``Subject/bundled(_:_:)`` adds the Patient itself.

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

The exporters assign no resource id, apart from the HealthKit exporter's opt-in transitional legacy `Bundle.id`.
A ``RepositoryID`` per ``ExchangeGraphNode`` in an ``ExchangeEventContext`` gives a node of a caller-managed converter's graph the logical id your repository assigned, and nothing else in the graph changes.

``ConverterRole/gatewayApplication(_:)`` names a distinct application that mediated the measurement; it travels as a second application snapshot when an Observation output names it through `observation-gatewayDevice`, and document-only graphs carry none.

A retry is exact when ``ExchangeGraph/isSemanticallyEqual(to:)`` says so: member order, whitespace and escaping do not matter, but `72` and `72.0` are different content.

An exporter's retraction graph takes back earlier outputs by typed identity: each Provenance target names the identity, the resource type and its role (the ``Canonicals/retractionTargetRole`` extension).
A target carries the record's native record identifier (the ``Canonicals/retractionTargetNativeIdentifier`` extension) only where the governed-source-identifier policy authorizes it, and never addresses the target by it.
`Provenance.occurred` is the deletion or detection instant, or bounds on the deletion when the source states no time.

Every refusal and every warning is one ``ProducerDiagnostic`` whose code is a registered ``ExchangeGraphRule``.
The conformance lane in `Scripts/validate-fhir-conformance.sh` proves an adapter's output against the grove-fhir corpora and the official validator.

> Tip: Keep one identity scope per key epoch, and keep the epoch in the systems, so an old graph stays verifiable after a rotation.

## Glossary

| IG term | Swift |
| --- | --- |
| Exchange event | ``ExchangeEventIdentifier`` and ``ExchangeEventContext`` |
| Exchange graph | ``ExchangeGraph`` |
| Business identifier | ``BusinessIdentifier`` |
| Identifier role | ``GroveIdentifierRole`` on a ``RoledIdentifier`` |
| Opaque identity | minted by ``OpaqueIdentityScope`` under ``DeploymentIdentifierSystems`` |
| Source-record identity | ``SourceRecordIdentity``; it names the output identities that extend it |
| Entry-node key | the ``Canonicals/entryNodeKey`` extension on each Bundle entry |
| Subject | ``Subject`` and its ``Subject/identifier`` |
| Study enrollment | ``StudyEnrollment`` |
| Application, host and recording device | ``ApplicationDevice``, ``HostDevice``, ``RecordingDevice`` |
| Writer | ``ExchangeGraphNode/writer`` and ``ExchangeGraphNode/writerHost``, chosen by the adapter's writer option, for HealthKit `HealthKitFHIRExporter.WriterPolicy` |
| Retraction event and target | an ``ExchangeGraph`` of kind ``ExchangeGraph/Kind/retraction``, whose Provenance targets carry the ``Canonicals/retractionTargetRole`` extension |
| Governed source identifier | ``GovernedSourceIdentifierDisclosurePolicy`` |
| Producer diagnostic | ``ProducerDiagnostic`` with its ``ExchangeGraphRule`` |

## Topics

### Identities

- ``IdentifierSystem``
- ``BusinessIdentifier``
- ``RoledIdentifier``
- ``GroveIdentifierRole``
- ``DeploymentIdentifierSystems``
- ``OpaqueIdentityScope``
- ``SourceRecordIdentity``
- ``EventSequence``
- ``ExchangeEventIdentifier``
- ``RepositoryID``
- ``ExchangeIdentityError``

### The producer and its ledger

- ``ExchangeProducer``
- ``ExchangeProducer/Receipt``
- <doc:ExchangeLedgerStorage>

### The event

- ``ExchangeEventContext``
- ``Subject``
- ``StudyEnrollment``
- ``ApplicationDevice``
- ``HostDevice``
- ``RecordingDevice``
- ``ConverterRole``
- ``ExchangeGraphNode``
- ``ConversionBatch``

### The graph

- ``ExchangeGraph``
- ``ExchangeGraphRule``
- ``ProducerDiagnostic``
- ``ExchangeGraphError``

### Disclosure

- ``GovernedSourceIdentifierDisclosurePolicy``

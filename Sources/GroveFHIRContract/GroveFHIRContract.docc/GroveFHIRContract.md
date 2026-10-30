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
`GroveHealthKitFHIR` and `GroveSensorKitFHIR` turn platform records into graphs with the types described here.
If you already know the pieces, jump to <doc:#Beyond-the-minimum>.

## What you need and why

Five inputs make a context; everything else has a default.

### The subject pseudonym

The subject is the participant the record belongs to.
FHIR wants every clinical resource to point at a Patient; Grove points at the deployment's pseudonym instead, so the graph carries no name and no account.
It is one ``BusinessIdentifier``: an absolute URI your deployment owns as the system, and the participant's stable pseudonym as the value.
Persist the pair with the enrollment; ``Subject/logical(_:)`` is the default form.

### The identity scope

Every record and every output gets an opaque identity: an HMAC of the record's native facts under your deployment's secret key.
The same record exported twice yields the same identifier, so a receiver deduplicates, and nobody can recover the native id from it.
``DeploymentIdentifierSystems/derived(root:keyID:epoch:)`` derives the twelve identifier systems the protocol recommends from your deployment root, a key id and an epoch, and ``OpaqueIdentityScope`` holds them with the key.
Persist the key id and the epoch beside the key; rotating either changes every system with it.

### The event identifier

Every export is an exchange event, and every event is immutable.
An ``ExchangeEventIdentifier`` is your producer instance UUID plus a monotonic ``EventSequence``.
A retry resends the same bytes under the same identifier; a new revision of the record gets a new sequence.
Persist the producer instance once and the next sequence before you emit.

### The repository scope

Two source stores must never collide: the HealthKit store on one phone and the one on another phone can hold the same record id.
The repository scope is one ``BusinessIdentifier`` that names the store the record came from, and it enters every opaque identity.
Persist it with the installation.

### The application

The conversion Provenance names the application that assembled the graph, so a receiver knows who to trust and which version wrote it.
``ApplicationDevice/init(bundle:)`` reads it from your bundle.

> Note: ``HostDevice`` defaults to ``HostDevice/current(processInfo:)`` and the conversion instant to now.
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
`producerInstance` is the UUID persisted with the installation and `nextSequence` the counter you durably advanced first.

```swift
let event = try ExchangeEventIdentifier(system: systems.event, producerInstance: producerInstance, sequence: nextSequence)
let context = ExchangeEventContext(
    subject: .logical(participant),
    event: event,
    identityScope: identityScope,
    repositoryScope: repositoryScope,
    application: application
)
```

The adapter for your source turns the context and one record into an ``ExchangeGraph``; encode its Bundle and hand it to your uploader.
Before you trust bytes you stored or received, re-validate them.

```swift
let bytes = try JSONEncoder().encode(graph.bundle)
let restored = try ExchangeGraph(kind: .active, jsonData: bytes)
precondition(restored.isSemanticallyEqual(to: graph))
```

What to persist, and why:

| Value | Why |
| --- | --- |
| The event sequence, before emitting | A reused sequence under different content is a conflict the receiver cannot resolve. |
| The key id and epoch, beside the key | They select the systems every identity is minted under. |
| The producer instance id | It is half of every event identifier. |

> Important: Never reuse an event sequence for different content, and never change the key or the epoch without deriving new systems.
> Both break the promise that one identifier means one thing.

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
``GovernedSourceIdentifierDisclosurePolicy/authorized(system:type:)`` discloses the clear native record identifier under a system you own, and ``RouteDisclosurePolicy/authorized`` admits a workout route.

A ``RepositoryID`` per ``ExchangeGraphNode`` gives a graph node the logical id your repository assigned, and nothing else in the graph changes.

``ConverterRole/gatewayApplication(_:)`` names a distinct application that mediated the measurement; it travels as a second application snapshot.

A retry is exact when ``ExchangeGraph/isSemanticallyEqual(to:)`` says so: member order, whitespace and escaping do not matter, but `72` and `72.0` are different content.

A ``RetractionEvent`` takes back earlier outputs by typed identity; each ``RetractionTarget`` names the identity, the resource type and its ``RetractionTargetRole``.
A target carries the record's ``RetractionTarget/nativeRecordIdentifier`` only where the governed-source-identifier policy authorizes it, and the event renders it beside the target without ever addressing the target by it.
Its ``RetractionOccurrence`` is the deletion or detection instant, or bounds on the deletion when the source states no time.

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
| Source-record identity | ``SourceRecordIdentity``, or ``ProviderRecordIdentity`` for a provider-owned record; it mints the output and artifact identities that extend it |
| Entry-node key | ``EntryNodeKey`` |
| Subject | ``Subject`` and its ``Subject/identifier`` |
| Study enrollment | ``StudyEnrollment`` |
| Application, host and recording device | ``ApplicationDevice``, ``HostDevice``, ``RecordingDevice`` |
| Writer | ``ExchangeGraphNode/writer`` and ``ExchangeGraphNode/writerHost``, chosen by the adapter's writer option, for HealthKit `HealthKitWriter` |
| Retraction event and target | ``RetractionEvent``, ``RetractionTarget``, ``RetractionTargetRole`` |
| Governed source identifier | ``GovernedSourceIdentifierDisclosurePolicy`` |
| Producer diagnostic | ``ProducerDiagnostic`` with its ``ExchangeGraphRule`` |

## Topics

### Identities

- ``IdentifierSystem``
- ``BusinessIdentifier``
- ``RoledIdentifier``
- ``GroveIdentifierRole``
- ``DeploymentIdentifierSystems``
- ``OpaqueIdentitySystems``
- ``OpaqueIdentityScope``
- ``SourceRecordIdentity``
- ``ProviderRecordIdentity``
- ``OpaqueIdentityKind``
- ``EventSequence``
- ``ExchangeEventIdentifier``
- ``EntryNodeKey``
- ``RepositoryID``

### The event

- ``ExchangeEventContext``
- ``Subject``
- ``StudyEnrollment``
- ``ApplicationDevice``
- ``HostDevice``
- ``RecordingDevice``
- ``ConverterRole``
- ``ExchangeGraphNode``
- ``ExchangeGraphIdentifiers``
- ``ConversionBatch``

### The graph

- ``ExchangeGraph``
- ``ExchangeGraphKind``
- ``ExchangeGraphRule``
- ``ProducerDiagnostic``
- ``ExchangeGraphError``
- ``RetractionEvent``
- ``RetractionTarget``
- ``RetractionTargetRole``
- ``RetractionOccurrence``

### Disclosure

- ``GovernedSourceIdentifierDisclosurePolicy``
- ``GovernedSourceIdentifierType``
- ``RouteDisclosurePolicy``

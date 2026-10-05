# Configuring the Exporter

<!--
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
-->

Supply the subject, identity, device and disclosure inputs every exported event states.

## Overview

The Grove Mobile implementation guide (`https://grovealliance.org/fhir/mobile`) explains the shared FHIR concepts; this article covers what is specific to this exporter.

An exporter is configured once per participant and installation, and every event it exports states that configuration.
Its `ExchangeProducer` holds the subject, the deployment's identity scope, the converting application and its host, and the participant's known studies, and numbers every event in its ledger.
The exporter adds the repository scope, which names this installation's HealthKit store, and ``HealthKitFHIRExporter/Options``: whether the source revision's writer is stated (only when you classify it as an application; by default it is omitted), how a sample's `HKDevice` resolves to a recording device, how your application relates to the measurement, and which disclosures the deployment authorizes.

```swift
let producer = try ExchangeProducer(
    identityScope: identityScope,
    subject: .logical(participantID),
    application: try ApplicationDevice(bundle: .main),
    studies: enrollments,
    storage: ledgerStorage
)
let exporter = try HealthKitFHIRExporter(producer: producer, repositoryScope: healthKitRepository, options: options)
let receipt = try exporter.export(samples) { export in
    try stage(export)
}
```

The host defaults to the current host and the export instant to now.
The producer freezes the instant, the application, the host and the studies with each event it reserves, so a redelivery before the receipt is released rebuilds the same bytes even when they changed in between.
The entry-node system comes from the identity scope, which holds all twelve deployment systems.

## Naming the subject

`Subject` is the link from every emitted clinical resource to the participant it belongs to.
`Subject.logical` is the default: the deployment's pseudonym as one complete `BusinessIdentifier`, emitted as an identifier-only logical `Reference` with the exact `Reference.type` token `Patient`.
The same pair participates in the opaque identity preimages, so the subject is stated once.
`Subject.bundled` adds the caller's `Patient` resource to the graph as an entry-node entry when a deployment exchanges the resource itself.
Never send an email address, display label, bare value, or literal URL in place of the pair.

## Attributing a study

A known enrollment travels as a `StudyEnrollment`: the study identifier, the protocol's canonical URL and version, and the enrollment identifier.
The exporter emits the `ResearchStudy`, `PlanDefinition`, and `ResearchSubject` entries itself under the catalog's entry-node roles, and every output carries the `workflow-researchStudy` extension.
A recording document names its studies in `DocumentReference.context.related` instead.
The producer's `studies` default to none.

Each enrollment keeps its own protocol revision: study A can carry protocol A version 2 while study B carries protocol B version 4.
Study relevance does not assert that a measurement followed a protocol, so no output carries `instantiatesCanonical`.
It grants no access either; consent and access decisions stay with the receiver, and a study-scoped export omits unrelated study associations.

The producer freezes the studies with each event, so a redelivery states them unchanged.
A later study association is the receiver's decision, recorded separately, not a reexport with altered metadata.

## Identifying the converting application

`ApplicationDevice` records which app produced the graph; `HostDevice` is the separate device on which it ran.
Both become immutable event-time `Device` snapshots, and the application snapshot links to its host.
Each snapshot's identity is minted from the event and the device's `sourceDeviceToken`: `<bundle identifier>|<version>`, plus `|<build>` when present, for the application, and `<model>|<operating-system version>` for the host, whose model `HostDevice.current()` reads from `uname`.
Do not update one stable Device resource across historical events.

`ApplicationDevice(bundle:)` reads the running bundle; a bare test runner has no bundle identity and fails there rather than inside an export.
Supply the facts explicitly in a command-line tool:

```swift
let application = try ApplicationDevice(
    name: "Example Study",
    bundleIdentifier: "org.example.study",
    version: "2.0.0",
    build: "42"
)
let host = HostDevice.current()
```

``HealthKitFHIRExporter/RolePolicy`` states how the application relates to the measurement.
`.assembler` is the default; `.gatewayForOwnWrites` marks the samples the application wrote in the build it runs as mediated by it, `.gateway` marks every measurement so, and `.gatewayApplication` names a distinct application that mediated them, emitted as a second application snapshot when an Observation references it through `observation-gatewayDevice`.
Recording and clinical documents carry no gateway link under any role.

## Numbering the events

The Bundle identifier is an `ExchangeEventIdentifier`.
Its wire value is `e0:<producer-instance UUID>:<positive monotonic sequence>`, and its system is the deployment's event system.

The producer's ledger mints the producer instance once and hands out the sequences in one ledger transaction per call, one per record it has not reserved yet.
A record exported again before its receipt is released keeps its event and its frozen facts, so the redelivery is byte-identical; after the release, or with other content, a new export of it is a new event.
Each record of an ECG, the ECG and each correlated symptom, takes an event of its own.
Never restore the ledger from a backup or copy it to another installation: two installations would then hand out the same events.

## Configuring opaque identities

`OpaqueIdentityScope` owns the HMAC key id, positive epoch, key material, and a distinct deployment-owned identifier system for each closed identity kind.
`DeploymentIdentifierSystems.derived(root:keyID:epoch:)` derives all twelve systems in the protocol's recommended form from one deployment root; a rotated key uses a new key id or epoch and with them new opaque systems.
Never reuse one system across kinds or deployments.
The scope rejects a short key, the published conformance key, a malformed URI, a repeated system, a wrong component count, or an empty core field.

Source UUIDs, bundle identifiers, device tokens, and source-revision linkage stay in the framed HMAC preimage rather than clear global Grove NamingSystems.
Every output carries typed `source-record` and `source-output` identifiers; recording documents additionally carry `source-artifact`.

## Choosing the recording device and disclosures

``HealthKitFHIRExporter/Options/recordingDevice`` names the physical unit behind a sample's `HKDevice`.
The default `.localIdentifier` uses the per-unit `HKDevice.localIdentifier`; model and version facts cannot identify a unit, so a device without one yields no recording Device and the export reports the `mobile-omission.recording-device` warning.
`.custom` takes your own ``RecordingDeviceResolver``, and `.omit` states no recording Device at all.
Every disclosure defaults to omission: the UDI, the workout route, and the clear native identifier are emitted only under an explicit authorized option, and an omission an option chose never warns.
``HealthKitFHIRExporter/Options/nativeIdentifier`` governs both paths: the primary output of an export and the targets a retraction names for a deletion carry the HealthKit UUID under the same authorized system.

## Understanding the two kinds of time

FHIR separates when a measurement happened from when a record was published; the guide's *New to FHIR* page explains the distinction under *Reading an Observation*.

This exporter keeps the distinct clocks explicit:

- `Observation.effective` is read from each sample's own `HKSample.startDate` and `endDate`, in the sample's own time zone when `HKMetadataKeyTimeZone` names one and in UTC with a `mobile-omission.source-offset` warning located at each effective element otherwise, and no effective value ever takes the phone's current zone.
- `Observation.issued` is absent because HealthKit exposes no object availability/modification instant.
- `Provenance.occurred`, `Provenance.recorded`, `Bundle.timestamp` and `DocumentReference.date` take the instant the event was first reserved at, frozen in the ledger, always in UTC at millisecond precision with ASCII digits, so a retry after the phone changed time zone or locale rebuilds the same bytes.
- A redelivery reuses that instant; a later source version receives a new event and instant.

The exporter reads no clock beyond the `at` instant of a call, which defaults to now.
This prevents a retry from silently changing the clinical graph.

Every graph the exporter delivers is already validated; `ExchangeGraph(validating:kind:)` validates serialized bytes again, for example on the receiving side.
Its JSON initializer preserves the shared conformance-corpus diagnostic even when a mutation changes `resourceType` so that ModelsR4 could not otherwise decode the resource.
Validation closes entry types, direct profile modes, typed identities, governed target types, fixed UCUM system/code pairs, numeric domains, contained nodes, and support connectivity.

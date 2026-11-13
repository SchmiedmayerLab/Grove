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

Supply the subject, identity, device and disclosure inputs every exported record states.

## Overview

The Grove Mobile implementation guide (`https://grovealliance.org/fhir/mobile`) explains the shared FHIR concepts; this article covers what is specific to this exporter.

An exporter is configured once per participant and installation, and every record it exports states that configuration.
Its `ExchangeProducer` holds the subject, the deployment's identity scope, the converting application and its host, and the participant's known studies.
The exporter adds the repository scope, which names this installation's HealthKit store, and ``HealthKitFHIRExporter/Options``: whether the source revision's writer is stated (only when you classify it as an application; by default it is omitted), which token proves the physical unit behind a sample's `HKDevice`, how your application relates to the measurement, and which disclosures the deployment authorizes.

```swift
let producer = try ExchangeProducer(
    identityScope: identityScope,
    subject: .logical(participantID),
    application: try ApplicationDevice(bundle: .main),
    studies: enrollments
)
let exporter = try HealthKitFHIRExporter(producer: producer, repositoryScope: healthKitRepository, options: options)
try await exporter.export(samples) { export in
    try stage(export)
}
```

The host defaults to the current host and the export instant to now.
Everything a record states is its content: when the instant, the application, the host or the studies change, a redelivery is a new version of the same source record.
The identity scope holds all thirteen deployment systems.

## Naming the subject

`Subject` is the link from every emitted clinical resource to the participant it belongs to.
`Subject.logical` is the default: the deployment's pseudonym as one complete `BusinessIdentifier`, emitted as an identifier-only logical `Reference` with the exact `Reference.type` token `Patient`.
The same pair participates in the opaque identity preimages, so the subject is stated once.
`Subject.bundled` adds the caller's `Patient` resource to the record as a `context-snapshot` node, keyed by its content, when a deployment exchanges the resource itself.
Never send an email address, display label, bare value, or literal URL in place of the pair.

## Attributing a study

A known enrollment travels as a `StudyEnrollment`: the study identifier, the protocol's canonical URL and version, and the enrollment identifier.
The exporter emits the `ResearchStudy`, `PlanDefinition`, and `ResearchSubject` entries itself as `context-snapshot` nodes, each keyed by its content, and every Observation output carries the `workflow-researchStudy` extension.
A recording or clinical document names its studies in `DocumentReference.context.related` instead.
The producer's `studies` default to none.

Each enrollment keeps its own protocol revision: study A can carry protocol A version 2 while study B carries protocol B version 4.
Study relevance does not assert that a measurement followed a protocol, so no output carries `instantiatesCanonical`.
It grants no access either; consent and access decisions stay with the receiver, and a study-scoped export omits unrelated study associations.

A later study association is the receiver's decision, recorded separately, not a reexport with altered metadata.

## Identifying the converting application

`ApplicationDevice` records which app produced the record; `HostDevice` is the separate device on which it ran.
Both become immutable `Device` snapshots, and the application snapshot links to its host.
Each snapshot's identity is a keyed digest of the subject, its role and its complete content, which `Device.parent` is part of, so the same content is the same snapshot in every record of a subject and changed content is a new one.
`HostDevice.current()` reads the product type from `uname` and the operating-system version and build; the facts `UIDevice` holds need the main actor, so an app that states them passes them to `HostDevice(operatingSystemName:operatingSystemVersion:operatingSystemBuild:productType:model:name:manufacturer:)`.
Do not update one stable Device resource across historical records.

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

## Recognizing a retry

A record has no sequence and no event: its identity is its content.
A conversion Provenance's entry key is the record version, a keyed digest of the source record, the Provenance and the outputs in target order, over their canonical JSON tokens, and the Provenance repeats it in its `grove-record-version` extension.
An exact retry repeats the version.
Any other content, a later `Provenance.recorded` included, is a new version of the same source record; a receiver keeps every version and selects the current one.
Each record of an ECG, the ECG and each correlated symptom, is a record of its own.

## Configuring opaque identities

`OpaqueIdentityScope` owns the HMAC key id, positive epoch, key material, and a distinct deployment-owned identifier system for each closed identity kind.
`OpaqueIdentityScope(root:keyID:epoch:key:)` derives all thirteen systems in the protocol's recommended form from one deployment root (`DeploymentIdentifierSystems.derived(root:keyID:epoch:)` alone, when you hold the systems apart from the key); a rotated key uses a new key id or epoch and with them new opaque systems.
Never share a deployment root, and with it its systems, across deployments.
The scope rejects a short key, the published conformance key, a malformed URI, a wrong component count, or an empty core field.

Source UUIDs, bundle identifiers, device tokens, and source-revision linkage stay in the framed HMAC preimage rather than clear global Grove NamingSystems.
Every output carries typed `source-record` and `source-output` identifiers; recording documents additionally carry `source-artifact`.

## Choosing the unit token and disclosures

Every non-nil `HKDevice` is a recording Device, stating its name, manufacturer, model, versions, local identifier and UDI. Sample device metadata supplements missing facts for both Observation and document outputs. Recognizable device metadata creates a recording Device even when `HKDevice` is absent; descriptive facts alone do not establish a stable physical-unit identity.
An `HKDevice` property wins over its key, a key fills only an absent field, and the serial number and the UDI production identifier come only from their keys.
These facts prove no physical unit; two Devices of equal content are one snapshot, not one unit.

``HealthKitFHIRExporter/Options/unitToken`` picks the token that does, and nothing else.
The default `.localIdentifier` uses `HKDevice.localIdentifier`, `.custom` takes your own token, and `.none` states no unit.
The token enters the keyed `recording-device` identity, scoped to the writing source's `HKSource.bundleIdentifier`, as a local identifier is local to one host and writable by any application.

Grove carries every source fact, and a deployment that shares data applies its own policy to the sensitive ones, such as a serial number or a name a person gave a device.
Workout routes and clear native identifiers default to omission and are emitted only under an explicit authorized option. An omission an option chose never warns. Supported sample metadata is preserved by default, as described below.
``HealthKitFHIRExporter/Options/nativeIdentifier`` governs both paths: the primary output of an export and the target of a retraction carry the HealthKit UUID under the same authorized system.

## Preserving source metadata

``HealthKitFHIRExporter/Options/metadata`` defaults to `.authorized`, preserving otherwise unmapped sample metadata on the primary output. Values faithfully represented by clinical elements, recording Devices or other IG-defined constructs are not duplicated. When an `HKDevice` fact conflicts with sample metadata, the device fact takes precedence and the different metadata value remains in the typed extension. Set it to `.omit` for an explicit deployment exclusion. Strings, finite numbers, Booleans, dates, known SDK enumerations and quantities with supported compatible units retain their types. Custom keys are preserved; arrays, nested dictionaries, binary values and unsupported quantity dimensions remain observable omissions. The native UUID option remains independent.

The container uses `https://grovealliance.org/fhir/core/StructureDefinition/metadata`. Each `entry` has a `key` child containing the exact runtime key and a `value` child containing its typed value. Metadata participates in record versioning: changing the exported metadata changes the record version while source and output identifiers remain stable. Preserve staged records verbatim for retries.

Clinical source bytes remain unchanged; their DocumentReference wrapper carries the metadata. Metadata on contained workout parts or correlation objects is not flattened into the parent's extension. Read each export's metadata summary and omission warnings to distinguish successful conversion from complete preservation.

## Understanding the two kinds of time

FHIR separates when a measurement happened from when a record was published; the guide's *New to FHIR* page explains the distinction under *Reading an Observation*.

This exporter keeps the distinct clocks explicit:

- `Observation.effective` is an `effectivePeriod` from `HKSample.startDate` to `endDate` where the measurement's profile fixes a Period, and for heart rate whenever the two differ at millisecond precision; otherwise it is an `effectiveDateTime` at `startDate`, and an instant-only measurement's interval `endDate` is withheld with no warning, because the pinned guide registers none. It is read in the sample's own time zone when `HKMetadataKeyTimeZone` names one and in UTC with a `mobile-omission.source-offset` warning located at each effective element otherwise, and no effective value ever takes the phone's current zone.
  A blood-pressure correlation's own `HKMetadataKeyTimeZone` and `HKMetadataKeyWasUserEntered` decide when it states them; otherwise its members supply the zone every member naming one agrees on, and manual entry only when every member states it.
- `Observation.issued` is absent because HealthKit exposes no object availability/modification instant.
- `Provenance.occurred`, `Provenance.recorded` and `DocumentReference.date` take the `at` instant of the call, always in UTC at millisecond precision with ASCII digits, so a retry at that instant after the phone changed time zone or locale rebuilds the same bytes. Every record of one call shares it.
- `Bundle.timestamp` is the packing time of the Bundle that carries the record, and enters no identity.

The exporter reads no clock beyond the `at` instant of a call, which defaults to now.
This prevents a retry from silently changing a record.

Every record the exporter delivers is already validated; `ExchangeRecord(validating:)` and `ExchangeGraph(validating:kind:)` validate serialized bytes again, for example on the receiving side.
Its JSON initializer preserves the shared conformance-corpus diagnostic even when a mutation changes `resourceType` so that ModelsR4 could not otherwise decode the resource.
Validation closes entry types, direct profile modes, typed identities, governed target types, fixed UCUM system/code pairs, numeric domains, contained nodes, and support connectivity.

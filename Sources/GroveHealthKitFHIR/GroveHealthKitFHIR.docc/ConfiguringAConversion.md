# Configuring a Conversion

<!--
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
-->

Supply the durable event, subject, device, and disclosure inputs for one source record/version.

## Overview

The Grove Mobile implementation guide (`https://grovealliance.org/fhir/mobile`) explains the shared FHIR concepts; this article covers what is specific to this converter.

A conversion context is an event record, not a bag of defaults.
The shared `ExchangeEventContext` carries the subject, the producer instance and monotonic event sequence, the converting application and its host, the deployment's identity scope, the source repository scope, and the conversion instant.
``HealthKitConversionOptions`` adds the HealthKit-specific choices: which writer the source revision names, how a sample's `HKDevice` resolves to a recording device, and which disclosures the deployment authorizes.
Construct and persist the event inputs before conversion; an exact retry reuses them unchanged.

```swift
let event = ExchangeEventContext(
    subject: .logical(participantID),
    event: persistedEventIdentifier,
    identityScope: identityScope,
    repositoryScope: healthKitRepository,
    application: try ApplicationDevice(bundle: .main),
    host: persistedHost,
    conversionInstant: persistedConversionInstant
)
let context = HealthKitConversionContext(event: event)
let conversion = try HealthKitConverter().convert(sample, context: context)
```

The host and the conversion instant default to the current host and to now; a replay passes the persisted values so the retry rebuilds the same bytes.
The entry-node system comes from the identity scope, which holds all twelve deployment systems.

## Naming the subject

`Subject` is the link from every emitted clinical resource to the participant it belongs to.
`Subject.logical` is the default: the deployment's pseudonym as one complete `BusinessIdentifier`, emitted as an identifier-only logical `Reference` with the exact `Reference.type` token `Patient`.
The same pair participates in the opaque identity preimages, so the subject is stated once.
`Subject.bundled` adds the caller's `Patient` resource to the graph as an entry-node entry when a deployment exchanges the resource itself.
Never send an email address, display label, bare value, or literal URL in place of the pair.

## Attributing a study

A known enrollment travels as a `StudyEnrollment`: the study identifier, the protocol's canonical URL and version, and the enrollment identifier.
The converter emits the `ResearchStudy`, `PlanDefinition`, and `ResearchSubject` entries itself under the catalog's entry-node roles, and every output carries the `workflow-researchStudy` extension.
`studies` defaults to none.

## Identifying the converting application

`ApplicationDevice` records which app produced the graph; `HostDevice` is the separate device on which it ran.
Both become immutable event-time `Device` snapshots, and the application snapshot links to its host.
Each snapshot's identity is minted from the event and the device's `sourceDeviceToken`: `<bundle identifier>|<version>`, plus `|<build>` when present, for the application, and `<model>|<operating-system version>` for the host, whose model `HostDevice.current()` reads from `uname`.
Do not update one stable Device resource across historical events.

`ApplicationDevice(bundle:)` reads the running bundle; a bare test runner has no bundle identity and fails there rather than inside a conversion.
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

`ConverterRole` states how the application relates to the measurement.
`.assembler` is the default; `.gateway` marks the converting application as the one that mediated the measurement, and `.gatewayApplication` names a distinct application that did, emitted as a second application snapshot referenced by `observation-gatewayDevice`.

## Persisting the event identity

The Bundle identifier is an `ExchangeEventIdentifier`.
Its wire value is `e0:<producer-instance UUID>:<positive monotonic sequence>`, and its system is the deployment's event system.

- Generate the producer UUID once and persist it.
- Reserve and durably persist the next `EventSequence` before emitting an event.
- Reuse the complete identifier, conversion instant, and identity inputs for an exact retry.
- Allocate a distinct event for every new source record/version; a batch supplies a context per sample and never shares one event identity across samples.

Do not derive the sequence from the wall clock, source UUID, or payload.
Those shortcuts cannot prove monotonicity and can mint a new identity during a retry.

## Configuring opaque identities

`OpaqueIdentityScope` owns the HMAC key id, positive epoch, key material, and a distinct deployment-owned identifier system for each closed identity kind.
`DeploymentIdentifierSystems.derived(root:keyID:epoch:)` derives all twelve systems in the protocol's recommended form from one deployment root; a rotated key uses a new key id or epoch and with them new opaque systems.
Never reuse one system across kinds or deployments.
The scope rejects a short key, the published conformance key, a malformed URI, a repeated system, a wrong component count, or an empty core field.

Source UUIDs, bundle identifiers, device tokens, and source-revision linkage stay in the framed HMAC preimage rather than clear global Grove NamingSystems.
Every output carries typed `source-record` and `source-output` identifiers; recording documents additionally carry `source-artifact`.

## Choosing the recording device and disclosures

`options.recordingDevice` names the physical unit behind a sample's `HKDevice`.
The default ``HealthKitLocalIdentifierResolver`` uses the per-unit `HKDevice.localIdentifier`; model and version facts cannot identify a unit, so a device without one yields no recording Device and the conversion reports ``HealthKitConversionWarning/recordingDeviceOmitted(deviceName:)``.
Every disclosure policy defaults to omission: the UDI, the workout route, and the clear native identifier are emitted only under an explicit authorized policy, and an omission a policy chose never warns.
The native-identifier policy governs both paths: the primary output of a conversion and the targets ``HealthKitConverter/retractionTargets(for:context:)`` names for a deletion carry the HealthKit UUID under the same authorized system.

## Understanding the two kinds of time

FHIR separates when a measurement happened from when a record was published; the guide's *New to FHIR* page explains the distinction under *Reading an Observation*.

This converter keeps the distinct clocks explicit:

- `Observation.effective` is read from each sample's own `HKSample.startDate` and `endDate`, in the sample's own time zone when `HKMetadataKeyTimeZone` names one and in UTC with ``HealthKitConversionWarning/sourceOffsetUnavailable(field:)`` naming each effective element otherwise; a workout's segments follow the workout's zone the same way, and no effective value ever takes the phone's current zone.
- `Observation.issued` is absent because HealthKit exposes no object availability/modification instant.
- `Provenance.occurred`, `Provenance.recorded`, and `Bundle.timestamp` take the event's persisted `conversionInstant`, always in UTC, so a retry after the phone changed time zone rebuilds the same bytes.
- A retry reuses that instant; a later source version receives a new event and instant.

The converter never reads the clock.
This prevents a retry from silently changing the clinical graph.

Before upload, validate the complete serialized graph with `ExchangeGraph`.
Its JSON initializer preserves the shared conformance-corpus diagnostic even when a mutation changes `resourceType` so that ModelsR4 could not otherwise decode the resource.
Validation closes entry types, direct profile modes, typed identities, governed target types, fixed UCUM system/code pairs, numeric domains, contained nodes, and support connectivity.

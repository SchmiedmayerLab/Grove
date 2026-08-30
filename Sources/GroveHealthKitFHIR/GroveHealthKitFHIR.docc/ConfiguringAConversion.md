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

Supply the durable event, subject, device, and privacy inputs for one source record/version.

## Overview

The Grove Mobile implementation guide (`https://grovealliance.org/fhir/mobile`) is the single place the shared FHIR concepts below are explained; this article covers what is specific to this converter.

A conversion context is an event record, not a bag of defaults. It carries the logical subject and
its stable identity, the producer instance and monotonic event sequence, the converter and host
snapshots, the deployment's current HMAC key epoch, the source repository scope, and the conversion
instant. Construct and persist these inputs before conversion; an exact retry reuses them unchanged.

The subject is an identifier-only logical `Reference`. The converter does not emit the caller's
`Patient`, so it rejects a literal `Patient/123` reference that would dangle inside the closed Bundle.

```swift
let patientID = try BusinessIdentifier(
    system: "https://study.example/fhir/identifiers/participant",
    value: "participant-42"
)
let patient = Reference(
    identifier: patientID.fhirIdentifier,
    type: FHIRPrimitive(FHIRURI(stringLiteral: "Patient"))
)
```

Build one ``HealthKitConversionContext`` per immutable source record/version and then convert:

```swift
let context = HealthKitConversionContext(
    subject: patient,
    subjectIdentity: patientID,
    converter: converter,
    converterHost: converterHost,
    eventIdentifier: persistedEventIdentifier,
    entryNodeIdentifierSystem: entryNodeSystem,
    identityScope: deploymentIdentityScope,
    repositoryScope: healthKitRepository,
    conversionInstant: persistedConversionInstant
)
let conversion = try HealthKitConverter().convert(sample, context: context)
```

## Naming the subject

`subject` is the link from every emitted clinical resource to the participant it belongs to. It must
contain exactly one complete `Identifier` and the exact `Reference.type` token `Patient`; it must not
also contain `Reference.reference`. The implementation guide's *New to FHIR* page explains why this
logical reference remains resolvable without inventing a Bundle-local Patient.

For this converter, two things follow:

- Use a deployment-owned absolute ASCII URI as `Identifier.system` and a nonempty stable value.
- Pass the complete pair separately as `subjectIdentity`; it participates in opaque HMAC preimages
  but the converter never substitutes it for the FHIR reference.
- Never send an email address, display label, bare value, or literal URL in place of the pair.

## Identifying the converting application

`converter` records which app produced the graph. `converterHost` is the separate device on which it
ran. Both become immutable event-time `Device` snapshots; the application snapshot links to its host.
Do not update one stable Device resource across historical events.

Supply the value explicitly in a bare test runner or a command-line tool, where there is no application bundle to read:

```swift
let converter = HealthKitApplication(
    name: "Example Study",
    bundleIdentifier: "org.example.study",
    version: "2.0.0 (42)"
)
```

## Persisting the event identity

The Bundle identifier is an `ExchangeEventIdentifier`. Its wire value is
`e0:<producer-instance UUID>:<positive monotonic sequence>`. The identifier system is
deployment-owned and stable for that producer instance.

- Generate the producer UUID once and persist it.
- Reserve and durably persist the next positive sequence before emitting an event.
- Reuse the complete identifier, conversion instant, and identity inputs for an exact retry.
- Allocate a distinct event for every new source record/version. A batch therefore supplies a
  context per sample through `contextForSample`; it never shares one event identity across samples.

Do not derive the sequence from the wall clock, source UUID, or payload. Those shortcuts cannot prove
monotonicity and can mint a new identity during a retry.

## Configuring pseudonymous identities

`PseudonymousIdentityScope` owns the HMAC key id, positive epoch, key material, and a distinct
deployment-owned identifier system for each closed identity kind. Rotate by creating new
key-epoch-specific systems; never reuse one system across kinds or deployments. The API rejects a
short key, zero epoch, malformed URI, repeated system, wrong component count, or empty core field.

Source UUIDs, bundle identifiers, device tokens, and source-revision linkage stay in the framed HMAC
preimage rather than clear global Grove NamingSystems. Every output carries typed `source-record` and
`source-output` identifiers; recording documents additionally carry `source-artifact`.

## Understanding the two kinds of time

FHIR separates when a measurement happened from when a record was published; the guide's *New to FHIR* page explains the distinction under *Reading an Observation*.

This converter keeps the distinct clocks explicit:

- **`Observation.effective`** is read from each sample's own `HKSample.startDate` and `endDate`.
  A batch of a thousand samples produces a thousand different effective times.
- **`Observation.issued` is absent** because HealthKit exposes no object availability/modification
  instant. A conversion clock is not a valid substitute.
- **`Provenance.occurred`**, **`Provenance.recorded`**, and **`Bundle.timestamp`** take the event's
  persisted `conversionInstant`.
- A retry reuses that instant. A later source version receives a new event and instant.

The converter never reads the clock. This prevents a retry from silently changing the clinical graph.

Before upload, validate the complete serialized graph with `ExchangeGraph`. Its JSON initializer
preserves the shared conformance-corpus diagnostic even when a mutation changes `resourceType` so
that ModelsR4 could not otherwise decode the resource. Validation closes entry types, direct profile
modes, typed identities, governed target types, fixed UCUM system/code pairs, numeric domains,
contained nodes, and support connectivity.

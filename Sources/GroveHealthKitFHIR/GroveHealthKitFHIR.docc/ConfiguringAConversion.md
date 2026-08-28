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

Decide who the data is about, who converted it, and which namespace names the resources the export creates.

## Overview

The Grove Mobile implementation guide (`https://grovealliance.org/fhir/mobile`) is the single place the shared FHIR concepts below are explained; this article covers what is specific to this converter.

A conversion needs one piece of information the device cannot supply — the subject — and derives the rest from the running application.

The subject is a FHIR `Reference` naming the participant the measurements belong to. Your backend assigns that id when it enrols the participant; the converter never invents one. <doc:ConfiguringAConversion#Naming-the-subject> covers how to choose it.

```swift
let patient = Reference(reference: "Patient/1a2b3c")
let conversion = try HealthKitConverter().convert(sample, for: patient)
```

Reach for ``HealthKitConversionContext`` when you need a study reference, a disclosure policy, or a fixed instant.

```swift
let context = HealthKitConversionContext(
    subject: patient,
    researchStudies: [Reference(reference: "ResearchStudy/heart-study")]
)
let result = HealthKitConverter().convert(samples, context: context)
```

## Naming the subject

`subject` is the link from every emitted `Observation` to the participant it belongs to, written as `"Patient/<id>"` where `<id>` is the patient's id **in the receiving system**.
The implementation guide's *New to FHIR* page, under *References, identifiers, and ids*, explains what that means in FHIR terms and why an email address is the wrong choice.

For this converter, two things follow:

- Pass the id your backend already assigns — a study enrolment id or an account primary key.
- If the backend has not created the `Patient` yet, create it first and convert afterwards.
  The converter never invents a subject, and there is no default.

## Identifying the converting application

`converter` records which app produced the graph, and defaults to ``HealthKitApplication/main``, which reads the name, bundle identifier, and version from the app's own bundle.
It becomes a `Device` resource in the output — see <doc:TheConversionGraph>.

Supply the value explicitly in a bare test runner or a command-line tool, where there is no application bundle to read:

```swift
let converter = HealthKitApplication(
    name: "Example Study",
    bundleIdentifier: "org.example.study",
    version: "2.0.0 (42)"
)
```

## Choosing an identifier namespace

A FHIR business identifier is a `system`/`value` pair, where the system names whose numbering scheme the value belongs to; the guide's *New to FHIR* page covers that under *References, identifiers, and ids*.

Most resources here already have a natural identifier: an `Observation` carries the HealthKit object UUID it came from.
But three kinds of node exist *only* because you ran an export — the `Bundle`, the conversion `Provenance`, and any `Device` the converter derived.
`graphIdentifierSystem` is the namespace their identifiers are minted in.

The identifiers are derived deterministically, so converting the same samples twice produces the same identifiers and the receiving server can recognise a re-send instead of storing a duplicate.

The default is derived from your bundle identifier — `urn:grove:healthkit-graph:org.example.study` — which is globally unique and stable across releases.
Once the deployment owns a server namespace, pass it instead:

```swift
let context = HealthKitConversionContext(
    subject: patient,
    graphIdentifierSystem: "https://mystudy.example.org/fhir/identifiers/mobile-graph"
)
```

Keep one namespace per deployment. Changing it re-mints every derived identifier, so previously exported graphs no longer deduplicate against new ones.

## Understanding the two kinds of time

FHIR separates when a measurement happened from when a record was published; the guide's *New to FHIR* page explains the distinction under *Reading an Observation*.

This converter fills both from different places, and that is worth being explicit about:

- **`Observation.effective`** is read from each sample's own `HKSample.startDate` and `endDate`.
  A batch of a thousand samples produces a thousand different effective times.
- **`Provenance.recorded` and `Bundle.timestamp`** both take the single `conversionInstant`.
  One export is one provenance event, so sharing that instant across the batch is deliberate rather than an oversight.
- **`Observation.issued`** is left out entirely.
  HealthKit keeps no publication timestamp for a sample, and filling it from the clock would make every re-conversion of unchanged data look like a new version.
  The conversion time is already recorded once, on the `Provenance`.

`conversionInstant` defaults to the wall clock; pass a fixed value to make a conversion byte-for-byte reproducible in tests.

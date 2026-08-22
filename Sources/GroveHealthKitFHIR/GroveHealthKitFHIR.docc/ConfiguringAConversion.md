# Configuring a Conversion

Decide who the data is about, who converted it, and which namespace names the resources the export creates.

## Overview

A conversion needs one piece of information the device cannot supply — the subject — and derives the rest from the running application.

```swift
let conversion = try HealthKitFHIRConverter().convert(sample, for: patient)
```

Reach for ``HealthKitFHIRConversionContext`` when you need a study reference, a disclosure policy, or a fixed instant.

```swift
let context = HealthKitFHIRConversionContext(
    subject: Reference(reference: "Patient/1a2b3c"),
    researchStudies: [Reference(reference: "ResearchStudy/heart-study")]
)
let result = HealthKitFHIRConverter().convert(samples, context: context)
```

## Naming the subject

FHIR keeps clinical facts in separate resources and links them by reference, so every `Observation` states whose measurement it is.
`subject` is that link, written as `"Patient/<id>"`, where `<id>` is the patient's id **in the receiving system**.

Use the identifier your backend already assigns to the participant — a study enrollment id or an account's primary key both work.
Two properties matter:

- **Stable.** The value is part of the resource forever. A participant whose id changes appears as two different people.
- **Not a personal detail.** An email address or phone number is neither stable nor safe to spread across a clinical record, so do not use one.

If your backend has not created the `Patient` yet, create it first and convert afterwards; the converter never invents a subject.

## Identifying the converting application

`converter` records which app produced the graph, and defaults to ``HealthKitFHIRApplication/main``, which reads the name, bundle identifier, and version from the app's own bundle.
It becomes a `Device` resource in the output — see <doc:TheConversionGraph>.

Supply the value explicitly in a bare test runner or a command-line tool, where there is no application bundle to read:

```swift
let converter = HealthKitFHIRApplication(
    name: "Example Study",
    bundleIdentifier: "org.example.study",
    version: "2.0.0 (42)"
)
```

## Choosing an identifier namespace

In FHIR, a business identifier is a pair: a `system` that names *whose* numbering scheme it is, and a `value` that is unique **within** that scheme.
The system exists because "patient 42" is meaningless on its own — "patient 42 in Example Hospital's medical record numbering" is not.

Most resources here already have a natural identifier: an `Observation` carries the HealthKit object UUID it came from.
But three kinds of node exist *only* because you ran an export — the `Bundle`, the conversion `Provenance`, and any `Device` the converter derived.
`graphIdentifierSystem` is the namespace their identifiers are minted in.

The identifiers are derived deterministically, so converting the same samples twice produces the same identifiers and the receiving server can recognise a re-send instead of storing a duplicate.

The default is derived from your bundle identifier — `urn:grove:healthkit-graph:org.example.study` — which is globally unique and stable across releases.
Once the deployment owns a server namespace, pass it instead:

```swift
let context = HealthKitFHIRConversionContext(
    subject: patient,
    graphIdentifierSystem: "https://mystudy.example.org/fhir/identifiers/mobile-graph"
)
```

Keep one namespace per deployment. Changing it re-mints every derived identifier, so previously exported graphs no longer deduplicate against new ones.

## Understanding the two kinds of time

A converted graph carries two unrelated timestamps, and mixing them up is the most common modelling mistake.

- **When the measurement happened** comes from each sample, individually. The converter reads `HKSample.startDate` and `endDate` and writes `Observation.effective`. A batch of a thousand samples produces a thousand different effective times.
- **When the export happened** is one instant for the whole conversion. It is written to `Observation.issued`, `Provenance.recorded`, and `Bundle.timestamp`, and describes the act of converting, not the act of measuring.

Sharing one instant across the batch is deliberate: one export is one provenance event.
`conversionInstant` defaults to the wall clock; pass a fixed value to make a conversion byte-for-byte reproducible in tests.

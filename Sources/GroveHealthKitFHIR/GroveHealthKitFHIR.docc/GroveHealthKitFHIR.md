# ``GroveHealthKitFHIR``

<!--
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
-->

Convert already-fetched HealthKit records into auditable HL7 FHIR R4 exchange graphs.

## Overview

``HealthKitConverter`` is a closed, profile-aware adapter for the published Grove FHIR implementation guides.
It consumes an `HKSample`; it does not request HealthKit authorization, query samples, manage anchors, store FHIR, or upload data.

### Convert a sample

```swift
import GroveHealthKitFHIR
import HealthKit
import ModelsR4

let sample: HKQuantitySample = // a sample already fetched from HealthKit
let conversion = try HealthKitConverter().convert(sample, for: Reference(reference: "Patient/example"))
upload(conversion.bundle)
```

Only the subject has no local answer — nothing on the device knows who the receiving system thinks the data is about.
The converting application's identity and the identifier namespace for derived resources are read from the app's own bundle, and the conversion instant defaults to the wall clock.

Pass a ``HealthKitConversionContext`` to set a study reference, a disclosure policy, a server-owned identifier namespace, or a fixed instant:

```swift
let context = HealthKitConversionContext(
    subject: Reference(reference: "Patient/example"),
    graphIdentifierSystem: "https://study.example.org/fhir/identifiers/mobile-graph"
)
let conversion = try HealthKitConverter().convert(sample, context: context)
```

<doc:ConfiguringAConversion> explains what each input means, including the FHIR background behind the subject reference and the identifier namespace.

One successful conversion returns a ``HealthKitConversion`` containing the normalized `Observation`, recording and application `Device` resources when applicable, conversion `Provenance`, and a FHIR `Bundle` of type `collection`.
<doc:TheConversionGraph> shows each of these resources as emitted JSON and explains why a measurement travels with a device and an audit record.
Internal references use deterministic `urn:uuid` full URLs derived from complete business identifiers.
Source UUIDs are business identifiers — not `Resource.id` values; a logical id is emitted only when a caller supplies a repository-assigned `RepositoryID`.

### Convert a batch

Batch conversion never silently drops unsupported or invalid records:

```swift
let result = HealthKitConverter().convert(samples, context: context)
for conversion in result.conversions {
    send(conversion.bundle)
}
for failure in result.failures {
    record(failure.sourceUUID, failure.reason)
}
```

### Convert an ECG

ECG conversion uses the dedicated ``HealthKitECGRecord`` input, so the caller supplies the already-enumerated voltage measurements and any already-queried correlated symptoms.
When an ECG reports symptoms, supply every associated `HKCategorySample` and select ``HealthKitSourceDisclosurePolicy/authorized``; the emitted evidence retains linkable `HKSourceRevision` fields, so the privacy gate is explicit.
Without authorization, conversion fails closed; required evidence is never silently omitted.

### What converts, and what fails closed

Every admitted Observation claims exactly the profile set published for its source type.
Most measurements claim a shared Mobile profile plus the HealthKit adapter profile; BMI claims the authoritative R4 BMI profile plus the adapter profile.
Values, UCUM units, effective datatype, codes, devices, provenance, time zone, and the small metadata allowlist are normalized rather than copied through an open mapping dictionary.
The exact HealthKit source-type coding is retained after the primary normative coding.

``HealthKitCatalog/entries`` is the complete machine-consumable matrix generated from the frozen adapter catalog: every HealthKit sample type known to Grove, its status, candidate measurement profiles, and any unmet requirement.
The converter fails closed when a row is not `supported`; no legacy canonical, provider sample-type code, or best-effort Observation is emitted.

Every measurement HealthKit can express has a representation, including the ones where the platform withholds a clinical detail.
Blood glucose is the worked example: FHIR distinguishes whole-blood, capillary, serum/plasma, and interstitial glucose, and a consumer meter or CGM reaching HealthKit does not say which it sampled.
Rather than guess a specimen or refuse the reading, Grove publishes a distinct *unspecified specimen* measurement, so the value is exchanged completely and honestly, and a consumer can tell it apart from a specimen-qualified laboratory result.
A source that does know its specimen — a Health Connect record, for example — selects the specimen-qualified profile instead.

The rows that remain unconverted are the ones with nothing to convert: platform identifiers that are not samples, and records Grove passes through rather than reinterprets.

### Explicit provenance and identity

Literal Patient and ResearchStudy references must be exact relative FHIR references or HTTP(S) URLs ending at the typed resource id; query, fragment, history, trailing, and extra path components fail closed.
Identifier-only references require a complete system and value plus the exact resource type; duplicate ResearchStudy references are rejected.

Every conversion `Provenance` directly claims only the HealthKit conversion-provenance profile, targets the emitted Observation, and carries the exact HealthKit object identifier as its sole source entity.
The writing source is always recorded: an `HKSource` carries a bundle identifier and is an application, so the adapter states that rather than guessing at hardware from a name or identifier shape.
Hardware attribution is a separate question answered by `HKDevice`, carried as the recording device.
A local `HKDevice.localIdentifier` is disclosed only with an explicit deployment-owned namespace, and a UDI is omitted unless the caller selects ``HealthKitUDIDisclosurePolicy/authorizedUDI`` after establishing necessity and authorization.

HealthKit's object UUID becomes the Observation's complete business identifier using the published HealthKit NamingSystem.
The exchange Bundle and derived graph nodes use the caller's namespace.
`ExchangeIdentity` implements the frozen RFC 8785/JCS plus UUIDv5 algorithm used by every Grove producer.

## Topics

### Essentials

- <doc:ConfiguringAConversion>
- <doc:TheConversionGraph>

### Conversion

- ``HealthKitConverter``
- ``HealthKitConversionContext``
- ``HealthKitApplication``
- ``HealthKitUDIDisclosurePolicy``
- ``HealthKitSourceDisclosurePolicy``
- ``HealthKitECGRecord``
- ``HealthKitConversion``
- ``HealthKitBatchResult``
- ``HealthKitRecordFailure``

### Coverage and identity

- ``HealthKitCatalog``
- ``HealthKitCatalogEntry``

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

``HealthKitFHIRConverter`` is a closed, profile-aware adapter for the published Grove FHIR implementation guides.
It consumes an `HKSample`; it does not request HealthKit authorization, query samples, manage anchors, store FHIR, or upload data.

### Convert a sample

```swift
import GroveHealthKitFHIR
import HealthKit
import ModelsR4

let sample: HKQuantitySample = // a sample already fetched from HealthKit
let context = HealthKitFHIRConversionContext(
    subject: Reference(reference: "Patient/example"),
    converter: .main,
    graphIdentifierSystem: "https://study.example.org/fhir/identifiers/mobile-graph"
)

let conversion = try HealthKitFHIRConverter().convert(sample, context: context)
upload(conversion.bundle)
```

Three inputs cannot be derived and identify every conversion:

- `subject`: who the data is about, as the receiving system knows them.
- `converter`: the identity of the converting application; ``HealthKitFHIRApplication/main`` reads it from the app's own bundle.
- `graphIdentifierSystem`: a deployment-owned identifier namespace for the graph nodes that exist only because of this export — the Bundle, the conversion `Provenance`, and derived `Device` resources.
  Identifiers are minted deterministically inside it, so converting the same sample twice yields the same graph and re-sends deduplicate on the server.

Each sample's measurement time comes from the sample itself and lands in `Observation.effective`.
The context's ``HealthKitFHIRConversionContext/conversionInstant`` stamps the export event (`Observation.issued`, `Provenance`, `Bundle.timestamp`) and defaults to the wall clock.

One successful conversion returns a ``HealthKitFHIRConversion`` containing the normalized `Observation`, recording and application `Device` resources when applicable, conversion `Provenance`, and a FHIR `Bundle` of type `collection`.
Internal references use deterministic `urn:uuid` full URLs derived from complete business identifiers.
Source UUIDs are business identifiers — not `Resource.id` values; a logical id is emitted only when a caller supplies a repository-assigned `GroveFHIRRepositoryID`.

### Convert a batch

Batch conversion never silently drops unsupported or invalid records:

```swift
let result = HealthKitFHIRConverter().convert(samples, context: context)
for conversion in result.conversions {
    send(conversion.bundle)
}
for failure in result.failures {
    record(failure.sourceUUID, failure.reason)
}
```

### Convert an ECG

ECG conversion uses the dedicated ``HealthKitECGRecord`` input, so the caller supplies the already-enumerated voltage measurements and any already-queried correlated symptoms.
When an ECG reports symptoms, supply every associated `HKCategorySample` and select ``HealthKitFHIRSourceDisclosurePolicy/authorized``; the emitted evidence retains linkable `HKSourceRevision` fields, so the privacy gate is explicit.
Without authorization, conversion fails closed; required evidence is never silently omitted.

### What converts, and what fails closed

Every admitted Observation claims exactly the profile set published for its source type.
Most measurements claim a shared Mobile profile plus the HealthKit adapter profile; BMI claims the authoritative R4 BMI profile plus the adapter profile.
Values, UCUM units, effective datatype, codes, devices, provenance, time zone, and the small metadata allowlist are normalized rather than copied through an open mapping dictionary.
The exact HealthKit source-type coding is retained after the primary normative coding.

``HealthKitFHIRCatalog/entries`` is the complete machine-consumable matrix generated from the frozen adapter catalog: every HealthKit sample type known to Grove, its status, candidate measurement profiles, and any unmet requirement.
The converter fails closed when a row is not `supported`; no legacy canonical, provider sample-type code, or best-effort Observation is emitted.
Deferred rows state their reason — blood glucose, for example, defers because HealthKit does not state the specimen needed to select whole-blood, capillary, serum/plasma, or interstitial glucose.

### Explicit provenance and identity

Literal Patient and ResearchStudy references must be exact relative FHIR references or HTTP(S) URLs ending at the typed resource id; query, fragment, history, trailing, and extra path components fail closed.
Identifier-only references require a complete system and value plus the exact resource type; duplicate ResearchStudy references are rejected.

Every conversion `Provenance` directly claims only the HealthKit conversion-provenance profile, targets the emitted Observation, and carries the exact HealthKit object identifier as its sole source entity.
Source application/device attribution is omitted unless the caller explicitly classifies `HKSourceRevision`; the adapter never guesses from names or identifier shapes.
A local `HKDevice.localIdentifier` is disclosed only with an explicit deployment-owned namespace, and a UDI is omitted unless the caller selects ``HealthKitFHIRUDIDisclosurePolicy/authorizedUDI`` after establishing necessity and authorization.

HealthKit's object UUID becomes the Observation's complete business identifier using the published HealthKit NamingSystem.
The exchange Bundle and derived graph nodes use the caller's namespace.
`GroveFHIRExchangeIdentity` implements the frozen RFC 8785/JCS plus UUIDv5 algorithm used by every Grove producer.

## Topics

### Conversion

- ``HealthKitFHIRConverter``
- ``HealthKitFHIRConversionContext``
- ``HealthKitFHIRApplication``
- ``HealthKitFHIRUDIDisclosurePolicy``
- ``HealthKitFHIRSourceDisclosurePolicy``
- ``HealthKitECGRecord``
- ``HealthKitFHIRConversion``
- ``HealthKitFHIRBatchResult``
- ``HealthKitFHIRRecordFailure``

### Coverage and identity

- ``HealthKitFHIRCatalog``
- ``HealthKitFHIRCatalogEntry``
- ``HealthKitFHIRImplementationStatus``

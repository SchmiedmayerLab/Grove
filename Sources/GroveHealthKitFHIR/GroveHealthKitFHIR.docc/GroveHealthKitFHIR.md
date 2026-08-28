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

``HealthKitConverter`` is a closed, profile-aware adapter for the published Grove FHIR
implementation guides. It consumes an `HKSample`; it does not request HealthKit authorization,
query samples, manage anchors, store FHIR, or upload data.

### Convert a sample

```swift
import GroveHealthKitFHIR
import HealthKit

let sample: HKQuantitySample = // a sample already fetched from HealthKit
let conversion = try HealthKitConverter().convert(sample, context: persistedEventContext)
upload(conversion.bundle)
```

The converter accepts no implicit identity or clock inputs. The caller supplies one complete
``HealthKitConversionContext`` for each immutable source record/version, persists it before upload,
and reuses it unchanged for an exact retry.

Subjects and studies are identifier-only logical references because their resources are not included
in the closed exchange Bundle:

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

<doc:ConfiguringAConversion> explains the persisted event identifier, logical references, HMAC key
epoch, deployment-owned systems, repository scope, device snapshots, and disclosure policies.

One successful conversion returns a ``HealthKitConversion`` containing the normalized
`Observation`, recording and application `Device` resources when applicable, conversion
`Provenance`, and an R4 `collection` Bundle. Send ``HealthKitConversion/bundle``; the other
properties are available for inspection and tests.

### Convert a batch

A batch supplies a distinct event context for each source record. It never silently drops an
unsupported or invalid record:

```swift
let result = HealthKitConverter().convert(samples) { sample in
    try persistedContext(for: sample)
}
for conversion in result.conversions {
    send(conversion.bundle)
}
for failure in result.failures {
    record(failure.sourceUUID, failure.reason)
}
```

### Convert an ECG

ECG conversion uses the dedicated ``HealthKitECGRecord`` input, so the caller supplies the complete,
already-enumerated voltage measurements and every correlated symptom. A context provider gives each
`HKCategorySample` its own event context. The returned ``HealthKitConversionSet`` contains each
symptom's normal profiled conversion, while the ECG carries only identifier-based `hasMember`
relationships to those separately exchangeable outputs.

### What converts, and what fails closed

Every admitted Observation claims exactly the profile set published for its source type. Values,
UCUM units, effective datatype, codes, devices, provenance, time zone, and allowlisted typed metadata are
normalized through generated catalog contracts. Numeric values must be finite and obey each
measurement's inclusive bounds and integer-only rule; zero remains valid when the catalog admits it.

``HealthKitCatalog/entries`` is the complete generated matrix: every known HealthKit sample type,
its status, candidate profiles, and any unmet requirement. The converter rejects rows that are not
`supported`; it does not emit a legacy canonical or best-effort Observation.

Blood glucose illustrates the policy. HealthKit may not disclose whether a value came from whole
blood, capillary blood, serum/plasma, or interstitial fluid. Grove uses its explicit unspecified-
specimen measurement rather than guessing a specimen or discarding the reading.

### Explicit provenance, references, and identity

Patient and ResearchStudy references must carry exactly one complete identifier, the exact resource
type token, and no literal reference. A literal would dangle because the converter does not emit
those caller-owned resources. Mixed, untyped, incomplete, and duplicate study references fail
closed.

Every conversion `Provenance` claims the HealthKit conversion-provenance profile, targets every
output for its one source record/version, and carries the typed pseudonymous `source-record`
identifier as its source entity. Its lifecycle activity contains exactly one ISO transform coding.
The writing application and its host are separate event-time Device snapshots. `HKDevice` answers
the distinct hardware-attribution question.

The HealthKit object UUID is never disclosed in a global Grove NamingSystem. Deployment-owned,
key-epoch-specific HMAC identifiers separate source record, output, writer, artifact, source context,
and device roles. Every output carries both `source-record` and exact `source-output` identifiers;
recording documents additionally carry `source-artifact`.

Internal references use deterministic `urn:uuid` full URLs derived with UUIDv5 from the selected
typed identifier's exact system/value pair. A logical id is emitted only when a caller supplies a
repository-assigned ``RepositoryID``.

## Topics

### Essentials

- <doc:ConfiguringAConversion>
- <doc:TheConversionGraph>

### Conversion

- ``HealthKitConverter``
- ``HealthKitConversionContext``
- ``HealthKitApplication``
- ``HealthKitHostDevice``
- ``HealthKitUDIDisclosurePolicy``
- ``HealthKitECGRecord``
- ``HealthKitConversion``
- ``HealthKitConversionSet``
- ``HealthKitBatchResult``
- ``HealthKitRecordFailure``

### Coverage and identity

- ``HealthKitCatalog``
- ``HealthKitCatalogEntry``
- ``PseudonymousIdentityScope``
- ``ExchangeEventIdentifier``

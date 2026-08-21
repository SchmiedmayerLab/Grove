# ``GroveHealthKitFHIR``

<!--

This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

Convert already-fetched HealthKit records into auditable HL7 FHIR R4 exchange graphs.

## Overview

``HealthKitFHIRConverter`` is a closed, profile-aware adapter for the Grove FHIR 0.2.0
implementation guides. It consumes an `HKSample`; it does not request HealthKit
authorization, query samples, manage anchors, store FHIR, or upload data.
ECG conversion uses the dedicated ``HealthKitECGRecord`` input so the caller supplies the
already-enumerated voltage measurements and any already-queried correlated symptoms.

One successful conversion returns a ``HealthKitFHIRConversion`` containing the normalized
`Observation`, recording and application `Device` resources when applicable, conversion
`Provenance`, and a FHIR `Bundle` of type `collection`. Internal references use deterministic
`urn:uuid` full URLs derived from complete business identifiers. Source UUIDs are business
identifiers—not `Resource.id` values. A logical id is emitted only when a caller supplies a
repository-assigned `GroveFHIRRepositoryID`.

```swift
import GroveHealthKitFHIR
import HealthKit
import ModelsR4

let sample: HKQuantitySample = // a sample already fetched from HealthKit
let now = Date.now
let context = HealthKitFHIRConversionContext(
    subject: Reference(reference: "Patient/example"),
    converter: HealthKitFHIRApplication(
        name: "Example Study",
        bundleIdentifier: "org.grovealliance.example-study",
        version: "2.0.0 (42)"
    ),
    graphIdentifierSystem: "https://study.example.org/fhir/identifiers/mobile-graph",
    issuedAt: now,
    recordedAt: now
)

let conversion = try HealthKitFHIRConverter().convert(sample, context: context)
let bundle = conversion.bundle
```

Every admitted Observation claims exactly the profile set published for its source type. Most
measurements claim a shared Mobile profile plus the HealthKit adapter profile; BMI claims the
authoritative R4 BMI profile plus the adapter profile. Profiles that build on an authoritative
standard inherit that constraint through the shared profile. Values, UCUM units, effective
datatype, codes, devices, provenance, time zone, and the small metadata allowlist are normalized
rather than copied through an open mapping dictionary. The exact HealthKit source-type coding is
retained after the primary normative coding.

### Implementation matrix

| HealthKit input | v0.2 Swift status | FHIR result |
|---|---|---|
| Active energy burned | Supported | Grove Mobile Active Energy |
| Basal body temperature | Supported | Grove Mobile Basal Body Temperature |
| Blood pressure correlation | Supported | Grove Mobile Blood Pressure with systolic and diastolic components |
| Body height, body temperature, body weight | Supported | Corresponding standards-backed Grove Mobile profiles |
| BMI | Supported | Authoritative R4 BMI profile plus the HealthKit adapter profile |
| Walking/running, cycling, swimming, wheelchair, and other admitted distance quantities | Supported | Grove Mobile Distance |
| Heart rate, oxygen saturation, respiratory rate | Supported | Corresponding standards-backed Grove Mobile profiles |
| Sleep analysis interval | Supported | Grove Mobile Sleep Stage; shared Grove coding precedes the exact HealthKit sleep-analysis coding |
| Step count interval | Supported | Grove Mobile Step Count |
| Blood glucose quantity | Deferred, fails closed | HealthKit does not state the specimen needed to select whole-blood, capillary, serum/plasma, or interstitial glucose |
| Sleep-duration session aggregate | Deferred | Requires an explicit aggregation of stage intervals; it is not a direct sample mapping |
| Electrocardiogram | Supported through the dedicated evidence API | Sensor ECG plus HealthKit ECG; exact classification, symptom status and evidence, source period, count, optional rate/frequency/algorithm, and complete uniform Lead-I waveform |
| Every other known quantity, category, correlation, clinical record, and other `HKSample` shape | No published contract | No v0.2 conformance claim is made; provider FHIR in clinical records is not rewritten or re-profiled |

``HealthKitFHIRCatalog/entries`` is the complete, machine-consumable matrix for the current
SDK (209 rows in the 0.2 conformance inventory). It includes every HealthKit sample type
known to Grove, its status, applicable candidate measurement profiles, and any unmet
requirement. The converter fails closed when a row is not
`supported`; no legacy canonical, provider sample-type code, or best-effort Observation is
emitted.

### Explicit provenance and identity

The caller supplies the Patient reference, converter application identity, a deployment-owned
graph identifier namespace, and conversion times. Literal Patient and ResearchStudy references
must be exact relative FHIR references or HTTP(S) URLs ending at the typed resource id; query,
fragment, history, trailing, and extra path components fail closed. Identifier-only references
require a complete system and value plus the exact resource type. Duplicate ResearchStudy
references are rejected.

Every conversion `Provenance` directly claims only the HealthKit conversion-provenance profile,
targets the emitted HealthKit Observation, and carries the exact HealthKit object identifier as
its sole source entity.

Source application/device attribution is omitted unless the caller explicitly classifies
`HKSourceRevision`; the adapter never guesses from names or identifier shapes. A local
`HKDevice.localIdentifier` is disclosed only with an explicit deployment-owned namespace. A
UDI is omitted by default and is independent from that local namespace; the caller must select
``HealthKitFHIRUDIDisclosurePolicy/authorizedUDI`` only after establishing both
necessity and authorization. Model, manufacturer, and typed software/hardware/firmware versions
are preserved when HealthKit supplies them.

When an ECG reports symptoms, the caller must supply every associated `HKCategorySample` and
select ``HealthKitFHIRSourceDisclosurePolicy/authorized``. Each emitted symptom retains its
UUID, period, type, severity, and complete `HKSourceRevision`, including source name, bundle
identifier, optional source/product versions, and operating-system version. These fields are
linkable, so the privacy gate is independent of UDI and local-device identifier authorization.
Without authorization, conversion fails closed; required evidence is never silently omitted.

HealthKit's object UUID becomes the Observation's complete business identifier using the
published HealthKit NamingSystem. The exchange Bundle and derived graph nodes use the caller's
namespace. `GroveFHIRExchangeIdentity` implements the frozen RFC 8785/JCS plus UUIDv5
algorithm used by every Grove producer.

### Batch conversion

Batch conversion does not silently drop unsupported or invalid records:

```swift
let samples: [HKSample] = // already fetched
let result = HealthKitFHIRConverter().convert(samples, context: context)

for conversion in result.conversions {
    send(conversion.bundle)
}
for failure in result.failures {
    record(failure.sourceUUID, failure.reason)
}
```

## Topics

### Conversion

- ``HealthKitFHIRConverter``
- ``HealthKitFHIRConversionContext``
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

# ``GroveHealthKitFHIR``

<!--

This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

Adds FHIR integrations and compatibility to HealthKit.


## Overview

You use the GroveHealthKitFHIR module to convert HealthKit samples into FHIR R4 resources.

```swift
let sample: HKQuantitySample = // ... a heart rate sample fetched from HealthKit
let subject = Reference(reference: "Patient/example".asFHIRStringPrimitive())
let resource = try sample.resource(subject: subject)
```

The profile pins `subject`, so pass the participant reference: an observation of nobody
does not conform, whatever else it carries.

This resource is an `Observation` shaped by the Grove FHIR core implementation guide:
the LOINC code and UCUM
value on the resource itself, the recording watch and the saving app as contained
`Device`s (`Observation.device` and the HL7 `observation-gatewayDevice` extension), the
HealthKit record id in `Observation.identifier`, timing in `effective[x]` with an IANA
`timezone` extension, and whatever platform metadata has no better home in repeating
`grove-platform-metadata` entries. `meta.profile` names the profile the observation
claims.

The guide carries worked examples of every resource this module produces; they are
validated on each publish, so they cannot drift from the profiles the way a snippet
pasted here would.



GroveHealthKitFHIR supports:
- Extensions to convert data from Apple HealthKit to HL7® FHIR® R4.
- Customizable mappings between HealthKit data types and standardized codes (e.g., LOINC)

## HealthKit Extensions

The GroveHealthKitFHIR module provides extensions that convert supported HealthKit samples to FHIR resources using [FHIRModels](https://github.com/apple/FHIRModels) encapsulated in a [ResourceProxy](https://github.com/apple/FHIRModels/blob/main/HowTo/Instantiation.md#1-use-resourceproxy).

```swift
let sample: HKSample = // ...
let resource = try sample.resource(subject: subject)
```

### Observations

`HKQuantitySample`, `HKCategorySample`, `HKCorrelationSample`, and `HKElectrocardiogram` will be converted into FHIR [Observation](https://hl7.org/fhir/R4/observation.html) resources encapsulated in a [ResourceProxy](https://github.com/apple/FHIRModels/blob/main/HowTo/Instantiation.md#1-use-resourceproxy).

```swift
let sample: HKQuantitySample = // ...
let observation = try sample.resource(subject: subject).get(if: Observation.self)
```

Codes and units can be customized by passing in a custom `SampleTypesFHIRMapping` instance to the `resource(withMapping:)` method.

```swift
let sample: HKQuantitySample = // ...
let sampleMapping: SampleTypesFHIRMapping = // ...
let observation = try sample.resource(withMapping: sampleMapping, subject: subject).get(if: Observation.self)
```

### Clinical Records

`HKClinicalRecord` will be converted to FHIR resources based on the type of its underlying data. Only records encoded in FHIR R4 are supported at this time.

```swift
let allergyRecord: HKClinicalRecord = // ...
let allergyIntolerance = try allergyRecord.resource().get(if: AllergyIntolerance.self)
```

## Example

In the following example, we will query the HealthKit store for step count data, convert the resulting samples to FHIR observations, and encode them into JSON.

```swift
import GroveHealthKitFHIR

// Initialize an HKHealthStore instance and request permissions with it
// ...

let date = ISO8601DateFormatter().date(from: "1885-11-11T00:00:00-08:00") ?? .now
let sample = HKQuantitySample(
    type: HKQuantityType(.heartRate),
    quantity: HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: 42.0),
    start: date,
    end: date
)

// Convert the results to FHIR observations
let subject = Reference(reference: "Patient/example".asFHIRStringPrimitive())
let observation: Observation?
do {
    try observation = sample.resource(subject: subject).get(if: Observation.self)
} catch {
    // Handle any mapping errors here.
    // ...
}

// Encode FHIR observations as JSON
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]

guard let observation, 
      let data = try? encoder.encode(observation) else {
    // Handle any encoding errors here.
    // ...
}

// Print the resulting JSON
let json = String(decoding: data, as: UTF8.self)
print(json)
```

The guide includes a heart-rate example that is validated on every publish, so it stays
in step with the profiles.

## Topics

### Mapping HealthKit Samples into FHIR Observations
- ``HealthKit/HKSample/resource(withMapping:issuedDate:subject:extensions:)``
- ``HealthKit/HKSampleType/fhirResourceType``
- ``HealthKit/HKElectrocardiogram/observation(subject:symptoms:voltageMeasurements:withMapping:issuedDate:extensions:)``

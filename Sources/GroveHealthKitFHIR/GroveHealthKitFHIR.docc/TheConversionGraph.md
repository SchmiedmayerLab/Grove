# The Conversion Graph

<!--
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
-->

Read the resources one conversion emits and understand why a measurement arrives with a `Device` and a `Provenance` beside it.

## Overview

Converting one `HKSample` does not produce one resource.
It produces a small graph: the measurement itself, the hardware that recorded it, the application that converted it, and a record of the conversion.

```swift
let conversion = try HealthKitConverter().convert(sample, for: patient)
conversion.observation   // the measurement
conversion.bundle        // the whole graph, ready to send
```

Send ``HealthKitConversion/bundle``. The other properties are there for inspection and testing.

## The measurement

The `Observation` carries the value, the code that says what was measured, and `effective`, the time the measurement covers.
It claims two profiles: the source-neutral Grove Mobile profile for the measurement and the HealthKit adapter profile, so a consumer can validate it either as a plain heart rate or as HealthKit-sourced data.

## The devices

Two different things get modelled as a `Device`, and they answer different questions.

The **recording device** is the hardware that produced the reading, taken from `HKSample.device`. Only non-identifying descriptive fields are copied; a serial number or UDI is never disclosed unless you explicitly opt in.

```json
{
  "resourceType": "Device",
  "meta": { "profile": ["https://grovealliance.org/fhir/mobile/StructureDefinition/grove-recording-device"] },
  "manufacturer": "Apple Inc.",
  "modelNumber": "Watch7,12",
  "deviceName": [{ "name": "Apple Watch", "type": "user-friendly-name" }]
}
```

The **application device** is your app — the software that read the sample out of HealthKit and converted it. Its identity comes from ``HealthKitApplication``.

```json
{
  "resourceType": "Device",
  "meta": { "profile": ["https://grovealliance.org/fhir/mobile/StructureDefinition/grove-application-device"] },
  "identifier": [{
    "system": "https://grovealliance.org/fhir/healthkit/NamingSystem/apple-bundle-id",
    "value": "org.example.study"
  }],
  "deviceName": [{ "name": "Example Study", "type": "user-friendly-name" }]
}
```

Both matter downstream: a reviewer asking "should I trust this number?" needs to know it came from a wrist-worn optical sensor rather than manual entry, and which build of which app transcribed it.

## The provenance

`Provenance` is FHIR's audit record. It answers *where did this resource come from, who produced it, and when* — and it is a separate resource so the answer survives even when the `Observation` is copied into another system.

Grove emits exactly one conversion `Provenance` per source record. It states three things:

- **activity** — `transform`, because nothing was measured here; an existing record was translated into FHIR.
- **agent** — the application device, as the `assembler` that performed the transformation.
- **entity** — the original HealthKit object, referenced by its UUID with `role: "source"`, so the output can always be traced back to the exact input.

```json
{
  "resourceType": "Provenance",
  "activity": {
    "coding": [{
      "system": "http://terminology.hl7.org/CodeSystem/iso-21089-lifecycle",
      "code": "transform",
      "display": "Transform/Translate Record Lifecycle Event"
    }]
  },
  "agent": [{
    "type": { "coding": [{
      "system": "http://terminology.hl7.org/CodeSystem/provenance-participant-type",
      "code": "assembler",
      "display": "Assembler"
    }] },
    "who": { "reference": "urn:uuid:b5f21171-75a7-5d01-ae9e-2097673a21c4" }
  }],
  "entity": [{
    "role": "source",
    "what": { "identifier": {
      "system": "https://grovealliance.org/fhir/healthkit/NamingSystem/healthkit-object-id",
      "value": "0cccc537-ffe2-472f-9fb2-260add5ba526"
    } }
  }]
}
```

`recorded` on this resource is the conversion instant, not the measurement time. See <doc:ConfiguringAConversion>.

## How the graph is wired

Inside the `Bundle`, resources reference each other by `urn:uuid:` full URLs rather than server ids, because none of these resources has been assigned a server id yet.
Those UUIDs are derived deterministically from the business identifiers, so the same input always produces the same graph and a re-send deduplicates instead of creating copies.

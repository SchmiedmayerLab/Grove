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

Understand the resources, immutable identities, and references emitted for one source record/version.

## Overview

Converting one `HKSample` produces a closed graph: the primary clinical output, any mandatory child
outputs or source artifact, immutable Device snapshots, and the Provenance assertion for that event.

```swift
let conversion = try HealthKitConverter().convert(sample, context: persistedEventContext)
conversion.observation   // the primary normalized measurement
conversion.bundle        // the complete graph to send
```

The active Bundle claims
`https://grovealliance.org/fhir/mobile/StructureDefinition/grove-mobile-exchange-bundle`, carries a
typed event identifier, and contains exactly one source record/version. It is an R4 `collection`, not
a transaction or delete command.

The entry type set is closed. Outputs are `Observation`, `DocumentReference`, `Specimen`,
`VisionPrescription`, `MedicationAdministration`, or `MedicationStatement`; supporting nodes are
`Patient`, `Device`, `ResearchStudy`, `ResearchSubject`, `PlanDefinition`, or
`QuestionnaireResponse`; and the only lifecycle node is `Provenance`. Every supporting entry must be
connected to an output or that lifecycle assertion.

## The clinical output

An `Observation` carries the normalized value, coding, and effective time required by the selected
catalog row. It claims the source-neutral Grove profile and the HealthKit adapter profile where both
apply. Quantity units are exact UCUM codes. The converter rejects nonfinite, out-of-domain, or
fractional integer-only values instead of relying on a later server validator.

Every output has both typed pseudonymous identifiers:

- `source-record` links all outputs from the same immutable source input.
- `source-output` identifies the exact output role and discriminator used by a retraction target.

A document-style native or clinical pass-through additionally has exactly one attachment and one
typed `source-artifact` identifier. Attachment size and FHIR R4's base64 SHA-1 `Attachment.hash`
cover the actual pre-base64 bytes. That hash is change detection, not a signature or authorization
credential; a future stronger integrity mechanism must use a separately defined manifest element.

HealthKit clinical records are admitted only when `HKFHIRVersion.fhirRelease` explicitly reports
R4. The provider-issued bytes are then carried unchanged and the document receives the catalog's
fixed `r4` release extension. DSTU2, missing, unknown, and future releases fail before Grove creates
a `DocumentReference`; their JSON is never relabeled or inferred to be R4.

## The devices

The recording hardware, conversion application, and host are separate Device resources because they
answer different provenance questions. Each is an immutable event-time snapshot; an application
links to its host through `Device.parent`.

A HealthKit application Device claims the HealthKit application profile and carries exactly two
identifiers: the opaque event-scoped `device-snapshot`, plus the clear Apple product bundle
identifier typed as `healthkit-identifier-type#apple-bundle-id`. That clear value identifies an
application product, never an installation, host, account, or person. The converter always uses this
shape; an `HKSourceRevision` author uses it only when the caller explicitly classifies the source as
an application.

A recording Device carries two identities. `recording-device` is the stable HMAC identity for the
physical unit when the caller has a stable local token. `device-snapshot` identifies the exact
event-time representation and is the selected Bundle node/fullUrl key. Historical events never
mutate one shared Device resource.

Only the catalogued descriptive fields are copied. A serial number or UDI remains omitted unless the
caller selects the explicit authorized disclosure policy.

## The provenance

The conversion `Provenance` is an assertion about how this graph came to exist. Its lifecycle
activity contains exactly one ISO 21089 `transform` coding and no Grove retraction lifecycle coding.
Its direct `meta.profile` claim contains exactly the one admitted HealthKit conversion profile; it
does not repeat a generic conversion profile alongside it.
It records:

- every emitted output as a target;
- the converter application as the assembler and its host relationship;
- the typed `source-record` identifier as the source entity;
- the event conversion instant in `occurred` and `recorded`.

The source HealthKit UUID, writer record, source-revision context, and device tokens are framed HMAC
inputs. They are not emitted through clear, global Grove NamingSystems.

## How the graph is wired

Every literal internal Reference resolves exactly once to a Bundle `fullUrl`. If
`Reference.type` is present it must exactly match the target resource type. Governed paths are
narrower: for example, an Observation device resolves to Device and a research-study extension is a
complete identifier-only logical Reference to ResearchStudy. Mixed literal-and-logical references,
untyped logical references, dangling references, and wrong target types fail closed.

Contained resources and `#fragment` references are prohibited. Every graph node is an addressable
Bundle entry with a deterministic fullUrl, so no hidden contained node can bypass entry identity,
profile, connection, or retraction rules.

Internal nodes use deterministic `urn:uuid` full URLs. UUIDv5 input is the unsigned length-framed
UTF-8 pair `[identifier.system, identifier.value]` for the selected typed identity. Nodes without a
separate business identity use a typed event node key. An exact retry therefore rebuilds identical
references, while a new event version cannot collide with an earlier snapshot.

## Retractions

A retraction is a new assertion Bundle with its own persisted event identifier. Its Provenance uses
exactly one Grove `source-record-retracted` lifecycle coding and targets typed logical identifiers
from an earlier active event. It is not an HTTP delete instruction.

The target role closes both identity and resource type: `primary-output`, `child-output`, `specimen`,
and `source-artifact` target a `source-output` identifier with the role's admitted resource type;
`device-snapshot` targets a Device's `device-snapshot` identifier. A recording document's
`source-artifact` role therefore selects the document's exact source-output entry key, not its
attachment identifier.

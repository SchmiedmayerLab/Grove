# The Exchange Graph

<!--
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
-->

Understand the resources, immutable identities, and references exported for one source record/version.

## Overview

Exporting one `HKSample` produces a closed graph: the primary clinical output, any mandatory child outputs or source artifact, immutable Device snapshots, the bundled study context when an enrollment is known, and the Provenance assertion for that event.

```swift
let receipt = try exporter.export([sample]) { export in
    guard let graph = export.graph else {
        return // Refused: export.outcome names the reason.
    }
    // `graph.eventIdentifier` is the event the graph asserts, and `graph.bundle` the graph as ModelsR4 resources.
    try stage(graph.json)   // the validated bytes, stored and sent verbatim
}
```

The active Bundle claims `https://grovealliance.org/fhir/mobile/StructureDefinition/grove-mobile-exchange-bundle`, carries a typed event identifier, and contains exactly one source record/version.
It is an R4 `collection`, not a transaction or delete command.

The entry type set is closed.
Outputs are `Observation`, `DocumentReference`, `Specimen`, `VisionPrescription`, `MedicationAdministration`, or `MedicationStatement`; supporting nodes are `Patient`, `Device`, `ResearchStudy`, `ResearchSubject`, `PlanDefinition`, or `QuestionnaireResponse`; and the only lifecycle node is `Provenance`.
Every supporting entry must be connected to an output or that lifecycle assertion.

## The clinical output

An `Observation` carries the normalized value, coding, and effective time required by the selected catalog row.
It claims the source-neutral Grove profile and the HealthKit adapter profile where both apply.
Quantity units are exact UCUM codes.
The exporter refuses nonfinite, out-of-domain, or fractional integer-only values instead of relying on a later server validator.

Every output has both typed opaque identifiers:

- `source-record` links all outputs from the same immutable source input.
- `source-output` identifies the exact output role and discriminator used by a retraction target.

A document-style native or clinical pass-through additionally has exactly one attachment and one typed `source-artifact` identifier.
Attachment size and FHIR R4's base64 SHA-1 `Attachment.hash` cover the actual pre-base64 bytes.
That hash is change detection, not a signature or authorization credential; a future stronger integrity mechanism must use a separately defined manifest element.

HealthKit clinical records are admitted only when `HKFHIRVersion.fhirRelease` explicitly reports `dstu2` or `r4`.
The provider-issued bytes are carried unchanged under the release-neutral `fhir-resource` format.
The R4 DocumentReference attachment declares the matching FHIR JSON media type: `application/fhir+json; fhirVersion=1.0` for DSTU2 or `application/fhir+json; fhirVersion=4.0` for R4.
Grove never converts DSTU2 to R4 or claims conformance over the payload.
Missing, unknown, and future releases fail before Grove creates a DocumentReference.

## The devices

The recording hardware, converting application, and host are separate Device resources because they answer different provenance questions.
Each is an immutable event-time snapshot; an application links to its host through `Device.parent`.

A HealthKit application Device claims the HealthKit application profile and carries exactly two identifiers: the opaque event-scoped `device-snapshot`, plus the clear Apple product bundle identifier typed as `healthkit-identifier-type#apple-bundle-id`.
That clear value identifies an application product, never an installation, host, account, or person.
The converting application always uses this shape; the writer of an `HKSourceRevision` uses it only when the caller classifies the source as an application through ``HealthKitFHIRExporter/WriterPolicy``.
That writer snapshot and the host it ran on are the graph's `writer` and `writerHost` nodes, and the writer is the author agent of the Provenance's source-record entity.
HealthKit does not say whether a source is an application or a device, so a source the caller has not classified states no writer and the Provenance names no author; Grove never infers the classification from the bundle identifier, the source name or the product type.
A writer snapshot the graph already states, such as the application that runs the exporter, is that one entry rather than a second one.

A recording Device carries two identities.
`recording-device` is the stable HMAC identity for the physical unit ``HealthKitFHIRExporter/RecordingDevicePolicy`` names.
`device-snapshot` identifies the exact event-time representation and is the selected Bundle node/fullUrl key.
Historical events never mutate one shared Device resource.
A device the policy cannot name is omitted rather than merged, and the export reports the `mobile-omission.recording-device` warning.

Only the catalogued descriptive fields are copied.
A serial number or UDI remains omitted unless ``HealthKitFHIRExporter/Options/udi`` is `.authorized`.

## The study context

A `StudyEnrollment` among the producer's studies becomes three entry-node entries: the `ResearchStudy`, the `PlanDefinition` it instantiates at the exact canonical URL and version, and the `ResearchSubject` that enrolls the subject.
Every Observation output references the study through the `workflow-researchStudy` extension.
A recording or clinical document names its studies in `DocumentReference.context.related` instead.
A `Subject.bundled` adds the `Patient` entry under the same entry-node scheme.

## The provenance

The conversion `Provenance` is an assertion about how this graph came to exist.
Its lifecycle activity contains exactly one ISO 21089 `transform` coding and no Grove retraction lifecycle coding.
Its direct `meta.profile` claim contains exactly the one admitted HealthKit conversion profile; it does not repeat a generic conversion profile alongside it.
It records:

- every emitted output as a target;
- the converting application as the assembler and its host relationship;
- the typed `source-record` identifier as the source entity;
- the event's frozen instant in `occurred` and `recorded`.

The source HealthKit UUID, writer record, source-revision context, and device tokens are framed HMAC inputs.
They are not emitted through clear, global Grove NamingSystems.

## How the graph is wired

Every literal internal Reference resolves exactly once to a Bundle `fullUrl`.
If `Reference.type` is present it must exactly match the target resource type.
Governed paths are narrower: an Observation device resolves to Device, and the subject is either one resolving literal or one complete identifier-only logical Reference, never both.
Mixed literal-and-logical references, untyped logical references, dangling references, and wrong target types fail closed.

Contained resources and `#fragment` references are prohibited.
Every graph node is an addressable Bundle entry with a deterministic fullUrl, so no hidden contained node can bypass entry identity, profile, connection, or retraction rules.

Internal nodes use deterministic `urn:uuid` full URLs.
UUIDv5 input is the unsigned length-framed UTF-8 pair `[identifier.system, identifier.value]` for the selected typed identity.
Nodes without a separate business identity use a typed entry-node key, whose ordinal is the entry's zero-based position among the entries sharing its role.
An exact retry therefore rebuilds identical references, while a new event version cannot collide with an earlier snapshot.

## Equality and retries

A receiver compares two graphs of the same event over lossless JSON tokens with `ExchangeGraph.isSemanticallyEqual(to:)`.
Member order, whitespace, and string escaping do not matter; a decimal lexeme is compared as text, so `72` and `72.0` are different content.
A retry that is equal under this comparison is the exact retry the exchange protocol admits.

## Retractions

A retraction is a new assertion Bundle with its own event identifier, which ``HealthKitFHIRExporter/retract(_:at:receive:)`` exports for a deleted record.
Its Provenance uses exactly one Grove `source-record-retracted` lifecycle coding and targets typed logical identifiers from an earlier active event.
It is not an HTTP delete instruction.

The target role closes both identity and resource type: `primary-output`, `child-output`, `specimen`, and `source-artifact` target a `source-output` identifier with the role's admitted resource type; `device-snapshot` targets a Device's `device-snapshot` identifier.
A recording document's `source-artifact` role therefore selects the document's exact source-output entry key, not its attachment identifier.
A disclosed native record identifier rides beside the target in the Grove retraction native-identifier extension; it never addresses the target.

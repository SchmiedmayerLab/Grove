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

Understand the resources, immutable identities, and references of one record and of the Bundle that carries it.

## Overview

Exporting one `HKSample` produces one record: the primary clinical output, any mandatory child outputs or source artifact, immutable Device snapshots, the study context when an enrollment is known, and the one conversion Provenance.

```swift
try await exporter.export([sample]) { export in
    guard let record = export.record else {
        return // Refused: export.outcome names the reason.
    }
    // `record.sourceRecord` names the source record, and `record.version` this revision of it.
    try stage(record.json)   // the validated canonical bytes, stored verbatim
}
```

`ExchangeBundlePacker` packs records into one Bundle, the exchange graph, stating each shared node once; a record's `json` is the same form with that one record.
The active Bundle claims `https://grovealliance.org/fhir/mobile/StructureDefinition/grove-mobile-exchange-bundle`, and `Bundle.identifier` is an optional transport id that enters no identity.
It is an R4 `collection`, not a transaction or delete command.

The entry type set is closed.
Outputs are `Observation`, `DocumentReference`, `Specimen`, `VisionPrescription`, `MedicationAdministration`, or `MedicationStatement`; supporting nodes are `Patient`, `Device`, `ResearchStudy`, `ResearchSubject`, `PlanDefinition`, or `QuestionnaireResponse`; and the only lifecycle node is `Provenance`.
Every supporting entry must be connected to an output or a lifecycle assertion.

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
Each is an immutable content snapshot; an application links to its host through `Device.parent`.

A HealthKit application Device claims the HealthKit application profile and carries exactly two identifiers: the opaque `device-snapshot` of its content, plus the clear Apple product bundle identifier typed as `healthkit-identifier-type#apple-bundle-id`.
That clear value identifies an application product, never an installation, host, account, or person.
The converting application always uses this shape; the writer of an `HKSourceRevision` uses it only when the caller classifies the source as an application through ``HealthKitFHIRExporter/WriterPolicy``.
That writer snapshot and the host it ran on are the record's `writer` and `writerHost` nodes, and the writer is the author agent of the Provenance's source-record entity.
HealthKit does not say whether a source is an application or a device, so a source the caller has not classified states no writer and the Provenance names no author; Grove never infers the classification from the bundle identifier, the source name or the product type.
The writer is an application snapshot of its own, stating its name, its bundle identifier and the source revision's `HKSourceRevision.version` as its build, while the converting application's snapshot states its marketing version and build.
So even a sample the running application wrote carries the writer beside the converter as a second application Device; the guide allows either form.
Only snapshots of equal content are one entry: the writer's host is the converter's host entry when they state the same facts.
A source that states no writer carries the five facts of its `HKSourceRevision` on the Provenance's source entity instead, in the `healthkit-source-revision` extension.
A sample the store never held has no revision, so it states neither.

Every non-nil `HKDevice` is a recording Device that `Observation.device` references.
It states every fact HealthKit supplies: `HKDevice.name` as the user-friendly `deviceName`, `manufacturer`, `model` as `modelNumber`, the hardware, firmware and software versions under their MDC codes, `localIdentifier` as a clear identifier of type `device-local-identifier` under the deployment's own system, and the UDI device identifier in `udiCarrier`.
A record with an Observation output also takes the sample's device metadata keys: the serial number, and the UDI production identifier in the Grove extension on `udiCarrier`, come only from their keys, and the device name, manufacturer and UDI device identifier keys fill what `HKDevice` leaves absent.

Every recording Device carries `device-snapshot`, the keyed digest of its complete content, which is the selected Bundle node and fullUrl key.
Equal content is one snapshot, and a snapshot proves no physical unit.
`recording-device` is the stable HMAC identity of the unit, present only when ``HealthKitFHIRExporter/UnitTokenPolicy`` picks a token.
Historical records never mutate one shared Device resource.

## The study context

A `StudyEnrollment` among the producer's studies becomes three `context-snapshot` nodes, each keyed by its content: the `ResearchStudy`, the `PlanDefinition` it instantiates at the exact canonical URL and version, and the `ResearchSubject` that enrolls the subject.
Every Observation output references the study through the `workflow-researchStudy` extension.
A recording or clinical document names its studies in `DocumentReference.context.related` instead.
A `Subject.bundled` adds the `Patient` entry under the same scheme.

## The provenance

The conversion `Provenance` is an assertion about how this record came to exist.
Its lifecycle activity contains exactly one ISO 21089 `transform` coding and no Grove retraction lifecycle coding.
Its direct `meta.profile` claim contains exactly the one admitted HealthKit conversion profile; it does not repeat a generic conversion profile alongside it.
It records:

- every emitted output as a target;
- the converting application as the assembler and its host relationship;
- the typed `source-record` identifier as the source entity;
- the call's instant in `occurred` and `recorded`;
- the record version in its `grove-record-version` extension, which equals its entry key.

The source HealthKit UUID, the writer record and the unit token are framed HMAC inputs.
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
A node without an immutable business identity uses a typed content key, so the same content has the same fullUrl in every Bundle.
An exact retry therefore rebuilds identical references, and changed content is a new snapshot rather than a second body under one fullUrl.
A literal reference points to an output of its own record or to a shared node of the same Bundle.
No literal reference reaches a lifecycle Provenance, not even the record's own, in an active or a retraction Bundle.

## Equality and retries

Two records are the same version when their `ExchangeRecord.version` is equal.
The version is keyed, so a receiver compares it and never recomputes it; `ExchangeRecord.verifyVersion(in:)` recomputes it for a holder of the key.
It covers the canonical JSON tokens of the Provenance and the outputs, so member order, whitespace and string escaping do not matter, while a decimal lexeme is kept as text: `72` and `72.0` are different content.
Equal fullUrls state equal tokens, which `ExchangeBundlePacker` checks when it dedupes a shared node.

## Retractions

A retraction is a record of its own, which ``HealthKitFHIRExporter/retract(_:at:receive:)`` exports for a deleted sample and which travels in a Bundle of retractions, never beside active records.
Its Provenance uses exactly one Grove `source-record-retracted` lifecycle coding, and its one target is the `source-record` identifier its entity names.
It is not an HTTP delete instruction.

It addresses the whole source record: a receiver suppresses every output of every version of that record, one only an earlier conversion emitted included, so a retraction restates no output list from the current catalog.
Its entry key is a function of the source record alone, it carries no `grove-record-version`, and the first accepted wins, so a re-reported deletion with other bounds is a duplicate.
A disclosed native record identifier rides beside the target in the Grove retraction native-identifier extension; it never addresses the target.

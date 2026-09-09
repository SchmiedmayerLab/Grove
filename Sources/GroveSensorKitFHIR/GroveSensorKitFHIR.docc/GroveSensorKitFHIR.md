# ``GroveSensorKitFHIR``

<!--
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
-->

Convert already-fetched SensorKit records into deterministic, conformant FHIR R4 graphs.

## Overview

``SensorKitConverter`` accepts explicit typed records and returns a complete
``SensorKitConversion``. It never queries SensorKit. Every graph uses stable
business identifiers, deterministic `urn:uuid` entry URLs, explicit Device roles, and
conversion Provenance. `Resource.id` remains absent unless the caller supplies a
repository-assigned id.

The structured Grove FHIR mappings are rotation-rate SampledData, a hybrid ECG waveform plus
its linked native recording, on-wrist state, device-usage summary plus its linked native
recording, and visit summary. Other catalog-admitted Grove SensorKit streams use an exact
native RecordingDocument. ``SensorKitCatalog`` is generated from the IG and records
implemented, deferred, and unavailable platform streams without claiming unsupported
structure.

On iOS, typed initializers map Grove's already-fetched safe representations into these
records. The caller still owns source identity and supplies exact native evidence where a
hybrid or raw graph requires it. No initializer performs fetching.

Opaque native bytes can carry identifying or sensitive provider content. Creating
``SensorKitNativeRecording`` therefore requires one explicit
``SensorRawPayloadAdmission``: caller-authorized opaque disclosure or verified
sanitized input. Grove does not inspect or sanitize those bytes, and the admission choice
is never serialized.

### Configure one conversion event

The context contains the complete identity and audit inputs for one source record/version. The
subject and each research study are identifier-only logical references; literal references such as
`Patient/123` would dangle because the exchange Bundle does not contain those caller-owned
resources. Persist the context before conversion and reuse it unchanged for an exact retry.

```swift
let context = SensorKitConversionContext(
    subject: patientReference,
    subjectIdentity: patientIdentity,
    converter: SensorApplication(
        sourceDeviceToken: "org.example.study",
        name: "Example Study",
        version: "1.0.0",
        build: "42"
    ),
    converterHost: SensorHostDevice(
        sourceDeviceToken: persistedHostToken,
        operatingSystemVersion: persistedOSVersion
    ),
    eventIdentifier: persistedEventIdentifier,
    entryNodeIdentifierSystem: entryNodeSystem,
    identityScope: deploymentIdentityScope,
    repositoryScope: sensorKitRepository,
    visitLocationIdentifierSystem: visitLocationSystem,
    sourceTimeZone: persistedSourceTimeZone,
    conversionInstant: persistedConversionInstant
)
let conversion = try SensorKitConverter().convert(record, context: context)
try persist(conversion.bundle)
```

``SensorKitConversion/bundle`` is the authoritative exchange unit. Persist and upload the complete
Bundle, not only ``SensorKitConversion/recordingDocument`` or an individual Observation; the
Bundle also carries the Device snapshots, identities, references, and conversion Provenance needed
to interpret and validate the result.

### Identify and acknowledge anchored batches

``SensorKitSourceRecordID`` preserves acquisition multiplicity. Derive it from the anchored batch's
persisted coordinate, sensor and device partitions, and the sample's zero-based ordinal. Do not
derive it from payload bytes: two byte-identical records acquired at different coordinates are two
records. Persist a digest of the source fields and native bytes beside the record; an exact retry
must reproduce that digest before it may reuse the identifier.

```swift
for try await batch in sensorKit.fetchAnchored(sensor) {
    for (ordinal, sample) in batch.samples.enumerated() {
        let recordID = SensorKitSourceRecordID.derived(
            acquisitionBatch: batch.info.acquisitionBatch,
            sourceToken: sourceToken,
            deviceProductType: batch.info.device.productType,
            recordOrdinal: UInt64(ordinal)
        )
        let sourceDigest = try digestCanonicalSource(sample)
        try verifyRetryOrPersist(recordID, sourceDigest)

        let record = try makeRecord(sample, sourceRecordID: recordID)
        let conversion = try SensorKitConverter().convert(
            record,
            context: try persistedContext(for: recordID)
        )
        try persist(conversion.bundle)
    }

    // Advance the query cursor only after every retry-critical value and Bundle is durable.
    try await batch.acknowledge()
}
```

An unacknowledged batch is reissued after restart. Asking for another batch first fails closed, as
does acknowledging twice or acknowledging after the cursor has changed or been reset.

### Declare native recording bytes

The registered format determines the media types that the payload is allowed to use. Formats with
one representation derive their media type automatically:

```swift
let recording = try SensorKitNativeRecording(
    title: "Accelerometer recording",
    format: .triaxialAccelerationSamples,
    payload: .sidecar(path: relativePath, bytes: csvData),
    admission: .callerAuthorizedOpaquePayload
)
recording.contentType // "text/csv", derived from the format registry
```

Some registry formats admit more than one exact media type. A producer can use such a format only
when its generated adapter row admits that format, and it must then supply one of the registered
media types explicitly. Construction rejects an unregistered media type and does not infer a FHIR
release from payload bytes.

Use the typed SensorKit records for structured measurements. If the source payload already is a
complete R4 `collection` Bundle with a timestamp, nonempty entries, unique full URLs, and no request
or response elements, declare the registry's `fhir-collection-bundle` format; its initializer
validates that envelope before conversion. A JSON array of resources is not a FHIR resource and is
not a registered recording format.

## The source-neutral producer

``SensorConverter`` is the same exchange contract without SensorKit: it converts
``SensorRecord`` values a caller assembles from any sensor source into the identical graph shape,
and imports no Apple sensor framework. It lives in this module because it shares the module's
records, identity minting, resource builders, and recording readers and writers; splitting it out
would duplicate all of them.

Its records carry the payload directly — sampled data, an electrocardiogram, or a recording
document — and ``SensorConversionContext`` states the adapter token that the SensorKit context
fixes to `sensorkit`. Everything else — persisted event identity, deterministic entry URLs, device
snapshots, conversion Provenance, retraction identity — behaves exactly as documented above.

## Topics

### Conversion

- ``SensorKitConverter``
- ``SensorKitConversionContext``
- ``SensorKitConversion``
- ``SensorKitRecord``
- ``SensorKitSourceRecordID``
- ``SensorKitNativeRecording``
- ``SensorRawPayloadAdmission``

### Source-neutral conversion

- ``SensorConverter``
- ``SensorConversionContext``
- ``SensorConversion``
- ``SensorRecord``
- ``SensorApplication``
- ``SensorHostDevice``
- ``SensorRecordingDevice``
- ``SensorRecordingDocument``
- ``SensorSampledDataRecord``
- ``SensorECGRecord``
- ``SensorCode``
- ``SensorRecordError``

### Recording payloads

- ``RecordingCSVReader``
- ``RecordingBinaryReader``
- ``RecordingBinaryWriter``
- ``SensorKitPPGRecording``

### Authoritative catalog

- ``SensorKitCatalog``
- ``SensorKitCatalogEntry``

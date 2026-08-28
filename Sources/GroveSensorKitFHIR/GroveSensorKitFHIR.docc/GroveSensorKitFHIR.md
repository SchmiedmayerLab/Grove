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

The structured Grove FHIR 0.6.0 mappings are rotation-rate SampledData, a hybrid ECG waveform plus
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

## Topics

### Conversion

- ``SensorKitConverter``
- ``SensorKitConversionContext``
- ``SensorKitConversion``
- ``SensorKitRecord``
- ``SensorKitSourceRecordID``
- ``SensorKitNativeRecording``
- ``SensorRawPayloadAdmission``

### Authoritative catalog

- ``SensorKitCatalog``
- ``SensorKitCatalogEntry``

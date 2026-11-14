# ``GroveProviderFHIR``

<!--
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
-->

Convert typed provider records into immutable FHIR exchange records.

## Overview

Withings, Oura and Google Health inputs use the shared Grove identity, Device and conversion Provenance infrastructure. The converters accept source values and timestamps; the application handles provider authorization, acquisition, pagination and durable custody.

``ProviderCapabilities`` describes conversion support for exact provider source tokens and the semantic profiles each source element can produce. It does not establish consent or qualify a provider connection. Select authorized source elements before conversion, and preserve the source token when recording each output's permissions.

## Identity and retries

``ProviderConversionContext`` supplies a stable identity scope, participant, application, source time zone and persisted conversion instant. Withings and Google Health records use an account scope; Oura documents use their global document scope. Keep the scope and native record identifier stable across reconnects and retries. A new retrieval time must not replace a measurement's source time or an existing conversion instant.

Stage each returned exchange record's exact bytes before advancing the acquisition checkpoint. A result without a record includes an explicit omission. Missing evidence, conflicting definitions and unimplemented conversions require resolution; they are not permission to discard a source record or advance past it.

## Structured values

The converters preserve source units through checked decimal scaling, complete session intervals and civil-day boundaries in the source time zone. They do not substitute retrieval time for missing source timestamps. Blood pressure requires both components from the same Withings group. Oura sleep duration, minimum heart rate and mean respiratory rate remain distinct outputs with their own clinical mappings. Oura activity totals span 04:00 on the named source date to 04:00 on the next date in the evidenced source zone. Its equivalent walking distance uses a separate provider measurement because it expresses an energy estimate rather than measured travel.

Every structured output directly claims its semantic profile and concrete provider Observation profile. The conversion Provenance targets every emitted output. Provider availability is not inferred, so these Observations omit `issued`.

## Source applications

``ProviderConversionContext/sourceApplication`` names the upstream application that wrote the source record. Supply its exact business identifiers in their documented namespaces and only the name, version and build the source actually reports. Grove emits an independent application Device snapshot and references it as the author on the source entity of conversion Provenance. The converting application remains the assembler.

A missing source application name is represented as unknown on the required FHIR name primitive. The writer states no inferred host, release or lifecycle status. Its identifier order is canonical, so the same source facts produce the same snapshot and retry bytes.

## Native recording files

``ProviderNativeRecording`` accepts an immutable recording file for the four admitted native streams: Google Health heart rate, Oura heart rate, and Withings activity and sleep intraday data. The caller explicitly asserts payload admission and supplies a relative attachment path. The converter emits a DocumentReference with the source checksum and byte count; it preserves the JSON bytes without inventing a uniform sampling period.

JSON grammar validation reads the bounded payload into memory, with a hard ceiling of 64 MiB and a caller-selectable lower limit. Perform this synchronous file work off the main actor. File staging and transfer compression use Grove's shared streaming recording APIs. Compressing a transfer does not change the source checksum, artifact identity or retained payload.

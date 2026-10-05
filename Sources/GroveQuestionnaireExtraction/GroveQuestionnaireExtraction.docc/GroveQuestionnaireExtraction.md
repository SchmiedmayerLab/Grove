# ``GroveQuestionnaireExtraction``

<!--
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
-->

Turn answered questionnaires into the Grove exchange bundles their instruments declare.

## Overview

An instrument that measures something says so itself: an item marked with the SDC `observationExtract` extension and carrying its measurement code declares that its answer is a measurement, not merely a survey response.
This target reads exactly those declarations and nothing else — an unmarked item never projects, and a marked item whose answer contradicts its measurement contract refuses rather than guessing.

The one public product is the complete Grove exchange graph, which ``QuestionnaireFHIRExporter`` exports per response: the Patient, the study context when the participant is enrolled, the carried response, the writer's application and host device snapshots, one profiled Observation per measurement, and the conversion Provenance, all under minted pseudonymous identities.
Its events are numbered by the same `ExchangeProducer` the HealthKit and SensorKit exporters use, so whoever exports holds the producer, whether that is a server receiving responses or an app converting its own.
``QuestionnaireFHIRExporter/retract(_:at:receive:)`` takes a withdrawn response's Observations back.

## What a response needs to export

A response exports only when all three of these hold; otherwise the export refuses it with an ``ObservationExtractionError`` and goes on with the others:

- **Something to extract.** The response answers at least one item its instrument marks for extraction. A response that answers none, or an instrument that marks nothing, refuses with ``ObservationExtractionError/noExtractableMeasurements``: an exchange event carries at least one output, and a graph of the response alone is not supported.
- **The writer context.** The app that authored the response stamped its writer context with `QuestionnaireResponse.apply(writerContext:)` when the response was authored, since the graph's application and host snapshots state that writer; without it the response refuses with ``ObservationExtractionError/writerContextMissing``.
- **The subject as author and source.** The response's `author` and `source`, where stated, are its subject. A response authored or supplied by anyone else, such as a caregiver, refuses with ``ObservationExtractionError/authorIsNotTheSubject`` or ``ObservationExtractionError/sourceIsNotTheSubject``: the guide states such an author as the Observations' performer, which this target does not support yet.

The response must also be `completed` or `amended`, and state its business identifier, its authored time and its instrument's versioned canonical; ``ObservationExtractionError`` names each refusal.

<doc:ExtractingObservations> walks through the markings, the export, and what consumers do with the bundle.

## Topics

### Essentials

- <doc:ExtractingObservations>

### Export

- ``QuestionnaireFHIRExporter``

### Writer Context

- ``QuestionnaireWriterContext``
- ``QuestionnaireWriterContextError``

### Identity

- ``QuestionnaireCanonicalIdentity``

### Refusals

- ``ObservationExtractionError``

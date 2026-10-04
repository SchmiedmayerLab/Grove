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

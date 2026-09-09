# ``GroveStudyDefinition``

<!--

This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT
       
-->

Definitions for reusable studies

## Overview

The GroveStudyDefinition module implements the ``StudyBundle`` type, which is used to create reusable study definitions.

See the ``StudyBundle`` documentation for more information.

## Localized Questionnaires

`StudyBundle` validates that localized Questionnaire resources preserve the same structural and
measurement semantics. The current StudyDefinition presentation supports fixed-unit quantity items:
each localization must declare exactly one `questionnaire-unitOption` with the same coding system and
code. This is a StudyDefinition presentation constraint; GroveQuestionnaire continues to support the
complete unit-selection model defined by the Grove FHIR Implementation Guides.

SDC `minQuantity` and `maxQuantity` extensions are optional. When present, their value, system, and
code must remain identical across localizations. The human-facing `Quantity.unit` text may be localized.

## Topics
- ``StudyBundle``
- ``StudyDefinition``
- <doc:StudyEvolution>

### Supporting Types
- ``TimedWalkingTestConfiguration``

### Other
- ``UniformTypeIdentifiers/UTType/studyBundle``

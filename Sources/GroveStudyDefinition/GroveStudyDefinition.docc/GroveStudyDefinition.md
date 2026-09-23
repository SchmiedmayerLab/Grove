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

A questionnaire is authored as one Questionnaire file per locale, such as `Survey+en-US.json` and `Survey+es-US.json`.
The files must share one `url`, `version` and structure, and each names its own `language`.
Once the bundle validates, ``StudyBundle/writeToDisk(at:definition:files:)`` merges them into one multilingual Questionnaire: the `en-US` file is the base, and every other file's text becomes a `translation` extension on the base text.
The files are compared element by element: a presentation string that differs, such as a title, an item's text, a display or a unit's text, becomes a translation.
Any other difference is data, such as a code, a system, a value or a `valueString` answer option, and fails validation instead of merging.
``StudyBundle/questionnaire(for:)`` returns that merged resource, merging on load a bundle that still carries per-locale files, and the renderer picks the language to show.
Articles, consent documents and other files stay per locale.

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

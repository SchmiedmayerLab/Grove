# ``GroveFHIR``

<!--

This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

Work with FHIR resources in a Grove application.

## Overview

Wraps the version-specific resource types from FHIRModels behind one value, ``FHIRResource``, so app
code can hold a DSTU2 and an R4 resource in the same collection and ask the same questions of both.

GroveFHIR requires the package's `DSTU2` trait, which is off by default; without it, the module is empty.
Swift keeps every linked module's types in the binary, used or not, so an app that never handles a DSTU2 resource
leaves the trait off to keep FHIRModels' `ModelsDSTU2` out of its binary.

``FHIRStore`` keeps the resources an app has loaded, grouped by ``FHIRResource/FHIRResourceCategory`` so a view can
show observations, conditions or medications without filtering by type itself.

## Topics

### Resources

- ``FHIRResource``
- ``FHIRResource/VersionedFHIRResource``
- ``FHIRResource/FHIRResourceCategory``

### Storing Resources

- ``FHIRStore``

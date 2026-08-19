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

Convert supported SensorKit samples into conformant FHIR R4 observations.

## Overview

`GroveSensorKitFHIR` maps on-wrist state, visits, and device-usage reports to
`ModelsR4.Observation` resources. Stable sample identifiers make repeated exports
idempotent, and contained sensor-device metadata records where each measurement came
from.

Conform a supported sample to ``SensorKitObservationConvertible`` to convert it, or use
``SensorBatchArchive`` to write newline-delimited FHIR for batch upload. The emitted
resources are validated in CI against Grove's published SensorKit implementation guide.

## Topics

### Conversion

- ``SensorKitObservationConvertible``
- ``SensorKitSampleIDHasher``

### Batch Export

- ``SensorBatchArchive``
- ``SensorBatchDocument``

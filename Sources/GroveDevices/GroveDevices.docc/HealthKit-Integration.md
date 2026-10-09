# HealthKit Integration

Convert Bluetooth measurement types to HealthKit samples.

<!--

This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

## Overview

GroveDevices helps developers converting measurements received from Bluetooth devices to HealthKit sample types.

### Device Information

As soon as you conform your [GroveBluetooth `BluetoothDevice`](../../GroveBluetooth/GroveBluetooth.docc/GroveBluetooth.md)
to the ``HealthDevice`` protocol and implement the [`DeviceInformationService`](../../GroveBluetoothServices/BluetoothServices.docc/BluetoothServices.md),
you can access the [`HKDevice`](https://developer.apple.com/documentation/healthkit/hkdevice)
description using the ``HealthDevice/hkDevice`` property

### Converting Measurements

GroveDevices can convert your Bluetooth Health Measurement characteristics into HealthKit samples.
This is support for characteristics like [`BloodPressureMeasurement`](../../GroveBluetoothServices/BluetoothServices.docc/BluetoothServices.md)
or [`WeightMeasurement`](../../GroveBluetoothServices/BluetoothServices.docc/BluetoothServices.md).

Use methods like ``GroveBluetoothServices/BloodPressureMeasurement/bloodPressureSample(source:)`` or
``GroveBluetoothServices/WeightMeasurement/weightSample(source:resolution:)`` to convert these measurements to their respective HealthKit Sample
representation.

> Tip: After producing an `HKSample`, pass it to the profile-aware
    [`HealthKitFHIRExporter`](../../GroveHealthKitFHIR/GroveHealthKitFHIR.docc/GroveHealthKitFHIR.md).
    For a supported sample type it delivers a complete HL7 FHIR R4 collection graph with Observation,
    Device, and Provenance resources; a sample it cannot export is refused with a typed error.
    [The Exchange Graph](../../GroveHealthKitFHIR/GroveHealthKitFHIR.docc/TheExchangeGraph.md)
    shows what those resources look like.
    The measuring device becomes a recording Device only when the exporter can name the physical unit:
    the ``HealthDevice/hkDevice`` this module builds states no `localIdentifier`, so under the exporter's
    default recording-device policy the graph omits that Device and the export reports the
    `mobile-omission.recording-device` warning. When your device has a stable per-unit token, name it
    through a `RecordingDeviceResolver` passed as the exporter's `.custom` recording-device policy.

## Topics

### Device

- ``HealthDevice/hkDevice``

### Blood Pressure Measurement

- ``GroveBluetoothServices/BloodPressureMeasurement/Unit/hkUnit``
- ``GroveBluetoothServices/BloodPressureMeasurement/bloodPressureSample(source:)``
- ``GroveBluetoothServices/BloodPressureMeasurement/heartRateSample(source:)``

### Weight Measurement

- ``GroveBluetoothServices/WeightMeasurement/Unit/massUnit``
- ``GroveBluetoothServices/WeightMeasurement/Unit/lengthUnit``
- ``GroveBluetoothServices/WeightMeasurement/weightSample(source:resolution:)``
- ``GroveBluetoothServices/WeightMeasurement/bmiSample(source:)``
- ``GroveBluetoothServices/WeightMeasurement/heightSample(source:resolution:)``

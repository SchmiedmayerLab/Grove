# HealthKit Integration

Convert Bluetooth measurement types to HealthKit samples.

<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

## Overview

SpeziDevices helps developers converting measurements received from Bluetooth devices to HealthKit sample types.

### Device Information

As soon as you conform your [SpeziBluetooth `BluetoothDevice`](../../SpeziBluetooth/SpeziBluetooth.docc/SpeziBluetooth.md)
to the ``HealthDevice`` protocol and implement the [`DeviceInformationService`](../../SpeziBluetoothServices/BluetoothServices.docc/BluetoothServices.md),
you can access the [`HKDevice`](https://developer.apple.com/documentation/healthkit/hkdevice)
description using the ``HealthDevice/hkDevice-32s1d`` property

### Converting Measurements

SpeziDevices can convert your Bluetooth Health Measurement characteristics into HealthKit samples.
This is support for characteristics like [`BloodPressureMeasurement`](../../SpeziBluetoothServices/BluetoothServices.docc/BluetoothServices.md)
or [`WeightMeasurement`](../../SpeziBluetoothServices/BluetoothServices.docc/BluetoothServices.md).

Use methods like ``SpeziBluetoothServices/BloodPressureMeasurement/bloodPressureSample(source:)`` or
``SpeziBluetoothServices/WeightMeasurement/weightSample(source:resolution:)`` to convert these measurements to their respective HealthKit Sample
representation.

> Tip: By using the [`resource`](../../SpeziHealthKitFHIR/SpeziHealthKitFHIR.docc/SpeziHealthKitFHIR.md)
    provided through [`SpeziHealthKitFHIR`](../../SpeziHealthKitFHIR/SpeziHealthKitFHIR.docc/SpeziHealthKitFHIR.md) you can convert
    your Bluetooth measurements to [HL7 FHIR Observation Resources](http://hl7.org/fhir/R4/observation.html).

## Topics

### Device

- ``HealthDevice/hkDevice-32s1d``

### Blood Pressure Measurement

- ``SpeziBluetoothServices/BloodPressureMeasurement/Unit/hkUnit``
- ``SpeziBluetoothServices/BloodPressureMeasurement/bloodPressureSample(source:)``
- ``SpeziBluetoothServices/BloodPressureMeasurement/heartRateSample(source:)``

### Weight Measurement

- ``SpeziBluetoothServices/WeightMeasurement/Unit/massUnit``
- ``SpeziBluetoothServices/WeightMeasurement/Unit/lengthUnit``
- ``SpeziBluetoothServices/WeightMeasurement/weightSample(source:resolution:)``
- ``SpeziBluetoothServices/WeightMeasurement/bmiSample(source:)``
- ``SpeziBluetoothServices/WeightMeasurement/heightSample(source:resolution:)``

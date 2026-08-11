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
description using the ``HealthDevice/hkDevice-32s1d`` property

### Converting Measurements

GroveDevices can convert your Bluetooth Health Measurement characteristics into HealthKit samples.
This is support for characteristics like [`BloodPressureMeasurement`](../../GroveBluetoothServices/BluetoothServices.docc/BluetoothServices.md)
or [`WeightMeasurement`](../../GroveBluetoothServices/BluetoothServices.docc/BluetoothServices.md).

Use methods like ``GroveBluetoothServices/BloodPressureMeasurement/bloodPressureSample(source:)`` or
``GroveBluetoothServices/WeightMeasurement/weightSample(source:resolution:)`` to convert these measurements to their respective HealthKit Sample
representation.

> Tip: By using the [`resource`](../../HealthKitOnFHIR/HealthKitOnFHIR.docc/HealthKitOnFHIR.md)
    provided through [`HealthKitOnFHIR`](../../HealthKitOnFHIR/HealthKitOnFHIR.docc/HealthKitOnFHIR.md) you can convert
    your Bluetooth measurements to [HL7 FHIR Observation Resources](http://hl7.org/fhir/R4/observation.html).

## Topics

### Device

- ``HealthDevice/hkDevice-32s1d``

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

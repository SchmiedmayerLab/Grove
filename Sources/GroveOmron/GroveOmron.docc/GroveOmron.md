# ``GroveOmron``

Support interactions with Omron Bluetooth Devices.

<!--
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
-->

## Overview

GroveOmron extends GroveDevices with support for Omron devices. This includes Omron-specific models, characteristics, services and fully reusable
device support.

### Omron Devices

The ``OmronBloodPressureCuff`` and ``OmronWeightScale``
devices provide reusable device implementations for Omron blood pressure cuffs
and the Omron weight scales respectively.
Both devices automatically integrate with the [`HealthMeasurements`](../../GroveDevices/GroveDevices.docc/GroveDevices.md)
and [`PairedDevices`](../../GroveDevices/GroveDevices.docc/GroveDevices.md) modules of GroveDevices.
You just need to configure them for use with the [`Bluetooth`](../../GroveBluetooth/GroveBluetooth.docc/GroveBluetooth.md#Configure-the-Bluetooth-Module)
module.

```swift
import GroveBluetooth
import GroveBluetoothServices
import GroveDevices
import GroveOmron

class ExampleAppDelegate: GroveAppDelegate {
    override var configuration: Configuration {
        Configuration {
            Bluetooth {
                Discover(OmronBloodPressureCuff.self, by: .advertisedService(BloodPressureService.self))
                Discover(OmronWeightScale.self, by: .advertisedService(WeightScaleService.self))
            }

            // If required, configure the PairedDevices and HealthMeasurements modules
            PairedDevices()
            HealthMeasurements()
        }
    }
}
```

## Topics

### Omron Devices

- ``OmronBloodPressureCuff``
- ``OmronWeightScale``
- <doc:OmronReverseEngineering>

### Omron Device

- ``OmronHealthDevice``
- ``OmronModel``
- ``OmronManufacturerData``
- ``GroveBluetooth/ManufacturerIdentifier/omronHealthcareCoLtd``

### Omron Services

- ``OmronOptionService``

### Omron Record Access

- ``GroveBluetooth/CharacteristicAccessor/reportStoredRecords(_:)``
- ``GroveBluetooth/CharacteristicAccessor/reportNumberOfStoredRecords(_:)``
- ``GroveBluetooth/CharacteristicAccessor/reportSequenceNumberOfLatestRecords()``
- ``OmronRecordAccessOperand``

# Reverse Engineering Omron Devices

Collects knowledge acquired when reverse engineering Omron Health devices.

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

This article collects some knowledge acquired reverse engineering Omron devices when developing GroveDevices.

### Discovery

Omron devices are discovery by searching for their primary advertised service (e.g.,
[`WeightScaleService`])../../GroveBluetoothServices/BluetoothServices.docc/BluetoothServices.md) or
[`BloodPressureService`](../../GroveBluetoothServices/BluetoothServices.docc/BluetoothServices.md)).
A Omron device is either advertising in pairing mode (if you press the Bluetooth/Connection button for 3s) or in transfer mode
(after taking a measurement or when pressing the Bluetooth/Connection button quickly).

> Note: If a Omron device wasn't paired you cannot enter transfer mode. Meaning pressing the Bluetooth/Connection button once doesn't do anything.

If the Omron device advertising pairing mode vs. transfer mode, depends on the the device model. It uses one of these two methods:
* Using the ``OmronManufacturerData/pairingMode-swift.property`` bit field of the ``OmronManufacturerData`` which is part of the advertisement data.
    Not all Omron devices include [`manufacturerData`](../../GroveBluetooth/GroveBluetooth.docc/GroveBluetooth.md)
    in their advertisement. In this cases use the other approach.
* Deriving the pairing mode from the [`localName`](../../GroveBluetooth/GroveBluetooth.docc/GroveBluetooth.md).
    For more information see ``OmronLocalName``.

> Tip: The name of the peripheral represents the model identifier. This can be useful to better visualize a Omron device to the user.

### Time Synchronization

Most Omron devices expose a [`CurrentTimeService`](../../GroveBluetoothServices/BluetoothServices.docc/BluetoothServices.md)
to support timestamps in reported measurements.
The device expects to receive updated time information when you receive the initial [`currentTime`](../../GroveBluetoothServices/BluetoothServices.docc/BluetoothServices.md)
notification after establishing a connection.

### Pairing

While you can initiate pairing with a device that is advertising in transfer mode, it makes sense to filter for nearby devices in pairing mode
to avoid accidental connections.

Omron application considers an application paired when the device disconnects and any success-indicating condition is fulfilled.
Such conditions are the following events if they happen once the device is fully connected (fully discovered and **subscribed to all relevant characteristics**):
* A [`currentTime`](../../GroveBluetoothServices/BluetoothServices.docc/BluetoothServices.md) notification was received
    (make sure you comply with <doc:#Time-Synchronization> requirements).
* A [`batteryLevel`](../../GroveBluetoothServices/BluetoothServices.docc/BluetoothServices.md) notification was received.

- Tip: GroveDevices improves pairing speed by not waiting for a disconnect to check these conditions, but notifying the [`PairedDevices`](../../GroveDevices/GroveDevices.docc/GroveDevices.md)
module as soon as these conditions are fulfilled, leading to a better user experience.

### Transfer

A Omron device will automatically indicate the measurement characteristic with new measurements once it is connected to the paired device.

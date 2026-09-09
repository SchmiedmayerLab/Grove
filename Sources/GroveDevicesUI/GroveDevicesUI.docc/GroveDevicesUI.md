# ``GroveDevicesUI``

Visualize Bluetooth device interactions.

<!--

This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

## Overview

GroveDevicesUI provides the views to pair Bluetooth devices, manage them once paired, and confirm the measurements they send.

@Row {
    @Column {
        @Image(source: "PairedDevices", alt: "The Devices screen showing a paired weight scale and two blood pressure cuffs as tiles with their battery level.") {
            ``DevicesView`` lists paired devices as tiles with their name and battery level.
        }
    }
    @Column {
        @Image(source: "Pairing", alt: "The Pair Accessory sheet asking whether to pair a nearby blood pressure cuff with the app.") {
            The ``AccessorySetupSheet`` asks to confirm pairing once a device is discovered nearby.
        }
    }
    @Column {
        @Image(source: "DeviceDetails", alt: "The Device Details screen of a paired blood pressure cuff with its name, battery level, and a Forget This Device button.") {
            ``DeviceDetailsView`` shows name, model, and battery, and lets the user rename or forget the device.
        }
    }
    @Column {
        @Image(source: "MeasurementRecorded", alt: "The Measurement Recorded sheet showing a blood pressure reading of 103/64 mmHg and 62 BPM with Save and Discard buttons.") {
            The ``MeasurementsRecordedSheet`` lets the user save or discard a reading a device just sent.
        }
    }
}

### Displaying paired devices

When managing paired devices using [`PairedDevices`](../../GroveDevices/GroveDevices.docc/GroveDevices.md),
GroveDevicesUI provides reusable View components to display paired devices.

The ``DevicesView`` provides everything you need to pair and manage paired devices.
It shows already paired devices in a grid layout using the ``DevicesGrid``. Additionally, it places an add button in the toolbar
to discover new devices using the ``AccessorySetupSheet`` view.

```swift
struct MyHomeView: View {
    var body: some View {
        TabView {
            NavigationStack {
                DevicesView(appName: "Example") {
                    Text("Provide helpful pairing instructions to the user.")
                }
            }
                .tabItem {
                    Label("Devices", systemImage: "sensor.fill")
                }
        }
    }
}
```

### Displaying Measurements

When managing measurements using [`HealthMeasurements`](../../GroveDevices/GroveDevices.docc/GroveDevices.md),
present pending measurements with the ``MeasurementsRecordedSheet``.

```swift
struct MyHomeView: View {
    @Environment(HealthMeasurements.self) private var measurements

    var body: some View {
        @Bindable var measurements = measurements
        ContentView()
            .sheet(isPresented: $measurements.shouldPresentMeasurements) {
                MeasurementsRecordedSheet { samples in
                    // save the array of HKSamples
                }
            }
    }
}
```

> Important: Don't forget to configure the `HealthMeasurements` module in
    your [`GroveAppDelegate`](../../Grove/Grove.docc/Grove.md).

## Topics

### Presenting nearby devices

Views that are helpful when building a nearby devices view.

- ``BluetoothUnavailableView``
- ``NearbyDeviceRow``
- ``LoadingSectionHeader``
- ``PeripheralLabel``
- ``PeripheralSecondaryLabel``

### Pairing Devices

- ``AccessorySetupSheet``

### Paired Devices

- ``DevicesView``
- ``DevicesGrid``
- ``DeviceTile``
- ``DeviceDetailsView``
- ``BatteryIcon``

### Measurements

- ``MeasurementsRecordedSheet``

# ``GroveDevicesUI``

Visualize Bluetooth device interactions.

<!--

This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

## Overview

GroveDevicesUI helps you to visualize Bluetooth device state and communicate interactions to the user.

@Row {
    @Column {
        @Image(source: "PairedDevices", alt: "Screenshot showing paired devices in a grid layout. A sheet is presented in the foreground showing a nearby devices able to pair.") {
            Display paired in a grid-layout devices using ``DevicesView``.
        }
    }
    @Column {
        @Image(source: "DeviceDetails", alt: "Displaying the device details of a paired device with information like Model number and battery percentage.") {
            Display device details using ``DeviceDetailsView``.
        }
    }
    @Column {
        @Image(source: "MeasurementRecorded_BloodPressure", alt: "Showing a newly recorded blood pressure measurement.") {
            Display recorded measurements using ``MeasurementsRecordedSheet``.
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
you can use the [`MeasurementsRecordedSheet`](GroveDevicesUI.md)
to display pending measurements.
Below is a short code example on how you would configure this view.

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

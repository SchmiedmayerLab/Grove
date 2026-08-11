<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

# SpeziDevices


Support interactions with Bluetooth Devices.

## Overview

SpeziDevices provides three different targets: `SpeziDevices`,
`SpeziDevicesUI`
and `SpeziOmron`.

|![Screenshot showing paired devices in a grid layout. A sheet is presented in the foreground showing a nearby devices able to pair.](../SpeziDevicesUI/SpeziDevicesUI.docc/Resources/PairedDevices.png#gh-light-mode-only) ![Screenshot showing paired devices in a grid layout. A sheet is presented in the foreground showing a nearby devices able to pair.](../SpeziDevicesUI/SpeziDevicesUI.docc/Resources/PairedDevices~dark.png#gh-dark-mode-only)|![Displaying the device details of a paired device with information like Model number and battery percentage.](../SpeziDevicesUI/SpeziDevicesUI.docc/Resources/DeviceDetails.png#gh-light-mode-only) ![Displaying the device details of a paired device with information like Model number and battery percentage.](../SpeziDevicesUI/SpeziDevicesUI.docc/Resources/DeviceDetails~dark.png#gh-dark-mode-only)| ![Showing a newly recorded blood pressure measurement.](../SpeziDevicesUI/SpeziDevicesUI.docc/Resources/MeasurementRecorded_BloodPressure.png#gh-light-mode-only) ![Showing a newly recorded blood pressure measurement.](../SpeziDevicesUI/SpeziDevicesUI.docc/Resources/MeasurementRecorded_BloodPressure~dark.png#gh-dark-mode-only) |
|:--:|:--:|:--:|
|Display paired in a grid-layout devices using `DevicesView`.|Display device details using `DeviceDetailsView`.|Display recorded measurements using `MeasurementsRecordedSheet`.|

### SpeziDevices

SpeziDevices abstracts common interactions with Bluetooth devices that are implemented using
SpeziBluetooth.
It supports pairing with devices and process health measurements.

#### Pairing Devices

Pairing devices is a good way of making sure that your application only connects to fixed set of devices and doesn't accept data from
non-authorized devices.
Further, it might be necessary to ensure certain operations stay secure.

Use the `PairedDevices`
module to discover and pair `PairableDevice`s
and automatically manage connection establishment of connected devices.

To support `PairedDevices`, you need to adopt the
`PairableDevice` protocol for your device.
Optionally you can adopt the `BatteryPoweredDevice`
protocol, if your device supports the
`BatteryService`.
Once your device is loaded, register it with the `PairedDevices` module by calling the
`PairedDevices/configure(device:accessing:_:_:)`
method.


> [!IMPORTANT]
> Don't forget to configure the `PairedDevices` module in
  your `SpeziAppDelegate`.

```swift
import SpeziDevices

class MyDevice: PairableDevice {
    @DeviceState(\.id) var id
    @DeviceState(\.name) var name
    @DeviceState(\.state) var state
    @DeviceState(\.advertisementData) var advertisementData
    @DeviceState(\.nearby) var nearby

    @Service var deviceInformation = DeviceInformationService()

    @DeviceAction(\.connect) var connect
    @DeviceAction(\.disconnect) var disconnect

    var isInPairingMode: Bool {
        // determine if a nearby device is in pairing mode
    }

    @Dependency private var pairedDevices: PairedDevices?

    required init() {}

    func configure() {
        pairedDevices?.configure(device: self, accessing: $state, $advertisementData, $nearby)
    }

    func handleSuccessfulPairing() { // called on events where a device can be considered paired (e.g., incoming notifications)
        pairedDevices?.signalDevicePaired(self)
    }
}
```

> [!TIP]
> To display and manage paired devices and support adding new paired devices, you can use the full-featured
  `DevicesView`.

#### Health Measurements

Use the `HealthMeasurements`
module to collect health measurements from nearby Bluetooth devices like connected weight scales or
blood pressure cuffs.

To support `HealthMeasurements`, you need to adopt the `HealthDevice` protocol for your device.
One your device is loaded, register its measurement service with the `HealthMeasurements` module
by calling a suitable variant of `configureReceivingMeasurements(for:on:)`.

```swift
import SpeziDevices

class MyDevice: HealthDevice {
    @Service var deviceInformation = DeviceInformationService()
    @Service var weightScale = WeightScaleService()

    @Dependency private var measurements: HealthMeasurements?

    required init() {}

    func configure() {
        measurements?.configureReceivingMeasurements(for: self, on: weightScale)
    }
}
```

To display new measurements to the user and save them to your external data store, you can use
`MeasurementsRecordedSheet`.
Below is a short code example.

```swift
import SpeziDevices
import SpeziDevicesUI

struct MyHomeView: View {
    @Environment(HealthMeasurements.self) private var measurements

    var body: some View {
        @Bindable var measurements = measurements
        ContentView()
            .sheet(isPresented: $measurements.shouldPresentMeasurements) {
                MeasurementsRecordedSheet { measurement in
                    // handle saving the measurement
                }
            }
    }
}
```

> [!IMPORTANT]
> Don't forget to configure the `HealthMeasurements` module in
  your `SpeziAppDelegate`.

### SpeziDevicesUI

SpeziDevicesUI helps you to visualize Bluetooth device state and communicate interactions to the user.

#### Displaying paired devices

When managing paired devices using `PairedDevices`,
SpeziDevicesUI provides reusable View components to display paired devices.

The `DevicesView`
provides everything you need to pair and manage paired devices.
It shows already paired devices in a grid layout using the `DevicesGrid`.
Additionally, it places an add button in the toolbar to discover new devices using the
`AccessorySetupSheet` view.

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

#### Displaying Measurements

When managing measurements using `HealthMeasurements`,
you can use the `MeasurementsRecordedSheet`
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

> [!IMPORTANT]
> Don't forget to configure the `HealthMeasurements` module in
  your `SpeziAppDelegate`.

### SpeziOmron

SpeziOmron extends SpeziDevices with support for Omron devices. This includes Omron-specific models, characteristics, services and fully reusable
device support.

#### Omron Devices

The `OmronBloodPressureCuff`
and `OmronWeightScale`
devices provide reusable device implementations for Omron blood pressure cuffs
and the Omron weight scales respectively.
Both devices automatically integrate with the `HealthMeasurements`
and `PairedDevices` modules of SpeziDevices.
You just need to configure them for use with the `Bluetooth`
module.

```swift
import SpeziBluetooth
import SpeziBluetoothServices
import SpeziDevices
import SpeziOmron

class ExampleAppDelegate: SpeziAppDelegate {
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

## Setup

Add the Spezi monorepo package to your app and select the products you need, such as `SpeziDevices`, `SpeziDevicesUI`, or `SpeziOmron`.

In Xcode, select **File > Add Package Dependencies...**, enter:

```text
https://github.com/SchmiedmayerLab/Spezi.git
```

Choose **Up to Next Minor Version** and enter the latest tagged `0.x` release, for example `0.1.0`.

If you manage dependencies in a `Package.swift`, add the package dependency:

```swift
.package(url: "https://github.com/SchmiedmayerLab/Spezi.git", .upToNextMinor(from: "0.1.0"))
```

Then add the product dependency to the target that needs it:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "SpeziDevices", package: "Spezi"),
        .product(name: "SpeziDevicesUI", package: "Spezi"),
        .product(name: "SpeziOmron", package: "Spezi")
    ]
)
```

## License

This target is licensed under the MIT License. The local [LICENSES](LICENSES) directory records license information imported from the original upstream repository. See the monorepo [LICENSES](../../LICENSES) directory for license information covering current changes in this repository.


## Contributors

The local [CONTRIBUTORS.md](CONTRIBUTORS.md) file records contributors from the original upstream repository. See the monorepo [CONTRIBUTORS.md](../../CONTRIBUTORS.md) file for contributors to current changes in this repository.
